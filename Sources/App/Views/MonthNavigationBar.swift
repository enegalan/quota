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
            Button {
                onShift(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoBack)
            .help("Previous month")

            Spacer(minLength: 0)

            monthControl

            Spacer(minLength: 0)

            if showsToday {
                Button("Today") {
                    onToday()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Jump to today")
            }

            Button {
                onShift(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canGoForward)
            .help("Next month")
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
                        .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, LayoutMetrics.unit)
                .padding(.vertical, LayoutMetrics.lineSpacing)
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
