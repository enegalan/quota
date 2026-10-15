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
                EmptyView()
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
///
/// The editor is now two things stacked: a week-shape chart that makes the ratio
/// visible at a glance, and the rows that carry the actual controls. A number on
/// a row says what a day was given; the chart says how the week feels.
struct WeeklyWeightsEditor: View {
    @Binding var weights: WeekdayWeights

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            presets
            weekChart
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                ForEach(PolicyWeekdays.all, id: \.self) { weekday in
                    HStack(spacing: LayoutMetrics.rowSpacing) {
                        weekdayMark(for: weekday)
                        Text(Self.weekdayTitle(weekday))
                            .font(.system(size: LayoutMetrics.footnoteSize))
                        Spacer(minLength: 0)
                        Stepper(
                            value: binding(for: weekday),
                            in: 0 ... PolicyWeekdays.maximumWeight,
                            step: PolicyWeekdays.weightStep
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Text(formatter.preciseString(share(for: weekday)))
                            .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: LayoutMetrics.weightColumnWidth, alignment: .trailing)
                    }
                }
            }
            Caption(text: "Days weighted zero carry no allowance. Bars show each weekday's share of the week.")
        }
        .animation(.easeInOut(duration: 0.2), value: weights)
    }

    // MARK: Presets

    /// Shortcuts to the shapes a weekly policy is most often reaching for.
    ///
    /// The domain already names these shapes (uniform and workdays only); the
    /// editor just had no way to ask for one without stepping seven times. Empty
    /// space on a week with no useful default is worse than a button that puts
    /// a standard shape one press away.
    private var presets: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            Button("Equal week") {
                weights = .uniform
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Give every weekday the same share")
            Button("Workdays only") {
                weights = .weekdaysOnly
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Weight weekdays one and weekends zero")
            Button {
                nudgeWeekends(by: 1)
            } label: {
                Label("Boost weekends", systemImage: "sun.max")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add one weight to each weekend day")
            Spacer(minLength: 0)
        }
    }

    // MARK: Week chart

    /// The week at a glance: each weekday a bar, its height that weekday's share.
    ///
    /// Normalised against the largest share rather than against 100%, because
    /// seven equal bars at a seventh of the height each would all look the same
    /// and a ratio of 2 against 1 would be invisible — which is the one thing the
    /// chart has to show that the numbers alone do not.
    private var weekChart: some View {
        HStack(alignment: .bottom, spacing: LayoutMetrics.unit) {
            ForEach(PolicyWeekdays.all, id: \.self) { weekday in
                VStack(spacing: LayoutMetrics.lineSpacing) {
                    Text(formatter.preciseString(share(for: weekday)))
                        .font(.system(size: LayoutMetrics.captionSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                            .fill(barTint(for: weekday))
                            .frame(height: barHeight(for: weekday, in: proxy.size.height))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 44)
                    Text(Self.shortWeekdayTitle(weekday))
                        .font(.system(size: LayoutMetrics.captionSize, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(LayoutMetrics.inset)
        .background(Color.primary.opacity(LayoutMetrics.barTrackOpacity))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
    }

    /// A small mark so the rows and the bars refer to the same day.
    private func weekdayMark(for weekday: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barTint(for: weekday))
            .frame(width: LayoutMetrics.unit * 2, height: LayoutMetrics.footnoteSize)
    }

    /// Colour for a day: accent for weekdays, secondary for weekends, dimmed for
    /// days weighted to nothing so an excluded day reads as excluded rather than
    /// merely low.
    private func barTint(for weekday: Int) -> Color {
        let value = weight(for: weekday)
        if value <= 0 {
            return Color.primary.opacity(LayoutMetrics.emptyDayOpacity)
        }
        return Self.isWeekend(weekday)
            ? Color.secondary
            : Color.accentColor
    }

    /// Bar height as a fraction of the tallest bar, always leaving a small
    /// pedestal so a zero-weight day is still visible as a gap in the pattern
    /// rather than as no bar at all.
    private func barHeight(for weekday: Int, in available: CGFloat) -> CGFloat {
        let shares = PolicyWeekdays.all.map { share(for: $0) }
        let tallest = shares.max() ?? 0
        guard tallest > 0 else { return LayoutMetrics.unit }
        let fraction = share(for: weekday) / tallest
        return max(LayoutMetrics.unit, available * CGFloat(fraction))
    }

    /// Adds one unit of weight to each weekend day, capping at the editor's
    /// maximum. A quick way to soften a "workdays only" policy without touching
    /// the weekdays by hand.
    private func nudgeWeekends(by amount: Int) {
        var updated: [Int: Int] = [:]
        for day in PolicyWeekdays.all {
            updated[day] = weight(for: day)
        }
        for day in PolicyWeekdays.all where Self.isWeekend(day) {
            updated[day] = min(
                PolicyWeekdays.maximumWeight,
                (updated[day] ?? PolicyWeekdays.defaultWeight) + amount
            )
        }
        if let newWeights = try? WeekdayWeights(weights: updated) {
            weights = newWeights
        }
    }

    /// A day's share of the week, as a percentage.
    private func share(for weekday: Int) -> Double {
        PolicyShare.weekday(weekday, among: weights.weights)
    }

    /// A weekday's weight, in arbitrary units.
    ///
    /// The default where the set holds no entry for that day, so a policy stored
    /// without every weekday still has a complete row to show and to edit.
    private func weight(for weekday: Int) -> Int {
        weights.weights[weekday] ?? PolicyWeekdays.defaultWeight
    }

    /// A stepper's binding onto one weekday's weight.
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

    /// A short name for the chart axis.
    private static func shortWeekdayTitle(_ weekday: Int) -> String {
        String(weekdayTitle(weekday).prefix(3))
    }

    /// Whether a PolicyWeekdays number falls on a weekend.
    ///
    /// The calendar this editor is written against numbers Sunday as 1 and
    /// Saturday as 7; the engine keys policies by that numbering, so the
    /// mark is answered here rather than by reaching into the domain's
    /// weekend test, which lives in a different module.
    private static func isWeekend(_ weekday: Int) -> Bool {
        weekday == 1 || weekday == 7
    }
}
