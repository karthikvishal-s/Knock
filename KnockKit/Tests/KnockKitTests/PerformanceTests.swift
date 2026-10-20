import Foundation
import SwiftData
import Testing
@testable import KnockKit

/// PLAN.md §7.3: History and Analytics must stay fast with 20,000+ transactions.
/// Budgets here are for a Mac test host (a phone is ~2–3× slower); they catch regressions
/// such as loading the whole table instead of a month.
@MainActor
@Suite(.serialized)
struct PerformanceTests {
    static let count = 20_000

    let container: ModelContainer
    let calc: PeriodCalculator
    let now: Date

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        calc = PeriodCalculator(calendar: calendar)
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populateBulk(context: container.mainContext, count: Self.count, now: now, calendar: calendar)
    }

    private func time(_ label: String, budget: Duration, _ work: () throws -> Void) rethrows {
        let clock = ContinuousClock()
        let elapsed = try clock.measure(work)
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], width: .narrow)))")
        #expect(elapsed < budget, "\(label) took \(elapsed)")
    }

    @Test func historyFirstPageAndSearch() throws {
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LedgerEntry>()) == Self.count)
        let query = HistoryQuery(context: container.mainContext, calendar: calc.calendar)
        try time("History first page", budget: .milliseconds(150)) {
            let page = try query.page(before: nil, filter: HistoryFilter())
            #expect(!page.sections.isEmpty)
        }
        var filter = HistoryFilter()
        filter.searchText = "swiggy"
        try time("History search", budget: .milliseconds(400)) {
            _ = try query.page(before: nil, filter: filter)
        }
    }

    @Test func analyticsMonthAndYear() async throws {
        let service = AnalyticsService(modelContainer: container)
        let clock = ContinuousClock()
        let month = calc.cycle(containing: now)
        let monthTime = try await clock.measure { _ = try await service.report(for: month, calculator: calc, now: now, dataVersion: 1) }
        let year = calc.year(containing: now)
        let yearTime = try await clock.measure { _ = try await service.report(for: year, calculator: calc, now: now, dataVersion: 1) }
        let cachedTime = try await clock.measure { _ = try await service.report(for: year, calculator: calc, now: now, dataVersion: 1) }
        print("⏱ Analytics month: \(monthTime), year: \(yearTime), cached: \(cachedTime)")
        #expect(monthTime < .milliseconds(400))
        #expect(yearTime < .milliseconds(1_500))
        #expect(cachedTime < .milliseconds(5))
    }

    @Test func budgetsAndWidgetSnapshot() throws {
        let context = container.mainContext
        try BudgetService(context: context, calculator: calc).setBudget(categoryID: nil, limit: 50_000, currencyCode: "INR", rollover: true, thresholds: [80], now: now)
        try time("Budget statuses", budget: .milliseconds(300)) {
            _ = try BudgetService(context: context, calculator: calc).statuses(now: now)
        }
        try time("Widget snapshot", budget: .milliseconds(500)) {
            _ = try WidgetSnapshotBuilder.build(context: context, calculator: calc, currencyCode: "INR", showsAmounts: true, now: now)
        }
    }
}
