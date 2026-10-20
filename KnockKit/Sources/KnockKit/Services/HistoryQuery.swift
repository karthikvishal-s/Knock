import Foundation
import SwiftData

/// What the History screen is filtered by. Empty sets mean "any".
public struct HistoryFilter: Equatable, Sendable {
    public var searchText: String = ""
    public var kinds: Set<TransactionKind> = []
    public var categoryIDs: Set<UUID> = []
    public var accountIDs: Set<UUID> = []
    public var tagIDs: Set<UUID> = []
    /// Whole-day range, `[start, end)`.
    public var dateRange: Period?
    public var minAmount: Decimal?
    public var maxAmount: Decimal?

    public init() {}

    public var isActive: Bool { activeCount > 0 || !trimmedSearch.isEmpty }

    /// Number of filters set, excluding search (for the badge on the filter button).
    public var activeCount: Int {
        [!kinds.isEmpty, !categoryIDs.isEmpty, !accountIDs.isEmpty, !tagIDs.isEmpty, dateRange != nil, minAmount != nil || maxAmount != nil]
            .filter { $0 }.count
    }

    var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The search text as an amount in minor units, if it parses as a number ("250", "250.50").
    func searchAmountMinor(currencyCode: String) -> Int64? {
        let cleaned = trimmedSearch.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, cleaned == trimmedSearch.replacingOccurrences(of: ",", with: ""),
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return Money(amount: value, currencyCode: currencyCode).minorUnits
    }

    /// Filters that the SwiftData predicate doesn't express (relationships), applied in memory.
    public func matchesRelationships(_ entry: LedgerEntry) -> Bool {
        if !categoryIDs.isEmpty {
            guard let id = entry.category?.id, categoryIDs.contains(id) else { return false }
        }
        if !accountIDs.isEmpty {
            let ids = [entry.account?.id, entry.transferAccount?.id].compactMap { $0 }
            guard ids.contains(where: accountIDs.contains) else { return false }
        }
        if !tagIDs.isEmpty {
            guard (entry.tags ?? []).contains(where: { tagIDs.contains($0.id) }) else { return false }
        }
        return true
    }
}

/// One day of history with its net total.
public struct DaySection: Identifiable {
    public let dayKey: Int32
    public let date: Date
    public let entries: [LedgerEntry]
    public let totals: Totals

    public var id: Int32 { dayKey }
}

/// Pages through history one calendar month at a time (newest first), so each day's total is
/// always complete and 20k+ rows never load at once. Months with no matches are skipped.
public struct HistoryQuery {
    public let context: ModelContext
    public let calendar: Calendar
    public let currencyCode: String

    public init(context: ModelContext, calendar: Calendar = .autoupdatingCurrent, currencyCode: String = "INR") {
        self.context = context
        self.calendar = calendar
        self.currencyCode = currencyCode
    }

    public struct Page {
        public let sections: [DaySection]
        /// Pass as `before` to load the next (older) page; `nil` when history is exhausted.
        public let nextCursor: Date?
    }

    /// Loads the newest month with matches older than `before` (or the newest overall).
    public func page(before cursor: Date?, filter: HistoryFilter, minimumEntries: Int = 20) throws -> Page {
        var upperBound = min(cursor ?? .distantFuture, filter.dateRange?.end ?? .distantFuture)
        let lowerBound = filter.dateRange?.start ?? .distantPast
        var collected: [LedgerEntry] = []

        while collected.count < minimumEntries {
            guard let newest = try newestDate(before: upperBound, after: lowerBound, filter: filter) else {
                return Page(sections: group(collected), nextCursor: nil)
            }
            let monthStart = calendar.dateInterval(of: .month, for: newest)?.start ?? calendar.startOfDay(for: newest)
            let windowStart = max(monthStart, lowerBound)
            let batch = try fetch(from: windowStart, to: upperBound, filter: filter)
            collected.append(contentsOf: batch.filter(filter.matchesRelationships))
            upperBound = windowStart
            if windowStart <= lowerBound {
                return Page(sections: group(collected), nextCursor: nil)
            }
        }
        return Page(sections: group(collected), nextCursor: upperBound)
    }

    // MARK: Private

    private func predicate(from start: Date, to end: Date, filter: HistoryFilter) -> Predicate<LedgerEntry> {
        let kinds = filter.kinds.map(\.rawValue)
        let anyKind = kinds.isEmpty
        let minMinor = filter.minAmount.map { Money(amount: $0, currencyCode: currencyCode).minorUnits } ?? Int64.min
        let maxMinor = filter.maxAmount.map { Money(amount: $0, currencyCode: currencyCode).minorUnits } ?? Int64.max
        let search = filter.trimmedSearch
        let hasSearch = !search.isEmpty
        let searchMinor = filter.searchAmountMinor(currencyCode: currencyCode) ?? -1

        return #Predicate<LedgerEntry> { entry in
            entry.date >= start && entry.date < end
                && (anyKind || kinds.contains(entry.kindRaw))
                && entry.amountMinor >= minMinor && entry.amountMinor <= maxMinor
                && (!hasSearch
                    || entry.note.localizedStandardContains(search)
                    || entry.payee.localizedStandardContains(search)
                    || entry.amountMinor == searchMinor)
        }
    }

    private func newestDate(before end: Date, after start: Date, filter: HistoryFilter) throws -> Date? {
        var descriptor = FetchDescriptor(predicate: predicate(from: start, to: end, filter: filter), sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.date]
        return try context.fetch(descriptor).first?.date
    }

    private func fetch(from start: Date, to end: Date, filter: HistoryFilter) throws -> [LedgerEntry] {
        var descriptor = FetchDescriptor(predicate: predicate(from: start, to: end, filter: filter), sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.relationshipKeyPathsForPrefetching = [\.category, \.account, \.tags]
        return try context.fetch(descriptor)
    }

    private func group(_ entries: [LedgerEntry]) -> [DaySection] {
        var order: [Int32] = []
        var byDay: [Int32: [LedgerEntry]] = [:]
        for entry in entries {
            if byDay[entry.dayKey] == nil { order.append(entry.dayKey) }
            byDay[entry.dayKey, default: []].append(entry)
        }
        return order.map { key in
            let items = byDay[key] ?? []
            return DaySection(dayKey: key, date: calendar.startOfDay(for: items.first?.date ?? .now), entries: items, totals: Totals(entries: items))
        }
    }
}
