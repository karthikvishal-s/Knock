import Foundation
import SwiftData
import Testing
@testable import KnockKit

@MainActor
struct TransactionServiceTests {
    let container: ModelContainer
    let context: ModelContext
    let service: TransactionService
    let calendar: Calendar

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        self.calendar = calendar
        service = TransactionService(context: context, calculator: PeriodCalculator(calendar: calendar))
    }

    private func category(_ name: String, _ kind: CategoryKind = .expense) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name && $0.kind == kind })
    }

    private func accounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    @Test func seedsOnceAndIsIdempotent() throws {
        try Seeder.seedIfNeeded(context: context)
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        #expect(categories.filter { $0.kind == .expense }.count == Seeder.expenseCategories.count)
        #expect(categories.filter { $0.kind == .income }.count == Seeder.incomeCategories.count)
        let accounts = try accounts()
        #expect(accounts.count == 2)
        #expect(accounts.filter(\.isDefault).map(\.name) == ["Cash"])
    }

    @Test func addsWithDefaultAccountAndBumpsUsage() throws {
        let food = try category("Food")
        let entry = try service.add(TransactionDraft(kind: .expense, amount: Decimal(string: "250.5") ?? 0, categoryID: food.id, date: date(2026, 10, 19), note: "  lunch "))
        #expect(entry.amountMinor == 25_050)
        #expect(entry.dayKey == 20261019)
        #expect(entry.note == "lunch")
        #expect(entry.account?.name == "Cash")
        #expect(food.usageCount == 1)
        #expect(food.lastUsedAt != nil)
    }

    @Test func rejectsInvalidDrafts() throws {
        let salary = try category("Salary", .income)
        #expect(throws: TransactionError.invalidAmount) { try service.add(TransactionDraft(amount: 0)) }
        #expect(throws: TransactionError.invalidAmount) { try service.add(TransactionDraft(amount: Decimal(string: "0.001") ?? 0)) }
        #expect(throws: TransactionError.amountTooLarge) { try service.add(TransactionDraft(amount: Decimal(string: "2000000000") ?? 0)) }
        #expect(throws: TransactionError.categoryKindMismatch) { try service.add(TransactionDraft(kind: .expense, amount: 10, categoryID: salary.id)) }
        let cash = try accounts()[0]
        #expect(throws: TransactionError.missingTransferAccount) { try service.add(TransactionDraft(kind: .transfer, amount: 10, accountID: cash.id)) }
        #expect(throws: TransactionError.sameTransferAccount) { try service.add(TransactionDraft(kind: .transfer, amount: 10, accountID: cash.id, transferAccountID: cash.id)) }
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
    }

    @Test func refundUsesExpenseCategories() throws {
        let shopping = try category("Shopping")
        let refund = try service.add(TransactionDraft(kind: .refund, amount: 499, categoryID: shopping.id))
        #expect(refund.category?.name == "Shopping")
        #expect(refund.cashFlowMinor == 49_900)
    }

    @Test func transferHasNoCategory() throws {
        let all = try accounts()
        let food = try category("Food")
        let transfer = try service.add(TransactionDraft(kind: .transfer, amount: 1_000, categoryID: food.id, accountID: all[1].id, transferAccountID: all[0].id))
        #expect(transfer.category == nil)
        #expect(transfer.account?.name == "Bank")
        #expect(transfer.transferAccount?.name == "Cash")
        #expect(transfer.cashFlowMinor == 0)
    }

    @Test func backdatingMovesTheDayKey() throws {
        let entry = try service.add(TransactionDraft(amount: 100, date: date(2026, 10, 19)))
        var draft = TransactionDraft(entry: entry)
        draft.date = date(2026, 9, 30, 23)
        try service.update(entry, with: draft)
        #expect(entry.dayKey == 20260930)
        #expect(entry.updatedAt >= entry.createdAt)
    }

    @Test func deleteThenRestoreKeepsIdentity() throws {
        let food = try category("Food")
        let tag = LedgerTag(name: "work", colorHex: "#000000")
        context.insert(tag)
        let entry = try service.add(TransactionDraft(amount: 75, categoryID: food.id, note: "chai"))
        entry.tags = [tag]
        try context.save()
        let id = entry.id

        let deleted = try service.delete(entry)
        #expect(try service.entry(id: id) == nil)

        let restored = try service.restore(deleted)
        #expect(restored.id == id)
        #expect(restored.note == "chai")
        #expect(restored.category?.name == "Food")
        #expect(restored.tags?.map(\.name) == ["work"])
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 1)
    }

    @Test func duplicateCopiesFieldsWithNewDate() throws {
        let food = try category("Food")
        let original = try service.add(TransactionDraft(amount: 120, categoryID: food.id, date: date(2026, 10, 1), payee: "Cafe"))
        let copy = try service.duplicate(original, date: date(2026, 10, 19))
        #expect(copy.id != original.id)
        #expect(copy.payee == "Cafe")
        #expect(copy.amountMinor == 12_000)
        #expect(copy.dayKey == 20261019)
    }

    @Test func savingBumpsDataVersion() throws {
        let before = StoreEvents.dataVersion
        try service.add(TransactionDraft(amount: 1))
        #expect(StoreEvents.dataVersion != before)
    }
}
