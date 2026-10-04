import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Resilience")
struct ResilienceTests {
    private typealias Fixture = SyncFixture

    @Test("Every provider failing still leaves every quota renderable")
    func allProvidersFailingStillRender() async throws {
        let now = Fixture.periodStart
        let failing = ScriptedProvider(always: .failure(Fixture.failure(.networkUnavailable, at: now)))
        let harness = try await Fixture.makeHarness(fetcher: failing, now: now)
        // Seed a good reading first, then fail forever.
        let good = try Fixture.snapshot(updatedAt: now)
        try await harness.snapshots.save(
            SnapshotRecord(
                quotaID: harness.quota.id,
                bucketID: good.primaryBucket?.id ?? "models",
                accountLabel: "work@example.com",
                snapshot: good
            )
        )
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let shown = try await harness.coordinator.reading(for: harness.quota.id)
        #expect(shown.reading != nil)
        let record = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(record.lastFailure != nil || shown.reading != nil)
    }

    @Test("A quota whose provider vanished keeps its data and is unrefreshable")
    func vanishedProviderKeepsData() async throws {
        let now = Fixture.periodStart
        let harness = try await Fixture.makeHarness(
            fetcher: ScriptedProvider(always: .success(try Fixture.snapshot(updatedAt: now))),
            now: now
        )
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        let continuity = QuotaContinuity(
            quotas: harness.quotas,
            snapshots: harness.snapshots,
            timeline: harness.timelines,
            installed: InstalledProviderRepository(store: harness.store),
            disabledProviders: []
        )
        // Remove the install record so the provider is "missing".
        try await harness.store.saveInstalledProviders([])
        let blocked = try await continuity.unrefreshable()
        #expect(blocked.contains { $0.quotaID == harness.quota.id && $0.reason == .missing })
        let shown = try await harness.coordinator.reading(for: harness.quota.id)
        #expect(shown.reading != nil)
    }

    @Test("A kill-switched provider is reported as disabled, not deleted")
    func killSwitchLeavesData() async throws {
        let now = Fixture.periodStart
        let harness = try await Fixture.makeHarness(
            fetcher: ScriptedProvider(always: .success(try Fixture.snapshot(updatedAt: now))),
            now: now
        )
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let continuity = QuotaContinuity(
            quotas: harness.quotas,
            snapshots: harness.snapshots,
            timeline: harness.timelines,
            installed: InstalledProviderRepository(store: harness.store),
            disabledProviders: [harness.quota.providerID.rawValue]
        )
        let blocked = try await continuity.unrefreshable()
        #expect(blocked.contains { $0.reason == .disabled })
    }

    @Test("Diagnostic-shaped failure codes never require a credential to classify")
    func failureCodesAreCredentialFree() {
        for code in ProviderErrorCode.allCases {
            let message = ProviderError.defaultMessage(for: code)
            #expect(!message.lowercased().contains("token"))
            #expect(!message.lowercased().contains("password"))
            #expect(!message.lowercased().contains("secret"))
        }
    }
}
