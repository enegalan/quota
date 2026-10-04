import Foundation

/// The mock provider's fixed values.
enum MockConstants {
    /// The usage percentages this provider reports, in order, one per fetch.
    ///
    /// Chosen to cover the cases a quota has to survive: barely used, past half,
    /// close to the limit, and exactly full. A single repeated value would never
    /// exercise the pacing calculation across a range.
    static let usagePercentages: [Double] = [12.5, 40, 87.5, 100]

    /// The day reported for a reading when the host's request carried none.
    ///
    /// Only reachable from a host speaking a different protocol version, since
    /// every `fetchUsage` in this version carries a date. The Unix epoch because
    /// it is obviously not a real reading: a test that unexpectedly got this
    /// should fail on the date rather than pass on a plausible number.
    static let fallbackDate = "1970-01-01"

    /// The account label this provider reports having connected.
    static let accountLabel = "mock-account"

    /// This provider's identifier.
    static let identifier = "mock"

    /// The one bucket it meters.
    static let bucketID = "models"
}
