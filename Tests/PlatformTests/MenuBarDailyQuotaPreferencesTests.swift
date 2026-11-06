import Foundation
import Testing
@testable import Platform

@Suite("Menu bar daily quotas")
struct MenuBarDailyQuotaPreferencesTests {
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

    @Test("The last daily quota cannot be hidden")
    func lastDailyQuotaStays() {
        var menuBar = MenuBarPreferences()
        let planned = UUID()
        let other = UUID()

        #expect(
            !menuBar.canHideDailyQuota(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )

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
            menuBar.showsDailyAllowance(
                quotaID: other,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
        #expect(
            !menuBar.canHideDailyQuota(
                quotaID: other,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
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
        menuBar.showAvailableLimits = true
        menuBar.setShowsDailyQuota(false)
        #expect(!menuBar.showDailyQuota)
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

    @Test("Deleting a quota removes it from every daily list")
    func deleteQuotaClearsDailySelections() {
        var menuBar = MenuBarPreferences()
        let planned = UUID()
        let other = UUID()
        menuBar.setShowsDailyAllowance(
            true,
            for: other,
            integrationID: "cursor",
            plannedQuotaID: planned
        )
        menuBar.deleteQuota(other)

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
        #expect(
            !menuBar.canHideDailyQuota(
                quotaID: planned,
                integrationID: "cursor",
                plannedQuotaID: planned
            )
        )
    }
}
