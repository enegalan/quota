import Foundation
import PluginKit
import ProviderSupport

/// Turning Codex's `/wham/usage` payload into `UsageResult`.
///
/// Codex meters a primary window and an optional secondary one that turn over
/// on different clocks (typically five hours and a week). Each one becomes its
/// own bucket with its own window. Additional feature-scoped limits, when
/// present, become buckets of their own.
enum UsageNormaliser {
    /// The buckets Codex reported.
    static func usageResult(
        from json: [String: Any],
        updatedAtDay: String
    ) throws -> UsageResult {
        var quotas: [ProviderUsage] = []

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            if let usage = windowBucket(
                from: rateLimit["primary_window"] as? [String: Any],
                bucketID: CodexConstants.primaryBucketID,
                preferredName: CodexConstants.primaryDisplayName,
                updatedAtDay: updatedAtDay
            ) {
                quotas.append(usage)
            }
            if let usage = windowBucket(
                from: rateLimit["secondary_window"] as? [String: Any],
                bucketID: CodexConstants.secondaryBucketID,
                preferredName: CodexConstants.secondaryDisplayName,
                updatedAtDay: updatedAtDay
            ) {
                quotas.append(usage)
            }
        }

        quotas.append(contentsOf: additionalBuckets(from: json, updatedAtDay: updatedAtDay))

        guard !quotas.isEmpty else {
            throw UsageDataError.noUsableMeter
        }
        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    // MARK: Windows

    /// One rate-limit window as a bucket, or nil when it cannot be paced.
    ///
    /// A window without `used_percent`, without a reset instant, or without a
    /// duration is left out rather than guessed at.
    private static func windowBucket(
        from payload: [String: Any]?,
        bucketID: String,
        preferredName: String?,
        updatedAtDay: String
    ) -> ProviderUsage? {
        guard let payload,
              let utilization = JSONAccess.double(payload, key: "used_percent"),
              let windowSeconds = JSONAccess.double(payload, key: "limit_window_seconds"),
              windowSeconds > 0,
              let reset = resetInstant(in: payload)
        else { return nil }

        let displayName = preferredName ?? windowDisplayName(seconds: windowSeconds)
        return ProviderUsage(
            externalID: bucketID,
            displayName: displayName,
            bucketID: bucketID,
            bucketDisplayName: displayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: DayFormat.instantString(from: reset.addingTimeInterval(-windowSeconds)),
            periodEnd: DayFormat.instantString(from: reset),
            updatedAt: updatedAtDay
        )
    }

    /// The instant a window turns over.
    ///
    /// Prefers absolute `reset_at` (Unix seconds). Falls back to
    /// `reset_after_seconds` counted from now only when the absolute instant
    /// is absent — relative figures alone still give a usable end.
    private static func resetInstant(in payload: [String: Any], now: Date = Date()) -> Date? {
        if let resetAt = JSONAccess.double(payload, key: "reset_at") {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let after = JSONAccess.double(payload, key: "reset_after_seconds") {
            return now.addingTimeInterval(after)
        }
        return nil
    }

    /// A human name for a window duration the preferred label does not cover.
    private static func windowDisplayName(seconds: Double) -> String {
        if abs(seconds - CodexConstants.fiveHourSeconds) < 1 {
            return CodexConstants.primaryDisplayName
        }
        if abs(seconds - CodexConstants.sevenDaySeconds) < 1 {
            return CodexConstants.secondaryDisplayName
        }
        let hours = seconds / 3600
        if hours == floor(hours), hours >= 1 {
            let value = Int(hours)
            return value == 1 ? "1-hour window" : "\(value)-hour window"
        }
        let days = seconds / 86400
        if days == floor(days), days >= 1 {
            let value = Int(days)
            return value == 1 ? "1-day window" : "\(value)-day window"
        }
        return "Usage window"
    }

    // MARK: Additional limits

    /// Feature-scoped limits nested under `additional_rate_limits`.
    private static func additionalBuckets(
        from json: [String: Any],
        updatedAtDay: String
    ) -> [ProviderUsage] {
        guard let limits = json["additional_rate_limits"] as? [[String: Any]] else { return [] }
        var usages: [ProviderUsage] = []
        for limit in limits {
            let name = (limit["limit_name"] as? String)
                ?? (limit["metered_feature"] as? String)
            guard let name, !name.isEmpty else { continue }
            let rateLimit = limit["rate_limit"] as? [String: Any]
            let window = (rateLimit?["primary_window"] as? [String: Any])
                ?? (limit["primary_window"] as? [String: Any])
            guard let usage = windowBucket(
                from: window,
                bucketID: additionalBucketID(for: name),
                preferredName: name,
                updatedAtDay: updatedAtDay
            ) else { continue }
            usages.append(usage)
        }
        return usages
    }

    /// Identifier for an additional limit, slugged so two names cannot collide
    /// over spacing alone.
    private static func additionalBucketID(for name: String) -> String {
        let slug = name
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if result.last == "-", character == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "additional-\(slug.isEmpty ? "limit" : slug)"
    }
}
