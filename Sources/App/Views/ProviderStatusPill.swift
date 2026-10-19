import Platform
import SwiftUI

/// A provider's state, as the small pill the list and the page show it in.
///
/// One view because two places draw the same words in the same shape, and a
/// pill that says "Connected" in one place and "Signed in" in another is a
/// difference a user notices without being able to name it.
struct ProviderStatusPill: View {
    let state: ProviderState

    var body: some View {
        Text(state.statusLabel)
            .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, LayoutMetrics.unit * 2)
            .padding(.vertical, LayoutMetrics.lineSpacing)
            .background(state.tint.opacity(LayoutMetrics.emptyDayOpacity * 0.3))
            .clipShape(Capsule())
            // The pill says what it says; it is not a control, and a control's
            // background would swallow the clicks meant for the row around it.
            .allowsHitTesting(false)
    }
}
