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

    @Test("An integration override fills the gap when nothing is suggested")
    func integrationOverrideFillsGap() async throws {
        let now = SyncFixture.periodStart
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        try await repositories.preferences.save(
            Preferences().withRefreshInterval(120, for: "mock")
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

    @Test("An integration's suggested default beats the platform schedule")
    func suggestedIntervalPrecedesPlatformDefault() async throws {
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        let coordinator = SyncFixture.makeCoordinator(
            repositories: repositories,
            fetcher: ScriptedProvider([]),
            now: { SyncFixture.periodStart }
        )
        let record = ProviderRecord(
            providerID: try ProviderID("mock"), displayName: "Mock", installedVersion: "1",
            suggestedRefreshInterval: 300
        )
        #expect(await coordinator.effectiveSchedule(for: record).baseInterval == 300)
    }

    @Test("The platform schedule is used when an integration suggests nothing")
    func platformScheduleFillsGap() async throws {
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        let coordinator = SyncFixture.makeCoordinator(
            repositories: repositories,
            fetcher: ScriptedProvider([]),
            now: { SyncFixture.periodStart }
        )
        let record = ProviderRecord(
            providerID: try ProviderID("mock"), displayName: "Mock", installedVersion: "1",
            suggestedRefreshInterval: nil
        )
        #expect(
            await coordinator.effectiveSchedule(for: record).baseInterval
                == RefreshConstants.defaultPollInterval
        )
    }

    @Test("A user override beats the integration's suggested default")
    func userIntervalPrecedesSuggestion() async throws {
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        try await repositories.preferences.save(
            Preferences().withRefreshInterval(300, for: "mock")
        )
        let coordinator = SyncFixture.makeCoordinator(
            repositories: repositories,
            fetcher: ScriptedProvider([]),
            now: { SyncFixture.periodStart }
        )
        let record = ProviderRecord(
            providerID: try ProviderID("mock"), displayName: "Mock", installedVersion: "1",
            suggestedRefreshInterval: 15 * 60
        )
        #expect(await coordinator.effectiveSchedule(for: record).baseInterval == 300)
    }
}
