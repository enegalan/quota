import Foundation

/// Relative emphasis for each weekday, in arbitrary integer units.
///
/// The units are a ratio, not a percentage: a weight of 2 on Monday and 1 on
/// Tuesday means Monday gets twice the share, whatever the total allowance
/// happens to be. Callers never sum these themselves; the engine normalises
/// them against the total weight of the days actually in the period.
public struct WeekdayWeights: Sendable, Hashable, Codable {
    /// Weekday to weight, using the numbering of the calendar the weights are
    /// evaluated against.
    public let weights: [Int: Int]

    /// - Throws: `QuotaDomainError.invalidWeights` when a weight is negative,
    ///   a weight falls outside the range a calendar can express, or every
    ///   weight is zero, which would leave the policy with nothing to divide.
    public init(weights: [Int: Int]) throws {
        guard !weights.values.contains(where: { $0 < 0 }) else {
            throw QuotaDomainError.invalidWeights
        }
        guard weights.values.allSatisfy({ $0 <= WeekdayConstants.maximumWeight }) else {
            throw QuotaDomainError.invalidWeights
        }
        guard weights.values.contains(where: { $0 > 0 }) else {
            throw QuotaDomainError.invalidWeights
        }

        self.weights = weights
    }

    /// Decoding validates, so a stored policy cannot reintroduce weights the
    /// initialiser would have rejected.
    ///
    /// Through string keys, because a JSON object's keys are always strings and
    /// `[Int: Int]`'s synthesised decoding insists on integers. Decoding it
    /// directly throws on every file ever written, and the store answers a
    /// failed read by setting the file aside as corrupt — so every weekly policy
    /// a user saved would quietly disappear on the next launch.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Int].self)
        var weights: [Int: Int] = [:]
        for (key, weight) in raw {
            guard let weekday = Int(key) else {
                throw QuotaDomainError.invalidWeights
            }
            weights[weekday] = weight
        }
        try self.init(weights: weights)
    }

    /// Encoded as a plain object of weekday to weight.
    ///
    /// Object rather than an array of pairs, so a stored policy can be read and
    /// edited by hand, and so the shape of the file is the shape of the decision.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let raw = Dictionary(
            uniqueKeysWithValues: weights.map { (String($0.key), $0.value) }
        )
        try container.encode(raw)
    }

    /// Every day weighted equally.
    public static let uniform = WeekdayWeights(unchecked: WeekdayConstants.uniformWeights)

    /// Days weighted one and weekend days zero: a typical working week.
    public static let weekdaysOnly = WeekdayWeights(
        unchecked: WeekdayConstants.weekdayOnlyWeights
    )

    /// Bypasses validation for the presets below, which are part of this file
    /// and are reviewed with it. Going through the throwing initialiser would
    /// mean a `try!` on a literal, which would turn a typo in a dictionary into
    /// a crash at launch instead of a failing test.
    private init(unchecked weights: [Int: Int]) {
        self.weights = weights
    }

    /// The weight for a date, falling back to a weight of one for a weekday the
    /// caller did not mention.
    ///
    /// The fallback is one rather than zero so a partial specification means
    /// "these days count more", not "every day I forgot is excluded".
    public func weight(for date: LocalDate, calendar: Calendar) -> Int {
        guard let weekday = date.weekday(calendar: calendar) else { return WeekdayConstants.defaultWeight }
        return weights[weekday] ?? WeekdayConstants.defaultWeight
    }
}
