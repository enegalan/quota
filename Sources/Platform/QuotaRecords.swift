import Core
import Foundation

// MARK: - Record families

/// A configured quota, as stored.
public struct QuotaRecord: Codable, Sendable, Equatable {
    public let quota: Quota
    public init(quota: Quota) {
        self.quota = quota
    }
}

/// The latest reading for one bucket of one account.
///
/// Keyed by quota and bucket together, because a provider may meter several
/// pools and a single-file-per-family layout would otherwise have the last
/// bucket written overwrite the others.
public struct SnapshotRecord: Codable, Sendable, Equatable, Identifiable {
    public let quotaID: UUID
    public let bucketID: String
    public let accountLabel: String
    public let snapshot: UsageSnapshot

    public var id: String {
        "\(quotaID.uuidString)/\(bucketID)/\(accountLabel)"
    }

    public init(quotaID: UUID, bucketID: String, accountLabel: String, snapshot: UsageSnapshot) {
        self.quotaID = quotaID
        self.bucketID = bucketID
        self.accountLabel = accountLabel
        self.snapshot = snapshot
    }
}

/// The plan last computed for one quota, as stored.
///
/// Wrapping the plan rather than storing it bare is what keeps a stored plan
/// from outliving the quota it describes: the record carries the period and the
/// total it was computed from, so a plan whose numbers no longer match the quota
/// can be recognised and replaced instead of shown.
public struct AllocationPlanRecord: Codable, Sendable, Equatable, Identifiable {
    public let quotaID: UUID
    public let accountLabel: String
    public let plan: AllocationPlan

    public var id: String {
        "\(quotaID.uuidString)/\(accountLabel)"
    }

    /// Whether this plan still describes the quota as it is now.
    ///
    /// Compared on the inputs rather than the date, because a plan is a pure
    /// function of period, remaining, and policy: if all three still match, the
    /// plan is still correct, and regenerating it would only make the file's
    /// timestamp newer than the reading that justified it.
    public func matches(period: QuotaPeriod, totalRemaining: Double) -> Bool {
        plan.period == period && plan.totalRemaining == totalRemaining
    }

    public init(quotaID: UUID, accountLabel: String, plan: AllocationPlan) {
        self.quotaID = quotaID
        self.accountLabel = accountLabel
        self.plan = plan
    }
}

/// The recorded history for one bucket of one account.
public struct TimelineRecord: Codable, Sendable, Equatable, Identifiable {
    public let quotaID: UUID
    public let bucketID: String
    public let accountLabel: String
    public let timeline: UsageTimeline

    public var id: String {
        "\(quotaID.uuidString)/\(bucketID)/\(accountLabel)"
    }

    public init(quotaID: UUID, bucketID: String, accountLabel: String, timeline: UsageTimeline) {
        self.quotaID = quotaID
        self.bucketID = bucketID
        self.accountLabel = accountLabel
        self.timeline = timeline
    }
}

/// What the app knows about a provider without contacting it.
///
/// Holds no credential. A provider's authentication material lives in the
/// Keychain under the provider's identifier, and the only thing recorded here
/// is which account is authenticated, so a user switching accounts inside one
/// provider cannot be served the previous account's numbers.
public struct ProviderRecord: Codable, Sendable, Equatable, Identifiable {
    public let providerID: ProviderID
    public let displayName: String
    public let installedVersion: String
    public let authenticatedAccountLabel: String?
    public let lastSyncAt: Date?

    /// The last refresh that failed, kept beside the last one that worked.
    ///
    /// Optional and last, so a file written before this field existed decodes
    /// without it: a synthesised decoder treats a missing key for an optional
    /// property as nil, which means adding a field to a stored record does not
    /// strand the records already on disk.
    public let lastFailure: SyncFailure?

    /// How many refreshes in a row have failed in a way worth backing off from.
    ///
    /// Stored rather than counted in memory because a menu bar app is mostly not
    /// running: a count that resets whenever the process restarts backs off
    /// exactly once per launch, which for an app that is opened and closed all
    /// day is no backoff at all. Zero for a record written before this field
    /// existed, which is the right default — a provider that has not failed
    /// should be read at its own rate.
    public let consecutiveFailures: Int

    /// How long this provider asked not to be read again, in seconds.
    ///
    /// Taken from the plugin's own description of itself rather than assumed,
    /// because the provider is the only party that knows its own rate limit.
    /// Nil means it has not said, and the platform default stands.
    public let suggestedRefreshInterval: TimeInterval?

    public var id: ProviderID {
        providerID
    }

    public init(
        providerID: ProviderID,
        displayName: String,
        installedVersion: String,
        authenticatedAccountLabel: String? = nil,
        lastSyncAt: Date? = nil,
        lastFailure: SyncFailure? = nil,
        consecutiveFailures: Int = 0,
        suggestedRefreshInterval: TimeInterval? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.installedVersion = installedVersion
        self.authenticatedAccountLabel = authenticatedAccountLabel
        self.lastSyncAt = lastSyncAt
        self.lastFailure = lastFailure
        self.consecutiveFailures = consecutiveFailures
        self.suggestedRefreshInterval = suggestedRefreshInterval
    }

    /// The same record with a failure noted and the last success left alone.
    ///
    /// The counter only grows for failures worth backing off from, and a failure
    /// that does not count clears it. Both halves matter: a provider that says
    /// "not connected" and then says "not connected" again should not end up
    /// waiting an hour because the app counted an answer as a failure, and a
    /// provider that fails transportably after saying "not connected" should not
    /// have its backoff reset by the earlier answer.
    public func withFailure(_ failure: SyncFailure) -> ProviderRecord {
        copying(
            authenticatedAccountLabel: authenticatedAccountLabel,
            lastSyncAt: lastSyncAt,
            lastFailure: failure,
            consecutiveFailures: failure.code.backsOff ? consecutiveFailures + 1 : 0,
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }

    /// The same record with the account signed in and the last failure cleared.
    ///
    /// Signing in is not a successful read, so the last reading and how old it is
    /// are left exactly as they were — and the failure being repaired is cleared,
    /// because a record that still carries it goes on backing off a provider the
    /// user has just fixed.
    public func authenticated(against label: String) -> ProviderRecord {
        copying(
            authenticatedAccountLabel: label,
            lastSyncAt: lastSyncAt,
            lastFailure: nil,
            consecutiveFailures: 0,
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }

    /// The same record with the account signed out.
    ///
    /// The failure is deliberately kept: signing out is not a read that failed,
    /// and clearing the count would let a provider that has been failing be read
    /// again at full rate straight after the user disconnected it.
    public func signedOut() -> ProviderRecord {
        copying(
            authenticatedAccountLabel: nil,
            lastSyncAt: lastSyncAt,
            lastFailure: lastFailure,
            consecutiveFailures: consecutiveFailures,
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }

    /// The one place a modified record is written out.
    ///
    /// Every method above names what it changes and passes the rest through here,
    /// because a record is eight fields long and a copy that lists seven of them
    /// compiles, saves, and fails silently. Dropping `suggestedRefreshInterval`
    /// forgets the rate the provider asked for; dropping `consecutiveFailures`
    /// resets a backoff that was working.
    private func copying(
        authenticatedAccountLabel: String?,
        lastSyncAt: Date?,
        lastFailure: SyncFailure?,
        consecutiveFailures: Int,
        suggestedRefreshInterval: TimeInterval?
    ) -> ProviderRecord {
        ProviderRecord(
            providerID: providerID,
            displayName: displayName,
            installedVersion: installedVersion,
            authenticatedAccountLabel: authenticatedAccountLabel,
            lastSyncAt: lastSyncAt,
            lastFailure: lastFailure,
            consecutiveFailures: consecutiveFailures,
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(ProviderID.self, forKey: .providerID)
        displayName = try container.decode(String.self, forKey: .displayName)
        installedVersion = try container.decode(String.self, forKey: .installedVersion)
        authenticatedAccountLabel = try container.decodeIfPresent(
            String.self, forKey: .authenticatedAccountLabel
        )
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastFailure = try container.decodeIfPresent(SyncFailure.self, forKey: .lastFailure)
        // Unlike the fields above, a missing key here is not an error: a record
        // written by a build that predates backoff has no count, and every
        // one of those providers was working at the time it was written. The
        // synthesised decoder would throw and the whole file would be
        // quarantined, losing the last good reading to gain nothing.
        consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        suggestedRefreshInterval = try container.decodeIfPresent(
            TimeInterval.self, forKey: .suggestedRefreshInterval
        )
    }

    /// The same record with a success noted and the last failure left alone.
    public func withSuccessfulSync(at date: Date, accountLabel: String?) -> ProviderRecord {
        copying(
            authenticatedAccountLabel: accountLabel ?? authenticatedAccountLabel,
            lastSyncAt: date,
            lastFailure: nil,
            consecutiveFailures: 0,
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }
}
