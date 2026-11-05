import Foundation
import Testing
@testable import Platform

@Suite("Menu bar limits")
struct MenuBarLimitPreferencesTests {
    @Test("Limits stay hidden until Show available limits is on")
    func limitsAreOffByDefault() {
        var menuBar = MenuBarPreferences()
        let available = ["5h", "1w"]
        menuBar.setShowsLimit(
            true,
            limitID: "5h",
            integrationID: "claude",
            availableLimitIDs: available
        )

        #expect(!menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))

        menuBar.showAvailableLimits = true

        #expect(menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))

        menuBar.showAvailableLimits = false

        #expect(!menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))
    }

    @Test("An integration keeps at least one limit while Show available limits is on")
    func availableLimitKeepsOne() {
        var menuBar = MenuBarPreferences()
        menuBar.showAvailableLimits = true
        let available = ["5h", "1w"]

        // The first available limit stands in until the user chooses one.
        #expect(menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))
        #expect(
            !menuBar.canHideLimit("5h", integrationID: "claude", availableLimitIDs: available)
        )

        menuBar.setShowsLimit(
            true,
            limitID: "1w",
            integrationID: "claude",
            availableLimitIDs: available
        )
        #expect(menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))
        #expect(menuBar.showsLimit("1w", integrationID: "claude", availableLimitIDs: available))

        menuBar.setShowsLimit(
            false,
            limitID: "5h",
            integrationID: "claude",
            availableLimitIDs: available
        )
        #expect(!menuBar.showsLimit("5h", integrationID: "claude", availableLimitIDs: available))
        #expect(menuBar.showsLimit("1w", integrationID: "claude", availableLimitIDs: available))
        #expect(
            !menuBar.canHideLimit("1w", integrationID: "claude", availableLimitIDs: available)
        )
    }

    @Test("A limit choice survives a round trip")
    func limitChoiceRoundTrip() throws {
        var menuBar = MenuBarPreferences()
        menuBar.showAvailableLimits = true
        let available = ["5h", "1w"]
        menuBar.setShowsLimit(
            true,
            limitID: "1w",
            integrationID: "claude",
            availableLimitIDs: available
        )

        let decoded = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: JSONEncoder().encode(menuBar)
        )

        #expect(decoded.showsLimit("1w", integrationID: "claude", availableLimitIDs: available))
    }

    @Test("Limits chosen before limits were off by default are kept")
    func legacyChosenLimitsAreRead() throws {
        var preferences = try JSONDecoder().decode(
            MenuBarPreferences.self,
            from: Data("""
            {"shownUnavailableBuckets":{"claude":["5h"]}}
            """.utf8)
        )
        #expect(!preferences.showAvailableLimits)

        preferences.showAvailableLimits = true

        #expect(preferences.showsLimit("5h", integrationID: "claude", availableLimitIDs: ["5h"]))
    }
}
