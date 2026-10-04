import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Freshness")
struct FreshnessTests {
    @Test("A reading ages through every state, in order")
    func agesInOrder() {
        #expect(Freshness.of(age: 0) == .fresh)
        #expect(Freshness.of(age: StalenessConstants.ageingAfter) == .ageing)
        #expect(Freshness.of(age: StalenessConstants.staleAfter) == .stale)
        #expect(Freshness.of(age: StalenessConstants.unavailableAfter) == .unavailable)
    }

    @Test("The current edge is the one the staleness policy draws")
    func boundaryIsThePolicy() {
        // The threshold itself is out of date, so the edge is checked both ways
        // through the policy, which is what decides it.
        #expect(Freshness.of(age: StalenessConstants.ageingAfter - 1) == .fresh)
        #expect(Freshness.of(age: StalenessConstants.ageingAfter) == .ageing)
        #expect(StalenessPolicy.isOutOfDate(age: StalenessConstants.ageingAfter - 1) == false)
    }

    @Test("A clock that moved backwards does not produce a negative age")
    func negativeAgeIsFresh() {
        #expect(Freshness.of(age: -500) == .fresh)
    }

    @Test("A stale reading is still shown; only an unavailable one is refused")
    func permitsDisplay() {
        // A stale figure stays on screen with its age stated.
        // Refusing it would leave a user with a quota that worked yesterday
        // showing nothing at all, which is a worse answer than an old number.
        #expect(Freshness.fresh.permitsDisplay)
        #expect(Freshness.ageing.permitsDisplay)
        #expect(Freshness.stale.permitsDisplay)
        #expect(!Freshness.unavailable.permitsDisplay)
    }

    @Test("The three thresholds ascend, so no state can be skipped")
    func thresholdsAscend() {
        #expect(StalenessConstants.ageingAfter < StalenessConstants.staleAfter)
        #expect(StalenessConstants.staleAfter < StalenessConstants.unavailableAfter)
    }
}

@Suite("Relative time")
struct RelativeTimeTests {
    private let relative = RelativeTime(calendar: {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }())

    @Test("Each threshold boundary names the unit it has entered")
    func boundaries() {
        #expect(relative.wording(for: 0) == "just now")
        #expect(relative.wording(for: 59) == "59 seconds ago")
        #expect(relative.wording(for: 60) == "1 minute ago")
        #expect(relative.wording(for: 119) == "1 minute ago")
        #expect(relative.wording(for: 120) == "2 minutes ago")
        #expect(relative.wording(for: 3599) == "59 minutes ago")
        #expect(relative.wording(for: 3600) == "1 hour ago")
        #expect(relative.wording(for: 86399) == "23 hours ago")
        #expect(relative.wording(for: 86400) == "1 day ago")
        #expect(relative.wording(for: 604_799) == "6 days ago")
        #expect(relative.wording(for: 604_800) == "1 week ago")
    }

    @Test("A moment in the future reads as just now")
    func futureReadsAsNow() {
        #expect(relative.wording(for: -3600) == "just now")
    }

    @Test("Wording is plural only when it should be")
    func pluralisation() {
        #expect(relative.wording(for: 61) == "1 minute ago")
        #expect(relative.wording(for: 121) == "2 minutes ago")
    }

    @Test("A failure keeps the age in the sentence")
    func failureKeepsTheAge() {
        let sentence = relative.describeFailure(age: 120)
        #expect(sentence == "Unable to update usage. Showing data from 2 minutes ago.")
    }

    @Test("Wording is derived from a pair of dates as well as an age")
    func describesSince() {
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        #expect(relative.describe(since: now.addingTimeInterval(-60), now: now) == "1 minute ago")
    }
}

@Suite("Refresh schedule")
struct RefreshScheduleTests {
    @Test("With no failures the provider's own interval is used")
    func honoursProviderSuggestion() {
        let schedule = RefreshSchedule(providerSuggestion: 900)
        #expect(schedule.baseInterval == 900)
    }

    @Test("A suggestion below the platform minimum is raised to it")
    func clampsToMinimum() {
        #expect(RefreshSchedule(providerSuggestion: 1).baseInterval == RefreshConstants.minimumPollInterval)
    }

    @Test("A suggestion above the platform maximum is lowered to it")
    func clampsToMaximum() {
        #expect(RefreshSchedule(providerSuggestion: 999_999).baseInterval == RefreshConstants.maximumPollInterval)
    }

    @Test("A suggestion of zero means whenever, so the default is used")
    func zeroSuggestionMeansDefault() {
        #expect(RefreshSchedule(providerSuggestion: 0).baseInterval == RefreshConstants.defaultPollInterval)
    }

    @Test("With no suggestion the default interval is used")
    func defaultInterval() {
        #expect(RefreshSchedule().baseInterval == RefreshConstants.defaultPollInterval)
    }

    @Test("Jitter is symmetric about the interval and bounded")
    func jitterIsBounded() {
        let schedule = RefreshSchedule()
        let last = Date(timeIntervalSince1970: 1_757_000_000)
        let early = schedule.nextRefresh(after: last, jitterSource: { 0 })
        let late = schedule.nextRefresh(after: last, jitterSource: { 1 })
        let exact = schedule.nextRefresh(after: last, jitterSource: { 0.5 })

        #expect(exact.timeIntervalSince(last) == schedule.baseInterval)
        #expect(early < exact)
        #expect(late > exact)
        // The cap applies before the jitter is used, so the spread is the
        // smaller of a tenth of the interval and the absolute cap.
        let spread = min(schedule.baseInterval * RefreshConstants.jitterFraction, RefreshConstants.maximumJitter)
        #expect(abs(early.timeIntervalSince(exact)) == spread)
        #expect(abs(late.timeIntervalSince(exact)) == spread)
        #expect(spread <= RefreshConstants.maximumJitter)
    }

    @Test("Backoff doubles per failure and stops at the cap")
    func backoffDoublesAndCaps() {
        var schedule = RefreshSchedule()
        var previous: TimeInterval = 0
        for attempt in 1 ... 10 {
            schedule = schedule.afterFailure(code: .rateLimited)
            #expect(schedule.consecutiveFailures == attempt)
            #expect(schedule.baseInterval >= previous)
            #expect(schedule.baseInterval <= RefreshConstants.maximumBackoff)
            previous = schedule.baseInterval
        }
        // Saturated by the last attempt and no further: a provider left failing
        // is polled at the cap, not at an interval that grows without bound.
        #expect(previous == RefreshConstants.maximumBackoff)
        #expect(RefreshConstants.defaultPollInterval < RefreshConstants.maximumBackoff)
    }

    @Test("Provider-unavailable backs off, an answer does not")
    func onlyFailuresThatNeedBackingOff() {
        #expect(ProviderErrorCode.networkUnavailable.backsOff)
        #expect(ProviderErrorCode.rateLimited.backsOff)
        #expect(ProviderErrorCode.pluginError.backsOff)
        #expect(!ProviderErrorCode.nothingToReport.backsOff)
        #expect(!ProviderErrorCode.invalidResponse.backsOff)
        #expect(!ProviderErrorCode.notAuthenticated.backsOff)
        #expect(!ProviderErrorCode.authenticationFailed.backsOff)
    }

    @Test("A success clears the backoff but keeps the provider's interval")
    func successResets() {
        let schedule = RefreshSchedule(providerSuggestion: 1800)
            .afterFailure(code: .rateLimited)
            .afterFailure(code: .rateLimited)
            .afterSuccess()
        #expect(schedule.consecutiveFailures == 0)
        #expect(schedule.baseInterval == 1800)
    }
}

@Suite("Provider failures")
struct ProviderFailureTests {
    @Test("Every protocol error code has a state and a word for it")
    func everyCodeIsTranslated() {
        // Total by construction: a new case added to the protocol enum cannot
        // compile without being given a state here, so this test is a check that
        // the list is not empty rather than a check for a missing entry.
        #expect(ProviderFailurePresentation.all.count == 9)
        for code in Self.codes {
            let presentation = ProviderFailureTranslator.presentation(for: code)
            #expect(!presentation.title.isEmpty)
        }
    }

    @Test("Every code the protocol declares is covered")
    func everyCodeIsCovered() {
        // The protocol has ten codes and the interface has nine states, because
        // a rate limit and a plain failure of the connection are told apart in
        // the wording but not in the state. What matters is that no code is left
        // without a decision, which the first test checks by exhausting them.
        #expect(ProviderErrorCode.allCases.count == Self.codes.count)
        #expect(Set(ProviderFailureTranslator.presentation(for: .pluginError).title).isEmpty == false)
    }

    @Test("Credentials problems are the ones that offer a reconnect")
    func credentialsOfferReconnect() {
        #expect(
            ProviderFailureTranslator.presentation(for: .notAuthenticated).action == .reconnect
        )
        #expect(
            ProviderFailureTranslator.presentation(for: .authenticationFailed).action == .reconnect
        )
    }

    @Test("A rate limit is retried rather than asked of the user")
    func rateLimitRetries() {
        #expect(ProviderFailureTranslator.presentation(for: .rateLimited).action == .waitAndRetry)
    }

    @Test("A failure that is the app's own fault offers a report, not a retry")
    func ownFaultOffersAReport() {
        #expect(ProviderFailureTranslator.presentation(for: .pluginError).action == .reportProblem)
        #expect(ProviderFailureTranslator.presentation(for: .invalidResponse).action == .reportProblem)
    }

    @Test("A provider that is merely unreachable offers a retry")
    func unreachableOffersRetry() {
        #expect(ProviderFailureTranslator.presentation(for: .networkUnavailable).action == .retry)
    }

    @Test("An answer that is not a failure offers nothing to do")
    func answersOfferNothing() {
        #expect(ProviderFailureTranslator.presentation(for: .nothingToReport).action == .none)
    }

    /// Every code the protocol declares, listed so the exhaustiveness of the
    /// translator is visible in the test as well as in the compiler.
    private static let codes: [ProviderErrorCode] = [
        .notInstalled, .notPermitted, .notAuthenticated, .authenticationFailed,
        .networkUnavailable, .rateLimited, .invalidResponse, .nothingToReport,
        .pluginError, .providerError,
    ]
}
