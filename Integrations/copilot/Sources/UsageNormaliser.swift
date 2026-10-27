import Foundation
import PluginKit
import ProviderSupport

/// Turning Copilot's `copilot_internal/user` payload into `UsageResult`.
///
/// Copilot meters several pools under `quota_snapshots` (premium requests,
/// chat, completions). Free/limited accounts may instead report remaining
/// counters under `limited_user_quotas` against `monthly_quotas`. Snapshots
/// marked unlimited or without a quota are left out rather than guessed at.
enum UsageNormaliser {
    private struct KnownSnapshot {
        let key: String
        let displayName: String
    }

    private static let knownSnapshots: [KnownSnapshot] = [
        KnownSnapshot(
            key: CopilotConstants.premiumInteractionsKey,
            displayName: CopilotConstants.premiumInteractionsDisplayName
        ),
        KnownSnapshot(
            key: CopilotConstants.chatKey,
            displayName: CopilotConstants.chatDisplayName
        ),
        KnownSnapshot(
            key: CopilotConstants.completionsKey,
            displayName: CopilotConstants.completionsDisplayName
        ),
    ]

    static func usageResult(
        from json: [String: Any],
        updatedAtDay: String,
        now: Date = Date()
    ) throws -> UsageResult {
        let window = try periodWindow(from: json, now: now)
        var quotas: [ProviderUsage] = []

        if let snapshots = json[CopilotConstants.quotaSnapshotsKey] as? [String: Any] {
            for known in knownSnapshots {
                guard let snapshot = snapshots[known.key] as? [String: Any],
                      let usage = bucket(
                          id: known.key,
                          displayName: known.displayName,
                          snapshot: snapshot,
                          window: window,
                          updatedAtDay: updatedAtDay
                      )
                else { continue }
                quotas.append(usage)
            }
        }

        if quotas.isEmpty {
            quotas.append(contentsOf: limitedBuckets(
                from: json,
                window: window,
                updatedAtDay: updatedAtDay
            ))
        }

        guard !quotas.isEmpty else {
            throw UsageDataError.noUsableMeter
        }

        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    // MARK: Snapshots

    private static func bucket(
        id: String,
        displayName: String,
        snapshot: [String: Any],
        window: PeriodWindow,
        updatedAtDay: String
    ) -> ProviderUsage? {
        if let unlimited = snapshot["unlimited"] as? Bool, unlimited {
            return nil
        }
        if let hasQuota = snapshot["has_quota"] as? Bool, !hasQuota {
            return nil
        }
        guard let utilization = utilization(from: snapshot) else { return nil }
        return ProviderUsage(
            externalID: id,
            displayName: displayName,
            bucketID: id,
            bucketDisplayName: displayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: window.start,
            periodEnd: window.end,
            updatedAt: updatedAtDay
        )
    }

    /// Prefer exact counters; fall back to `percent_remaining`.
    private static func utilization(from snapshot: [String: Any]) -> Double? {
        let entitlement = JSONAccess.double(snapshot, key: "entitlement")
        let remaining = JSONAccess.double(snapshot, key: "remaining")
            ?? JSONAccess.double(snapshot, key: "quota_remaining")
        let creditsUsed = JSONAccess.double(snapshot, key: "credits_used")

        if let entitlement, entitlement > 0 {
            if let creditsUsed, let share = Percentage.of(used: creditsUsed, limit: entitlement) {
                return share
            }
            if let remaining, let share = Percentage.of(
                used: entitlement - remaining,
                limit: entitlement
            ) {
                return share
            }
        }

        if let percentRemaining = JSONAccess.double(snapshot, key: "percent_remaining") {
            return Percentage.scale - percentRemaining
        }

        return nil
    }

    // MARK: Free / limited counters

    private static func limitedBuckets(
        from json: [String: Any],
        window: PeriodWindow,
        updatedAtDay: String
    ) -> [ProviderUsage] {
        guard let remaining = json[CopilotConstants.limitedUserQuotasKey] as? [String: Any],
              let monthly = json[CopilotConstants.monthlyQuotasKey] as? [String: Any]
        else {
            return []
        }

        var usages: [ProviderUsage] = []
        for known in knownSnapshots where known.key != CopilotConstants.premiumInteractionsKey {
            guard let left = JSONAccess.double(remaining, key: known.key),
                  let limit = JSONAccess.double(monthly, key: known.key),
                  let share = Percentage.of(used: limit - left, limit: limit)
            else { continue }
            usages.append(
                ProviderUsage(
                    externalID: known.key,
                    displayName: known.displayName,
                    bucketID: known.key,
                    bucketDisplayName: known.displayName,
                    usagePercentage: Percentage.clamp(share),
                    periodStart: window.start,
                    periodEnd: window.end,
                    updatedAt: updatedAtDay
                )
            )
        }
        return usages
    }

    // MARK: Period

    /// The billing window ending at Copilot's reset instant.
    ///
    /// Copilot reports when the quota turns over, not when the current period
    /// began. The window is taken as one calendar month ending at that reset,
    /// which matches the monthly cycle the endpoint describes.
    private static func periodWindow(from json: [String: Any], now: Date) throws -> PeriodWindow {
        if let reset = resetDate(from: json) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            guard let start = calendar.date(byAdding: .month, value: -1, to: reset),
                  start <= reset
            else {
                throw UsageDataError.invalidPeriod
            }
            return PeriodWindow(
                start: DayFormat.instantString(from: start),
                end: DayFormat.instantString(from: reset)
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let interval = calendar.dateInterval(of: .month, for: now) else {
            throw UsageDataError.invalidPeriod
        }
        return PeriodWindow(
            start: DayFormat.instantString(from: interval.start),
            end: DayFormat.instantString(from: interval.end)
        )
    }

    private static func resetDate(from json: [String: Any]) -> Date? {
        if let text = JSONAccess.string(json, key: CopilotConstants.quotaResetDateUTCKey),
           let date = DayFormat.instant(fromISO8601: text)
        {
            return date
        }
        if let text = JSONAccess.string(json, key: CopilotConstants.quotaResetDateKey) {
            if let date = DayFormat.instant(fromISO8601: text) {
                return date
            }
            // Date-only values such as `2026-11-01`.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: text)
        }
        if let text = JSONAccess.string(json, key: CopilotConstants.limitedUserResetDateKey) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: text)
        }
        return nil
    }
}
