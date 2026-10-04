import Core
import Foundation
import Platform

/// The world where the provider has stopped reporting one of its limits.
///
/// Its own file because it is a whole second world — a second quota on the same
/// provider, holding the reading the quota under test has lost — and folding it
/// into the fixture would leave a `if bucketGone` arrangement nobody reads in
/// one piece.
extension SummaryFixture {
    /// The provider's other quota, its reading, and the quota's later one without
    /// the limit.
    ///
    /// Written the way the coordinator writes it: each quota's record is keyed by
    /// the limit it watches, and holds whatever the provider reported that
    /// refresh. So the quota under test ends up reading a record whose reading no
    /// longer has its limit, while the sibling's older record still does.
    static func seedVanishedLimit(
        repositories: Repositories,
        quota: Quota,
        providerID: ProviderID
    ) async throws {
        let other = try UsageBucket(
            id: "other",
            displayName: "Other",
            usagePercentage: 12,
            period: quota.period
        )
        let watched = try UsageBucket(
            id: bucketID,
            displayName: "Usage",
            usagePercentage: 40,
            period: quota.period
        )
        let sibling = try Quota(
            id: siblingQuotaID,
            name: "Mock",
            providerID: providerID,
            bucketID: other.id,
            period: quota.period,
            policy: .even,
            createdAt: reference,
            updatedAt: reference
        )
        try await repositories.quotas.save(sibling)
        try await repositories.snapshots.save(
            reading(quotaID: sibling.id, bucketID: other.id, at: reference, buckets: [other, watched])
        )
        try await repositories.snapshots.save(
            reading(
                quotaID: quota.id,
                bucketID: bucketID,
                at: reference.addingTimeInterval(3600),
                buckets: [other]
            )
        )
    }

    static func reading(
        quotaID: UUID,
        bucketID: String,
        at updatedAt: Date,
        buckets: [UsageBucket]
    ) throws -> SnapshotRecord {
        SnapshotRecord(
            quotaID: quotaID,
            bucketID: bucketID,
            accountLabel: account,
            snapshot: try UsageSnapshot(updatedAt: updatedAt, buckets: buckets)
        )
    }
}
