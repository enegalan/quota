import Foundation
import Testing
@testable import Core
@testable import Platform

/// The hop from a snapshot-wide period to a period per bucket.
///
/// The stored shape this reads no longer exists in the code, so the fixtures are
/// written by hand as version 1 wrote them. That is the point: a fixture built by
/// encoding today's types would change with them, and would pass exactly when the
/// migration was wrong.
@Suite("Period per bucket migration")
struct PeriodPerBucketTests {
    /// Version 1's envelope: one period, above the buckets.
    private static func version1Snapshots(
        buckets: String,
        period: String = #"{"start":1756684800,"end":1759190399}"#,
        updatedAt: String = "1757956800"
    ) throws -> Data {
        let json = """
        {"version":1,"payload":[
          {"quotaID":"6C4E0B0A-1111-2222-3333-444455556666","bucketID":"primary",
           "accountLabel":"work@example.com",
           "snapshot":{"period":\(period),"updatedAt":\(updatedAt),"buckets":\(buckets)}}
        ]}
        """
        return Data(json.utf8)
    }

    private static let twoBuckets = """
    [{"id":"plan","displayName":"Plan","usagePercentage":11.5,"limitDescription":"2000 credits"},
     {"id":"api","displayName":"API","usagePercentage":0.25}]
    """

    /// A version 1 snapshot's single period lands on every bucket.
    ///
    /// Copying rather than choosing is what makes this exact for the providers
    /// that existed under version 1: their pools shared a clock, so the window
    /// each bucket is given is the window it was already measured over. The first
    /// bucket then reads as the one the old code would have paced every quota
    /// against, which is the reading a user upgrading from one quota per provider
    /// expects to be unchanged.
    @Test("The file's one period is carried onto every bucket")
    func periodLandsOnEveryBucket() throws {
        let migrated = try #require(
            PeriodPerBucket().migrate(
                try Self.version1Snapshots(buckets: Self.twoBuckets),
                for: PersistenceConstants.FileName.snapshots
            ) as Data?
        )
        let envelope = try JSONDecoder.quota.decode(
            StoreSchema.Envelope<[SnapshotRecord]>.self, from: migrated
        )

        #expect(envelope.version == 2)
        let snapshot = try #require(envelope.payload.first).snapshot
        let expected = try QuotaPeriod(
            start: Date(timeIntervalSince1970: 1_756_684_800),
            end: Date(timeIntervalSince1970: 1_759_190_399)
        )
        #expect(snapshot.buckets.count == 2)
        for bucket in snapshot.buckets {
            #expect(bucket.period == expected)
        }
        #expect(snapshot.period(forBucket: "plan") == expected)
        // The period is no longer a property of the reading, so a second bucket's
        // window is a value rather than an absence.
        #expect(snapshot.period(forBucket: "api") == expected)
    }

    @Test("Everything else about the reading survives the hop")
    func figuresSurviveTheHop() throws {
        let migrated = try #require(
            PeriodPerBucket().migrate(
                try Self.version1Snapshots(buckets: Self.twoBuckets),
                for: PersistenceConstants.FileName.snapshots
            ) as Data?
        )
        let snapshot = try #require(
            try JSONDecoder.quota.decode(StoreSchema.Envelope<[SnapshotRecord]>.self, from: migrated)
                .payload.first
        ).snapshot

        #expect(snapshot.buckets[0].id == "plan")
        #expect(snapshot.buckets[0].displayName == "Plan")
        #expect(snapshot.buckets[0].usagePercentage == 11.5)
        #expect(snapshot.buckets[0].limitDescription == "2000 credits")
        #expect(snapshot.buckets[1].id == "api")
        #expect(snapshot.buckets[1].usagePercentage == 0.25)
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 1_757_956_800))
    }

    /// A reading's age decides whether the interface calls it stale, and these
    /// files store dates to three decimal places. A hop that re-serialised them
    /// through a generic value would round them, and a reading taken a third of a
    /// second before a launch would come back a third of a second older on every
    /// one.
    @Test("Fractional seconds in a reading are not rounded away")
    func fractionalSecondsSurvive() throws {
        let data = try Self.version1Snapshots(
            buckets: Self.twoBuckets,
            period: #"{"start":1756684800.25,"end":1759190399.75}"#,
            updatedAt: "1757956800.125"
        )
        let migrated = try #require(
            PeriodPerBucket().migrate(data, for: PersistenceConstants.FileName.snapshots) as Data?
        )
        let envelope = try JSONDecoder.quota.decode(
            StoreSchema.Envelope<[SnapshotRecord]>.self, from: migrated
        )

        let snapshot = try #require(envelope.payload.first).snapshot
        #expect(snapshot.updatedAt.timeIntervalSince1970 == 1_757_956_800.125)
        let period = try #require(snapshot.period(forBucket: "plan"))
        #expect(period.start.timeIntervalSince1970 == 1_756_684_800.25)
        #expect(period.end.timeIntervalSince1970 == 1_759_190_399.75)
    }

    /// Every family has to reach the current version, or the store treats it as
    /// written by a build it cannot read and sets it aside. So a family this hop
    /// has nothing to say about is stamped anyway — with its payload left exactly
    /// as it was, because a quota's `updatedAt` is as load-bearing as a reading's.
    @Test("A family this hop does not touch is stamped, and its payload is untouched")
    func otherFamiliesAreOnlyStamped() throws {
        let json = """
        {"version":1,"payload":[
          {"quota":{"id":"6C4E0B0A-1111-2222-3333-444455556666","name":"Cursor",
                    "providerID":"mock","period":{"start":1756684800,"end":1759190399},
                    "policy":{"kind":"even"},"createdAt":1756684800.5,"updatedAt":1757956800.375}}
        ]}
        """
        let migrated = try #require(
            PeriodPerBucket().migrate(
                Data(json.utf8),
                for: PersistenceConstants.FileName.quotas
            ) as Data?
        )

        #expect(StoreSchema.version(of: migrated) == 2)
        let envelope = try JSONDecoder.quota.decode(
            StoreSchema.Envelope<[QuotaRecord]>.self, from: migrated
        )
        let quota = try #require(envelope.payload.first).quota
        #expect(quota.name == "Cursor")
        #expect(quota.period.start == Date(timeIntervalSince1970: 1_756_684_800))
        #expect(quota.createdAt.timeIntervalSince1970 == 1_756_684_800.5)
        #expect(quota.updatedAt.timeIntervalSince1970 == 1_757_956_800.375)
    }

    /// A snapshot file that is not the shape this hop expects is refused, not
    /// guessed at: a reading with no period on it and no period to hand down would
    /// otherwise be written out as one the interface would call stale.
    @Test("A snapshot file in an unexpected shape is refused")
    func unexpectedShapeIsRefused() throws {
        let json = """
        {"version":1,"payload":[{"quotaID":"not-a-uuid","bucketID":"primary"}]}
        """
        // The specific error is the decoder's, and pinning it would say the hop
        // depends on a type it only reaches by accident. What matters is that it
        // throws rather than returning bytes.
        #expect(throws: (any Error).self) {
            try PeriodPerBucket().migrate(
                Data(json.utf8),
                for: PersistenceConstants.FileName.snapshots
            )
        }
    }

    @Test("A file that parses but is not an envelope is refused as unreadable")
    func notAnEnvelopeIsUnreadable() {
        #expect(throws: MigrationError.unreadable) {
            try PeriodPerBucket().migrate(
                Data("[1, 2, 3]".utf8),
                for: PersistenceConstants.FileName.quotas
            )
        }
    }

    /// Which is what a user experiences: the file is set aside rather than read,
    /// so nothing is silently half-loaded.
    @Test("A store quarantines a snapshot file it cannot migrate")
    func unmigratableSnapshotIsQuarantined() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-period-broken-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(PersistenceConstants.FileName.snapshots)
        try Data(#"{"version":1,"payload":[{"quotaID":"not-a-uuid","bucketID":"primary"}]}"#.utf8)
            .write(to: url)
        let disk = DiskStoreFixture(directory: directory, now: { Date(timeIntervalSince1970: 0) })

        #expect(try await disk.store.loadSnapshots().isEmpty)
        let contents = try disk.directoryContents()
        #expect(contents.contains { $0.hasSuffix(PersistenceConstants.quarantineSuffix) })
    }

    /// The hop is reached through the store, so what is checked is what a user
    /// upgrading experiences: their file is read, not quarantined.
    @Test("A store reads a version 1 snapshot file and rewrites it at version 2")
    func storeMigratesSnapshotsOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-period-per-bucket-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(PersistenceConstants.FileName.snapshots)
        try Self.version1Snapshots(buckets: Self.twoBuckets).write(to: url)
        let disk = DiskStoreFixture(directory: directory, now: { Date(timeIntervalSince1970: 0) })

        let records = try await disk.store.loadSnapshots()

        #expect(records.count == 1)
        let snapshot = try #require(records.first).snapshot
        let expected = try QuotaPeriod(
            start: Date(timeIntervalSince1970: 1_756_684_800),
            end: Date(timeIntervalSince1970: 1_759_190_399)
        )
        #expect(snapshot.buckets.allSatisfy { $0.period == expected })
        #expect(snapshot.period(forBucket: "plan") == expected)
        #expect(snapshot.bucket(id: "api")?.usagePercentage == 0.25)
        // Written back at the current version, so the hop runs once and not again.
        #expect(StoreSchema.version(of: try Data(contentsOf: url)) == StoreSchema.currentVersion)
        let contents = try disk.directoryContents()
        #expect(!contents.contains { $0.hasSuffix(PersistenceConstants.quarantineSuffix) })
    }
}
