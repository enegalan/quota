import Core

/// What a weekday's weight means as a share of the week.
///
/// In the app rather than only in the view, because it is a claim the user reads
/// and the test asserts: "2" beside "1" means nothing until it is two thirds and
/// one third, and computing that in two places would be two chances to disagree
/// about the same number.
enum PolicyShare {
    /// A weekday's share of the total weight, as a percentage.
    ///
    /// Returns zero rather than a wrong figure when the weights sum to nothing,
    /// which is the state the domain refuses to plan at all — so there is no plan
    /// for this number to be wrong about.
    static func weekday(_ weekday: Int, among weights: [Int: Int]) -> Double {
        let total = PolicyWeekdays.all.reduce(0) { $0 + (weights[$1] ?? PolicyWeekdays.defaultWeight) }
        guard total > 0 else { return 0 }
        let weight = weights[weekday] ?? PolicyWeekdays.defaultWeight
        return UsageConstants.percentageScale * Double(weight) / Double(total)
    }

    /// Two weights' shares of each other, which is how the editor explains a
    /// single step: moving Monday from 1 to 2 against a Tuesday left at 1.
    static func pair(_ weight: Int, against other: Int) -> Double {
        let total = weight + other
        guard total > 0 else { return 0 }
        return UsageConstants.percentageScale * Double(weight) / Double(total)
    }
}

/// The arithmetic behind the custom policy editor's shares.
///
/// A custom policy is the user's own figures: a percentage per day of a period,
/// which together are the whole allowance. The rules that keep those figures
/// honest live here, in one place, because the editor's stepper, the total it
/// displays, and the buttons that fill a period in one press all have to agree
/// about what a policy may add up to. Two of them computing the ceiling
/// separately would be two chances for the total to pass 100% in the place the
/// user is not looking.
enum Share {
    /// How near two figures must be to count as the same number.
    ///
    /// For comparisons that mean one particular figure — a weekday's share, a
    /// step's worth of a day — where any difference is a difference. What the
    /// editor *displays* is decided by `roundingTolerance` instead, because a total
    /// the user reads in hundredths is not wrong by a hundredth of a hundredth.
    static let tolerance: Double = 0.0001

    /// The most a custom policy can assign in total: the whole of the allowance.
    ///
    /// A policy above 100% is not a preference, it is a plan the engine can only
    /// satisfy by scaling every day down — the user would have asked for 150% of
    /// their quota and been given 100% of it spread thinner than they asked for.
    /// Refusing to let the total exceed the scale is what makes the policy mean
    /// what it says: one hundred percent assigned is one hundred percent spent.
    static let maximumTotal: Double = UsageConstants.percentageScale

    /// What a policy assigns across every day.
    static func total(_ assignments: [LocalDate: Double]) -> Double {
        assignments.values.reduce(0, +)
    }

    /// Whether a policy adds up to the whole allowance.
    ///
    /// Checked with a tolerance because the total is a sum of figures the user
    /// moved in whole steps: 33.33 and 33.33 and 33.34 is one hundred percent
    /// to any figure a person can read, and calling it short would warn a user
    /// who has assigned their quota exactly.
    static func isComplete(_ assignments: [LocalDate: Double]) -> Bool {
        abs(total(assignments) - maximumTotal) < Share.roundingTolerance
    }

    /// How close a figure has to be to count as the same number.
    ///
    /// The domain's own rounding tolerance rather than `tolerance`: this decides
    /// whether a plan is complete, and the engine reports a plan whose shares miss
    /// the allowance by more than this as under- or over-allocated. Two
    /// thresholds for the same question would let the editor call a policy whole
    /// that the engine then trims.
    static let roundingTolerance: Double = UsageConstants.percentageRoundingTolerance

    /// The most one day may be given, given what the other days already hold.
    ///
    /// The share that would take the policy to exactly 100%, and never negative:
    /// a policy stored before this ceiling existed can already be over 100%, and
    /// a ceiling below zero is not a number a control can be given.
    static func maximum(for date: LocalDate, in assignments: [LocalDate: Double]) -> Double {
        max(0, maximumTotal - assignedElsewhere(date, in: assignments))
    }

    /// The range a day's share may move in, given what the others hold.
    ///
    /// Raised to whatever the day already holds when a stored policy is over the
    /// ceiling, because a control opened on a figure the user never set would be
    /// showing them something else, and because a policy that is too full has to
    /// be walkable back down one press at a time.
    static func range(for date: LocalDate, in assignments: [LocalDate: Double]) -> ClosedRange<Double> {
        0 ... max(assignments[date] ?? 0, maximum(for: date, in: assignments))
    }

    /// A day's share, held below the ceiling.
    ///
    /// Only raising is held back. Lowering is always allowed, and a day that is
    /// already above the ceiling — a policy written before there was one — has to
    /// come down to reach it, so a clamp applied to both directions would leave
    /// such a day unable to move at all except to nothing.
    static func clamped(
        _ value: Double,
        for date: LocalDate,
        in assignments: [LocalDate: Double]
    ) -> Double {
        guard value.isFinite else { return 0 }
        let floor = max(0, value)
        guard floor > (assignments[date] ?? 0) else { return floor }
        return min(floor, maximum(for: date, in: assignments))
    }

    /// What every day but this one has been given.
    private static func assignedElsewhere(
        _ date: LocalDate,
        in assignments: [LocalDate: Double]
    ) -> Double {
        total(assignments) - (assignments[date] ?? 0)
    }

    /// The policy that spreads the whole allowance evenly across the given days.
    ///
    /// Whole hundredths, handed out one at a time to the first days, so the days
    /// add up to exactly 100% rather than to 100% minus the rounding of thirty
    /// divisions by thirty. Without this, a period that cannot be divided evenly
    /// could not be filled by pressing a button: the user would have to walk a
    /// stepper across every day to land on the total the engine wants.
    static func even(across days: [LocalDate]) -> [LocalDate: Double] {
        guard !days.isEmpty else { return [:] }
        let scale = UsageConstants.percentagePrecisionScale
        let units = Int((maximumTotal * scale).rounded())
        let perDay = units / days.count
        let extra = units % days.count
        var assignments: [LocalDate: Double] = [:]
        for (index, day) in days.enumerated() {
            assignments[day] = Double(perDay + (index < extra ? 1 : 0)) / scale
        }
        return assignments
    }
}

extension AllocationPolicy {
    /// What this policy does, in one line.
    ///
    /// One sentence per policy, because it was written out twice: once under the
    /// control that chooses a policy and once in the caption describing it, and
    /// the two were worded differently for the same policy. A user comparing the
    /// editor with the summary is meant to be reading the same sentence twice.
    var summary: String {
        switch self {
        case .even: "The same share on every day."
        case .weekly: "Weighted by weekday."
        case .custom(let assignments): "\(Share.total(assignments))% assigned by hand."
        }
    }
}
