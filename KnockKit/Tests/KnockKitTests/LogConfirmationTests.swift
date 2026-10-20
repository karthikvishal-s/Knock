import Foundation
import SwiftData
import Testing
@testable import KnockKit

struct LogConfirmationTests {
    let india = Locale(identifier: "en_IN")

    private func totals(spent: Int64, income: Int64 = 0) -> Totals {
        Totals([(kind: .expense, amountMinor: spent), (kind: .income, amountMinor: income)])
    }

    @Test func expenseShowsMonthSpend() {
        let c = LogConfirmation(kind: .expense, amountMinor: 25_000, currencyCode: "INR", categoryName: "Food", categoryEmoji: "🍔",
                                cycleTotals: totals(spent: 432_000), locale: india)
        #expect(c.title == "₹250.00 · 🍔 Food")
        #expect(c.subtitle == "₹4,320 spent this month")
        #expect(c.spoken == "Logged ₹250.00 for Food.")
        #expect(!c.isInflow)
    }

    @Test func refundIsGreenAndPrefixed() {
        let c = LogConfirmation(kind: .refund, amountMinor: 25_000, currencyCode: "INR", categoryName: "Shopping", categoryEmoji: "🛍️",
                                cycleTotals: totals(spent: 407_000), locale: india)
        #expect(c.title == "+₹250.00 refund · 🛍️ Shopping")
        #expect(c.isInflow)
    }

    @Test func incomeShowsMonthIncome() {
        let c = LogConfirmation(kind: .income, amountMinor: 5_000_000, currencyCode: "INR", categoryName: "Salary", categoryEmoji: "💼",
                                cycleTotals: totals(spent: 0, income: 6_200_000), locale: india)
        #expect(c.title == "+₹50,000.00 · 💼 Salary")
        #expect(c.subtitle == "₹62,000 income this month")
    }

    @Test func hiddenTotalsDropSubtitle() {
        let c = LogConfirmation(kind: .expense, amountMinor: 100, currencyCode: "INR", categoryName: nil, categoryEmoji: nil, cycleTotals: nil, locale: india)
        #expect(c.title == "₹1.00")
        #expect(c.subtitle == nil)
    }
}

@MainActor
struct QuickLogServiceTests {
    @Test func repeatAndUndoWindow() throws {
        let container = try KnockStore.makeInMemoryContainer()
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        let service = TransactionService(context: context)
        #expect(try service.latestRepeatable() == nil)

        let first = try service.add(TransactionDraft(amount: 10), createdAt: Date(timeIntervalSinceNow: -3_600))
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
        try service.add(TransactionDraft(kind: .transfer, amount: 5, accountID: accounts[0].id, transferAccountID: accounts[1].id))
        #expect(try service.latestRepeatable()?.id == first.id, "transfers aren't repeatable")

        #expect(try service.deleteIfRecent(id: first.id) == false, "older than 10 minutes")
        let fresh = try service.add(TransactionDraft(amount: 20))
        #expect(try service.deleteIfRecent(id: fresh.id) == true)
        #expect(try service.entry(id: fresh.id) == nil)
        #expect(try service.deleteIfRecent(id: UUID()) == false)
    }
}
