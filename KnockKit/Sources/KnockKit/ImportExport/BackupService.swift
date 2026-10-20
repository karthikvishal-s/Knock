import Foundation
import SwiftData

/// A complete, versioned JSON copy of every record. Relationships are stored as UUIDs.
public struct KnockBackup: Codable, Sendable {
    public static let currentVersion = 1

    public struct CategoryDTO: Codable, Sendable { var id: UUID; var name, emoji, colorHex, kind: String; var sortOrder: Int; var isArchived: Bool; var usageCount: Int; var lastUsedAt: Date?; var parentID: UUID? }
    public struct AccountDTO: Codable, Sendable { var id: UUID; var name, kind, emoji, colorHex, currencyCode: String; var openingBalanceMinor: Int64; var openingDate: Date; var creditLimitMinor: Int64?; var isArchived, isDefault: Bool; var sortOrder: Int }
    public struct TagDTO: Codable, Sendable { var id: UUID; var name, colorHex: String }
    public struct EntryDTO: Codable, Sendable { var id: UUID; var kind: String; var amountMinor: Int64; var currencyCode: String; var date: Date; var dayKey: Int32; var note, payee, source: String; var createdAt, updatedAt: Date; var categoryID, accountID, transferAccountID, ruleID: UUID?; var tagIDs: [UUID]; var receipt: Data? }
    public struct BudgetDTO: Codable, Sendable { var id: UUID; var categoryID: UUID?; var limitMinor: Int64; var rollover: Bool; var thresholds: [Int]; var isActive: Bool; var effectiveFrom: Date }
    public struct RuleDTO: Codable, Sendable { var id: UUID; var kind: String; var amountMinor: Int64; var currencyCode, note, payee: String; var categoryID, accountID, transferAccountID: UUID?; var frequency: String; var interval: Int; var weekdays: [Int]?; var dayOfMonth: Int?; var startDate: Date; var endDate: Date?; var nextDueDate: Date; var mode: String; var isActive: Bool }
    public struct GoalDTO: Codable, Sendable { var id: UUID; var name, emoji, colorHex: String; var targetMinor: Int64; var targetDate: Date?; var isArchived: Bool; var accountID: UUID?; var contributions: [ContributionDTO] }
    public struct ContributionDTO: Codable, Sendable { var id: UUID; var amountMinor: Int64; var date: Date; var note: String }

    public var version: Int
    public var exportedAt: Date
    public var categories: [CategoryDTO]
    public var accounts: [AccountDTO]
    public var tags: [TagDTO]
    public var entries: [EntryDTO]
    public var budgets: [BudgetDTO]
    public var rules: [RuleDTO]
    public var goals: [GoalDTO]
}

public enum BackupError: LocalizedError {
    case unreadable
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "That file isn't a Knock backup.")
        case .newerVersion(let v): String(localized: "This backup is from a newer version of Knock (format \(v)). Update the app first.")
        }
    }
}

public enum BackupService {
    public static func makeBackup(context: ModelContext, includeReceipts: Bool = true, now: Date = .now) throws -> KnockBackup {
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let tags = try context.fetch(FetchDescriptor<LedgerTag>())
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date)]))
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
        return KnockBackup(
            version: KnockBackup.currentVersion, exportedAt: now,
            categories: categories.map { .init(id: $0.id, name: $0.name, emoji: $0.emoji, colorHex: $0.colorHex, kind: $0.kindRaw, sortOrder: $0.sortOrder,
                                               isArchived: $0.isArchived, usageCount: $0.usageCount, lastUsedAt: $0.lastUsedAt, parentID: $0.parent?.id) },
            accounts: accounts.map { .init(id: $0.id, name: $0.name, kind: $0.kindRaw, emoji: $0.emoji, colorHex: $0.colorHex, currencyCode: $0.currencyCode,
                                           openingBalanceMinor: $0.openingBalanceMinor, openingDate: $0.openingDate, creditLimitMinor: $0.creditLimitMinor,
                                           isArchived: $0.isArchived, isDefault: $0.isDefault, sortOrder: $0.sortOrder) },
            tags: tags.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
            entries: entries.map { .init(id: $0.id, kind: $0.kindRaw, amountMinor: $0.amountMinor, currencyCode: $0.currencyCode, date: $0.date, dayKey: $0.dayKey,
                                         note: $0.note, payee: $0.payee, source: $0.sourceRaw, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                                         categoryID: $0.category?.id, accountID: $0.account?.id, transferAccountID: $0.transferAccount?.id,
                                         ruleID: $0.recurringRule?.id, tagIDs: ($0.tags ?? []).map(\.id), receipt: includeReceipts ? $0.receiptImage : nil) },
            budgets: budgets.map { .init(id: $0.id, categoryID: $0.category?.id, limitMinor: $0.limitMinor, rollover: $0.rollover, thresholds: $0.alertThresholds,
                                         isActive: $0.isActive, effectiveFrom: $0.effectiveFrom) },
            rules: rules.map { .init(id: $0.id, kind: $0.kindRaw, amountMinor: $0.amountMinor, currencyCode: $0.currencyCode, note: $0.note, payee: $0.payee,
                                     categoryID: $0.category?.id, accountID: $0.account?.id, transferAccountID: $0.transferAccount?.id, frequency: $0.frequencyRaw,
                                     interval: $0.interval, weekdays: $0.weekdays, dayOfMonth: $0.dayOfMonth, startDate: $0.startDate, endDate: $0.endDate,
                                     nextDueDate: $0.nextDueDate, mode: $0.modeRaw, isActive: $0.isActive) },
            goals: goals.map { goal in .init(id: goal.id, name: goal.name, emoji: goal.emoji, colorHex: goal.colorHex, targetMinor: goal.targetMinor, targetDate: goal.targetDate,
                                             isArchived: goal.isArchived, accountID: goal.linkedAccount?.id,
                                             contributions: (goal.contributions ?? []).map { .init(id: $0.id, amountMinor: $0.amountMinor, date: $0.date, note: $0.note) }) }
        )
    }

    public static func encode(_ backup: KnockBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> KnockBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(KnockBackup.self, from: data) else { throw BackupError.unreadable }
        guard backup.version <= KnockBackup.currentVersion else { throw BackupError.newerVersion(backup.version) }
        return backup
    }

    /// Deletes every record. With `reseed`, puts the default categories and accounts back.
    public static func eraseAll(context: ModelContext, reseed: Bool = true) throws {
        try context.delete(model: GoalContribution.self)
        try context.delete(model: SavingsGoal.self)
        try context.delete(model: Budget.self)
        try context.delete(model: LedgerEntry.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: LedgerTag.self)
        try context.delete(model: LedgerCategory.self)
        try context.delete(model: Account.self)
        try context.save()
        if reseed { try Seeder.seedIfNeeded(context: context) }
        StoreEvents.bump()
    }

    /// Replaces everything with the backup's contents.
    public static func restore(_ backup: KnockBackup, context: ModelContext) throws {
        try eraseAll(context: context, reseed: false)

        var categories: [UUID: LedgerCategory] = [:]
        for dto in backup.categories {
            let category = LedgerCategory(id: dto.id, name: dto.name, emoji: dto.emoji, colorHex: dto.colorHex, kind: CategoryKind(rawValue: dto.kind) ?? .expense, sortOrder: dto.sortOrder)
            category.isArchived = dto.isArchived
            category.usageCount = dto.usageCount
            category.lastUsedAt = dto.lastUsedAt
            context.insert(category)
            categories[dto.id] = category
        }
        for dto in backup.categories { categories[dto.id]?.parent = dto.parentID.flatMap { categories[$0] } }

        var accounts: [UUID: Account] = [:]
        for dto in backup.accounts {
            let account = Account(id: dto.id, name: dto.name, kind: AccountKind(rawValue: dto.kind) ?? .other, emoji: dto.emoji, colorHex: dto.colorHex,
                                  currencyCode: dto.currencyCode, sortOrder: dto.sortOrder, isDefault: dto.isDefault)
            account.openingBalanceMinor = dto.openingBalanceMinor
            account.openingDate = dto.openingDate
            account.creditLimitMinor = dto.creditLimitMinor
            account.isArchived = dto.isArchived
            context.insert(account)
            accounts[dto.id] = account
        }

        var tags: [UUID: LedgerTag] = [:]
        for dto in backup.tags {
            let tag = LedgerTag(id: dto.id, name: dto.name, colorHex: dto.colorHex)
            context.insert(tag)
            tags[dto.id] = tag
        }

        var rules: [UUID: RecurringRule] = [:]
        for dto in backup.rules {
            let rule = RecurringRule(id: dto.id, kind: TransactionKind(rawValue: dto.kind) ?? .expense, amountMinor: dto.amountMinor,
                                     frequency: RecurrenceFrequency(rawValue: dto.frequency) ?? .monthly, startDate: dto.startDate)
            context.insert(rule)
            rule.currencyCode = dto.currencyCode
            rule.note = dto.note
            rule.payee = dto.payee
            rule.category = dto.categoryID.flatMap { categories[$0] }
            rule.account = dto.accountID.flatMap { accounts[$0] }
            rule.transferAccount = dto.transferAccountID.flatMap { accounts[$0] }
            rule.interval = dto.interval
            rule.weekdays = dto.weekdays
            rule.dayOfMonth = dto.dayOfMonth
            rule.endDate = dto.endDate
            rule.nextDueDate = dto.nextDueDate
            rule.modeRaw = dto.mode
            rule.isActive = dto.isActive
            rules[dto.id] = rule
        }

        for dto in backup.entries {
            let entry = LedgerEntry(id: dto.id, kind: TransactionKind(rawValue: dto.kind) ?? .expense, amountMinor: dto.amountMinor, currencyCode: dto.currencyCode,
                                    date: dto.date, dayKey: dto.dayKey)
            context.insert(entry)
            entry.note = dto.note
            entry.payee = dto.payee
            entry.sourceRaw = dto.source
            entry.createdAt = dto.createdAt
            entry.updatedAt = dto.updatedAt
            entry.receiptImage = dto.receipt
            entry.category = dto.categoryID.flatMap { categories[$0] }
            entry.account = dto.accountID.flatMap { accounts[$0] }
            entry.transferAccount = dto.transferAccountID.flatMap { accounts[$0] }
            entry.recurringRule = dto.ruleID.flatMap { rules[$0] }
            entry.tags = dto.tagIDs.compactMap { tags[$0] }
        }

        for dto in backup.budgets {
            let budget = Budget(id: dto.id, category: dto.categoryID.flatMap { categories[$0] }, limitMinor: dto.limitMinor)
            context.insert(budget)
            budget.rollover = dto.rollover
            budget.alertThresholds = dto.thresholds
            budget.isActive = dto.isActive
            budget.effectiveFrom = dto.effectiveFrom
        }

        for dto in backup.goals {
            let goal = SavingsGoal(id: dto.id, name: dto.name, targetMinor: dto.targetMinor)
            context.insert(goal)
            goal.emoji = dto.emoji
            goal.colorHex = dto.colorHex
            goal.targetDate = dto.targetDate
            goal.isArchived = dto.isArchived
            goal.linkedAccount = dto.accountID.flatMap { accounts[$0] }
            for item in dto.contributions {
                let contribution = GoalContribution(id: item.id, amountMinor: item.amountMinor, date: item.date)
                contribution.note = item.note
                context.insert(contribution)
                contribution.goal = goal
            }
        }

        try context.save()
        if try context.fetchCount(FetchDescriptor<Account>()) == 0 || context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 {
            try Seeder.seedIfNeeded(context: context)
        }
        StoreEvents.bump()
    }
}

/// Daily automatic JSON backups in a folder the Files app can see. Keeps the newest `keep`.
public enum AutoBackup {
    public static let folderName = "Backups"

    public static func directory(documents: URL = URL.documentsDirectory) -> URL {
        documents.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Writes today's backup if there isn't one yet. Returns the file written, if any.
    @discardableResult
    public static func performIfNeeded(context: ModelContext, directory: URL = directory(), now: Date = .now, calendar: Calendar = .current, keep: Int = 14) throws -> URL? {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let url = directory.appending(path: "knock-\(formatter.string(from: now)).json")
        var written: URL?
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try BackupService.encode(BackupService.makeBackup(context: context, now: now)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            written = url
        }
        let backups = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("knock-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) { try? fileManager.removeItem(at: old) }
        return written
    }
}
