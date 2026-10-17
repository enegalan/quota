import Foundation
import PluginKit

/// A payload a plugin cannot make a reading out of — all of its cases are the
/// same thing to the host: the provider answered, and not with something
/// usable. Which field was wrong goes to stderr, not into the user's message.
public enum UsageDataError: Error, Equatable, ProviderFailure {
    /// A field a reading depends on was not there.
    case missingField(String)

    /// The period runs backwards — an end before its start.
    case invalidPeriod

    /// The payload carries numbers, and not one of them is a meter.
    case noUsableMeter

    public var providerError: ProviderError {
        ProviderError(code: .invalidResponse)
    }
}

/// Reading values out of a provider's JSON without repeating the casts. The
/// untyped shape stays untyped until the provider says what it wants from it:
/// decoding a payload into a model is a claim about a schema this plugin does
/// not control, and a claim that fails halfway leaves nothing to report with.
public enum JSONAccess {
    public static func dictionary(_ json: [String: Any], key: String) throws -> [String: Any] {
        guard let value = json[key] as? [String: Any] else {
            throw UsageDataError.missingField(key)
        }
        return value
    }

    public static func string(_ json: [String: Any], key: String) -> String? {
        json[key] as? String
    }

    /// Every numeric shape a serializer can write: an `Int`, a `Double` and an
    /// `NSNumber` are three different Swift types carrying one idea, and a
    /// whole number written as `42` would otherwise read as "no number here".
    public static func double(_ json: [String: Any], key: String) -> Double? {
        if let value = json[key] as? Double {
            return value
        }
        if let value = json[key] as? Int {
            return Double(value)
        }
        if let value = json[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}

/// Dates: a day as the protocol carries it, an instant as providers write it.
public enum DayFormat {
    /// The day as `yyyy-MM-dd`, in UTC — a wire value, so two sides never
    /// disagree about which day a reading belongs to over a detail both would
    /// have spelled plausibly.
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// An ISO 8601 instant, with or without fractional seconds — both
    /// spellings are a detail of the serializer, not of the value.
    public static func instant(fromISO8601 value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: value)
    }
}

/// The window a reading is measured over: first and last day, `yyyy-MM-dd`.
public struct PeriodDays: Equatable, Sendable {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

/// Reading the period a provider meters, in the two shapes providers send it.
///
/// The keys are always passed rather than defaulted: which field a provider
/// calls its billing cycle is that provider's naming, and a default here would
/// make one provider's coincidence look like a rule.
public enum UsagePeriod {
    private static let millisecondsPerSecond = 1000.0

    /// Milliseconds since the epoch, sent as strings — the shape a
    /// JavaScript-backed dashboard writes, since its numbers can be too large
    /// for some serializers to send whole.
    public static func days(
        fromMillisecondsStrings json: [String: Any],
        startKey: String,
        endKey: String
    ) throws -> PeriodDays {
        guard let startRaw = JSONAccess.string(json, key: startKey),
              let endRaw = JSONAccess.string(json, key: endKey),
              let startMillis = Double(startRaw),
              let endMillis = Double(endRaw)
        else {
            throw UsageDataError.missingField("\(startKey)/\(endKey)")
        }
        return try days(
            from: (
                Date(timeIntervalSince1970: startMillis / millisecondsPerSecond),
                Date(timeIntervalSince1970: endMillis / millisecondsPerSecond)
            )
        )
    }

    /// ISO 8601 instants.
    public static func days(
        fromISO8601 json: [String: Any],
        startKey: String,
        endKey: String
    ) throws -> PeriodDays {
        guard let startRaw = JSONAccess.string(json, key: startKey),
              let endRaw = JSONAccess.string(json, key: endKey),
              let start = DayFormat.instant(fromISO8601: startRaw),
              let end = DayFormat.instant(fromISO8601: endRaw)
        else {
            throw UsageDataError.missingField("\(startKey)/\(endKey)")
        }
        return try days(from: (start, end))
    }

    /// The check is here rather than per provider because a period that runs
    /// backwards is wrong for all of them, and the ways it goes wrong all
    /// produce the same silent damage: a reading filed against a window that
    /// never happened.
    private static func days(from interval: (start: Date, end: Date)) throws -> PeriodDays {
        guard interval.start <= interval.end else {
            throw UsageDataError.invalidPeriod
        }
        return PeriodDays(
            start: DayFormat.string(from: interval.start),
            end: DayFormat.string(from: interval.end)
        )
    }
}

/// Turning a provider's numbers into the one number this app paces — every
/// provider eventually does this arithmetic, and every dashboard has a
/// different way of being wrong about it.
public enum Percentage {
    /// The whole-to-percent scale.
    public static let scale = 100.0

    /// A provider reporting 130% or −4% is reporting something that cannot be
    /// paced: past the meter draws a bar through the edge of its row, negative
    /// shows an allowance a user has not earned back by using less. The
    /// provider's figure is not believed past its own scale.
    public static func clamp(_ value: Double) -> Double {
        min(max(value, 0), scale)
    }

    /// `used` as a share of `limit`, in percent — or nil when there is no
    /// meter in those two numbers.
    ///
    /// Nil rather than a made-up percentage, because the two cases a provider
    /// hits are different: an account with no allowance recorded yet has *no
    /// reading*, and turning that into 0% would say a user has used nothing of
    /// a quota they were never given. What a provider does with the nil —
    /// another field, or nothing to report — is its own.
    public static func of(used: Double, limit: Double) -> Double? {
        guard limit > 0 else { return nil }
        return used / limit * scale
    }
}
