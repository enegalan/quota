import Foundation

/// A normalised measurement of one provider at one moment in time.
///
/// This is the only place actual usage is recorded. A `Quota` holds no usage
/// figure of its own, so a stale or absent reading can never be mistaken for a
/// current one.
///
/// It carries no period of its own. Every bucket has one, because a provider's
/// limits do not necessarily share a clock: the period a quota is planned over is
/// the period of the bucket that quota reads, and resolving it here is what keeps
/// a quota watching a five-hour limit from being stamped with a week's window.
public struct UsageSnapshot: Sendable, Hashable, Codable, Identifiable {
    public let updatedAt: Date
    public let buckets: [UsageBucket]

    /// Distinguishes two readings of the same provider taken at different
    /// moments. Derived, not stored, because two snapshots of one provider in
    /// one list are otherwise indistinguishable to SwiftUI.
    public var id: Date {
        updatedAt
    }

    /// - Throws: `QuotaDomainError.emptyBuckets` when there is nothing to report,
    ///   and `QuotaDomainError.duplicateBucketID` when two buckets share an
    ///   identifier, which would make a quota's bucket reference ambiguous.
    public init(updatedAt: Date, buckets: [UsageBucket]) throws {
        guard !buckets.isEmpty else {
            throw QuotaDomainError.emptyBuckets
        }

        // `insert` returning false means this identifier was already seen, so the
        // first bucket to collide is the one reported.
        var seen = Set<String>()
        for bucket in buckets where !seen.insert(bucket.id).inserted {
            throw QuotaDomainError.duplicateBucketID(bucket.id)
        }

        self.updatedAt = updatedAt
        self.buckets = buckets
    }

    /// The bucket a quota with no explicit bucket reference uses.
    ///
    /// The first, not the largest or the most complete: a provider decides its
    /// own bucket order, and overriding it would make the app disagree with the
    /// provider's own dashboard.
    public var primaryBucket: UsageBucket? {
        buckets.first
    }

    /// The bucket a quota points at, or the primary one when the quota does not
    /// name a bucket.
    public func bucket(id: String?) -> UsageBucket? {
        guard let id else { return primaryBucket }
        return buckets.first { $0.id == id }
    }

    /// The window the figure a quota reads is measured over.
    ///
    /// Nil only when the quota names a bucket this reading does not carry: the
    /// provider has stopped metering that pool. It is nil rather than falling back
    /// to the primary bucket's period because another pool's window is not this
    /// quota's, and handing one back would let a five-hour limit be paced against
    /// a week — or, with a five-hour pool gone, a week-long plan resumed as though
    /// nothing had changed.
    public func period(forBucket id: String?) -> QuotaPeriod? {
        bucket(id: id)?.period
    }

    /// The share of the allowance not yet used.
    ///
    /// Clamped defensively, even though `UsageBucket` already rejects
    /// out-of-range values: a value of exactly 100 yields 0, and a rounding
    /// artefact must not produce a negative allowance.
    public var remainingPercentage: Double {
        let remaining = UsageConstants.percentageScale - (primaryBucket?.usagePercentage ?? 0)
        return min(max(remaining, UsageConstants.minimumPercentage), UsageConstants.maximumPercentage)
    }

    /// Decoding validates, so a corrupted store or a misbehaving provider is
    /// reported rather than loaded.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            buckets: container.decode([UsageBucket].self, forKey: .buckets)
        )
    }
}
