import Foundation

/// The user's configuration for one metered resource: what it is, where it
/// comes from, and how its allowance is spread over the period.
///
/// A quota is what the user set up, not what a provider last reported. It holds
/// no usage figure and no reading timestamp, even though the stored schema has
/// fields for both, `currentUsagePercentage` and `usageUpdatedAt`, in the
/// rest.
///
/// That omission is deliberate, and it is the single most important
/// structural decision in this file. Three parts of the specification need
/// the two ideas kept apart: one keeps actual and planned usage as distinct
/// quantities, one lets the menu bar mark a past reading as explicitly stale,
/// and one makes stored data the single source of truth. A usage field on
/// `Quota` would have to be either copied from the latest snapshot, which is
/// a second copy that can disagree with the snapshot, or left behind, which
/// means the figure silently describes a different instant than the snapshot
/// it came from. Neither can satisfy all three, because a `Quota` cannot be
/// re-read to discover that its embedded number is out of date.
///
/// Actual usage therefore lives only in `UsageSnapshot`, and that separation is
/// preserved by the type system: the two values are composed at the UI layer into
/// a `QuotaSummary`, which is the only value the interface reads. Nothing can
/// consume a usage figure without also holding the snapshot it came from, and
/// with it the timestamp that makes staleness computable.
public struct Quota: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let providerID: ProviderID
    public let bucketID: String?
    public let period: QuotaPeriod
    public let policy: AllocationPolicy
    public let createdAt: Date
    public let updatedAt: Date

    /// - Throws: `QuotaDomainError.invalidIdentifier` when the bucket reference
    ///   is not a valid identifier. A quota may point at no bucket, in which case
    ///   the provider's primary bucket is used, but a blank one is a mistake.
    public init(
        id: UUID = UUID(),
        name: String,
        providerID: ProviderID,
        bucketID: String? = nil,
        period: QuotaPeriod,
        policy: AllocationPolicy,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        if let bucketID, (try? ProviderID(bucketID)) == nil {
            throw QuotaDomainError.invalidIdentifier(bucketID)
        }

        self.id = id
        self.name = name
        self.providerID = providerID
        self.bucketID = bucketID
        self.period = period
        self.policy = policy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The same quota with a corrected period, as the provider reported.
    ///
    /// Separate from the initializer so a period change reads as what it is —
    /// the provider moved the window, rather than a different quota having been
    /// created — and so the identifier, the policy and the creation date survive
    /// it without having to be passed along.
    public func withPeriod(_ period: QuotaPeriod, updatedAt: Date) -> Quota {
        Quota(
            copying: self,
            period: period,
            policy: policy,
            updatedAt: updatedAt
        )
    }

    /// The same quota, marked as having been read at `date`.
    public func withUpdatedAt(_ date: Date) -> Quota {
        Quota(copying: self, period: period, policy: policy, updatedAt: date)
    }

    /// The same quota with a different allocation policy.
    public func withPolicy(_ policy: AllocationPolicy, updatedAt: Date) -> Quota {
        Quota(copying: self, period: period, policy: policy, updatedAt: updatedAt)
    }

    /// A copy of a quota that is already valid, with fields replaced.
    ///
    /// Skips the initializer's checks because there is nothing to check: every
    /// field is either carried over from a quota that passed them or is a
    /// `QuotaPeriod`, which validates itself on construction. Going through the
    /// public initializer would mean force-unwrapping a throw that cannot
    /// happen, which reads as a place where something can.
    private init(
        copying source: Quota,
        period: QuotaPeriod,
        policy: AllocationPolicy,
        updatedAt: Date
    ) {
        id = source.id
        name = source.name
        providerID = source.providerID
        bucketID = source.bucketID
        self.period = period
        self.policy = policy
        createdAt = source.createdAt
        self.updatedAt = updatedAt
    }
}
