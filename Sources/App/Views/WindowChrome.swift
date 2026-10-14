import AppKit
import SwiftUI

/// A section of a window: a title in caps, and its content on a card.
///
/// The card is the whole point. A window whose sections are only separated by
/// blank space is a wall of text: the eye finds no grouping, so a user looking
/// for today's figures has to read everything above them to find out which part
/// of the page answers the question. One background, one radius, one inset, and
/// the sections separate themselves.
struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.titleSpacing) {
            SectionTitle(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }
}

/// The card a section or a panel is drawn on.
///
/// One modifier because the four modifiers are one decision: the inset, the
/// background, and the radius are what make a window look designed rather than
/// assembled, and a copy of the four lines at each of the ten sites they appeared
/// at is a copy that can drift. The full-width frame is not part of it, because
/// whether a card fills its column is a per-caller choice and two of the panels
/// that use this one deliberately does not.
private struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(LayoutMetrics.inset)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
    }
}

extension View {
    /// Draws this view on a card. See `CardChrome`.
    func cardChrome() -> some View {
        modifier(CardChrome())
    }
}

/// A section title, in caps.
///
/// One view for it because there were four hand-written versions of the same ten
/// words, at three different sizes and weights, which is how a window ends up
/// looking assembled rather than designed.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: LayoutMetrics.sectionTitleSize, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// The last failure, in the window's own words.
///
/// One view for it because it was written four times in three windows, once
/// without its font. A banner that is the same size in one place and a point
/// larger in another reads as two severities, and the severity is the message.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: LayoutMetrics.footnoteSize))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bar of a figure against its scale: a track, and a filled share of it.
///
/// Used for the two questions a user asks about a quota — how much of the
/// allowance is spent, and how much of today's plan is assigned — because a
/// proportion is read as a proportion. Two numbers side by side make the reader
/// do the division; a bar has already done it.
struct UsageBar: View {
    let value: Double
    let maximum: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(LayoutMetrics.barTrackOpacity))
                Capsule()
                    .fill(tint)
                    .frame(width: width(in: proxy.size.width))
            }
        }
        .frame(height: LayoutMetrics.barHeight)
        .accessibilityElement()
        .accessibilityLabel("Share")
    }

    /// The filled width, never past the end of the track.
    ///
    /// A value above the scale — a stored figure from a provider that reports
    /// more than a hundred percent, or a policy the user has typed past — would
    /// otherwise draw a capsule wider than the bar it belongs to and spill out of
    /// the row. Clamped, and tinted by the caller when being over is the point.
    private func width(in available: CGFloat) -> CGFloat {
        guard maximum > 0, value.isFinite else { return 0 }
        return available * CGFloat(min(1, max(0, value / maximum)))
    }
}

/// The colour a share-of-allowance bar is drawn in, as a continuous warning.
///
/// A share spent starts green while there is still margin before the allowance
/// is filled, and changes progressively to red as the bar fills. The hue moves
/// linearly from green to red, passing through yellow, so the colour reads as
/// "becoming warmer" as consumption increases without introducing a discrete
/// threshold.
enum ShareTint {
    /// Hue at an empty bar, where the whole allowance is still available.
    ///
    /// Green (120°) in the HSV colour space.
    static let emptyHue: Double = 0.33

    /// Hue at a full bar, where the allowance is entirely spent.
    ///
    /// Red (0°) in the HSV colour space.
    static let fullHue: Double = 0.0

    /// Saturation applied to the computed hue.
    static let saturation: Double = 0.8

    /// Brightness applied to the computed hue.
    static let brightness: Double = 0.9

    /// A neutral tint used when no share is known or the maximum is invalid.
    static let neutral: Color = .secondary

    /// The hue for a given fill fraction, clamped to the unit range.
    ///
    /// The mapping is linear from `emptyHue` (0% spent) to `fullHue` (100% spent).
    static func hue(forFillFraction fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return emptyHue + (fullHue - emptyHue) * clamped
    }

    /// The tint colour for the proportion `value` of `maximum`.
    ///
    /// If the value is unknown or `maximum` is not positive, returns `neutral`.
    static func color(for value: Double?, of maximum: Double) -> Color {
        guard let value, maximum > 0, maximum.isFinite, value.isFinite else {
            return neutral
        }
        let fraction = value / maximum
        let hueValue = hue(forFillFraction: fraction)
        return Color(hue: hueValue, saturation: saturation, brightness: brightness)
    }
}

/// A line of supporting text, and whether it should read as a warning.
///
/// Named rather than written inline at each site, because the caption is the
/// smallest piece of the interface: several views show one, and a warning that
/// one of them coloured differently is a difference a user would notice.
struct Caption: View {
    let text: String
    var isWarning = false

    /// A caption the presentation already decided the wording and the tone of.
    init(_ caption: CaptionText) {
        text = caption.text
        isWarning = caption.isWarning
    }

    init(text: String, isWarning: Bool = false) {
        self.text = text
        self.isWarning = isWarning
    }

    var body: some View {
        Text(text)
            .font(.system(size: LayoutMetrics.captionSize))
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
    }
}

/// A line of text and whether it is a warning, decided away from any view.
///
/// The pair travels together because a caller that had to pass both to two
/// different places could pass the warning to one and not the other, and then
/// say the same words in two tones.
struct CaptionText {
    let text: String
    var isWarning = false

    init(_ text: String, isWarning: Bool = false) {
        self.text = text
        self.isWarning = isWarning
    }
}

/// A titled card: a heading, the words under it, and what the reader can do.
///
/// One view because five places wrote the same card and the copies had already
/// begun to differ — a heading at one size on one screen, the message left to
/// wrap at one place and pinned open at another. A card whose title changed size
/// between screens is a difference a user notices without being able to name it.
struct NoticeCard<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            Text(title)
                .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
            Text(message)
                .font(.system(size: LayoutMetrics.footnoteSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }
}

extension NoticeCard where Actions == EmptyView {
    /// A card with nothing to do about it, which is most of them.
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

/// How much of the period is left, and how the spending is going against it.
///
/// The two facts share a line because a user reads them as one question: days
/// left is only meaningful next to whether they are behind.
struct OutlookRow: View {
    let presentation: QuotaPresentation
    let reference: Date
    let calendar: Calendar

    var body: some View {
        HStack {
            if let days = presentation.daysRemaining(asOf: reference, calendar: calendar) {
                Text("\(days) \(days == 1 ? "day" : "days") remaining")
            }
            Spacer()
            PacingView(pacing: presentation.summary.pacing)
        }
        .font(.system(size: LayoutMetrics.footnoteSize))
    }
}
