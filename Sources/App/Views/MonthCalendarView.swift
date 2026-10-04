import AppKit
import Core
import SwiftUI

/// Month calendar, with each day classified and filled in.
///
/// The classification is the presenter's, not the view's. A view that worked out
/// "is this in the past" itself would be a second implementation of that
/// could disagree with the detail panel underneath it about the same day, and
/// the disagreement would be visible as a day that is grey in one place and not
/// in the other.
///
/// The drawing is `MonthGrid`'s, shared with the custom policy editor's calendar:
/// what a month looks like is one decision, and this view supplies only what each
/// of its days means.
struct MonthCalendarView: View {
    let presenter: CalendarPresenter
    let calendar: Calendar
    var selected: LocalDate?
    let onSelect: (LocalDate) -> Void
    var showsNavigation = false
    var showsLegend = true

    private let formatter = PercentageFormatter()

    var body: some View {
        MonthGrid(
            calendar: calendar,
            month: presenter.referenceDate,
            available: presenter.availableDates,
            today: LocalDate(date: presenter.referenceDate, calendar: calendar),
            selected: selected,
            showsNavigation: showsNavigation,
            monthRange: monthRange,
            showsLegend: showsLegend,
            legend: Self.legend,
            lines: lines,
            onSelect: onSelect
        )
    }

    /// The two figures a day carries: what was planned for it, and what was spent
    /// of it.
    ///
    /// A day with no allocation has no figure to show. The grid's own empty state
    /// says so, and a "0%" beside an unfunded day would read as a plan of nothing
    /// rather than as no plan at all.
    private func lines(for date: LocalDate) -> [String] {
        let day = presenter.day(date)
        var lines: [String] = []
        if let planned = day.planned, day.kind != .zeroAllocation {
            lines.append(formatter.string(planned))
        }
        if let actual = day.actual {
            lines.append(formatter.string(actual))
        }
        return lines
    }

    /// The months the calendar may be paged through: the plan's period.
    ///
    /// Bounded so the arrows cannot walk off either end of the period, which for a
    /// monthly quota is also the edge of the world the calendar has anything to
    /// say about.
    private var monthRange: MonthRange? {
        guard let period = presenter.period else { return nil }
        return MonthRange(earliest: period.start, latest: period.end)
    }

    /// What the grid's marks mean here.
    static let legend: [CalendarLegendItem] = [
        CalendarLegendItem(label: "Today", marker: .today),
        CalendarLegendItem(label: "Selected", marker: .selected),
        CalendarLegendItem(label: "Nothing planned", marker: .empty),
        CalendarLegendItem(label: "Outside period", marker: .outOfPeriod),
    ]
}

/// Detail for one date, as labelled figures under the calendar.
///
/// A short strip rather than a panel: the calendar is what the user is reading,
/// so the selected day's numbers sit directly under it. Each figure is a column
/// (label above value) so a narrow pane cannot wrap mid-word the way a single
/// crowded row of "Label value Label value" does.
struct DateDetailView: View {
    let day: CalendarDay
    let calendar: Calendar

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            Text(formattedDate)
                .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if day.kind == .outOfPeriod {
                Caption(text: "Outside this quota's period.")
            } else {
                HStack(alignment: .top, spacing: LayoutMetrics.sectionSpacing) {
                    figure("Planned", day.planned)
                    figure("Used", day.actual)
                    figure("Remaining", day.remaining)
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.inset)
        .padding(.vertical, LayoutMetrics.rowSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
    }

    private var formattedDate: String {
        guard let instant = day.date.date(calendar: calendar) else {
            return day.date.description
        }
        return LayoutMetrics.date(instant, template: "d MMM yyyy", calendar: calendar)
    }

    /// Draws one labelled figure of the selected day's strip.
    ///
    /// Label above value, so a narrow pane wraps between the two rather than
    /// through the middle of a figure. The unknown marker comes from the
    /// shared formatter rather than from being written here, so a day with no
    /// reading is spelled the same way as every other absent figure in the
    /// app, and monospaced digits keep the three columns of numbers aligned.
    private func figure(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            Text(label)
                .font(.system(size: LayoutMetrics.captionSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value.map(formatter.stringWithFraction) ?? PercentageFormatter.unknown)
                .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
