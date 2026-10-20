import Foundation
import SwiftData

/// Builds analytics reports off the main thread. Results are cached per period and data
/// version, so swiping back to a period is instant and any save invalidates everything.
@ModelActor
public actor AnalyticsService {
    private var cache: [CacheKey: AnalyticsReport] = [:]

    private struct CacheKey: Hashable {
        let start: Date
        let end: Date
        let cycleStartDay: Int
        let firstWeekday: Int
        let version: Int
        let dayStamp: Int32
    }

    /// Recurring expenses still due in `period` (supplied by the recurring-rules layer, M5).
    public var scheduledSpendProvider: (@Sendable (Period, Date) -> Int64)?

    public func setScheduledSpendProvider(_ provider: (@Sendable (Period, Date) -> Int64)?) {
        scheduledSpendProvider = provider
        cache.removeAll()
    }

    public func report(for period: Period, calculator: PeriodCalculator, now: Date = .now, dataVersion: Int) throws -> AnalyticsReport {
        let key = CacheKey(start: period.start, end: period.end, cycleStartDay: calculator.cycleStartDay,
                           firstWeekday: calculator.calendar.firstWeekday, version: dataVersion, dayStamp: calculator.dayKey(for: now))
        if let cached = cache[key] { return cached }

        let current = try points(from: period.start, to: period.end)
        let previous = calculator.shifted(period, by: -1)
        let elapsed = calculator.daysElapsed(in: period, now: now)
        let previousEnd: Date
        if period.contains(now) {
            previousEnd = min(calculator.calendar.date(byAdding: .day, value: elapsed, to: previous.start) ?? previous.end, previous.end)
        } else {
            previousEnd = previous.end
        }
        let previousPoints = try points(from: previous.start, to: previousEnd)

        let input = AnalyticsEngine.Input(
            period: period,
            points: current,
            previousPoints: previousPoints,
            categories: try categoryInfos(),
            tagNames: Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<LedgerTag>()).map { ($0.id, $0.name) }),
            now: now,
            currentNetWorthMinor: try AccountService(context: modelContext).netWorthMinor(),
            cashFlowAfterPeriodMinor: try cashFlow(from: period.end),
            scheduledRemainingSpendMinor: scheduledSpendProvider?(period, now) ?? 0
        )
        let report = AnalyticsEngine.report(input, calculator: calculator)
        if cache.count > 48 { cache.removeAll() }
        cache[key] = report
        return report
    }

    public func points(from start: Date, to end: Date) throws -> [TxnPoint] {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        descriptor.relationshipKeyPathsForPrefetching = [\.category, \.tags]
        return try modelContext.fetch(descriptor).map { entry in
            TxnPoint(date: entry.date, dayKey: entry.dayKey, kind: entry.kind, amountMinor: entry.amountMinor,
                     categoryID: entry.category?.id, payee: entry.payee, tagIDs: (entry.tags ?? []).map(\.id),
                     isRecurring: entry.recurringRule != nil)
        }
    }

    public func categoryInfos() throws -> [UUID: CategoryInfo] {
        let categories = try modelContext.fetch(FetchDescriptor<LedgerCategory>())
        return Dictionary(uniqueKeysWithValues: categories.map {
            ($0.id, CategoryInfo(id: $0.id, name: $0.name, emoji: $0.emoji, colorHex: $0.colorHex, parentID: $0.parent?.id))
        })
    }

    private func cashFlow(from start: Date) throws -> Int64 {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start })
        descriptor.propertiesToFetch = [\.kindRaw, \.amountMinor]
        return try modelContext.fetch(descriptor).reduce(0) { $0 + $1.cashFlowMinor }
    }
}
