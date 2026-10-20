import Foundation

/// What a ledger entry does to your money. Stored as `LedgerEntry.kindRaw`.
public enum TransactionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case expense
    case income
    /// A credit against spending (refund, cashback). Reduces expense totals.
    case refund
    /// Money moved between two of your own accounts. Never counts as income or expense.
    case transfer

    public var id: String { rawValue }

    /// Which category list applies, or `nil` for transfers (no category).
    public var categoryKind: CategoryKind? {
        switch self {
        case .expense, .refund: .expense
        case .income: .income
        case .transfer: nil
        }
    }

    /// Sign applied to the amount for net cash flow.
    public var cashFlowSign: Int64 {
        switch self {
        case .expense: -1
        case .income, .refund: 1
        case .transfer: 0
        }
    }
}

public enum CategoryKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case expense
    case income

    public var id: String { rawValue }
}

public enum AccountKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case cash
    case bank
    case creditCard
    case upiWallet
    case savings
    case other

    public var id: String { rawValue }

    public var defaultEmoji: String {
        switch self {
        case .cash: "💵"
        case .bank: "🏦"
        case .creditCard: "💳"
        case .upiWallet: "📱"
        case .savings: "🐷"
        case .other: "👛"
        }
    }
}

/// Where an entry was captured. Intents can't tell Back Tap from Shortcuts, so both are `.shortcut`.
public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case app
    case shortcut
    case siri
    case widget
    case control
    case recurring
    case importFile
}

public enum RecurrenceFrequency: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum RecurringMode: String, Codable, Sendable, CaseIterable {
    case autoPost
    case remind
}
