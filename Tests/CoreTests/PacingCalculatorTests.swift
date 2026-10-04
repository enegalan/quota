import Foundation
import Testing
@testable import Core

@Suite("PacingCalculator")
struct PacingCalculatorTests {
    private var calculator: PacingCalculator {
        PacingCalculator(calendar: quotaCalendar)
    }

    private func makePlan(
        policy: AllocationPolicy = .even,
        remaining: Double = 100
    ) throws -> AllocationPlan {
        let period = try quotaPeriod(from: "2026-09-01", to: "2026-09-30")
        return try AllocationEngine(calendar: quotaCalendar).plan(
            quotaID: UUID(),
            policy: policy,
            period: period,
            totalRemaining: remaining,
            asOf: try quotaInstant(2026, 9, 1)
        )
    }

    private func makeQuota(bucketID: String? = nil) throws -> Quota {
        try Quota(
            name: "Cursor",
            providerID: try ProviderID("mock"),
            bucketID: bucketID,
            period: try quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            policy: .even,
            createdAt: try quotaInstant(2026, 9, 1),
            updatedAt: try quotaInstant(2026, 9, 1)
        )
    }

    private func makeSnapshot(_ models: Double, at updatedAt: Date) throws -> UsageSnapshot {
        let window = try quotaPeriod(from: "2026-09-01", to: "2026-09-30")
        return try UsageSnapshot(
            updatedAt: updatedAt,
            buckets: [
                try UsageBucket(
                    id: "models", displayName: "Models", usagePercentage: models, period: window
                ),
            ]
        )
    }

    @Test("A reading within tolerance of the plan is on track")
    func onTrack() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        // Day 10 of 30 has 9 days of 3.33 behind it, so about 30% is expected.
        let expected = calculator.expectedUsage(plan: plan, asOf: try quotaInstant(2026, 9, 10))
        let snapshot = try makeSnapshot(expected, at: try quotaInstant(2026, 9, 10))

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: try quotaInstant(2026, 9, 10)
        ))
        #expect(status.phase == .onTrack)
    }

    @Test("Spending more than the tolerance allows is reported as behind")
    func behind() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 9, 10)
        let expected = calculator.expectedUsage(plan: plan, asOf: now)
        let snapshot = try makeSnapshot(expected * 2, at: now)

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .behind)
        #expect(status.difference > 0)
    }

    @Test("Spending less than the tolerance allows is reported as ahead")
    func ahead() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 9, 10)
        let expected = calculator.expectedUsage(plan: plan, asOf: now)
        let snapshot = try makeSnapshot(expected / 2, at: now)

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .ahead)
        #expect(status.difference < 0)
    }

    @Test("A deviation inside the tolerance is not reported as behind")
    func toleranceAbsorbsSmallDeviation() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 9, 10)
        let expected = calculator.expectedUsage(plan: plan, asOf: now)
        let snapshot = try makeSnapshot(expected * 1.04, at: now)

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .onTrack)
    }

    @Test("A fully used allowance is exhausted, not merely behind")
    func exhausted() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 9, 10)
        let snapshot = try makeSnapshot(100, at: now)

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .exhausted)
    }

    @Test("A period that has ended reports expired rather than a failure")
    func expired() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 10, 5)
        let snapshot = try makeSnapshot(20, at: now)

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .expired)
    }

    @Test("No reading means no verdict, not a verdict of on track")
    func noReadingIsNoVerdict() throws {
        let plan = try makePlan()
        let quota = try makeQuota()
        let now = try quotaInstant(2026, 9, 10)
        #expect(calculator.status(quota: quota, snapshot: nil, plan: plan, asOf: now) == nil)
    }

    @Test("The verdict uses the bucket the quota names")
    func usesNamedBucket() throws {
        let plan = try makePlan()
        let quota = try makeQuota(bucketID: "other")
        let now = try quotaInstant(2026, 9, 10)
        let window = try quotaPeriod(from: "2026-09-01", to: "2026-09-30")
        let snapshot = try UsageSnapshot(
            updatedAt: now,
            buckets: [
                try UsageBucket(
                    id: "models", displayName: "Models", usagePercentage: 0, period: window
                ),
                try UsageBucket(
                    id: "other", displayName: "Other", usagePercentage: 100, period: window
                ),
            ]
        )

        let status = try #require(calculator.status(
            quota: quota, snapshot: snapshot, plan: plan, asOf: now
        ))
        #expect(status.phase == .exhausted)
        #expect(status.usagePercentage == 100)
    }

    @Test("Expected usage accumulates across the days that have begun")
    func expectedUsageAccumulates() throws {
        let plan = try makePlan()
        let day1 = calculator.expectedUsage(plan: plan, asOf: try quotaInstant(2026, 9, 1))
        let day10 = calculator.expectedUsage(plan: plan, asOf: try quotaInstant(2026, 9, 10))
        let day30 = calculator.expectedUsage(plan: plan, asOf: try quotaInstant(2026, 9, 30))
        #expect(day1 > 0)
        #expect(day10 > day1)
        #expect(day30 >= day10)
    }

    @Test("A period that has not started expects nothing")
    func futurePeriodExpectsNothing() throws {
        let plan = try makePlan()
        let before = try quotaInstant(2026, 8, 1)
        #expect(calculator.elapsedFraction(plan: plan, asOf: before) == nil)
    }

    @Test("The elapsed fraction runs from zero to one across a period")
    func elapsedFraction() throws {
        let plan = try makePlan()
        let start = try #require(calculator.elapsedFraction(
            plan: plan, asOf: try quotaInstant(2026, 9, 1)
        ))
        let end = try #require(calculator.elapsedFraction(
            plan: plan, asOf: try quotaInstant(2026, 9, 30)
        ))
        #expect(abs(start - 1.0 / 30.0) < 0.0001)
        #expect(abs(end - 1.0) < 0.0001)
    }

    /// The policy is what the user approved; asking whether they are on track
    /// must not be able to change it.
    @Test("Evaluating pacing never mutates the plan or the policy")
    func evaluationIsSideEffectFree() throws {
        let policy = AllocationPolicy.even
        let plan = try makePlan(policy: policy)
        let quota = try makeQuota()
        let before = plan
        _ = calculator.status(
            quota: quota,
            snapshot: try makeSnapshot(50, at: try quotaInstant(2026, 9, 15)),
            plan: plan,
            asOf: try quotaInstant(2026, 9, 15)
        )
        #expect(plan == before)
        #expect(quota.policy == policy)
    }
}
