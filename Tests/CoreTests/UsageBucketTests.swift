import Foundation
import Testing
@testable import Core

/// A fixed calendar so every assertion holds in every time zone.
let quotaCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    return calendar
}()

func quotaInstant(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0
) throws -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour)
    return try #require(quotaCalendar.date(from: components))
}

/// A period covering whole calendar days, from the first day's start to the
/// last day's end.
///
/// Quota can be spent on the final day up until midnight, so the end is the last
/// moment of that day rather than its first; treating the end as midnight would
/// report the period as expired for the whole of its final day.
func quotaPeriod(from start: String, to end: String) throws -> QuotaPeriod {
    let firstDay = try LocalDate(iso: start)
    let lastDay = try LocalDate(iso: end)
    let startDate = try #require(firstDay.date(calendar: quotaCalendar))
    let endDate = try #require(
        lastDay.adding(days: 1, calendar: quotaCalendar)?
            .date(calendar: quotaCalendar)?
            .addingTimeInterval(-1)
    )
    return try QuotaPeriod(start: startDate, end: endDate)
}

/// A window to hang on a bucket that is not about its period.
///
/// Shared so the assertions in this suite stay about the figure and the
/// identifier; `UsageSnapshotTests` and `SyncCoordinatorTests` are where two
/// windows on purpose are covered.
func samplePeriod() throws -> QuotaPeriod {
    try quotaPeriod(from: "2026-01-01", to: "2026-01-31")
}

@Suite("UsageBucket")
struct UsageBucketTests {
    @Test("A bucket accepts the inclusive bounds")
    func acceptsBounds() throws {
        #expect(try UsageBucket(
            id: "a", displayName: "A", usagePercentage: 0, period: samplePeriod()
        ).usagePercentage == 0)
        #expect(try UsageBucket(
            id: "a", displayName: "A", usagePercentage: 100, period: samplePeriod()
        ).usagePercentage == 100)
    }

    @Test("A bucket rejects percentages outside the range")
    func rejectsOutOfRange() throws {
        for value in [-0.1, -1, 100.1, 200, 1e9] {
            #expect(throws: QuotaDomainError.self) {
                try UsageBucket(
                    id: "a", displayName: "A", usagePercentage: value, period: samplePeriod()
                )
            }
        }
    }

    @Test("A bucket rejects values that are not finite numbers")
    func rejectsNonFinite() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: QuotaDomainError.self) {
                try UsageBucket(
                    id: "a", displayName: "A", usagePercentage: value, period: samplePeriod()
                )
            }
        }
    }

    @Test("A bucket accepts every value inside the range")
    func acceptsInsideRange() throws {
        for value in [0.0, 0.01, 50.0, 99.99, 100.0] {
            #expect(try UsageBucket(
                id: "a", displayName: "A", usagePercentage: value, period: samplePeriod()
            ).usagePercentage == value)
        }
    }

    @Test("A bucket rejects an invalid identifier")
    func rejectsInvalidIdentifier() throws {
        for invalid in ["", " ", "has space", "tab\there"] {
            #expect(throws: QuotaDomainError.self) {
                try UsageBucket(
                    id: invalid, displayName: "A", usagePercentage: 50, period: samplePeriod()
                )
            }
        }
    }

    @Test("A limit description is optional and never affects validation")
    func limitDescription() throws {
        let without = try UsageBucket(
            id: "a", displayName: "A", usagePercentage: 50, period: samplePeriod()
        )
        let with = try UsageBucket(
            id: "a", displayName: "A", usagePercentage: 50, period: samplePeriod(),
            limitDescription: "$20 included"
        )
        #expect(without.limitDescription == nil)
        #expect(with.limitDescription == "$20 included")
        #expect(without.usagePercentage == with.usagePercentage)
    }

    @Test("A bucket carries the window its figure is measured over")
    func keepsItsOwnPeriod() throws {
        let window = try quotaPeriod(from: "2026-01-01", to: "2026-01-07")
        let bucket = try UsageBucket(
            id: "session", displayName: "Session", usagePercentage: 10, period: window
        )
        #expect(bucket.period == window)
    }

    @Test("Decoding rejects an out-of-range percentage")
    func decodingValidates() throws {
        let json = """
        {"id":"a","displayName":"A","usagePercentage":150.0,\
        "period":{"start":0,"end":1}}
        """
        #expect(throws: QuotaDomainError.self) {
            try JSONDecoder().decode(UsageBucket.self, from: Data(json.utf8))
        }
    }

    @Test("Decoding rejects a bucket stored without a window")
    func decodingRequiresPeriod() {
        let json = """
        {"id":"a","displayName":"A","usagePercentage":50.0}
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(UsageBucket.self, from: Data(json.utf8))
        }
    }

    @Test("A bucket round trips through Codable")
    func codableRoundTrip() throws {
        let bucket = try UsageBucket(
            id: "models", displayName: "Models", usagePercentage: 42.5,
            period: samplePeriod(), limitDescription: "500 requests"
        )
        let data = try JSONEncoder().encode(bucket)
        #expect(try JSONDecoder().decode(UsageBucket.self, from: data) == bucket)
    }
}
