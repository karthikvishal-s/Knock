import Foundation

public enum DecimalConversion {
    /// Converts a `Double` from an App Intents number prompt into a `Decimal` with at most
    /// `fractionDigits` places, without binary floating-point artefacts.
    ///
    /// Goes through Swift's shortest round-trip description ("19.99", not 19.989999…), then
    /// rounds half-up (what people expect when typing money). Returns `nil` for NaN/infinity.
    public static func decimal(from value: Double, fractionDigits: Int) -> Decimal? {
        guard value.isFinite, let parsed = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var input = parsed
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, fractionDigits, .plain)
        return rounded
    }
}
