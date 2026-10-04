import SwiftUI

/// A creation flow's steps, as a numbered trail with the current one marked.
///
/// Its own view rather than a corner of the flow, because numbering is a decision
/// of its own: which step is number two depends on the steps that apply, and a
/// flow that kept that arithmetic in a loop would have to recompute it every time
/// it drew. The trail takes the steps that apply and which one is current, and
/// knows how to number them.
struct StepTrail: View {
    /// One step of creating a quota.
    ///
    /// `CaseIterable` only so the raw values are available for a case that is
    /// missing from a trail, which a switch over the visible steps has to be
    /// able to name even when it can only be reached by a bug.
    enum Step: String, CaseIterable, Hashable {
        case chooseProvider
        case install
        case connect
        case policy

        var title: String {
            switch self {
            case .chooseProvider: "Choose Provider"
            case .install: "Install"
            case .connect: "Connect"
            case .policy: "Policy"
            }
        }
    }

    /// The steps to show, in order, already reduced to those that apply.
    let steps: [Step]
    let current: Step

    var body: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                item(step, number: index + 1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Draws one numbered step of the trail.
    ///
    /// Extracted so the body's loop says what the trail is, a list of steps
    /// in order, and leaves the badge, its alignment and the accessibility
    /// label that has to repeat the number to someone who cannot see it to
    /// the one place that builds them. The label is the reason it cannot stay
    /// in the loop: the number belongs to the caller's index, so "step
    /// \(number)" is only composable where the number is.
    private func item(_ step: Step, number: Int) -> some View {
        let isCurrent = step == current
        return HStack(spacing: LayoutMetrics.lineSpacing) {
            Text("\(number)")
                .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                .frame(width: LayoutMetrics.stepNumberSize, height: LayoutMetrics.stepNumberSize)
                .background(isCurrent ? Color.accentColor : Color.clear)
                .clipShape(Circle())
            Text(step.title)
                .font(.system(
                    size: LayoutMetrics.footnoteSize,
                    weight: isCurrent ? .semibold : .regular
                ))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), step \(number)\(isCurrent ? ", current" : "")")
    }
}
