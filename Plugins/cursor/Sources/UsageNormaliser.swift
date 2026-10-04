import Foundation
import PluginKit

enum UsageNormaliserError: Error, Equatable {
    case missingField(String)
    case invalidPeriod
    case noUsableMeter
}

/// Maps Cursor dashboard JSON into `UsageResult` (plugin wire format).
///
/// Percentage rule: prefer `autoPercentUsed` / `totalPercentUsed` (what Cursor's
/// UI shows). Fall back to `includedSpend|used / limit` only when no percent
/// field is present — those cents fields can sit at the cap while the percent
/// meter is still low.
enum UsageNormaliser {
    static func usageResult(
        fromCurrentPeriod json: [String: Any],
        updatedAtDay: String
    ) throws -> UsageResult {
        let period = try periodFromMillisecondStrings(json)
        let planUsage = try dictionary(json, key: "planUsage")
        return try makeResult(
            plan: planUsage,
            periodStart: period.start,
            periodEnd: period.end,
            updatedAtDay: updatedAtDay
        )
    }

    static func usageResult(
        fromUsageSummary json: [String: Any],
        updatedAtDay: String
    ) throws -> UsageResult {
        let period = try periodFromISO8601(json)
        let individual = try dictionary(json, key: "individualUsage")
        let plan = try dictionary(individual, key: "plan")
        return try makeResult(
            plan: plan,
            periodStart: period.start,
            periodEnd: period.end,
            updatedAtDay: updatedAtDay
        )
    }

    private static func makeResult(
        plan: [String: Any],
        periodStart: String,
        periodEnd: String,
        updatedAtDay: String
    ) throws -> UsageResult {
        let planPercentage = try planUsagePercentage(plan)
        let apiPercentage = double(plan, key: "apiPercentUsed") ?? CursorConstants.minimumPercentage

        let quotas = [
            ProviderUsage(
                externalID: CursorConstants.planExternalID,
                displayName: CursorConstants.planBucketDisplayName,
                bucketID: CursorConstants.planBucketID,
                bucketDisplayName: CursorConstants.planBucketDisplayName,
                usagePercentage: clamp(planPercentage),
                periodStart: periodStart,
                periodEnd: periodEnd,
                updatedAt: updatedAtDay
            ),
            ProviderUsage(
                externalID: CursorConstants.apiExternalID,
                displayName: CursorConstants.apiBucketDisplayName,
                bucketID: CursorConstants.apiBucketID,
                bucketDisplayName: CursorConstants.apiBucketDisplayName,
                usagePercentage: clamp(apiPercentage),
                periodStart: periodStart,
                periodEnd: periodEnd,
                updatedAt: updatedAtDay
            ),
        ]
        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    /// Percentage of plan usage as Cursor's own UI reports it.
    ///
    /// Prefer `autoPercentUsed` / `totalPercentUsed`: those match the dashboard
    /// copy ("You've used X% of your included total usage"). The cents fields
    /// `includedSpend`/`used`/`limit` are a different meter that can sit at the
    /// cap (e.g. 2000/2000) while the percent meter is still ~14%.
    static func planUsagePercentage(_ plan: [String: Any]) throws -> Double {
        if let reported = double(plan, key: "autoPercentUsed")
            ?? double(plan, key: "totalPercentUsed")
        {
            return reported
        }
        if let used = double(plan, key: "includedSpend") ?? double(plan, key: "used"),
           let limit = double(plan, key: "limit"),
           limit > 0
        {
            return used / limit * CursorConstants.percentageScale
        }
        throw UsageNormaliserError.noUsableMeter
    }

    private struct PeriodDays {
        let start: String
        let end: String
    }

    private static func periodFromMillisecondStrings(_ json: [String: Any]) throws -> PeriodDays {
        guard let startRaw = string(json, key: "billingCycleStart"),
              let endRaw = string(json, key: "billingCycleEnd"),
              let startMillis = Double(startRaw),
              let endMillis = Double(endRaw)
        else {
            throw UsageNormaliserError.missingField("billingCycleStart/End")
        }
        let start = Date(timeIntervalSince1970: startMillis / CursorConstants.millisecondsPerSecond)
        let end = Date(timeIntervalSince1970: endMillis / CursorConstants.millisecondsPerSecond)
        guard start <= end else { throw UsageNormaliserError.invalidPeriod }
        return PeriodDays(start: dayString(start), end: dayString(end))
    }

    private static func periodFromISO8601(_ json: [String: Any]) throws -> PeriodDays {
        guard let startRaw = string(json, key: "billingCycleStart"),
              let endRaw = string(json, key: "billingCycleEnd"),
              let start = parseISO8601(startRaw),
              let end = parseISO8601(endRaw)
        else {
            throw UsageNormaliserError.missingField("billingCycleStart/End")
        }
        guard start <= end else { throw UsageNormaliserError.invalidPeriod }
        return PeriodDays(start: dayString(start), end: dayString(end))
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    private static func clamp(_ value: Double) -> Double {
        min(
            max(value, CursorConstants.minimumPercentage),
            CursorConstants.maximumPercentage
        )
    }

    private static func dictionary(_ json: [String: Any], key: String) throws -> [String: Any] {
        guard let value = json[key] as? [String: Any] else {
            throw UsageNormaliserError.missingField(key)
        }
        return value
    }

    private static func string(_ json: [String: Any], key: String) -> String? {
        json[key] as? String
    }

    private static func double(_ json: [String: Any], key: String) -> Double? {
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
