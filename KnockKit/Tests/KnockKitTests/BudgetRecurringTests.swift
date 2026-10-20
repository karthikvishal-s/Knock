import Foundation
import SwiftData
import Testing
@testable import KnockKit

struct BudgetMathTests {
    @Test func rolloverCarriesUnspentButNeverDebt() {
        #expect(BudgetMath.rollover(limitMinor: 1_000, previousSpends: []) == 0)
        #expect(BudgetMath.rollover(limitMinor: 1_000, previousSpends: [600]) == 400)
        #expect(BudgetMath.rollover(limitMinor: 1_000, previousSpends: [600, 1_200]) == 200)
        #expect(BudgetMath.rollover(limitMinor: 1_000, previousSpends: [600, 2_000]) == 0)
        #expect(BudgetMath.rollover(limitMinor: 1_000, previousSpends: [2_000, 500]) == 500)
    }

    @Test func safeToSpendSplitsWhatsLeftAcrossRemainingDays() {
        // ₹15,000 budget, ₹9,000 spent before today, ₹300 today, ₹649 bill due, 12 days left.
        let safe = BudgetMath.safeToSpend(availableMinor: 1_500_000, spentBeforeTodayMinor: 900_000, spentTodayMinor: 30_000,
                                          upcomingRecurringMinor: 64_900, daysRemainingIncludingToday: 12)
        #expect(safe.perDayMinor == (1_500_000 - 900_000 - 64_900) / 12)
        #expect(safe.leftTodayMinor == safe.perDayMinor - 30_000)
        let over = BudgetMath.safeToSpend(availableMinor: 100, spentBeforeTodayMinor: 500, spentTodayMinor: 10, upcomingRecurringMinor: 0, daysRemainingIncludingToday: 0)
        #expect(over.perDayMinor == 0)
        #expect(over.leftTodayMinor == -10)
        #expect(over.daysRemaining == 1)
    }

    @Test func thresholdsFireOnceInOrder() {
        let t = [50, 80, 100]
        #expect(BudgetMath.thresholdToAlert(thresholds: t, progress: 0.49, alreadyAlerted: nil) == nil)
        #expect(BudgetMath.thresholdToAlert(thresholds: t, progress: 0.5, alreadyAlerted: nil) == 50)
        #expect(BudgetMath.thresholdToAlert(thresholds: t, progress: 0.85, alreadyAlerted: 50) == 80)
        #expect(BudgetMath.thresholdToAlert(thresholds: t, progress: 0.85, alreadyAlerted: 80) == nil)
        #expect(BudgetMath.thresholdToAlert(thresholds: t, progress: 1.3, alreadyAlerted: nil) == 100, "jumping straight past several announces the highest")
    }

    @Test func alertLogKeepsOnlyCurrentCycle() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        let log = BudgetAlertLog(defaults: defaults)
        let id = UUID()
        let october = Period(kind: .cycle, start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 2_000))
        let november = Period(kind: .cycle, start: Date(timeIntervalSince1970: 2_000), end: Date(timeIntervalSince1970: 3_000))
        log.record(80, budgetID: id, cycle: october)
        #expect(log.lastAlerted(budgetID: id, cycle: october) == 80)
        #expect(log.lastAlerted(budgetID: id, cycle: november) == nil)
        log.record(50, budgetID: id, cycle: november)
        #expect(log.lastAlerted(budgetID: id, cycle: october) == nil)
    }
}

struct RecurrenceEngineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    func days(_ dates: [Date]) -> [String] {
        dates.map { d in let c = calendar.dateComponents([.month, .day], from: d); return "\(c.month ?? 0)/\(c.day ?? 0)" }
    }

    @Test func monthlyOn31stClampsToMonthEnd() {
        let spec = RecurrenceSpec(frequency: .monthly, dayOfMonth: 31, startDate: date(2026, 1, 31))
        let dates = RecurrenceEngine.occurrences(of: spec, from: date(2026, 1, 1), through: date(2026, 5, 31, 23), calendar: calendar)
        #expect(days(dates) == ["1/31", "2/28", "3/31", "4/30", "5/31"])
        #expect(dates.allSatisfy { calendar.component(.hour, from: $0) == 9 })
    }

    @Test func weeklyOnSeveralDays() {
        // 2026-10-19 is a Monday. Mondays and Thursdays.
        let spec = RecurrenceSpec(frequency: .weekly, weekdays: [5, 2], startDate: date(2026, 10, 19))
        let dates = RecurrenceEngine.occurrences(of: spec, from: date(2026, 10, 19), through: date(2026, 11, 1), calendar: calendar)
        #expect(days(dates) == ["10/19", "10/22", "10/26", "10/29"])
    }

    @Test func intervalsAndEndDate() {
        let spec = RecurrenceSpec(frequency: .monthly, interval: 2, startDate: date(2026, 1, 15), endDate: date(2026, 8, 1))
        let dates = RecurrenceEngine.occurrences(of: spec, from: date(2026, 1, 1), through: date(2027, 1, 1), calendar: calendar)
        #expect(days(dates) == ["1/15", "3/15", "5/15", "7/15"])
        #expect(RecurrenceEngine.next(after: date(2026, 7, 15), spec: spec, calendar: calendar) == nil)
    }

    @Test func yearlyLeapDay() {
        let spec = RecurrenceSpec(frequency: .yearly, startDate: date(2028, 2, 29))
        let dates = RecurrenceEngine.occurrences(of: spec, from: date(2028, 1, 1), through: date(2032, 12, 31), calendar: calendar)
        #expect(days(dates) == ["2/29", "2/28", "2/28", "2/28", "2/29"])
    }

    @Test func startWithSecondsKeepsFirstOccurrence() {
        let start = date(2026, 10, 22, 22).addingTimeInterval(48 * 60 + 37)
        let spec = RecurrenceSpec(frequency: .weekly, startDate: start)
        #expect(RecurrenceEngine.next(after: start.addingTimeInterval(-1), spec: spec, calendar: calendar).map { days([$0]) } == ["10/22"])
        let dates = RecurrenceEngine.occurrences(of: spec, from: start, through: date(2026, 10, 30), calendar: calendar)
        #expect(days(dates) == ["10/22", "10/29"])
    }

    @Test func nextIsStrictlyAfter() {
        let spec = RecurrenceSpec(frequency: .daily, startDate: date(2026, 10, 1))
        #expect(RecurrenceEngine.next(after: date(2026, 10, 1), spec: spec, calendar: calendar) == date(2026, 10, 2))
        #expect(RecurrenceEngine.next(after: date(2026, 9, 1), spec: spec, calendar: calendar) == date(2026, 10, 1))
    }
}

@MainActor
struct RecurringAndBudgetServiceTests {
    let container: ModelContainer
    let context: ModelContext
    let calc: PeriodCalculator
    let calendar: Calendar

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        self.calendar = calendar
        calc = PeriodCalculator(calendar: calendar)
    }

    func date(_ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h)) ?? .distantPast
    }

    func category(_ name: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name })
    }

    @Test func catchUpPostsEachMissedOccurrenceOnce() throws {
        let service = RecurringService(context: context, calculator: calc)
        var draft = RecurringDraft(spec: RecurrenceSpec(frequency: .daily, startDate: date(10, 1)))
        draft.amount = 50
        draft.categoryID = try category("Transport").id
        let rule = try service.save(draft, now: date(10, 1, 8))
        #expect(rule.nextDueDate == date(10, 1))

        #expect(try service.postDue(now: date(10, 10, 12)) == 10, "ten days offline → ten entries")
        #expect(try service.postDue(now: date(10, 10, 12)) == 0, "idempotent")
        #expect(rule.nextDueDate == date(10, 11))
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(entries.count == 10)
        #expect(entries.allSatisfy { $0.source == .recurring && $0.recurringRule?.id == rule.id })
    }

    @Test func remindRulesWaitForMarkPaid() throws {
        let service = RecurringService(context: context, calculator: calc)
        var draft = RecurringDraft(spec: RecurrenceSpec(frequency: .monthly, startDate: date(10, 5)))
        draft.amount = 649
        draft.payee = "Netflix"
        draft.mode = .remind
        let rule = try service.save(draft, now: date(10, 1))
        #expect(try service.postDue(now: date(10, 20)) == 0)
        let upcoming = try service.upcoming(days: 30, now: date(10, 20))
        #expect(upcoming.first?.name == "Netflix")
        #expect(upcoming.first?.date == date(10, 5), "overdue reminder shows first")
        try service.markPaid(rule, now: date(10, 20))
        #expect(rule.nextDueDate == date(11, 5))
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 1)
    }

    @Test func scheduledSpendCountsRemainingOccurrencesInPeriod() throws {
        let service = RecurringService(context: context, calculator: calc)
        var weekly = RecurringDraft(spec: RecurrenceSpec(frequency: .weekly, startDate: date(10, 5)))
        weekly.amount = 100
        try service.save(weekly, now: date(10, 1))
        var income = RecurringDraft(spec: RecurrenceSpec(frequency: .monthly, startDate: date(10, 25)))
        income.kind = .income
        income.amount = 50_000
        try service.save(income, now: date(10, 1))
        let october = calc.cycle(containing: date(10, 15))
        // Mondays after the 15th: 19, 26 → ₹200. Income isn't spending.
        #expect(try service.scheduledSpend(in: october, after: date(10, 15, 12)) == 20_000)
    }

    @Test func budgetStatusesIncludeChildrenRefundsAndRollover() throws {
        let food = try category("Food")
        let dining = try CategoryService(context: context).add(CategoryDraft(name: "Dining", parentID: food.id))
        let tx = TransactionService(context: context, calculator: calc)
        let budgets = BudgetService(context: context, calculator: calc)
        try budgets.setBudget(categoryID: food.id, limit: 5_000, currencyCode: "INR", rollover: true, thresholds: [80, 50], now: date(9, 2))
        try budgets.setBudget(categoryID: nil, limit: 20_000, currencyCode: "INR", rollover: false, thresholds: [100], now: date(9, 2))
        #expect(throws: BudgetError.invalidLimit) { try budgets.setBudget(categoryID: nil, limit: 0, currencyCode: "INR", rollover: false, thresholds: []) }

        try tx.add(TransactionDraft(amount: 3_000, categoryID: food.id, date: date(9, 10)))   // September: ₹2,000 unspent rolls over
        try tx.add(TransactionDraft(amount: 1_000, categoryID: food.id, date: date(10, 3)))
        try tx.add(TransactionDraft(amount: 500, categoryID: dining.id, date: date(10, 4)))
        try tx.add(TransactionDraft(kind: .refund, amount: 200, categoryID: food.id, date: date(10, 5)))
        try tx.add(TransactionDraft(amount: 4_000, categoryID: try category("Rent").id, date: date(10, 1)))

        let statuses = try budgets.statuses(now: date(10, 6))
        #expect(statuses.first?.categoryID == nil, "overall first")
        let overall = try #require(statuses.first)
        #expect(overall.spentMinor == (1_000 + 500 - 200 + 4_000) * 100)
        let foodStatus = try #require(statuses.first { $0.categoryID == food.id })
        #expect(foodStatus.spentMinor == 130_000)
        #expect(foodStatus.rolloverMinor == 200_000)
        #expect(foodStatus.availableMinor == 700_000)
        #expect(foodStatus.thresholds == [50, 80])

        let safe = try #require(try budgets.safeToSpend(now: date(10, 6, 20), upcomingRecurringMinor: 0))
        #expect(safe.daysRemaining == 26)
        #expect(safe.perDayMinor == (2_000_000 - 530_000) / 26)
    }

    @Test func goalsTrackProgress() throws {
        let goals = GoalService(context: context)
        let trip = try goals.add(name: "Goa trip", emoji: "🏖️", colorHex: "#0A84FF", target: 30_000, targetDate: date(12, 31), currencyCode: "INR")
        try goals.contribute(10_000, to: trip, currencyCode: "INR", date: date(10, 1))
        try goals.contribute(5_000, to: trip, currencyCode: "INR", date: date(10, 15))
        #expect(GoalService.savedMinor(trip) == 1_500_000)
        #expect(GoalService.progress(trip) == 0.5)
        #expect(GoalService.monthlyNeededMinor(trip, now: date(10, 20), calendar: calendar) == Int64(1_500_000 / 3))
    }
}
