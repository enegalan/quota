import Foundation
import PluginKit
import ProviderSupport

/// Turning Antigravity's usage payload into `UsageResult` (plugin wire format).
enum UsageNormaliser {
    static func usageResult(from json: [String: Any], updatedAtDay: String) throws -> UsageResult {
        var quotas: [ProviderUsage] = []
        quotas.append(contentsOf: quotas(from: json, updatedAtDay: updatedAtDay))

        if quotas.isEmpty {
            quotas.append(contentsOf: quotas(from: json["usage"] as? [String: Any], updatedAtDay: updatedAtDay))
            quotas.append(contentsOf: quotas(from: json["quota"] as? [String: Any], updatedAtDay: updatedAtDay))
        }

        guard !quotas.isEmpty else {
            throw UsageDataError.noUsableMeter
        }

        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    private static func quotas(from json: [String: Any]?, updatedAtDay: String) -> [ProviderUsage] {
        guard let json else { return [] }
        var result: [ProviderUsage] = []
        if let credits = extractCredits(from: json, updatedAtDay: updatedAtDay) {
            result.append(credits)
        }
        if let plan = extractPlanUsage(from: json, updatedAtDay: updatedAtDay) {
            result.append(plan)
        }
        return result
    }

    private static func readDouble(_ json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = JSONAccess.double(json, key: key) {
                return value
            }
        }
        return nil
    }

    private static func readString(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = JSONAccess.string(json, key: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func computeUtilization(from json: [String: Any]) -> Double? {
        let used = readDouble(json, keys: ["usedCredits", "used_credits", "creditsUsed", "used"])
        let limit = readDouble(json, keys: ["totalCredits", "total_credits", "creditsLimit", "limit", "quota"])
        let remaining = readDouble(json, keys: ["remainingCredits", "remaining_credits"])

        if let used, let limit, limit > 0 {
            return Percentage.of(used: used, limit: limit)
        }
        if let used, let remaining, (used + remaining) > 0 {
            return Percentage.of(used: used, limit: used + remaining)
        }
        if let value = readDouble(json, keys: ["utilization", "usagePercentage", "percentUsed"]) {
            return value
        }
        return nil
    }

    private static func defaultPeriod() -> (start: String, end: String) {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        if let interval = calendar.dateInterval(of: .month, for: now) {
            return (
                DayFormat.instantString(from: interval.start),
                DayFormat.instantString(from: interval.end)
            )
        }
        return ("", "")
    }

    private static func period(from json: [String: Any]) -> (start: String, end: String) {
        let fallback = defaultPeriod()
        var start = ""
        var end = ""

        if let raw = readString(json, keys: ["periodStart", "period_start", "billingCycleStart", "startDate"]) {
            if let date = DayFormat.instant(fromISO8601: raw) {
                start = DayFormat.instantString(from: date)
            } else {
                start = raw
            }
        }
        if let raw = readString(
            json,
            keys: ["periodEnd", "period_end", "billingCycleEnd", "endDate", "resetAt", "resetsAt"]
        ) {
            if let date = DayFormat.instant(fromISO8601: raw) {
                end = DayFormat.instantString(from: date)
            } else {
                end = raw
            }
        }

        return (
            start.isEmpty ? fallback.start : start,
            end.isEmpty ? fallback.end : end
        )
    }

    private static func extractCredits(from json: [String: Any], updatedAtDay: String) -> ProviderUsage? {
        guard let utilization = computeUtilization(from: json) else { return nil }
        let window = period(from: json)
        return ProviderUsage(
            externalID: AntigravityConstants.creditsBucketID,
            displayName: AntigravityConstants.creditsBucketDisplayName,
            bucketID: AntigravityConstants.creditsBucketID,
            bucketDisplayName: AntigravityConstants.creditsBucketDisplayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: window.start,
            periodEnd: window.end,
            updatedAt: updatedAtDay
        )
    }

    private static func extractPlanUsage(from json: [String: Any], updatedAtDay: String) -> ProviderUsage? {
        guard let plan = json["plan"] as? [String: Any] else { return nil }
        let used = readDouble(plan, keys: ["used"]) ?? readDouble(json, keys: ["planUsed"])
        let limit = readDouble(plan, keys: ["limit"]) ?? readDouble(json, keys: ["planLimit"])
        guard let used, let limit, limit > 0,
              let utilization = Percentage.of(used: used, limit: limit) else { return nil }

        let fallback = defaultPeriod()
        var start = readString(plan, keys: ["periodStart", "start"]) ?? ""
        var end = readString(plan, keys: ["periodEnd", "end"]) ?? ""
        if start.isEmpty {
            start = fallback.start
        }
        if end.isEmpty {
            end = fallback.end
        }

        return ProviderUsage(
            externalID: AntigravityConstants.planBucketID,
            displayName: AntigravityConstants.planBucketDisplayName,
            bucketID: AntigravityConstants.planBucketID,
            bucketDisplayName: AntigravityConstants.planBucketDisplayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: start,
            periodEnd: end,
            updatedAt: updatedAtDay
        )
    }
}
