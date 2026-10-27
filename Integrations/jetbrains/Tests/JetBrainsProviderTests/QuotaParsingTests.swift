import Foundation
import PluginKit
import ProviderSupport
import Testing
@testable import QuotaPluginJetBrains

@Suite("JetBrains quota XML parsing")
struct QuotaParsingTests {
    private let day = "2026-10-27"

    @Test("Tariff quota becomes the monthly meter")
    func tariffQuota() throws {
        let snapshot = try QuotaFileParser.parse(xml: try JetBrainsFixture.xml("quota-tariff"))
        #expect(snapshot.used == 7478.3)
        #expect(snapshot.maximum == 1_000_000)
        #expect(snapshot.available == 992_521.7)
        #expect(snapshot.refillDuration == "PT720H")
        #expect(snapshot.refillNext == DayFormat.instant(fromISO8601: "2026-01-16T14:00:54Z"))

        let result = try UsageNormaliser.usageResult(from: snapshot, updatedAtDay: day)
        let plan = try #require(result.quotas.first { $0.bucketID == "plan" })
        #expect(abs(plan.usagePercentage - 0.74783) < 0.0001)
        #expect(plan.periodEnd == "2026-01-16T14:00:54Z")
        #expect(plan.periodStart == "2025-12-17T14:00:54Z")
        #expect(result.quotas.allSatisfy { $0.bucketID != "topup" })
    }

    @Test("Top-up credits are a separate bucket; monthly ignores inflated totals")
    func topUpBucket() throws {
        let snapshot = try QuotaFileParser.parse(xml: try JetBrainsFixture.xml("quota-with-topup"))
        #expect(snapshot.used == 346_000)
        #expect(snapshot.maximum == 1_000_000)
        #expect(abs(snapshot.usedPercent - 34.6) < 0.001)

        let result = try UsageNormaliser.usageResult(from: snapshot, updatedAtDay: day)
        let plan = try #require(result.quotas.first { $0.bucketID == "plan" })
        #expect(abs(plan.usagePercentage - 34.6) < 0.001)

        let topUp = try #require(result.quotas.first { $0.bucketID == "topup" })
        #expect(topUp.usagePercentage == 0.0)
    }

    @Test("Flat quota without tariffQuota still meters")
    func flatQuota() throws {
        let snapshot = try QuotaFileParser.parse(xml: try JetBrainsFixture.xml("quota-flat"))
        #expect(snapshot.used == 75)
        #expect(snapshot.maximum == 100)
        #expect(snapshot.usedPercent == 75)

        let result = try UsageNormaliser.usageResult(from: snapshot, updatedAtDay: day)
        let plan = try #require(result.quotas.first)
        #expect(plan.usagePercentage == 75)
        #expect(plan.periodEnd == "2099-01-01T00:00:00Z")
    }

    @Test("PT720H is thirty days")
    func durationParsing() {
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        #expect(UsageNormaliser.durationSeconds("PT720H") == thirtyDays)
        #expect(UsageNormaliser.durationSeconds("P30D") == thirtyDays)
        #expect(UsageNormaliser.durationSeconds("30d") == thirtyDays)
        #expect(UsageNormaliser.durationSeconds("monthly") == thirtyDays)
        #expect(UsageNormaliser.durationSeconds(nil) == nil)
    }

    @Test("Missing quotaInfo is refused")
    func missingQuotaInfo() {
        let xml = Data("""
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="{}" />
          </component>
        </application>
        """.utf8)
        #expect(throws: JetBrainsProviderError.invalidQuotaFile) {
            try QuotaFileParser.parse(xml: xml)
        }
    }
}
