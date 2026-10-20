import Foundation
import SwiftData
import Testing
@testable import KnockKit

struct AnalyticsEngineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        return calendar
    }()

    var calc: PeriodCalculator { PeriodCalculator(calendar: calendar) }

    func date(_ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h)) ?? .distantPast
    }

    func point(_ kind: TransactionKind, _ rupees: Int64, _ m: Int, _ d: Int, category: UUID? = nil, payee: String = "", recurring: Bool = false, tags: [UUID] = []) -> TxnPoint {
        let at = date(m, d)
        return TxnPoint(date: at, dayKey: calc.dayKey(for: at), kind: kind, amountMinor: rupees * 100, categoryID: category, payee: payee, tagIDs: tags, isRecurring: recurring)
    }

    let food = UUID(), dining = UUID(), rent = UUID(), salary = UUID()

    var categories: [UUID: CategoryInfo] {
        [
            food: CategoryInfo(id: food, name: "Food", emoji: "🍔", colorHex: "#FF9F0A"),
            dining: CategoryInfo(id: dining, name: "Dining", emoji: "🍽️", colorHex: "#FF9F0A", parentID: food),
            rent: CategoryInfo(id: rent, name: "Rent", emoji: "🏠", colorHex: "#BF5AF2"),
            salary: CategoryInfo(id: salary, name: "Salary", emoji: "💼", colorHex: "#30D158"),
        ]
    }

    @Test func categoriesRollUpToParentsAndRefundsNet() {
        let october = calc.cycle(containing: date(10, 1))
        let points = [
            point(.expense, 300, 10, 2, category: food),
            point(.expense, 200, 10, 3, category: dining),
            point(.refund, 100, 10, 4, category: food),
            point(.expense, 1_000, 10, 1, category: rent),
            point(.income, 5_000, 10, 1, category: salary),
        ]
        let report = AnalyticsEngine.report(.init(period: october, points: points, categories: categories, now: date(11, 5)), calculator: calc)
        #expect(report.spendingByCategory.map(\.name) == ["Rent", "Food"])
        #expect(report.spendingByCategory.map(\.amountMinor) == [100_000, 40_000])
        #expect(report.spendingByCategory.map(\.count) == [1, 3])
        #expect(abs(report.spendingByCategory.map(\.share).reduce(0, +) - 1) < 0.0001)
        #expect(report.incomeByCategory.map(\.name) == ["Salary"])
        #expect(report.totals.netMinor == (5_000 - 1_400) * 100)
    }

    @Test func dailySeriesAndCumulativeNet() {
        let october = calc.cycle(containing: date(10, 1))
        let points = [point(.income, 1_000, 10, 1), point(.expense, 100, 10, 1), point(.expense, 50, 10, 3), point(.transfer, 999, 10, 3)]
        let report = AnalyticsEngine.report(.init(period: october, points: points, now: date(11, 5)), calculator: calc)
        #expect(report.dailySpend.count == 31)
        #expect(report.dailySpend[0].valueMinor == 10_000)
        #expect(report.dailySpend[2].valueMinor == 5_000)
        #expect(report.cumulativeNet[0].valueMinor == 90_000)
        #expect(report.cumulativeNet[30].valueMinor == 85_000)
        #expect(report.granularity == .day)
        #expect(report.buckets.count == 31)
    }

    @Test func yearUsesMonthlyBuckets() {
        let year = calc.year(containing: date(6, 1))
        let points = [point(.expense, 100, 1, 5), point(.expense, 200, 1, 20), point(.income, 900, 3, 1)]
        let report = AnalyticsEngine.report(.init(period: year, points: points, now: date(12, 31)), calculator: calc)
        #expect(report.granularity == .month)
        #expect(report.buckets.count == 12)
        #expect(report.buckets[0].spendMinor == 30_000)
        #expect(report.buckets[2].incomeMinor == 90_000)
    }

    @Test func projectionExcludesRecurringFromTheDailyRate() {
        let october = calc.cycle(containing: date(10, 1))
        // Day 10 of 31: ₹10,000 rent (recurring) + ₹2,000 variable.
        let points = [point(.expense, 10_000, 10, 1, category: rent, recurring: true), point(.expense, 2_000, 10, 5, category: food)]
        let report = AnalyticsEngine.report(.init(period: october, points: points, now: date(10, 10), scheduledRemainingSpendMinor: 64_900), calculator: calc)
        let insights = report.insights
        #expect(insights.elapsedDays == 10)
        #expect(insights.dailyAverageMinor == 120_000)
        // 12,000 so far + (2,000 / 10) × 21 remaining days + ₹649 still due.
        #expect(insights.projectedSpendMinor == Int64(1_200_000 + 20_000 * 21 + 64_900))
    }

    @Test func noProjectionForPastPeriodsOrEarlyDays() {
        let october = calc.cycle(containing: date(10, 1))
        let points = [point(.expense, 100, 10, 1)]
        #expect(AnalyticsEngine.report(.init(period: october, points: points, now: date(11, 2)), calculator: calc).insights.projectedSpendMinor == nil)
        #expect(AnalyticsEngine.report(.init(period: october, points: points, now: date(10, 2)), calculator: calc).insights.projectedSpendMinor == nil)
    }

    @Test func comparisonBiggestFrequentAndNoSpendDays() {
        let october = calc.cycle(containing: date(10, 1))
        let points = [
            point(.expense, 500, 10, 1, category: food, payee: "Swiggy"),
            point(.expense, 100, 10, 1, category: food),
            point(.expense, 900, 10, 3, category: rent),
            point(.refund, 50, 10, 4, category: food),
        ]
        let previous = [point(.expense, 1_000, 9, 2)]
        let report = AnalyticsEngine.report(.init(period: october, points: points, previousPoints: previous, categories: categories, now: date(10, 6)), calculator: calc)
        let insights = report.insights
        #expect(insights.comparisonDeltaMinor == Int64((1_450 - 1_000) * 100))
        #expect(insights.comparisonRatio == 0.45)
        #expect(insights.biggestExpense?.amountMinor == 90_000)
        #expect(insights.biggestExpense?.label == "Rent")
        #expect(insights.mostFrequentCategory == Insights.FrequentCategory(name: "Food", count: 2))
        // Days 1–5 counted (today, the 6th, is still running): spent on 1 and 3 → 2, 4, 5 are no-spend.
        #expect(insights.noSpendDays == 3)
    }

    @Test func topPayeesAndTags() {
        let october = calc.cycle(containing: date(10, 1))
        let work = UUID()
        let points = [
            point(.expense, 100, 10, 1, payee: "Uber", tags: [work]),
            point(.expense, 300, 10, 2, payee: "Uber"),
            point(.expense, 250, 10, 2, payee: "Zomato", tags: [work]),
        ]
        let report = AnalyticsEngine.report(.init(period: october, points: points, tagNames: [work: "work"], now: date(11, 1)), calculator: calc)
        #expect(report.topPayees.map(\.name) == ["Uber", "Zomato"])
        #expect(report.topPayees.first?.count == 2)
        #expect(report.topTags == [RankedItem(name: "work", amountMinor: 35_000, count: 2)])
    }

    @Test func netWorthWalksBackwardsFromToday() {
        let october = calc.cycle(containing: date(10, 1))
        let points = [point(.income, 1_000, 10, 10), point(.expense, 400, 10, 20)]
        // Net worth today ₹50,000; ₹2,000 of cash flow happened after October.
        let report = AnalyticsEngine.report(.init(period: october, points: points, now: date(11, 15), currentNetWorthMinor: 5_000_000, cashFlowAfterPeriodMinor: 200_000), calculator: calc)
        #expect(report.netWorth.last?.valueMinor == 4_800_000)
        #expect(report.netWorth.first?.valueMinor == Int64(4_800_000 - 60_000))
    }
}

@MainActor
struct AnalyticsServiceTests {
    @Test func serviceMatchesTotalsAndCaches() async throws {
        let container = try KnockStore.makeInMemoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populate(context: container.mainContext, months: 2, now: now, calendar: calendar)
        let calc = PeriodCalculator(calendar: calendar)
        let october = calc.cycle(containing: now)

        let service = AnalyticsService(modelContainer: container)
        let report = try await service.report(for: october, calculator: calc, now: now, dataVersion: 1)
        let expected = try TransactionService(context: container.mainContext, calculator: calc).totals(in: october)
        #expect(report.totals == expected)
        #expect(report.spendingByCategory.reduce(0) { $0 + $1.amountMinor } >= expected.netSpendMinor)
        #expect(report.insights.projectedSpendMinor != nil)
        #expect(report.insights.comparisonDeltaMinor != nil)
        let again = try await service.report(for: october, calculator: calc, now: now, dataVersion: 1)
        #expect(again.totals == report.totals)
    }
}
