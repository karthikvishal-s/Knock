import Foundation
import SwiftData

/// Deterministic, realistic INR data for previews, UI tests and performance runs.
public enum SampleData {
    /// Seeds defaults, then adds `months` of entries ending at `now`.
    @discardableResult
    public static func populate(context: ModelContext, months: Int = 3, now: Date = .now, calendar: Calendar = .current, seed: UInt64 = 42) throws -> Int {
        try Seeder.seedIfNeeded(context: context)
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
        func category(_ name: String, _ kind: CategoryKind) -> LedgerCategory? {
            categories.first { $0.name == name && $0.kind == kind }
        }
        let cash = accounts.first
        let bank = accounts.dropFirst().first ?? cash
        let calculator = PeriodCalculator(calendar: calendar)
        var rng = SplitMix64(seed: seed)
        var count = 0

        func add(_ kind: TransactionKind, rupees: Double, _ categoryName: String?, on date: Date, note: String = "", payee: String = "", account: Account?) {
            let entry = LedgerEntry(kind: kind, amountMinor: Int64((rupees * 100).rounded()), currencyCode: "INR", date: date, dayKey: calculator.dayKey(for: date))
            entry.note = note
            entry.payee = payee
            entry.account = account
            if let categoryName, let categoryKind = kind.categoryKind, let category = category(categoryName, categoryKind) {
                entry.category = category
                category.usageCount += 1
                if (category.lastUsedAt ?? .distantPast) < date { category.lastUsedAt = date }
            }
            context.insert(entry)
            count += 1
        }

        let everyday: [(String, ClosedRange<Double>, [String])] = [
            ("Food", 80...650, ["Swiggy", "Zomato", "Chai Point", "Office canteen", ""]),
            ("Groceries", 150...2_400, ["BigBasket", "Blinkit", "DMart", ""]),
            ("Transport", 40...420, ["Uber", "Ola", "Metro", "Rapido"]),
            ("Shopping", 299...3_999, ["Amazon", "Myntra", "Decathlon"]),
            ("Entertainment", 149...899, ["PVR", "BookMyShow", "Steam"]),
            ("Health", 120...1_500, ["Apollo Pharmacy", "1mg"]),
            ("Fuel", 500...2_500, ["Indian Oil", "HP"]),
        ]

        let firstDay = calendar.date(byAdding: .month, value: -months, to: calendar.startOfDay(for: now)) ?? now
        var day = firstDay
        while day <= now {
            let dayOfMonth = calendar.component(.day, from: day)
            if dayOfMonth == 1 {
                add(.income, rupees: 85_000, "Salary", on: at(9, day, calendar), payee: "Employer", account: bank)
                add(.expense, rupees: 22_000, "Rent", on: at(10, day, calendar), note: "Monthly rent", account: bank)
            }
            if dayOfMonth == 5 {
                add(.expense, rupees: 649, "Subscriptions", on: at(8, day, calendar), payee: "Netflix", account: bank)
                add(.expense, rupees: 1_299, "Bills", on: at(19, day, calendar), payee: "Airtel", account: bank)
            }
            if dayOfMonth == 18, rng.chance(0.5) {
                add(.income, rupees: Double(rng.int(in: 5...25)) * 1_000, "Freelance", on: at(15, day, calendar), payee: "Client", account: bank)
            }
            for _ in 0..<rng.int(in: 0...3) {
                let (name, range, payees) = everyday[rng.int(in: 0...(everyday.count - 1))]
                let rupees = (rng.double(in: range) / 10).rounded() * 10
                let payee = payees[rng.int(in: 0...(payees.count - 1))]
                let time = at(rng.int(in: 8...22), day, calendar, minute: rng.int(in: 0...59))
                guard time <= now else { continue }
                add(.expense, rupees: rupees, name, on: time, payee: payee, account: rng.chance(0.6) ? cash : bank)
            }
            if rng.chance(0.04) {
                add(.refund, rupees: Double(rng.int(in: 3...30)) * 50, "Shopping", on: at(12, day, calendar), note: "Return", payee: "Amazon", account: bank)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        try context.save()
        try addPlans(context: context, now: now, calendar: calendar, food: category("Food", .expense), bank: bank)
        return count
    }

    /// Budgets, recurring rules and a goal, so the Budgets screens have something to show.
    private static func addPlans(context: ModelContext, now: Date, calendar: Calendar, food: LedgerCategory?, bank: Account?) throws {
        let calculator = PeriodCalculator(calendar: calendar)
        let budgets = BudgetService(context: context, calculator: calculator)
        try budgets.setBudget(categoryID: nil, limit: 60_000, currencyCode: "INR", rollover: false, thresholds: [80, 100], now: now)
        if let food {
            try budgets.setBudget(categoryID: food.id, limit: 3_000, currencyCode: "INR", rollover: false, thresholds: [80, 100], now: now)
        }
        let recurring = RecurringService(context: context, calculator: calculator)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.dateInterval(of: .month, for: now)?.start ?? now) ?? now
        var netflix = RecurringDraft(spec: RecurrenceSpec(frequency: .monthly, startDate: calendar.date(byAdding: .day, value: 4, to: nextMonth) ?? nextMonth))
        netflix.amount = 649
        netflix.payee = "Netflix"
        netflix.mode = .remind
        netflix.accountID = bank?.id
        try recurring.save(netflix, now: now)
        var gym = RecurringDraft(spec: RecurrenceSpec(frequency: .weekly, startDate: calendar.date(byAdding: .day, value: 2, to: now) ?? now))
        gym.amount = 300
        gym.payee = "Yoga class"
        try recurring.save(gym, now: now)
        let goals = GoalService(context: context)
        let trip = try goals.add(name: "Goa trip", emoji: "🏖️", colorHex: "#0A84FF", target: 40_000,
                                 targetDate: calendar.date(byAdding: .month, value: 4, to: now), currencyCode: "INR")
        try goals.contribute(12_500, to: trip, currencyCode: "INR", date: now)
    }

    /// `count` random entries spread evenly over `years`, for performance testing.
    @discardableResult
    public static func populateBulk(context: ModelContext, count: Int, years: Int = 4, now: Date = .now, calendar: Calendar = .current, seed: UInt64 = 7) throws -> Int {
        try Seeder.seedIfNeeded(context: context)
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let expense = categories.filter { $0.kind == .expense }
        let income = categories.filter { $0.kind == .income }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let calculator = PeriodCalculator(calendar: calendar)
        var rng = SplitMix64(seed: seed)
        let span = Double(years) * 365 * 86_400
        let payees = ["Swiggy", "Zomato", "Uber", "Amazon", "BigBasket", "Metro", "Chai Point", ""]
        for index in 0..<count {
            let date = now.addingTimeInterval(-Double(rng.int(in: 0...Int(span))))
            let isIncome = index % 25 == 0
            let category = isIncome ? income[rng.int(in: 0...(income.count - 1))] : expense[rng.int(in: 0...(expense.count - 1))]
            let entry = LedgerEntry(kind: isIncome ? .income : .expense, amountMinor: Int64(rng.int(in: 1_000...500_000)), currencyCode: "INR",
                                    date: date, dayKey: calculator.dayKey(for: date))
            entry.payee = payees[rng.int(in: 0...(payees.count - 1))]
            entry.category = category
            entry.account = accounts[rng.int(in: 0...(accounts.count - 1))]
            context.insert(entry)
            if index % 2_000 == 1_999 { try context.save() }
        }
        try context.save()
        return count
    }

    private static func at(_ hour: Int, _ day: Date, _ calendar: Calendar, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// Small deterministic PRNG so sample data is identical on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }
}
