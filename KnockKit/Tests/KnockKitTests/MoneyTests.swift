import Foundation
import Testing
@testable import KnockKit

struct MoneyTests {
    let india = Locale(identifier: "en_IN")

    @Test(arguments: [("INR", 2), ("inr", 2), ("JPY", 0), ("KWD", 3), ("USD", 2)])
    func minorUnitDigits(code: String, digits: Int) {
        #expect(CurrencyCatalog.minorUnitDigits(for: code) == digits)
    }

    @Test func minorUnitsRoundTrip() {
        #expect(Money(amount: Decimal(string: "250.50") ?? 0, currencyCode: "INR").minorUnits == 25_050)
        #expect(Money(minorUnits: 25_050, currencyCode: "INR").amount == Decimal(string: "250.5"))
        #expect(Money(minorUnits: 1_500, currencyCode: "JPY").amount == 1_500)
        #expect(Money(minorUnits: 1_234, currencyCode: "KWD").amount == Decimal(string: "1.234"))
    }

    @Test func minorUnitsRoundHalfUp() {
        #expect(Money(amount: Decimal(string: "0.005") ?? 0, currencyCode: "INR").minorUnits == 1)
        #expect(Money(amount: Decimal(string: "0.004") ?? 0, currencyCode: "INR").minorUnits == 0)
    }

    @Test func formatsWithLakhGrouping() {
        #expect(MoneyFormat.string(minor: 10_000_000, currencyCode: "INR", locale: india) == "₹1,00,000.00")
        #expect(MoneyFormat.string(minor: 25_050, currencyCode: "INR", locale: india, showsFraction: false) == "₹251")
    }

    @Test func formatsSigns() {
        #expect(MoneyFormat.string(minor: -25_000, currencyCode: "INR", locale: india) == "−₹250.00")
        #expect(MoneyFormat.string(minor: 25_000, currencyCode: "INR", locale: india, sign: .explicit) == "+₹250.00")
        #expect(MoneyFormat.string(minor: -25_000, currencyCode: "INR", locale: india, sign: .explicit) == "−₹250.00")
        #expect(MoneyFormat.string(minor: 0, currencyCode: "INR", locale: india, sign: .explicit) == "₹0.00")
    }

    @Test func symbol() {
        #expect(MoneyFormat.symbol(for: "INR", locale: india) == "₹")
    }

    @Test func catalogListsISOCodes() {
        #expect(CurrencyCatalog.allCodes.contains("INR"))
        #expect(CurrencyCatalog.allCodes.count > 100)
    }
}

struct TotalsTests {
    @Test func refundsReduceSpendAndTransfersAreIgnored() {
        let totals = Totals([
            (kind: .expense, amountMinor: 10_000),
            (kind: .expense, amountMinor: 5_000),
            (kind: .refund, amountMinor: 2_000),
            (kind: .income, amountMinor: 50_000),
            (kind: .transfer, amountMinor: 99_999),
        ])
        #expect(totals.netSpendMinor == 13_000)
        #expect(totals.netMinor == 37_000)
        #expect(totals.count == 4)
        #expect(totals.savingsRate == 0.74)
    }

    @Test func savingsRateNeedsIncome() {
        #expect(Totals([(kind: .expense, amountMinor: 100)]).savingsRate == nil)
        #expect(Totals([(kind: .income, amountMinor: 100), (kind: .expense, amountMinor: 300)]).savingsRate == -2)
    }
}
