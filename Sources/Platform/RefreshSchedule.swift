import Core
import Foundation
import PluginKit

/// Decides when each provider is next read.
///
/// A value rather than a timer, so the decision can be tested at a given instant
/// and a given failure count without waiting for anything, and so the same
/// arithmetic is used by the scheduler and by whatever is showing "next refresh".
public struct RefreshSchedule: Sendable, Equatable {
    /// What the provider said it would like, if anything.
    public let providerSuggestion: TimeInterval?

    /// How many refreshes in a row have failed.
    public let consecutiveFailures: Int

    public init(providerSuggestion: TimeInterval? = nil, consecutiveFailures: Int = 0) {
        self.providerSuggestion = providerSuggestion
        self.consecutiveFailures = max(0, consecutiveFailures)
    }

    /// The gap before the next read, before jitter.
    ///
    /// Three things decide it and the order matters. A rate limit and a
    /// transport failure both back off, because asking again sooner is the one
    /// thing guaranteed to keep failing. A provider's own suggestion is honoured
    /// because it knows its rate limit and the app does not. The platform's floor
    /// and ceiling are applied last, because they are the limits that hold no
    /// matter what anyone suggests — including a suggestion of zero, which is
    /// what a provider means by "whenever".
    public var baseInterval: TimeInterval {
        // The backoff already starts from the interval the provider would have
        // been read at, so taking the larger of the two here would only ever
        // discard the backoff when it is shorter — which it never is.
        max(unbackedInterval, backoffInterval)
    }

    /// The wait after this many consecutive failures.
    ///
    /// The interval that would otherwise have been used, multiplied, rather than
    /// a fixed delay compared against it. A fixed delay that loses to the normal
    /// interval would be invisible for the first several failures — a provider
    /// that has failed four times would still be polled every fifteen minutes,
    /// which is not backing off — and only start to matter once it happened to
    /// exceed the poll interval.
    public var backoffInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return 0 }
        let factor = pow(RefreshConstants.backoffFactor, Double(consecutiveFailures - 1))
        return min(unbackedInterval * factor, RefreshConstants.maximumBackoff)
    }

    /// The interval this provider would be read at if nothing had failed.
    private var unbackedInterval: TimeInterval {
        let suggested = providerSuggestion.flatMap { $0 > 0 ? $0 : nil }
        return min(
            max(suggested ?? RefreshConstants.defaultPollInterval, RefreshConstants.minimumPollInterval),
            RefreshConstants.maximumPollInterval
        )
    }

    /// When the next read is due, given when the last one happened.
    ///
    /// - Parameter jitterSource: a value in 0 ..< 1, standing in for a random
    ///   number. Injected so the nudge is testable: a real random source would
    ///   make every test of this either flaky or unable to assert the offset at
    ///   all.
    public func nextRefresh(
        after lastAttempt: Date,
        jitterSource: () -> Double = { Double.random(in: 0 ..< 1) }
    ) -> Date {
        let base = baseInterval
        let spread = min(base * RefreshConstants.jitterFraction, RefreshConstants.maximumJitter)
        // Centred on the interval and two spreads wide, so the jitter moves the
        // read either earlier or later by the same amount and never shortens
        // the interval to less than nothing.
        let offset = (jitterSource() - RefreshConstants.jitterMidpoint)
            * RefreshConstants.jitterSpan * spread
        return lastAttempt.addingTimeInterval(base + offset)
    }

    /// The same schedule with a known number of consecutive failures.
    ///
    /// For rebuilding a schedule from a stored count rather than from the run
    /// that just happened, which is the case after a relaunch: the count is real
    /// but the schedule that produced it is gone.
    public func withConsecutiveFailures(_ count: Int) -> RefreshSchedule {
        RefreshSchedule(providerSuggestion: providerSuggestion, consecutiveFailures: count)
    }

    /// The schedule after a read that worked.
    public func afterSuccess(providerSuggestion: TimeInterval? = nil) -> RefreshSchedule {
        // A nil argument keeps the suggestion this schedule already had. Passing
        // nil means "no new information", not "the provider stopped
        // suggesting", and a schedule that forgot its interval on the first
        // success would quietly start polling at the default.
        RefreshSchedule(
            providerSuggestion: providerSuggestion ?? self.providerSuggestion,
            consecutiveFailures: 0
        )
    }

    /// The schedule after a read that failed.
    ///
    /// Only some failures count. Being told the quota is unsupported, or that
    /// there is nothing to report, is an answer: backing off from it would only
    /// mean the app never learns the situation changed.
    public func afterFailure(code: ProviderErrorCode, providerSuggestion: TimeInterval? = nil) -> RefreshSchedule {
        // A nil argument keeps this schedule's suggestion, for the same reason
        // `afterSuccess` does: nil means no new information from the provider.
        let suggestion = providerSuggestion ?? self.providerSuggestion
        guard Self.backsOff(for: code) else { return afterSuccess(providerSuggestion: suggestion) }
        return RefreshSchedule(providerSuggestion: suggestion, consecutiveFailures: consecutiveFailures + 1)
    }

    /// Whether a failure means wait longer before trying again.
    public static func backsOff(for code: ProviderErrorCode) -> Bool {
        code.backsOff
    }
}
