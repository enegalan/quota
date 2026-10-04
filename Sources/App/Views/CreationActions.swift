import SwiftUI

/// The buttons at the foot of the creation flow.
///
/// Its own view because the flow's own state is not what these decide: what is
/// enabled is a question about the step and what has been filled in, and keeping
/// that here means the flow says *what* may be pressed rather than rebuilding the
/// row every time one of them changes.
struct CreationActions: View {
    let step: StepTrail.Step
    let isWorking: Bool
    /// Whether the flow can move on from this step.
    let canAdvance: Bool
    /// Whether the chosen provider can still take a quota.
    let canCreate: Bool
    /// Whether the user has named the quota.
    let hasName: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: onBack)
                .disabled(step == .chooseProvider || isWorking)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
            if step == .policy {
                Button("Create Quota", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!hasName || isWorking || !canCreate)
            } else {
                Button(isWorking ? "Working…" : "Next", action: onNext)
                    .disabled(!canAdvance || isWorking)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .font(.system(size: LayoutMetrics.footnoteSize))
    }
}
