import Core
import Platform
import SwiftUI

/// User-level settings: notifications, refresh interval, and update checks.
///
/// Shared by the management-window sidebar and the macOS Settings window, so
/// both surfaces edit the same preferences through the same model.
struct SettingsView: View {
    let model: AppModel

    @State private var notificationsEnabled = PreferenceConstants.defaultNotificationsEnabled
    @State private var refreshIntervalSeconds = RefreshConstants.defaultPollInterval
    @State private var automaticUpdateChecksEnabled =
        PreferenceConstants.defaultAutomaticUpdateChecksEnabled
    @State private var isReady = false

    var body: some View {
        Form {
            menuBarSettings
            menuBarProviders
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Enable notifications", systemImage: "bell")
                    }
                    .onChange(of: notificationsEnabled) { _, newValue in
                        guard isReady else { return }
                        Task { await model.setNotificationsEnabled(newValue) }
                    }
                    SettingInfoButton(
                        explanation: """
                        When on, Quota can alert you about quota conditions \
                        (for example a limit reached) through Notification Centre. \
                        When off, those alerts are not delivered; the menu bar and \
                        window still show the same figures.
                        """
                    )
                }
            } header: {
                Text("Notifications")
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Picker(selection: $refreshIntervalSeconds) {
                        ForEach(UpdateConstants.refreshIntervalChoices, id: \.self) { seconds in
                            Text(Self.label(for: seconds)).tag(seconds)
                        }
                    } label: {
                        Label("Poll interval", systemImage: "arrow.clockwise")
                    }
                    .onChange(of: refreshIntervalSeconds) { _, newValue in
                        guard isReady else { return }
                        Task { await model.setRefreshInterval(newValue) }
                    }
                    SettingInfoButton(
                        explanation: """
                        How often Quota re-reads a connected provider when that \
                        provider has not suggested a schedule of its own. A shorter \
                        interval keeps figures fresher and sends more requests; a \
                        longer one is quieter on the network and may show older data \
                        between polls.
                        """
                    )
                }
            } header: {
                Text("Providers Refresh")
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: $automaticUpdateChecksEnabled) {
                        Label(
                            "Check for updates automatically",
                            systemImage: "arrow.down.app"
                        )
                    }
                    .onChange(of: automaticUpdateChecksEnabled) { _, newValue in
                        guard isReady else { return }
                        Task { await model.setAutomaticUpdateChecksEnabled(newValue) }
                    }
                    SettingInfoButton(
                        explanation: """
                        When on, Quota asks GitHub for the latest release about once \
                        a day. If a newer version is found and you have not been told \
                        about it yet, the release page opens in your browser. Quota \
                        does not download or install the update itself. When off, \
                        only Check Now runs a check.
                        """
                    )
                }

                HStack {
                    Button {
                        Task { await model.checkForUpdates(force: true) }
                    } label: {
                        Label("Check Now", systemImage: "magnifyingglass")
                    }
                    .disabled(model.isCheckingForUpdates)

                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if case .available = model.updateStatus {
                    Button {
                        model.openAvailableUpdate()
                    } label: {
                        Label("Open Download Page", systemImage: "safari")
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: LayoutMetrics.providerListWidth, alignment: .leading)
        .task {
            await reloadFromPreferences()
            isReady = true
        }
    }

    private var menuBarSettings: some View {
        Section {
            Toggle("Show provider logos", isOn: menuBarBinding(\.showLogos))
            Toggle("Show daily quota", isOn: menuBarBinding(\.showDailyQuota))
            Picker("Show values", selection: menuBarBinding(\.valueMode)) {
                Text("Used and remaining").tag(MenuBarPreferences.ValueMode.both)
                Text("Used only").tag(MenuBarPreferences.ValueMode.used)
                Text("Remaining only").tag(MenuBarPreferences.ValueMode.remaining)
            }
            Text("Daily quota remaining is the amount planned for today minus the amount used.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Menu Bar")
        }
    }

    private var menuBarProviders: some View {
        Section {
            if providerPresentations.isEmpty {
                Text("Add a quota to choose which provider limits appear in the menu bar.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(providerPresentations) { presentation in
                    providerSettings(presentation)
                }
            }
        } header: {
            Text("Provider Limits")
        } footer: {
            Text("Choose the limits to display for each provider. Available limits depend on your plan.")
        }
    }

    private var providerPresentations: [QuotaPresentation] {
        var seen = Set<String>()
        return model.presentations.filter {
            seen.insert($0.summary.quota.providerID.rawValue).inserted
        }
    }

    private func providerSettings(_ presentation: QuotaPresentation) -> some View {
        let providerID = presentation.summary.quota.providerID.rawValue
        let quotas = model.presentations.filter { $0.summary.quota.providerID.rawValue == providerID }
        let selected = quotas.first { $0.id == model.menuBarPreferences.selectedQuotas[providerID] }
            ?? (model.primaryPresentation.flatMap { primary in quotas.first { $0.id == primary.id } })
            ?? presentation
        let buckets = selected.summary.snapshot?.buckets ?? []
        let unavailable = MenuBarLimits.known(for: providerID).filter { known in
            !buckets.contains { $0.id == known.id }
        }
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show in menu bar", isOn: Binding(
                    get: { !model.menuBarPreferences.hiddenProviders.contains(providerID) },
                    set: { enabled in
                        model.updateMenuBarPreferences {
                            if enabled {
                                $0.hiddenProviders.remove(providerID)
                            } else {
                                $0.hiddenProviders.insert(providerID)
                            }
                        }
                    }
                ))
                .accessibilityLabel("Show \(providerID) in menu bar")
                if !model.menuBarPreferences.hiddenProviders.contains(providerID) {
                    if model.menuBarPreferences.showDailyQuota {
                        Toggle("Today's planned quota", isOn: Binding(
                            get: { !model.menuBarPreferences.hiddenDailyProviders.contains(providerID) },
                            set: { enabled in
                                model.updateMenuBarPreferences {
                                    if enabled {
                                        $0.hiddenDailyProviders.remove(providerID)
                                    } else {
                                        $0.hiddenDailyProviders.insert(providerID)
                                    }
                                }
                            }
                        ))
                        .accessibilityLabel("\(providerID) today's planned quota")
                    }
                    if quotas.count > 1 {
                        Picker("Planned quota", selection: Binding(
                            get: { selected.id },
                            set: { id in model.updateMenuBarPreferences { $0.selectedQuotas[providerID] = id } }
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
                        Toggle(bucket.displayName, isOn: limitBinding(providerID, bucket.id, available: true))
                            .accessibilityLabel("\(providerID) \(bucket.displayName)")
                    }
                    if !unavailable.isEmpty {
                        DisclosureGroup("Unavailable limits (\(unavailable.count))") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(
                                    "These limits may be unavailable for your plan or missing from the latest update. Selected limits show a dash until data is available."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                ForEach(unavailable) { limit in
                                    Toggle(limit.name, isOn: limitBinding(providerID, limit.id, available: false))
                                        .accessibilityLabel("\(providerID) \(limit.name), unavailable")
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    if buckets.isEmpty {
                        Text("No limits reported in the latest update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                ProviderMark(providerID: providerID, size: 18, sizesNativeImage: true)
                Text(model.sections.listing(id: providerID)?.displayName ?? presentation.summary.quota.name)
                    .font(.headline)
            }
        }
    }

    private func limitBinding(_ providerID: String, _ bucketID: String, available: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let preferences = model.menuBarPreferences
                return !(preferences.hiddenBuckets[providerID] ?? []).contains(bucketID)
                    && (available || (preferences.shownUnavailableBuckets[providerID] ?? []).contains(bucketID))
            },
            set: { enabled in
                model.updateMenuBarPreferences {
                    if enabled {
                        $0.hiddenBuckets[providerID, default: []].remove(bucketID)
                        $0.shownUnavailableBuckets[providerID, default: []].insert(bucketID)
                    } else {
                        $0.hiddenBuckets[providerID, default: []].insert(bucketID)
                        $0.shownUnavailableBuckets[providerID, default: []].remove(bucketID)
                    }
                }
            }
        )
    }

    private func menuBarBinding<Value>(_ keyPath: WritableKeyPath<MenuBarPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.menuBarPreferences[keyPath: keyPath] },
            set: { value in model.updateMenuBarPreferences { $0[keyPath: keyPath] = value } }
        )
    }

    private var statusText: String {
        switch model.updateStatus {
        case .idle:
            " "
        case .checking:
            "Checking…"
        case .upToDate:
            "Quota is up to date."
        case .available(let version, _):
            "Version \(version) is available."
        case .failed(let message):
            message
        }
    }

    private func reloadFromPreferences() async {
        notificationsEnabled = await model.notificationsEnabled()
        refreshIntervalSeconds = await Self.nearestChoice(
            model.effectiveRefreshIntervalSeconds()
        )
        automaticUpdateChecksEnabled = await model.automaticUpdateChecksEnabled()
    }

    /// The offered interval closest to a stored preference.
    private static func nearestChoice(_ seconds: TimeInterval) -> TimeInterval {
        let choices = UpdateConstants.refreshIntervalChoices
        return choices.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? seconds
    }

    /// A short label for a poll interval shown in the picker.
    private static func label(for seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes == 1 {
            return "1 minute"
        }
        if minutes < 60 {
            return "\(minutes) minutes"
        }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

/// A compact “i” that shows what changing a setting does.
private struct SettingInfoButton: View {
    let explanation: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("About this setting")
        .accessibilityLabel("About this setting")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: LayoutMetrics.settingsInfoPopoverWidth, alignment: .leading)
                .padding(LayoutMetrics.inset)
        }
    }
}
