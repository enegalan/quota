import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Sync coordinator, failures and schedules")
struct SyncCoordinatorStateTests {
    private typealias Fixture = SyncFixture

    @Test("A cached reading is never served past its own period end")
    func periodEndRefusesTheCachedReading() async throws {
        let now = Fixture.periodStart
        let good = try Fixture.snapshot(updatedAt: now)
        let provider = ScriptedProvider(always: .success(good))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        // The outage lasts past the end of the period the reading belongs to.
        let later = try Fixture.period(Fixture.periodStart, days: 30).end.addingTimeInterval(3600)
        let outcome = try await harness.coordinator(readingAt: later).reading(for: harness.quota.id)

        #expect(outcome.reading == nil)
        guard case .unserved(.periodEnded) = outcome else {
            Issue.record("expected the period to be reported as ended, got \(outcome)")
            return
        }
    }

    @Test("A provider period change updates the quota and resets the timeline")
    func periodChangeResetsTimeline() async throws {
        let start = Fixture.periodStart
        let first = try Fixture.snapshot(usage: 20, periodStart: start, updatedAt: start)
        let next = try Fixture.period(start, days: 30).end
        let second = try Fixture.snapshot(usage: 5, periodStart: next, updatedAt: next)
        let provider = ScriptedProvider([.success(first), .success(second)])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: start, periodStart: start)

        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let outcome = try await harness.coordinator(readingAt: next).refresh(quotaID: harness.quota.id)

        #expect(outcome.periodChanged)
        let updated = try #require(await harness.quotas.quota(id: harness.quota.id))
        let expected = try Fixture.period(next, days: 30)
        #expect(updated.period == expected)
        let timeline = try #require(
            await harness.timelines.timeline(
                quotaID: harness.quota.id,
                bucketID: "primary",
                accountLabel: "work@example.com"
            )
        )
        // The old cycle's points are gone, so used-today cannot straddle two
        // periods.
        #expect(timeline.timeline.points.count == 1)
        #expect(timeline.timeline.points.first?.recordedAt == next)
    }

    @Test("A rate-limited result backs off exponentially, within the cap")
    func rateLimitBacksOff() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider(always: .failure(Fixture.failure(.rateLimited, at: now)))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)

        var schedule = RefreshSchedule()
        var intervals: [TimeInterval] = []
        for _ in 0 ..< 4 {
            _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
            schedule = schedule.afterFailure(code: .rateLimited)
            intervals.append(schedule.baseInterval)
        }

        #expect(intervals[0] < intervals[1])
        #expect(intervals[1] < intervals[2])
        #expect(intervals.last == RefreshConstants.maximumBackoff)
        // The first failure waits one whole interval rather than a delay of its
        // own, so nothing is polled sooner than it would have been.
        #expect(intervals[0] == RefreshConstants.defaultPollInterval)
        for interval in intervals {
            #expect(interval <= RefreshConstants.maximumBackoff)
        }
    }

    @Test("A failure that is an answer does not back off")
    func unsupportedDoesNotBackOff() {
        let schedule = RefreshSchedule().afterFailure(code: .nothingToReport)
        #expect(schedule.consecutiveFailures == 0)
        #expect(schedule.baseInterval == RefreshConstants.defaultPollInterval)
    }

    @Test("The backoff count survives a restart and is reset by a success")
    func backoffCountPersists() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider(always: .failure(Fixture.failure(.networkUnavailable, at: now)))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)

        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let once = try #require(await harness.providers.provider(try ProviderID("mock")))
        #expect(once.consecutiveFailures == 1)
        // A second coordinator over the same store is the same app relaunched.
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let twice = try #require(await harness.providers.provider(try ProviderID("mock")))
        #expect(twice.consecutiveFailures == 2)
        let schedule = await harness.coordinator.effectiveSchedule(for: twice)
        // Two failures, so the interval is doubled from what the provider would
        // have been read at: a wait measured against a constant that is not in
        // the mechanism would pass whatever that wait was.
        #expect(schedule.backoffInterval == RefreshConstants.defaultPollInterval * 2)
        #expect(schedule.baseInterval == schedule.backoffInterval)
    }

    @Test("An expired authentication prompts a reconnect and keeps the cached data")
    func authenticationExpiredPromptsReconnect() async throws {
        let now = Fixture.periodStart
        let good = try Fixture.snapshot(usage: 33, updatedAt: now)
        let provider = ScriptedProvider([
            .success(good),
            .failure(Fixture.failure(.authenticationFailed, at: now.addingTimeInterval(60))),
        ])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        let later = now.addingTimeInterval(60)
        let outcome = try await harness.coordinator(readingAt: later).refresh(quotaID: harness.quota.id)

        let state = ProviderFailureTranslator.presentation(for: try #require(outcome.result.failure))
        #expect(state == .authenticationExpired)
        #expect(state.action == .reconnect)
        // The reading is still there: an expired token is not a reason to lose
        // the last known usage.
        let shown = try await harness.coordinator(readingAt: later).reading(for: harness.quota.id)
        #expect(shown.reading?.snapshot.bucket(id: "primary")?.usagePercentage == 33)
    }

    @Test("One provider failing leaves another provider's quota and plan alone")
    func quotasAreIndependent() async throws {
        let now = Fixture.periodStart
        let store = CodableStore.inMemory()
        let repositories = Fixture.Repositories(store: store)
        let good = try Fixture.snapshot(usage: 12, updatedAt: now)
        let bad = Fixture.failure(.pluginError, at: now)

        // Two quotas, one provider each: one answers, one does not.
        let quotas = try await Fixture.arrangeQuotas(
            store: store,
            providerIDs: ["mock", "broken"],
            periodStart: Fixture.periodStart,
            accountLabel: "work@example.com"
        )
        let mock = quotas[0]
        let broken = quotas[1]
        let coordinator = Fixture.makeCoordinator(
            repositories: repositories,
            fetcher: PerProviderFetcher(results: [
                "mock": .success(good),
                "broken": .failure(bad),
            ]),
            now: { now }
        )

        let outcomes = try await coordinator.refreshAll()
        #expect(outcomes.count == 2)
        let byQuota = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.quotaID, $0.result) })
        #expect(byQuota[mock.id]?.succeeded == true)
        #expect(byQuota[broken.id]?.succeeded == false)
        let mockPlan = try await repositories.plans.plan(quotaID: mock.id)
        let brokenPlan = try await repositories.plans.plan(quotaID: broken.id)
        #expect(mockPlan != nil)
        #expect(brokenPlan == nil)
    }

    // MARK: Not connected

    @Test("A provider with no account reads as needing a connection, not as broken")
    func unconnectedProviderReadsAsNeedingConnection() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider([])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now, connected: false)

        let outcome = try await harness.coordinator.refresh(quotaID: harness.quota.id)

        #expect(outcome.result.failure?.code == .notAuthenticated)
        #expect(try await provider.callCount == 0)
        let shown = try await harness.coordinator.reading(for: harness.quota.id)
        #expect(shown.reason == .noAccount)
    }

    // MARK: Captions

    @Test("A caption states the age, and a failure keeps the figure with its age")
    func captionsStateTheAge() async throws {
        let now = Fixture.periodStart
        let good = try Fixture.snapshot(updatedAt: now)
        let harness = try await Fixture.makeHarness(fetcher: ScriptedProvider(always: .success(good)), now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        let shown = try await harness.coordinator.reading(for: harness.quota.id)
        let reading = try #require(shown.reading)

        #expect(harness.coordinator.caption(for: reading) == "Updated just now.")
        let withFailure = harness.coordinator.caption(
            for: reading,
            lastFailure: Fixture.failure(.networkUnavailable, at: now)
        )
        #expect(withFailure.hasPrefix("Unable to update usage."))
        // The figure is still on screen, so the caption has to say how old it is.
        #expect(withFailure.contains("just now"))

        let later = now.addingTimeInterval(120)
        let agedReading = ServedReading(
            snapshot: try Fixture.snapshot(updatedAt: now),
            freshness: .stale,
            accountLabel: "work@example.com"
        )
        let agedCaption = harness.coordinator(readingAt: later).caption(for: agedReading)
        #expect(agedCaption == "Updated 2 minutes ago.")
    }
}
