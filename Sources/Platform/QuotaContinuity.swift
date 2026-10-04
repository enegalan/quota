import Core
import Foundation

/// What removing a provider would cost, for the uninstall confirmation dialog.
///
/// Counted as well as listed because the dialog leads with a number — "3 quotas
/// will stop updating" — and the ids are there for a caller that wants to show
/// which ones.
public struct UninstallImpact: Sendable, Equatable {
    /// The quotas that name this provider, by id.
    public let affectedQuotas: [String]
    /// How many quotas would stop being refreshed.
    public let unrefreshableCount: Int

    public init(affectedQuotas: [String], unrefreshableCount: Int) {
        self.affectedQuotas = affectedQuotas
        self.unrefreshableCount = unrefreshableCount
    }

    public static let none = UninstallImpact(affectedQuotas: [], unrefreshableCount: 0)

    /// Whether removing this provider is worth confirming at all.
    ///
    /// Nothing depends on it, so the removal is not a decision and asking about it
    /// would be a dialog about nothing.
    public var needsConfirmation: Bool {
        unrefreshableCount > 0
    }
}

/// A quota whose provider is not on this machine.
///
/// Not an error and not a deletion. The quota's last good snapshot is still
/// there and still worth showing; what is missing is any way to refresh it.
/// The record survives, and it says so.
public struct UnrefreshableQuota: Sendable, Equatable, Identifiable {
    public let quotaID: UUID
    public let providerID: String
    public let reason: ProviderState
    public let lastKnownSnapshotAt: Date?

    public var id: UUID {
        quotaID
    }

    public init(
        quotaID: UUID,
        providerID: String,
        reason: ProviderState,
        lastKnownSnapshotAt: Date?
    ) {
        self.quotaID = quotaID
        self.providerID = providerID
        self.reason = reason
        self.lastKnownSnapshotAt = lastKnownSnapshotAt
    }
}

/// Finds the quotas that can no longer be refreshed, and why.
///
/// A separate answer from the uninstall impact: the impact is asked before a user
/// confirms a removal, and this is what the rest of the application reads
/// afterwards, including for a provider that was never installed here in the first
/// place.
public struct QuotaContinuity: Sendable {
    private let quotas: QuotaRepository
    private let snapshots: SnapshotRepository
    private let timeline: TimelineRepository
    private let installed: InstalledProviderRepository
    private let disabledProviders: Set<String>

    public init(
        quotas: QuotaRepository,
        snapshots: SnapshotRepository,
        timeline: TimelineRepository,
        installed: InstalledProviderRepository,
        disabledProviders: Set<String> = []
    ) {
        self.quotas = quotas
        self.snapshots = snapshots
        self.timeline = timeline
        self.installed = installed
        self.disabledProviders = disabledProviders
    }

    /// Every quota that cannot be refreshed right now, with its cached data intact.
    public func unrefreshable() async throws -> [UnrefreshableQuota] {
        let records = try await installed.all()
        let byProvider = Dictionary(
            records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var result: [UnrefreshableQuota] = []
        for quota in try await quotas.all() {
            let id = quota.providerID.rawValue
            let reason: ProviderState? = if disabledProviders.contains(id) {
                .disabled
            } else if byProvider[id] == nil {
                .missing
            } else if byProvider[id]?.state.permitsLaunch == false {
                byProvider[id]?.state
            } else {
                nil
            }
            guard let reason else { continue }
            await result.append(
                UnrefreshableQuota(
                    quotaID: quota.id,
                    providerID: id,
                    reason: reason,
                    lastKnownSnapshotAt: try lastReading(for: quota)
                )
            )
        }
        return result
    }

    /// When this quota's own buckets were last read, if ever.
    ///
    /// The newest across the quota's buckets rather than the newest overall: a
    /// provider that meters two pools and stopped refreshing one of them is stale
    /// for that pool, and the freshest number on the other does not fix it.
    private func lastReading(for quota: Quota) async throws -> Date? {
        let records = try await snapshots.all().filter { $0.quotaID == quota.id }
        let history = try await timeline.all()
        var newest: Date?
        for record in records {
            for entry in history where entry.quotaID == record.quotaID
                && entry.bucketID == record.bucketID
            {
                guard let last = entry.timeline.points.last?.recordedAt else { continue }
                // Written as a merge rather than a comparison against an unwrapped
                // optional, so there is no force unwrap to get wrong.
                newest = max(newest ?? last, last)
            }
        }
        return newest
    }
}
