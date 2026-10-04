import Core
import Foundation
import Testing
@testable import Platform

@Suite("Cache keying")
struct CacheKeyingTests {
    @Test("Two accounts never serve each other's snapshot")
    func accountsStaySeparate() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let period = try QuotaPeriod(
            start: now.addingTimeInterval(-86400),
            end: now.addingTimeInterval(86400 * 20)
        )
        let store = CodableStore.inMemory()
        let snapshots = SnapshotRepository(store: store)
        let quotaID = UUID()
        try await Self.save(
            snapshots, quotaID: quotaID, label: "account-a",
            snapshot: try Self.snapshot(period: period, updatedAt: now, percentage: 10)
        )
        try await Self.save(
            snapshots, quotaID: quotaID, label: "account-b",
            snapshot: try Self.snapshot(period: period, updatedAt: now, percentage: 90)
        )

        let forA = try await snapshots.snapshot(
            quotaID: quotaID, bucketID: "plan", accountLabel: "account-a"
        )
        let forB = try await snapshots.snapshot(
            quotaID: quotaID, bucketID: "plan", accountLabel: "account-b"
        )
        #expect(forA?.snapshot.buckets.first?.usagePercentage == 10)
        #expect(forB?.snapshot.buckets.first?.usagePercentage == 90)
    }

    @Test("A snapshot past cycle end is refused by the reading path")
    func refusesPastCycle() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = try await Self.endedCycleFixture(now: now)
        let outcome = try await fixture.coordinator.reading(for: fixture.quotaID)
        guard case .unserved(let reason) = outcome, case .periodEnded = reason else {
            Issue.record("expected periodEnded, got \(outcome)")
            return
        }
    }

    private static func endedCycleFixture(now: Date) async throws -> (
        coordinator: SyncCoordinator, quotaID: UUID
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let ended = try QuotaPeriod(
            start: now.addingTimeInterval(-86400 * 40),
            end: now.addingTimeInterval(-86400)
        )
        let store = CodableStore.inMemory()
        let quotaID = try await seedEndedCycle(
            store: store, period: ended, now: now
        )
        return (
            SyncCoordinator(
                quotas: QuotaRepository(store: store),
                snapshots: SnapshotRepository(store: store),
                timelines: TimelineRepository(store: store),
                providers: ProviderRepository(store: store),
                plans: AllocationPlanRepository(store: store),
                engine: AllocationEngine(calendar: calendar),
                fetcher: StaticFetcher(),
                calendar: calendar,
                now: { now }
            ),
            quotaID
        )
    }

    private static func seedEndedCycle(
        store: CodableStore,
        period: QuotaPeriod,
        now: Date
    ) async throws -> UUID {
        let quotas = QuotaRepository(store: store)
        let snapshots = SnapshotRepository(store: store)
        let providers = ProviderRepository(store: store)
        let providerID = try ProviderID("mock")
        let quota = try Quota(
            id: UUID(),
            name: "Test",
            providerID: providerID,
            bucketID: "plan",
            period: period,
            policy: .even,
            createdAt: now,
            updatedAt: now
        )
        try await quotas.save(quota)
        try await providers.save(
            ProviderRecord(
                providerID: providerID,
                displayName: "Mock",
                installedVersion: "1.0.0",
                authenticatedAccountLabel: "work@example.com"
            )
        )
        try await save(
            snapshots, quotaID: quota.id, label: "work@example.com",
            snapshot: try snapshot(
                period: period, updatedAt: now.addingTimeInterval(-86400 * 2), percentage: 40
            )
        )
        return quota.id
    }

    private static func snapshot(
        period: QuotaPeriod, updatedAt: Date, percentage: Double
    ) throws -> UsageSnapshot {
        try UsageSnapshot(
            updatedAt: updatedAt,
            buckets: [
                try UsageBucket(
                    id: "plan",
                    displayName: "Plan",
                    usagePercentage: percentage,
                    period: period
                ),
            ]
        )
    }

    private static func save(
        _ snapshots: SnapshotRepository,
        quotaID: UUID,
        label: String,
        snapshot: UsageSnapshot
    ) async throws {
        try await snapshots.save(
            SnapshotRecord(
                quotaID: quotaID,
                bucketID: "plan",
                accountLabel: label,
                snapshot: snapshot
            )
        )
    }
}

private struct StaticFetcher: UsageFetching {
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        .failure(
            SyncFailure(code: .nothingToReport, message: "unused", occurredAt: Date())
        )
    }
}
