import AppKit
import Core
import Platform
import SwiftUI

/// Compact menu-bar preview: every quota, and a door into the window.
///
/// Editing (providers, create, calendar, custom policy) lives in `MainWindow`.
/// The popover only answers "how am I doing" and how to open the rest.
///
/// Every quota is listed, not just the one the menu bar item speaks for, because
/// the item shows a single number and the question that number raises — "which of
/// my quotas is that?" — is unanswerable from a list that hides the rest. The
/// chosen quota gets the full card and the others a row, so the popover answers
/// for all of them without growing a full card per quota into something taller
/// than the screen it is opened on.
struct MainPopover: View {
    let model: AppModel
    let launchFailure: String?

    @Environment(\.openWindow) private var openWindow

    /// The row the pointer is over, so only that row offers itself as pressable.
    @State private var hoveredQuotaID: UUID?

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            if let launchFailure {
                LaunchFailureView(message: launchFailure)
            } else if model.isEmpty {
                emptyState
            } else {
                quotas
            }
            if let lastError = model.lastError {
                ErrorBanner(message: lastError)
            }
            footer
        }
        .padding(LayoutMetrics.inset)
        .frame(width: LayoutMetrics.popoverWidth)
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            MainWindowOpener.open(using: openWindow)
        }
    }

    /// The chosen quota in full, then the rest in a row each.
    ///
    /// Split out of `body` so the ordering is a statement about what the popover
    /// leads with: the number the menu bar item is showing, spelled out, and the
    /// rest of them underneath where a click can promote one.
    ///
    /// Not a scrolling list. One full card plus a row per other quota is one card
    /// and a few lines — a provider can back one quota per bucket, and the rows
    /// are what a user scans to pick one, so a panel they have to scroll to read
    /// is worse than a tall one. A `ScrollView` here would also be the one part
    /// of the popover the rendered snapshots cannot photograph.
    private var quotas: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            if let primary = model.primaryPresentation {
                preview(for: primary)
            }
            otherRows
        }
    }

    /// Every quota the menu bar item is not speaking for, as a clickable row.
    @ViewBuilder
    private var otherRows: some View {
        let others = model.presentations.filter { $0.id != model.primaryPresentation?.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                if model.primaryPresentation != nil {
                    Divider()
                }
                Caption(text: model.presentations.count > 1 ? "Other quotas" : "Quota")
                ForEach(others) { presentation in
                    row(for: presentation)
                }
            }
        }
    }

    /// The full card for the quota the menu bar item speaks for.
    private func preview(for presentation: QuotaPresentation) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            HStack(alignment: .center, spacing: LayoutMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                    HStack(spacing: LayoutMetrics.lineSpacing) {
                        Text(presentation.summary.quota.name)
                            .font(.system(size: LayoutMetrics.bodySize + 3, weight: .bold))
                            .lineLimit(1)
                            .padding(2)
                        MenuBarMarker()
                    }
                    Caption(presentation.accountCaption)
                    PacingView(pacing: presentation.summary.pacing)
                }
                Spacer(minLength: 0)
                UsageRing(
                    fraction: (presentation.usagePercentage ?? 0) / 100.0,
                    label: formatter.string(presentation.usagePercentage)
                )
            }
            TodayAllowanceView(
                presentation: presentation
            )
            OutlookRow(
                presentation: presentation,
                reference: model.reference,
                calendar: model.userCalendar
            )
            Caption(
                text: presentation.syncCaption(asOf: model.reference, calendar: model.userCalendar),
                isWarning: presentation.syncIsWarning(asOf: model.reference)
            )
        }
        .padding(LayoutMetrics.inset)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    /// Empty popover: one short pitch and the door into the window.
    private var emptyState: some View {
        NoticeCard(
            title: "Welcome to Quota",
            message: "Connect a provider and create a quota to start tracking usage."
        )
    }

    /// One other quota, and the click that makes it the one in the menu bar.
    ///
    /// A button rather than a plain row because the action is the reason the row
    /// is there: with several quotas a user opening the popover is looking for
    /// one of them, and the way to say "that one" is to click it. Shown on hover
    /// so the row reads as something to press only while the pointer is on it,
    /// and always for a row that already carries the choice.
    private func row(for presentation: QuotaPresentation) -> some View {
        Button {
            Task { await model.showInMenuBar(presentation) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                    Text(presentation.summary.quota.name)
                        .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                        .lineLimit(1)
                    Caption(presentation.accountCaption)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(ShareTint.color(for: presentation.usagePercentage, of: 100))
                    .frame(width: 6, height: 6)
                Text(formatter.string(presentation.usagePercentage))
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Show")
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isHovered(presentation) ? 1 : 0)
            }
            .padding(.vertical, LayoutMetrics.lineSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarRowButtonStyle(isHovered: isHovered(presentation)))
        .onHover { hovering in
            hoveredQuotaID = hovering ? presentation.id : (hoveredQuotaID == presentation.id ? nil : hoveredQuotaID)
        }
        .accessibilityLabel(Text(presentation.summary.quota.name))
        .accessibilityHint("Show this quota in the menu bar")
    }

    /// Whether the pointer is over this quota's row.
    ///
    /// One question asked in one place. The row's button style and its "Show"
    /// affordance both need this answer, and reading the state directly at
    /// each site would let the two disagree about which row is under the
    /// pointer — leaving a row highlighted with nothing in it to press.
    private func isHovered(_ presentation: QuotaPresentation) -> Bool {
        hoveredQuotaID == presentation.id
    }

    private var footer: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            Button {
                MainWindowOpener.open(using: openWindow)
            } label: {
                Label("Open", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .foregroundStyle(.white)
            Button {
                Task { await model.refreshAll() }
            } label: {
                Label(model.isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.accentColor)
            .foregroundStyle(.white)
            .disabled(model.isRefreshing)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.red)
            .foregroundStyle(.white)
            .keyboardShortcut(
                KeyEquivalent(Character(Shortcut.quitKeyEquivalent)),
                modifiers: .command
            )
        }
        .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
    }
}

/// A compact ring that shows how much of the allowance is spent.
///
/// The figure sits in the middle so the most important number stays the
/// largest thing in the card, with the proportion encoded as the ring's fill
/// rather than as a second number the reader has to compare.
struct UsageRing: View {
    let fraction: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(LayoutMetrics.barTrackOpacity), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(
                    ShareTint.color(for: fraction * 100, of: 100),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: LayoutMetrics.bodySize, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 64, height: 64)
        .padding(8)
        .drawingGroup()
        .accessibilityLabel("\(label) used")
    }
}

/// Marks the quota the menu bar item is speaking for.
///
/// A dot and not the word "Menu bar": the card is the first thing read when the
/// popover opens, and a line of text saying which of the user's quotas is the one
/// in the menu bar is a worse answer than the mark next to its name. The word is
/// still there for a screen reader, which is where "Show this quota in the menu
/// bar" on the other rows makes sense.
struct MenuBarMarker: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: LayoutMetrics.menuBarMarkerSize, height: LayoutMetrics.menuBarMarkerSize)
            .accessibilityLabel("Shown in the menu bar")
    }
}

/// A quota row that shows itself as pressable only under the pointer.
///
/// No border and no fill at rest. A popover is a readout, and a column of rows
/// drawn as buttons would claim to be a list of things to press when most of the
/// time they are there to be read; the fill appears on hover, so a row that
/// cannot be pressed never looks like one.
struct MenuBarRowButtonStyle: ButtonStyle {
    var isHovered = false

    /// Paints the row, with a fill that exists only under the pointer.
    ///
    /// Layered on rather than swapping in a second background, so hover and
    /// press stay independent: a row can be pressed after the pointer has
    /// already moved off it, and only the label's own tint follows the press.
    ///
    /// Drawn with `background` rather than a ZStack under the label, so the
    /// row keeps the layout it was given and the highlight cannot reorder
    /// anything above it.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                    .fill(Color(nsColor: .controlAccentColor).opacity(fillOpacity))
            )
            .foregroundStyle(configuration.isPressed ? Color.accentColor : Color.primary)
    }

    private var fillOpacity: Double {
        isHovered ? LayoutMetrics.hoverFillOpacity : 0
    }
}
