import Foundation

/// Facts about usage figures that are structural rather than tunable.
///
/// Public because the interface formats the same figures the engine plans in:
/// a scale defined in two places is a scale that will eventually disagree with
/// itself, and the interface is where that disagreement would be visible.
public enum UsageConstants {
    /// Usage is reported as a percentage of a provider's allowance, so the scale
    /// is 0 to 100 inclusive. A provider reporting anything else is reporting
    /// something this model cannot represent, and the value is rejected rather
    /// than clamped.
    public static let percentageScale: Double = 100

    /// Zero: the lower bound of a valid figure, and the value that stands for
    /// "none of it has been used".
    ///
    /// Doubling as that sentinel is why absence is carried by an optional
    /// elsewhere rather than by this number, and why a plan compares against
    /// "nothing expected yet" by testing this rather than a second zero.
    public static let minimumPercentage: Double = 0

    /// The upper bound of a valid figure, and the point at which an allowance is
    /// spent.
    public static let maximumPercentage: Double = 100

    /// The inclusive bounds of a valid usage figure.
    public static let percentageRange: ClosedRange<Double> = minimumPercentage ... maximumPercentage

    /// A plan is expressed in hundredths of a percent. A provider reports its own
    /// usage with decimals, so two places is as precise as the figures being
    /// compared, and finer rounding would imply confidence the inputs do not
    /// have.
    public static let percentagePrecisionScale: Double = 100

    /// How far a plan's rounded shares may miss the allowance by before it is
    /// called under- or over-allocated. Larger than the rounding step, so a plan
    /// that balances to a fraction of a unit is still reported as exact.
    public static let percentageRoundingTolerance: Double = 0.01
}
