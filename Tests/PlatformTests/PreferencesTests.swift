import Foundation
import Testing
@testable import Platform

@Suite("Preferences")
struct PreferencesTests {
    @Test("Preferences fall back to defaults when nothing is stored")
    func preferencesDefault() async throws {
        let store = CodableStore.inMemory()
        #expect(try await PreferencesRepository(store: store).load() == .default)
    }

    @Test("Saved preferences are read back")
    func preferencesRoundTrip() async throws {
        let store = CodableStore.inMemory()
        let repository = PreferencesRepository(store: store)
        let preferences = Preferences(
            defaultPolicyKind: "weekly",
            hasCompletedOnboarding: true,
            refreshIntervalSeconds: 300
        )
        try await repository.save(preferences)
        #expect(try await repository.load() == preferences)
    }

    @Test("A missing notificationsEnabled key defaults rather than failing decode")
    func preferencesMissingNotificationsDefault() throws {
        let json = Data("""
        {
          "defaultPolicyKind": "monthly",
          "hasCompletedOnboarding": true,
          "refreshIntervalSeconds": 900,
          "disabledProviders": []
        }
        """.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.notificationsEnabled == PreferenceConstants.defaultNotificationsEnabled)
        #expect(preferences.defaultPolicyKind == "monthly")
        #expect(preferences.hasCompletedOnboarding == true)
        #expect(preferences.refreshIntervalSeconds == 900)
        #expect(preferences.refreshIntervalSecondsByProvider.isEmpty)
        #expect(preferences.disabledProviders.isEmpty)
        #expect(preferences.menuBarQuotaID == nil)
        #expect(
            preferences.automaticUpdateChecksEnabled
                == PreferenceConstants.defaultAutomaticUpdateChecksEnabled
        )
        #expect(preferences.lastUpdateCheckAt == nil)
        #expect(preferences.announcedUpdateVersion == nil)
    }

    @Test("Update-check preference fields round-trip")
    func preferencesUpdateFieldsRoundTrip() async throws {
        let store = CodableStore.inMemory()
        let repository = PreferencesRepository(store: store)
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let preferences = Preferences(
            automaticUpdateChecksEnabled: false,
            lastUpdateCheckAt: checkedAt,
            announcedUpdateVersion: "1.4.0"
        )
        try await repository.save(preferences)
        #expect(try await repository.load() == preferences)
    }

    @Test("An integration interval survives a round trip and can be cleared")
    func providerIntervalRoundTrip() throws {
        let stored = Preferences(refreshIntervalSeconds: 60).withRefreshInterval(300, for: "claude")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(stored))
        #expect(decoded.refreshInterval(for: "claude") == 300)
        #expect(decoded.refreshInterval(for: "codex") == 60)
        let cleared = stored.withRefreshInterval(nil, for: "claude")
        #expect(cleared.refreshIntervalSecondsByProvider.isEmpty)
        #expect(cleared.refreshInterval(for: "claude") == 60)
    }

    @Test("Popover orders survive encoding and older menu preferences decode")
    func popoverOrdersRoundTrip() throws {
        var options = MenuBarPreferences()
        options.keepRunningOnClose = true
        options.popoverProviderOrder = ["claude:YWJj", "codex:ZGVm"]
        options.popoverItemOrder = ["claude:YWJj": ["bucket:five_hour", "quota:123"]]
        let decoded = try JSONDecoder().decode(MenuBarPreferences.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
        let old = try JSONDecoder().decode(MenuBarPreferences.self, from: Data("{}".utf8))
        #expect(!old.keepRunningOnClose)
        #expect(old.popoverProviderOrder.isEmpty)
        #expect(old.popoverItemOrder.isEmpty)
    }
}
