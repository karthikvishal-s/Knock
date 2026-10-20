import SwiftData

/// App code always names the current schema's types through these aliases, so adding a
/// `SchemaV2` only means re-pointing them and adding a `MigrationStage`.
public typealias LedgerEntry = SchemaV1.LedgerEntry
public typealias LedgerCategory = SchemaV1.LedgerCategory
public typealias Account = SchemaV1.Account
public typealias LedgerTag = SchemaV1.LedgerTag
public typealias Budget = SchemaV1.Budget
public typealias RecurringRule = SchemaV1.RecurringRule
public typealias SavingsGoal = SchemaV1.SavingsGoal
public typealias GoalContribution = SchemaV1.GoalContribution

public enum KnockMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public extension LedgerEntry {
    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .app }
        set { sourceRaw = newValue.rawValue }
    }

    var money: Money { Money(minorUnits: amountMinor, currencyCode: currencyCode) }

    /// Signed contribution to net cash flow (expense negative, income/refund positive, transfer 0).
    var cashFlowMinor: Int64 { amountMinor * kind.cashFlowSign }
}

public extension LedgerCategory {
    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String { "\(emoji) \(name)" }
}

public extension Account {
    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String { "\(emoji) \(name)" }
}
