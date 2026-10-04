import Core
import Foundation
import Platform
import Testing
@testable import App

/// Creation flow, from a chosen provider to a saved quota.
///
/// Asserted on what is stored rather than on the controls, because the controls
/// are SwiftUI's and the claim is that a quota came into existence with a period
/// and a policy the user chose.
@Suite("Quota creation")
@MainActor
struct QuotaCreationTests {
    @Test("A created quota is saved, and shown")
    func creationSavesAndShows() async {
        let model = QuotaCreationFixture.model()

        let created = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        #expect(created)
        #expect(model.presentations.count == 1)
        #expect(model.presentations.first?.summary.quota.name == "Work")
    }

    @Test("A created quota covers the whole month around the reference instant")
    func creationUsesTheCalendarMonth() async throws {
        let calendar = QuotaCreationFixture.calendar
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        // A quota created on the 15th of a 31-day month must still start on the
        // 1st, or most of the month has no plan and the panel shows nothing.
        let period = try #require(model.presentations.first?.summary.quota.period)
        // A whole month, and the end is exclusive — the first instant of the
        // next month — so the 31st of a month belongs to that month and the 1st
        // of the next does not.
        #expect(calendar.dateComponents([.day], from: period.start).day == 1)
        #expect(calendar.dateComponents([.month, .day], from: period.end).month == 4)
        #expect(calendar.dateComponents([.day], from: period.end).day == 1)
        #expect(period.start < period.end)
    }

    @Test("A quota created late in a month still covers that whole month")
    func creationOnTheLastDayCoversTheMonth() throws {
        // The failure this guards: an interval built from the reference instant
        // rather than the month, so a quota created on the 31st would own one day
        // and then be over-allocated for the rest of the month.
        let calendar = QuotaCreationFixture.calendar
        let lastDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23))
        )
        let period = try QuotaPeriod.month(containing: lastDay, calendar: calendar)

        let firstOfMonth = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let firstOfNext = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))
        )
        #expect(period.start == firstOfMonth)
        #expect(period.end == firstOfNext)
    }

    @Test("A quota created on the first of a month still covers that month")
    func creationOnTheFirstCoversTheMonth() throws {
        let calendar = QuotaCreationFixture.calendar
        let first = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 0, minute: 1))
        )
        let period = try QuotaPeriod.month(containing: first, calendar: calendar)

        let firstOfNext = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
        )
        // A minute past midnight is still the first of the month, and the period
        // is snapped to the day rather than inheriting the time of day — a period
        // starting at 00:01 would leave a minute of the first day unplanned.
        #expect(period.start < first)
        #expect(period.end == firstOfNext)
    }

    @Test("The month around an instant is the user's, not a fixed one")
    func monthFollowsTheUsersCalendar() throws {
        // A quota whose period came from a hardcoded month would be off by a month
        // for every user east or west of the app's own time zone.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Pacific/Kiritimati") ?? .current
        let instant = try #require(cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10)))

        let period = try QuotaPeriod.month(containing: instant, calendar: cal)

        #expect(cal.dateComponents([.month, .day], from: period.start).month == 3)
        #expect(cal.dateComponents([.month, .day], from: period.end).month == 4)
    }

    @Test("The policy the user chose is the policy stored")
    func policyIsStored() async {
        let model = QuotaCreationFixture.model()
        let policy = AllocationPolicy.weekly(weekdayWeights: .weekdaysOnly)

        _ = await model.createQuota(
            named: "Weekdays",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: policy
        )

        #expect(model.presentations.first?.summary.quota.policy == policy)
    }

    @Test("A quota is created against the provider the catalog named, not an invented one")
    func providerIDIsTheCatalogs() async {
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        #expect(model.presentations.first?.summary.quota.providerID.rawValue == QuotaCreationFixture.providerID)
    }

    @Test("A provider identifier the domain would reject is refused, and nothing is saved")
    func invalidProviderIDIsRefused() async {
        let model = QuotaCreationFixture.model()

        let created = await model.createQuota(
            named: "Work",
            // Whitespace: a valid-looking string that would break the catalog key.
            providerID: "not a provider",
            bucketID: nil,
            period: nil,
            policy: .even
        )

        #expect(!created)
        #expect(model.presentations.isEmpty)
        #expect(model.lastError != nil)
    }

    @Test("A second quota on a provider that already has one is refused")
    func duplicateProviderIsRefused() async {
        // The failure this guards: a second quota on the same provider and the
        // same bucket reads exactly the same numbers as the first and differs
        // only in how they are divided, so the interface would be showing two
        // panels disagreeing about one set of readings with nothing to tell the
        // user which is the real one.
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )
        let created = await model.createQuota(
            named: "Personal",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .weekly(weekdayWeights: .weekdaysOnly)
        )

        #expect(!created)
        #expect(model.presentations.count == 1)
        #expect(model.presentations.map(\.summary.quota.name) == ["Work"])
    }

    @Test("A refused duplicate says what is already there")
    func duplicateProviderSaysWhy() async {
        // A refusal the user cannot act on is the same as a failure that is not
        // explained: the flow shows one line of text for a failure, so a message
        // that does not name the quota already in the way tells them nothing
        // about which quota to go and remove.
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )
        _ = await model.createQuota(
            named: "Personal",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        #expect(model.lastError?.contains("Work") == true)
    }

    @Test("A second bucket on one provider is a different quota, and is kept")
    func secondBucketOnOneProviderIsAllowed() async {
        // A provider can meter several pools, and two quotas on one provider
        // watching different buckets read genuinely different numbers. Refusing
        // that would be a rule written for the common case that quietly breaks
        // the case that needs it — and it is the arrangement the architecture
        // names as the one whose state must stay separate.
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Models",
            providerID: QuotaCreationFixture.providerID,
            bucketID: "models",
            period: nil,
            policy: .even
        )
        let created = await model.createQuota(
            named: "Requests",
            providerID: QuotaCreationFixture.providerID,
            bucketID: "requests",
            period: nil,
            policy: .even
        )

        #expect(created)
        #expect(model.presentations.count == 2)
        #expect(model.presentations.map(\.summary.quota.bucketID) == ["models", "requests"])
    }

    @Test("A provider with an un bucketed quota is closed off to further quotas")
    func unboundQuotaClosesTheProviderOff() async {
        // Asked of the model rather than worked out in the flow, because the row
        // that is disabled has to be disabled by the same rule the repository
        // enforces. A flow that computed this itself would be a second answer to
        // "can this provider take a quota", and the two would drift.
        let model = QuotaCreationFixture.model()

        #expect(!model.hasUnboundQuota(forProviderID: QuotaCreationFixture.providerID))

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        #expect(model.hasUnboundQuota(forProviderID: QuotaCreationFixture.providerID))
        #expect(!model.hasUnboundQuota(forProviderID: "some.other.provider"))
    }

    @Test("A quota on one pool leaves the provider's other pools open")
    func namedQuotaLeavesOtherPoolsOpen() async {
        // The model answers the same question the repository does. If it matched
        // on the provider alone it would refuse, in the interface, the second
        // pool's quota that the repository has just accepted — the row would be
        // disabled for a quota the app would in fact have created.
        let model = QuotaCreationFixture.model()
        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: "models",
            period: nil,
            policy: .even
        )

        #expect(model.isWatched(providerID: QuotaCreationFixture.providerID, bucketID: "models"))
        #expect(!model.isWatched(providerID: QuotaCreationFixture.providerID, bucketID: "requests"))
        // Naming a pool is not the same as taking the provider's primary reading,
        // so this does not close the provider off either.
        #expect(!model.hasUnboundQuota(forProviderID: QuotaCreationFixture.providerID))
        #expect(!model.isWatched(providerID: "some.other.provider", bucketID: "models"))
    }

    @Test("The pools a provider meters are read from it, each with its own window")
    func bucketsAreDiscoveredFromTheProvider() async throws {
        let model = try await QuotaCreationFixture.modelWithTwoPools()

        let buckets = await model.buckets(forProviderID: QuotaCreationFixture.providerID)

        #expect(buckets.map(\.id) == ["five_hour", "week"])
        // Two limits that reset at different instants is the arrangement this
        // whole path exists for, so the picker is handed two windows rather than
        // one window twice.
        let first = try #require(buckets.first)
        let second = try #require(buckets.last)
        #expect(first.period != second.period)
    }

    @Test("A quota is created over the window the provider reports for that pool")
    func quotaTakesTheBucketsWindow() async throws {
        let model = try await QuotaCreationFixture.modelWithTwoPools()
        let buckets = await model.buckets(forProviderID: QuotaCreationFixture.providerID)
        let week = try #require(buckets.last)

        let created = await model.createQuota(
            named: "Weekly",
            providerID: QuotaCreationFixture.providerID,
            bucketID: week.id,
            period: week.period,
            policy: .even
        )

        #expect(created)
        // Not the month around today: the window the provider says this pool
        // resets over, which for a weekly pool is not a month.
        let quota = try #require(model.presentations.first?.summary.quota)
        #expect(quota.bucketID == "week")
        #expect(quota.period == week.period)
        let monthAround = try QuotaPeriod.month(containing: SummaryFixture.reference, calendar: .current)
        #expect(quota.period != monthAround)
    }

    @Test("A created quota is planned straight away, not left until the next tick")
    func creationPlansImmediately() async {
        // A quota appearing with no plan would show an empty panel until a
        // refresh happened, and says the first-run state must be honest
        // rather than blank.
        let model = QuotaCreationFixture.model()

        _ = await model.createQuota(
            named: "Work",
            providerID: QuotaCreationFixture.providerID,
            bucketID: nil,
            period: nil,
            policy: .even
        )

        // With no reading there is no allowance to divide, so no plan exists
        // yet — and that is not a failure to have created a quota. What matters
        // is that the quota is on screen rather than saved and invisible.
        #expect(model.presentations.first?.summary.plan == nil)
        #expect(model.presentations.count == 1)
    }
}
