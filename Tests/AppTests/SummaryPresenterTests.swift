import Core
import Foundation
import Platform
import Testing
@testable import App

/// Summary presentation, tested through the presenter that assembles them.
///
/// The cases are the ones where showing a number that is not true would be worse
/// than showing none: a quota whose provider has never answered, a day whose
/// usage cannot be established, a quota whose bucket the provider named itself,
/// and a plan that ran out of eligible days.
@Suite("Summary presentation")
struct SummaryPresenterTests {
    // MARK: - A quota the app can fully describe

    @Test("A quota with a reading, a plan, and a connected provider fills in")
    func fullyPopulated() async throws {
        let fixture = try await SummaryFixture.make()
        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        let summary = presentation.summary

        #expect(summary.snapshot != nil)
        #expect(summary.plan != nil)
        #expect(summary.pacing != nil)
        #expect(presentation.accountLabel == SummaryFixture.account)
        #expect(presentation.bucketID == SummaryFixture.bucketID)
    }

    @Test("A quota whose provider has never answered is shown, not omitted")
    func neverAnswered() async throws {
        var world = SummaryFixture.World()
        world.connected = false
        world.withReading = false
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)

        // A quota the user added must not vanish from the interface.
        #expect(presentation.summary.quota.id == fixture.quota.id)
        #expect(presentation.summary.snapshot == nil)
        #expect(presentation.accountLabel == nil)
        #expect(presentation.bucketID == nil)
    }

    @Test("Every quota appears in the list, including one with nothing behind it")
    func listsEveryQuota() async throws {
        var world = SummaryFixture.World()
        world.withPlan = false
        world.withTimeline = false
        let fixture = try await SummaryFixture.make(world)

        let presentations = try await fixture.presenter.presentations()
        #expect(presentations.count == 1)
        #expect(presentations.first?.summary.quota.id == fixture.quota.id)
    }

    // MARK: - The bucket the provider named

    @Test("A quota that names no bucket is read through the bucket the provider reported")
    func unnamedBucketResolvesThroughTheRecord() async throws {
        // The bucket is called something the app never chose. Reading it under a
        // name of the app's own invention would find nothing and render the
        // quota as though it had no history.
        var world = SummaryFixture.World()
        world.namedBucket = false
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)

        #expect(presentation.bucketID == SummaryFixture.bucketID)
        #expect(presentation.summary.snapshot != nil)
    }

    @Test("A quota that names its bucket is read by that name")
    func namedBucket() async throws {
        let fixture = try await SummaryFixture.make()
        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        #expect(presentation.summary.snapshot != nil)
        #expect(presentation.bucketID == SummaryFixture.bucketID)
    }

    // MARK: - a limit the provider stops reporting

    @Test("A limit the provider stops reporting is named by what it was called")
    func goneBucketIsNamed() async throws {
        // The interface has to say which limit has gone. With several limits on
        // one provider, "this quota has no reading" does not, and the identifier
        // the provider uses is not a name the user recognises.
        var world = SummaryFixture.World()
        world.bucketGone = true
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)

        #expect(presentation.summary.unavailableBucketID == SummaryFixture.bucketID)
        #expect(presentation.unavailableBucketName == "Usage")
        // No figure at all rather than the zero an absent figure would print as.
        #expect(presentation.summary.usage == nil)
        #expect(presentation.summary.pacing == nil)
    }

    @Test("A quota reading the provider's primary is never waiting for a limit")
    func primaryBucketIsNeverMissing() async throws {
        // A quota naming no bucket reads the primary, and a non-empty reading
        // always carries its primary — so this state cannot arise, and a test that
        // says so is what keeps the primary's being absent from being treated as
        // a missing limit.
        var world = SummaryFixture.World()
        world.namedBucket = false
        world.bucketGone = true
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)

        #expect(presentation.summary.unavailableBucketID == nil)
        #expect(presentation.unavailableBucketName == nil)
    }

    @Test("A quota never read is waiting for a reading, not for a limit")
    func neverReadIsNotWaitingForALimit() async throws {
        var world = SummaryFixture.World()
        world.withReading = false
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)

        #expect(presentation.unavailableBucketName == nil)
    }

    // MARK: - today's allowance

    @Test("Today's allowance is the planned share, less what has been used")
    func todayAllowanceSubtractsUsage() async throws {
        var world = SummaryFixture.World()
        world.usedToday = 2
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        let allowance = try #require(presentation.summary.todayAllowance)
        let share = try SummaryFixture.todayShare(of: fixture.plan)
        let remaining = try #require(allowance.remainingAfterToday)

        #expect(abs(allowance.suggested - share) < SummaryFixture.tolerance)
        // The day's share, less the two points spent against it.
        #expect(abs(remaining - (share - 2)) < SummaryFixture.tolerance)
        #expect(allowance.usedToday == 2)
        #expect(abs((allowance.usedToday ?? 0) + remaining - allowance.suggested) < SummaryFixture.tolerance)
    }

    @Test("Today's remaining is unknown, not the whole allowance, when nothing was read")
    func todayRemainingUnknownWithoutATimeline() async throws {
        // A provider that has not reported today has spent an unknown
        // amount, and showing the whole share as available invites overspending.
        var world = SummaryFixture.World()
        world.withTimeline = false
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        let allowance = try #require(presentation.summary.todayAllowance)
        let share = try SummaryFixture.todayShare(of: fixture.plan)

        #expect(abs(allowance.suggested - share) < SummaryFixture.tolerance)
        #expect(allowance.remainingAfterToday == nil)
    }

    @Test("Overspending today leaves zero remaining, never a negative one")
    func todayRemainingFloorsAtZero() async throws {
        var world = SummaryFixture.World()
        world.usedToday = 90
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        let allowance = try #require(presentation.summary.todayAllowance)
        #expect(allowance.remainingAfterToday == 0)
    }

    @Test("A quota with no plan has no today's allowance")
    func noPlanNoAllowance() async throws {
        var world = SummaryFixture.World()
        world.withPlan = false
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        #expect(presentation.summary.todayAllowance == nil)
    }

    // MARK: - the future strip

    @Test("The future strip holds a week, starting today")
    func upcomingIsAWeek() async throws {
        let fixture = try await SummaryFixture.make()
        let upcoming = fixture.presenter.upcoming(from: fixture.plan)

        #expect(upcoming.count == SummaryPresenter.upcomingDayCount)
        #expect(upcoming.first?.date.day == 15)
        #expect(upcoming.last?.date.day == 21)
    }

    @Test("The future strip keeps days with no allocation")
    func upcomingKeepsZeros() async throws {
        // A run of unfunded days is the pattern, and skipping them
        // would show a week that all looks spendable. 15 March 2026 is a Sunday
        // and 21 March a Saturday, so a weekdays-only policy leaves both ends of
        // this window empty and Wednesday the 18th funded.
        var world = SummaryFixture.World()
        world.weekdaysOnly = true
        let fixture = try await SummaryFixture.make(world)

        let upcoming = fixture.presenter.upcoming(from: fixture.plan)

        // Seven days, of which the weekend ends carry nothing — and are still
        // there, which is the point: a strip of seven consecutive days with two
        // of them showing no share is a different claim from one where those two
        // days are simply missing.
        #expect(upcoming.count == SummaryPresenter.upcomingDayCount)
        #expect(upcoming.map(\.date.day) == [15, 16, 17, 18, 19, 20, 21])
        #expect(upcoming.first?.percentage == 0)
        #expect(upcoming.last?.percentage == 0)
        #expect(try #require(upcoming.first { $0.date.day == 18 }).percentage > 0)
    }

    // MARK: - no eligible days

    @Test("A period with no days left retains the allowance and keeps the quota")
    func noEligibleDays() async throws {
        // A plan with nothing to spend must still account for the whole
        // allowance, and the quota is re-planned for the next period rather than
        // discarded, so a user is never told their remaining quota vanished.
        var world = SummaryFixture.World()
        world.periodEndingYesterday = true
        let fixture = try await SummaryFixture.make(world)

        let presentation = try await fixture.presenter.presentation(for: fixture.quota)
        let plan = try #require(presentation.summary.plan)

        #expect(plan.validation == .noEligibleDays(retained: 100))
        #expect(plan.allocations.isEmpty)
        #expect(fixture.presenter.noEligibleDays(in: plan) == 100)

        // The quota stands, so the user can plan it again.
        #expect(presentation.summary.quota.id == fixture.quota.id)
    }

    @Test("A plan with days left is not reported as having retained anything")
    func eligibleDaysRetainNothing() async throws {
        let fixture = try await SummaryFixture.make()
        #expect(fixture.presenter.noEligibleDays(in: fixture.plan) == nil)
    }
}
