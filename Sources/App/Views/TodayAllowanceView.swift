import Core
import SwiftUI

/// Today's block: the plan as a figure, the day drawn as a bar against it,
/// and the two measurements spelled out beneath.
///
/// The bar's track is the day's plan, its fill is what has been spent of it,
/// and the part of the track the fill does not reach is what remains — so the
/// plan is drawn, as the width everything is measured against, and set above
/// the bar as a figure in the same idiom the allowance card uses. The two
/// measurements are what the figures below spell out, each with its own mark
/// and small label; the plan keeps its own row because it is the only number
/// here that is not a measurement.
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
            plannedFigure
            allowanceBar
            figuresRow
        }
    }

    /// The day's plan, as a figure in the allowance card's own idiom.
    ///
    /// A value with its small label beside it, the way the allowance card sets
    /// its used and remaining pair: the plan is read against the bar beneath
    /// it, and a figure in the same idiom says the two are one question. The
    /// value keeps the day's own precision rather than the headline's whole
    /// points, because the two readings below are precise and a plan rounded
    /// differently would not add up to them.
    private var plannedFigure: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.lineSpacing) {
            Text(plannedLabel)
                .font(.system(size: LayoutMetrics.headlineFigureSize))
                .monospacedDigit()
            Text("planned")
                .font(.system(size: LayoutMetrics.footnoteSize))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Planned \(plannedLabel) for today")
    }

    /// The day's plan as a track, what has been spent as its fill.
    ///
    /// The track's full width is the planned allowance; the fill is the used
    /// share of it, tinted from green to red as the plan is consumed, and what
    /// is left of the track is what remains. A use above the plan fills the
    /// track and reads as over plan rather than spilling past it.
    private var allowanceBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(LayoutMetrics.barTrackOpacity))
                    .frame(height: LayoutMetrics.barHeight)
                if let planned, planned > 0 {
                    Capsule()
                        .fill(usedTint)
                        .frame(width: barFillWidth(in: proxy.size.width), height: LayoutMetrics.barHeight)
                }
            }
        }
        .frame(height: LayoutMetrics.barHeight)
        .accessibilityElement()
        .accessibilityLabel("Today's allowance: \(plannedLabel), \(usedLabel), \(remainingLabel)")
    }

    /// The fill width as a fraction of the track, clamped so a use above the
    /// plan fills the track rather than drawing past its end.
    private func barFillWidth(in trackWidth: CGFloat) -> CGFloat {
        guard let planned, let used, planned > 0 else { return 0 }
        return trackWidth * CGFloat(min(max(used / planned, 0), 1))
    }

    /// Used and remaining as small figures, each with its own mark.
    ///
    /// Two and not three: the plan is the figure above the bar and the bar's
    /// track, and a third figure in the row would put the measurement and the
    /// thing it is measured against side by side as though both were readings.
    private var figuresRow: some View {
        HStack(spacing: LayoutMetrics.sectionSpacing) {
            todayFigure(mark: usedTint, label: "Used", value: used)
            todayFigure(mark: .secondary, label: "Remaining", value: remaining, isEmphasis: true)
        }
    }

    /// The tint the used figure shares with the bar's fill.
    private var usedTint: Color {
        ShareTint.color(for: used, of: max(planned ?? 0, 1))
    }

    /// One figure of the row: a coloured mark, the value, and its small label.
    private func todayFigure(mark: Color, label: String, value: Double?, isEmphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            HStack(spacing: LayoutMetrics.lineSpacing) {
                Circle()
                    .fill(mark)
                    .frame(width: LayoutMetrics.menuBarMarkerSize, height: LayoutMetrics.menuBarMarkerSize)
                Text(dayFigure(value))
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: isEmphasis ? .semibold : .regular))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: LayoutMetrics.captionSize))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) \(dayFigure(value))")
    }

    /// A day's figure, with a decimal when it is not a whole point.
    private func dayFigure(_ value: Double?) -> String {
        guard let value else { return PercentageFormatter.unknown }
        return formatter.preciseString(value)
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

    private var plannedLabel: String {
        dayFigure(planned)
    }

    private var usedLabel: String {
        dayFigure(used)
    }

    private var remainingLabel: String {
        dayFigure(remaining)
    }
}

/// Pacing state, as words.
struct PacingView: View {
    let pacing: PacingStatus?

    private let formatter = PercentageFormatter()

    var body: some View {
        if let pacing {
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                Text(pacing.phase.wording)
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                    .foregroundStyle(pacing.phase.tint)
                Caption(text: figures(pacing))
            }
        }
    }

    /// The two figures the verdict is about.
    ///
    /// A verdict on its own says a pace without saying what it is a pace of. A
    /// user who has just changed plan and sees their usage at zero cannot tell
    /// from "Ahead of Pace" alone whether the app believes they have spent
    /// nothing, or believes they have spent less than it expected — and the
    /// two are very different news.
    private func figures(_ pacing: PacingStatus) -> String {
        let used = formatter.preciseString(pacing.usagePercentage)
        let planned = formatter.preciseString(pacing.expectedPercentage)
        return "\(used) used · \(planned) planned"
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
}
