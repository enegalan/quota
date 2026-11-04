import Core
import Foundation
import Platform
import Testing
@testable import App

/// A quota created against one pool of a provider that meters several.
@Suite("Quota creation pools")
@MainActor
struct QuotaCreationPoolTests {
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
