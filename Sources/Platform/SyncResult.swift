import Foundation
@testable import Core
@testable import PluginKit

/// The outcome of one attempt to read a provider.
///
/// A sum rather than a snapshot-or-nil, because the two failures have to stay
/// apart: "there is no reading" and "there is a reading but it is old and the
/// refresh failed" need different words, different colours and different
/// decisions about what to offer the user. Collapsing them into nil loses the
/// one that matters.
public enum SyncResult: Sendable, Equatable {
    case success(UsageSnapshot)
    case failure(SyncFailure)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .success(let snapshot): snapshot
        case .failure: nil
        }
    }

    public var failure: SyncFailure? {
        switch self {
        case .success: nil
        case .failure(let failure): failure
        }
    }

    public var succeeded: Bool {
        snapshot != nil
    }
}

/// A refresh, as a value, so the outcome of a whole pass can be reported.
public struct SyncOutcome: Sendable, Equatable, Identifiable {
    public let quotaID: UUID
    public let result: SyncResult
    /// Whether the provider reported a different period than the quota had, in
    /// which case the quota's period was corrected and its timeline reset.
    public let periodChanged: Bool

    public var id: UUID {
        quotaID
    }

    public init(quotaID: UUID, result: SyncResult, periodChanged: Bool = false) {
        self.quotaID = quotaID
        self.result = result
        self.periodChanged = periodChanged
    }
}
