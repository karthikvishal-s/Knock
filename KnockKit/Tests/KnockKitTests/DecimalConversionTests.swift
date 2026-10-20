import Foundation
import Testing
@testable import KnockKit

struct DecimalConversionTests {
    @Test(arguments: [
        (19.99, "19.99"),
        (250.5, "250.5"),
        (0.1 + 0.2, "0.3"),
        (1.005, "1.01"),
        (100_000, "100000"),
        (0, "0"),
        (-42.125, "-42.13"),
        (1e-7, "0"),
        (1e16, "10000000000000000"),
    ])
    func convertsToTwoPlaces(input: Double, expected: String) throws {
        let result = try #require(DecimalConversion.decimal(from: input, fractionDigits: 2))
        #expect(result == Decimal(string: expected))
    }

    @Test func zeroFractionDigitsRoundsToWhole() throws {
        let result = try #require(DecimalConversion.decimal(from: 199.5, fractionDigits: 0))
        #expect(result == 200)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFinite(input: Double) {
        #expect(DecimalConversion.decimal(from: input, fractionDigits: 2) == nil)
    }
}
