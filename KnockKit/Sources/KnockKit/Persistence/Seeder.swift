import Foundation
import SwiftData

/// Inserts the default categories and accounts on first launch. Safe to call every launch.
public enum Seeder {
    public struct CategorySeed: Sendable {
        public let name: String
        public let emoji: String
        public let colorHex: String
    }

    public static let expenseCategories: [CategorySeed] = [
        .init(name: "Food", emoji: "🍔", colorHex: "#FF9F0A"),
        .init(name: "Groceries", emoji: "🛒", colorHex: "#30D158"),
        .init(name: "Transport", emoji: "🚕", colorHex: "#FFD60A"),
        .init(name: "Fuel", emoji: "⛽", colorHex: "#FF6B35"),
        .init(name: "Shopping", emoji: "🛍️", colorHex: "#FF375F"),
        .init(name: "Bills", emoji: "🧾", colorHex: "#64D2FF"),
        .init(name: "Rent", emoji: "🏠", colorHex: "#BF5AF2"),
        .init(name: "Health", emoji: "💊", colorHex: "#FF453A"),
        .init(name: "Entertainment", emoji: "🎬", colorHex: "#5E5CE6"),
        .init(name: "Travel", emoji: "✈️", colorHex: "#0A84FF"),
        .init(name: "Education", emoji: "📚", colorHex: "#AC8E68"),
        .init(name: "Personal Care", emoji: "💇", colorHex: "#FF8FAB"),
        .init(name: "Gifts", emoji: "🎁", colorHex: "#E05780"),
        .init(name: "EMI / Loans", emoji: "🏦", colorHex: "#8E8E93"),
        .init(name: "Subscriptions", emoji: "🔁", colorHex: "#40C8E0"),
        .init(name: "Other", emoji: "⋯", colorHex: "#98989D"),
    ]

    public static let incomeCategories: [CategorySeed] = [
        .init(name: "Salary", emoji: "💼", colorHex: "#30D158"),
        .init(name: "Freelance", emoji: "🧑‍💻", colorHex: "#64D2FF"),
        .init(name: "Business", emoji: "🏪", colorHex: "#FF9F0A"),
        .init(name: "Interest", emoji: "🏦", colorHex: "#5E5CE6"),
        .init(name: "Dividends", emoji: "📈", colorHex: "#0A84FF"),
        .init(name: "Gifts", emoji: "🎁", colorHex: "#E05780"),
        .init(name: "Refunds", emoji: "↩️", colorHex: "#40C8E0"),
        .init(name: "Rental", emoji: "🏘️", colorHex: "#BF5AF2"),
        .init(name: "Other", emoji: "⋯", colorHex: "#98989D"),
    ]

    public static func seedIfNeeded(context: ModelContext, currencyCode: String = "INR") throws {
        var changed = false
        if try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 {
            for (index, seed) in expenseCategories.enumerated() {
                context.insert(LedgerCategory(name: seed.name, emoji: seed.emoji, colorHex: seed.colorHex, kind: .expense, sortOrder: index))
            }
            for (index, seed) in incomeCategories.enumerated() {
                context.insert(LedgerCategory(name: seed.name, emoji: seed.emoji, colorHex: seed.colorHex, kind: .income, sortOrder: index))
            }
            changed = true
        }
        if try context.fetchCount(FetchDescriptor<Account>()) == 0 {
            context.insert(Account(name: "Cash", kind: .cash, emoji: "💵", colorHex: "#34C759", currencyCode: currencyCode, sortOrder: 0, isDefault: true))
            context.insert(Account(name: "Bank", kind: .bank, emoji: "🏦", colorHex: "#0A84FF", currencyCode: currencyCode, sortOrder: 1))
            changed = true
        }
        if changed {
            try context.save()
        }
    }
}
