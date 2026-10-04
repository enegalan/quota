import Foundation
import Testing
@testable import Core
@testable import Platform

@Suite("Repositories")
struct RepositoryTests {
    private func makeQuota(name: String) async throws -> Quota {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        return try Quota(
            name: name,
            providerID: try ProviderID("mock"),
            period: try QuotaPeriod(start: start, end: end),
            policy: .even,
            createdAt: start,
            updatedAt: start
        )
    }

    private func snapshot(_ percentage: Double, bucketID: String) throws -> UsageSnapshot {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        return try UsageSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            buckets: [
                try UsageBucket(
                    id: bucketID,
                    displayName: bucketID,
                    usagePercentage: percentage,
                    period: try QuotaPeriod(start: start, end: end)
                ),
            ]
        )
    }

    // MARK: Quotas

    @Test("Saving a quota twice updates it rather than duplicating it")
    func saveIsUpsert() async throws {
        let store = CodableStore.inMemory()
        let repository = QuotaRepository(store: store)
        let quota = try await makeQuota(name: "Before")

        try await repository.save(quota)
        let renamed = try Quota(
            id: quota.id,
            name: "After",
            providerID: quota.providerID,
            bucketID: quota.bucketID,
            period: quota.period,
            policy: quota.policy,
            createdAt: quota.createdAt,
            updatedAt: quota.updatedAt
        )
        try await repository.save(renamed)

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(all.first?.name == "After")
    }

    @Test("Deleting a quota removes it and leaves the others")
    func deleteIsScoped() async throws {
        let store = CodableStore.inMemory()
        let repository = QuotaRepository(store: store)
        let first = try await makeQuota(name: "First")
        let second = try await makeQuota(name: "Second")
        try await repository.save([first, second])

        try await repository.delete(id: first.id)
        #expect(try await repository.all().map(\.name) == ["Second"])
    }

    @Test("Quotas can be listed per provider")
    func listByProvider() async throws {
        let store = CodableStore.inMemory()
        let repository = QuotaRepository(store: store)
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        let period = try QuotaPeriod(start: start, end: end)

        let mock = try Quota(
            name: "Mock", providerID: try ProviderID("mock"),
            period: period, policy: .even, createdAt: start, updatedAt: start
        )
        let other = try Quota(
            name: "Other", providerID: try ProviderID("other"),
            period: period, policy: .even, createdAt: start, updatedAt: start
        )
        try await repository.save([mock, other])

        let forMock = try await repository.quotas(providerID: try ProviderID("mock"))
        #expect(forMock.map(\.name) == ["Mock"])
    }

    // MARK: Snapshots

    /// The regression this keying exists for. A provider metering two pools must
    /// not have one pool's reading overwritten by the other's.
    @Test("Two buckets of one quota keep separate readings")
    func bucketsDoNotOverwrite() async throws {
        let store = CodableStore.inMemory()
        let repository = SnapshotRepository(store: store)
        let quota = try await makeQuota(name: "Cursor")

        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "models", accountLabel: "work",
            snapshot: try snapshot(10, bucketID: "models")
        ))
        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "other", accountLabel: "work",
            snapshot: try snapshot(90, bucketID: "other")
        ))

        #expect(try await repository.all().count == 2)
        let models = try await repository.snapshot(
            quotaID: quota.id, bucketID: "models", accountLabel: "work"
        )
        let other = try await repository.snapshot(
            quotaID: quota.id, bucketID: "other", accountLabel: "work"
        )
        #expect(models?.snapshot.primaryBucket?.usagePercentage == 10)
        #expect(other?.snapshot.primaryBucket?.usagePercentage == 90)
    }

    /// A user who switches accounts inside one provider must not be served the
    /// previous account's cached numbers.
    @Test("Two accounts of one provider keep separate readings")
    func accountsDoNotOverwrite() async throws {
        let store = CodableStore.inMemory()
        let repository = SnapshotRepository(store: store)
        let quota = try await makeQuota(name: "Cursor")

        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "models", accountLabel: "work",
            snapshot: try snapshot(10, bucketID: "models")
        ))
        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "models", accountLabel: "personal",
            snapshot: try snapshot(80, bucketID: "models")
        ))

        #expect(try await repository.all().count == 2)
        let work = try await repository.snapshot(
            quotaID: quota.id, bucketID: "models", accountLabel: "work"
        )
        let personal = try await repository.snapshot(
            quotaID: quota.id, bucketID: "models", accountLabel: "personal"
        )
        #expect(work?.snapshot.primaryBucket?.usagePercentage == 10)
        #expect(personal?.snapshot.primaryBucket?.usagePercentage == 80)
    }

    @Test("Every reading for a quota can be fetched at once")
    func allForQuota() async throws {
        let store = CodableStore.inMemory()
        let repository = SnapshotRepository(store: store)
        let quota = try await makeQuota(name: "Cursor")

        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "models", accountLabel: "work",
            snapshot: try snapshot(10, bucketID: "models")
        ))
        try await repository.save(SnapshotRecord(
            quotaID: quota.id, bucketID: "other", accountLabel: "work",
            snapshot: try snapshot(90, bucketID: "other")
        ))

        let records = try await repository.snapshots(quotaID: quota.id, accountLabel: "work")
        #expect(records.count == 2)
    }

    @Test("Deleting a quota removes only its own readings")
    func deleteIsScopedToQuota() async throws {
        let store = CodableStore.inMemory()
        let repository = SnapshotRepository(store: store)
        let first = try await makeQuota(name: "First")
        let second = try await makeQuota(name: "Second")

        try await repository.save(SnapshotRecord(
            quotaID: first.id, bucketID: "models", accountLabel: "work",
            snapshot: try snapshot(10, bucketID: "models")
        ))
        try await repository.save(SnapshotRecord(
            quotaID: second.id, bucketID: "models", accountLabel: "work",
            snapshot: try snapshot(20, bucketID: "models")
        ))

        try await repository.delete(quotaID: first.id)
        let remaining = try await repository.all()
        #expect(remaining.count == 1)
        #expect(remaining.first?.quotaID == second.id)
    }

    // MARK: Timelines

    @Test("Appending a timeline keeps only the most recent points")
    func timelineTrimsToRetention() async throws {
        let store = CodableStore.inMemory()
        let repository = TimelineRepository(store: store)
        let quota = try await makeQuota(name: "Cursor")

        let points = try (0 ..< 10).map { index in
            try TimelinePoint(
                recordedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                bucketID: "models",
                usagePercentage: Double(index)
            )
        }
        try await repository.append(
            TimelineRecord(
                quotaID: quota.id, bucketID: "models", accountLabel: "work",
                timeline: UsageTimeline(points: points)
            ),
            keepingAtMost: 3
        )

        let stored = try await repository.timeline(
            quotaID: quota.id, bucketID: "models", accountLabel: "work"
        )
        #expect(stored?.timeline.points.count == 3)
        #expect(stored?.timeline.points.last?.usagePercentage == 9)
    }

    @Test("A quota's timeline is not affected by another quota's")
    func timelinesAreScoped() async throws {
        let store = CodableStore.inMemory()
        let repository = TimelineRepository(store: store)
        let first = try await makeQuota(name: "First")
        let second = try await makeQuota(name: "Second")

        try await repository.append(
            TimelineRecord(
                quotaID: first.id, bucketID: "models", accountLabel: "work",
                timeline: UsageTimeline(points: [
                    try TimelinePoint(
                        recordedAt: Date(timeIntervalSince1970: 0),
                        bucketID: "models", usagePercentage: 5
                    ),
                ])
            ),
            keepingAtMost: 100
        )

        let forSecond = try await repository.timeline(
            quotaID: second.id, bucketID: "models", accountLabel: "work"
        )
        #expect(forSecond == nil)
    }

    // MARK: Providers and preferences

    @Test("A provider record is replaced on save, not duplicated")
    func providerSaveIsUpsert() async throws {
        let store = CodableStore.inMemory()
        let repository = ProviderRepository(store: store)
        let id = try ProviderID("mock")

        try await repository.save(ProviderRecord(
            providerID: id, displayName: "Mock", installedVersion: "1.0.0"
        ))
        try await repository.save(ProviderRecord(
            providerID: id, displayName: "Mock Renamed", installedVersion: "1.1.0",
            authenticatedAccountLabel: "work", lastSyncAt: Date(timeIntervalSince1970: 1)
        ))

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(all.first?.installedVersion == "1.1.0")
        #expect(all.first?.authenticatedAccountLabel == "work")
    }

    @Test("Preferences fall back to defaults when nothing is stored")
    func preferencesDefault() async throws {
        let store = CodableStore.inMemory()
        #expect(try await PreferencesRepository(store: store).load() == .default)
    }

    @Test("Saved preferences are read back")
    func preferencesRoundTrip() async throws {
        let store = CodableStore.inMemory()
        let repository = PreferencesRepository(store: store)
        let preferences = Preferences(
            defaultPolicyKind: "weekly",
            hasCompletedOnboarding: true,
            refreshIntervalSeconds: 300
        )
        try await repository.save(preferences)
        #expect(try await repository.load() == preferences)
    }
}
