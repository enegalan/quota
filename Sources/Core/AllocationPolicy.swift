import Foundation

/// How the remaining allowance is spread across the days left in a period.
///
/// The three cases exist because the user's situation decides which question they
/// are asking. `even` is "I want the same every day". `weekly` is "weekends are
/// wasted on me". `custom` is "I know exactly which days matter". No fourth case
/// is provided, because a policy the engine cannot evaluate exactly would be
/// worse than one the user cannot express.
public enum AllocationPolicy: Sendable, Hashable, Codable {
    case even
    case weekly(weekdayWeights: WeekdayWeights)
    case custom(assignments: [LocalDate: Double])

    /// Encoded with a discriminating `kind` field so that adding a case later
    /// cannot make an existing file decode as the wrong policy.
    private enum CodingKeys: String, CodingKey {
        case kind
        case weekdayWeights
        case assignments
    }

    private enum Kind: String, Codable {
        case even
        case weekly
        case custom
    }

    /// The name this policy is stored under.
    ///
    /// Public because the stored form is written in more than one place — the
    /// wire, the quota file, and a preference naming the policy a new quota gets
    /// — and a preference holding `"even"` as a hand-written literal is one more
    /// string that can drift from the case it is meant to name.
    public var kind: String {
        switch self {
        case .even: Kind.even.rawValue
        case .weekly: Kind.weekly.rawValue
        case .custom: Kind.custom.rawValue
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .even:
            self = .even
        case .weekly:
            self = try .weekly(
                weekdayWeights: container.decode(
                    WeekdayWeights.self,
                    forKey: .weekdayWeights
                )
            )
        case .custom:
            let raw = try container.decode([String: Double].self, forKey: .assignments)
            self = try .custom(assignments: CustomAssignments.decode(raw))
        }
    }

    /// Encodes the `kind` tag alongside whichever fields the case carries.
    ///
    /// Written out rather than left to the compiler: a case with no associated
    /// value produces an empty object under the synthesised form, and `kind` is
    /// the only thing that tells a later launch which policy it is reading.
    ///
    /// The custom case goes out through `CustomAssignments.encode` because
    /// `[LocalDate: Double]` has no representation of its own on the wire.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .even:
            try container.encode(Kind.even, forKey: .kind)
        case .weekly(let weekdayWeights):
            try container.encode(Kind.weekly, forKey: .kind)
            try container.encode(weekdayWeights, forKey: .weekdayWeights)
        case .custom(let assignments):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(CustomAssignments.encode(assignments), forKey: .assignments)
        }
    }

    /// Builds a custom policy, rejecting values that cannot be a share.
    ///
    /// - Throws: `QuotaDomainError.invalidAssignment` for a negative or
    ///   non-finite percentage.
    public static func customValidated(
        assignments: [LocalDate: Double]
    ) throws -> AllocationPolicy {
        try CustomAssignments.validate(assignments)
        return .custom(assignments: assignments)
    }
}

/// `[LocalDate: Double]` cannot be `Codable` directly, because `LocalDate` is not
/// a `String` or an `Int` key. Mapping through ISO strings keeps the stored file
/// readable and keeps the date type in one place.
enum CustomAssignments {
    /// Rejects percentages that cannot be a share of an allowance.
    ///
    /// Called from construction and from decoding alike, so a policy made in
    /// memory and one read back from disk are held to one rule. A store willing
    /// to keep what the engine will not plan is how a corrupt file becomes a
    /// wrong plan.
    static func validate(_ assignments: [LocalDate: Double]) throws {
        for (date, percentage) in assignments {
            guard percentage.isFinite, percentage >= UsageConstants.minimumPercentage else {
                throw QuotaDomainError.invalidAssignment(
                    date: date.description,
                    percentage: percentage
                )
            }
        }
    }

    /// Rebuilds the assignment map from its stored string keys.
    ///
    /// Re-validates rather than trusting the file: the values arrived as bare
    /// `Double`s, so this is the only place a hand-edited or truncated file is
    /// caught before the engine spreads them across a period.
    static func decode(_ raw: [String: Double]) throws -> [LocalDate: Double] {
        var result: [LocalDate: Double] = [:]
        for (key, percentage) in raw {
            try result[LocalDate(iso: key)] = percentage
        }
        try validate(result)
        return result
    }

    /// Flattens the assignment map to the string-keyed form that is stored.
    ///
    /// `description` is the one place the ISO form is written, so the file a
    /// user might edit by hand and the string `init(iso:)` reads back cannot
    /// drift apart into two date formats.
    static func encode(_ assignments: [LocalDate: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.description, $0.value) })
    }
}
