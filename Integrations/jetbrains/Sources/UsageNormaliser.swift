import Foundation
import PluginKit
import ProviderSupport

/// Turning a parsed JetBrains quota snapshot into `UsageResult`.
enum UsageNormaliser {
    static func usageResult(
        from snapshot: QuotaSnapshot,
        updatedAtDay: String,
        now: Date = Date()
    ) throws -> UsageResult {
        let window = periodWindow(from: snapshot, now: now)
        var quotas: [ProviderUsage] = [
            ProviderUsage(
                externalID: JetBrainsConstants.planBucketID,
                displayName: JetBrainsConstants.planBucketDisplayName,
                bucketID: JetBrainsConstants.planBucketID,
                bucketDisplayName: JetBrainsConstants.planBucketDisplayName,
                usagePercentage: Percentage.clamp(snapshot.usedPercent),
                periodStart: window.start,
                periodEnd: window.end,
                updatedAt: updatedAtDay
            ),
        ]

        if let topUp = topUpUsage(from: snapshot, window: window, updatedAtDay: updatedAtDay) {
            quotas.append(topUp)
        }

        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    /// Purchased top-up credits, when the IDE reports a positive maximum.
    ///
    /// JetBrains spends top-ups only after the monthly quota is gone. The meter
    /// is still a used/limit percentage so Quota can pace what remains.
    private static func topUpUsage(
        from snapshot: QuotaSnapshot,
        window: PeriodWindow,
        updatedAtDay: String
    ) -> ProviderUsage? {
        guard let maximum = snapshot.topUpMaximum, maximum > 0 else { return nil }
        let available = snapshot.topUpAvailable ?? 0
        guard available.isFinite, available >= 0 else { return nil }
        let used = snapshot.topUpUsed ?? max(0, maximum - available)
        guard let share = Percentage.of(used: used, limit: maximum) else { return nil }
        return ProviderUsage(
            externalID: JetBrainsConstants.topUpBucketID,
            displayName: JetBrainsConstants.topUpBucketDisplayName,
            bucketID: JetBrainsConstants.topUpBucketID,
            bucketDisplayName: JetBrainsConstants.topUpBucketDisplayName,
            usagePercentage: Percentage.clamp(share),
            periodStart: window.start,
            periodEnd: window.end,
            updatedAt: updatedAtDay
        )
    }

    /// Window ending at the next refill (or `until`), lasting the tariff duration.
    private static func periodWindow(from snapshot: QuotaSnapshot, now: Date) -> PeriodWindow {
        let end = snapshot.refillNext ?? snapshot.until ?? now.addingTimeInterval(
            JetBrainsConstants.defaultPeriodSeconds
        )
        let duration = durationSeconds(snapshot.refillDuration)
            ?? JetBrainsConstants.defaultPeriodSeconds
        let start = end.addingTimeInterval(-duration)
        return PeriodWindow(
            start: DayFormat.instantString(from: min(start, end)),
            end: DayFormat.instantString(from: max(start, end))
        )
    }

    /// ISO-8601 durations JetBrains uses (`PT720H`, `P30D`) and plain `30d`.
    static func durationSeconds(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("monthly") == .orderedSame {
            return JetBrainsConstants.defaultPeriodSeconds
        }

        let lower = trimmed.lowercased()
        if lower.hasSuffix("d"),
           !lower.hasPrefix("p"),
           let days = Double(lower.dropLast()),
           days > 0
        {
            return days * 24 * 60 * 60
        }

        guard trimmed.uppercased().hasPrefix("P") else { return nil }
        return iso8601DurationSeconds(trimmed.uppercased())
    }

    private static func iso8601DurationSeconds(_ raw: String) -> TimeInterval? {
        // Enough for JetBrains' `PT720H` / `P30D` spellings — not a full ISO parser.
        var body = String(raw.dropFirst()) // drop leading P
        var total: TimeInterval = 0
        var matched = false

        if let days = takeLeadingQuantity(&body, suffix: "D") {
            total += days * 24 * 60 * 60
            matched = true
        }
        if body.hasPrefix("T") {
            body.removeFirst()
            if let hours = takeLeadingQuantity(&body, suffix: "H") {
                total += hours * 60 * 60
                matched = true
            }
            if let minutes = takeLeadingQuantity(&body, suffix: "M") {
                total += minutes * 60
                matched = true
            }
            if let seconds = takeLeadingQuantity(&body, suffix: "S") {
                total += seconds
                matched = true
            }
        }

        guard matched, body.isEmpty else { return nil }
        return total
    }

    private static func takeLeadingQuantity(_ body: inout String, suffix: Character) -> Double? {
        var digits = ""
        while let first = body.first, first.isNumber {
            digits.append(first)
            body.removeFirst()
        }
        guard !digits.isEmpty, body.first == suffix, let value = Double(digits) else {
            body = digits + body
            return nil
        }
        body.removeFirst()
        return value
    }
}
