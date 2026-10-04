import Core
import Foundation
import PluginKit

/// How current a reading is, as four states rather than a number.
///
/// Four because the interface does the same four things in each case: show the
/// figure, show it with a caveat, show it flagged as old, or refuse to show it.
/// Any finer division would be a number the interface has to interpret, which is
/// the mistake that produces a reading marked fresh in one place and stale in
/// another.
public enum Freshness: String, Sendable, Codable, CaseIterable, Equatable {
    /// Younger than `StalenessConstants.ageingAfter`.
    case fresh

    /// Past `ageingAfter` but under `staleAfter`: still shown, worth mentioning.
    case ageing

    /// Past `staleAfter`: shown, but flagged.
    case stale

    /// Past `unavailableAfter`, or there is no reading at all.
    ///
    /// Separate from `stale` because a month-old figure and a missing one are
    /// different problems: one means the refresh has not worked for a long time,
    /// the other means it has never worked.
    case unavailable

    /// The reading's age against a reference moment.
    ///
    /// - Throws: `FreshnessError.noReading` when there is nothing to date, so a
    ///   caller cannot accidentally date a missing reading from "now" and call
    ///   it fresh.
    public static func of(snapshot: UsageSnapshot?, now: Date) throws -> Freshness {
        guard let snapshot else { throw FreshnessError.noReading }
        return of(age: StalenessPolicy.age(of: snapshot, now: now))
    }

    /// The state for an age, which is the part worth testing on its own.
    public static func of(age: TimeInterval) -> Freshness {
        // A reading from the future is treated as fresh rather than as an
        // error: a clock that moved backwards between two reads is a thing that
        // happens, and refusing to show a current figure over it is worse than
        // showing it.
        guard age >= 0 else { return .fresh }
        // `StalenessPolicy` draws the fresh line at `ageingAfter`, so asking the
        // policy rather than comparing a constant here is what keeps the two
        // answers from drifting apart.
        if !StalenessPolicy.isOutOfDate(age: age) {
            return .fresh
        }
        if age < StalenessConstants.staleAfter {
            return .ageing
        }
        if age < StalenessConstants.unavailableAfter {
            return .stale
        }
        return .unavailable
    }

    /// Whether a figure from this state may be shown as a number.
    public var permitsDisplay: Bool {
        self != .unavailable
    }
}

public enum FreshnessError: Error, Equatable {
    case noReading
}

/// What is known about one provider's ability to be read right now.
///
/// Separate from the reading itself, so that "we have a figure from an hour ago"
/// and "the last refresh failed" can both be true at once, which they usually
/// are, and neither has to overwrite the other to be recorded.
public struct ConnectionStatus: Sendable, Equatable, Codable, Identifiable {
    public let providerID: ProviderID

    /// What the account is called, as the provider names it.
    ///
    /// Optional because a provider can be read before it has ever connected, and
    /// an account label is a thing you learn by connecting.
    public var accountLabel: String?

    /// When a reading last arrived, or nil if none ever has.
    public var lastSuccessfulSync: Date?

    /// The last failure, kept next to the last success so the interface can say
    /// both: a reading is not "the truth", it is "the last thing that worked".
    public var lastError: SyncFailure?

    /// When the next poll is due, or nil when nothing is scheduled.
    public var nextScheduledRefresh: Date?

    public var id: ProviderID {
        providerID
    }

    public init(
        providerID: ProviderID,
        accountLabel: String? = nil,
        lastSuccessfulSync: Date? = nil,
        lastError: SyncFailure? = nil,
        nextScheduledRefresh: Date? = nil
    ) {
        self.providerID = providerID
        self.accountLabel = accountLabel
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastError = lastError
        self.nextScheduledRefresh = nextScheduledRefresh
    }

    /// The state of the last reading, for the interface to word.
    public func freshness(asOf now: Date) throws -> Freshness {
        guard let lastSuccessfulSync else { throw FreshnessError.noReading }
        let age = now.timeIntervalSince(lastSuccessfulSync)
        return Freshness.of(age: age)
    }

    /// A status with nothing recorded yet.
    public static func unknown(_ id: ProviderID) -> ConnectionStatus {
        ConnectionStatus(providerID: id)
    }
}

/// Why a refresh did not produce a reading.
///
/// The protocol's own error code is kept rather than collapsed into a string, so
/// that a later version which distinguishes two cases the protocol v1 lumps
/// together can be recognised without having thrown the detail away.
public struct SyncFailure: Sendable, Equatable, Codable, Identifiable {
    public let code: ProviderErrorCode
    public let message: String
    public let occurredAt: Date

    public var id: Date {
        occurredAt
    }

    public init(code: ProviderErrorCode, message: String, occurredAt: Date) {
        self.code = code
        self.message = message
        self.occurredAt = occurredAt
    }
}
