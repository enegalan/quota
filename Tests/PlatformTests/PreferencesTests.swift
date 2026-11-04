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

    @Test("Without a daily quota choice, only the planned quota is shown")
    func plannedQuotaIsTheDailyQuotaUntilChosen() {
        let menuBar = MenuBarPreferences()
        let planned = UUID()
        let other = UUID()
        #expect(
            menuBar.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        #expect(
            !menuBar.showsDailyAllowance(
                quotaID: other,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
    }

    @Test("A hidden integration shows no daily quota until one is chosen")
    func hiddenIntegrationShowsNoDailyQuota() {
        var menuBar = MenuBarPreferences()
        menuBar.hiddenDailyIntegrations = ["cursor"]
        let planned = UUID()
        #expect(
            !menuBar.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        menuBar.setShowsDailyAllowance(
            true,
            for: planned,
            integrationID: "cursor",
            plannedQuotaID: planned
        )
        #expect(
            menuBar.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        #expect(!menuBar.hiddenDailyIntegrations.contains("cursor"))
    }

    @Test("Each quota can show today's allowance on its own")
    func dailyQuotaPerQuota() {
        var menuBar = MenuBarPreferences()
        let planned = UUID()
        let other = UUID()
        menuBar.setShowsDailyAllowance(
            true,
            for: other,
            integrationID: "cursor",
            plannedQuotaID: planned
        )
        menuBar.setShowsDailyAllowance(
            false,
            for: planned,
            integrationID: "cursor",
            plannedQuotaID: planned
        )
        #expect(
            !menuBar.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        #expect(
            menuBar.showsDailyAllowance(
                quotaID: other,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
    }

    @Test("The global daily switch hides every quota's allowance")
    func globalDailySwitchHidesAllowances() {
        var menuBar = MenuBarPreferences()
        let planned = UUID()
        menuBar.showDailyQuota = false
        #expect(
            !menuBar.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
    }

    @Test("Chosen daily quotas survive a round trip")
    func dailyQuotasRoundTrip() throws {
        var menuBar = MenuBarPreferences()
        let planned = UUID()
        let other = UUID()
        menuBar.hiddenDailyIntegrations = ["cursor"]
        menuBar.setShowsDailyAllowance(
            true,
            for: other,
            integrationID: "cursor",
            plannedQuotaID: planned
        )
        let decoded = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: JSONEncoder().encode(menuBar)
        )
        #expect(
            decoded.showsDailyAllowance(
                quotaID: other,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        #expect(
            !decoded.showsDailyAllowance(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
    }

    @Test("A stored menu bar without daily quotas still decodes")
    func menuBarMissingDailyQuotas() throws {
        let preferences = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: Data("{\"showLogos\":false}".utf8)
        )
        #expect(!preferences.showLogos)
        #expect(preferences.dailyQuotas.isEmpty)
        #expect(preferences.showDailyQuota)
    }
}
