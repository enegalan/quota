import Core
import SwiftUI

/// Today's block: planned, used, and remaining, shown as a bar first and as
/// figures beside it, so the proportion is read rather than worked out.
///
/// The bar's track is the day's plan, its fill is what has been spent of it,
/// and the part of the track the fill does not reach is what remains. Each
/// figure keeps its own mark and small label so the three numbers cannot be
/// confused even when the block is read at a glance.
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
            allowanceBar
            figuresRow
        }
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

    /// Planned, used, remaining as small figures, each with its own mark.
    private var figuresRow: some View {
        HStack(spacing: LayoutMetrics.sectionSpacing) {
            todayFigure(mark: .secondary, label: "Planned", value: planned)
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
}
