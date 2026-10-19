import Core
import SwiftUI

/// The paging controls above a month: back, the month itself, forward, Today.
///
/// Its own view because those controls are two different things. Whether a page
/// exists, which months the menu offers, and whether Today is worth a button are
/// the grid's decisions — they come from the period, and the period is the grid's
/// business. How a button looks and where the checkmark goes is drawing. Handing
/// the decisions over rather than recomputing them here is what keeps one answer
/// to "can this calendar go back a month" instead of two that can disagree: a
/// control that bounded its own paging differently would page into months of
/// cells that cannot be acted on.
struct MonthNavigationBar: View {
    let calendar: Calendar

    /// The months on offer, or empty when nothing bounds the calendar and the
    /// month becomes a date picker rather than a menu of blank pages.
    let months: [Date]

    /// The month being drawn.
    let shown: Date

    let canGoBack: Bool
    let canGoForward: Bool
    let showsToday: Bool

    let onShift: (Int) -> Void
    let onChoose: (Date) -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: LayoutMetrics.rowSpacing) {
            Spacer(minLength: 0)

            // The arrows sit beside the month they move. At the far ends of the
            // bar they were two buttons a long way from the thing they change,
            // and the bar read as a toolbar with a month floating in it.
            //
            // Fixed at its own width so the group is centred as a group: a menu
            // given the room would stretch to the edges and leave its label
            // sitting at one side of them.
            paging.fixedSize()

            Spacer(minLength: 0)

            // Nothing else shares this row. A button that jumps to today, drawn
            // beside the control that shows the month, reads as a control of
            // that month: the title changes under the pointer and the button
            // that did it looks like it edited the title. Today is offered by
            // the month menu instead, which is the control it belongs to.
            //
            // The exception is a calendar with no month menu, where the picker
            // is not a month to be confused with and there is nothing else to
            // offer the jump in.
            if months.isEmpty, showsToday {
                todayButton
            }
        }
    }

    /// The jump to today, for a calendar that has no month menu to put it in.
    private var todayButton: some View {
        Button("Today") {
            onToday()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Jump to today")
    }

    /// The month and the two arrows that page through the months.
    private var paging: some View {
        HStack(spacing: LayoutMetrics.lineSpacing) {
            MonthArrow(
                symbol: "chevron.left",
                isEnabled: canGoBack,
                help: "Previous month"
            ) {
                onShift(-1)
            }
            monthControl
            MonthArrow(
                symbol: "chevron.right",
                isEnabled: canGoForward,
                help: "Next month"
            ) {
                onShift(1)
            }
        }
    }

    /// Title as a menu of months in range, or a month/year picker when unbounded.
    @ViewBuilder
    private var monthControl: some View {
        if months.isEmpty {
            DatePicker(
                "",
                selection: Binding(get: { shown }, set: { onChoose($0) }),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .controlSize(.small)
        } else {
            Menu {
                // Today first, because it is not a month but a place to go, and
                // a menu of months is where a user looks for it.
                if showsToday {
                    Button {
                        onToday()
                    } label: {
                        Label("Today", systemImage: "calendar")
                    }
                    Divider()
                }
                ForEach(months, id: \.self) { candidate in
                    Button {
                        onChoose(candidate)
                    } label: {
                        HStack {
                            Text(title(for: candidate))
                            if isDrawn(candidate) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: LayoutMetrics.lineSpacing) {
                    Text(title(for: shown))
                        .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, LayoutMetrics.unit * 2)
                .padding(.vertical, LayoutMetrics.lineSpacing)
                // On a tile of its own, so the month reads as the control it is
                // rather than as a word in a bar of buttons.
                .background(
                    RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                        .fill(Color.primary.opacity(LayoutMetrics.hoverTintOpacity * 2))
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Choose month")
        }
    }

    /// A month named the way the user's own calendar names it.
    private func title(for date: Date) -> String {
        LayoutMetrics.date(date, template: "MMMM yyyy", calendar: calendar)
    }

    /// Whether this menu entry is the month on screen.
    ///
    /// Compared as month starts: the picker hands back an instant inside the month
    /// and never the same instant twice, so comparing dates would tick nothing at
    /// all.
    private func isDrawn(_ candidate: Date) -> Bool {
        let start = { MonthLayout.monthStart(of: $0, calendar: calendar) }
        return start(candidate) == start(shown)
    }
}

/// One of the two arrows that page the calendar.
///
/// Plain rather than bordered: the month they move is right beside them, and a
/// border around each would draw three boxes where the group reads as one
/// control. The tint under the pointer is what says there is something there to
/// press.
private struct MonthArrow: View {
    let symbol: String
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.35))
                .padding(.horizontal, LayoutMetrics.unit * 1.5)
                .padding(.vertical, LayoutMetrics.lineSpacing)
                .background(
                    RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                        .fill(Color.primary.opacity(isHovered ? LayoutMetrics.hoverFillOpacity : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
