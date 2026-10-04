import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Two limits on one provider, metered over windows of different lengths.
///
/// The arrangement is the one the model was changed for: a five-hour pool and a
/// weekly pool, read from the same account in the same reading. Every test here
/// is about what must stay apart, because what must stay apart is exactly what
/// was shared before — one period for the whole reading, which made each refresh
/// look like a period change to the other quota, which deleted its timeline.
private enum MultiWindowFixture {
    typealias Repositories = SyncFixture.Repositories

    /// The pool that resets every few hours, and the one that resets weekly.
    static let short = "five_hour"
    static let long = "week"
    static let accountLabel = "work@example.com"

    static var weekStart: Date {
        SyncFixture.periodStart.addingTimeInterval(-86400 * 3)
    }

    /// The two quotas these tests read through, and the storage they read from.
    struct Arrangement {
        let fiveHours: Quota
        let week: Quota
        let repositories: Repositories
    }

    /// A reading with both pools, each over its own window.
    static func reading(
        at instant: Date,
        shortUsage: Double = 20,
        longUsage: Double = 35,
        shortStart: Date = SyncFixture.periodStart,
        longStart: Date? = nil
    ) throws -> UsageSnapshot {
        let week = longStart ?? weekStart
        return try UsageSnapshot(
            updatedAt: instant,
            buckets: [
                try UsageBucket(
                    id: short,
                    displayName: "Five hours",
                    usagePercentage: shortUsage,
                    period: try SyncFixture.period(shortStart, days: 1)
                ),
                try UsageBucket(
                    id: long,
                    displayName: "Weekly",
                    usagePercentage: longUsage,
                    period: try SyncFixture.period(week, days: 7)
                ),
            ]
        )
    }

    /// The same reading with one pool taken out of it, for a provider that has
    /// stopped metering it.
    static func reading(_ original: UsageSnapshot, keeping bucketID: String) throws -> UsageSnapshot {
        try UsageSnapshot(
            updatedAt: original.updatedAt,
            buckets: original.buckets.filter { $0.id == bucketID }
        )
    }

    /// One quota per pool on one connected provider, both created against a
    /// window that is neither of theirs — a month for both, where the provider
    /// reports a day and a week. A coordinator that stamped the reading's first
    /// window onto both, or either pool's window onto the other, changes one of
    /// them on the first read.
    static func arrange() async throws -> Arrangement {
        let store = CodableStore.inMemory()
        let repositories = Repositories(store: store)
        let providerID = try ProviderID("mock")
        let month = try SyncFixture.period(SyncFixture.periodStart, days: 30)
        let quotas = [
            try Quota(
                name: "Five hours", providerID: providerID, bucketID: short,
                period: month, policy: .even,
                createdAt: SyncFixture.periodStart, updatedAt: SyncFixture.periodStart
            ),
            try Quota(
                name: "Weekly", providerID: providerID, bucketID: long,
                period: month, policy: .even,
                createdAt: SyncFixture.periodStart, updatedAt: SyncFixture.periodStart
            ),
        ]
        try await store.saveQuotas(quotas.map(QuotaRecord.init(quota:)))
        try await store.saveProviders([
            ProviderRecord(
                providerID: providerID,
                displayName: "Mock",
                installedVersion: "1.0.0",
                authenticatedAccountLabel: accountLabel
            ),
        ])
        return Arrangement(fiveHours: quotas[0], week: quotas[1], repositories: repositories)
    }

    /// A coordinator over an arrangement, reading at a given instant.
    static func coordinator(
        _ arrangement: Arrangement,
        provider: any UsageFetching,
        at instant: Date
    ) -> SyncCoordinator {
        SyncFixture.makeCoordinator(
            repositories: arrangement.repositories,
            fetcher: provider,
            now: { instant }
        )
    }

    /// The points recorded against one quota's own pool.
    static func points(
        for quota: Quota,
        in arrangement: Arrangement
    ) async throws -> [TimelinePoint] {
        try #require(
            await arrangement.repositories.timelines.timeline(
                quotaID: quota.id,
                bucketID: quota.bucketID ?? "",
                accountLabel: accountLabel
            )
        ).timeline.points
    }
}

@Suite("Several windows on one provider")
struct MultiWindowQuotaTests {
    private typealias Fixture = MultiWindowFixture

    @Test("Each quota is corrected to its own pool's window, not to the reading's first")
    func eachQuotaTakesItsOwnWindow() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let reading = try Fixture.reading(at: now)
        let coordinator = Fixture.coordinator(
            arrangement,
            provider: ScriptedProvider(always: .success(reading)),
            at: now
        )

        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        _ = try await coordinator.refresh(quotaID: arrangement.week.id)

        let storedShort = try #require(
            await arrangement.repositories.quotas.quota(id: arrangement.fiveHours.id)
        )
        let storedLong = try #require(
            await arrangement.repositories.quotas.quota(id: arrangement.week.id)
        )
        #expect(storedShort.period == reading.period(forBucket: Fixture.short))
        #expect(storedLong.period == reading.period(forBucket: Fixture.long))
        #expect(storedShort.period != storedLong.period)
    }

    @Test("A second poll of both pools is not a period change, and keeps both timelines")
    func repeatedPollsKeepBothTimelines() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let provider = ScriptedProvider([
            .success(try Fixture.reading(at: now)),
            .success(try Fixture.reading(at: now)),
            .success(try Fixture.reading(at: now, shortUsage: 30, longUsage: 44)),
            .success(try Fixture.reading(at: now, shortUsage: 30, longUsage: 44)),
        ])
        let coordinator = Fixture.coordinator(arrangement, provider: provider, at: now)

        let first = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        _ = try await coordinator.refresh(quotaID: arrangement.week.id)
        let third = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        let fourth = try await coordinator.refresh(quotaID: arrangement.week.id)

        #expect(first.periodChanged)
        // The correction happened once. After that the provider is reporting the
        // same two windows it reported before, so neither quota has a new period
        // and neither loses the points it has already spent.
        #expect(!third.periodChanged)
        #expect(!fourth.periodChanged)
        let shortPoints = try await Fixture.points(for: arrangement.fiveHours, in: arrangement)
        let longPoints = try await Fixture.points(for: arrangement.week, in: arrangement)
        #expect(shortPoints.count == 2)
        #expect(longPoints.count == 2)
        // And each timeline holds its own pool's figure, not the other's.
        #expect(shortPoints.last?.usagePercentage == 30)
        #expect(longPoints.last?.usagePercentage == 44)
    }

    @Test("A plan is built over the window of the pool it watches")
    func planUsesTheBucketsWindow() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let reading = try Fixture.reading(at: now)
        let coordinator = Fixture.coordinator(
            arrangement,
            provider: ScriptedProvider(always: .success(reading)),
            at: now
        )

        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        _ = try await coordinator.refresh(quotaID: arrangement.week.id)

        let plans = arrangement.repositories.plans
        let shortPlan = try #require(await plans.plan(quotaID: arrangement.fiveHours.id))
        let longPlan = try #require(await plans.plan(quotaID: arrangement.week.id))
        #expect(shortPlan.period == reading.period(forBucket: Fixture.short))
        #expect(longPlan.period == reading.period(forBucket: Fixture.long))
        // Remaining is each pool's own complement.
        #expect(shortPlan.totalRemaining == 80)
        #expect(longPlan.totalRemaining == 65)
    }
}

@Suite("A pool the provider stops reporting")
struct MissingPoolTests {
    private typealias Fixture = MultiWindowFixture

    /// The window the weekly quota is created against, which is what it keeps
    /// while the pool it watches is missing.
    private func weeklyWindow() throws -> QuotaPeriod {
        try SyncFixture.period(Fixture.weekStart, days: 7)
    }

    @Test("A pool that is missing keeps its window and adds nothing to its timeline")
    func missingPoolKeepsItsWindow() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let before = try Fixture.reading(at: now)
        // An hour later the weekly pool is gone from the answer and the five-hour
        // one has moved on.
        let after = try Fixture.reading(before, keeping: Fixture.short)
        let provider = ScriptedProvider([.success(before), .success(before), .success(after)])
        let coordinator = Fixture.coordinator(arrangement, provider: provider, at: now)
        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        _ = try await coordinator.refresh(quotaID: arrangement.week.id)

        let outcome = try await Fixture.coordinator(arrangement, provider: provider, at: now + 3600)
            .refresh(quotaID: arrangement.week.id)

        #expect(outcome.result.succeeded)
        #expect(!outcome.periodChanged)
        let stored = try #require(
            await arrangement.repositories.quotas.quota(id: arrangement.week.id)
        )
        // The weekly window it was created with, not the five-hour one it can
        // still see: another pool's window is not this quota's to adopt.
        let weekly = try weeklyWindow()
        #expect(stored.period == weekly)
        // The point it had is still there, and none was invented for a pool the
        // provider stopped reporting — a fabricated point would read as zero
        // spent, which is the opposite of what is known.
        #expect(try await Fixture.points(for: arrangement.week, in: arrangement).count == 1)
    }

    @Test("A quota whose pool is missing is reported as waiting for that pool")
    func missingPoolIsReported() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let before = try Fixture.reading(at: now)
        let after = try Fixture.reading(before, keeping: Fixture.short)
        let provider = ScriptedProvider([.success(before), .success(after)])
        let coordinator = Fixture.coordinator(arrangement, provider: provider, at: now)
        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)

        _ = try await coordinator.refresh(quotaID: arrangement.week.id)
        let shown = try await coordinator.reading(for: arrangement.week.id)

        #expect(shown.reason == .bucketUnavailable(Fixture.long))
    }

    @Test("The other pool is untouched by its neighbour's disappearance")
    func otherPoolKeepsReading() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let before = try Fixture.reading(at: now)
        let after = try Fixture.reading(before, keeping: Fixture.short)
        let provider = ScriptedProvider([.success(before), .success(after), .success(after)])
        let coordinator = Fixture.coordinator(arrangement, provider: provider, at: now + 3600)
        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)

        _ = try await coordinator.refresh(quotaID: arrangement.week.id)
        _ = try await coordinator.refresh(quotaID: arrangement.fiveHours.id)
        let shown = try await coordinator.reading(for: arrangement.fiveHours.id)

        #expect(shown.reading?.snapshot.bucket(id: Fixture.short) != nil)
        #expect(shown.reading?.snapshot.bucket(id: Fixture.long) == nil)
        #expect(try await Fixture.points(for: arrangement.fiveHours, in: arrangement).count == 2)
    }

    @Test("A pool that comes back is picked up again, with the window it now reports")
    func returningPoolIsAdopted() async throws {
        let now = SyncFixture.periodStart
        let arrangement = try await Fixture.arrange()
        let both = try Fixture.reading(at: now)
        let provider = ScriptedProvider([.success(try Fixture.reading(both, keeping: Fixture.short))])
        let coordinator = Fixture.coordinator(arrangement, provider: provider, at: now)
        _ = try await coordinator.refresh(quotaID: arrangement.week.id)
        #expect(try await coordinator.reading(for: arrangement.week.id).reason == .bucketUnavailable(Fixture.long))

        let nextWeek = SyncFixture.periodStart.addingTimeInterval(7 * 86400)
        let returned = try Fixture.reading(
            at: nextWeek, shortUsage: 5, longUsage: 8, shortStart: nextWeek, longStart: nextWeek
        )
        let later = ScriptedProvider([.success(returned)])
        let outcome = try await Fixture.coordinator(arrangement, provider: later, at: nextWeek)
            .refresh(quotaID: arrangement.week.id)

        #expect(outcome.periodChanged)
        let stored = try #require(
            await arrangement.repositories.quotas.quota(id: arrangement.week.id)
        )
        let newWeek = try SyncFixture.period(nextWeek, days: 7)
        #expect(stored.period == newWeek)
        // A new window drops the old cycle's point rather than totalling across
        // two weeks.
        let points = try await Fixture.points(for: arrangement.week, in: arrangement)
        #expect(points.count == 1)
        #expect(points.first?.recordedAt == nextWeek)
    }
}
