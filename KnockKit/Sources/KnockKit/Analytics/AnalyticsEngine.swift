import Foundation

/// A ledger entry reduced to what analytics needs. `Sendable`, so it crosses actors.
public struct TxnPoint: Sendable, Hashable {
    public var date: Date
    public var dayKey: Int32
    public var kind: TransactionKind
    public var amountMinor: Int64
    public var categoryID: UUID?
    public var payee: String
    public var tagIDs: [UUID]
    public var isRecurring: Bool

    public init(date: Date, dayKey: Int32, kind: TransactionKind, amountMinor: Int64, categoryID: UUID? = nil,
                payee: String = "", tagIDs: [UUID] = [], isRecurring: Bool = false) {
        self.date = date
        self.dayKey = dayKey
        self.kind = kind
        self.amountMinor = amountMinor
        self.categoryID = categoryID
        self.payee = payee
        self.tagIDs = tagIDs
        self.isRecurring = isRecurring
    }

    /// Contribution to net spending: expenses positive, refunds negative, else 0.
    public var spendMinor: Int64 {
        switch kind {
        case .expense: amountMinor
        case .refund: -amountMinor
        case .income, .transfer: 0
        }
    }
}

public struct CategoryInfo: Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var colorHex: String
    public var parentID: UUID?

    public init(id: UUID, name: String, emoji: String, colorHex: String, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.parentID = parentID
    }
}

public struct CategorySlice: Sendable, Hashable, Identifiable {
    public var id: UUID?
    public var name: String
    public var emoji: String
    public var colorHex: String
    public var amountMinor: Int64
    public var count: Int
    /// 0...1 of the positive total.
    public var share: Double

    public init(id: UUID?, name: String, emoji: String, colorHex: String, amountMinor: Int64, count: Int, share: Double) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.amountMinor = amountMinor
        self.count = count
        self.share = share
    }
}

public struct Bucket: Sendable, Hashable, Identifiable {
    public var start: Date
    public var incomeMinor: Int64
    public var spendMinor: Int64
    public var id: Date { start }

    public init(start: Date, incomeMinor: Int64, spendMinor: Int64) {
        self.start = start
        self.incomeMinor = incomeMinor
        self.spendMinor = spendMinor
    }
}

public struct SeriesPoint: Sendable, Hashable, Identifiable {
    public var date: Date
    public var valueMinor: Int64
    public var id: Date { date }

    public init(date: Date, valueMinor: Int64) {
        self.date = date
        self.valueMinor = valueMinor
    }
}

public struct RankedItem: Sendable, Hashable, Identifiable {
    public var name: String
    public var amountMinor: Int64
    public var count: Int
    public var id: String { name }

    public init(name: String, amountMinor: Int64, count: Int) {
        self.name = name
        self.amountMinor = amountMinor
        self.count = count
    }
}

public struct Insights: Sendable, Hashable {
    public struct BiggestExpense: Sendable, Hashable {
        public var amountMinor: Int64
        public var label: String
        public var date: Date
    }

    public struct FrequentCategory: Sendable, Hashable {
        public var name: String
        public var count: Int
    }

    public var dailyAverageMinor: Int64
    /// Only for the period containing today, after 3+ days.
    public var projectedSpendMinor: Int64?
    /// Spend change vs. the same number of days in the previous period.
    public var comparisonDeltaMinor: Int64?
    public var comparisonRatio: Double?
    public var biggestExpense: BiggestExpense?
    public var mostFrequentCategory: FrequentCategory?
    public var noSpendDays: Int
    public var elapsedDays: Int
}

public struct AnalyticsReport: Sendable {
    public enum Granularity: Sendable { case day, month }

    public var period: Period
    public var totals: Totals
    public var granularity: Granularity
    public var spendingByCategory: [CategorySlice]
    public var incomeByCategory: [CategorySlice]
    public var buckets: [Bucket]
    public var cumulativeNet: [SeriesPoint]
    public var dailySpend: [SeriesPoint]
    public var insights: Insights
    public var topPayees: [RankedItem]
    public var topTags: [RankedItem]
    public var netWorth: [SeriesPoint]

    public static func empty(_ period: Period) -> AnalyticsReport {
        AnalyticsReport(period: period, totals: Totals(), granularity: .day, spendingByCategory: [], incomeByCategory: [], buckets: [],
                        cumulativeNet: [], dailySpend: [], insights: Insights(dailyAverageMinor: 0, noSpendDays: 0, elapsedDays: 0),
                        topPayees: [], topTags: [], netWorth: [])
    }
}

/// Pure analytics maths. Every formula is in PLAN.md §7.1.
public enum AnalyticsEngine {
    public struct Input: Sendable {
        public var period: Period
        public var points: [TxnPoint]
        /// The previous period, cut to the same number of elapsed days.
        public var previousPoints: [TxnPoint]
        public var categories: [UUID: CategoryInfo]
        public var tagNames: [UUID: String]
        public var now: Date
        /// Net worth now and the cash flow of everything after the period (for the backwards series).
        public var currentNetWorthMinor: Int64
        public var cashFlowAfterPeriodMinor: Int64
        /// Recurring expenses still due in this period (from M5's rules).
        public var scheduledRemainingSpendMinor: Int64

        public init(period: Period, points: [TxnPoint], previousPoints: [TxnPoint] = [], categories: [UUID: CategoryInfo] = [:],
                    tagNames: [UUID: String] = [:], now: Date = .now, currentNetWorthMinor: Int64 = 0,
                    cashFlowAfterPeriodMinor: Int64 = 0, scheduledRemainingSpendMinor: Int64 = 0) {
            self.period = period
            self.points = points
            self.previousPoints = previousPoints
            self.categories = categories
            self.tagNames = tagNames
            self.now = now
            self.currentNetWorthMinor = currentNetWorthMinor
            self.cashFlowAfterPeriodMinor = cashFlowAfterPeriodMinor
            self.scheduledRemainingSpendMinor = scheduledRemainingSpendMinor
        }
    }

    public static func report(_ input: Input, calculator: PeriodCalculator) -> AnalyticsReport {
        let period = input.period
        let points = input.points.filter { period.contains($0.date) }
        let totals = Totals(points.map { (kind: $0.kind, amountMinor: $0.amountMinor) })
        let days = calculator.days(in: period)
        let granularity: AnalyticsReport.Granularity = days.count > 62 ? .month : .day
        let elapsed = calculator.daysElapsed(in: period, now: input.now)

        // Per-day sums.
        var spendByDay: [Int32: Int64] = [:]
        var netByDay: [Int32: Int64] = [:]
        var expenseDays = Set<Int32>()
        for point in points {
            spendByDay[point.dayKey, default: 0] += point.spendMinor
            netByDay[point.dayKey, default: 0] += point.amountMinor * point.kind.cashFlowSign
            if point.kind == .expense { expenseDays.insert(point.dayKey) }
        }

        let dailySpend = days.map { SeriesPoint(date: $0, valueMinor: spendByDay[calculator.dayKey(for: $0)] ?? 0) }
        var running: Int64 = 0
        let cumulativeNet = days.map { day -> SeriesPoint in
            running += netByDay[calculator.dayKey(for: day)] ?? 0
            return SeriesPoint(date: day, valueMinor: running)
        }

        // Net worth, walked backwards from today's value.
        var worth = input.currentNetWorthMinor - input.cashFlowAfterPeriodMinor
        var netWorth: [SeriesPoint] = []
        for day in days.reversed() {
            netWorth.append(SeriesPoint(date: day, valueMinor: worth))
            worth -= netByDay[calculator.dayKey(for: day)] ?? 0
        }
        netWorth.reverse()

        let buckets = makeBuckets(points, days: days, granularity: granularity, calculator: calculator)

        return AnalyticsReport(
            period: period,
            totals: totals,
            granularity: granularity,
            spendingByCategory: slices(points.filter { $0.kind == .expense || $0.kind == .refund }, value: \.spendMinor, categories: input.categories),
            incomeByCategory: slices(points.filter { $0.kind == .income }, value: \.amountMinor, categories: input.categories),
            buckets: buckets,
            cumulativeNet: cumulativeNet,
            dailySpend: dailySpend,
            insights: insights(input, points: points, totals: totals, elapsed: elapsed, dayCount: days.count, expenseDays: expenseDays, calculator: calculator),
            topPayees: ranked(points.filter { $0.kind == .expense && !$0.payee.isEmpty }.map { ($0.payee, $0.amountMinor) }),
            topTags: ranked(points.filter { $0.kind == .expense }.flatMap { point in point.tagIDs.compactMap { input.tagNames[$0] }.map { ($0, point.amountMinor) } }),
            netWorth: netWorth
        )
    }

    // MARK: Pieces

    /// Category totals rolled up to top-level categories, largest first. Non-positive totals
    /// (e.g. refunds exceeding spend) are dropped from the chart.
    static func slices(_ points: [TxnPoint], value: (TxnPoint) -> Int64, categories: [UUID: CategoryInfo]) -> [CategorySlice] {
        var sums: [UUID?: (amount: Int64, count: Int)] = [:]
        for point in points {
            var key = point.categoryID
            if let id = key, let parent = categories[id]?.parentID { key = parent }
            sums[key, default: (0, 0)].amount += value(point)
            sums[key, default: (0, 0)].count += 1
        }
        let positive = sums.filter { $0.value.amount > 0 }
        let total = positive.values.reduce(0) { $0 + $1.amount }
        return positive.map { id, sum in
            let info = id.flatMap { categories[$0] }
            return CategorySlice(id: id, name: info?.name ?? String(localized: "Uncategorised"), emoji: info?.emoji ?? "🏷️",
                                 colorHex: info?.colorHex ?? "#8E8E93", amountMinor: sum.amount, count: sum.count,
                                 share: total > 0 ? Double(sum.amount) / Double(total) : 0)
        }
        .sorted { $0.amountMinor != $1.amountMinor ? $0.amountMinor > $1.amountMinor : $0.name < $1.name }
    }

    static func makeBuckets(_ points: [TxnPoint], days: [Date], granularity: AnalyticsReport.Granularity, calculator: PeriodCalculator) -> [Bucket] {
        let calendar = calculator.calendar
        func bucketStart(_ date: Date) -> Date {
            switch granularity {
            case .day: calendar.startOfDay(for: date)
            case .month: calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
            }
        }
        var starts: [Date] = []
        for day in days {
            let start = bucketStart(day)
            if starts.last != start { starts.append(start) }
        }
        var income: [Date: Int64] = [:]
        var spend: [Date: Int64] = [:]
        for point in points {
            let start = bucketStart(point.date)
            if point.kind == .income { income[start, default: 0] += point.amountMinor }
            spend[start, default: 0] += point.spendMinor
        }
        return starts.map { Bucket(start: $0, incomeMinor: income[$0] ?? 0, spendMinor: spend[$0] ?? 0) }
    }

    static func insights(_ input: Input, points: [TxnPoint], totals: Totals, elapsed: Int, dayCount: Int, expenseDays: Set<Int32>,
                         calculator: PeriodCalculator) -> Insights {
        let spend = totals.netSpendMinor
        let dailyAverage = elapsed > 0 ? spend / Int64(elapsed) : 0

        var projection: Int64?
        if input.period.contains(input.now), elapsed >= 3 {
            // Spend so far + the variable (non-recurring) daily rate for the days left + bills still due.
            let variable = points.filter { !$0.isRecurring }.reduce(0) { $0 + $1.spendMinor }
            let remaining = Int64(dayCount - elapsed)
            projection = spend + variable / Int64(elapsed) * remaining + input.scheduledRemainingSpendMinor
        }

        let previousSpend = Totals(input.previousPoints.map { (kind: $0.kind, amountMinor: $0.amountMinor) }).netSpendMinor
        let hasPrevious = !input.previousPoints.isEmpty
        let delta: Int64? = hasPrevious ? spend - previousSpend : nil
        let ratio: Double? = hasPrevious && previousSpend > 0 ? Double(spend - previousSpend) / Double(previousSpend) : nil

        let biggest = points.filter { $0.kind == .expense }.max { $0.amountMinor < $1.amountMinor }.map { point in
            Insights.BiggestExpense(
                amountMinor: point.amountMinor,
                label: point.payee.isEmpty ? (point.categoryID.flatMap { input.categories[$0]?.name } ?? String(localized: "Expense")) : point.payee,
                date: point.date
            )
        }

        var counts: [UUID: Int] = [:]
        for point in points where point.kind == .expense {
            if let id = point.categoryID { counts[id, default: 0] += 1 }
        }
        let frequent = counts.max { $0.value != $1.value ? $0.value < $1.value : (input.categories[$0.key]?.name ?? "") > (input.categories[$1.key]?.name ?? "") }
            .map { Insights.FrequentCategory(name: input.categories[$0.key]?.name ?? "", count: $0.value) }

        // No-spend days: elapsed days (not counting today unless the period is over) with no expense.
        let countedDays = input.period.contains(input.now) ? max(elapsed - 1, 0) : elapsed
        let countedKeys = calculator.days(in: input.period).prefix(countedDays).map { calculator.dayKey(for: $0) }
        let noSpend = countedKeys.filter { !expenseDays.contains($0) }.count

        return Insights(dailyAverageMinor: dailyAverage, projectedSpendMinor: projection, comparisonDeltaMinor: delta, comparisonRatio: ratio,
                        biggestExpense: biggest, mostFrequentCategory: frequent, noSpendDays: noSpend, elapsedDays: elapsed)
    }

    static func ranked(_ items: [(String, Int64)], limit: Int = 5) -> [RankedItem] {
        var sums: [String: (Int64, Int)] = [:]
        for (name, amount) in items {
            sums[name, default: (0, 0)].0 += amount
            sums[name, default: (0, 0)].1 += 1
        }
        return sums.map { RankedItem(name: $0.key, amountMinor: $0.value.0, count: $0.value.1) }
            .sorted { $0.amountMinor != $1.amountMinor ? $0.amountMinor > $1.amountMinor : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
