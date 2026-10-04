import Foundation

/// Compares what a provider reported against what the plan expected by now.
///
/// Pure and side-effect free: it reads a reading and a plan and returns a
/// verdict. It never writes back to the policy, so asking "am I on track" can
/// never change the plan, and the plan a user approved is the plan that is
/// evaluated.
///
/// The calendar is injected for the same reason the engine takes one: "today"
/// must be the user's today, and a day boundary fixed to UTC would call a user
/// in Auckland ahead of schedule every morning.
public struct PacingCalculator: Sendable {
    private let calendar: Calendar

    /// The share of the expected usage a reading may deviate by before it is
    /// reported as ahead or behind.
    ///
    /// Without a tolerance the verdict would oscillate between "on track" and
    /// "behind" on ordinary rounding, and a status that flickers is one a user
    /// learns to ignore.
    private let tolerance: Double

    public init(calendar: Calendar, tolerance: Double = PacingCalculator.defaultTolerance) {
        self.calendar = calendar
        self.tolerance = tolerance
    }

    public static let defaultTolerance: Double = PacingConstants.defaultTolerance

    /// Evaluates a reading against a plan.
    ///
    /// - Returns: nil when there is no reading to evaluate. Absence is not zero
    ///   usage, and reporting "on track" for a provider that has never answered
    ///   would be a claim the app cannot support.
    public func status(
        quota: Quota,
        snapshot: UsageSnapshot?,
        plan: AllocationPlan,
        asOf reference: Date
    ) -> PacingStatus? {
        guard let bucket = snapshot?.bucket(id: quota.bucketID) else { return nil }

        let expected = expectedUsage(plan: plan, asOf: reference)
        let difference = bucket.usagePercentage - expected
        let phase = phase(
            usage: bucket.usagePercentage,
            expected: expected,
            periodStatus: plan.period.status(asOf: reference)
        )

        return PacingStatus(
            phase: phase,
            usagePercentage: bucket.usagePercentage,
            expectedPercentage: expected,
            difference: difference
        )
    }

    /// How much of the period has elapsed, as a fraction.
    ///
    /// - Returns: nil when the period has not started, since nothing is expected
    ///   of the user yet.
    public func elapsedFraction(plan: AllocationPlan, asOf reference: Date) -> Double? {
        guard plan.period.status(asOf: reference) != .future else { return nil }

        let total = Double(plan.period.totalDays(calendar: calendar))
        guard total > UsageConstants.minimumPercentage else { return nil }
        return Double(plan.period.elapsedDays(since: reference, calendar: calendar)) / total
    }

    /// The cumulative usage the plan expects by now: the sum of the shares for
    /// the days that have begun.
    public func expectedUsage(plan: AllocationPlan, asOf reference: Date) -> Double {
        let today = LocalDate(date: reference, calendar: calendar)
        return plan.allocations
            .filter { $0.date <= today }
            .reduce(0) { $0 + $1.percentage }
    }

    /// The one verdict the three facts add up to.
    ///
    /// The order of the checks is the decision. A reading at the cap is
    /// exhausted whatever the period says, and an ended period is expired rather
    /// than a pacing failure: neither describes the user's habits, and reporting
    /// either as "behind" would be wrong in a way that alarms. With nothing
    /// expected yet — the first day of a plan — everything is on track, because
    /// there is nothing yet to be behind.
    private func phase(
        usage: Double,
        expected: Double,
        periodStatus: QuotaPeriod.Status
    ) -> PacingStatus.Phase {
        if usage >= UsageConstants.maximumPercentage {
            return .exhausted
        }
        if periodStatus == .expired {
            return .expired
        }
        if expected <= UsageConstants.minimumPercentage {
            return .onTrack
        }

        let ratio = usage / expected
        if ratio > 1 + tolerance {
            return .behind
        }
        if ratio < 1 - tolerance {
            return .ahead
        }
        return .onTrack
    }
}
