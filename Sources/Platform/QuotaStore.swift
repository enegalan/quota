import Core
import Foundation

/// The single persistence boundary.
///
/// One protocol for every record family, rather than one protocol per family,
/// because a caller that knows which store to reach for cannot enforce that it
/// used the right one; and because the atomicity guarantee belongs to the store
/// as a whole, not to whichever file a caller happened to touch.
public protocol QuotaStore: Sendable {
    /// Reads every configured quota.
    ///
    /// The rationale the other thirteen methods share: a family is either
    /// wholly there or wholly absent, and a load that cannot decode reports
    /// emptiness rather than throwing. A caller therefore never has to
    /// reconcile "this user has no quotas" with "this file would not decode"
    /// — only the store can act on the second, and it can only do so once,
    /// rather than on every launch.
    ///
    /// - Throws: only when the store cannot be reached at all.
    func loadQuotas() async throws -> [QuotaRecord]

    /// Replaces the stored quotas with `records`.
    ///
    /// Whole-family replacement rather than a merge, because the caller
    /// already holds the complete list: merging would leave behind records
    /// nobody knows about, and a quota the user deleted would come back on
    /// the next launch.
    func saveQuotas(_ records: [QuotaRecord]) async throws

    /// Reads the latest reading for every bucket of every account.
    ///
    /// The newest reading per bucket, not a history. History is what
    /// timelines hold, and a load that returned both would leave the caller
    /// choosing with no way to tell the reading it picked from the one that
    /// superseded it.
    func loadSnapshots() async throws -> [SnapshotRecord]

    /// Replaces the stored readings with `records`.
    ///
    /// Whole-family replacement so that a reading superseded by a newer one
    /// disappears rather than competing with it: last write wins only because
    /// the older record is no longer in the list.
    func saveSnapshots(_ records: [SnapshotRecord]) async throws

    /// Reads the recorded history for every bucket of every account.
    ///
    /// Empty for a bucket that has never been read. Absence is not zero
    /// usage, so a caller must draw no chart from an empty history rather
    /// than a flat line along the bottom — the two make different claims
    /// about what happened.
    func loadTimelines() async throws -> [TimelineRecord]

    /// Replaces the stored history with `records`.
    ///
    /// Written whole rather than appended to, so the store stays the only
    /// place that decides what history exists and an interrupted write cannot
    /// leave a timeline whose latest point was never finished.
    func saveTimelines(_ records: [TimelineRecord]) async throws

    /// Reads the plans last computed, one per quota and account.
    ///
    /// Candidates, not answers. Each record carries the period and total it
    /// was computed from precisely so the caller can check it against the
    /// quota as it now stands and drop the ones that no longer describe it,
    /// rather than pacing a quota against numbers chosen before the user
    /// changed them.
    func loadAllocationPlans() async throws -> [AllocationPlanRecord]

    /// Replaces the stored plans with `records`.
    ///
    /// A plan is only worth keeping while it still matches its quota, so this
    /// overwrites rather than merges: a stale plan is dropped instead of
    /// sitting beside the replacement that supersedes it.
    func saveAllocationPlans(_ records: [AllocationPlanRecord]) async throws

    /// Reads what the app knows about each provider without contacting it.
    ///
    /// Metadata only: which account is authenticated, when the last refresh
    /// landed, and how long the provider asked to be left alone. No
    /// credential is kept here, because a store whose files hold secrets
    /// cannot be backed up, synced, or handed to support without first
    /// becoming a risk.
    func loadProviders() async throws -> [ProviderRecord]

    /// Replaces the stored provider records with `records`.
    ///
    /// Holds the consecutive-failure count and the provider's own refresh
    /// interval, both of which have to outlive the process. A backoff that
    /// restarted at zero on every launch would be no backoff at all for an
    /// app that is opened and closed all day.
    func saveProviders(_ records: [ProviderRecord]) async throws

    /// Reads the user's settings.
    ///
    /// - Returns: nil when settings have never been written, which is an
    ///   ordinary first-launch state rather than a fault: there is nothing to
    ///   recover, because nothing was ever chosen.
    func loadPreferences() async throws -> Preferences?

    /// Replaces the user's settings with `preferences`.
    ///
    /// A whole-value write, since there is only ever one settings object.
    /// Merging field by field would make a setting impossible to clear —
    /// there would be no absent field left to merge into.
    func savePreferences(_ preferences: Preferences) async throws

    /// Reads the set of providers this machine has a record of installing.
    ///
    /// A fact about a directory, kept separately from the quotas configured
    /// against a provider, because a plugin can be installed and disabled and
    /// can be removed while the app is not running: the store is the only
    /// place that can tell those apart, and the only place that can say what
    /// the app last believed.
    func loadInstalledProviders() async throws -> [InstalledProvider]

    /// Replaces the recorded set of installed providers with `records`.
    ///
    /// Written on install and on removal, so that a plugin removed while the
    /// app was not running is still noticed the next time it launches.
    func saveInstalledProviders(_ records: [InstalledProvider]) async throws
}

/// The schema version stamped on every file this build writes.
///
/// A stored file carries the version it was written with so a future build can
/// tell "written by an older version" from "written by a newer one" and refuse
/// to guess, instead of decoding a record whose meaning has since changed.
public enum StoreSchema {
    public static let currentVersion = 2

    /// The envelope every file uses.
    ///
    /// A single wrapper rather than a bare array, so the version travels with
    /// the data and a decoder can dispatch on it before it tries to interpret
    /// anything inside.
    public struct Envelope<Payload: Codable & Sendable>: Codable, Sendable {
        public let version: Int
        public let payload: Payload

        public init(version: Int = StoreSchema.currentVersion, payload: Payload) {
            self.version = version
            self.payload = payload
        }
    }
}
