import Foundation

/// Income, net spending and net cash flow for a set of entries, in minor units.
/// Refunds reduce spending; transfers are excluded. See PLAN.md §7.1.
public struct Totals: Equatable, Sendable {
    public var incomeMinor: Int64 = 0
    public var expenseMinor: Int64 = 0
    public var refundMinor: Int64 = 0
    public var count: Int = 0

    public init() {}

    public init<S: Sequence>(_ items: S) where S.Element == (kind: TransactionKind, amountMinor: Int64) {
        for item in items {
            add(kind: item.kind, amountMinor: item.amountMinor)
        }
    }

    public init(entries: [LedgerEntry]) {
        self.init(entries.lazy.map { (kind: $0.kind, amountMinor: $0.amountMinor) })
    }

    public mutating func add(kind: TransactionKind, amountMinor: Int64) {
        switch kind {
        case .expense: expenseMinor += amountMinor
        case .income: incomeMinor += amountMinor
        case .refund: refundMinor += amountMinor
        case .transfer: return
        }
        count += 1
    }

    /// Expenses minus refunds. Can be negative if refunds exceed spending.
    public var netSpendMinor: Int64 { expenseMinor - refundMinor }

    /// Income minus net spending.
    public var netMinor: Int64 { incomeMinor - netSpendMinor }

    /// `net / income`, or `nil` when there's no income.
    public var savingsRate: Double? {
        guard incomeMinor > 0 else { return nil }
        return Double(netMinor) / Double(incomeMinor)
    }
}
