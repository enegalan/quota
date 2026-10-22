import Foundation
import PluginKit
import ProviderSupport

/// Turning Claude's usage payload into `UsageResult` (plugin wire format).
///
/// Claude meters several limits that turn over on different clocks: a rolling
/// five-hour session allowance and a weekly one, plus per-model weekly limits
/// on the plans that have them. Each one becomes its own bucket with its own
/// window, because a limit that resets on Monday and an allowance that resets
/// every five hours cannot be paced against a single period.
enum UsageNormaliser {
    /// The buckets Claude reported.
    ///
    /// - Parameters:
    ///   - json: the payload as the endpoint answered it.
    ///   - updatedAtDay: the local day the reading belongs to, as `yyyy-MM-dd`.
    ///   - now: the instant the reading was taken, used for the one window
    ///     Claude does not state — the month the extra-usage credits are
    ///     counted over.
    static func usageResult(
        from json: [String: Any],
        updatedAtDay: String,
        now: Date = Date()
    ) throws -> UsageResult {
        var quotas: [ProviderUsage] = []

        for limit in knownLimits {
            guard let usage = bucket(
                for: limit,
                in: json,
                updatedAtDay: updatedAtDay
            ) else { continue }
            quotas.append(usage)
        }

        quotas.append(contentsOf: scopedBuckets(from: json, updatedAtDay: updatedAtDay))

        if let usage = extraUsageBucket(from: json, updatedAtDay: updatedAtDay, now: now) {
            quotas.append(usage)
        }

        return UsageResult(quotas: quotas, supportsHistorical: false)
    }

    // MARK: The limits Claude names by key

    /// One of the limits Claude reports under a key of its own.
    private struct KnownLimit {
        let key: String
        let bucketID: String
        let displayName: String
        let window: TimeInterval
    }

    /// The limits with a key, and how long each one runs for.
    private static let knownLimits: [KnownLimit] = [
        KnownLimit(
            key: ClaudeConstants.fiveHourKey,
            bucketID: ClaudeConstants.fiveHourBucketID,
            displayName: ClaudeConstants.fiveHourDisplayName,
            window: ClaudeConstants.fiveHourWindow
        ),
        KnownLimit(
            key: ClaudeConstants.sevenDayKey,
            bucketID: ClaudeConstants.sevenDayBucketID,
            displayName: ClaudeConstants.sevenDayDisplayName,
            window: ClaudeConstants.sevenDayWindow
        ),
        KnownLimit(
            key: ClaudeConstants.sevenDayOpusKey,
            bucketID: ClaudeConstants.sevenDayOpusBucketID,
            displayName: ClaudeConstants.sevenDayOpusDisplayName,
            window: ClaudeConstants.sevenDayWindow
        ),
        KnownLimit(
            key: ClaudeConstants.sevenDaySonnetKey,
            bucketID: ClaudeConstants.sevenDaySonnetBucketID,
            displayName: ClaudeConstants.sevenDaySonnetDisplayName,
            window: ClaudeConstants.sevenDayWindow
        ),
    ]

    /// One named limit, as a bucket, or nil when it is not reported.
    ///
    /// A limit that is absent, null, or reported without a reset instant is
    /// left out rather than guessed at: a bucket whose window is unknown cannot
    /// be paced against, and a window invented here would be a plan against
    /// days the limit does not cover.
    private static func bucket(
        for limit: KnownLimit,
        in json: [String: Any],
        updatedAtDay: String
    ) -> ProviderUsage? {
        guard let payload = json[limit.key] as? [String: Any] else { return nil }
        guard let utilization = JSONAccess.double(payload, key: "utilization"),
              let reset = resetInstant(in: payload)
        else { return nil }
        return makeUsage(
            bucketID: limit.bucketID,
            displayName: limit.displayName,
            utilization: utilization,
            window: limit.window,
            reset: reset,
            updatedAtDay: updatedAtDay
        )
    }

    // MARK: The per-model weekly limits

    /// The weekly limits Claude scopes to one model.
    ///
    /// They arrive in a list rather than under a key of their own, so each one
    /// is read on its own terms and named after the model it belongs to. A
    /// limit whose name cannot be read is left out rather than reported under
    /// a name that would mean nothing.
    private static func scopedBuckets(
        from json: [String: Any],
        updatedAtDay: String
    ) -> [ProviderUsage] {
        guard let limits = json[ClaudeConstants.limitsKey] as? [[String: Any]] else { return [] }
        var usages: [ProviderUsage] = []
        for limit in limits {
            guard let kind = limit["kind"] as? String, kind == ClaudeConstants.scopedLimitKind
            else { continue }
            guard let utilization = JSONAccess.double(limit, key: "percent"),
                  let reset = resetInstant(in: limit),
                  let name = scopedName(limit)
            else { continue }
            usages.append(
                makeUsage(
                    bucketID: scopedBucketID(for: name),
                    displayName: "Weekly \(name)",
                    utilization: utilization,
                    window: ClaudeConstants.sevenDayWindow,
                    reset: reset,
                    updatedAtDay: updatedAtDay
                )
            )
        }
        return usages
    }

    /// The model a scoped limit belongs to, as Claude names it.
    private static func scopedName(_ limit: [String: Any]) -> String? {
        guard let scope = limit["scope"] as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let name = model["display_name"] as? String,
              !name.isEmpty
        else { return nil }
        return name
    }

    /// The identifier a scoped limit is filed under.
    ///
    /// Slugged so two models cannot collide over a name that differs only in
    /// its spacing, and so the identifier is something a quota can name.
    private static func scopedBucketID(for name: String) -> String {
        let slug = name
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if result.last == "-" && character == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "scoped-\(slug.isEmpty ? "limit" : slug)"
    }

    // MARK: The extra usage credits

    /// The optional pay-as-you-go pool, when the account has one.
    ///
    /// The only limit whose window Claude does not state: the credits are
    /// counted over a month, and the month is taken as the calendar month the
    /// reading falls in. The figure is Claude's own; only the window is the
    /// app's, and it is the window the credits would be spent in anyway.
    private static func extraUsageBucket(
        from json: [String: Any],
        updatedAtDay: String,
        now: Date
    ) -> ProviderUsage? {
        guard let extra = json[ClaudeConstants.extraUsageKey] as? [String: Any] else { return nil }
        guard (extra["is_enabled"] as? Bool) ?? false else { return nil }

        let utilization: Double? = if let used = JSONAccess.double(extra, key: "used_credits"),
                                      let limit = JSONAccess.double(extra, key: "monthly_limit"),
                                      let share = Percentage.of(used: used, limit: limit)
        {
            share
        } else {
            JSONAccess.double(extra, key: "utilization")
        }
        guard let utilization else { return nil }

        guard let window = month(containing: now) else { return nil }
        return ProviderUsage(
            externalID: ClaudeConstants.extraUsageBucketID,
            displayName: ClaudeConstants.extraUsageDisplayName,
            bucketID: ClaudeConstants.extraUsageBucketID,
            bucketDisplayName: ClaudeConstants.extraUsageDisplayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: window.start,
            periodEnd: window.end,
            updatedAt: updatedAtDay
        )
    }

    /// The calendar month an instant falls in, as two instants.
    private static func month(containing instant: Date) -> (start: String, end: String)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let interval = calendar.dateInterval(of: .month, for: instant) else { return nil }
        return (
            DayFormat.instantString(from: interval.start),
            DayFormat.instantString(from: interval.end)
        )
    }

    // MARK: Shared

    /// The instant a limit turns over, when it says.
    private static func resetInstant(in payload: [String: Any]) -> Date? {
        guard let text = payload["resets_at"] as? String else { return nil }
        return ClaudeTimestamp.instant(from: text)
    }

    /// One bucket, from a figure and the window it is measured over.
    ///
    /// The window ends where the limit turns over, and runs back for as long
    /// as the limit lasts: Claude's windows are rolling, so the period is a
    /// window that ends at the reset rather than a calendar period that
    /// contains it.
    private static func makeUsage(
        bucketID: String,
        displayName: String,
        utilization: Double,
        window: TimeInterval,
        reset: Date,
        updatedAtDay: String
    ) -> ProviderUsage {
        ProviderUsage(
            externalID: bucketID,
            displayName: displayName,
            bucketID: bucketID,
            bucketDisplayName: displayName,
            usagePercentage: Percentage.clamp(utilization),
            periodStart: DayFormat.instantString(from: reset.addingTimeInterval(-window)),
            periodEnd: DayFormat.instantString(from: reset),
            updatedAt: updatedAtDay
        )
    }
}
