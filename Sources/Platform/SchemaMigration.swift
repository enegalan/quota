import Core
import Foundation

/// One hop from a stored schema version to the next.
///
/// A migration is a function over bytes rather than over decoded records on
/// purpose: the whole point is to read a shape this build does not understand,
/// and the shape a previous version meant may no longer be `Codable` here.
public protocol SchemaMigration: Sendable {
    var fromVersion: Int { get }
    var toVersion: Int { get }

    /// Returns the bytes in the `toVersion` format. Throwing means the stored
    /// data is not in the shape this migration expects, and the caller sets it
    /// aside rather than guessing.
    ///
    /// - Parameter fileName: which family of records these bytes hold. Named
    ///   because a hop usually applies to one family and not the others, and a
    ///   migration that decoded bytes it did not understand would quarantine a
    ///   file that needed nothing done to it. Every family still has to reach the
    ///   current version, so a migration that skips a file returns it with its
    ///   envelope version restamped and its payload untouched.
    func migrate(_ data: Data, for fileName: String) throws -> Data
}

/// Brings stored bytes up to the version this build writes.
///
/// The chain is dispatched on the stored version rather than applied
/// unconditionally, so an upgrade walks exactly the hops it needs and a
/// downgrade is refused instead of being read as if it were current.
public struct SchemaMigrator: Sendable {
    /// The version this build writes.
    public let targetVersion: Int

    private let migrationsBySource: [Int: any SchemaMigration]

    /// - Parameters:
    ///   - targetVersion: the version the caller wants bytes in.
    ///   - migrations: the hops available. Ones not on a path to
    ///     `targetVersion` are ignored rather than silently applied.
    public init(
        targetVersion: Int = StoreSchema.currentVersion,
        migrations: [any SchemaMigration] = []
    ) {
        self.targetVersion = targetVersion
        var bySource: [Int: any SchemaMigration] = [:]
        // Sorted so that, if two migrations claim the same source version, the
        // higher target wins: preferring the shorter hop cannot get stuck.
        for migration in migrations.sorted(by: { $0.toVersion > $1.toVersion }) {
            bySource[migration.fromVersion] = migration
        }
        migrationsBySource = bySource
    }

    /// The migrator for the current build.
    ///
    /// Registered here and not by each store, so a new hop is picked up by every
    /// family at once: a store that registered its own would be a place to forget
    /// one, and the family that forgot is the one whose data quietly stops
    /// loading.
    public static let current = SchemaMigrator(migrations: [
        PeriodPerBucket(),
    ])

    /// The migrations registered for a version, for tests and for a future
    /// settings screen that wants to say what an upgrade will do.
    public var knownMigrations: [any SchemaMigration] {
        migrationsBySource.values.sorted { $0.fromVersion < $1.fromVersion }
    }

    /// Brings `data` from `storedVersion` to the target version.
    ///
    /// Returns `nil` when the version cannot be reached, which covers both a
    /// file from a newer build and one from an older build whose migration has
    /// been dropped. The caller cannot tell those apart from here and should not
    /// try: both mean "do not interpret these bytes".
    public func migrate(_ data: Data, from storedVersion: Int, for fileName: String) throws -> Data? {
        // A file from a newer build may mean something different now; reading it
        // as if it were current is how data gets quietly corrupted.
        guard storedVersion <= targetVersion else { return nil }

        var current = data
        var version = storedVersion
        while version < targetVersion {
            guard let migration = migrationsBySource[version] else { return nil }
            // A migration that overshoots, or that does not advance, would
            // either lose data or loop; treat either as unavailable.
            guard migration.toVersion > version, migration.toVersion <= targetVersion else {
                return nil
            }
            current = try migration.migrate(current, for: fileName)
            version = migration.toVersion
        }
        return current
    }
}

/// Version 1 stored one period per snapshot; version 2 stores one per bucket.
///
/// The period moves down onto every bucket because a provider's limits need not
/// share a clock, and a snapshot-wide period could only describe one that does.
/// A file written under version 1 could only ever have had one, so its single
/// period is copied onto each of its buckets: for the providers that existed
/// then, whose limits did share a window, that is not an approximation but the
/// same window, written in the place this version reads it from.
///
/// Decoded into types that spell version 1 out rather than walked as generic
/// JSON, because the dates in these files are numbers to three decimal places and
/// a snapshot's timestamp decides whether the interface calls it stale. A hop
/// that re-serialised them through `Any` would be trading a schema fix for a
/// reading that changes age every launch.
public struct PeriodPerBucket: SchemaMigration {
    public let fromVersion = 1
    public let toVersion = 2

    public init() {}

    /// Moves one file from version 1 to version 2.
    ///
    /// Only the snapshots file carries the period, so every other family is handed
    /// back with its envelope restamped and its payload untouched. A hop that
    /// decoded a file it has no model for would be guessing at its shape in order
    /// to leave it alone, and would quarantine data that needed nothing done to it.
    public func migrate(_ data: Data, for fileName: String) throws -> Data {
        guard fileName == PersistenceConstants.FileName.snapshots else {
            return try Self.restamp(data, to: toVersion)
        }
        let old = try JSONDecoder.quota.decode(
            StoreSchema.Envelope<[StoredSnapshot]>.self, from: data
        )
        let upgraded = old.payload.map { $0.periodPerBucket() }
        return try JSONEncoder.quota.encode(
            StoreSchema.Envelope(version: toVersion, payload: upgraded)
        )
    }

    /// The same bytes with the envelope version changed and nothing else.
    ///
    /// Every family has to reach the current version, or the store treats the file
    /// as coming from a build it cannot read and sets it aside. A family this hop
    /// has nothing to say about is still stamped.
    ///
    /// Written rather than decoded: the payload of a family this hop does not
    /// touch is not modelled here, and re-encoding it through a generic value is
    /// the one thing that could disturb a timestamp it has no business reading.
    /// Rewriting the object and handing `JSONSerialization` the untouched
    /// sub-trees keeps those exact; `PeriodPerBucketTests` pins a reading's
    /// fractional seconds across this hop so the claim is checked rather than
    /// believed.
    private static func restamp(_ data: Data, to version: Int) throws -> Data {
        guard var envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.unreadable
        }
        envelope["version"] = version
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}

/// A stored snapshot as version 1 wrote it: one period, above the buckets.
private struct StoredSnapshot: Codable, Sendable {
    struct StoredBucket: Codable, Sendable {
        let id: String
        let displayName: String
        let usagePercentage: Double
        let limitDescription: String?
    }

    struct StoredSnapshotBody: Codable, Sendable {
        let period: QuotaPeriod
        let updatedAt: Date
        let buckets: [StoredBucket]
    }

    let quotaID: UUID
    let bucketID: String
    let accountLabel: String
    let snapshot: StoredSnapshotBody

    /// The same record with the period carried down onto each bucket.
    func periodPerBucket() -> UpgradedSnapshot {
        UpgradedSnapshot(
            quotaID: quotaID,
            bucketID: bucketID,
            accountLabel: accountLabel,
            snapshot: UpgradedSnapshot.Body(
                updatedAt: snapshot.updatedAt,
                buckets: snapshot.buckets.map { bucket in
                    UpgradedSnapshot.Body.UpgradedBucket(
                        id: bucket.id,
                        displayName: bucket.displayName,
                        usagePercentage: bucket.usagePercentage,
                        period: snapshot.period,
                        limitDescription: bucket.limitDescription
                    )
                }
            )
        )
    }
}

/// A stored snapshot in the shape this build reads.
private struct UpgradedSnapshot: Codable, Sendable {
    struct Body: Codable, Sendable {
        struct UpgradedBucket: Codable, Sendable {
            let id: String
            let displayName: String
            let usagePercentage: Double
            let period: QuotaPeriod
            let limitDescription: String?
        }

        let updatedAt: Date
        let buckets: [UpgradedBucket]
    }

    let quotaID: UUID
    let bucketID: String
    let accountLabel: String
    let snapshot: Body
}

/// Why a hop could not be applied.
public enum MigrationError: Error, Equatable {
    /// The bytes are not the shape the hop expected.
    case unreadable
}

/// The version of a stored file, read without interpreting what is inside it.
///
/// The whole point of stamping a version is to be able to ask this question
/// before committing to a decode, so it is answered with its own tiny type rather
/// than by attempting the payload and catching the failure.
struct StoreVersionHeader: Decodable {
    let version: Int
}

extension StoreSchema {
    /// The version stamped in `data`, or nil when `data` is not an envelope at
    /// all.
    ///
    /// Not throwing on purpose. "Unreadable" and "carries no version" lead the
    /// caller to the same place — set the bytes aside — so there is nothing for it
    /// to do differently, and a `try` here would only invite a caller to guess
    /// at a distinction it cannot act on.
    static func version(of data: Data) -> Int? {
        try? JSONDecoder.quota.decode(StoreVersionHeader.self, from: data).version
    }
}
