import Foundation
import Testing
@testable import KnockKit

struct AmountInputTests {
    private func typed(_ keys: String, fractionDigits: Int = 2) -> AmountInput {
        var input = AmountInput(fractionDigits: fractionDigits)
        for key in keys {
            switch key {
            case ".": input.appendDecimalSeparator()
            case "<": input.deleteLast()
            default: if let digit = key.wholeNumberValue { input.append(digit: digit) }
            }
        }
        return input
    }

    @Test(arguments: [
        ("250", "250"),
        ("250.5", "250.5"),
        ("250.567", "250.56"),
        ("00012", "12"),
        (".5", "0.5"),
        ("1..2", "1.2"),
        ("12<", "1"),
        ("0.<<", ""),
        ("9.<", "9"),
    ])
    func keySequences(keys: String, expected: String) {
        #expect(typed(keys).text == expected)
    }

    @Test func decimalValue() {
        #expect(typed("250.5").decimal == Decimal(string: "250.5"))
        #expect(typed("250.").decimal == 250)
        #expect(typed("").decimal == 0)
        #expect(!typed("0.0").isPositive)
        #expect(typed("0.01").isPositive)
    }

    @Test func integerDigitLimit() {
        #expect(typed("12345678901234").text == "1234567890")
    }

    @Test func zeroFractionCurrencyIgnoresSeparator() {
        #expect(typed("15.5", fractionDigits: 0).text == "155")
    }

    @Test func displayUsesLocaleGrouping() {
        let india = Locale(identifier: "en_IN")
        #expect(typed("125000.5").display(locale: india) == "1,25,000.5")
        #expect(typed("250.").display(locale: india) == "250.")
        #expect(typed("").display(locale: india) == "0")
        #expect(typed("1234.5").display(locale: Locale(identifier: "de_DE")) == "1.234,5")
    }

    @Test func startsFromExistingAmount() {
        #expect(AmountInput(amount: Decimal(string: "250.50") ?? 0).text == "250.5")
        #expect(AmountInput(amount: 0).text == "")
    }
}

struct CategoryRankingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recentUseBeatsSlightlyHigherFrequency() {
        let recent = CategoryRanking.score(usageCount: 10, lastUsedAt: now.addingTimeInterval(-3_600), now: now)
        let stale = CategoryRanking.score(usageCount: 12, lastUsedAt: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(recent > stale)
    }

    @Test func muchHigherFrequencyStillWins() {
        let heavy = CategoryRanking.score(usageCount: 200, lastUsedAt: now.addingTimeInterval(-5 * 86_400), now: now)
        let recentOnce = CategoryRanking.score(usageCount: 1, lastUsedAt: now, now: now)
        #expect(heavy > recentOnce)
    }

    @Test func unusedScoresZero() {
        #expect(CategoryRanking.score(usageCount: 0, lastUsedAt: nil, now: now) == 0)
    }

    @Test func rankedFallsBackToSortOrder() {
        let a = LedgerCategory(name: "A", emoji: "a", colorHex: "#000000", kind: .expense, sortOrder: 2)
        let b = LedgerCategory(name: "B", emoji: "b", colorHex: "#000000", kind: .expense, sortOrder: 1)
        let c = LedgerCategory(name: "C", emoji: "c", colorHex: "#000000", kind: .expense, sortOrder: 3)
        c.usageCount = 4
        c.lastUsedAt = now
        #expect(CategoryRanking.ranked([a, b, c], now: now).map(\.name) == ["C", "B", "A"])
    }
}
