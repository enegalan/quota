import Core
import SwiftUI

/// The menu bar item: what has been spent of today's allowance, out of what the
/// day planned, or a dash when there is nothing to say.
///
/// The figure is what has been used today, not what is left, because that is the
/// question the interface should answer at a glance, and the planned allowance
/// follows it as the denominator so the same number is not read as a share of
/// the whole period: 3% of a month's quota and 3% of a day's plan are the same
/// figure and very different news. The provider's own name is not shown: at that
/// size the name costs more width than it explains, and the popover is one click
/// away.
struct MenuBarLabel: View {
    let presentation: QuotaPresentation?

    private let formatter = PercentageFormatter()

    var body: some View {
        Text(text)
            .font(.system(size: LayoutMetrics.indicatorSize))
            .monospacedDigit()
    }

    /// The label as text, for the allowance the presentation carries.
    var text: String {
        Self.text(for: presentation?.summary.todayAllowance, formatter: formatter)
    }

    /// The label as text, for an allowance and a formatter.
    ///
    /// A static function rather than an inline string so the wording can be
    /// asserted without rendering, and so the two figures cannot be swapped in
    /// one place and not the other. Usage that cannot be established is a dash
    /// in the numerator and the plan is still shown, since a plan is known even
    /// when today's spending is not.
    ///
    /// The two figures are spaced apart rather than written as one fraction. At
    /// the size a menu bar item is drawn, `6%/8%` runs together into a single
    /// number the eye reads as a percentage, and the whole point of the label is
    /// that the two are separate claims: what was spent, and what the day planned.
    static func text(for allowance: TodayAllowance?, formatter: PercentageFormatter) -> String {
        guard let allowance else { return "Quota · \(PercentageFormatter.unknown)" }
        let used = allowance.usedToday.map {
            formatter.string($0, distinctFrom: allowance.suggested)
        } ?? PercentageFormatter.unknown
        return "Quota · \(used) / \(formatter.string(allowance.suggested))"
    }
}
