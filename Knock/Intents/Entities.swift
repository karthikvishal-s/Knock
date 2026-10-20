import AppIntents
import KnockKit
import SwiftData

struct CategoryEntity: AppEntity {
    let id: UUID
    let name: String
    let emoji: String
    let kind: CategoryKind

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)", subtitle: kind == .income ? "Income" : "Expense")
    }

    init(_ category: LedgerCategory) {
        id = category.id
        name = category.name
        emoji = category.emoji
        kind = category.kind
    }
}

struct CategoryQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        try IntentStore.categories(includeArchived: true).filter { identifiers.contains($0.id) }.map(CategoryEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CategoryEntity] {
        try IntentStore.categories().filter { $0.name.localizedStandardContains(string) }.map(CategoryEntity.init)
    }

    /// Likeliest first, expense categories before income.
    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        try (IntentStore.rankedCategories(.expense) + IntentStore.rankedCategories(.income)).map(CategoryEntity.init)
    }
}

struct AccountEntity: AppEntity {
    let id: UUID
    let name: String
    let emoji: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(_ account: Account) {
        id = account.id
        name = account.name
        emoji = account.emoji
    }
}

struct AccountQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        try IntentStore.accounts().filter { identifiers.contains($0.id) }.map(AccountEntity.init)
    }

    /// The default account first.
    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        try IntentStore.accounts().sorted { $0.isDefault && !$1.isDefault }.map(AccountEntity.init)
    }
}

/// Store access for intents, on the app's main context so in-app `@Query`s update immediately.
@MainActor
enum IntentStore {
    static var context: ModelContext { AppBootstrap.container.mainContext }

    static var service: TransactionService {
        TransactionService(context: context, calculator: AppSettings.shared.calculator)
    }

    static func categories(includeArchived: Bool = false) throws -> [LedgerCategory] {
        let all = try context.fetch(FetchDescriptor<LedgerCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    static func rankedCategories(_ kind: CategoryKind) throws -> [LedgerCategory] {
        CategoryRanking.ranked(try categories().filter { $0.kind == kind })
    }

    static func accounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)]))
    }

    static func currentCycleTotals() throws -> Totals {
        let settings = AppSettings.shared
        return try service.totals(in: settings.calculator.cycle(containing: .now))
    }

    static func confirmation(for entry: LedgerEntry) -> LogConfirmation {
        let totals = AppSettings.shared.showsTotalsOutsideApp ? try? currentCycleTotals() : nil
        return LogConfirmation(kind: entry.kind, amountMinor: entry.amountMinor, currencyCode: entry.currencyCode,
                               categoryName: entry.category?.name, categoryEmoji: entry.category?.emoji, cycleTotals: totals)
    }
}
