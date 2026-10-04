import Core
import SwiftUI

/// Underallocated and overallocated states, as the engine reported them.
///
/// Read from `AllocationPlan.validation` and nothing else. A view that
/// recomputed whether a plan balances would be a second implementation of the
/// engine's arithmetic, and the two would disagree first on exactly the plans a
/// user built by hand — the ones where those states are the whole point.
struct AllocationValidationView: View {
    let validation: AllocationValidation

    private let formatter = PercentageFormatter()

    var body: some View {
        switch validation {
        case .exact:
            EmptyView()
        case .underallocated(let unassigned):
            Caption(
                text: "Underallocated: \(formatter.string(unassigned)) of your quota has not been assigned.",
                isWarning: true
            )
        case .overallocated(let exceeding):
            Caption(
                text: "Overallocated by \(formatter.string(exceeding)). The days have been trimmed to fit.",
                isWarning: true
            )
        case .noEligibleDays(let retained):
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                Caption(
                    text: "Eligible days: 0. \(formatter.string(retained)) of your quota is unallocated.",
                    isWarning: true
                )
                Text("Your quota has not been discarded. Extend the period or change the policy to spend it.")
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
