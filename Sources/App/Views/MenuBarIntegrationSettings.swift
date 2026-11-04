import Core
import Platform
import SwiftUI

/// Which limits each integration shows in the menu bar.
struct MenuBarIntegrationSettings: View {
    let model: AppModel

    var body: some View {
        Section {
            if integrationPresentations.isEmpty {
                Text("Add a quota to choose which integration limits appear in the menu bar.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(integrationPresentations) { presentation in
                    MenuBarIntegrationRow(model: model, presentation: presentation)
                }
            }
        } header: {
            Text("Integration Limits")
        } footer: {
            Text("Choose the limits to display for each integration. Available limits depend on your plan.")
        }
    }

    private var integrationPresentations: [QuotaPresentation] {
        var seen = Set<String>()
        return model.presentations.filter {
            seen.insert($0.summary.quota.providerID.rawValue).inserted
        }
    }
}

private struct MenuBarIntegrationRow: View {
    let model: AppModel
    let presentation: QuotaPresentation

    var body: some View {
        let integrationID = presentation.summary.quota.providerID.rawValue
        let quotas = model.presentations.filter { $0.summary.quota.providerID.rawValue == integrationID }
        let selected = quotas.first { $0.id == model.menuBarPreferences.selectedQuotas[integrationID] }
            ?? model.primaryPresentation.flatMap { primary in quotas.first { $0.id == primary.id } }
            ?? presentation
        let buckets = selected.summary.snapshot?.buckets ?? []
        let unavailable = (selected.summary.snapshot?.knownLimits ?? []).filter { known in
            !buckets.contains { $0.id == known.id }
        }
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show in menu bar", isOn: shownInMenuBar(integrationID))
                    .accessibilityLabel("Show \(integrationID) in menu bar")
                if !model.menuBarPreferences.hiddenIntegrations.contains(integrationID) {
                    MenuBarLimitControls(
                        model: model,
                        integrationID: integrationID,
                        quotas: quotas,
                        selected: selected,
                        buckets: buckets,
                        unavailable: unavailable
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                ProviderMark(providerID: integrationID, size: 18, sizesNativeImage: true)
                Text(model.sections.listing(id: integrationID)?.displayName ?? presentation.summary.quota.name)
                    .font(.headline)
            }
        }
    }

    private func shownInMenuBar(_ integrationID: String) -> Binding<Bool> {
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
}

private struct MenuBarLimitControls: View {
    let model: AppModel
    let integrationID: String
    let quotas: [QuotaPresentation]
    let selected: QuotaPresentation
    let buckets: [UsageBucket]
    let unavailable: [KnownLimit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.menuBarPreferences.showDailyQuota {
                Toggle("Today's planned quota", isOn: showsDailyQuota)
                    .accessibilityLabel("\(integrationID) today's planned quota")
            }
            if quotas.count > 1 {
                Picker("Planned quota", selection: Binding(
                    get: { selected.id },
                    set: { id in
                        let pinnedHere = model.presentations.contains { presentation in
                            presentation.id == model.menuBarQuotaID
                                && presentation.summary.quota.providerID.rawValue == integrationID
                        }
                        guard pinnedHere, let quota = quotas.first(where: { $0.id == id }) else {
                            model.updateMenuBarPreferences { $0.selectedQuotas[integrationID] = id }
                            return
                        }
                        Task { await model.showInMenuBar(quota) }
                    }
                )) {
                    ForEach(quotas) { quota in
                        Text(quota.summary.quota.name).tag(quota.id)
                    }
                }
            }
            if !buckets.isEmpty {
                Text("Available limits")
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(buckets) { bucket in
                Toggle(bucket.displayName, isOn: limitBinding(bucket.id, available: true))
                    .accessibilityLabel("\(integrationID) \(bucket.displayName)")
            }
            if !unavailable.isEmpty {
                DisclosureGroup("Unavailable limits (\(unavailable.count))") {
                    unavailableList
                }
            }
            if buckets.isEmpty {
                Text("No limits reported in the latest update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsDailyQuota: Binding<Bool> {
        Binding(
            get: { !model.menuBarPreferences.hiddenDailyIntegrations.contains(integrationID) },
            set: { enabled in
                model.updateMenuBarPreferences {
                    if enabled {
                        $0.hiddenDailyIntegrations.remove(integrationID)
                    } else {
                        $0.hiddenDailyIntegrations.insert(integrationID)
                    }
                }
            }
        )
    }

    private var unavailableList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "These limits may be unavailable for your plan or missing from the latest update. Selected limits show a dash until data is available."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(unavailable) { limit in
                Toggle(
                    limit.name,
                    isOn: limitBinding(
                        limit.id,
                        available: false,
                        shownByDefault: limit.shownWhenUnavailable
                    )
                )
                .accessibilityLabel("\(integrationID) \(limit.name), unavailable")
            }
        }
        .padding(.top, 8)
    }

    private func limitBinding(
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
