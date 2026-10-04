import Core
import Foundation
import PluginKit
import Testing

enum CursorFixtureLoader {
    static func json(_ name: String) throws -> [String: Any] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    static func numeric(_ object: [String: Any], _ key: String) throws -> Double {
        if let value = object[key] as? Double {
            return value
        }
        if let value = object[key] as? Int {
            return Double(value)
        }
        if let value = object[key] as? NSNumber {
            return value.doubleValue
        }
        Issue.record("missing \(key)")
        return 0
    }

    /// Mirrors the plugin's percentage rule and period formatting for fixtures.
    static func usageResult(fromCurrentPeriod json: [String: Any], day: String) throws -> UsageResult {
        let plan = try #require(json["planUsage"] as? [String: Any])
        let startMs = try #require(Double(json["billingCycleStart"] as? String ?? ""))
        let endMs = try #require(Double(json["billingCycleEnd"] as? String ?? ""))
        let start = dayString(Date(timeIntervalSince1970: startMs / 1000))
        let end = dayString(Date(timeIntervalSince1970: endMs / 1000))
        let planPercent = try planUsagePercentage(plan)
        let apiPercent = try numeric(plan, "apiPercentUsed")
        return UsageResult(
            quotas: [
                ProviderUsage(
                    externalID: "cursor-plan",
                    displayName: "Included plan",
                    bucketID: "plan",
                    bucketDisplayName: "Included plan",
                    usagePercentage: planPercent,
                    periodStart: start,
                    periodEnd: end,
                    updatedAt: day
                ),
                ProviderUsage(
                    externalID: "cursor-api",
                    displayName: "API / named models",
                    bucketID: "api",
                    bucketDisplayName: "API / named models",
                    usagePercentage: apiPercent,
                    periodStart: start,
                    periodEnd: end,
                    updatedAt: day
                ),
            ]
        )
    }

    static func usageResult(fromSummary json: [String: Any], day: String) throws -> UsageResult {
        let individual = try #require(json["individualUsage"] as? [String: Any])
        let plan = try #require(individual["plan"] as? [String: Any])
        let start = dayString(try parseISO(try #require(json["billingCycleStart"] as? String)))
        let end = dayString(try parseISO(try #require(json["billingCycleEnd"] as? String)))
        let planPercent = try planUsagePercentage(plan)
        let apiPercent = try numeric(plan, "apiPercentUsed")
        return UsageResult(
            quotas: [
                ProviderUsage(
                    externalID: "cursor-plan",
                    displayName: "Included plan",
                    bucketID: "plan",
                    bucketDisplayName: "Included plan",
                    usagePercentage: planPercent,
                    periodStart: start,
                    periodEnd: end,
                    updatedAt: day
                ),
                ProviderUsage(
                    externalID: "cursor-api",
                    displayName: "API / named models",
                    bucketID: "api",
                    bucketDisplayName: "API / named models",
                    usagePercentage: apiPercent,
                    periodStart: start,
                    periodEnd: end,
                    updatedAt: day
                ),
            ]
        )
    }

    /// Same rule as the plugin: percent fields first, cents as fallback.
    private static func planUsagePercentage(_ plan: [String: Any]) throws -> Double {
        if plan["autoPercentUsed"] != nil {
            return try numeric(plan, "autoPercentUsed")
        }
        if plan["totalPercentUsed"] != nil {
            return try numeric(plan, "totalPercentUsed")
        }
        let used: Double = if plan["includedSpend"] != nil {
            try numeric(plan, "includedSpend")
        } else {
            try numeric(plan, "used")
        }
        let limit = try numeric(plan, "limit")
        guard limit > 0 else { return 0 }
        return used / limit * UsageConstants.percentageScale
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseISO(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return try #require(basic.date(from: value))
    }
}
