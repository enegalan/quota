import Foundation

/// How Quota turns a number into text.
///
/// The guard's rule is that tunables are declared in a `*Constants.swift` file,
/// and these are tunables: change one and every figure in the app changes with
/// it. They live here rather than on the formatter so that the rounding rule is
/// one decision, stated once, instead of a set of literals a formatter happens
/// to use today.
enum PercentageFormatting {
    /// The base a decimal place shifts by.
    static let decimalScale: Double = 10

    /// The point at which a rendering counts as non-zero.
    ///
    /// The last digit shown is worth half of its own place, so 0.5 at one decimal
    /// rounds to a rendered 1 and anything below it renders as 0.
    static let halfUnit: Double = 0.5

    /// The most digits a value too small to show may be given.
    ///
    /// Beyond this, a figure is smaller than a provider can meaningfully report,
    /// and saying so at four decimals is more useful than a fifth would be.
    static let maximumSmallValueDigits: Int = 4

    /// The digits a value below `wholePointThreshold` is shown with at first.
    static let defaultFractionDigits: Int = 1

    /// Below this, a whole-point rendering would say "0%" for something that is
    /// not nothing.
    static let wholePointThreshold: Double = 1
}

/// The weekday numbers a policy's weights are keyed by.
///
/// `Calendar` numbers them 1 through 7 with 1 as Sunday, and the app writes
/// policies against that numbering rather than its own, so a policy means the same
/// thing in a calendar this app did not choose.
enum PolicyWeekdays {
    /// The first weekday a `Calendar` uses.
    static let first = 1
    /// One past the last, so the range covers every day.
    static let last = 8
    /// How many days a week has.
    static let count = last - first

    /// Every weekday number, in calendar order.
    static var all: [Int] {
        Array(first ..< last)
    }

    /// The largest weight the editor offers.
    ///
    /// Far below what the domain accepts, because a share of a daily allowance
    /// above a few tens has stopped describing a preference and started being a
    /// rounding error on the other days.
    static let maximumWeight = 10

    /// How much one press of the stepper moves a weight.
    static let weightStep = 1

    /// The largest per-date share the custom editor accepts, as a percentage.
    ///
    /// A day's share of a monthly allowance is a small number; a cap of the whole
    /// scale keeps the stepper from being able to express a day that spends more
    /// than the quota has, which the engine would only have to trim.
    static let maximumDailyShare: Double = 100

    /// How much one press of the custom editor's stepper moves a share.
    static let dailyShareStep: Double = 1

    /// The weight a weekday the editor has never been shown carries.
    ///
    /// One, matching the domain's own fallback, so a partial specification means
    /// "these days count more" rather than "every other day is excluded".
    static let defaultWeight = 1
}
