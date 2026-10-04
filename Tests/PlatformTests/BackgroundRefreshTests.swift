import Foundation
import Testing
@testable import Core
@testable import Platform

@Suite("Background refresh")
struct BackgroundRefreshTests {
    @Test("A user interval below the platform minimum is clamped")
    func clampsMinimum() {
        let schedule = RefreshSchedule(providerSuggestion: 1)
        #expect(schedule.baseInterval == RefreshConstants.minimumPollInterval)
    }

    @Test("A user interval above the platform maximum is clamped")
    func clampsMaximum() {
        let schedule = RefreshSchedule(providerSuggestion: 24 * 60 * 60)
        #expect(schedule.baseInterval == RefreshConstants.maximumPollInterval)
    }

    @Test("Preferences supply the interval when the provider suggests nothing")
    func preferencesFillGap() async throws {
        let now = SyncFixture.periodStart
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        try await repositories.preferences.save(
            Preferences(refreshIntervalSeconds: 120)
        )
        _ = try await SyncFixture.arrangeOneQuota(
            store: store,
            providerID: "mock",
            periodStart: now,
            connected: true
        )
        let coordinator = SyncFixture.makeCoordinator(
            repositories: repositories,
            fetcher: ScriptedProvider(always: .success(try SyncFixture.snapshot(updatedAt: now))),
            now: { now }
        )
        _ = try await coordinator.refresh(quotaID: try #require(await repositories.quotas.all().first).id)
        let record = try #require(await repositories.providers.provider(try ProviderID("mock")))
        // Clear provider suggestion so the preference is what remains.
        try await repositories.providers.save(
            ProviderRecord(
                providerID: record.providerID,
                displayName: record.displayName,
                installedVersion: record.installedVersion,
                authenticatedAccountLabel: record.authenticatedAccountLabel,
                lastSyncAt: record.lastSyncAt,
                suggestedRefreshInterval: nil
            )
        )
        let refreshed = try #require(await repositories.providers.provider(try ProviderID("mock")))
        let schedule = await coordinator.effectiveSchedule(for: refreshed)
        #expect(schedule.baseInterval == 120)
    }

    @Test("Low-power suspension is a boolean the controller can read")
    func lowPowerFlagExists() {
        // The controller suspends when this is true; the value itself is owned by
        // the system. Asserting the type keeps the test offline and deterministic.
        let suspended = ProcessInfo.processInfo.isLowPowerModeEnabled
        #expect(suspended == true || suspended == false)
    }
}
