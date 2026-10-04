import Foundation

/// One day's share of the remaining allowance.
public struct Allocation: Sendable, Hashable, Codable {
    public let date: LocalDate
    public let percentage: Double

    public init(date: LocalDate, percentage: Double) {
        self.date = date
        self.percentage = percentage
    }
}

/// Whether a plan spends exactly the allowance it was given.
///
/// A plan is not required to be exact. A user who assigns percentages by hand
/// will often total 95 or 105, and refusing to plan at all would be worse than
/// planning and saying so. The engine never discards the remainder silently:
/// under-allocated remainder is spread across the days, and over-allocation is
/// reported so the interface can say which days were trimmed.
public enum AllocationValidation: Sendable, Hashable, Codable {
    case exact
    case underallocated(unassigned: Double)
    case overallocated(exceeding: Double)

    /// A period with no days left in it, so the whole allowance is retained
    /// rather than discarded.
    case noEligibleDays(retained: Double)
}

/// The full set of daily shares for one quota, plus how it was validated.
public struct AllocationPlan: Sendable, Hashable, Codable {
    public let quotaID: UUID
    public let generatedAt: Date
    public let totalRemaining: Double
    public let period: QuotaPeriod
    public let allocations: [Allocation]
    public let validation: AllocationValidation

    /// - Throws: `QuotaDomainError.negativeValue` when the allowance is negative.
    public init(
        quotaID: UUID,
        generatedAt: Date,
        totalRemaining: Double,
        period: QuotaPeriod,
        allocations: [Allocation],
        validation: AllocationValidation
    ) throws {
        guard totalRemaining >= UsageConstants.minimumPercentage else {
            throw QuotaDomainError.negativeValue("totalRemaining")
        }
        self.quotaID = quotaID
        self.generatedAt = generatedAt
        self.totalRemaining = totalRemaining
        self.period = period
        self.allocations = allocations
        self.validation = validation
    }

    /// Today's share, or nil when today is not in the plan.
    public func allocation(on date: LocalDate) -> Allocation? {
        allocations.first { $0.date == date }
    }
}

/// What the user may spend today, and what they have already spent of it.
///
/// The suggested amount is a recommendation derived from the policy and the days
/// left. What has been used today is measured from the timeline, and what remains
/// is that suggestion minus the usage — never stored on its own, so a view cannot
/// show a remaining figure that no longer matches the usage beside it. When the
/// provider cannot report today's usage that subtraction cannot be done, so
/// `usedToday` and `remainingAfterToday` are nil rather than treating silence as
/// zero spend.
public struct TodayAllowance: Sendable, Hashable, Codable {
    public let date: LocalDate
    public let suggested: Double
    public let usedToday: Double?

    public var remainingAfterToday: Double? {
        guard let usedToday else { return nil }
        let remaining = suggested - usedToday
        return remaining > 0 ? remaining : 0
    }

    public init(date: LocalDate, suggested: Double, usedToday: Double?) {
        self.date = date
        self.suggested = suggested
        self.usedToday = usedToday
    }
}
