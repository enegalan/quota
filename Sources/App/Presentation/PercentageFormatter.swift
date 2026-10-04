import Core
import Foundation

/// The one place a percentage becomes text.
///
/// Every view formats percentages through this type, so a plan figure and a
/// reading cannot end up with different precision on the same screen, and so the
/// rounding rule is a decision that can be tested rather than one that is
/// re-invented in each view.
///
/// Percentages are shown to the nearest whole point. A provider reports usage
/// with two decimals, and a figure quoted to a hundredth of a percent of a
/// month's allowance is a precision the underlying data does not support: one
/// refresh moves a monthly number by more than that. Where a value is small
/// enough that rounding would erase it, a decimal is shown instead, so a 0.4%
/// allocation reads as "0.4%" rather than "0%" — a day with a real allocation
/// must not read as a day with none.
struct PercentageFormatter: Sendable {
    /// Usage is a share of an allowance, so the top of the scale is the
    /// domain's, not a number this file chose.
    static let percentageScale: Double = UsageConstants.percentageScale

    private let scale: Double
    private let fractionDigits: Int
    private let locale: Locale

    /// - Parameters:
    ///   - scale: the top of the scale, which is also the largest value the
    ///     formatter will render.
    ///   - fractionDigits: digits after the point when a decimal is shown.
    ///   - locale: whose conventions to use. The user's, so a decimal comma is a
    ///     decimal comma for them; pinned in tests, because an assertion about
    ///     wording cannot be made without fixing it.
    init(
        scale: Double = PercentageFormatter.percentageScale,
        fractionDigits: Int = PercentageFormatting.defaultFractionDigits,
        locale: Locale = .current
    ) {
        self.scale = scale
        self.fractionDigits = fractionDigits
        self.locale = locale
    }

    /// A percentage, rounded to the nearest whole point unless rounding would
    /// erase it.
    ///
    /// Rounds half away from zero, so 0.5 shows as "1%" rather than "0%": a
    /// provider that has met half its allowance should not read as having met
    /// none of it.
    func string(_ value: Double) -> String {
        guard value.isFinite else { return Self.unknown }
        guard abs(value) < PercentageFormatting.wholePointThreshold, value != 0 else {
            return "\(Int(value.rounded()))%"
        }
        return "\(smallDecimal(value))%"
    }

    /// A percentage that may not have been measured.
    ///
    /// The figure is absent for two reasons that look the same on screen — a
    /// quota whose limit the provider has stopped reporting, and one never read
    /// at all — and both print a dash. Neither is zero: a zero reads as a
    /// measurement of nothing spent, which is a claim no reading here supports.
    func string(_ value: Double?) -> String {
        guard let value else { return Self.unknown }
        return string(value)
    }

    /// A percentage that always shows a decimal.
    ///
    /// For the places where a day-to-day difference is the point and a rounded
    /// figure would hide it, such as the detail panel for one date.
    func stringWithFraction(_ value: Double) -> String {
        guard value.isFinite else { return Self.unknown }
        return "\(decimal(value, digits: fractionDigits))%"
    }

    /// A percentage that stays visibly different from a peer when the raw values
    /// differ.
    ///
    /// Independent whole-point rounding of related figures — remaining against
    /// planned, for a day's allowance — can collapse a real difference into the
    /// same reading: 2.5% and 3% both become "3%", and a day that has already
    /// been spent then reads as untouched. When that would happen, the figure
    /// keeps a decimal instead.
    func string(_ value: Double, distinctFrom peer: Double) -> String {
        let rendered = string(value)
        guard value.isFinite, peer.isFinite, value != peer else { return rendered }
        guard rendered == string(peer) else { return rendered }
        return stringWithFraction(value)
    }

    /// A percentage and its sign, for figures that may be above or below a
    /// reference: how far ahead of, or behind, the plan a quota is.
    func signedString(_ value: Double) -> String {
        guard value.isFinite else { return Self.unknown }
        let rounded = value.rounded()
        guard rounded != 0 else { return string(0) }
        return rounded > 0 ? "+\(Int(rounded))%" : "-\(Int(abs(rounded)))%"
    }

    /// A small value with enough digits to be non-zero.
    ///
    /// Digits are added one at a time until the rendering stops being zero,
    /// rather than jumping to a fixed count: 0.04% needs two decimals and 0.004%
    /// needs three, and a single choice of "extra digits" would be wrong for
    /// whichever of the two it was not tuned to. A value that would still read as
    /// zero at the cap is shown at the cap — a long string of zeros is more honest
    /// than a rounded one that implies precision the data has not got.
    private func smallDecimal(_ value: Double) -> String {
        let cap = PercentageFormatting.maximumSmallValueDigits
        for digits in fractionDigits ... cap {
            let rendered = decimal(value, digits: digits)
            let shifted = abs(value) * pow(PercentageFormatting.decimalScale, Double(digits))
            if shifted >= PercentageFormatting.halfUnit {
                return rendered
            }
        }
        return decimal(value, digits: PercentageFormatting.maximumSmallValueDigits)
    }

    /// A number with a fixed count of fraction digits, in the user's locale.
    ///
    /// `NumberFormatStyle` rather than `String(format:)`, because the decimal
    /// separator is the user's and not the process's: a `String(format:)`
    /// result puts a period in front of the digits of a Dutch or German user,
    /// where that reads as a different number entirely.
    private func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(digits))
                .locale(locale)
        )
    }

    /// What is shown when a figure is not a number at all.
    ///
    /// A dash rather than "0%": absence of a reading is not a reading of zero,
    /// and the two are different claims.
    static let unknown = "—"

    /// Whether a figure can be shown as a percentage.
    ///
    /// Guards against a stored file holding something outside the scale, which
    /// the domain rejects on the way in but a hand-edited file might not.
    func canFormat(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= scale
    }
}
