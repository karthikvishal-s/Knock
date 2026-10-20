import Foundation
import SwiftData
import Testing
@testable import KnockKit

@MainActor
struct AccountServiceTests {
    let container: ModelContainer
    let context: ModelContext
    let accounts: AccountService
    let transactions: TransactionService

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        accounts = AccountService(context: context)
        transactions = TransactionService(context: context)
    }

    @Test func balanceFormula() {
        let opening = Date(timeIntervalSince1970: 1_000)
        let movements: [AccountBalances.Movement] = [
            .init(kind: .income, amountMinor: 1_000, date: opening, isIncomingTransfer: false),
            .init(kind: .expense, amountMinor: 300, date: opening, isIncomingTransfer: false),
            .init(kind: .refund, amountMinor: 50, date: opening, isIncomingTransfer: false),
            .init(kind: .transfer, amountMinor: 200, date: opening, isIncomingTransfer: false),
            .init(kind: .transfer, amountMinor: 75, date: opening, isIncomingTransfer: true),
            .init(kind: .expense, amountMinor: 9_999, date: Date(timeIntervalSince1970: 0), isIncomingTransfer: false),
        ]
        #expect(AccountBalances.balance(openingMinor: 500, openingDate: opening, movements: movements) == 500 + 1_000 - 300 + 50 - 200 + 75)
    }

    @Test func balancesAndNetWorthIncludeTransfers() throws {
        let all = try accounts.activeAccounts()
        let cash = all[0], bank = all[1]
        try accounts.update(bank, with: { var d = AccountDraft(account: bank); d.openingBalance = 10_000; return d }())
        try transactions.add(TransactionDraft(kind: .expense, amount: 250, accountID: cash.id))
        try transactions.add(TransactionDraft(kind: .transfer, amount: 2_000, accountID: bank.id, transferAccountID: cash.id))
        try transactions.add(TransactionDraft(kind: .income, amount: 500, accountID: bank.id))

        #expect(accounts.balanceMinor(of: cash) == (2_000 - 250) * 100)
        #expect(accounts.balanceMinor(of: bank) == (10_000 - 2_000 + 500) * 100)
        #expect(try accounts.netWorthMinor() == (10_000 - 250 + 500) * 100, "transfers net to zero")
    }

    @Test func creditCardGoesNegative() throws {
        let card = try accounts.add(AccountDraft(name: "HDFC Card", kind: .creditCard, creditLimit: 100_000))
        try transactions.add(TransactionDraft(kind: .expense, amount: 4_500, accountID: card.id))
        #expect(accounts.balanceMinor(of: card) == -450_000)
        #expect(card.creditLimitMinor == 10_000_000)
        #expect(card.emoji == AccountKind.creditCard.defaultEmoji)
    }

    @Test func archivingMovesDefaultAndProtectsLastAccount() throws {
        let all = try accounts.activeAccounts()
        try accounts.setArchived(all[0], true)
        #expect(all[1].isDefault)
        #expect(!all[0].isDefault)
        #expect(throws: AccountError.lastActiveAccount) { try accounts.setArchived(all[1], true) }
        #expect(throws: AccountError.emptyName) { try accounts.add(AccountDraft(name: "  ")) }
    }
}

@MainActor
struct CategoryServiceTests {
    let container: ModelContainer
    let context: ModelContext
    let categories: CategoryService
    let transactions: TransactionService

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        categories = CategoryService(context: context)
        transactions = TransactionService(context: context)
    }

    private func named(_ name: String, _ kind: CategoryKind = .expense) throws -> LedgerCategory {
        try #require(try categories.categories(kind).first { $0.name == name })
    }

    @Test func addValidatesNamesAndAppendsToEnd() throws {
        let pets = try categories.add(CategoryDraft(name: " Pets ", emoji: "🐶", kind: .expense))
        #expect(pets.name == "Pets")
        #expect(pets.sortOrder == Seeder.expenseCategories.count)
        #expect(throws: CategoryError.duplicateName) { try categories.add(CategoryDraft(name: "food")) }
        #expect(throws: CategoryError.emptyName) { try categories.add(CategoryDraft(name: "")) }
        // Same name is fine across kinds.
        #expect(throws: Never.self) { try categories.add(CategoryDraft(name: "Food", kind: .income)) }
    }

    @Test func subCategoriesAreOneLevelDeep() throws {
        let food = try named("Food")
        let dining = try categories.add(CategoryDraft(name: "Dining out", parentID: food.id))
        #expect(dining.parent?.id == food.id)
        #expect(throws: CategoryError.invalidParent) { try categories.add(CategoryDraft(name: "Deep", parentID: dining.id)) }
        #expect(throws: CategoryError.invalidParent) { try categories.update(food, with: { var d = CategoryDraft(category: food); d.parentID = dining.id; return d }()) }
        let salary = try named("Salary", .income)
        #expect(throws: CategoryError.invalidParent) { try categories.add(CategoryDraft(name: "Mixed", kind: .expense, parentID: salary.id)) }
    }

    @Test func mergeMovesEverythingAndDeletesSource() throws {
        let food = try named("Food"), groceries = try named("Groceries")
        try transactions.add(TransactionDraft(amount: 100, categoryID: food.id))
        try transactions.add(TransactionDraft(amount: 200, categoryID: groceries.id))
        let budget = Budget(category: food, limitMinor: 5_000)
        context.insert(budget)
        try context.save()

        try categories.merge(food, into: groceries)
        #expect(try categories.categories(.expense).contains { $0.name == "Food" } == false)
        #expect(groceries.entries?.count == 2)
        #expect(groceries.usageCount == 2)
        #expect(budget.category?.id == groceries.id)
        #expect(throws: CategoryError.kindMismatch) { try categories.merge(groceries, into: try named("Salary", .income)) }
    }

    @Test func deleteOnlyWhenUnused() throws {
        let fuel = try named("Fuel"), travel = try named("Travel")
        try transactions.add(TransactionDraft(amount: 100, categoryID: fuel.id))
        #expect(throws: CategoryError.inUse) { try categories.delete(fuel) }
        try categories.delete(travel)
        #expect(try categories.categories(.expense).contains { $0.name == "Travel" } == false)
    }

    @Test func reorderAndArchive() throws {
        let ids = try categories.categories(.expense).map(\.id).reversed()
        try categories.reorder(Array(ids), kind: .expense)
        #expect(try categories.categories(.expense).map(\.id) == Array(ids))
        let first = try #require(try categories.categories(.expense).first)
        try categories.setArchived(first, true)
        #expect(try categories.categories(.expense, includeArchived: false).contains { $0.id == first.id } == false)
    }

    @Test func tagsOnDraftsAndHistoryFilter() throws {
        let tags = TagService(context: context)
        let work = try tags.findOrCreate(named: "#Work")
        #expect(work.name == "Work")
        #expect(try tags.findOrCreate(named: "work").id == work.id)
        let tagged = try transactions.add(TransactionDraft(amount: 10, tagIDs: [work.id]))
        try transactions.add(TransactionDraft(amount: 20))
        #expect(tagged.tags?.map(\.name) == ["Work"])

        var filter = HistoryFilter()
        filter.tagIDs = [work.id]
        let page = try HistoryQuery(context: context).page(before: nil, filter: filter)
        #expect(page.sections.flatMap(\.entries).map(\.id) == [tagged.id])
    }
}
