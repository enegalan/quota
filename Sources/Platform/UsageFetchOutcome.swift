import Core
import Foundation
import PluginKit

/// What a usage fetch returns to the coordinator.
///
/// Separates the reading from the provider's preferred poll interval so a
/// successful refresh can both file a snapshot and remember how long to wait
/// without stuffing scheduling into `UsageSnapshot`.
public struct UsageFetchOutcome: Sendable, Equatable {
    public let result: SyncResult
    public let suggestedRefreshInterval: TimeInterval?

    public init(result: SyncResult, suggestedRefreshInterval: TimeInterval? = nil) {
        self.result = result
        self.suggestedRefreshInterval = suggestedRefreshInterval
    }

    /// A reading, plus whatever interval came with it.
    ///
    /// The interval rides along with the result rather than being passed separately,
    /// so it is recorded from the read that produced it. Splitting them would allow
    /// a schedule to be updated on the strength of a reading that was then
    /// rejected, or a suggestion to be dropped because the code that received it
    /// had somewhere else to put it.
    public static func success(
        _ snapshot: UsageSnapshot,
        suggestedRefreshInterval: TimeInterval? = nil
    ) -> UsageFetchOutcome {
        UsageFetchOutcome(
            result: .success(snapshot),
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }

    /// A failed read, which may still carry an interval.
    ///
    /// Built through the same initialiser as `success` so a caller passes the
    /// interval on whenever it has one and gets nil when it does not. A failure
    /// with a shape of its own would ask the caller to remember which side of the
    /// result it was on before it could decide whether to record the schedule.
    public static func failure(
        _ failure: SyncFailure,
        suggestedRefreshInterval: TimeInterval? = nil
    ) -> UsageFetchOutcome {
        UsageFetchOutcome(
            result: .failure(failure),
            suggestedRefreshInterval: suggestedRefreshInterval
        )
    }
}
