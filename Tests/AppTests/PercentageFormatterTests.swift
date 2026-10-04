import Foundation
import Testing
@testable import App

/// One test per format, including the boundaries.
///
/// The formatter is the only thing in the app that turns a number into a
/// percentage, so these are the tests that decide what a user reads. The
/// sub-one-percent case is the one that matters most: rounding it to "0%" would
/// tell a user a day with an allocation has none.
@Suite("Percentage formatting")
struct PercentageFormatterTests {
    /// Pinned, because an assertion about wording cannot be made against
    /// whatever locale the machine running it happens to use.
    private let formatter = PercentageFormatter(locale: Locale(identifier: "en_US"))

    @Test("A whole number is shown without a decimal")
    func wholeNumbers() {
        #expect(formatter.string(40) == "40%")
        #expect(formatter.string(0) == "0%")
        #expect(formatter.string(100) == "100%")
    }

    @Test("A value of one or more rounds to the nearest whole point, up at a half")
    func roundsHalfAwayFromZero() {
        #expect(formatter.string(1.4) == "1%")
        #expect(formatter.string(1.5) == "2%")
        #expect(formatter.string(2.5) == "3%")
        #expect(formatter.string(99.5) == "100%")
    }

    @Test("A value below one keeps a decimal rather than reading as zero")
    func subOneKeepsADecimal() {
        #expect(formatter.string(0.4) == "0.4%")
        #expect(formatter.string(0.04) == "0.04%")
        #expect(formatter.string(0) == "0%")
    }

    @Test("A value too small for the first decimal gets more digits, not a zero")
    func tinyValuesGainDigits() {
        // One decimal would render this as "0.0%", which is the exact failure
        // the sub-one branch exists to prevent.
        #expect(formatter.string(0.004) == "0.004%")
    }

    @Test("A forced fraction always shows a decimal")
    func forcedFraction() {
        #expect(formatter.stringWithFraction(5) == "5.0%")
        #expect(formatter.stringWithFraction(0.25) == "0.2%")
        #expect(formatter.stringWithFraction(0.26) == "0.3%")
    }

    @Test("A figure that would round into its peer keeps a decimal instead")
    func staysDistinctFromPeer() {
        #expect(formatter.string(2.5, distinctFrom: 3) == "2.5%")
        #expect(formatter.string(2.5, distinctFrom: 2.5) == "3%")
        #expect(formatter.string(2, distinctFrom: 8) == "2%")
    }

    @Test("A signed figure says which side of the reference it is on")
    func signedFigures() {
        #expect(formatter.signedString(3.2) == "+3%")
        #expect(formatter.signedString(-3.2) == "-3%")
        #expect(formatter.signedString(0.2) == "0%")
        #expect(formatter.signedString(-0.2) == "0%")
    }

    @Test("A figure that was never measured reads as unknown, not as zero")
    func absentFigure() {
        // A limit the provider stopped reporting has no percentage, and zero would
        // be a claim about spending rather than about measurement.
        #expect(formatter.string(nil) == "—")
        #expect(formatter.string(0) == "0%")
    }

    @Test("A value that is not a number reads as unknown, not as zero")
    func notANumber() {
        #expect(formatter.string(.nan) == PercentageFormatter.unknown)
        #expect(formatter.string(.infinity) == PercentageFormatter.unknown)
        #expect(formatter.stringWithFraction(.nan) == PercentageFormatter.unknown)
        #expect(formatter.signedString(.nan) == PercentageFormatter.unknown)
    }

    @Test("The user's own decimal separator is used")
    func followsTheLocale() {
        let german = PercentageFormatter(locale: Locale(identifier: "de_DE"))
        #expect(german.stringWithFraction(0.5) == "0,5%")
        #expect(german.string(40) == "40%")
    }

    @Test("A figure outside the scale is refused rather than rendered")
    func outsideTheScale() {
        #expect(!formatter.canFormat(-1))
        #expect(!formatter.canFormat(101))
        #expect(!formatter.canFormat(.nan))
        #expect(formatter.canFormat(0))
        #expect(formatter.canFormat(100))
    }
}
