import Foundation

/// Spreads a remaining allowance across the days left in a period.
///
/// The whole allowance is always accounted for. Every policy and every branch
/// ends in a list of daily shares that sums to the allowance, or in a
/// `noEligibleDays` result that says the allowance was retained. No path
/// discards a remainder, because a user told their remaining quota vanished has
/// no way to recover it.
public struct AllocationEngine: Sendable {
    private let calendar: Calendar
    private let precision: AllocationPrecision

    public init(calendar: Calendar, precision: AllocationPrecision = .default) {
        self.calendar = calendar
        self.precision = precision
    }

    /// Builds the plan for a quota.
    ///
    /// - Parameter asOf: the reference instant, so a plan is reproducible and
    ///   testable rather than dependent on when it happened to be called.
    public func plan(
        quotaID: UUID,
        policy: AllocationPolicy,
        period: QuotaPeriod,
        totalRemaining: Double,
        asOf reference: Date
    ) throws -> AllocationPlan {
        let days = eligibleDays(in: period, asOf: reference)

        guard !days.isEmpty else {
            return try AllocationPlan(
                quotaID: quotaID,
                generatedAt: reference,
                totalRemaining: totalRemaining,
                period: period,
                allocations: [],
                validation: .noEligibleDays(retained: totalRemaining)
            )
        }

        let (exact, validation) = try shares(
            policy: policy,
            days: days,
            totalRemaining: totalRemaining
        )
        let allocations = quantize(exact, totalRemaining: totalRemaining)

        return try AllocationPlan(
            quotaID: quotaID,
            generatedAt: reference,
            totalRemaining: totalRemaining,
            period: period,
            allocations: allocations,
            validation: validation
        )
    }

    /// The days an allocation may land on.
    ///
    /// The intersection of "from today onwards" with "inside the period", so a
    /// period that has not started yet plans only its own days and never offers
    /// the user quota to spend before the period begins. A period that has
    /// already ended yields no days, which is what makes `plan` report
    /// `noEligibleDays` rather than throwing: an expired period is a normal
    /// thing to encounter, not a malformed input.
    public func eligibleDays(in period: QuotaPeriod, asOf reference: Date) -> [LocalDate] {
        let today = LocalDate(date: reference, calendar: calendar)
        let firstDay = LocalDate(date: period.start, calendar: calendar)
        let lastDay = LocalDate(date: period.end, calendar: calendar)

        let start = max(today, firstDay)
        guard let days = start.inclusiveDayCount(through: lastDay, calendar: calendar), days > 0 else {
            return []
        }
        return (0 ..< days).compactMap { start.adding(days: $0, calendar: calendar) }
    }
}

// MARK: - Policy shares

extension AllocationEngine {
    /// The exact, unrounded share for each eligible day, and how the policy
    /// itself was found to be inconsistent.
    private func shares(
        policy: AllocationPolicy,
        days: [LocalDate],
        totalRemaining: Double
    ) throws -> ([Allocation], AllocationValidation) {
        switch policy {
        case .even:
            (even(days: days, totalRemaining: totalRemaining), .exact)

        case .weekly(let weights):
            try (weekly(weights: weights, days: days, totalRemaining: totalRemaining), .exact)

        case .custom(let assignments):
            try custom(assignments: assignments, days: days, totalRemaining: totalRemaining)
        }
    }

    /// The same share for every eligible day.
    ///
    /// Also the fallback for a custom policy with a shortfall and free days to
    /// absorb it, so a remainder is spread by the one rule that needs nothing
    /// beyond the days themselves.
    private func even(days: [LocalDate], totalRemaining: Double) -> [Allocation] {
        let share = totalRemaining / Double(days.count)
        return days.map { Allocation(date: $0, percentage: share) }
    }

    /// A day's share, in proportion to its weekday's weight.
    ///
    /// Throws when the weights sum to nothing across the days actually in the
    /// period: the weights can be valid in themselves while every day left in the
    /// period is excluded, and there is no plan that divides by zero.
    private func weekly(
        weights: WeekdayWeights,
        days: [LocalDate],
        totalRemaining: Double
    ) throws -> [Allocation] {
        let perDay = days.map { (day: $0, weight: weights.weight(for: $0, calendar: calendar)) }
        let totalWeight = perDay.reduce(0) { $0 + $1.weight }

        guard totalWeight > WeekdayConstants.minimumWeight else {
            throw QuotaDomainError.invalidWeights
        }

        return perDay.map {
            Allocation(
                date: $0.day,
                percentage: totalRemaining * Double($0.weight) / Double(totalWeight)
            )
        }
    }

    /// Applies hand-assigned percentages to the days they name.
    ///
    /// Three cases, all of which keep the shares summing to the allowance:
    ///
    /// - Under-assigned with unassigned days left: the remainder is spread
    ///   evenly across them, and the shortfall is reported so the interface can
    ///   say the user's own figures did not add up.
    /// - Over-assigned: the assignments are scaled down proportionally. Ignoring
    ///   the excess instead would produce a plan worth more than the allowance,
    ///   which is the one thing a plan must never be.
    /// - Under-assigned with no unassigned days left: the remainder is added
    ///   back in proportion to what was assigned, because the allowance may not
    ///   be discarded. The shortfall is still reported.
    private func custom(
        assignments: [LocalDate: Double],
        days: [LocalDate],
        totalRemaining: Double
    ) throws -> ([Allocation], AllocationValidation) {
        try CustomAssignments.validate(assignments)

        let eligible = Set(days)
        let assigned = assignments.filter { eligible.contains($0.key) }
        let assignedTotal = assigned.values.reduce(0, +)

        if assignedTotal > totalRemaining {
            let scale = totalRemaining / assignedTotal
            let scaled = days.map { day in
                Allocation(date: day, percentage: (assigned[day] ?? 0) * scale)
            }
            return (scaled, .overallocated(exceeding: assignedTotal - totalRemaining))
        }

        let remainder = totalRemaining - assignedTotal
        // A shortfall of zero is not a shortfall. Reporting it as under-allocated
        // would make the interface warn a user who has assigned their quota
        // perfectly.
        if abs(remainder) <= precision.tolerance {
            let exact = days.map { Allocation(date: $0, percentage: assigned[$0] ?? 0) }
            return (exact, .exact)
        }

        let unassignedDays = days.filter { assigned[$0] == nil }

        guard !unassignedDays.isEmpty else {
            // Every day was named, so there is no free day to absorb the
            // remainder: it is added back in proportion to what was assigned.
            // The share is *added* to the assignment, not returned instead of
            // it, or the assigned values themselves would vanish.
            let share = proportional(days: days, weights: assigned, total: remainder)
            let shareByDay = Dictionary(uniqueKeysWithValues: share.map { ($0.date, $0.percentage) })
            let combined = days.map {
                Allocation(date: $0, percentage: (assigned[$0] ?? 0) + (shareByDay[$0] ?? 0))
            }
            return (combined, .underallocated(unassigned: remainder))
        }

        let spread = even(days: unassignedDays, totalRemaining: remainder)
        let byDay = Dictionary(uniqueKeysWithValues: spread.map { ($0.date, $0.percentage) })
        let combined = days.map {
            Allocation(date: $0, percentage: (assigned[$0] ?? 0) + (byDay[$0] ?? 0))
        }
        return (combined, .underallocated(unassigned: remainder))
    }

    /// Distributes a total across the named days in proportion to their weights,
    /// falling back to an even split when every weight is zero.
    private func proportional(
        days: [LocalDate],
        weights: [LocalDate: Double],
        total: Double
    ) -> [Allocation] {
        let totalWeight = days.reduce(0) { $0 + (weights[$1] ?? 0) }
        guard totalWeight > 0 else {
            return even(days: days, totalRemaining: total)
        }
        return days.map {
            Allocation(date: $0, percentage: total * (weights[$0] ?? 0) / totalWeight)
        }
    }
}

// MARK: - Rounding

extension AllocationEngine {
    /// Rounds the exact shares so their sum equals the allowance exactly.
    ///
    /// The largest-remainder method is used rather than rounding each day
    /// independently, because independent rounding does not preserve a total:
    /// thirty days each rounded to two places can add up to 99.99 or 100.01, and
    /// an allowance that does not add up is one a user cannot trust.
    ///
    /// Only ever hands out whole units, never takes them away. Rounding down
    /// cannot sum to more than the total it came from, so the shortfall is
    /// always non-negative.
    private func quantize(
        _ exact: [Allocation],
        totalRemaining: Double
    ) -> [Allocation] {
        var units = exact.map { entry in
            let scaled = entry.percentage * precision.scale
            return (
                date: entry.date,
                units: scaled.rounded(.down),
                remainder: scaled - scaled.rounded(.down)
            )
        }

        let target = (totalRemaining * precision.scale).rounded()
        var owed = Int(target) - Int(units.reduce(0) { $0 + $1.units }.rounded())

        let ranked = units.indices.sorted { units[$0].remainder > units[$1].remainder }
        for index in ranked where owed > 0 {
            units[index].units += 1
            owed -= 1
        }

        return units.map { Allocation(date: $0.date, percentage: $0.units / precision.scale) }
    }
}

/// How precisely a plan is expressed.
///
/// A provider's own figures are percentages with decimals, so a plan rounded to
/// two places is as precise as the thing it is compared against; finer rounding
/// would imply a confidence the inputs do not have.
public struct AllocationPrecision: Sendable, Hashable {
    public let scale: Double
    public let tolerance: Double

    public static let `default` = AllocationPrecision(
        scale: UsageConstants.percentagePrecisionScale,
        tolerance: UsageConstants.percentageRoundingTolerance
    )

    public init(scale: Double, tolerance: Double) {
        self.scale = scale
        self.tolerance = tolerance
    }
}
