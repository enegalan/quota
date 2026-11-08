// swiftlint:disable file_length
import AppKit
import Core
import Platform
import SwiftUI

// swiftlint:disable type_body_length
/// A glanceable overview of every quota and the limits reported by its integration.
struct MainPopover: View {
    let model: AppModel
    let launchFailure: String?

    @Environment(\.openWindow) private var openWindow
    /// Active local drag. System `onDrag`/`onDrop` does not deliver drops in a
    /// MenuBarExtra window, so reordering uses a gesture and this session.
    @State private var draggedItem: PopoverDrag?
    /// Order while dragging. Written to preferences only when the drag ends, so
    /// mid-drag preference saves cannot cancel the gesture.
    @State private var draftItemOrder: [String: [String]] = [:]
    @State private var draftIntegrationOrder: [String]?
    @State private var rowFrames: [String: CGRect] = [:]
    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            if let launchFailure {
                LaunchFailureView(message: launchFailure)
            } else if model.isEmpty, model.unplannedIntegrations.isEmpty {
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
        .coordinateSpace(name: PopoverReorder.space)
        .onPreferenceChange(PopoverReorder.FrameKey.self) { rowFrames = $0 }
    }

    private var groups: [PopoverIntegrationGroup] {
        let groups = PopoverIntegrationGroup.group(model.presentations, unplanned: model.unplannedIntegrations)
        let ids = PopoverOrder.arranged(
            groups.map(\.orderKey),
            accordingTo: draftIntegrationOrder ?? model.menuBarPreferences.popoverIntegrationOrder
        )
        return ids.compactMap { id in groups.first { $0.orderKey == id } }
    }

    /// Limits, with the quotas that watch each one nested under it.
    ///
    /// A quota whose limit is no longer in the reading stays as its own row.
    private func items(for group: PopoverIntegrationGroup) -> [PopoverItem] {
        let buckets = (group.snapshot?.buckets ?? []).filter {
            group.unplanned == nil || $0.period.end > model.reference
        }
        let items = buckets.map(PopoverItem.bucket) + group.unmatchedQuotas.map(PopoverItem.quota)
        let saved = draftItemOrder[group.orderKey]
            ?? model.menuBarPreferences.popoverItemOrder[group.orderKey]
            ?? []
        let ids = PopoverOrder.arranged(items.map(\.id), accordingTo: saved)
        return ids.compactMap { id in items.first { $0.id == id } }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            HStack {
                Text("Usage overview")
                    .font(.system(size: LayoutMetrics.bodySize + 3, weight: .bold))
                Spacer()
                Text(integrationCount)
                    .font(.system(size: LayoutMetrics.footnoteSize))
                    .foregroundStyle(.secondary)
            }
            if scrollsOverview {
                ScrollView {
                    VStack(spacing: LayoutMetrics.rowSpacing) {
                        ForEach(groups) { group in
                            integrationCard(group)
                        }
                    }
                }
                // Fixed height: in a MenuBarExtra, maxHeight lets ScrollView
                // collapse to zero. Short content already skips this branch.
                .frame(height: min(
                    LayoutMetrics.popoverScrollMaximumHeight,
                    (NSScreen.main?.visibleFrame.height ?? LayoutMetrics.popoverScrollFallbackScreenHeight)
                        * LayoutMetrics.popoverScrollScreenFraction
                ))
            } else if let group = groups.first {
                integrationCard(group)
            }
        }
    }

    private var integrationCount: String {
        groups.count == 1 ? "1 integration" : "\(groups.count) integrations"
    }

    /// One short card stays put. Several integrations, or several rows, scroll.
    private var scrollsOverview: Bool {
        guard groups.count == 1, let group = groups.first else { return true }
        return items(for: group).count + group.presentations.count
            > LayoutMetrics.popoverScrollRowThreshold
    }

    /// One integration's limits and quotas, with drag handles for reordering.
    private func integrationCard( // swiftlint:disable:this function_body_length
        _ group: PopoverIntegrationGroup
    ) -> some View {
        let rows = items(for: group)
        return VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
            reorderable(HStack(spacing: LayoutMetrics.rowSpacing) {
                ProviderMark(providerID: group.integrationID, size: 20)
                Text(model.sections.all.first { $0.id == group.integrationID }?.displayName ?? group.integrationID)
                    .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                Spacer()
                Caption(text: group.accountLabel ?? QuotaPresentation.disconnectedAccountCaption)
                    .lineLimit(1)
            }, id: group.orderKey, ids: groups.map(\.orderKey), scope: nil)

            if rows.isEmpty {
                Caption(text: "No usage reading available.")
            }
            ForEach(rows) { item in
                let ids = rows.map(\.id)
                reorderable(VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
                    switch item {
                    case .bucket(let bucket):
                        bucketRow(bucket)
                        ForEach(group.quotas(for: bucket.id)) { presentation in
                            quotaDetails(presentation, in: group)
                        }
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
                    Caption(
                        text: provider
                            .snapshot == nil ? "Unable to refresh usage." :
                            "Refresh failed. Showing the last available reading.",
                        isWarning: true
                    )
                } else if let snapshot = provider.snapshot {
                    Caption(
                        text: "Updated \(RelativeTime(calendar: model.userCalendar).describe(since: snapshot.updatedAt, now: model.reference))."
                    )
                }
            }
        }
        .padding(LayoutMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
    }

    /// A limit's name, bar, and reset caption.
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
            if let reset = ResetCaption.caption(
                for: bucket.period,
                asOf: model.reference,
                calendar: model.userCalendar
            ) {
                Caption(text: reset)
            } else {
                Caption(text: "Reset time unavailable.")
            }
        }
        .padding(.vertical, LayoutMetrics.lineSpacing)
    }

    /// One quota under its limit, with today's plan and a pin control.
    private func quotaDetails(_ presentation: QuotaPresentation, in group: PopoverIntegrationGroup) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.unit) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quota: \(presentation.summary.quota.name)")
                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                if !isPinned(presentation) {
                    Button("Show") {
                        Task { await model.showInMenuBar(presentation) }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Spacer(minLength: LayoutMetrics.rowSpacing)
                if let allowance = presentation.summary.todayAllowance {
                    Text(todayFigures(allowance))
                        .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                        .monospacedDigit()
                }
            }
            todayAllowance(presentation)
            if let bucketID = presentation.summary.quota.bucketID ?? presentation.summary.snapshot?.primaryBucket?.id,
               let bucket = group.snapshot?.buckets.first(where: { $0.id == bucketID })
            {
                Caption(text: "Limit: \(bucket.displayName)")
            }
            if presentation.summary.usage == nil {
                Caption(text: "This quota's limit is unavailable.", isWarning: true)
            }
        }
        .padding(.vertical, LayoutMetrics.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The quota the menu bar item currently speaks for.
    private func isPinned(_ presentation: QuotaPresentation) -> Bool {
        presentation.id == (model.menuBarQuotaID ?? model.primaryPresentation?.id)
    }

    /// Used over today's plan, for the trailing figure on a quota row.
    private func todayFigures(_ allowance: TodayAllowance) -> String {
        "\(formatter.preciseString(allowance.usedToday)) / \(formatter.preciseString(allowance.suggested)) today"
    }

    /// Today's bar and remaining caption when the plan is known.
    @ViewBuilder
    private func todayAllowance(_ presentation: QuotaPresentation) -> some View {
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
    }

    /// Drag and move-up/down for one row in a shared order list.
    private func reorderable(
        _ content: some View, id: String, ids: [String], scope: String?
    ) -> some View {
        let index = ids.firstIndex(of: id) ?? 0
        let frameID = PopoverReorder.frameID(id: id, scope: scope)
        return content
            .contentShape(Rectangle())
            .opacity(draggedItem?.id == id && draggedItem?.scope == scope ? 0.55 : 1)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PopoverReorder.FrameKey.self,
                        value: [frameID: geometry.frame(in: .named(PopoverReorder.space))]
                    )
                }
            }
            .help("Drag to reorder, or right-click to move up or down")
            .contextMenu {
                if index > 0 {
                    Button("Move up") { commitMove(id, to: ids[index - 1], ids: ids, scope: scope) }
                }
                if index + 1 < ids.count {
                    Button("Move down") { commitMove(id, to: ids[index + 1], ids: ids, scope: scope) }
                }
            }
            .accessibilityAction(named: Text("Move up")) {
                if index > 0 {
                    commitMove(id, to: ids[index - 1], ids: ids, scope: scope)
                }
            }
            .accessibilityAction(named: Text("Move down")) {
                if index + 1 < ids.count {
                    commitMove(id, to: ids[index + 1], ids: ids, scope: scope)
                }
            }
            .gesture(reorderGesture(id: id, ids: ids, scope: scope))
    }

    /// Long-press then drag so a ScrollView can still scroll on a short flick.
    private func reorderGesture(id: String, ids: [String], scope: String?) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(
                before: DragGesture(minimumDistance: 1, coordinateSpace: .named(PopoverReorder.space))
            )
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draggedItem == nil {
                    draggedItem = PopoverDrag(id: id, scope: scope)
                }
                guard draggedItem?.id == id, draggedItem?.scope == scope else { return }
                let order = liveOrder(ids: ids, scope: scope)
                guard let target = hitTarget(at: drag.location, dragging: id, scope: scope, ids: order),
                      target != id
                else { return }
                draftMove(id, to: target, ids: order, scope: scope)
            }
            .onEnded { _ in
                guard draggedItem?.id == id, draggedItem?.scope == scope else { return }
                commitDraft()
            }
    }

    /// Current order for a scope, preferring an in-flight draft.
    private func liveOrder(ids: [String], scope: String?) -> [String] {
        if let scope {
            return PopoverOrder.arranged(
                ids,
                accordingTo: draftItemOrder[scope] ?? model.menuBarPreferences.popoverItemOrder[scope] ?? []
            )
        }
        return PopoverOrder.arranged(
            ids,
            accordingTo: draftIntegrationOrder ?? model.menuBarPreferences.popoverIntegrationOrder
        )
    }

    /// Row under the pointer in the same reorder scope, if any.
    ///
    /// A target counts only after the pointer crosses that row's midpoint in the
    /// reorder direction, so grazing the near edge does not flip the order.
    private func hitTarget(at point: CGPoint, dragging: String, scope: String?, ids: [String]) -> String? {
        let available = Set(ids)
        guard let from = ids.firstIndex(of: dragging) else { return nil }
        for (frameID, frame) in rowFrames {
            guard frame.contains(point),
                  let parsed = PopoverReorder.parse(frameID),
                  parsed.scope == scope,
                  parsed.id != dragging,
                  available.contains(parsed.id),
                  let to = ids.firstIndex(of: parsed.id)
            else { continue }
            let midpoint = frame.midY
            if from < to {
                guard point.y >= midpoint else { continue }
            } else {
                guard point.y <= midpoint else { continue }
            }
            return parsed.id
        }
        return nil
    }

    /// Updates only the draft order while a drag is live.
    private func draftMove(_ id: String, to target: String, ids: [String], scope: String?) {
        let updated = PopoverOrder.moving(id, to: target, in: ids)
        guard updated != ids else { return }
        if let scope {
            draftItemOrder[scope] = updated
        } else {
            draftIntegrationOrder = updated
        }
    }

    /// Writes a reordered list into preferences immediately (context menu).
    private func commitMove(_ id: String, to target: String, ids: [String], scope: String?) {
        let updated = PopoverOrder.moving(id, to: target, in: ids)
        model.updateMenuBarPreferences { preferences in
            if let scope {
                preferences.popoverItemOrder[scope] = updated
            } else {
                preferences.popoverIntegrationOrder = updated
            }
        }
    }

    /// Persists the draft built during a drag, then clears the session.
    private func commitDraft() {
        let integrationOrder = draftIntegrationOrder
        let itemOrder = draftItemOrder
        draggedItem = nil
        draftIntegrationOrder = nil
        draftItemOrder = [:]
        guard integrationOrder != nil || !itemOrder.isEmpty else { return }
        model.updateMenuBarPreferences { preferences in
            if let integrationOrder {
                preferences.popoverIntegrationOrder = integrationOrder
            }
            for (scope, order) in itemOrder {
                preferences.popoverItemOrder[scope] = order
            }
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

// swiftlint:enable type_body_length

private struct PopoverDrag {
    let id: String
    let scope: String?
}

/// Local reorder hit-testing for the menu-bar popover.
private enum PopoverReorder {
    static let space = "popoverReorder"
    private static let separator = "\u{1e}"

    static func frameID(id: String, scope: String?) -> String {
        (scope ?? "") + separator + id
    }

    static func parse(_ frameID: String) -> (id: String, scope: String?)? {
        let parts = frameID.split(
            separator: "\u{1e}",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else { return nil }
        let scope = String(parts[0])
        return (String(parts[1]), scope.isEmpty ? nil : scope)
    }

    struct FrameKey: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]

        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
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

// One provider account and the quotas that belong to its reported limits.
