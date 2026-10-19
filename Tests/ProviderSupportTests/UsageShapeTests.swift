import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

@Suite("Reading a provider's payload")
struct JSONAccessTests {
    @Test("A nested object, or the field named as missing")
    func dictionary() throws {
        let json = ["planUsage": ["used": 1]]
        let plan = try JSONAccess.dictionary(json, key: "planUsage")
        #expect(plan["used"] as? Int == 1)
        #expect(throws: UsageDataError.self) {
            try JSONAccess.dictionary(json, key: "apiUsage")
        }
        #expect(throws: UsageDataError.self) {
            try JSONAccess.dictionary(["planUsage": 3], key: "planUsage")
        }
    }

    @Test("Every numeric shape a serializer can write reads as one number")
    func numbers() {
        let json: [String: Any] = [
            "double": 1.5,
            "int": 2,
            "number": NSNumber(value: 3),
            "string": "4",
        ]
        #expect(JSONAccess.double(json, key: "double") == 1.5)
        #expect(JSONAccess.double(json, key: "int") == 2)
        #expect(JSONAccess.double(json, key: "number") == 3)
        // A string is not a number, even one that looks like one: a provider
        // that quoted its figure reported it as text, and guessing otherwise
        // would turn a type it did change into one it did not.
        #expect(JSONAccess.double(json, key: "string") == nil)
        #expect(JSONAccess.double(json, key: "absent") == nil)
    }

    @Test("A missing field names itself, for the plugin's own diagnosis")
    func missingFieldNamesItself() {
        do {
            _ = try JSONAccess.dictionary([:], key: "planUsage")
            Issue.record("expected a failure")
        } catch UsageDataError.missingField(let field) {
            #expect(field == "planUsage")
        } catch {
            Issue.record("expected UsageDataError, got \(error)")
        }
    }

    @Test("Every shape of a payload a plugin cannot read is an unreadable response")
    func dataErrorsAreInvalidResponse() {
        #expect(UsageDataError.missingField("x").providerError.code == .invalidResponse)
        #expect(UsageDataError.invalidPeriod.providerError.code == .invalidResponse)
        #expect(UsageDataError.noUsableMeter.providerError.code == .invalidResponse)
    }
}

@Suite("Dates and days")
struct DayFormatTests {
    @Test("A day is written as the user's calendar day, not wherever the plugin runs")
    func dayString() {
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(DayFormat.string(from: instant) == "2025-10-09")

        // The same instant is the 8th in New York and the 9th in UTC; the wire
        // takes the UTC one so both sides name the same day.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = utc.dateComponents([.year, .month, .day], from: instant)
        #expect(parts.year == 2025 && parts.month == 10 && parts.day == 9)
    }

    @Test("An instant is read with or without fractional seconds")
    func instants() {
        let whole = DayFormat.instant(fromISO8601: "2026-10-17T12:00:00Z")
        let fractional = DayFormat.instant(fromISO8601: "2026-10-17T12:00:00.500Z")
        #expect(whole == Date(timeIntervalSince1970: 1_792_238_400))
        #expect(fractional == Date(timeIntervalSince1970: 1_792_238_400.5))
    }

    @Test("An instant is written whole, to the second, in UTC")
    func instantString() {
        #expect(DayFormat.instantString(from: Date(timeIntervalSince1970: 1_792_238_400)) == "2026-10-17T12:00:00Z")
        // The fraction is the serializer's detail, not the value's.
        #expect(DayFormat.instantString(from: Date(timeIntervalSince1970: 1_792_238_400.5)) == "2026-10-17T12:00:00Z")
    }

    @Test("Something that is not an instant is not read as one")
    func notAnInstant() {
        #expect(DayFormat.instant(fromISO8601: "17/10/2026") == nil)
        #expect(DayFormat.instant(fromISO8601: "") == nil)
    }
}

@Suite("The period a provider meters")
struct UsagePeriodTests {
    private let keys = (start: "billingCycleStart", end: "billingCycleEnd")

    @Test("Milliseconds since the epoch, sent as strings")
    func millisecondsStrings() throws {
        let json: [String: Any] = [
            "billingCycleStart": "1760000000000",
            "billingCycleEnd": "1762592000000",
        ]
        let period = try UsagePeriod.days(
            fromMillisecondsStrings: json,
            startKey: keys.start,
            endKey: keys.end
        )
        #expect(period.start == "2025-10-09")
        #expect(period.end == "2025-11-08")
    }

    @Test("ISO 8601 instants")
    func iso8601() throws {
        let json: [String: Any] = [
            "billingCycleStart": "2026-10-01T00:00:00.000Z",
            "billingCycleEnd": "2026-10-31T23:59:59Z",
        ]
        let period = try UsagePeriod.days(
            fromISO8601: json,
            startKey: keys.start,
            endKey: keys.end
        )
        #expect(period.start == "2026-10-01")
        #expect(period.end == "2026-10-31")
    }

    @Test("The window whole: milliseconds since the epoch arrive with their hour")
    func windowFromMillisecondsStrings() throws {
        let json: [String: Any] = [
            "billingCycleStart": "1790073992000",
            "billingCycleEnd": "1792665992000",
        ]
        let window = try UsagePeriod.window(
            fromMillisecondsStrings: json,
            startKey: keys.start,
            endKey: keys.end
        )
        #expect(window.start == "2026-09-22T10:46:32Z")
        #expect(window.end == "2026-10-22T10:46:32Z")
    }

    @Test("The window whole: ISO 8601 instants survive, fraction and all")
    func windowFromISO8601() throws {
        let json: [String: Any] = [
            "billingCycleStart": "2026-10-01T00:00:00.000Z",
            "billingCycleEnd": "2026-10-31T23:59:59Z",
        ]
        let window = try UsagePeriod.window(
            fromISO8601: json,
            startKey: keys.start,
            endKey: keys.end
        )
        #expect(window.start == "2026-10-01T00:00:00Z")
        #expect(window.end == "2026-10-31T23:59:59Z")
    }

    @Test("Boundaries that arrive as numbers rather than strings are still missing")
    func numbersAreNotStrings() {
        // Providers quote these on purpose — JavaScript numbers are too large
        // for some serializers to send whole — so a number arriving where a
        // string was promised is a payload this plugin does not recognise.
        let json: [String: Any] = [
            "billingCycleStart": 1_760_000_000_000,
            "billingCycleEnd": 1_762_592_000_000,
        ]
        #expect(throws: UsageDataError.self) {
            try UsagePeriod.days(
                fromMillisecondsStrings: json,
                startKey: keys.start,
                endKey: keys.end
            )
        }
    }

    @Test("A period that runs backwards is refused, not filed")
    func reversedPeriod() {
        let json: [String: Any] = [
            "billingCycleStart": "2026-10-31T00:00:00Z",
            "billingCycleEnd": "2026-10-01T00:00:00Z",
        ]
        do {
            _ = try UsagePeriod.days(
                fromISO8601: json,
                startKey: keys.start,
                endKey: keys.end
            )
            Issue.record("expected a failure")
        } catch UsageDataError.invalidPeriod {
            // Expected: this is the reading that would be filed against a
            // window that never happened.
        } catch {
            Issue.record("expected invalidPeriod, got \(error)")
        }
        // Whole instants are refused by the same rule: keeping the time does
        // not loosen the check the days were held to.
        #expect(throws: UsageDataError.self) {
            try UsagePeriod.window(
                fromISO8601: json,
                startKey: keys.start,
                endKey: keys.end
            )
        }
    }

    @Test("Missing boundaries say which fields were wanted")
    func missingBoundaries() {
        do {
            _ = try UsagePeriod.days(
                fromISO8601: [:],
                startKey: "cycleStart",
                endKey: "cycleEnd"
            )
            Issue.record("expected a failure")
        } catch UsageDataError.missingField(let field) {
            #expect(field == "cycleStart/cycleEnd")
        } catch {
            Issue.record("expected UsageDataError, got \(error)")
        }
    }
}

@Suite("Percentages")
struct PercentageTests {
    @Test("A reported figure is held to the meter it claims to be on")
    func clamp() {
        #expect(Percentage.clamp(11.5) == 11.5)
        #expect(Percentage.clamp(-3) == 0)
        #expect(Percentage.clamp(130) == 100)
        #expect(Percentage.clamp(0) == 0)
        #expect(Percentage.clamp(100) == 100)
    }

    @Test("Used over limit, when there is a limit to divide by")
    func share() {
        #expect(Percentage.of(used: 10, limit: 100) == 10)
        #expect(Percentage.of(used: 0, limit: 40) == 0)
        #expect(Percentage.of(used: 40, limit: 40) == 100)
    }

    @Test("With no allowance recorded, there is no reading at all — rather than a made-up one")
    func noLimitIsNoReading() {
        #expect(Percentage.of(used: 10, limit: 0) == nil)
        #expect(Percentage.of(used: 10, limit: -1) == nil)
        #expect(Percentage.of(used: 0, limit: 0) == nil)
    }
}
