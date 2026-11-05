import Foundation
import Testing
@testable import Platform

@Suite("Menu bar figure switches")
struct MenuBarFigureSwitchPreferencesTests {
    @Test("The last figure switch cannot be turned off")
    func lastFigureSwitchStaysOn() {
        var menuBar = MenuBarPreferences()

        #expect(!menuBar.canTurnOffDailyQuota)
        menuBar.setShowsDailyQuota(false)
        #expect(menuBar.showDailyQuota)

        menuBar.setShowsAvailableLimits(true)
        #expect(menuBar.canTurnOffDailyQuota)
        menuBar.setShowsDailyQuota(false)
        #expect(!menuBar.showDailyQuota)

        #expect(!menuBar.canTurnOffAvailableLimits)
        menuBar.setShowsAvailableLimits(false)
        #expect(menuBar.showAvailableLimits)
    }

    @Test("The last figure switch can be swapped rather than only kept")
    func figureSwitchCanBeSwapped() {
        var menuBar = MenuBarPreferences()
        menuBar.setShowsAvailableLimits(true)
        menuBar.setShowsDailyQuota(false)

        menuBar.setShowsDailyQuota(true)
        menuBar.setShowsAvailableLimits(false)

        #expect(menuBar.showDailyQuota)
        #expect(!menuBar.showAvailableLimits)
    }

    @Test("A stored menu bar with both switches off returns to today's allowance")
    func storedBothOffReturnsToDaily() throws {
        let preferences = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: Data("""
            {"showDailyQuota":false,"showAvailableLimits":false}
            """.utf8)
        )

        #expect(preferences.showDailyQuota)
        #expect(!preferences.showAvailableLimits)
    }

    @Test("A missing showAvailableLimits key follows the inverse of today's allowance")
    func missingAvailableLimitsFollowsDaily() throws {
        let dailyOff = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: Data("""
            {"showDailyQuota":false}
            """.utf8)
        )
        #expect(!dailyOff.showDailyQuota)
        #expect(dailyOff.showAvailableLimits)

        let dailyOn = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: Data("""
            {"showDailyQuota":true}
            """.utf8)
        )
        #expect(dailyOn.showDailyQuota)
        #expect(!dailyOn.showAvailableLimits)
    }
}
