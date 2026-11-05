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
            MenuBarIntegrationSettings(model: model)
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
            HStack(alignment: .firstTextBaseline) {
                Toggle("Show integration logos", isOn: menuBarBinding(\.showLogos))
                SettingInfoButton(explanation: Self.logosExplanation)
            }
            HStack(alignment: .firstTextBaseline) {
                Toggle("Show daily quota", isOn: showsDailyQuotaBinding)
                    .disabled(dailyQuotaSwitchIsDisabled)
                    .help(dailyQuotaSwitchIsDisabled ? Self.figureSwitchHelp : "")
                SettingInfoButton(explanation: Self.dailyQuotaExplanation)
            }
            HStack(alignment: .firstTextBaseline) {
                Toggle("Show available limits", isOn: showsAvailableLimitsBinding)
                    .disabled(availableLimitsSwitchIsDisabled)
                    .help(availableLimitsSwitchIsDisabled ? Self.figureSwitchHelp : "")
                SettingInfoButton(explanation: Self.availableLimitsExplanation)
            }
            HStack(alignment: .firstTextBaseline) {
                Picker("Show values", selection: menuBarBinding(\.valueMode)) {
                    Text("Used and remaining").tag(MenuBarPreferences.ValueMode.both)
                    Text("Used only").tag(MenuBarPreferences.ValueMode.used)
                    Text("Remaining only").tag(MenuBarPreferences.ValueMode.remaining)
                }
                SettingInfoButton(explanation: Self.valuesExplanation)
            }
        } header: {
            Text("Menu Bar")
        }
    }

    private static let logosExplanation = """
    When on, each integration in the menu bar starts with its provider \
    mark. When off, the integration name is shown instead.
    """

    private static let dailyQuotaExplanation = """
    When on, the menu bar includes today's allowance for the quotas \
    switched on under Integration Limits. Remaining is the amount planned \
    for today minus the amount used. Each integration keeps at least one \
    quota switched on. When off, those Today figures are hidden. If Show \
    available limits is also off, this switch stays on so the menu bar \
    keeps a figure.
    """

    private static let availableLimitsExplanation = """
    When on, the menu bar includes the limits switched on under Integration \
    Limits. Each integration keeps at least one limit switched on. When off, \
    those limit figures are hidden. If Show daily quota is also off, this \
    switch stays on so the menu bar keeps a figure.
    """

    private static let figureSwitchHelp = """
    At least one of Show daily quota and Show available limits must stay on.
    """

    private static let valuesExplanation = """
    The figures drawn beside each limit. Used and remaining shows both; \
    used only and remaining only show one of them. A figure that has not \
    been read yet is a dash.
    """

    /// A binding that writes one menu-bar preference through the model.
    private func menuBarBinding<Value>(_ keyPath: WritableKeyPath<MenuBarPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.menuBarPreferences[keyPath: keyPath] },
            set: { value in model.updateMenuBarPreferences { $0[keyPath: keyPath] = value } }
        )
    }

    /// The daily switch, which stays on when it is the only figure shown.
    private var showsDailyQuotaBinding: Binding<Bool> {
        Binding(
            get: { model.menuBarPreferences.showDailyQuota },
            set: { enabled in
                model.updateMenuBarPreferences { $0.setShowsDailyQuota(enabled) }
            }
        )
    }

    /// The limits switch, which stays on when it is the only figure shown.
    private var showsAvailableLimitsBinding: Binding<Bool> {
        Binding(
            get: { model.menuBarPreferences.showAvailableLimits },
            set: { enabled in
                model.updateMenuBarPreferences { $0.setShowsAvailableLimits(enabled) }
            }
        )
    }

    private var dailyQuotaSwitchIsDisabled: Bool {
        let preferences = model.menuBarPreferences
        return preferences.showDailyQuota && !preferences.canTurnOffDailyQuota
    }

    private var availableLimitsSwitchIsDisabled: Bool {
        let preferences = model.menuBarPreferences
        return preferences.showAvailableLimits && !preferences.canTurnOffAvailableLimits
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
struct SettingInfoButton: View {
    let explanation: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
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
