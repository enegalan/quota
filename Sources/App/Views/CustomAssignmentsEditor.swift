import Core
import SwiftUI

/// Per-date shares on a period calendar: click a day, set its %, watch the total.
///
/// Lives in the management window rather than the menu-bar popover: a month of
/// days cannot be edited usefully in a status-item panel.
///
/// The total cannot pass 100%. A custom policy is the user's own share of their
/// allowance, and a policy that asked for 150% could only be satisfied by the
/// engine scaling every day down — so the editor stops a day at the ceiling
/// rather than storing a figure the engine would have to trim. Filling a period
/// in one press is here for the same reason: with a ceiling in place, a period
/// that does not divide evenly cannot be completed by hand in any reasonable
/// number of steps.
struct CustomAssignmentsEditor: View {
    @Binding var assignments: [LocalDate: Double]
    let period: QuotaPeriod
    let calendar: Calendar
    /// The instant the calendar marks as today.
    let reference: Date

    @State private var selected: LocalDate?

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            total
            month
            if let selected {
                dayEditor(for: selected)
            } else {
                Caption(text: "Select a day to set its share of the allowance.")
            }
            actions
        }
        .onAppear {
            if selected == nil {
                selected = period.localDates(in: calendar).first
            }
        }
    }

    // MARK: Total

    /// The total, a bar of it, and the two buttons that fill or clear a period.
    ///
    /// All three in one place because they are one decision: how much of the
    /// allowance is assigned, and the two ways of answering it in a single press.
    private var total: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            HStack {
                Text("Assigned")
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                Spacer()
                Text(formatter.stringWithFraction(Share.total(assignments)))
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(totalColour)
            }
            UsageBar(value: Share.total(assignments), maximum: Share.maximumTotal)
            totalCaption
        }
    }

    /// What the total means, said once rather than left to the reader.
    @ViewBuilder
    private var totalCaption: some View {
        if overTotal {
            Caption(
                text: "More than 100% is assigned. Lower a day, or press Even.",
                isWarning: true
            )
        } else if Share.isComplete(assignments) {
            Caption(text: "Every percent of the allowance has a day.")
        } else {
            Caption(text: "\(formatter.stringWithFraction(unassigned)) still to assign.")
        }
    }

    /// How much of the allowance has no day yet.
    private var unassigned: Double {
        max(0, Share.maximumTotal - Share.total(assignments))
    }

    private var overTotal: Bool {
        Share.total(assignments) > Share.maximumTotal + Share.roundingTolerance
    }

    private var totalColour: Color {
        overTotal ? .orange : .primary
    }

    private var actions: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            Button("Even") {
                assignments = Share.even(across: days)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Give every day an equal share of the whole allowance")
            Button("Clear") {
                assignments = [:]
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(assignments.isEmpty)
            .help("Remove every assigned share")
            Spacer(minLength: 0)
        }
    }

    // MARK: Calendar

    private var month: some View {
        MonthGrid(
            calendar: calendar,
            month: period.start,
            available: daySet,
            today: LocalDate(date: reference, calendar: calendar),
            selected: selected,
            showsNavigation: true,
            monthRange: MonthRange(earliest: period.start, latest: period.end),
            showsLegend: false,
            lines: lines,
            onSelect: { selected = $0 }
        )
    }

    /// One line per day: the share it has been given, or the absence of one.
    ///
    /// An unassigned day is blank rather than "0%": a day the policy says nothing
    /// about is a day the engine will spread the remainder over, which is not the
    /// same claim as a day the user has explicitly given nothing to.
    private func lines(for date: LocalDate) -> [String] {
        let share = assignments[date]
        guard let share, share > 0 else { return [] }
        return [formatter.string(share)]
    }

    // MARK: One day

    /// The panel for the selected day: its share, and the stepper that sets
    /// it.
    ///
    /// A panel below the grid rather than controls inside a cell, so the
    /// calendar keeps drawing what the policy says and this keeps being the
    /// only place an assignment changes. That matters because this is where
    /// the 100% ceiling is enforced and where a day that cannot take more is
    /// explained; spreading it across a month of small cells would make the
    /// constraint something the user discovers by hitting it.
    ///
    /// Split out of `body` so the body reads as layout — grid, then editor,
    /// then actions — instead of as the construction of a form.
    private func dayEditor(for date: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            HStack {
                Text(date.description)
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                Spacer()
                Text(formatter.string(share(for: date)))
                    .font(.system(size: LayoutMetrics.footnoteSize))
                    .monospacedDigit()
                Stepper(
                    "",
                    value: binding(for: date),
                    in: Share.range(for: date, in: assignments),
                    step: PolicyWeekdays.dailyShareStep
                )
                .labelsHidden()
                .help("The share this day is given, up to what is left of 100%")
            }
            if ceilingForSelectedDayIsBeneathTheScale {
                Caption(text: "\(formatter.string(ceiling(for: date))) is all this day can take.")
            }
        }
        .padding(.horizontal, LayoutMetrics.inset)
        .padding(.vertical, LayoutMetrics.rowSpacing)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
    }

    /// Whether the ceiling is worth saying out loud.
    ///
    /// Only when it is lower than the whole allowance: a day that could take the
    /// lot needs no explanation, and a caption on every day of a month is a
    /// caption nobody reads.
    private var ceilingForSelectedDayIsBeneathTheScale: Bool {
        guard let selected else { return false }
        return ceiling(for: selected) < Share.maximumTotal
    }

    /// What the selected day could still be given, which is what is left of 100%
    /// after every other day.
    private func ceiling(for date: LocalDate) -> Double {
        Share.maximum(for: date, in: assignments)
    }

    /// A day's share, clamped so no press can take the policy past 100%.
    ///
    /// Clamped in the setter rather than only by the stepper's range, because the
    /// range is the control's own arithmetic and a range recomputed on each step
    /// can lag the value it is stepping. The setter is the one place every
    /// assignment passes through, so a policy that cannot exceed 100% is a
    /// property of the binding rather than a promise about a control.
    private func binding(for date: LocalDate) -> Binding<Double> {
        Binding(
            get: { share(for: date) },
            set: { newValue in
                let value = Share.clamped(newValue, for: date, in: assignments)
                var updated = assignments
                if value <= 0 {
                    updated.removeValue(forKey: date)
                } else {
                    updated[date] = value
                }
                assignments = updated
            }
        )
    }

    /// A day's assigned share, and zero where the policy assigns it none.
    ///
    /// A total rather than an optional, so everything downstream — the
    /// ceiling, the stepper's range, the running total — can be computed on
    /// it without unwrapping at every use.
    ///
    /// Absence stays absence in the stored dictionary even though it reads as
    /// zero here. A day the policy says nothing about is a day the engine
    /// will spread the remainder over, which is not the same claim as a day
    /// the user was explicitly given nothing on. Every figure the editor
    /// shows and bounds is a total either way, so nothing here has to hold
    /// the two apart.
    private func share(for date: LocalDate) -> Double {
        assignments[date] ?? 0
    }

    /// The days the period has, as a set the grid can ask about in one step.
    private var daySet: Set<LocalDate> {
        Set(days)
    }

    private var days: [LocalDate] {
        period.localDates(in: calendar)
    }
}
