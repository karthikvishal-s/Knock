import Foundation
import SwiftData

// CloudKit-ready from day one: no unique constraints, every stored property defaulted or
// optional, every relationship optional with an explicit inverse, enums stored as raw strings,
// money stored as Int64 minor units. See PLAN.md §4.

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [LedgerEntry.self, LedgerCategory.self, Account.self, LedgerTag.self, Budget.self, RecurringRule.self, SavingsGoal.self, GoalContribution.self]
    }

    @Model
    public final class LedgerEntry {
        #Index<LedgerEntry>([\.date], [\.dayKey], [\.kindRaw, \.date])

        public var id: UUID = UUID()
        public var kindRaw: String = TransactionKind.expense.rawValue
        /// Always positive; the sign comes from `kind`.
        public var amountMinor: Int64 = 0
        public var currencyCode: String = "INR"
        public var originalAmountMinor: Int64?
        public var originalCurrencyCode: String?
        public var exchangeRateString: String?
        public var date: Date = Date.now
        /// `yyyyMMdd` in the device time zone, for day grouping and the heatmap.
        public var dayKey: Int32 = 0
        public var note: String = ""
        public var payee: String = ""
        @Attribute(.externalStorage) public var receiptImage: Data?
        public var sourceRaw: String = TransactionSource.app.rawValue
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.entries)
        public var category: LedgerCategory?
        @Relationship(deleteRule: .nullify, inverse: \Account.entries)
        public var account: Account?
        @Relationship(deleteRule: .nullify, inverse: \Account.incomingTransfers)
        public var transferAccount: Account?
        @Relationship(deleteRule: .nullify, inverse: \LedgerTag.entries)
        public var tags: [LedgerTag]? = []
        @Relationship(deleteRule: .nullify, inverse: \RecurringRule.generated)
        public var recurringRule: RecurringRule?

        public init(id: UUID = UUID(), kind: TransactionKind, amountMinor: Int64, currencyCode: String, date: Date, dayKey: Int32) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.amountMinor = amountMinor
            self.currencyCode = currencyCode
            self.date = date
            self.dayKey = dayKey
        }
    }

    @Model
    public final class LedgerCategory {
        #Index<LedgerCategory>([\.kindRaw, \.sortOrder])

        public var id: UUID = UUID()
        public var name: String = ""
        public var emoji: String = "🏷️"
        public var colorHex: String = "#8E8E93"
        public var kindRaw: String = CategoryKind.expense.rawValue
        public var sortOrder: Int = 0
        public var isArchived: Bool = false
        public var usageCount: Int = 0
        public var lastUsedAt: Date?
        public var createdAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.children)
        public var parent: LedgerCategory?
        public var children: [LedgerCategory]? = []
        public var entries: [LedgerEntry]? = []
        @Relationship(deleteRule: .cascade, inverse: \Budget.category)
        public var budgets: [Budget]? = []
        public var recurringRules: [RecurringRule]? = []

        public init(id: UUID = UUID(), name: String, emoji: String, colorHex: String, kind: CategoryKind, sortOrder: Int) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.colorHex = colorHex
            self.kindRaw = kind.rawValue
            self.sortOrder = sortOrder
        }
    }

    @Model
    public final class Account {
        public var id: UUID = UUID()
        public var name: String = ""
        public var kindRaw: String = AccountKind.cash.rawValue
        public var emoji: String = "💵"
        public var colorHex: String = "#34C759"
        public var openingBalanceMinor: Int64 = 0
        public var openingDate: Date = Date.distantPast
        public var currencyCode: String = "INR"
        public var creditLimitMinor: Int64?
        public var isArchived: Bool = false
        public var isDefault: Bool = false
        public var sortOrder: Int = 0
        public var createdAt: Date = Date.now

        public var entries: [LedgerEntry]? = []
        public var incomingTransfers: [LedgerEntry]? = []
        @Relationship(deleteRule: .nullify, inverse: \SavingsGoal.linkedAccount)
        public var goals: [SavingsGoal]? = []
        @Relationship(deleteRule: .nullify, inverse: \RecurringRule.account)
        public var recurringRules: [RecurringRule]? = []
        @Relationship(deleteRule: .nullify, inverse: \RecurringRule.transferAccount)
        public var incomingRecurringRules: [RecurringRule]? = []

        public init(id: UUID = UUID(), name: String, kind: AccountKind, emoji: String, colorHex: String, currencyCode: String, sortOrder: Int, isDefault: Bool = false) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
            self.emoji = emoji
            self.colorHex = colorHex
            self.currencyCode = currencyCode
            self.sortOrder = sortOrder
            self.isDefault = isDefault
        }
    }

    @Model
    public final class LedgerTag {
        public var id: UUID = UUID()
        public var name: String = ""
        public var colorHex: String = "#8E8E93"
        public var entries: [LedgerEntry]? = []

        public init(id: UUID = UUID(), name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }
    }

    @Model
    public final class Budget {
        public var id: UUID = UUID()
        /// `nil` is the overall monthly budget.
        public var category: LedgerCategory?
        public var limitMinor: Int64 = 0
        public var rollover: Bool = false
        public var alertThresholds: [Int] = [50, 80, 100]
        public var isActive: Bool = true
        public var effectiveFrom: Date = Date.now
        public var createdAt: Date = Date.now

        public init(id: UUID = UUID(), category: LedgerCategory?, limitMinor: Int64) {
            self.id = id
            self.category = category
            self.limitMinor = limitMinor
        }
    }

    @Model
    public final class RecurringRule {
        public var id: UUID = UUID()
        public var kindRaw: String = TransactionKind.expense.rawValue
        public var amountMinor: Int64 = 0
        public var currencyCode: String = "INR"
        public var note: String = ""
        public var payee: String = ""
        @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.recurringRules)
        public var category: LedgerCategory?
        public var account: Account?
        public var transferAccount: Account?
        public var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
        public var interval: Int = 1
        public var weekdays: [Int]?
        public var dayOfMonth: Int?
        public var startDate: Date = Date.now
        public var endDate: Date?
        public var nextDueDate: Date = Date.now
        public var modeRaw: String = RecurringMode.autoPost.rawValue
        public var remindDaysBefore: Int = 0
        public var isActive: Bool = true
        public var generated: [LedgerEntry]? = []

        public init(id: UUID = UUID(), kind: TransactionKind, amountMinor: Int64, frequency: RecurrenceFrequency, startDate: Date) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.amountMinor = amountMinor
            self.frequencyRaw = frequency.rawValue
            self.startDate = startDate
            self.nextDueDate = startDate
        }
    }

    @Model
    public final class SavingsGoal {
        public var id: UUID = UUID()
        public var name: String = ""
        public var emoji: String = "🎯"
        public var colorHex: String = "#0A84FF"
        public var targetMinor: Int64 = 0
        public var targetDate: Date?
        public var isArchived: Bool = false
        public var linkedAccount: Account?
        @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
        public var contributions: [GoalContribution]? = []

        public init(id: UUID = UUID(), name: String, targetMinor: Int64) {
            self.id = id
            self.name = name
            self.targetMinor = targetMinor
        }
    }

    @Model
    public final class GoalContribution {
        public var id: UUID = UUID()
        public var amountMinor: Int64 = 0
        public var date: Date = Date.now
        public var note: String = ""
        public var goal: SavingsGoal?

        public init(id: UUID = UUID(), amountMinor: Int64, date: Date) {
            self.id = id
            self.amountMinor = amountMinor
            self.date = date
        }
    }
}
