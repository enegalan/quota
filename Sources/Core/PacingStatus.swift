import Foundation

/// How actual spending compares with the plan.
///
/// Derived from a reading and a plan, never stored on either, so it cannot
/// outlive the values it describes.
public struct PacingStatus: Sendable, Hashable, Codable {
    public enum Phase: String, Sendable, Codable {
        /// Within tolerance: spending in step with the plan.
        case onTrack
        /// Using less than planned, which is not a problem.
        case ahead
        /// Using more than planned.
        case behind
        /// The allowance is used up while the period is still running.
        case exhausted
        /// The period has ended. Nothing more can be spent, and this is not a
        /// failure state.
        case expired
    }

    public let phase: Phase
    public let usagePercentage: Double
    public let expectedPercentage: Double
    public let difference: Double

    public init(
        phase: Phase,
        usagePercentage: Double,
        expectedPercentage: Double,
        difference: Double
    ) {
        self.phase = phase
        self.usagePercentage = usagePercentage
        self.expectedPercentage = expectedPercentage
        self.difference = difference
    }
}
