import Core
import Foundation
import Testing

@Suite("Provider independence")
struct FictionalProviderTests {
    @Test("A second fictional provider needs no engine changes")
    func fictionalProviderPlansWithoutEngineChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let engine = AllocationEngine(calendar: calendar)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86400 * 6)
        let period = try QuotaPeriod(start: start, end: end)

        // Entirely fictional: no Cursor knowledge in Core is required.
        let plan = try engine.plan(
            quotaID: UUID(),
            policy: .even,
            period: period,
            totalRemaining: 70,
            asOf: start
        )
        #expect(plan.allocations.count == 7)
        let sum = plan.allocations.reduce(0.0) { $0 + $1.percentage }
        #expect(abs(sum - 70) < UsageConstants.percentageRoundingTolerance)
    }
}
