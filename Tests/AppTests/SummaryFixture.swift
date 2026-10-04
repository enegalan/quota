import Core
import Foundation
import Platform
import Testing
@testable import App

/// The store a summary test reads from.
///
/// Kept out of the suite so the tests read as claims and the arranging lives
/// here, and so a test can change one thing about the world without the rest of
/// the suite shifting underneath it.
struct SummaryFixture {
    /// 15 March 2026, midday.
    ///
    /// Midday rather than midnight, because the day's usage window runs from the
    /// start of the day to the reference instant: a reference at midnight would
    /// make the window empty and every day's reading unknowable, which would be a
    /// property of the test's clock rather than of the app.
    static var reference: Date {
        let calendar = calendar
        guard let midnight = try? LocalDate(year: 2026, month: 3, day: 15).date(calendar: calendar),
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: midnight)
        else {
            return Date(timeIntervalSince1970: 0)
        }
        return noon
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static let timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
    static let account = "user@example.com"

    /// The bucket the fixture's provider reports.
    ///
    /// Named by the provider, not by the app, so a test that looks a quota up by
    /// a name the app invented would fail.
    static let bucketID = "usage"

    /// A stable identifier, so a failure names the same quota every run.
    static let quotaID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")
        ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xC1))

    /// How close two figures must be to count as the same, for values the engine
    /// computes by dividing a total across the days ahead.
    static let tolerance: Double = 0.0001

    /// Matches the production retention, so a test timeline is trimmed the same
    /// way a real one is.
    static let timelineRetention = 1000

    /// What the world should contain.
    ///
    /// One struct rather than a list of arguments, so adding a case to a test
    /// reads as adding a line here and cannot silently reorder two booleans.
    struct World {
        /// Whether the quota names a bucket of its own.
        var namedBucket = true
        /// Whether the provider has an authenticated account on file.
        var connected = true
        /// Whether a reading has been stored.
        var withReading = true
        /// Whether any history has been stored.
        var withTimeline = true
        /// Whether a plan has been computed and stored.
        var withPlan = true
        /// How much of today's allowance has been spent, if history exists.
        var usedToday: Double = 0
        /// Whether the provider has stopped reporting the quota's own bucket.
        ///
        /// The state a provider reaches by renaming or merging a limit: the record
        /// is written again, because the refresh succeeded, but the limit is not
        /// in it any more.
        var bucketGone = false
        /// Whether the period's days have all gone by.
        var periodEndingYesterday = false
        /// Whether weekends are left unfunded.
        var weekdaysOnly = false
    }

    let quota: Quota
    let plan: AllocationPlan?
    let presenter: SummaryPresenter

    /// A factory rather than an initialiser, because seeding the store is
    /// asynchronous and an initialiser cannot await.
    static func make(_ world: World = World()) async throws -> SummaryFixture {
        let store = CodableStore.inMemory()
        let providerID = try ProviderID("mock")
        let period = try makePeriod(endingYesterday: world.periodEndingYesterday)
        let quota = try makeQuota(
            providerID: providerID,
            period: period,
            namedBucket: world.namedBucket
        )
        let plan = try makePlan(quotaID: quota.id, period: period, world: world)
        try await seed(store: store, quota: quota, plan: plan, providerID: providerID, world: world)
        return SummaryFixture(quota: quota, plan: plan, presenter: presenter(for: store))
    }

    /// A second quota on the same provider, for the cases that need one.
    static let siblingQuotaID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")
        ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xC2, 0))

    /// The share the stored plan gives today, taken from the plan itself.
    ///
    /// Not written out as a number: the engine plans the days still ahead of the
    /// reference, so the share is a property of the plan rather than of the
    /// month's length, and a hard-coded figure would need correcting whenever
    /// that changes.
    static func todayShare(of plan: AllocationPlan?) throws -> Double {
        let today = LocalDate(date: reference, calendar: calendar)
        return try #require(plan?.allocation(on: today)?.percentage)
    }

    private static func presenter(for store: CodableStore) -> SummaryPresenter {
        SummaryPresenter(
            quotas: QuotaRepository(store: store),
            snapshots: SnapshotRepository(store: store),
            timelines: TimelineRepository(store: store),
            providers: ProviderRepository(store: store),
            plans: AllocationPlanRepository(store: store),
            calendar: calendar,
            reference: reference
        )
    }

    /// March 2026, ending on the 14th when the test wants a period whose days
    /// have all gone by.
    private static func makePeriod(endingYesterday: Bool) throws -> QuotaPeriod {
        let start = try #require(
            try LocalDate(year: 2026, month: 3, day: 1).date(calendar: calendar)
        )
        let end = try #require(
            try LocalDate(year: 2026, month: 3, day: endingYesterday ? 14 : 31)
                .date(calendar: calendar)
        )
        return try QuotaPeriod(start: start, end: end)
    }

    private static func makeQuota(
        providerID: ProviderID,
        period: QuotaPeriod,
        namedBucket: Bool
    ) throws -> Quota {
        try Quota(
            id: quotaID,
            name: "Mock",
            providerID: providerID,
            bucketID: namedBucket ? bucketID : nil,
            period: period,
            policy: .even,
            createdAt: reference,
            updatedAt: reference
        )
    }

    /// Even by default, so every day ahead carries a share and the plain cases
    /// can assert against it. The weekdays-only variant leaves weekends unfunded,
    /// which is the pattern describe and the only way to reach a day
    /// with nothing allocated.
    private static func makePlan(
        quotaID: UUID,
        period: QuotaPeriod,
        world: World
    ) throws -> AllocationPlan? {
        guard world.withPlan else { return nil }
        let policy: AllocationPolicy = world.weekdaysOnly
            ? .weekly(weekdayWeights: .weekdaysOnly)
            : .even
        return try AllocationEngine(calendar: calendar).plan(
            quotaID: quotaID,
            policy: policy,
            period: period,
            totalRemaining: 100,
            asOf: reference
        )
    }

    private static func seed(
        store: CodableStore,
        quota: Quota,
        plan: AllocationPlan?,
        providerID: ProviderID,
        world: World
    ) async throws {
        let repositories = Repositories(store: store)
        try await repositories.quotas.save(quota)
        if let plan {
            try await repositories.plans.save(plan, accountLabel: account)
        }
        if world.connected {
            try await repositories.providers.save(connectedProvider(providerID: providerID))
        }
        if world.withReading {
            if world.bucketGone {
                // The state a provider reaches by dropping a limit: the quota's
                // own record is written again without it, and a sibling quota on
                // the same provider still holds a reading from before, which is
                // where the limit's name survives to be shown.
                try await seedVanishedLimit(
                    repositories: repositories, quota: quota, providerID: providerID
                )
            } else {
                try await repositories.snapshots.save(try reading(for: quota))
            }
        }
        guard world.withTimeline else { return }
        try await repositories.timelines.append(
            try history(for: quota, usedToday: world.usedToday),
            keepingAtMost: timelineRetention
        )
    }

    private static func connectedProvider(providerID: ProviderID) -> ProviderRecord {
        // Under the same id the quota was built with: a record under a different
        // one would leave the quota unaccounted and the summary blank, which
        // would read as missing data rather than as a broken fixture.
        ProviderRecord(
            providerID: providerID,
            displayName: "Mock",
            installedVersion: "1.0.0",
            authenticatedAccountLabel: account
        )
    }

    private static func reading(for quota: Quota) throws -> SnapshotRecord {
        let bucket = try UsageBucket(
            id: bucketID,
            displayName: "Usage",
            usagePercentage: 40,
            period: quota.period
        )
        return SnapshotRecord(
            quotaID: quota.id,
            bucketID: bucket.id,
            accountLabel: account,
            snapshot: try UsageSnapshot(
                updatedAt: reference,
                buckets: [bucket]
            )
        )
    }

    /// Two points, not one: a day's spending is the rise from where the day
    /// started, so a single reading cannot establish it. The baseline sits at the
    /// start of the day and the reading at noon, both inside the window the
    /// presenter asks about.
    private static func history(for quota: Quota, usedToday: Double) throws -> TimelineRecord {
        var points: [TimelinePoint] = []
        if usedToday > 0 {
            let midnight = calendar.startOfDay(for: reference)
            let noon = try #require(
                calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reference)
            )
            points.append(
                try TimelinePoint(recordedAt: midnight, bucketID: bucketID, usagePercentage: 0)
            )
            points.append(
                try TimelinePoint(recordedAt: noon, bucketID: bucketID, usagePercentage: usedToday)
            )
        }
        return TimelineRecord(
            quotaID: quota.id,
            bucketID: bucketID,
            accountLabel: account,
            timeline: UsageTimeline(points: points)
        )
    }

    /// The five repositories, so a test's arranging reads as one line each.
    struct Repositories {
        let quotas: QuotaRepository
        let snapshots: SnapshotRepository
        let timelines: TimelineRepository
        let providers: ProviderRepository
        let plans: AllocationPlanRepository

        init(store: any QuotaStore) {
            quotas = QuotaRepository(store: store)
            snapshots = SnapshotRepository(store: store)
            timelines = TimelineRepository(store: store)
            providers = ProviderRepository(store: store)
            plans = AllocationPlanRepository(store: store)
        }
    }
}
