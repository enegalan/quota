import Core
import Platform
import SwiftUI

/// Which limits each integration shows in the menu bar.
struct MenuBarIntegrationSettings: View {
    let model: AppModel

    fileprivate static let explanation = """
    Choose which quotas show today's allowance, and which limits to \
    display. Available limits depend on your plan.

    Show in menu bar includes that integration. When off, none of its \
    figures are drawn.

    Today's planned quota is the allowance for today. With more than one \
    quota, each can be included; one is labelled Today, and more than one \
    are named. Those rows follow the Show daily quota switch.

    The limits listed below are the ones in the latest update. Unavailable \
    limits may be missing from your plan or from that update. A selected \
    one shows a dash until data is available.
    """

    var body: some View {
        Section {
            if items.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Add a quota to choose which integration limits appear in the menu bar.")
                        .foregroundStyle(.secondary)
                    SettingInfoButton(explanation: Self.explanation)
                }
            } else {
                ForEach(items) { item in
                    IntegrationLimitRowView(model: model, item: item)
                }
            }
        } header: {
            Text("Integration Limits")
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
        case .limitsHeader:
            groupLabel("Available limits")
        case .limit(let bucket):
            Toggle(bucket.displayName, isOn: slice.limitBinding(bucket.id, available: true))
                .accessibilityLabel("\(slice.integrationID) \(bucket.displayName)")
        case .unavailable:
            DisclosureGroup("Unavailable limits (\(slice.unavailable.count))") {
                VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
                    Text(
                        "These limits may be unavailable for your plan or missing from the latest update. Selected limits show a dash until data is available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(slice.unavailable) { limit in
                        Toggle(
                            limit.name,
                            isOn: slice.limitBinding(
                                limit.id,
                                available: false,
                                shownByDefault: limit.shownWhenUnavailable
                            )
                        )
                        .accessibilityLabel("\(slice.integrationID) \(limit.name), unavailable")
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
private struct IntegrationSlice {
    let model: AppModel
    let presentation: QuotaPresentation

    var integrationID: String {
        presentation.summary.quota.providerID.rawValue
    }

    var displayName: String {
        model.sections.listing(id: integrationID)?.displayName ?? presentation.summary.quota.name
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

    var shownInMenuBar: Binding<Bool> {
        Binding(
            get: { !model.menuBarPreferences.hiddenIntegrations.contains(integrationID) },
            set: { enabled in
                model.updateMenuBarPreferences {
                    if enabled {
                        $0.hiddenIntegrations.remove(integrationID)
                    } else {
                        $0.hiddenIntegrations.insert(integrationID)
                    }
                }
            }
        )
    }

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

    func limitBinding(
        _ bucketID: String,
        available: Bool,
        shownByDefault: Bool = false
    ) -> Binding<Bool> {
        Binding(
            get: { isShown(bucketID, available: available, shownByDefault: shownByDefault) },
            set: { enabled in
                model.updateMenuBarPreferences {
                    if enabled {
                        $0.hiddenBuckets[integrationID, default: []].remove(bucketID)
                        $0.shownUnavailableBuckets[integrationID, default: []].insert(bucketID)
                    } else {
                        $0.hiddenBuckets[integrationID, default: []].insert(bucketID)
                        $0.shownUnavailableBuckets[integrationID, default: []].remove(bucketID)
                    }
                }
            }
        )
    }

    private func isShown(_ bucketID: String, available: Bool, shownByDefault: Bool) -> Bool {
        let preferences = model.menuBarPreferences
        let hidden = (preferences.hiddenBuckets[integrationID] ?? []).contains(bucketID)
        if hidden {
            return false
        }
        if available {
            return true
        }
        let chosen = (preferences.shownUnavailableBuckets[integrationID] ?? []).contains(bucketID)
        return chosen || shownByDefault
    }
}

@MainActor
private struct IntegrationLimitItem: Identifiable {
    enum Kind {
        case identity
        case dailyHeader
        case daily(QuotaPresentation)
        case limitsHeader
        case limit(UsageBucket)
        case unavailable
        case noLimits
    }

    let id: String
    let presentation: QuotaPresentation
    let kind: Kind
    /// Extra space above a later integration, so two providers do not read as one list.
    let separates: Bool

    static func rows(
        model: AppModel,
        presentation: QuotaPresentation,
        separates: Bool
    ) -> [IntegrationLimitItem] {
        let slice = IntegrationSlice(model: model, presentation: presentation)
        let prefix = slice.integrationID
        var built = [
            IntegrationLimitItem(
                id: "\(prefix)-identity",
                presentation: presentation,
                kind: .identity,
                separates: separates
            ),
        ]
        guard !model.menuBarPreferences.hiddenIntegrations.contains(prefix) else { return built }
        if model.menuBarPreferences.showDailyQuota {
            if slice.quotas.count > 1 {
                built.append(item(prefix, "daily-header", presentation, .dailyHeader))
            }
            for quota in slice.quotas {
                built.append(item(prefix, "daily-\(quota.id.uuidString)", presentation, .daily(quota)))
            }
        }
        if slice.buckets.isEmpty {
            built.append(item(prefix, "no-limits", presentation, .noLimits))
        } else {
            built.append(item(prefix, "limits-header", presentation, .limitsHeader))
            for bucket in slice.buckets {
                built.append(item(prefix, "limit-\(bucket.id)", presentation, .limit(bucket)))
            }
        }
        if !slice.unavailable.isEmpty {
            built.append(item(prefix, "unavailable", presentation, .unavailable))
        }
        return built
    }

    private static func item(
        _ prefix: String,
        _ suffix: String,
        _ presentation: QuotaPresentation,
        _ kind: Kind
    ) -> IntegrationLimitItem {
        IntegrationLimitItem(
            id: "\(prefix)-\(suffix)",
            presentation: presentation,
            kind: kind,
            separates: false
        )
    }
}
