import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// The scripted provider and the storage a coordinator test runs against.
///
/// In its own file, and in a type rather than in each suite, because two
/// suites need the same arrangement and a helper copied into both is a
/// helper that will be updated in one of them.
enum SyncFixture {
    static let periodStart = Date(timeIntervalSince1970: 1_757_000_000)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func period(_ start: Date, days: Int) throws -> QuotaPeriod {
        try QuotaPeriod(
            start: start,
            end: Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: start) ?? start
        )
    }

    static func snapshot(
        usage: Double = 40,
        periodStart: Date? = nil,
        updatedAt: Date,
        bucketID: String = "primary"
    ) throws -> UsageSnapshot {
        let start = periodStart ?? SyncFixture.periodStart
        return try UsageSnapshot(
            updatedAt: updatedAt,
            buckets: [
                try UsageBucket(
                    id: bucketID,
                    displayName: "Primary",
                    usagePercentage: usage,
                    period: try period(start, days: 30)
                ),
            ]
        )
    }

    struct Harness {
        let store: CodableStore
        let quotas: QuotaRepository
        let snapshots: SnapshotRepository
        let timelines: TimelineRepository
        let providers: ProviderRepository
        let plans: AllocationPlanRepository
        let preferences: PreferencesRepository
        let coordinator: SyncCoordinator
        let quota: Quota
        let fetcher: any UsageFetching
        let calendar: Calendar

        /// The same coordinator, reading at a different instant.
        ///
        /// Every dependency is shared, so what changes between two refreshes is
        /// only the clock — which is the point: a test about ageing or a period
        /// boundary must be able to move time without moving anything else, or
        /// it is not testing what it claims to.
        func coordinator(readingAt instant: Date) -> SyncCoordinator {
            SyncCoordinator(
                quotas: quotas,
                snapshots: snapshots,
                timelines: timelines,
                providers: providers,
                plans: plans,
                engine: AllocationEngine(calendar: calendar),
                fetcher: fetcher,
                calendar: calendar,
                now: { instant },
                preferences: preferences
            )
        }
    }

    /// A coordinator over in-memory storage with one connected provider.
    static func makeHarness(
        fetcher: any UsageFetching,
        now: Date,
        periodStart: Date? = nil,
        connected: Bool = true,
        providerID: String = "mock"
    ) async throws -> Harness {
        let store = CodableStore.inMemory()
        let repositories = Repositories(store: store)
        let quota = try await arrangeOneQuota(
            store: store,
            providerID: providerID,
            periodStart: periodStart,
            connected: connected
        )
        let coordinator = SyncCoordinator(
            quotas: repositories.quotas,
            snapshots: repositories.snapshots,
            timelines: repositories.timelines,
            providers: repositories.providers,
            plans: repositories.plans,
            engine: AllocationEngine(calendar: calendar),
            fetcher: fetcher,
            calendar: calendar,
            now: { now },
            preferences: repositories.preferences
        )
        return Harness(
            store: store,
            quotas: repositories.quotas,
            snapshots: repositories.snapshots,
            timelines: repositories.timelines,
            providers: repositories.providers,
            plans: repositories.plans,
            preferences: repositories.preferences,
            coordinator: coordinator,
            quota: quota,
            fetcher: fetcher,
            calendar: calendar
        )
    }

    /// The repositories every harness needs, in one place.
    ///
    /// A type rather than five constructor arguments, so a suite that builds its
    /// own arrangement passes one value around and cannot get two of the five
    /// the wrong way round.
    struct Repositories: Sendable {
        let quotas: QuotaRepository
        let snapshots: SnapshotRepository
        let timelines: TimelineRepository
        let providers: ProviderRepository
        let plans: AllocationPlanRepository
        let preferences: PreferencesRepository

        init(store: any QuotaStore) {
            quotas = QuotaRepository(store: store)
            snapshots = SnapshotRepository(store: store)
            timelines = TimelineRepository(store: store)
            providers = ProviderRepository(store: store)
            plans = AllocationPlanRepository(store: store)
            preferences = PreferencesRepository(store: store)
        }
    }

    /// A store holding one quota on one provider, ready to refresh.
    static func arrangeOneQuota(
        store: any QuotaStore,
        providerID: String,
        periodStart: Date?,
        connected: Bool
    ) async throws -> Quota {
        let identifier = try ProviderID(providerID)
        let start = periodStart ?? SyncFixture.periodStart
        let quota = try Quota(
            name: "Mock",
            providerID: identifier,
            period: try period(start, days: 30),
            policy: .even,
            createdAt: start,
            updatedAt: start
        )
        try await store.saveQuotas([QuotaRecord(quota: quota)])
        try await store.saveProviders([
            ProviderRecord(
                providerID: identifier,
                displayName: "Mock",
                installedVersion: "1.0.0",
                authenticatedAccountLabel: connected ? "work@example.com" : nil
            ),
        ])
        return quota
    }

    /// One quota per provider, each connected, over one store.
    ///
    /// For the tests that need several providers side by side; a suite about one
    /// provider's failures should use `makeHarness`, which is a smaller thing to
    /// reason about.
    static func arrangeQuotas(
        store: any QuotaStore,
        providerIDs: [String],
        periodStart: Date,
        accountLabel: String
    ) async throws -> [Quota] {
        let period = try period(periodStart, days: 30)
        let quotas = try providerIDs.map { identifier in
            try Quota(
                name: identifier,
                providerID: try ProviderID(identifier),
                period: period,
                policy: .even,
                createdAt: periodStart,
                updatedAt: periodStart
            )
        }
        try await store.saveQuotas(quotas.map(QuotaRecord.init(quota:)))
        try await store.saveProviders(try providerIDs.map { identifier in
            ProviderRecord(
                providerID: try ProviderID(identifier),
                displayName: identifier,
                installedVersion: "1",
                authenticatedAccountLabel: accountLabel
            )
        })
        return quotas
    }

    /// A coordinator over repositories that are already arranged.
    static func makeCoordinator(
        repositories: Repositories,
        fetcher: any UsageFetching,
        now: @escaping @Sendable () -> Date
    ) -> SyncCoordinator {
        SyncCoordinator(
            quotas: repositories.quotas,
            snapshots: repositories.snapshots,
            timelines: repositories.timelines,
            providers: repositories.providers,
            plans: repositories.plans,
            engine: AllocationEngine(calendar: calendar),
            fetcher: fetcher,
            calendar: calendar,
            now: now,
            preferences: repositories.preferences
        )
    }

    static func failure(_ code: ProviderErrorCode, at date: Date) -> SyncFailure {
        SyncFailure(code: code, message: code.rawValue.description, occurredAt: date)
    }
}

/// A provider that answers whatever the test tells it to answer.
///
/// The whole scripted-provider contract in one type: a script of results, consumed in order, and a
/// record of how it was called. No sockets, no processes, no sleeping — so a
/// test can assert the exact number of reads a policy performs, which is the
/// only way to test that the app is not polling more often than it says it will.
actor ScriptedProvider: UsageFetching {
    private var script: [SyncResult]
    private(set) var callCount = 0
    private(set) var askedForLocalDate: [LocalDate] = []

    init(_ script: [SyncResult]) {
        self.script = script
    }

    /// Answers the same thing however many times it is asked.
    init(always result: SyncResult) {
        self.init(Array(repeating: result, count: 16))
    }

    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        callCount += 1
        askedForLocalDate.append(localDate)
        guard !script.isEmpty else {
            return .failure(
                SyncFailure(code: .nothingToReport, message: "Script exhausted.", occurredAt: Date())
            )
        }
        let result = script.count == 1 ? script[0] : script.removeFirst()
        return UsageFetchOutcome(result: result)
    }
}

/// Answers differently per provider, so independence can be tested.
actor PerProviderFetcher: UsageFetching {
    private let results: [String: SyncResult]

    init(results: [String: SyncResult]) {
        self.results = results
    }

    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        if let result = results[providerID.rawValue] {
            return UsageFetchOutcome(result: result)
        }
        return .failure(
            SyncFailure(code: .nothingToReport, message: "No script.", occurredAt: Date())
        )
    }
}
