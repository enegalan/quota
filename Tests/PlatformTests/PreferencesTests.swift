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
}
