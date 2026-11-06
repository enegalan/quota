import AppKit
import Core
import Platform
import SwiftUI
import UniformTypeIdentifiers

/// A glanceable overview of every quota and the limits reported by its provider.
struct MainPopover: View {
    let model: AppModel
    let launchFailure: String?

    @Environment(\.openWindow) private var openWindow
    @State private var draggedItem: PopoverDrag?
    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            if let launchFailure {
                LaunchFailureView(message: launchFailure)
            } else if model.isEmpty && model.unplannedProviders.isEmpty {
                NoticeCard(
                    title: "Welcome to Quota",
                    message: "Connect an integration to start tracking usage."
                )
            } else {
                overview
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

    private var groups: [PopoverProviderGroup] {
        let groups = PopoverProviderGroup.group(model.presentations, unplanned: model.unplannedProviders)
        let ids = PopoverOrder.arranged(groups.map(\.orderKey), accordingTo: model.menuBarPreferences.popoverProviderOrder)
        return ids.compactMap { id in groups.first { $0.orderKey == id } }
    }

    private func items(for group: PopoverProviderGroup) -> [PopoverItem] {
        let buckets = (group.snapshot?.buckets ?? []).filter {
            group.unplanned == nil || $0.period.end > model.reference
        }
        let items = buckets.map(PopoverItem.bucket)
            + group.presentations.map(PopoverItem.quota)
        let ids = PopoverOrder.arranged(items.map(\.id), accordingTo: model.menuBarPreferences.popoverItemOrder[group.orderKey] ?? [])
        return ids.compactMap { id in items.first { $0.id == id } }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            HStack {
                Text("Usage overview")
                    .font(.system(size: LayoutMetrics.bodySize + 3, weight: .bold))
                Spacer()
                Text("\(groups.count) providers")
                    .font(.system(size: LayoutMetrics.footnoteSize))
                    .foregroundStyle(.secondary)
            }
            if groups.count == 1, let group = groups.first,
               (group.snapshot?.buckets.count ?? 0) <= 2 {
                providerCard(group)
            } else {
                ScrollView {
                    VStack(spacing: LayoutMetrics.rowSpacing) {
                        ForEach(groups) { group in
                            providerCard(group)
                        }
                    }
                }
                .frame(height: min(480, (NSScreen.main?.visibleFrame.height ?? 800) * 0.65))
            }
        }
    }

    private func providerCard(_ group: PopoverProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
            reorderable(HStack(spacing: LayoutMetrics.rowSpacing) {
                ProviderMark(providerID: group.providerID, size: 20)
                Text(model.sections.all.first { $0.id == group.providerID }?.displayName ?? group.providerID)
                    .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                Spacer()
                Caption(text: group.accountLabel ?? QuotaPresentation.disconnectedAccountCaption)
                    .lineLimit(1)
            }, id: group.orderKey, ids: groups.map(\.orderKey), scope: nil)

            if items(for: group).isEmpty {
                Caption(text: "No usage reading available.")
            }
            ForEach(items(for: group)) { item in
                let ids = items(for: group).map(\.id)
                reorderable(HStack(alignment: .top, spacing: LayoutMetrics.unit) {
                    switch item {
                    case .bucket(let bucket):
                        bucketRow(bucket)
                    case .quota(let presentation):
                        quotaDetails(presentation, in: group)
                    }
                }, id: item.id, ids: ids, scope: group.orderKey)
            }
            if let latest = group.latestPresentation {
                Caption(
                    text: latest.syncCaption(asOf: model.reference, calendar: model.userCalendar),
                    isWarning: latest.syncIsWarning(asOf: model.reference)
                )
            } else if let provider = group.unplanned {
                if provider.failed {
                    Caption(text: provider.snapshot == nil ? "Unable to refresh usage." : "Refresh failed. Showing the last available reading.", isWarning: true)
                } else if let snapshot = provider.snapshot {
                    Caption(text: "Updated \(RelativeTime(calendar: model.userCalendar).describe(since: snapshot.updatedAt, now: model.reference)).")
                }
            }
        }
        .padding(LayoutMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
        .onDrop(of: [PopoverDrag.type], delegate: dropDelegate(target: group.orderKey, ids: groups.map(\.orderKey), scope: nil))
    }

    private func bucketRow(_ bucket: UsageBucket) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.displayName)
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                Spacer(minLength: LayoutMetrics.rowSpacing)
                Text("\(formatter.string(bucket.usagePercentage)) used")
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                    .monospacedDigit()
            }
            UsageBar(
                value: bucket.usagePercentage,
                maximum: UsageConstants.percentageScale,
                tint: ShareTint.color(for: bucket.usagePercentage, of: UsageConstants.percentageScale)
            )
            if let description = bucket.limitDescription {
                Caption(text: description)
            }
            if let reset = ResetCaption.caption(for: bucket.period, asOf: model.reference, calendar: model.userCalendar) {
                Caption(text: reset)
            } else {
                Caption(text: "Reset time unavailable.")
            }
        }
        .padding(.vertical, LayoutMetrics.lineSpacing)
    }

    private func quotaDetails(_ presentation: QuotaPresentation, in group: PopoverProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quota: \(presentation.summary.quota.name)")
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                Spacer(minLength: LayoutMetrics.rowSpacing)
                if let allowance = presentation.summary.todayAllowance {
                    Text("\(formatter.preciseString(allowance.usedToday)) / \(formatter.preciseString(allowance.suggested)) today")
                        .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                        .monospacedDigit()
                }
            }
            if let allowance = presentation.summary.todayAllowance {
                if let used = allowance.usedToday {
                    UsageBar(
                        value: used,
                        maximum: allowance.suggested,
                        tint: ShareTint.color(for: used, of: allowance.suggested)
                    )
                    Caption(text: "\(formatter.preciseString(max(0, allowance.suggested - used))) remaining today")
                } else {
                    Caption(text: "Today's consumption unavailable.")
                }
            } else {
                Caption(text: "No daily plan available.")
            }
            if let bucketID = presentation.summary.quota.bucketID ?? presentation.summary.snapshot?.primaryBucket?.id,
               let bucket = group.snapshot?.buckets.first(where: { $0.id == bucketID }) {
                Caption(text: "Limit: \(bucket.displayName)")
            }
            if presentation.summary.usage == nil {
                Caption(text: "This quota's limit is unavailable.", isWarning: true)
            }
        }
        .padding(.vertical, LayoutMetrics.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reorderable<Content: View>(
        _ content: Content, id: String, ids: [String], scope: String?
    ) -> some View {
        let index = ids.firstIndex(of: id) ?? 0
        return content
        .contentShape(Rectangle())
        .help("Drag to reorder, or right-click to move up or down")
        .onHover { hovering in
            if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            if index > 0 {
                Button("Move up") { move(id, to: ids[index - 1], ids: ids, scope: scope) }
            }
            if index + 1 < ids.count {
                Button("Move down") { move(id, to: ids[index + 1], ids: ids, scope: scope) }
            }
        }
        .accessibilityAction(named: Text("Move up")) {
            if index > 0 { move(id, to: ids[index - 1], ids: ids, scope: scope) }
        }
        .accessibilityAction(named: Text("Move down")) {
            if index + 1 < ids.count { move(id, to: ids[index + 1], ids: ids, scope: scope) }
        }
        .onDrag {
            draggedItem = PopoverDrag(id: id, scope: scope)
            return NSItemProvider(object: id as NSString)
        }
        .onDrop(of: [PopoverDrag.type], delegate: dropDelegate(target: id, ids: ids, scope: scope))
    }

    private func move(_ id: String, to target: String, ids: [String], scope: String?) {
        let updated = PopoverOrder.moving(id, to: target, in: ids)
        model.updateMenuBarPreferences { preferences in
            if let scope {
                preferences.popoverItemOrder[scope] = updated
            } else {
                preferences.popoverProviderOrder = updated
            }
        }
    }

    private func dropDelegate(target: String, ids: [String], scope: String?) -> PopoverDropDelegate {
        PopoverDropDelegate(draggedItem: $draggedItem, target: target, scope: scope) { source in
            move(source, to: target, ids: ids, scope: scope)
        }
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
        }
        .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
    }
}

private struct PopoverDrag {
    static let type = UTType.plainText
    let id: String
    let scope: String?
}

private struct PopoverDropDelegate: DropDelegate {
    @Binding var draggedItem: PopoverDrag?
    let target: String
    let scope: String?
    let move: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedItem?.scope == scope && draggedItem?.id != target && draggedItem != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let item = draggedItem, item.scope == scope, item.id != target else { return }
        move(item.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = draggedItem, item.scope == scope, item.id != target else { return false }
        draggedItem = nil
        return true
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

/// One provider account and the quotas that belong to its reported limits.
struct PopoverProviderGroup: Identifiable {
    struct ID: Hashable {
        let providerID: String
        let accountLabel: String?
    }

    let id: ID
    var presentations: [QuotaPresentation]
    var unplanned: UnplannedProvider? = nil

    var providerID: String { id.providerID }
    var accountLabel: String? { id.accountLabel }
    var orderKey: String { PopoverOrder.key(providerID: providerID, account: accountLabel) }
    var latestPresentation: QuotaPresentation? {
        presentations.max { ($0.summary.snapshot?.updatedAt ?? .distantPast) < ($1.summary.snapshot?.updatedAt ?? .distantPast) }
    }
    var snapshot: UsageSnapshot? { latestPresentation?.summary.snapshot ?? unplanned?.snapshot }

    func quotas(for bucketID: String) -> [QuotaPresentation] {
        presentations.filter { ($0.summary.quota.bucketID ?? $0.summary.snapshot?.primaryBucket?.id) == bucketID }
    }

    var unmatchedQuotas: [QuotaPresentation] {
        presentations.filter { presentation in
            let bucketID = presentation.summary.quota.bucketID ?? presentation.summary.snapshot?.primaryBucket?.id
            return !((snapshot?.buckets ?? []).contains { $0.id == bucketID })
        }
    }

    static func group(_ presentations: [QuotaPresentation], unplanned: [UnplannedProvider] = []) -> [PopoverProviderGroup] {
        var groups: [PopoverProviderGroup] = []
        for presentation in presentations {
            let id = ID(providerID: presentation.summary.quota.providerID.rawValue, accountLabel: presentation.accountLabel)
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].presentations.append(presentation)
            } else {
                groups.append(PopoverProviderGroup(id: id, presentations: [presentation]))
            }
        }
        for provider in unplanned {
            let id = ID(providerID: provider.providerID, accountLabel: provider.accountLabel)
            guard !groups.contains(where: { $0.id == id }) else { continue }
            groups.append(PopoverProviderGroup(id: id, presentations: [], unplanned: provider))
        }
        return groups
    }
}
