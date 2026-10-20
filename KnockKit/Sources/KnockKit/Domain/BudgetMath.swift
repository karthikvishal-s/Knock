import Foundation

/// Budget formulas (PLAN.md §7.1). All amounts in minor units.
public enum BudgetMath {
    /// Unspent budget carried into the current cycle. `previousSpends` runs oldest → newest
    /// (the cycle just before the current one last). Overspending never carries a debt.
    public static func rollover(limitMinor: Int64, previousSpends: [Int64]) -> Int64 {
        previousSpends.reduce(0) { carried, spent in max(0, limitMinor + carried - spent) }
    }

    public struct SafeToSpend: Equatable, Sendable {
        /// What you can spend per day for the rest of the cycle, today included.
        public var perDayMinor: Int64
        /// Today's allowance minus what's already been spent today. Negative = over.
        public var leftTodayMinor: Int64
        public var daysRemaining: Int
    }

    /// `available` = budget + rollover; `upcoming` = recurring bills still due this cycle.
    public static func safeToSpend(availableMinor: Int64, spentBeforeTodayMinor: Int64, spentTodayMinor: Int64,
                                   upcomingRecurringMinor: Int64, daysRemainingIncludingToday: Int) -> SafeToSpend {
        let days = max(daysRemainingIncludingToday, 1)
        let pool = max(0, availableMinor - spentBeforeTodayMinor - upcomingRecurringMinor)
        let perDay = pool / Int64(days)
        return SafeToSpend(perDayMinor: perDay, leftTodayMinor: perDay - spentTodayMinor, daysRemaining: days)
    }

    /// The highest threshold (in %) reached by `progress` that's above `alreadyAlerted`, if any.
    public static func thresholdToAlert(thresholds: [Int], progress: Double, alreadyAlerted: Int?) -> Int? {
        let percent = progress * 100
        return thresholds
            .filter { Double($0) <= percent + 0.000_1 && $0 > (alreadyAlerted ?? 0) }
            .max()
    }
}

/// One budget's state in a cycle.
public struct BudgetStatus: Identifiable, Sendable, Equatable {
    public var id: UUID
    /// `nil` for the overall budget.
    public var categoryID: UUID?
    public var name: String
    public var emoji: String
    public var colorHex: String
    public var limitMinor: Int64
    public var rolloverMinor: Int64
    public var spentMinor: Int64
    public var thresholds: [Int]

    public var availableMinor: Int64 { limitMinor + rolloverMinor }
    public var remainingMinor: Int64 { availableMinor - spentMinor }
    public var progress: Double { availableMinor > 0 ? Double(max(spentMinor, 0)) / Double(availableMinor) : (spentMinor > 0 ? 1 : 0) }
    public var isOver: Bool { spentMinor > availableMinor }
}

/// Remembers which threshold was last announced per budget per cycle, so an alert fires once.
public struct BudgetAlertLog {
    private let defaults: UserDefaults
    private let key = "budgets.alertLog"

    public init(defaults: UserDefaults = StoreLocation.sharedDefaults) {
        self.defaults = defaults
    }

    private func cycleKey(_ cycle: Period) -> String { String(Int(cycle.start.timeIntervalSince1970)) }

    public func lastAlerted(budgetID: UUID, cycle: Period) -> Int? {
        let log = defaults.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        return log[cycleKey(cycle)]?[budgetID.uuidString]
    }

    public func record(_ threshold: Int, budgetID: UUID, cycle: Period) {
        var log = defaults.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        // Keep only the current cycle's entries.
        log = log.filter { $0.key == cycleKey(cycle) }
        log[cycleKey(cycle), default: [:]][budgetID.uuidString] = threshold
        defaults.set(log, forKey: key)
    }
}
