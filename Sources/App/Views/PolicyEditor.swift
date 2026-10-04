import Core
import SwiftUI

/// One policy editor for all three policy kinds.
///
/// The selector chooses the kind and the editor below edits whichever kind is
/// chosen — even has nothing to fill in, weekly has seven weights, and custom has
/// one figure per date. Three separate editors would be three screens to navigate
/// between to change one thing, and a user moving from "spread it evenly" to
/// "weekends are different" would have to start again rather than adjust.
///
/// Custom editing needs the period's dates so each day can be assigned a share.
struct PolicyEditor: View {
    @Binding var policy: AllocationPolicy
    let period: QuotaPeriod
    var calendar: Calendar = .current
    /// The instant the custom editor's calendar marks as today.
    var reference = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            Picker("Policy", selection: $policy) {
                Text("Even").tag(AllocationPolicy.even)
                Text("Weekly").tag(AllocationPolicy.weekly(weekdayWeights: .uniform))
                Text("Custom").tag(AllocationPolicy.custom(assignments: [:]))
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch policy {
            case .even:
                Caption(text: policy.summary)
            case .weekly:
                WeeklyWeightsEditor(weights: weightsBinding)
            case .custom:
                CustomAssignmentsEditor(
                    assignments: customBinding,
                    period: period,
                    calendar: calendar,
                    reference: reference
                )
            }
        }
    }

    /// The weights, as a binding that keeps the policy's shape.
    ///
    /// Reading through the policy rather than holding a copy, so the editor cannot
    /// show weights the policy does not have, and choosing a new kind is one
    /// assignment to `policy` rather than a migration between stored values.
    private var weightsBinding: Binding<WeekdayWeights> {
        Binding(
            get: {
                if case .weekly(let weights) = policy {
                    return weights
                }
                return .uniform
            },
            set: { policy = .weekly(weekdayWeights: $0) }
        )
    }

    private var customBinding: Binding<[LocalDate: Double]> {
        Binding(
            get: {
                if case .custom(let assignments) = policy {
                    return assignments
                }
                return [:]
            },
            set: { policy = .custom(assignments: $0) }
        )
    }
}

/// Weekly weights: one emphasis per weekday, in the user's calendar order.
///
/// Weights are integers in arbitrary units — Monday 2 and Tuesday 1 means Monday
/// gets twice the share — so the editor moves them in whole steps and shows the
/// ratio they add up to. The ratio is shown because "2" means nothing on its own,
/// and computed here because it is a restatement of what the user is editing
/// rather than a plan figure: the plan itself still comes from the engine, which
/// normalises against the days actually in the period.
struct WeeklyWeightsEditor: View {
    @Binding var weights: WeekdayWeights

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            ForEach(PolicyWeekdays.all, id: \.self) { weekday in
                HStack {
                    Text(Self.weekdayTitle(weekday))
                        .font(.system(size: LayoutMetrics.footnoteSize))
                    Spacer()
                    Stepper(
                        value: binding(for: weekday),
                        in: 0 ... PolicyWeekdays.maximumWeight,
                        step: PolicyWeekdays.weightStep
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                    Text(formatter.string(share(for: weekday)))
                        .font(.system(size: LayoutMetrics.footnoteSize))
                        .monospacedDigit()
                        .frame(width: LayoutMetrics.weightColumnWidth, alignment: .trailing)
                }
            }
        }
    }

    /// A day's share of the week, as a percentage.
    private func share(for weekday: Int) -> Double {
        PolicyShare.weekday(weekday, among: weights.weights)
    }

    /// A weekday's weight, in arbitrary units.
    ///
    /// The default where the set holds no entry for that day, so a policy
    /// stored without every weekday still has a complete row to show and to
    /// edit. Substituting zero instead would draw a missing day as
    /// emphatically unweighted, and would quietly take it out of the ratio
    /// the editor prints beside the stepper.
    private func weight(for weekday: Int) -> Int {
        weights.weights[weekday] ?? PolicyWeekdays.defaultWeight
    }

    /// A stepper's binding onto one weekday's weight.
    ///
    /// Every edit rebuilds the whole set rather than assigning a single key,
    /// because `WeekdayWeights` is a value the domain validates as a unit. An
    /// edit that only replaced the day being pressed would have to assume the
    /// other six are already right, and the stepper is the one place that
    /// assumption would be made without anyone making it.
    ///
    /// Reconstruction is also what lets the guards below run on the value the
    /// domain is about to see rather than on a single key the guards cannot
    /// judge. How a set of weights adds up is still the domain's to normalise
    /// against the days actually in the period; this binding only has to keep
    /// the shape legal.
    private func binding(for weekday: Int) -> Binding<Int> {
        Binding(
            get: { weight(for: weekday) },
            set: { newValue in
                var updated: [Int: Int] = [:]
                for day in PolicyWeekdays.all {
                    updated[day] = weight(for: day)
                }
                updated[weekday] = newValue
                // An all-zero set has no ratio and the domain rejects it, so a
                // user zeroing the last day is held at the previous value rather
                // than left with a policy that cannot be planned.
                if updated.values.allSatisfy({ $0 == 0 }) {
                    updated[weekday] = newValue + PolicyWeekdays.weightStep
                }
                // A typo-free fallback: every weekday the editor does not show
                // keeps a weight of one, matching the domain's own default.
                weights = (try? WeekdayWeights(weights: updated)) ?? weights
            }
        )
    }

    /// A weekday's name, in the user's calendar.
    private static func weekdayTitle(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.weekdaySymbols[safe: weekday - 1] ?? ""
    }
}
