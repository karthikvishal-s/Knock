import Foundation
import SwiftData

/// Everything needed to create or update a ledger entry. `Sendable`, so intents and view
/// models can build one anywhere and hand it to the service.
public struct TransactionDraft: Equatable, Sendable {
    public var kind: TransactionKind
    public var amount: Decimal
    public var currencyCode: String
    public var categoryID: UUID?
    public var accountID: UUID?
    public var transferAccountID: UUID?
    public var date: Date
    public var note: String
    public var payee: String
    public var source: TransactionSource

    public init(
        kind: TransactionKind = .expense,
        amount: Decimal = 0,
        currencyCode: String = "INR",
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        transferAccountID: UUID? = nil,
        date: Date = .now,
        note: String = "",
        payee: String = "",
        source: TransactionSource = .app
    ) {
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.accountID = accountID
        self.transferAccountID = transferAccountID
        self.date = date
        self.note = note
        self.payee = payee
        self.source = source
    }

    public init(entry: LedgerEntry) {
        self.init(
            kind: entry.kind,
            amount: entry.money.amount,
            currencyCode: entry.currencyCode,
            categoryID: entry.category?.id,
            accountID: entry.account?.id,
            transferAccountID: entry.transferAccount?.id,
            date: entry.date,
            note: entry.note,
            payee: entry.payee,
            source: entry.source
        )
    }
}

public enum TransactionError: LocalizedError, Equatable {
    case invalidAmount
    case amountTooLarge
    case categoryKindMismatch
    case missingTransferAccount
    case sameTransferAccount

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: String(localized: "Enter an amount greater than zero.")
        case .amountTooLarge: String(localized: "That amount is too large.")
        case .categoryKindMismatch: String(localized: "That category doesn't match the transaction type.")
        case .missingTransferAccount: String(localized: "Choose both accounts for a transfer.")
        case .sameTransferAccount: String(localized: "A transfer needs two different accounts.")
        }
    }
}

/// A deleted entry's contents, kept so the delete can be undone with the same identity.
public struct DeletedEntry: Equatable, Sendable {
    public let id: UUID
    public let draft: TransactionDraft
    public let createdAt: Date
    public let tagIDs: [UUID]
}

/// The single write path for ledger entries, shared by the app, intents and importers.
public struct TransactionService {
    /// ₹100 crore in paise, a sanity limit against keypad accidents.
    public static let maxAmountMinor: Int64 = 1_000_000_000 * 100

    public let context: ModelContext
    public let calculator: PeriodCalculator

    public init(context: ModelContext, calculator: PeriodCalculator = PeriodCalculator(calendar: .autoupdatingCurrent)) {
        self.context = context
        self.calculator = calculator
    }

    @discardableResult
    public func add(_ draft: TransactionDraft, id: UUID = UUID(), createdAt: Date = .now) throws -> LedgerEntry {
        let amountMinor = try validatedMinor(draft)
        let links = try resolveLinks(draft)
        let entry = LedgerEntry(id: id, kind: draft.kind, amountMinor: amountMinor, currencyCode: draft.currencyCode, date: draft.date, dayKey: calculator.dayKey(for: draft.date))
        entry.createdAt = createdAt
        entry.updatedAt = createdAt
        context.insert(entry)
        apply(draft, links, to: entry)
        if let category = entry.category {
            category.usageCount += 1
            category.lastUsedAt = max(category.lastUsedAt ?? .distantPast, .now)
        }
        try commit()
        return entry
    }

    public func update(_ entry: LedgerEntry, with draft: TransactionDraft) throws {
        let amountMinor = try validatedMinor(draft)
        let links = try resolveLinks(draft)
        entry.amountMinor = amountMinor
        entry.kind = draft.kind
        entry.currencyCode = draft.currencyCode
        entry.date = draft.date
        entry.dayKey = calculator.dayKey(for: draft.date)
        entry.updatedAt = .now
        apply(draft, links, to: entry)
        try commit()
    }

    @discardableResult
    public func delete(_ entry: LedgerEntry) throws -> DeletedEntry {
        let snapshot = DeletedEntry(id: entry.id, draft: TransactionDraft(entry: entry), createdAt: entry.createdAt, tagIDs: (entry.tags ?? []).map(\.id))
        context.delete(entry)
        try commit()
        return snapshot
    }

    @discardableResult
    public func restore(_ deleted: DeletedEntry) throws -> LedgerEntry {
        let amountMinor = try validatedMinor(deleted.draft)
        let links = try resolveLinks(deleted.draft)
        let entry = LedgerEntry(id: deleted.id, kind: deleted.draft.kind, amountMinor: amountMinor, currencyCode: deleted.draft.currencyCode, date: deleted.draft.date, dayKey: calculator.dayKey(for: deleted.draft.date))
        entry.createdAt = deleted.createdAt
        context.insert(entry)
        apply(deleted.draft, links, to: entry)
        if !deleted.tagIDs.isEmpty {
            let ids = deleted.tagIDs
            entry.tags = try context.fetch(FetchDescriptor<LedgerTag>(predicate: #Predicate { ids.contains($0.id) }))
        }
        try commit()
        return entry
    }

    /// Copies an entry, dated `date` (now by default), keeping its tags.
    @discardableResult
    public func duplicate(_ entry: LedgerEntry, date: Date = .now) throws -> LedgerEntry {
        var draft = TransactionDraft(entry: entry)
        draft.date = date
        draft.source = .app
        let copy = try add(draft)
        if let tags = entry.tags, !tags.isEmpty {
            copy.tags = tags
            try context.save()
        }
        return copy
    }

    /// The newest entry that "Repeat last" can copy (anything but a transfer).
    public func latestRepeatable() throws -> LedgerEntry? {
        let transfer = TransactionKind.transfer.rawValue
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.kindRaw != transfer }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Deletes an entry only if it was created within `window` of `now` — the confirmation
    /// snippet's Undo must not remove something old if a stale card is tapped later.
    @discardableResult
    public func deleteIfRecent(id: UUID, within window: TimeInterval = 600, now: Date = .now) throws -> Bool {
        guard let entry = try entry(id: id), now.timeIntervalSince(entry.createdAt) <= window else { return false }
        try delete(entry)
        return true
    }

    /// Income / spending totals for `period`.
    public func totals(in period: Period) throws -> Totals {
        let start = period.start, end = period.end
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        descriptor.propertiesToFetch = [\.kindRaw, \.amountMinor]
        return Totals(entries: try context.fetch(descriptor))
    }

    public func entry(id: UUID) throws -> LedgerEntry? {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Private

    private func validatedMinor(_ draft: TransactionDraft) throws -> Int64 {
        guard draft.amount > 0 else { throw TransactionError.invalidAmount }
        let minor = Money(amount: draft.amount, currencyCode: draft.currencyCode).minorUnits
        guard minor > 0 else { throw TransactionError.invalidAmount }
        guard minor <= Self.maxAmountMinor else { throw TransactionError.amountTooLarge }
        if draft.kind == .transfer {
            guard let from = draft.accountID, let to = draft.transferAccountID else { throw TransactionError.missingTransferAccount }
            guard from != to else { throw TransactionError.sameTransferAccount }
        }
        return minor
    }

    /// The relationships a draft points at, resolved and validated before anything is inserted
    /// or mutated, so a rejected draft leaves the context untouched.
    private struct Links {
        var category: LedgerCategory?
        var account: Account?
        var transferAccount: Account?
    }

    private func resolveLinks(_ draft: TransactionDraft) throws -> Links {
        var links = Links()
        if draft.kind != .transfer, let categoryID = draft.categoryID {
            let category = try fetchCategory(categoryID)
            guard category?.kind == draft.kind.categoryKind else { throw TransactionError.categoryKindMismatch }
            links.category = category
        }
        links.account = try draft.accountID.flatMap(fetchAccount) ?? defaultAccount()
        if draft.kind == .transfer {
            links.transferAccount = try draft.transferAccountID.flatMap(fetchAccount)
        }
        return links
    }

    private func apply(_ draft: TransactionDraft, _ links: Links, to entry: LedgerEntry) {
        entry.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.payee = draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.source = draft.source
        entry.category = links.category
        entry.account = links.account
        entry.transferAccount = links.transferAccount
    }

    private func fetchCategory(_ id: UUID) throws -> LedgerCategory? {
        var descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchAccount(_ id: UUID) throws -> Account? {
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func defaultAccount() throws -> Account? {
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.isDefault && !$0.isArchived })
        descriptor.fetchLimit = 1
        if let account = try context.fetch(descriptor).first { return account }
        var any = FetchDescriptor<Account>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)])
        any.fetchLimit = 1
        return try context.fetch(any).first
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}
