import Foundation
import SwiftData

/// Running balances (PLAN.md §7.1):
/// opening + income + refunds − expenses − transfers out + transfers in, counting only entries
/// dated on or after the account's opening date.
public enum AccountBalances {
    public struct Movement: Sendable {
        public var kind: TransactionKind
        public var amountMinor: Int64
        public var date: Date
        /// Whether the account is the destination of a transfer (vs. the source / owner).
        public var isIncomingTransfer: Bool

        public init(kind: TransactionKind, amountMinor: Int64, date: Date, isIncomingTransfer: Bool) {
            self.kind = kind
            self.amountMinor = amountMinor
            self.date = date
            self.isIncomingTransfer = isIncomingTransfer
        }
    }

    public static func balance(openingMinor: Int64, openingDate: Date, movements: [Movement]) -> Int64 {
        movements.reduce(openingMinor) { total, movement in
            guard movement.date >= openingDate else { return total }
            return total + delta(movement)
        }
    }

    /// Every account's balance in one pass over the ledger, reading only kind, amount and
    /// date. (Walking `account.entries` materialises every entry and is ~6× slower.)
    public static func compute(context: ModelContext) throws -> [UUID: Int64] {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalanceMinor) })
        let openingDates = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingDate) })
        var descriptor = FetchDescriptor<LedgerEntry>()
        descriptor.propertiesToFetch = [\.kindRaw, \.amountMinor, \.date]
        for entry in try context.fetch(descriptor) {
            if let id = entry.account?.id, entry.date >= openingDates[id] ?? .distantPast {
                balances[id, default: 0] += delta(Movement(kind: entry.kind, amountMinor: entry.amountMinor, date: entry.date, isIncomingTransfer: false))
            }
            if entry.kind == .transfer, let id = entry.transferAccount?.id, entry.date >= openingDates[id] ?? .distantPast {
                balances[id, default: 0] += entry.amountMinor
            }
        }
        return balances
    }

    public static func delta(_ movement: Movement) -> Int64 {
        switch movement.kind {
        case .income, .refund: movement.amountMinor
        case .expense: -movement.amountMinor
        case .transfer: movement.isIncomingTransfer ? movement.amountMinor : -movement.amountMinor
        }
    }
}

public struct AccountDraft: Equatable, Sendable {
    public var name: String
    public var kind: AccountKind
    public var emoji: String
    public var colorHex: String
    public var openingBalance: Decimal
    public var openingDate: Date
    public var creditLimit: Decimal?
    public var currencyCode: String

    public init(name: String = "", kind: AccountKind = .bank, emoji: String? = nil, colorHex: String = "#0A84FF",
                openingBalance: Decimal = 0, openingDate: Date = .distantPast, creditLimit: Decimal? = nil, currencyCode: String = "INR") {
        self.name = name
        self.kind = kind
        self.emoji = emoji ?? kind.defaultEmoji
        self.colorHex = colorHex
        self.openingBalance = openingBalance
        self.openingDate = openingDate
        self.creditLimit = creditLimit
        self.currencyCode = currencyCode
    }

    public init(account: Account) {
        self.init(
            name: account.name, kind: account.kind, emoji: account.emoji, colorHex: account.colorHex,
            openingBalance: Money(minorUnits: account.openingBalanceMinor, currencyCode: account.currencyCode).amount,
            openingDate: account.openingDate,
            creditLimit: account.creditLimitMinor.map { Money(minorUnits: $0, currencyCode: account.currencyCode).amount },
            currencyCode: account.currencyCode
        )
    }
}

public enum AccountError: LocalizedError, Equatable {
    case emptyName
    case lastActiveAccount

    public var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "Give the account a name.")
        case .lastActiveAccount: String(localized: "Keep at least one active account.")
        }
    }
}

public struct AccountService {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func activeAccounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)]))
    }

    public func allAccounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    @discardableResult
    public func add(_ draft: AccountDraft) throws -> Account {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AccountError.emptyName }
        let order = (try allAccounts().map(\.sortOrder).max() ?? -1) + 1
        let account = Account(name: name, kind: draft.kind, emoji: draft.emoji, colorHex: draft.colorHex, currencyCode: draft.currencyCode, sortOrder: order)
        context.insert(account)
        apply(draft, to: account)
        if try activeAccounts().count == 1 { account.isDefault = true }
        try commit()
        return account
    }

    public func update(_ account: Account, with draft: AccountDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AccountError.emptyName }
        apply(draft, to: account)
        try commit()
    }

    /// Archiving hides an account from pickers but keeps its history. The default moves on.
    public func setArchived(_ account: Account, _ archived: Bool) throws {
        if archived {
            let others = try activeAccounts().filter { $0.id != account.id }
            guard let next = others.first else { throw AccountError.lastActiveAccount }
            if account.isDefault {
                account.isDefault = false
                next.isDefault = true
            }
        }
        account.isArchived = archived
        try commit()
    }

    public func makeDefault(_ account: Account) throws {
        for other in try allAccounts() {
            other.isDefault = other.id == account.id
        }
        try commit()
    }

    public func reorder(_ ids: [UUID]) throws {
        let accounts = try allAccounts()
        for (index, id) in ids.enumerated() {
            accounts.first { $0.id == id }?.sortOrder = index
        }
        try commit()
    }

    /// One account's balance, fetching only that account's rows.
    public func balanceMinor(of account: Account) -> Int64 {
        let id = account.id
        var own = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.account?.id == id })
        own.propertiesToFetch = [\.kindRaw, \.amountMinor, \.date]
        let transfer = TransactionKind.transfer.rawValue
        var incoming = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.transferAccount?.id == id && $0.kindRaw == transfer })
        incoming.propertiesToFetch = [\.amountMinor, \.date]
        let movements = ((try? context.fetch(own)) ?? []).map {
            AccountBalances.Movement(kind: $0.kind, amountMinor: $0.amountMinor, date: $0.date, isIncomingTransfer: false)
        } + ((try? context.fetch(incoming)) ?? []).map {
            AccountBalances.Movement(kind: .transfer, amountMinor: $0.amountMinor, date: $0.date, isIncomingTransfer: true)
        }
        return AccountBalances.balance(openingMinor: account.openingBalanceMinor, openingDate: account.openingDate, movements: movements)
    }

    /// Sum of active account balances (single currency in v1).
    public func netWorthMinor() throws -> Int64 {
        let balances = try AccountBalances.compute(context: context)
        return try activeAccounts().reduce(0) { $0 + (balances[$1.id] ?? 0) }
    }

    private func apply(_ draft: AccountDraft, to account: Account) {
        account.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.kind = draft.kind
        account.emoji = draft.emoji.isEmpty ? draft.kind.defaultEmoji : draft.emoji
        account.colorHex = draft.colorHex
        account.currencyCode = draft.currencyCode
        account.openingBalanceMinor = Money(amount: draft.openingBalance, currencyCode: draft.currencyCode).minorUnits
        account.openingDate = draft.openingDate
        account.creditLimitMinor = draft.creditLimit.map { Money(amount: $0, currencyCode: draft.currencyCode).minorUnits }
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}
