import Foundation
import Testing
@testable import Core
@testable import Platform

/// A hop from one version to the next, standing in for a real migration.
///
/// A real one would also rewrite the payload, and these tests are about the
/// dispatch rather than the rewriting: walking the wrong number of hops, applying
/// a hop to a file already current, or accepting a version from a newer build.
/// `PeriodPerBucketTests` covers the rewriting.
private struct CountingMigration: SchemaMigration {
    let fromVersion: Int
    let toVersion: Int
    let marker: String

    func migrate(_ data: Data, for fileName: String) throws -> Data {
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["migratedFrom"] = marker
        object["version"] = toVersion
        return try JSONSerialization.data(withJSONObject: object)
    }
}

@Suite("Schema migration")
struct SchemaMigrationTests {
    /// The fixture for a file stamped with the current version.
    private func currentVersionFixture() async throws -> (Data, QuotaRecord) {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        let record = QuotaRecord(quota: try Quota(
            name: "Cursor",
            providerID: try ProviderID("mock"),
            period: try QuotaPeriod(start: start, end: end),
            policy: .even,
            createdAt: start,
            updatedAt: start
        ))
        let envelope = StoreSchema.Envelope(payload: [record])
        return (try JSONEncoder.quota.encode(envelope), record)
    }

    private func stamp(_ version: Int, payload: [QuotaRecord]) throws -> Data {
        try JSONEncoder.quota.encode(StoreSchema.Envelope(version: version, payload: payload))
    }

    @Test("A file at the current version loads with no migration applied")
    func currentVersionNeedsNoMigration() async throws {
        let (data, record) = try await currentVersionFixture()
        #expect(StoreSchema.version(of: data) == StoreSchema.currentVersion)

        let migrator = SchemaMigrator(targetVersion: StoreSchema.currentVersion)
        let migrated = try migrator.migrate(
            data, from: StoreSchema.currentVersion, for: PersistenceConstants.FileName.quotas
        )
        #expect(migrated == data)
        #expect(try JSONDecoder.quota.decode(StoreSchema.Envelope<[QuotaRecord]>.self, from: try #require(migrated))
            .payload == [record])
    }

    @Test("A file from a newer build is refused rather than read")
    func newerVersionIsRefused() throws {
        let migrator = SchemaMigrator(targetVersion: 2)
        let data = try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: 3, payload: [QuotaRecord]())
        )
        #expect(try migrator.migrate(data, from: 3, for: PersistenceConstants.FileName.quotas) == nil)
    }

    @Test("An older file with no registered migration is refused")
    func missingMigrationIsRefused() throws {
        let migrator = SchemaMigrator(targetVersion: 3)
        let data = try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: 1, payload: [QuotaRecord]())
        )
        #expect(try migrator.migrate(data, from: 1, for: PersistenceConstants.FileName.quotas) == nil)
    }

    @Test("The chain walks one hop at a time to the target version")
    func chainWalksEveryHop() throws {
        let migrator = SchemaMigrator(
            targetVersion: 3,
            migrations: [
                CountingMigration(fromVersion: 1, toVersion: 2, marker: "one"),
                CountingMigration(fromVersion: 2, toVersion: 3, marker: "two"),
            ]
        )
        let data = try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: 1, payload: [QuotaRecord]())
        )

        let migrated = try #require(try migrator.migrate(data, from: 1, for: PersistenceConstants.FileName.quotas))
        let object = try #require(try JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        // The last hop wins, and it was reached through the first.
        #expect(object["migratedFrom"] as? String == "two")
        #expect(object["version"] as? Int == 3)
    }

    @Test("A hop that does not advance is refused rather than looping")
    func nonAdvancingMigrationIsRefused() throws {
        let migrator = SchemaMigrator(
            targetVersion: 2,
            migrations: [CountingMigration(fromVersion: 1, toVersion: 1, marker: "stuck")]
        )
        let data = try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: 1, payload: [QuotaRecord]())
        )
        #expect(try migrator.migrate(data, from: 1, for: PersistenceConstants.FileName.quotas) == nil)
    }

    @Test("A hop that overshoots the target is refused")
    func overshootingMigrationIsRefused() throws {
        let migrator = SchemaMigrator(
            targetVersion: 2,
            migrations: [CountingMigration(fromVersion: 1, toVersion: 3, marker: "too-far")]
        )
        let data = try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: 1, payload: [QuotaRecord]())
        )
        #expect(try migrator.migrate(data, from: 1, for: PersistenceConstants.FileName.quotas) == nil)
    }

    @Test("A store dispatches to the injected migrator when reading an old file")
    func storeDispatchesOnStoredVersion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let start = QuotaFixture.start
        let end = QuotaFixture.end
        let record = QuotaRecord(quota: try Quota(
            name: "Cursor",
            providerID: try ProviderID("mock"),
            period: try QuotaPeriod(start: start, end: end),
            policy: .even,
            createdAt: start,
            updatedAt: start
        ))

        // A file stamped with an older version than the target this store
        // migrates to, carrying the payload under the versioned envelope.
        let url = directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        try stamp(1, payload: [record]).write(to: url)

        let migrator = SchemaMigrator(
            targetVersion: 2,
            migrations: [CountingMigration(fromVersion: 1, toVersion: 2, marker: "upgraded")]
        )
        let store = CodableStore.onDisk(
            directory: directory,
            now: { Date(timeIntervalSince1970: 0) },
            migrator: migrator
        )

        // The payload came through, having been dispatched on the stored version.
        #expect(try await store.loadQuotas() == [record])
        // And the file was rewritten at the new version, so the hop runs once.
        #expect(StoreSchema.version(of: try Data(contentsOf: url)) == 2)
    }

    @Test("A file the store cannot migrate is quarantined, not decoded")
    func unmigratableFileIsQuarantined() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-unmigratable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try stamp(1, payload: []).write(
            to: directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        )
        // Target version 2, but nothing registered to get there.
        let disk = DiskStoreFixture(
            directory: directory,
            now: { Date(timeIntervalSince1970: 0) },
            migrator: SchemaMigrator(targetVersion: 2)
        )

        #expect(try await disk.store.loadQuotas().isEmpty)
        let contents = try disk.directoryContents()
        #expect(contents.contains { $0.hasSuffix(PersistenceConstants.quarantineSuffix) })
    }

    @Test("Bytes that are not an envelope at all report no version")
    func nonEnvelopeHasNoVersion() {
        #expect(StoreSchema.version(of: Data("not json".utf8)) == nil)
        #expect(StoreSchema.version(of: Data("[1, 2, 3]".utf8)) == nil)
    }
}

@Suite("Adding a field to a stored record")
struct AdditiveFieldTests {
    @Test("A provider record written before backoff existed loads with no count")
    func missingBackoffCountIsZero() throws {
        let json = """
        {
          "providerID": "mock",
          "displayName": "Mock",
          "installedVersion": "1.0.0",
          "authenticatedAccountLabel": "work@example.com"
        }
        """
        let record = try JSONDecoder().decode(ProviderRecord.self, from: Data(json.utf8))

        #expect(record.consecutiveFailures == 0)
        #expect(record.authenticatedAccountLabel == "work@example.com")
    }

    @Test("A stored count survives a round trip")
    func countRoundTrips() throws {
        let record = ProviderRecord(
            providerID: try ProviderID("mock"),
            displayName: "Mock",
            installedVersion: "1.0.0",
            consecutiveFailures: 3
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ProviderRecord.self, from: data)

        #expect(decoded.consecutiveFailures == 3)
    }
}
