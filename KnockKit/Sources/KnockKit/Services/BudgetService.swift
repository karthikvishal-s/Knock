import Foundation
import SwiftData

public enum BudgetError: LocalizedError, Equatable {
    case invalidLimit
    case duplicate

    public var errorDescription: String? {
        switch self {
        case .invalidLimit: String(localized: "Enter a budget greater than zero.")
        case .duplicate: String(localized: "That budget already exists. Edit it instead.")
        }
    }
}

public struct BudgetService {
    public let context: ModelContext
    public let calculator: PeriodCalculator

    public init(context: ModelContext, calculator: PeriodCalculator) {
        self.context = context
        self.calculator = calculator
    }

    public func activeBudgets() throws -> [Budget] {
        try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.isActive }))
    }

    public func overall() throws -> Budget? {
        try activeBudgets().first { $0.category == nil }
    }

    @discardableResult
    public func setBudget(categoryID: UUID?, limit: Decimal, currencyCode: String, rollover: Bool, thresholds: [Int], now: Date = .now) throws -> Budget {
        let limitMinor = Money(amount: limit, currencyCode: currencyCode).minorUnits
        guard limitMinor > 0 else { throw BudgetError.invalidLimit }
        let existing = try activeBudgets().first { $0.category?.id == categoryID }
        let budget: Budget
        if let existing {
            budget = existing
        } else {
            let category = try categoryID.flatMap { id in try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })).first }
            budget = Budget(category: category, limitMinor: limitMinor)
            budget.effectiveFrom = calculator.cycle(containing: now).start
            context.insert(budget)
        }
        budget.limitMinor = limitMinor
        budget.rollover = rollover
        budget.alertThresholds = thresholds.sorted()
        try commit()
        return budget
    }

    public func delete(_ budget: Budget) throws {
        context.delete(budget)
        try commit()
    }

    /// Status of every active budget in the cycle containing `now`, overall first, then by spend.
    public func statuses(now: Date = .now) throws -> [BudgetStatus] {
        let cycle = calculator.cycle(containing: now)
        let budgets = try activeBudgets()
        guard !budgets.isEmpty else { return [] }
        let earliest = budgets.filter(\.rollover).map(\.effectiveFrom).min() ?? cycle.start
        let points = try spendPoints(from: min(earliest, cycle.start), to: cycle.end)

        return budgets.map { budget in
            let matches = categoryMatcher(budget)
            let spent = points.filter { cycle.contains($0.date) && matches($0.categoryID) }.reduce(0) { $0 + $1.spend }
            var rollover: Int64 = 0
            if budget.rollover {
                var previous: [Int64] = []
                var period = calculator.shifted(cycle, by: -1)
                while period.end > budget.effectiveFrom, previous.count < 12 {
                    let p = period
                    previous.insert(points.filter { p.contains($0.date) && matches($0.categoryID) }.reduce(0) { $0 + $1.spend }, at: 0)
                    period = calculator.shifted(period, by: -1)
                }
                rollover = BudgetMath.rollover(limitMinor: budget.limitMinor, previousSpends: previous)
            }
            return BudgetStatus(
                id: budget.id, categoryID: budget.category?.id,
                name: budget.category?.name ?? String(localized: "Monthly budget"),
                emoji: budget.category?.emoji ?? "💰", colorHex: budget.category?.colorHex ?? "#0A84FF",
                limitMinor: budget.limitMinor, rolloverMinor: rollover, spentMinor: spent, thresholds: budget.alertThresholds
            )
        }
        .sorted { lhs, rhs in
            if (lhs.categoryID == nil) != (rhs.categoryID == nil) { return lhs.categoryID == nil }
            return lhs.progress > rhs.progress
        }
    }

    /// Safe-to-spend for the overall budget, or `nil` if there's none.
    public func safeToSpend(now: Date = .now, upcomingRecurringMinor: Int64) throws -> BudgetMath.SafeToSpend? {
        guard let overall = try statuses(now: now).first(where: { $0.categoryID == nil }) else { return nil }
        let today = calculator.day(containing: now)
        let cycle = calculator.cycle(containing: now)
        let spentToday = try spendPoints(from: today.start, to: today.end).reduce(0) { $0 + $1.spend }
        return BudgetMath.safeToSpend(
            availableMinor: overall.availableMinor, spentBeforeTodayMinor: overall.spentMinor - spentToday, spentTodayMinor: spentToday,
            upcomingRecurringMinor: upcomingRecurringMinor, daysRemainingIncludingToday: calculator.daysRemaining(in: cycle, now: now)
        )
    }

    // MARK: Private

    /// Overall budgets match everything; category budgets match the category and its children.
    private func categoryMatcher(_ budget: Budget) -> (UUID?) -> Bool {
        guard let category = budget.category else { return { _ in true } }
        let ids = Set([category.id] + (category.children ?? []).map(\.id))
        return { id in id.map(ids.contains) ?? false }
    }

    private func spendPoints(from start: Date, to end: Date) throws -> [(date: Date, categoryID: UUID?, spend: Int64)] {
        let expense = TransactionKind.expense.rawValue, refund = TransactionKind.refund.rawValue
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end && ($0.kindRaw == expense || $0.kindRaw == refund) })
        descriptor.relationshipKeyPathsForPrefetching = [\.category]
        return try context.fetch(descriptor).map { (date: $0.date, categoryID: $0.category?.id, spend: $0.kind == .refund ? -$0.amountMinor : $0.amountMinor) }
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}

public struct RecurringDraft: Equatable, Sendable {
    public var kind: TransactionKind = .expense
    public var amount: Decimal = 0
    public var currencyCode: String = "INR"
    public var categoryID: UUID?
    public var accountID: UUID?
    public var transferAccountID: UUID?
    public var payee: String = ""
    public var note: String = ""
    public var spec: RecurrenceSpec
    public var mode: RecurringMode = .autoPost
    public var isActive = true

    public init(spec: RecurrenceSpec) {
        self.spec = spec
    }

    public init(rule: RecurringRule) {
        self.init(spec: rule.spec)
        kind = rule.kind
        amount = Money(minorUnits: rule.amountMinor, currencyCode: rule.currencyCode).amount
        currencyCode = rule.currencyCode
        categoryID = rule.category?.id
        accountID = rule.account?.id
        transferAccountID = rule.transferAccount?.id
        payee = rule.payee
        note = rule.note
        mode = rule.mode
        isActive = rule.isActive
    }
}

/// A rule's next due date, for the upcoming-bills list.
public struct UpcomingItem: Identifiable, Sendable, Equatable {
    public var id: String { "\(ruleID)-\(date.timeIntervalSince1970)" }
    public var ruleID: UUID
    public var name: String
    public var emoji: String
    public var kind: TransactionKind
    public var amountMinor: Int64
    public var currencyCode: String
    public var date: Date
    public var mode: RecurringMode
}

public struct RecurringService {
    public let context: ModelContext
    public let calculator: PeriodCalculator

    public init(context: ModelContext, calculator: PeriodCalculator) {
        self.context = context
        self.calculator = calculator
    }

    public func rules() throws -> [RecurringRule] {
        try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [SortDescriptor(\.nextDueDate)]))
    }

    @discardableResult
    public func save(_ draft: RecurringDraft, editing rule: RecurringRule? = nil, now: Date = .now) throws -> RecurringRule {
        let minor = Money(amount: draft.amount, currencyCode: draft.currencyCode).minorUnits
        guard minor > 0 else { throw TransactionError.invalidAmount }
        if draft.kind == .transfer, draft.accountID == nil || draft.transferAccountID == nil || draft.accountID == draft.transferAccountID {
            throw TransactionError.missingTransferAccount
        }
        let target = rule ?? RecurringRule(kind: draft.kind, amountMinor: minor, frequency: draft.spec.frequency, startDate: draft.spec.startDate)
        if rule == nil { context.insert(target) }
        let scheduleChanged = rule == nil || target.spec != draft.spec
        target.kind = draft.kind
        target.amountMinor = minor
        target.currencyCode = draft.currencyCode
        target.category = try draft.categoryID.flatMap { id in try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })).first }
        target.account = try draft.accountID.flatMap { id in try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first }
        target.transferAccount = draft.kind == .transfer ? try draft.transferAccountID.flatMap { id in try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first } : nil
        target.payee = draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.frequency = draft.spec.frequency
        target.interval = draft.spec.interval
        target.weekdays = draft.spec.weekdays.isEmpty ? nil : draft.spec.weekdays
        target.dayOfMonth = draft.spec.dayOfMonth
        target.startDate = draft.spec.startDate
        target.endDate = draft.spec.endDate
        target.mode = draft.mode
        target.isActive = draft.isActive
        if scheduleChanged {
            // First occurrence at or after the start (or today, for an edited rule).
            let from = rule == nil ? draft.spec.startDate.addingTimeInterval(-1) : max(draft.spec.startDate, calculator.calendar.startOfDay(for: now)).addingTimeInterval(-1)
            target.nextDueDate = RecurrenceEngine.next(after: from, spec: draft.spec, calendar: calculator.calendar) ?? draft.spec.startDate
        }
        try commit()
        return target
    }

    public func delete(_ rule: RecurringRule) throws {
        context.delete(rule)
        try commit()
    }

    /// Posts every auto-post occurrence due by `now`, oldest first, advancing each rule.
    /// Safe to call repeatedly: a posted occurrence moves `nextDueDate` past it.
    @discardableResult
    public func postDue(now: Date = .now) throws -> Int {
        var posted = 0
        for rule in try rules() where rule.isActive && rule.mode == .autoPost {
            while rule.nextDueDate <= now, rule.endDate.map({ rule.nextDueDate <= $0 }) ?? true {
                try post(rule, on: rule.nextDueDate)
                posted += 1
                guard advance(rule) else { break }
            }
        }
        if posted > 0 { try commit() }
        return posted
    }

    /// For remind-mode rules: log the due occurrence now and move to the next one.
    public func markPaid(_ rule: RecurringRule, now: Date = .now) throws {
        try post(rule, on: min(rule.nextDueDate, now))
        _ = advance(rule)
        try commit()
    }

    public func skip(_ rule: RecurringRule) throws {
        _ = advance(rule)
        try commit()
    }

    /// Due items in the next `days` days (including overdue remind-mode ones).
    public func upcoming(days: Int, now: Date = .now) throws -> [UpcomingItem] {
        guard let horizon = calculator.calendar.date(byAdding: .day, value: days, to: now) else { return [] }
        return try rules().filter(\.isActive).flatMap { rule -> [UpcomingItem] in
            var dates: [Date] = []
            if rule.mode == .remind, rule.nextDueDate <= now { dates.append(rule.nextDueDate) }
            dates += RecurrenceEngine.occurrences(of: rule.spec, from: max(rule.nextDueDate, now), through: horizon, calendar: calculator.calendar)
            return dates.map { date in
                UpcomingItem(ruleID: rule.id, name: rule.displayName, emoji: rule.category?.emoji ?? (rule.kind == .transfer ? "⇄" : "🔁"),
                             kind: rule.kind, amountMinor: rule.amountMinor, currencyCode: rule.currencyCode, date: date, mode: rule.mode)
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// Recurring expenses still due after `now` and before the end of `period`.
    public func scheduledSpend(in period: Period, after now: Date) throws -> Int64 {
        guard now < period.end else { return 0 }
        return try rules().filter { $0.isActive && $0.kind == .expense }.reduce(0) { total, rule in
            let from = max(rule.nextDueDate, max(now, period.start))
            let count = RecurrenceEngine.occurrences(of: rule.spec, from: from, through: period.end.addingTimeInterval(-1), calendar: calculator.calendar)
                .filter { $0 > now }.count
            return total + Int64(count) * rule.amountMinor
        }
    }

    private func post(_ rule: RecurringRule, on date: Date) throws {
        let draft = TransactionDraft(kind: rule.kind, amount: Money(minorUnits: rule.amountMinor, currencyCode: rule.currencyCode).amount,
                                     currencyCode: rule.currencyCode, categoryID: rule.category?.id, accountID: rule.account?.id,
                                     transferAccountID: rule.transferAccount?.id, date: date, note: rule.note, payee: rule.payee, source: .recurring)
        let entry = try TransactionService(context: context, calculator: calculator).add(draft)
        entry.recurringRule = rule
    }

    /// Moves to the next occurrence; deactivates the rule past its end. Returns false when done.
    private func advance(_ rule: RecurringRule) -> Bool {
        guard let next = RecurrenceEngine.next(after: rule.nextDueDate, spec: rule.spec, calendar: calculator.calendar) else {
            rule.isActive = false
            return false
        }
        if let end = rule.endDate, next > end {
            rule.nextDueDate = next
            rule.isActive = false
            return false
        }
        rule.nextDueDate = next
        return true
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}

public struct GoalService {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func add(name: String, emoji: String, colorHex: String, target: Decimal, targetDate: Date?, currencyCode: String) throws -> SavingsGoal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }
        let minor = Money(amount: target, currencyCode: currencyCode).minorUnits
        guard minor > 0 else { throw BudgetError.invalidLimit }
        let goal = SavingsGoal(name: trimmed, targetMinor: minor)
        goal.emoji = emoji
        goal.colorHex = colorHex
        goal.targetDate = targetDate
        context.insert(goal)
        try commit()
        return goal
    }

    public func contribute(_ amount: Decimal, to goal: SavingsGoal, currencyCode: String, date: Date = .now, note: String = "") throws {
        let minor = Money(amount: amount, currencyCode: currencyCode).minorUnits
        guard minor != 0 else { throw TransactionError.invalidAmount }
        let contribution = GoalContribution(amountMinor: minor, date: date)
        contribution.note = note
        context.insert(contribution)
        contribution.goal = goal
        try commit()
    }

    public func delete(_ goal: SavingsGoal) throws {
        context.delete(goal)
        try commit()
    }

    public static func savedMinor(_ goal: SavingsGoal) -> Int64 {
        (goal.contributions ?? []).reduce(0) { $0 + $1.amountMinor }
    }

    public static func progress(_ goal: SavingsGoal) -> Double {
        goal.targetMinor > 0 ? min(1, max(0, Double(savedMinor(goal)) / Double(goal.targetMinor))) : 0
    }

    /// Per-month saving needed to hit the target date, if it's set and not reached.
    public static func monthlyNeededMinor(_ goal: SavingsGoal, now: Date = .now, calendar: Calendar = .current) -> Int64? {
        guard let targetDate = goal.targetDate, targetDate > now else { return nil }
        let remaining = goal.targetMinor - savedMinor(goal)
        guard remaining > 0 else { return nil }
        let months = max(1, (calendar.dateComponents([.month], from: now, to: targetDate).month ?? 0) + 1)
        return (remaining + Int64(months) - 1) / Int64(months)
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}
