import Foundation

/// Keypad state for typing an amount: digits, one decimal separator, a limited number of
/// fraction digits. Canonical text uses "." internally; `display(locale:)` localises it.
public struct AmountInput: Equatable, Sendable {
    public private(set) var text: String = ""
    public let fractionDigits: Int
    public let maxIntegerDigits: Int

    public init(fractionDigits: Int = 2, maxIntegerDigits: Int = 10) {
        self.fractionDigits = fractionDigits
        self.maxIntegerDigits = maxIntegerDigits
    }

    /// Starts from an existing amount (for editing). Trailing zero fractions are dropped.
    public init(amount: Decimal, fractionDigits: Int = 2, maxIntegerDigits: Int = 10) {
        self.init(fractionDigits: fractionDigits, maxIntegerDigits: maxIntegerDigits)
        guard amount > 0 else { return }
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, fractionDigits, .plain)
        text = NSDecimalNumber(decimal: rounded).stringValue
    }

    public var isEmpty: Bool { text.isEmpty }

    public var decimal: Decimal {
        Decimal(string: text.hasSuffix(".") ? String(text.dropLast()) : text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    public var isPositive: Bool { decimal > 0 }

    private var parts: (integer: Substring, fraction: Substring?) {
        let split = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        return (split.first ?? "", split.count > 1 ? split[1] : nil)
    }

    public mutating func append(digit: Int) {
        guard (0...9).contains(digit) else { return }
        let (integer, fraction) = parts
        if let fraction {
            guard fraction.count < fractionDigits else { return }
        } else {
            if integer == "0" {
                text = String(digit)
                return
            }
            guard integer.count < maxIntegerDigits else { return }
        }
        text.append(String(digit))
    }

    public mutating func appendDecimalSeparator() {
        guard fractionDigits > 0, parts.fraction == nil else { return }
        text = (text.isEmpty ? "0" : text) + "."
    }

    public mutating func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
        if text == "0" { text = "" }
    }

    public mutating func clear() {
        text = ""
    }

    /// The amount as typed, with the locale's grouping and decimal separator ("1,25,000.5").
    public func display(locale: Locale = .autoupdatingCurrent) -> String {
        let (integer, fraction) = parts
        let integerValue = Decimal(string: integer.isEmpty ? "0" : String(integer)) ?? 0
        let grouped = integerValue.formatted(.number.locale(locale).precision(.fractionLength(0)))
        guard let fraction else { return grouped }
        return grouped + (locale.decimalSeparator ?? ".") + fraction
    }
}
