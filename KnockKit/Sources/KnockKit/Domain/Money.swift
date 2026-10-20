import Foundation

/// ISO 4217 minor-unit exponents. Everything not listed uses 2.
public enum CurrencyCatalog {
    private static let zeroDigit: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    ]
    private static let threeDigit: Set<String> = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]

    public static func minorUnitDigits(for currencyCode: String) -> Int {
        let code = currencyCode.uppercased()
        if zeroDigit.contains(code) { return 0 }
        if threeDigit.contains(code) { return 3 }
        return 2
    }

    public static var allCodes: [String] {
        Locale.Currency.isoCurrencies.map(\.identifier).sorted()
    }
}

/// An exact amount of money. The only money type UI and services pass around.
public struct Money: Hashable, Sendable, Comparable {
    public var amount: Decimal
    public var currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    public init(minorUnits: Int64, currencyCode: String) {
        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        self.init(amount: Decimal(minorUnits) / Self.power(of: digits), currencyCode: currencyCode)
    }

    /// The amount in minor units (paise for INR), rounded half-up. Saturates at the Int64 range.
    public var minorUnits: Int64 {
        let digits = CurrencyCatalog.minorUnitDigits(for: currencyCode)
        var scaled = amount * Self.power(of: digits)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        if rounded >= Decimal(Int64.max) { return .max }
        if rounded <= Decimal(Int64.min) { return .min }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.amount < rhs.amount }

    private static func power(of digits: Int) -> Decimal {
        var result: Decimal = 1
        for _ in 0..<digits { result *= 10 }
        return result
    }
}

public enum MoneyFormat {
    public enum Sign: Sendable {
        /// "₹250.00"
        case none
        /// "−₹250.00" / "+₹250.00"
        case explicit
    }

    /// Formats money for display. INR in an Indian locale gets lakh grouping (₹1,00,000.00).
    public static func string(_ money: Money, locale: Locale = .autoupdatingCurrent, sign: Sign = .none, showsFraction: Bool = true) -> String {
        let digits = showsFraction ? CurrencyCatalog.minorUnitDigits(for: money.currencyCode) : 0
        let style = Decimal.FormatStyle.Currency(code: money.currencyCode, locale: locale)
            .precision(.fractionLength(digits))
            .rounded(rule: .toNearestOrAwayFromZero)
        let magnitude = (money.amount < 0 ? -money.amount : money.amount).formatted(style)
        switch sign {
        case .none:
            return money.amount < 0 ? "−" + magnitude : magnitude
        case .explicit:
            if money.amount == 0 { return magnitude }
            return (money.amount < 0 ? "−" : "+") + magnitude
        }
    }

    public static func string(minor: Int64, currencyCode: String, locale: Locale = .autoupdatingCurrent, sign: Sign = .none, showsFraction: Bool = true) -> String {
        string(Money(minorUnits: minor, currencyCode: currencyCode), locale: locale, sign: sign, showsFraction: showsFraction)
    }

    /// The currency symbol for a code in a locale, e.g. "₹".
    public static func symbol(for currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.currencySymbol ?? currencyCode
    }
}
