import SwiftUI

/// The months a calendar may be paged through.
///
/// The span of a quota's period, so navigation cannot walk off either end of the
/// thing the calendar is about.
struct MonthRange: Hashable {
    let earliest: Date
    let latest: Date

    init(earliest: Date, latest: Date) {
        self.earliest = min(earliest, latest)
        self.latest = max(earliest, latest)
    }
}

/// One entry in a calendar's legend: a marker as it appears in the grid, and what
/// it means.
///
/// A calendar that distinguished five kinds of day with five shades of grey
/// asked the user to learn a colour code. Saying what each mark stands for costs
/// one row of text and is the difference between a calendar that can be read and
/// one that has to be decoded.
struct CalendarLegendItem: Identifiable, Hashable {
    /// How the mark is drawn in a cell.
    enum Marker: Hashable {
        /// Today's tinted cell.
        case today
        /// The ring around the selected day.
        case selected
        /// A day with nothing assigned to it.
        case empty
        /// A day outside the period.
        case outOfPeriod
    }

    let label: String
    let marker: Marker

    var id: String {
        label
    }
}

/// The calendar's key, as a wrapping row of marks.
struct CalendarLegend: View {
    let items: [CalendarLegendItem]

    var body: some View {
        // Adaptive wrapping: four marks in a row when there is room, two-by-two
        // when the pane is narrow, so the key never clips mid-label.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: LayoutMetrics.actionSpacing)],
            alignment: .leading,
            spacing: LayoutMetrics.rowSpacing
        ) {
            ForEach(items) { item in
                HStack(spacing: LayoutMetrics.lineSpacing) {
                    mark(item.marker)
                    Text(item.label)
                        .font(.system(size: LayoutMetrics.captionSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(items.map(\.label).joined(separator: ", "))
    }

    /// The mark as it is drawn in a cell, at the size a key can afford.
    ///
    /// The same shape the grid draws, so the key is a picture of the calendar
    /// rather than a description of it; a legend that differs in any detail
    /// teaches the reader a mark they will not meet in the grid. Isolated so
    /// the two cannot drift apart in how they render one.
    private func mark(_ marker: CalendarLegendItem.Marker) -> some View {
        RoundedRectangle(cornerRadius: LayoutMetrics.lineSpacing)
            .fill(fill(for: marker))
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.lineSpacing)
                    .strokeBorder(Color.accentColor, lineWidth: marker == .selected ? 1 : 0)
            )
            .frame(width: LayoutMetrics.legendMarkSize, height: LayoutMetrics.legendMarkSize)
    }

    /// The colour a mark is filled with.
    ///
    /// Tints at the opacities the grid itself uses, which is what makes the
    /// key worth reading: the shades are the calendar's, so nothing has to be
    /// learned that the calendar does not also teach.
    ///
    /// The selected marker is left clear and carried by its outline alone.
    /// The ring is what identifies a selection, and a filled swatch beside it
    /// in the key would imply a colour strong enough to read through — which
    /// is exactly what the grid refuses to do, since a selected day has to
    /// stay legible.
    private func fill(for marker: CalendarLegendItem.Marker) -> Color {
        switch marker {
        case .today: Color.accentColor.opacity(LayoutMetrics.todayTintOpacity)
        case .selected: Color.clear
        case .empty: Color.primary.opacity(LayoutMetrics.emptyDayOpacity)
        case .outOfPeriod: Color.primary.opacity(LayoutMetrics.outOfPeriodOpacity)
        }
    }
}
