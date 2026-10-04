import Foundation
import Testing
@testable import Core

/// Custom policies place the user in charge of the arithmetic, so these tests
/// concentrate on the cases where their numbers do not add up: the remainder
/// still has to reach the full allowance, and the interface has to be told
/// which way it fell short.
@Suite("AllocationEngine · custom policy")
struct CustomPolicyTests {
    private var engine: AllocationEngine {
        AllocationEngine(calendar: quotaCalendar)
    }

    private func makePlan(
        policy: AllocationPolicy,
        remaining: Double,
        onDay day: Int = 15,
        over period: QuotaPeriod? = nil
    ) throws -> AllocationPlan {
        try engine.plan(
            quotaID: UUID(),
            policy: policy,
            period: period ?? (try quotaPeriod(from: "2026-09-01", to: "2026-09-30")),
            totalRemaining: remaining,
            asOf: try quotaInstant(2026, 9, day)
        )
    }

    private func total(of plan: AllocationPlan) -> Double {
        plan.allocations.reduce(0) { $0 + $1.percentage }
    }

    /// Binary floating point cannot represent a hundredth exactly, so a sum of
    /// thirty of them lands a fraction away from the total.
    private let sumTolerance = 0.000_001

    private func expectTotal(_ plan: AllocationPlan, _ allowance: Double) {
        let difference = abs(total(of: plan) - allowance)
        #expect(difference <= sumTolerance, "off by \(difference)")
    }

    // MARK: Custom policy

    @Test("A custom policy uses the assigned percentages")
    func customPolicy() throws {
        let assignments = [
            try LocalDate(iso: "2026-09-15"): 60.0,
            try LocalDate(iso: "2026-09-16"): 40.0,
        ]
        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100
        )
        let first = try #require(plan.allocation(on: try LocalDate(iso: "2026-09-15")))
        let second = try #require(plan.allocation(on: try LocalDate(iso: "2026-09-16")))
        #expect(first.percentage == 60)
        #expect(second.percentage == 40)
        expectTotal(plan, 100)
    }

    @Test("A custom policy spreads the unassigned remainder over the days left")
    func customSpreadsRemainder() throws {
        let assignments = [try LocalDate(iso: "2026-09-15"): 50.0]
        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100
        )
        let assigned = try #require(plan.allocation(on: try LocalDate(iso: "2026-09-15")))
        #expect(assigned.percentage == 50)
        if case .underallocated(let unassigned) = plan.validation {
            #expect(unassigned == 50)
        } else {
            Issue.record("expected underallocated, got \(plan.validation)")
        }
        expectTotal(plan, 100)
    }

    @Test("A custom policy that assigns more than the allowance is trimmed and reported")
    func customOverallocatedIsTrimmed() throws {
        let assignments = [
            try LocalDate(iso: "2026-09-15"): 60.0,
            try LocalDate(iso: "2026-09-16"): 60.0,
        ]
        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100
        )
        if case .overallocated(let exceeding) = plan.validation {
            #expect(exceeding == 20)
        } else {
            Issue.record("expected overallocated, got \(plan.validation)")
        }
        // A plan may never be worth more than the allowance.
        expectTotal(plan, 100)
    }

    @Test("A custom policy assigning every eligible day exactly is exact")
    func customExact() throws {
        var assignments: [LocalDate: Double] = [:]
        let days = engine.eligibleDays(
            in: try quotaPeriod(from: "2026-09-15", to: "2026-09-30"),
            asOf: try quotaInstant(2026, 9, 15)
        )
        let share = 100.0 / Double(days.count)
        for day in days {
            assignments[day] = share
        }

        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100
        )
        #expect(plan.validation == .exact)
        expectTotal(plan, 100)
    }

    @Test("A custom policy assigning no unassigned day still keeps the whole allowance")
    func customWithNoUnassignedDays() throws {
        let assignments = [try LocalDate(iso: "2026-09-15"): 50.0]
        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100,
            onDay: 15,
            over: try quotaPeriod(from: "2026-09-15", to: "2026-09-15")
        )
        if case .underallocated(let unassigned) = plan.validation {
            #expect(unassigned == 50)
        } else {
            Issue.record("expected underallocated, got \(plan.validation)")
        }
        expectTotal(plan, 100)
    }

    @Test("Custom assignments outside the period are ignored, not silently counted")
    func customIgnoresDatesOutsideThePeriod() throws {
        let assignments = [
            try LocalDate(iso: "2026-09-15"): 50.0,
            try LocalDate(iso: "2026-08-01"): 500.0,
        ]
        let plan = try makePlan(
            policy: try .customValidated(assignments: assignments),
            remaining: 100
        )
        // The 500 for a day outside the window must not inflate the plan.
        expectTotal(plan, 100)
        // Only the assignment inside the window counts towards coverage, so the
        // shortfall is still reported against the 50 the user really assigned.
        if case .underallocated(let unassigned) = plan.validation {
            #expect(unassigned == 50)
        } else {
            Issue.record("expected underallocated, got \(plan.validation)")
        }
    }

    @Test("A negative custom assignment is rejected")
    func customRejectsNegative() throws {
        #expect(throws: QuotaDomainError.self) {
            try AllocationPolicy.customValidated(
                assignments: [try LocalDate(iso: "2026-09-15"): -10]
            )
        }
    }

    // MARK: No eligible days

    @Test("A period with no days left retains the allowance rather than discarding it")
    func noEligibleDaysRetainsAllowance() throws {
        let period = try quotaPeriod(from: "2026-09-01", to: "2026-09-14")
        let plan = try makePlan(policy: .even, remaining: 42, onDay: 15, over: period)
        #expect(plan.allocations.isEmpty)
        if case .noEligibleDays(let retained) = plan.validation {
            #expect(retained == 42)
        } else {
            Issue.record("expected noEligibleDays, got \(plan.validation)")
        }
        #expect(plan.totalRemaining == 42)
    }

    @Test("An expired period yields no days rather than days in the past")
    func expiredPeriodYieldsNoDays() throws {
        let period = try quotaPeriod(from: "2026-09-01", to: "2026-09-14")
        let days = engine.eligibleDays(in: period, asOf: try quotaInstant(2026, 10, 1))
        #expect(days.isEmpty)
    }

    /// A period that has not started yet must not offer quota for the days
    /// before it begins, or the plan would tell a user to spend allowance that
    /// does not exist yet.
    @Test("A future period plans only its own days")
    func futurePeriodSkipsPreStartDays() throws {
        let period = try quotaPeriod(from: "2026-09-10", to: "2026-09-20")
        let days = engine.eligibleDays(in: period, asOf: try quotaInstant(2026, 9, 1))
        #expect(days.count == 11)
        #expect(days.first?.description == "2026-09-10")
        #expect(days.last?.description == "2026-09-20")
    }
}
