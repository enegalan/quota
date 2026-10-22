import Foundation

/// Reading the instants Claude reports.
///
/// The endpoint writes timestamps in more than one spelling: with a `Z`, with
/// a `+00:00` offset, and with a fraction of a second in either. A reader
/// that only accepts one of them throws away the reading of a limit that is
/// perfectly well reported, and the limit then looks like no limit at all.
enum ClaudeTimestamp {
    /// The calendar the instants are read in.
    ///
    /// UTC, because an offset is carried in the text itself: a timestamp
    /// without an offset is read as UTC rather than as the reader's own zone,
    /// which would put a limit's reset on the wrong day for half the world.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// The instant in a timestamp, or nil when the text is not one.
    static func instant(from value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = text.firstIndex(of: "T") else { return nil }
        guard var components = dayComponents(String(text[text.startIndex ..< separator]))
        else { return nil }

        var clock = String(text[text.index(after: separator)...])
        var offsetSeconds = 0

        if clock.hasSuffix("Z") || clock.hasSuffix("z") {
            clock = String(clock.dropLast())
        } else if let sign = clock.lastIndex(of: "+") ?? clock.lastIndex(of: "-") {
            // The offset can only come after the time: the sign in a date is
            // always before the `T`, which has already been split off.
            guard let offset = parseOffset(
                from: String(clock[clock.index(after: sign)...]),
                negative: clock[sign] == "-"
            )
            else { return nil }
            offsetSeconds = offset
            clock = String(clock[..<sign])
        }

        if let dot = clock.firstIndex(of: ".") {
            clock = String(clock[..<dot])
        }

        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        components.hour = parts[0]
        components.minute = parts[1]
        components.second = parts[2]
        components.timeZone = TimeZone(secondsFromGMT: 0)

        guard let instant = calendar.date(from: components) else { return nil }
        return instant.addingTimeInterval(-Double(offsetSeconds))
    }

    /// The date half of a timestamp.
    private static func dayComponents(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components
    }

    /// An offset in seconds, from the text after its sign.
    ///
    /// Both `+01:00` and `+0100` are accepted, and a bare `+01` is read as
    /// whole hours: the endpoint writes the first, and a reader that only
    /// understood it would have to fail on the second. The sign is the
    /// caller's, because the text after the sign carries only the magnitude.
    private static func parseOffset(from text: String, negative: Bool) -> Int? {
        let digits: String
        if let colon = text.firstIndex(of: ":") {
            let hours = text[..<colon]
            let minutes = text[text.index(after: colon)...]
            guard hours.count == 2,
                  minutes.count == 2,
                  hours.allSatisfy(isASCIIDigit),
                  minutes.allSatisfy(isASCIIDigit)
            else { return nil }
            digits = String(hours) + String(minutes)
        } else {
            guard text.allSatisfy(isASCIIDigit) else { return nil }
            digits = text
        }

        let magnitude: Int
        switch digits.count {
        case 2:
            magnitude = (Int(digits) ?? 0) * 3600
        case 4:
            let hours = Int(digits.prefix(2)) ?? 0
            let minutes = Int(digits.suffix(2)) ?? 0
            magnitude = hours * 3600 + minutes * 60
        default:
            return nil
        }
        return negative ? -magnitude : magnitude
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
