enum PacingConstants {
    /// The share of the expected usage a reading may deviate by before it is
    /// reported as ahead of or behind the plan.
    ///
    /// Without a tolerance the verdict would oscillate between "on track" and
    /// "behind" on ordinary rounding, and a status that flickers is one a user
    /// learns to ignore. Five percent is wide enough to absorb a provider's
    /// rounding and a user's imperfect memory, and narrow enough that a real
    /// change in habits is still reported.
    static let defaultTolerance: Double = 0.05
}
