import Foundation
import Testing
@testable import Core

@Suite("AllocationEngine")
struct AllocationEngineTests {
    private var engine: AllocationEngine {
        AllocationEngine(calendar: quotaCalendar)
    }

    private func septemberPlan(
        policy: AllocationPolicy,
        remaining: Double,
        onDay day: Int = 15
    ) throws -> AllocationPlan {
        try engine.plan(
            quotaID: UUID(),
            policy: policy,
            period: try quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            totalRemaining: remaining,
            asOf: try quotaInstant(2026, 9, day)
        )
    }

    /// The invariant that matters most: whatever the policy, the plan is worth
    /// the allowance. A user who does not add up their own numbers still gets a
    /// plan they can trust, because the remainder is never discarded.
    ///
    /// The engine's shares are exact hundredths, so the sum is exact in decimal.
    /// Summing them in `Double` is not, because 3.33 and 3.34 are not
    /// representable in binary, so the comparison allows representation error
    /// rather than pretending the arithmetic is exact.
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

    // MARK: Eligible days

    @Test("Eligible days run from today through the end of the period")
    func eligibleDays() throws {
        let days = engine.eligibleDays(
            in: try quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            asOf: try quotaInstant(2026, 9, 15)
        )
        #expect(days.count == 16)
        #expect(days.first?.description == "2026-09-15")
        #expect(days.last?.description == "2026-09-30")
    }

    @Test("The final day of a period is the last eligible day")
    func finalDayIsEligible() throws {
        let days = engine.eligibleDays(
            in: try quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            asOf: try quotaInstant(2026, 9, 30)
        )
        #expect(days.count == 1)
        #expect(days.first?.description == "2026-09-30")
    }

    // MARK: Even policy

    @Test("An even policy splits the allowance equally to within rounding")
    func evenPolicy() throws {
        let plan = try septemberPlan(policy: .even, remaining: 100, onDay: 1)
        #expect(plan.allocations.count == 30)
        for allocation in plan.allocations {
            #expect(allocation.percentage == 3.33 || allocation.percentage == 3.34)
        }
    }

    /// Independent rounding does not preserve a total. 30 days of 3.3333 rounds
    /// to 99.9, and the missing 0.1 has to land somewhere. Largest-remainder
    /// picks the days whose fraction was largest, so exactly ten days carry the
    /// extra hundredth rather than one day carrying all ten.
    @Test("Rounding spreads the shortfall across the days that lost the most")
    func largestRemainderPreservesTotal() throws {
        let plan = try septemberPlan(policy: .even, remaining: 100, onDay: 1)
        let higher = plan.allocations.filter { $0.percentage == 3.34 }
        let lower = plan.allocations.filter { $0.percentage == 3.33 }
        #expect(higher.count == 10)
        #expect(lower.count == 20)
        // Ten days a hundredth higher and twenty a hundredth lower is exactly the
        // hundredth that independent rounding threw away.
        expectTotal(plan, 100)
    }

    @Test("The total is exact for every allowance the provider can report")
    func totalIsExactForEveryAllowance() throws {
        for allowance in stride(from: 0.0, through: 100.0, by: 0.07) {
            let plan = try septemberPlan(policy: .even, remaining: allowance, onDay: 1)
            let difference = abs(total(of: plan) - allowance)
            #expect(difference <= 0.01, "allowance \(allowance) lost \(difference)")
        }
    }

    @Test("A zero allowance plans nothing without dividing by zero")
    func zeroAllowance() throws {
        let plan = try septemberPlan(policy: .even, remaining: 0, onDay: 1)
        #expect(plan.allocations.count == 30)
        expectTotal(plan, 0)
    }

    // MARK: Weekly policy

    @Test("A weekly policy excludes the weekend entirely")
    func weekdaysOnlyPolicy() throws {
        let plan = try septemberPlan(
            policy: .weekly(weekdayWeights: .weekdaysOnly),
            remaining: 100,
            onDay: 14 // Monday, so all 22 weekdays of the month remain
        )
        let weekends = plan.allocations.filter { $0.percentage == 0 }
        #expect(!weekends.isEmpty)
        for allocation in weekends {
            let weekday = allocation.date.weekday(calendar: quotaCalendar) ?? 0
            #expect(WeekdayConstants.isWeekend(weekday))
        }
        expectTotal(plan, 100)
    }

    @Test("A weekly policy that weights every day equally matches the even policy")
    func uniformWeightsMatchEven() throws {
        let weekly = try septemberPlan(
            policy: .weekly(weekdayWeights: .uniform),
            remaining: 100,
            onDay: 1
        )
        let even = try septemberPlan(policy: .even, remaining: 100, onDay: 1)
        #expect(weekly.allocations.map(\.percentage) == even.allocations.map(\.percentage))
    }

    @Test("A weekly policy doubles the share of a doubled day")
    func weightedPolicyProportions() throws {
        let weights = try WeekdayWeights(weights: [1: 1, 2: 2, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1])
        let plan = try septemberPlan(
            policy: .weekly(weekdayWeights: weights),
            remaining: 100,
            onDay: 14
        )
        let mondayDate = LocalDate(date: try quotaInstant(2026, 9, 14), calendar: quotaCalendar)
        let tuesdayDate = LocalDate(date: try quotaInstant(2026, 9, 15), calendar: quotaCalendar)
        let monday = try #require(plan.allocation(on: mondayDate))
        let tuesday = try #require(plan.allocation(on: tuesdayDate))
        #expect(monday.percentage == tuesday.percentage * 2)
        expectTotal(plan, 100)
    }
}
