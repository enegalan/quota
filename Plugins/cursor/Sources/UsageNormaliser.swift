import Foundation
import PluginKit
import ProviderSupport

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
        let period = try UsagePeriod.days(
            fromMillisecondsStrings: json,
            startKey: CursorConstants.billingStartKey,
            endKey: CursorConstants.billingEndKey
        )
        let planUsage = try JSONAccess.dictionary(json, key: "planUsage")
        return try makeResult(plan: planUsage, period: period, updatedAtDay: updatedAtDay)
    }

    static func usageResult(
        fromUsageSummary json: [String: Any],
        updatedAtDay: String
    ) throws -> UsageResult {
        let period = try UsagePeriod.days(
            fromISO8601: json,
            startKey: CursorConstants.billingStartKey,
            endKey: CursorConstants.billingEndKey
        )
        let individual = try JSONAccess.dictionary(json, key: "individualUsage")
        let plan = try JSONAccess.dictionary(individual, key: "plan")
        return try makeResult(plan: plan, period: period, updatedAtDay: updatedAtDay)
    }

    private static func makeResult(
        plan: [String: Any],
        period: PeriodDays,
        updatedAtDay: String
    ) throws -> UsageResult {
        let planPercentage = try planUsagePercentage(plan)
        let apiPercentage = JSONAccess.double(plan, key: "apiPercentUsed") ?? 0

        let quotas = [
            ProviderUsage(
                externalID: CursorConstants.planExternalID,
                displayName: CursorConstants.planBucketDisplayName,
                bucketID: CursorConstants.planBucketID,
                bucketDisplayName: CursorConstants.planBucketDisplayName,
                usagePercentage: Percentage.clamp(planPercentage),
                periodStart: period.start,
                periodEnd: period.end,
                updatedAt: updatedAtDay
            ),
            ProviderUsage(
                externalID: CursorConstants.apiExternalID,
                displayName: CursorConstants.apiBucketDisplayName,
                bucketID: CursorConstants.apiBucketID,
                bucketDisplayName: CursorConstants.apiBucketDisplayName,
                usagePercentage: Percentage.clamp(apiPercentage),
                periodStart: period.start,
                periodEnd: period.end,
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
        if let reported = JSONAccess.double(plan, key: "autoPercentUsed")
            ?? JSONAccess.double(plan, key: "totalPercentUsed")
        {
            return reported
        }
        if let used = JSONAccess.double(plan, key: "includedSpend")
            ?? JSONAccess.double(plan, key: "used"),
            let limit = JSONAccess.double(plan, key: "limit"),
            let share = Percentage.of(used: used, limit: limit)
        {
            return share
        }
        throw UsageDataError.noUsableMeter
    }
}
