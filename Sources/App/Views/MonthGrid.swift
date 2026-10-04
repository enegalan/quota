import Core
import SwiftUI

/// A month of days, selectable, navigable, and marked for today and selection.
///
/// Shared by every calendar in the app. The plan's calendar and the custom
/// policy editor differ in what a day *means* and in what happens when it is
/// clicked; they do not differ in how a month is drawn, how a day says it is
/// today, or what it looks like when the pointer is over it, and a second
/// implementation of any of those would be a second thing to keep in step.
struct MonthGrid: View {
    let calendar: Calendar
    let month: Date
    let available: Set<LocalDate>
    var today: LocalDate?
    var selected: LocalDate?
    var showsNavigation = true
    var monthRange: MonthRange?
    var showsLegend = true
    var legend: [CalendarLegendItem] = []
    let lines: (LocalDate) -> [String]
    let onSelect: (LocalDate) -> Void

    @State private var visibleMonth: Date?
    @State private var hoveredDay: LocalDate?

    var body: some View {
        let layout = MonthLayout.month(containing: shown, calendar: calendar)
        VStack(alignment: .leading, spacing: LayoutMetrics.titleSpacing) {
            if showsNavigation {
                navigation
            }
            grid(layout)
            if showsLegend, !legend.isEmpty {
                CalendarLegend(items: legend)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            visibleMonth = initialMonth
        }
        .onChange(of: selected) { _, newValue in
            // A selection made elsewhere — a day listed under the grid, a month
            // the user paged back to — has to bring the grid with it, or the
            // selected day is on a page the user cannot see.
            guard let newValue, let date = newValue.date(calendar: calendar) else { return }
            guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return }
            if MonthLayout.monthStart(of: shown, calendar: calendar) != start {
                visibleMonth = date
            }
        }
    }

    /// The month actually drawn, falling back to the one asked for before the
    /// grid has appeared.
    private var shown: Date {
        visibleMonth ?? month
    }

    /// Prefer the selected day's month, then the caller's month.
    private var initialMonth: Date {
        if let selected, let date = selected.date(calendar: calendar) {
            return date
        }
        return month
    }

    // MARK: Navigation

    /// The controls, with every paging decision already made.
    ///
    /// What the bar draws and which months it is allowed to offer are two
    /// different questions, and both halves live here so that a bound taken from
    /// the period cannot end up stated twice, in two rules that drift apart.
    private var navigation: some View {
        MonthNavigationBar(
            calendar: calendar,
            months: monthsInRange,
            shown: shown,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            showsToday: showsTodayButton,
            onShift: shiftMonth,
            onChoose: choose(month:),
            onToday: jumpToToday
        )
    }

    /// A month chosen from the menu or the picker.
    ///
    /// Written as a function so what the bar is handed is a named decision rather
    /// than an assignment buried in an argument list.
    private func choose(month: Date) {
        visibleMonth = month
    }

    /// Every month start inside the period, so the menu never offers a blank page.
    private var monthsInRange: [Date] {
        guard let range = monthRange else { return [] }
        guard var current = MonthLayout.monthStart(of: range.earliest, calendar: calendar),
              let end = MonthLayout.monthStart(of: range.latest, calendar: calendar)
        else { return [] }
        var months: [Date] = []
        while current <= end {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return months
    }

    /// Whether the previous month holds any day the user can act on.
    ///
    /// A period is a span, and a calendar that could be paged a year past its
    /// end would show month after month of greyed-out cells — navigation that
    /// can only ever lead somewhere useless.
    private var canGoBack: Bool {
        guard let range = monthRange,
              let shown = MonthLayout.monthStart(of: shown, calendar: calendar) else { return true }
        guard let earliest = MonthLayout.monthStart(of: range.earliest, calendar: calendar) else { return true }
        return shown > earliest
    }

    /// Whether a later month inside the period exists to page to.
    ///
    /// The mirror of `canGoBack`, and the reason the two are separate
    /// properties rather than one signed bound: they are read by different
    /// buttons, and a single comparison would leave each caller deciding
    /// which end of the range it was standing at.
    private var canGoForward: Bool {
        guard let range = monthRange,
              let shown = MonthLayout.monthStart(of: shown, calendar: calendar) else { return true }
        guard let latest = MonthLayout.monthStart(of: range.latest, calendar: calendar) else { return true }
        return shown < latest
    }

    /// Today is offered only when it sits in the period and is not already shown.
    private var showsTodayButton: Bool {
        guard let today, let todayDate = today.date(calendar: calendar) else { return false }
        if let range = monthRange {
            guard todayDate >= range.earliest, todayDate <= range.latest else { return false }
        }
        return MonthLayout.monthStart(of: shown, calendar: calendar) != MonthLayout.monthStart(
            of: todayDate,
            calendar: calendar
        )
    }

    /// Shows today's month, leaving the selection alone.
    ///
    /// Moves the page only. The button is a navigation control, and a user
    /// who pages forward to look at a later date must not find the selection
    /// dragged along with them; when the panel above also wants today
    /// selected, that is its decision to make through `onSelect`.
    private func jumpToToday() {
        guard let today, let todayDate = today.date(calendar: calendar) else { return }
        visibleMonth = todayDate
    }

    /// Pages by whole months from wherever the grid has been taken to.
    ///
    /// Offset from the month on screen rather than from the caller's `month`,
    /// so repeated clicks walk away from where the user is instead of
    /// snapping back to the month they started on. Which directions are
    /// offered is the bar's decision, so all this has to refuse is a calendar
    /// that cannot represent the month it was asked for.
    private func shiftMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: shown) else { return }
        visibleMonth = next
    }

    // MARK: Grid

    private var dayColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: LayoutMetrics.calendarMinDayWidth),
                spacing: LayoutMetrics.unit
            ),
            count: DateConstants.daysInWeek
        )
    }

    /// The seven day columns, with the weekday header as their first row.
    ///
    /// The header is emitted inside the grid rather than stacked above it so
    /// the initials share the columns' own flexible widths: in a window too
    /// narrow for seven days, letters and days stay in column instead of the
    /// header becoming a row of centred labels over a grid that has already
    /// wrapped.
    ///
    /// Takes the layout rather than deriving one, because the caller has
    /// already walked the month to find the first of it. A second walk here
    /// would be the same answer computed twice, with no way to compare the
    /// two for drift.
    ///
    /// Trailing blanks are appended because a `LazyVGrid` row shorter than
    /// seven cells draws short, which would leave the last week of every
    /// month sitting against the left edge under a full row.
    private func grid(_ layout: MonthLayout) -> some View {
        let days = cells(in: layout)
        let columns = DateConstants.daysInWeek
        return LazyVGrid(columns: dayColumns, spacing: LayoutMetrics.unit) {
            ForEach(Array(Self.weekdayInitials(in: calendar).enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.system(size: LayoutMetrics.captionSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(0 ..< days.count, id: \.self) { index in
                cell(days[index])
            }
            // Trailing blanks so the last week still fills seven columns.
            let trailing = (columns - (days.count % columns)) % columns
            ForEach(0 ..< trailing, id: \.self) { offset in
                emptyCell
                    .id("trailing-\(offset)")
            }
        }
    }

    /// The month's cells, the blanks that precede the first of it included.
    ///
    /// The blanks come first so the first of the month lands in the column its
    /// weekday is in, which is the whole reason a calendar handed a different
    /// first weekday has to be able to pad.
    private func cells(in layout: MonthLayout) -> [MonthGridDay] {
        let blanks = (0 ..< layout.leadingBlankCount).map { MonthGridDay.blank(at: $0) }
        let days = layout.days.enumerated().map { offset, date in
            MonthGridDay(
                position: layout.leadingBlankCount + offset,
                date: date,
                isAvailable: available.contains(date),
                lines: available.contains(date) ? lines(date) : []
            )
        }
        return blanks + days
    }

    /// One cell: the day's number, whatever the caller chose to say about
    /// it, and the states that day can be in.
    ///
    /// A blank carries no date and is drawn as `emptyCell`, so the two cases
    /// are erased to `AnyView` here rather than in the grid. This is the only
    /// place the view loses its return type, and keeping the cost to one
    /// function is what makes the rest of the file worth reading as ordinary
    /// SwiftUI.
    ///
    /// Today and selected share one weight deliberately: a day that is both
    /// is still one day, and marking them separately would make the calendar
    /// look as though it had two days marked. Unavailable days are disabled
    /// rather than hidden, because the gap a missing day leaves is itself
    /// information about where the period's edges fall.
    private func cell(_ day: MonthGridDay) -> some View {
        guard let date = day.date else { return AnyView(emptyCell) }
        let isSelected = date == selected
        let isToday = date == today
        return AnyView(
            Button {
                onSelect(date)
            } label: {
                VStack(spacing: LayoutMetrics.lineSpacing) {
                    Text("\(date.day)")
                        .font(.system(
                            size: LayoutMetrics.footnoteSize,
                            weight: isToday || isSelected ? .semibold : .regular
                        ))
                    ForEach(Array(day.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: LayoutMetrics.captionSize))
                            .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: LayoutMetrics.calendarDayHeight)
                .background(background(for: date, isSelected: isSelected))
                .foregroundStyle(dayForeground(day))
                .overlay(selectionRing(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!day.isAvailable)
            .onHover { hovering in
                hoveredDay = hovering ? date : nil
            }
            .help(day.isAvailable ? date.description : "\(date.description) is outside the period")
            .accessibilityLabel(date.description)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        )
    }

    /// Readable on dark and light windows: funded days at full strength, empty
    /// days softer, out-of-period days dimmer still — never near-invisible.
    private func dayForeground(_ day: MonthGridDay) -> Color {
        if !day.isAvailable {
            return Color.primary.opacity(LayoutMetrics.outOfPeriodOpacity)
        }
        if day.lines.isEmpty {
            return Color.primary.opacity(LayoutMetrics.emptyDayOpacity)
        }
        return Color.primary
    }

    /// A cell with nothing in it, holding the month's shape.
    ///
    /// Present at the start of a month that does not open on the first weekday,
    /// and at the tail of a short one, so that every day sits in the column its
    /// own weekday falls in.
    private var emptyCell: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: LayoutMetrics.calendarDayHeight)
    }

    /// The tint behind a cell, at most one of them.
    ///
    /// A single chain rather than a stack of modifiers, because these are
    /// competing claims on one small square: today, the selection, and the
    /// pointer can all be true at once, and layering them would compound the
    /// opacities into a colour nobody chose. Today wins because it is a fact
    /// about the day rather than something the user just did; hover loses
    /// because it is the weakest of the three and must never be the reason a
    /// real state goes unshown.
    /// Tints rather than fills, so they sit under the selection ring and
    /// under the day's own figures instead of replacing them.
    @ViewBuilder
    private func background(for date: LocalDate, isSelected: Bool) -> some View {
        if date == today {
            Color.accentColor.opacity(LayoutMetrics.todayTintOpacity)
        } else if isSelected {
            Color.accentColor.opacity(LayoutMetrics.todayTintOpacity / 2)
        } else if hoveredDay == date {
            Color.primary.opacity(LayoutMetrics.hoverTintOpacity)
        } else {
            Color.clear
        }
    }

    /// The outline around the selected day.
    ///
    /// An outline rather than a fill: the numbers in the cell are the
    /// content, and a selected day that hid them would be impossible to read,
    /// which is the one thing a calendar must not do to the day a user just
    /// chose. `strokeBorder` rather than `stroke` so the line is drawn inside
    /// the cell's bounds and the columns do not shift as the selection moves.
    @ViewBuilder
    private func selectionRing(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                .strokeBorder(Color.accentColor, lineWidth: LayoutMetrics.selectionRingWidth)
        }
    }

    /// The weekday initials, starting on the user's first weekday.
    ///
    /// Nonisolated because it is a pure reading of the calendar, and a `View`'s
    /// members otherwise inherit the main actor from SwiftUI — which would mean a
    /// header row that cannot be asked for without a run loop, and a test that had
    /// to own one.
    nonisolated static func weekdayInitials(in calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let start = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
        return Array(symbols[start...] + symbols[..<start]).map { String($0.prefix(1)) }
    }
}
