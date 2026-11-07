import Core
import Platform
import SwiftUI

/// Which limits each integration shows in the menu bar.
struct MenuBarIntegrationSettings: View {
    let model: AppModel

    fileprivate static let explanation = """
    Choose which quotas show today's allowance, and which limits to \
    display. Available limits depend on your plan. Show available limits \
    is off by default so the menu bar stays compact; switch it on to see \
    each limit's total usage beside today's allowance.

    Show in menu bar includes that integration. When off, none of its \
    figures are drawn. With only one integration, it stays on: Quota \
    always shows at least one quota.

    Today's planned quota is the allowance for today. With more than one \
    quota, each can be included; one is labelled Today, and more than one \
    are named. Those rows follow the Show daily quota switch, and each \
    integration keeps at least one daily quota when it is on.

    Each integration keeps at least one limit when Show available limits \
    is on.

    The limits listed below are the ones in the latest update. Unavailable \
    limits may be missing from your plan or from that update. A selected \
    one shows a dash until data is available.
    """

    var body: some View {
        Section {
            if items.isEmpty, unplannedIntegrations.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Add a quota to choose which integration limits appear in the menu bar.")
                        .foregroundStyle(.secondary)
                    SettingInfoButton(explanation: Self.explanation)
                }
            } else {
                ForEach(items) { item in
                    IntegrationLimitRowView(model: model, item: item)
                }
                ForEach(unplannedIntegrations, id: \.orderKey) { provider in
                    unplannedSettings(provider)
                }
            }
        } header: {
            Text("Integration Limits")
        }
    }

    private var unplannedIntegrations: [UnplannedIntegration] {
        var seen = Set(model.presentations.map(\.summary.quota.providerID.rawValue))
        return model.unplannedIntegrations.filter { seen.insert($0.integrationID).inserted }
    }

    private func unplannedSettings(_ provider: UnplannedIntegration) -> some View {
        let integrationID = provider.integrationID
        let buckets = provider.snapshot?.buckets ?? []
        let ids = buckets.map(\.id)
        let shown = model.isIntegrationShownInMenuBar(integrationID)
        return Group {
            Toggle(model.sections.listing(id: integrationID)?.displayName ?? integrationID, isOn: Binding(
                get: { model.isIntegrationShownInMenuBar(integrationID) },
                set: { model.setShowsIntegrationInMenuBar($0, integrationID: integrationID) }
            ))
            .disabled(shown && !model.canHideIntegration(integrationID))
            ForEach(buckets, id: \.id) { bucket in
                Toggle(bucket.displayName, isOn: Binding(
                    get: {
                        model.menuBarPreferences.showsLimit(
                            bucket.id,
                            integrationID: integrationID,
                            availableLimitIDs: ids
                        )
                    },
                    set: { enabled in
                        model.updateMenuBarPreferences {
                            $0.setShowsLimit(
                                enabled,
                                limitID: bucket.id,
                                integrationID: integrationID,
                                availableLimitIDs: ids
                            )
                        }
                    }
                ))
            }
        }
    }

    private var integrationPresentations: [QuotaPresentation] {
        var seen = Set<String>()
        return model.presentations.filter {
            seen.insert($0.summary.quota.providerID.rawValue).inserted
        }
    }

    private var items: [IntegrationLimitItem] {
        integrationPresentations.enumerated().flatMap { index, presentation in
            IntegrationLimitItem.rows(
                model: model,
                presentation: presentation,
                separates: index > 0
            )
        }
    }
}

/// One form row for an integration limit.
///
/// Kept as its own row so the switches use the same form layout as the other
/// settings, rather than a box nested inside the section.
private struct IntegrationLimitRowView: View {
    let model: AppModel
    let item: IntegrationLimitItem

    private var slice: IntegrationSlice {
        IntegrationSlice(model: model, presentation: item.presentation)
    }

    var body: some View {
        switch item.kind {
        case .identity:
            HStack(alignment: .firstTextBaseline) {
                Toggle(isOn: slice.shownInMenuBar) {
                    HStack(spacing: LayoutMetrics.rowSpacing) {
                        ProviderMark(providerID: slice.integrationID, size: 18, sizesNativeImage: true)
                        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                            Text(slice.displayName)
                            Text("Show in menu bar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel("Show \(slice.displayName) in menu bar")
                .disabled(!slice.canToggle)
                .help(slice.toggleHelp)
                SettingInfoButton(explanation: MenuBarIntegrationSettings.explanation)
            }
            .padding(.top, item.separates ? LayoutMetrics.sectionSpacing : 0)
        case .dailyHeader:
            groupLabel("Daily quotas")
        case .daily(let quota):
            let title = slice.quotas.count > 1
                ? quota.dailyMenuTitle(among: slice.quotas)
                : "Today's planned quota"
            Toggle(title, isOn: slice.dailyQuotaBinding(quota.id))
                .accessibilityLabel(
                    slice.quotas.count > 1
                        ? "\(slice.integrationID) \(title) today's planned quota"
                        : "\(slice.integrationID) today's planned quota"
                )
                .disabled(!slice.canToggleDailyQuota(quota.id))
                .help(slice.dailyQuotaHelp(quota.id, title: title))
        case .limitsHeader:
            groupLabel("Available limits")
        case .limit(let bucket):
            Toggle(bucket.displayName, isOn: slice.limitBinding(bucket.id))
                .accessibilityLabel("\(slice.integrationID) \(bucket.displayName)")
                .disabled(!slice.canToggleLimit(bucket.id))
                .help(slice.limitHelp(bucket.displayName, limitID: bucket.id))
        case .unavailable:
            DisclosureGroup("Unavailable limits (\(slice.unavailable.count))") {
                VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
                    Text(
                        "These limits may be unavailable for your plan or missing from the latest update. Selected limits show a dash until data is available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(slice.unavailable) { limit in
                        Toggle(limit.name, isOn: slice.limitBinding(limit.id))
                            .accessibilityLabel("\(slice.integrationID) \(limit.name), unavailable")
                            .disabled(!slice.canToggleLimit(limit.id))
                            .help(slice.limitHelp(limit.name, limitID: limit.id))
                    }
                }
                .padding(.top, LayoutMetrics.rowSpacing)
            }
        case .noLimits:
            Text("No limits reported in the latest update.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A heading for the rows under it, without a separator that would split them off.
    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden, edges: .bottom)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The quotas and limits of one integration, read the same way for every row.
@MainActor
struct IntegrationSlice {
    let model: AppModel
    let presentation: QuotaPresentation

    var integrationID: String {
        presentation.summary.quota.providerID.rawValue
    }

    var displayName: String {
        model.sections.listing(id: integrationID)?.displayName ?? presentation.summary.quota.name
    }

    /// Whether turning this integration off would leave the menu bar empty.
    var canHide: Bool {
        model.canHideIntegration(integrationID)
    }

    var isShownInMenuBar: Bool {
        model.isIntegrationShownInMenuBar(integrationID)
    }

    /// A hidden integration can always be switched back on; the last visible
    /// one cannot be switched off.
    var canToggle: Bool {
        !isShownInMenuBar || canHide
    }

    var toggleHelp: String {
        guard canToggle else {
            return "At least one integration must stay in the menu bar"
        }
        return isShownInMenuBar
            ? "Exclude \(displayName) from the menu bar"
            : "Include \(displayName) in the menu bar"
    }

    var quotas: [QuotaPresentation] {
        model.presentations.filter { $0.summary.quota.providerID.rawValue == integrationID }
    }

    /// The quota whose reading lists this integration's limits.
    ///
    /// The pinned quota when the menu bar speaks for this integration,
    /// otherwise the first quota of the integration.
    var selected: QuotaPresentation {
        quotas.first { $0.id == model.menuBarQuotaID } ?? presentation
    }

    var buckets: [UsageBucket] {
        selected.summary.snapshot?.buckets ?? []
    }

    var unavailable: [KnownLimit] {
        let known = selected.summary.snapshot?.knownLimits ?? []
        return known.filter { limit in !buckets.contains { $0.id == limit.id } }
    }

    /// Limit IDs present in the latest reading.
    var availableLimitIDs: [String] {
        buckets.map(\.id)
    }

    /// Declared limits this reading omitted.
    var unavailableLimitIDs: [String] {
        unavailable.map(\.id)
    }

    var shownInMenuBar: Binding<Bool> {
        Binding(
            get: { isShownInMenuBar },
            set: { enabled in
                model.setShowsIntegrationInMenuBar(enabled, integrationID: integrationID)
            }
        )
    }

    /// Whether this quota's today's allowance is drawn in the menu bar.
    func dailyQuotaBinding(_ quotaID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                model.menuBarPreferences.showsDailyAllowance(
                    quotaID: quotaID,
                    integrationID: integrationID,
                    plannedQuotaID: selected.id
                )
            },
            set: { enabled in
                model.updateMenuBarPreferences {
                    $0.setShowsDailyAllowance(
                        enabled,
                        for: quotaID,
                        integrationID: integrationID,
                        plannedQuotaID: selected.id
                    )
                }
            }
        )
    }

    /// A daily quota that is on can be switched off only while another one
    /// stays on; a hidden one can always be switched back on.
    func canToggleDailyQuota(_ quotaID: UUID) -> Bool {
        let preferences = model.menuBarPreferences
        let shown = preferences.showsDailyAllowance(
            quotaID: quotaID,
            integrationID: integrationID,
            plannedQuotaID: selected.id
        )
        return !shown || preferences.canHideDailyQuota(
            quotaID: quotaID,
            integrationID: integrationID,
            plannedQuotaID: selected.id
        )
    }

    func dailyQuotaHelp(_ quotaID: UUID, title: String) -> String {
        guard canToggleDailyQuota(quotaID) else {
            return "At least one daily quota must stay in the menu bar"
        }
        let shown = model.menuBarPreferences.showsDailyAllowance(
            quotaID: quotaID,
            integrationID: integrationID,
            plannedQuotaID: selected.id
        )
        return shown
            ? "Hide \(title) from the menu bar"
            : "Show \(title) in the menu bar"
    }

    /// Whether this limit is drawn. Limits are off by default; choosing one
    /// adds it to the menu bar whether or not the latest reading carried it.
    func limitBinding(_ bucketID: String) -> Binding<Bool> {
        Binding(
            get: {
                model.menuBarPreferences.showsLimit(
                    bucketID,
                    integrationID: integrationID,
                    availableLimitIDs: availableLimitIDs,
                    unavailableLimitIDs: unavailableLimitIDs
                )
            },
            set: { enabled in
                model.updateMenuBarPreferences {
                    $0.setShowsLimit(
                        enabled,
                        limitID: bucketID,
                        integrationID: integrationID,
                        availableLimitIDs: availableLimitIDs,
                        unavailableLimitIDs: unavailableLimitIDs
                    )
                }
            }
        )
    }

    /// A shown limit can be switched off only while another one stays on; a
    /// hidden one can always be switched back on.
    func canToggleLimit(_ limitID: String) -> Bool {
        let preferences = model.menuBarPreferences
        let shown = preferences.showsLimit(
            limitID,
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        return !shown || preferences.canHideLimit(
            limitID,
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
    }

    func limitHelp(_ name: String, limitID: String) -> String {
        guard canToggleLimit(limitID) else {
            return "At least one limit must stay in the menu bar"
        }
        let shown = model.menuBarPreferences.showsLimit(
            limitID,
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        return shown
            ? "Hide \(name) from the menu bar"
            : "Show \(name) in the menu bar"
    }
}
