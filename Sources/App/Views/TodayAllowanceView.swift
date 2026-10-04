import Core
import SwiftUI

/// Today's block: planned, used, and remaining, labelled so they cannot be
/// confused.
///
/// The three labels are the whole point of the block. requires actual usage
/// and planned allocation to stay separate in the interface, and a block that
/// showed three bare numbers would leave the reader to guess which was which —
/// so each line carries its own word and the planned line is marked as a plan
/// rather than a measurement.
///
/// All three figures come from the same `TodayAllowance`. Remaining is derived
/// as planned minus used there, not recomputed beside a live usage reading that
/// could disagree with a remaining figure baked earlier.
struct TodayAllowanceView: View {
    let presentation: QuotaPresentation
    /// Whether the block names itself.
    ///
    /// It has to in the popover, where it stands alone, and must not inside a
    /// titled card, where a second heading for the same section is a heading
    /// twice.
    var showsTitle = true

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.titleSpacing) {
            if showsTitle {
                SectionTitle("Today")
            }
            row(label: "Planned", value: planned)
            row(label: "Used", value: used)
            row(label: "Remaining", value: remaining, isEmphasis: true)
        }
    }

    /// One labelled figure of the block.
    ///
    /// Extracted because the three lines differ in only three ways — their
    /// label, their figure, and whether the last of them is emphasised — and
    /// writing the row out three times in the body would make a change to the
    /// block's typography three edits in three places.
    ///
    /// Formatting is all that happens here. The figures arrive from the
    /// presentation already derived, so this stays a way of setting type
    /// around a number the engine computed rather than a second place where a
    /// number is worked out.
    private func row(label: String, value: Double?, isEmphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: LayoutMetrics.footnoteSize))
            Spacer()
            Text(dayFigure(value))
                .font(.system(size: LayoutMetrics.footnoteSize, weight: isEmphasis ? .semibold : .regular))
                .monospacedDigit()
        }
    }

    /// A day's figure, with a decimal when it is not a whole point.
    ///
    /// Whole-point rounding of used and remaining separately would break the
    /// identity the block claims: 0.8 used of a 3 plan is 2.2 remaining, and
    /// rendering that remainder as "2%" leaves three lines that no longer add.
    private func dayFigure(_ value: Double?) -> String {
        guard let value else { return PercentageFormatter.unknown }
        if value.rounded() == value {
            return formatter.string(value)
        }
        return formatter.stringWithFraction(value)
    }

    private var planned: Double? {
        presentation.summary.todayAllowance?.suggested
    }

    private var used: Double? {
        presentation.summary.todayAllowance?.usedToday
    }

    private var remaining: Double? {
        presentation.summary.todayAllowance?.remainingAfterToday
    }
}

/// Pacing state, as words.
///
/// The engine's phase, rendered rather than recomputed: a view that worked out
/// the phase itself would be a second implementation of that could disagree
/// with the first, and the disagreement would show as a user being told they
/// are behind pace by a view rather than by their own usage.
struct PacingView: View {
    let pacing: PacingStatus?

    var body: some View {
        if let pacing {
            Text(pacing.phase.wording)
                .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                .foregroundStyle(pacing.phase.tint)
        }
    }
}

/// How a pacing phase is worded and coloured, in one place.
///
/// Here rather than by the engine because `PacingStatus` says a user is behind
/// pace; how that reads is the interface's decision, and a second source for it
/// would be somewhere the two could disagree.
///
/// Only behind and exhausted alarm. Being ahead of pace is good news and an
/// expired period is simply over, so tinting those as problems would mark a
/// large share of a careful user's months as failures.
extension PacingStatus.Phase {
    /// What the phase is called.
    var wording: String {
        switch self {
        case .onTrack: "On Pace"
        case .ahead: "Ahead of Pace"
        case .behind: "Behind Pace"
        case .exhausted: "Quota Exhausted"
        case .expired: "Period Expired"
        }
    }

    /// The tint for text naming the phase.
    var tint: Color {
        switch self {
        case .onTrack, .ahead, .expired: .secondary
        case .behind: .orange
        case .exhausted: .red
        }
    }

    /// The tint for a bar measuring share spent.
    ///
    /// A share spent is drawn in the accent colour while it is ordinary and
    /// alarms in the same colours as the phase it is in, so a quota that has run
    /// out is the same red in a list row as it is beside its own label. Exhausted
    /// was orange here and red there, which is the kind of difference a user
    /// reads as two different states.
    var usageTint: Color {
        switch self {
        case .onTrack, .ahead: .accentColor
        case .behind: .orange
        case .exhausted: .red
        case .expired: .secondary
        }
    }
}
