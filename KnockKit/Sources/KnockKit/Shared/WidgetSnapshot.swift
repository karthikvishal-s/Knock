import Foundation
import SwiftData

/// Everything the widgets show, precomputed by the app after every change and stored as JSON
/// in the App Group. Widgets never open the database.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct CategoryLine: Codable, Sendable, Equatable {
        public var emoji: String
        public var name: String
        public var colorHex: String
        public var spentMinor: Int64
        public var budgetMinor: Int64?
    }

    public struct RecentLine: Codable, Sendable, Equatable {
        public var emoji: String
        public var title: String
        public var signedMinor: Int64
        public var kindRaw: String
        public var date: Date
    }

    public var generatedAt: Date
    public var currencyCode: String
    /// False when App Lock hides totals outside the app.
    public var showsAmounts: Bool
    public var cycleStart: Date
    public var cycleEnd: Date
    public var spentMinor: Int64
    public var incomeMinor: Int64
    public var budgetMinor: Int64?
    public var budgetProgress: Double?
    public var perDayMinor: Int64?
    public var leftTodayMinor: Int64?
    public var daysRemaining: Int?
    /// Tomorrow's per-day allowance, for the midnight timeline entry.
    public var tomorrowPerDayMinor: Int64?
    public var topCategories: [CategoryLine]
    public var recent: [RecentLine]

    public static let fileName = "widget-snapshot.json"

    public static var placeholder: WidgetSnapshot {
        let now = Date.now
        return WidgetSnapshot(
            generatedAt: now, currencyCode: "INR", showsAmounts: true, cycleStart: now, cycleEnd: now.addingTimeInterval(86_400 * 30),
            spentMinor: 1_842_000, incomeMinor: 6_200_000, budgetMinor: 3_000_000, budgetProgress: 0.61, perDayMinor: 61_000,
            leftTodayMinor: 35_000, daysRemaining: 12, tomorrowPerDayMinor: 59_000,
            topCategories: [
                CategoryLine(emoji: "🍔", name: "Food", colorHex: "#FF9F0A", spentMinor: 590_000, budgetMinor: 800_000),
                CategoryLine(emoji: "🏠", name: "Rent", colorHex: "#BF5AF2", spentMinor: 500_000, budgetMinor: nil),
                CategoryLine(emoji: "🚕", name: "Transport", colorHex: "#FFD60A", spentMinor: 210_000, budgetMinor: 300_000),
            ],
            recent: [
                RecentLine(emoji: "🍔", title: "Swiggy", signedMinor: -25_000, kindRaw: "expense", date: now),
                RecentLine(emoji: "☕", title: "Chai Point", signedMinor: -8_000, kindRaw: "expense", date: now.addingTimeInterval(-3_600)),
                RecentLine(emoji: "💼", title: "Salary", signedMinor: 6_200_000, kindRaw: "income", date: now.addingTimeInterval(-86_400)),
            ]
        )
    }
}

public enum WidgetSnapshotStore {
    public static func url(directory: URL = StoreLocation.resolve().directory) -> URL {
        directory.appending(path: WidgetSnapshot.fileName)
    }

    public static func write(_ snapshot: WidgetSnapshot, directory: URL = StoreLocation.resolve().directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url(directory: directory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func read(directory: URL = StoreLocation.resolve().directory) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url(directory: directory)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

public enum WidgetSnapshotBuilder {
    public static func build(context: ModelContext, calculator: PeriodCalculator, currencyCode: String, showsAmounts: Bool, now: Date = .now) throws -> WidgetSnapshot {
        let cycle = calculator.cycle(containing: now)
        let transactions = TransactionService(context: context, calculator: calculator)
        let totals = try transactions.totals(in: cycle)
        let budgets = BudgetService(context: context, calculator: calculator)
        let statuses = try budgets.statuses(now: now)
        let overall = statuses.first { $0.categoryID == nil }
        let upcoming = try RecurringService(context: context, calculator: calculator).scheduledSpend(in: cycle, after: now)
        let safe = try budgets.safeToSpend(now: now, upcomingRecurringMinor: upcoming)

        var tomorrowPerDay: Int64?
        if let overall, let safe, safe.daysRemaining > 1 {
            tomorrowPerDay = BudgetMath.safeToSpend(availableMinor: overall.availableMinor, spentBeforeTodayMinor: overall.spentMinor, spentTodayMinor: 0,
                                                    upcomingRecurringMinor: upcoming, daysRemainingIncludingToday: safe.daysRemaining - 1).perDayMinor
        }

        // Top categories by spend this cycle, with their budgets where set.
        let start = cycle.start, end = cycle.end
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))
        var byCategory: [UUID: (category: LedgerCategory, spent: Int64)] = [:]
        for entry in entries where entry.kind == .expense || entry.kind == .refund {
            guard let category = entry.category?.parent ?? entry.category else { continue }
            byCategory[category.id, default: (category, 0)].spent += entry.kind == .refund ? -entry.amountMinor : entry.amountMinor
        }
        let top = byCategory.values.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }.prefix(4).map { item in
            WidgetSnapshot.CategoryLine(emoji: item.category.emoji, name: item.category.name, colorHex: item.category.colorHex, spentMinor: item.spent,
                                        budgetMinor: statuses.first { $0.categoryID == item.category.id }?.availableMinor)
        }

        var recentDescriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        recentDescriptor.fetchLimit = 4
        let recent = try context.fetch(recentDescriptor).map { entry in
            WidgetSnapshot.RecentLine(
                emoji: entry.kind == .transfer ? "⇄" : entry.category?.emoji ?? "🏷️",
                title: entry.payee.isEmpty ? (entry.category?.name ?? String(localized: "Transfer")) : entry.payee,
                signedMinor: entry.kind == .transfer ? entry.amountMinor : entry.cashFlowMinor,
                kindRaw: entry.kindRaw, date: entry.date
            )
        }

        return WidgetSnapshot(
            generatedAt: now, currencyCode: currencyCode, showsAmounts: showsAmounts, cycleStart: cycle.start, cycleEnd: cycle.end,
            spentMinor: totals.netSpendMinor, incomeMinor: totals.incomeMinor,
            budgetMinor: overall?.availableMinor, budgetProgress: overall?.progress,
            perDayMinor: safe?.perDayMinor, leftTodayMinor: safe?.leftTodayMinor, daysRemaining: safe?.daysRemaining,
            tomorrowPerDayMinor: tomorrowPerDay, topCategories: Array(top), recent: recent
        )
    }
}
