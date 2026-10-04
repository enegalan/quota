import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Sync coordinator")
struct SyncCoordinatorTests {
    private typealias Fixture = SyncFixture

    @Test("A successful refresh files the snapshot, the timeline point, and a plan")
    func successfulRefreshFilesEverything() async throws {
        let now = Fixture.periodStart
        let reading = try Fixture.snapshot(updatedAt: now)
        let provider = ScriptedProvider(always: .success(reading))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)

        let outcome = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        #expect(outcome.result.succeeded)
        #expect(!outcome.periodChanged)
        let record = try #require(
            await harness.snapshots.snapshot(
                quotaID: harness.quota.id,
                bucketID: "primary",
                accountLabel: "work@example.com"
            )
        )
        #expect(record.snapshot.bucket(id: "primary")?.usagePercentage == 40)
        let timeline = try #require(
            await harness.timelines.timeline(
                quotaID: harness.quota.id,
                bucketID: "primary",
                accountLabel: "work@example.com"
            )
        )
        #expect(timeline.timeline.points.count == 1)
        // The plan is recomputed with no user action.
        let plan = try #require(await harness.plans.plan(quotaID: harness.quota.id))
        #expect(plan.totalRemaining == 60)
        #expect(!plan.allocations.isEmpty)
    }

    @Test("A refresh records the provider as having answered, and is timestamped")
    func successIsRecordedAgainstTheProvider() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider(always: .success(try Fixture.snapshot(updatedAt: now)))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)

        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        let record = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(record.lastSyncAt == now)
        #expect(record.lastFailure == nil)
        #expect(record.consecutiveFailures == 0)
    }

    @Test("Intraday readings accumulate in the timeline")
    func timelineAccumulates() async throws {
        let start = Fixture.periodStart
        // A reading from the day before, so the day's consumption has a
        // baseline; then two during the day.
        let yesterday = start.addingTimeInterval(-86400)
        let baseline = try Fixture.snapshot(usage: 10, updatedAt: yesterday)
        let morning = try Fixture.snapshot(usage: 20, updatedAt: start.addingTimeInterval(3600))
        let evening = try Fixture.snapshot(usage: 25, updatedAt: start.addingTimeInterval(7200))
        let provider = ScriptedProvider([.success(baseline), .success(morning), .success(evening)])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: yesterday, periodStart: start)

        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        _ = try await harness.coordinator(readingAt: start.addingTimeInterval(3600))
            .refresh(quotaID: harness.quota.id)
        _ = try await harness.coordinator(readingAt: start.addingTimeInterval(7200))
            .refresh(quotaID: harness.quota.id)

        let timeline = try #require(
            await harness.timelines.timeline(
                quotaID: harness.quota.id,
                bucketID: "primary",
                accountLabel: "work@example.com"
            )
        )
        #expect(timeline.timeline.points.count == 3)
        // Consumption between the two readings is measurable, which is the whole
        // point of keeping a timeline rather than only the latest figure.
        #expect(
            timeline.timeline.usedOn(
                bucketID: "primary",
                from: start,
                to: start.addingTimeInterval(7200),
                calendar: Fixture.calendar
            ) == 15
        )
    }

    @Test("A failed refresh keeps the last good reading and reports the failure")
    func failureKeepsLastGoodSnapshot() async throws {
        let now = Fixture.periodStart
        let good = try Fixture.snapshot(usage: 30, updatedAt: now)
        let provider = ScriptedProvider([
            .success(good),
            .failure(Fixture.failure(.networkUnavailable, at: now.addingTimeInterval(60))),
        ])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        let later = now.addingTimeInterval(60)
        let outcome = try await harness.coordinator(readingAt: later).refresh(quotaID: harness.quota.id)

        #expect(!outcome.result.succeeded)
        #expect(outcome.result.failure?.code == .networkUnavailable)
        let record = try #require(
            await harness.snapshots.snapshot(
                quotaID: harness.quota.id,
                bucketID: "primary",
                accountLabel: "work@example.com"
            )
        )
        #expect(record.snapshot.bucket(id: "primary")?.usagePercentage == 30)
        let stored = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(stored.lastFailure?.code == .networkUnavailable)
        // The earlier success is still the last success: a failure does not move
        // it, because the reading on screen came from then.
        #expect(stored.lastSyncAt == now)
    }

    @Test("A reading is still served while it is stale")
    func staleReadingIsStillServed() async throws {
        let now = Fixture.periodStart
        let good = try Fixture.snapshot(updatedAt: now)
        let provider = ScriptedProvider(always: .success(good))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        // Well past the stale threshold, still inside the period.
        let later = now.addingTimeInterval(StalenessConstants.unavailableAfter / 2)
        let outcome = try await harness.coordinator(readingAt: later).reading(for: harness.quota.id)

        let reading = try #require(outcome.reading)
        #expect(reading.freshness == .stale)
    }

    @Test("A refresh after failures recovers and clears the recorded error")
    func recoveryAfterFailure() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider([
            .failure(Fixture.failure(.networkUnavailable, at: now)),
            .success(try Fixture.snapshot(updatedAt: now.addingTimeInterval(600))),
        ])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)

        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let after = now.addingTimeInterval(600)
        let outcome = try await harness.coordinator(readingAt: after).refresh(quotaID: harness.quota.id)

        #expect(outcome.result.succeeded)
        let stored = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(stored.lastFailure == nil)
        #expect(stored.consecutiveFailures == 0)
        #expect(stored.lastSyncAt == after)
    }
}
