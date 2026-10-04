import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Snapshot normalisation")
struct SnapshotNormaliserTests {
    private let recordedAt = Date(timeIntervalSince1970: 1_757_000_000)

    private func usage(
        percentage: Double,
        start: String = "2026-09-01",
        end: String = "2026-10-01"
    ) -> ProviderUsage {
        ProviderUsage(
            externalID: "q1",
            displayName: "Quota",
            bucketID: "primary",
            bucketDisplayName: "Primary",
            usagePercentage: percentage,
            periodStart: start,
            periodEnd: end,
            updatedAt: "2026-09-26T10:00:00Z"
        )
    }

    @Test("A well-formed answer becomes a snapshot with the provider's period")
    func normalises() throws {
        let snapshot = try SnapshotNormaliser.snapshot(
            from: UsageResult(quotas: [usage(percentage: 42)]),
            recordedAt: recordedAt
        )
        #expect(snapshot.buckets.count == 1)
        #expect(snapshot.bucket(id: "primary")?.usagePercentage == 42)
        #expect(snapshot.updatedAt == recordedAt)
        #expect(snapshot.remainingPercentage == 58)
    }

    @Test("Every bucket of a multi-pool provider is kept")
    func keepsEveryBucket() throws {
        var second = usage(percentage: 10)
        second = ProviderUsage(
            externalID: "q2", displayName: "Other", bucketID: "secondary",
            bucketDisplayName: "Secondary", usagePercentage: 10,
            periodStart: "2026-09-01", periodEnd: "2026-10-01", updatedAt: "2026-09-26T10:00:00Z"
        )
        let snapshot = try SnapshotNormaliser.snapshot(
            from: UsageResult(quotas: [usage(percentage: 42), second]),
            recordedAt: recordedAt
        )
        #expect(snapshot.buckets.count == 2)
    }

    /// The bug this arrangement is easiest to get wrong: reading the window off
    /// the first limit in the answer and handing it to all of them, which turns a
    /// five-hour pool into a month-long one and a weekly pool into a five-hour one.
    /// The normaliser's own parsing — a full date in UTC — made per call, because
    /// a shared formatter is the data race the production code comments about.
    private static func fullDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }

    @Test("Each bucket keeps the window its own provider usage reported")
    func keepsEachWindows() throws {
        let weekly = ProviderUsage(
            externalID: "q2", displayName: "Weekly", bucketID: "week",
            bucketDisplayName: "Weekly", usagePercentage: 8,
            periodStart: "2026-09-21", periodEnd: "2026-09-28", updatedAt: "2026-09-26T10:00:00Z"
        )
        let fiveHourly = usage(percentage: 42, start: "2026-09-26", end: "2026-09-27")

        let snapshot = try SnapshotNormaliser.snapshot(
            from: UsageResult(quotas: [fiveHourly, weekly]),
            recordedAt: recordedAt
        )

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let fiveHour = try #require(snapshot.period(forBucket: "primary"))
        let week = try #require(snapshot.period(forBucket: "week"))
        // Each one is its own, not the answer's first: two days against eight.
        #expect(fiveHour.totalDays(calendar: utc) == 2)
        #expect(week.totalDays(calendar: utc) == 8)
        #expect(fiveHour != week)
        let firstInstant = try #require(Self.fullDate("2026-09-26"))
        let weekEnd = try #require(Self.fullDate("2026-09-28"))
        #expect(fiveHour.start == firstInstant)
        #expect(week.end == weekEnd)
    }

    @Test("A percentage outside the scale is refused rather than clamped")
    func refusesOutOfRange() {
        #expect(throws: NormalisationError.self) {
            try SnapshotNormaliser.snapshot(
                from: UsageResult(quotas: [usage(percentage: 140)]),
                recordedAt: recordedAt
            )
        }
        #expect(throws: NormalisationError.self) {
            try SnapshotNormaliser.snapshot(
                from: UsageResult(quotas: [usage(percentage: .nan)]),
                recordedAt: recordedAt
            )
        }
    }

    @Test("A period that cannot be read is refused rather than guessed")
    func refusesUnreadablePeriod() {
        #expect(throws: NormalisationError.self) {
            try SnapshotNormaliser.snapshot(
                from: UsageResult(quotas: [usage(percentage: 10, end: "next month")]),
                recordedAt: recordedAt
            )
        }
    }

    @Test("A period that runs backwards is refused")
    func refusesBackwardsPeriod() {
        #expect(throws: QuotaDomainError.self) {
            try SnapshotNormaliser.snapshot(
                from: UsageResult(quotas: [usage(percentage: 10, start: "2026-10-01", end: "2026-09-01")]),
                recordedAt: recordedAt
            )
        }
    }

    @Test("An answer with no quotas at all is refused")
    func refusesEmpty() {
        #expect(throws: NormalisationError.noBuckets) {
            try SnapshotNormaliser.snapshot(from: UsageResult(quotas: []), recordedAt: recordedAt)
        }
    }

    @Test("A normalising failure is reported as an invalid response")
    func failureCode() {
        #expect(NormalisationError.unreadablePeriod("q1").code == .invalidResponse)
        #expect(NormalisationError.usageOutOfRange("q1", 140).code == .invalidResponse)
    }
}

@Suite("Refresh triggers")
struct RefreshTriggerTests {
    @Test("A popover, a manual request and a restored connection always read")
    func userVisibleTriggersAlwaysRead() {
        let farFuture = Date(timeIntervalSince1970: 1_757_000_000 + 999_999)
        for trigger in [RefreshTrigger.popoverOpened, .manual, .connectivityRestored] {
            let decision = RefreshDecision.decide(
                trigger: trigger,
                lastAttempt: Date(timeIntervalSince1970: 1_757_000_000),
                nextDue: farFuture,
                inFlight: false,
                now: farFuture
            )
            #expect(decision.shouldRefresh, "\(trigger) should read")
        }
    }

    @Test("A timer waits for the schedule")
    func timerWaits() {
        let last = Date(timeIntervalSince1970: 1_757_000_000)
        let decision = RefreshDecision.decide(
            trigger: .scheduleElapsed,
            lastAttempt: last,
            nextDue: last.addingTimeInterval(600),
            inFlight: false,
            now: last.addingTimeInterval(599)
        )
        #expect(!decision.shouldRefresh)
        #expect(decision.deferral == .notDue(until: last.addingTimeInterval(600)))
    }

    @Test("A launch with nothing recorded is a first read")
    func launchWithNoHistory() {
        let decision = RefreshDecision.decide(
            trigger: .launch,
            lastAttempt: nil,
            nextDue: nil,
            inFlight: false,
            now: Date()
        )
        #expect(decision.shouldRefresh)
    }

    @Test("A read already under way is never started twice")
    func neverTwiceAtOnce() {
        let decision = RefreshDecision.decide(
            trigger: .manual,
            lastAttempt: nil,
            nextDue: nil,
            inFlight: true,
            now: Date()
        )
        #expect(!decision.shouldRefresh)
        #expect(decision.deferral == .alreadyInFlight)
    }

    @Test("Connectivity is only a restoration on the edge from not connected")
    func restorationIsAnEdge() {
        var tracker = ConnectivityTracker()
        #expect(tracker.observe(true).justRestored)
        #expect(!tracker.observe(true).justRestored)
        #expect(!tracker.observe(false).justRestored)
        #expect(tracker.observe(true).justRestored)
    }

    @Test("The first reading at launch counts as a restoration when connected")
    func launchCountsAsRestoration() {
        #expect(ConnectivityTracker.initial(true).justRestored)
        #expect(!ConnectivityTracker.initial(false).justRestored)
    }
}
