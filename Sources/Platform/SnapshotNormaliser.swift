import Foundation
@testable import Core
@testable import PluginKit

/// Turns a plugin's answer into the app's own reading.
///
/// The boundary where a provider's vocabulary becomes the app's: dates as
/// strings become dates, percentages become buckets, and one provider's set of
/// quotas becomes one snapshot. Isolated here because this is where a provider
/// can be wrong in a way the rest of the app must not inherit — an unparseable
/// date, a percentage over 100, a period that runs backwards — and each of those
/// wants to become a failure the user can be told about rather than a value that
/// quietly propagates.
public enum SnapshotNormaliser: Sendable {
    /// Converts one provider's answer into a snapshot.
    ///
    /// - Throws: `NormalisationError` with a reason, which the caller turns into
    ///   a `SyncFailure` — never into a partially built snapshot.
    public static func snapshot(from result: UsageResult, recordedAt: Date) throws -> UsageSnapshot {
        // Checked before the buckets are built, because an answer with no quotas
        // has no dates to read and reporting "unreadable period" for it would send
        // a provider author looking at their date format.
        guard !result.quotas.isEmpty else { throw NormalisationError.noBuckets }
        var buckets: [UsageBucket] = []
        for usage in result.quotas {
            guard let percentage = validPercentage(usage.usagePercentage) else {
                throw NormalisationError.usageOutOfRange(usage.externalID, usage.usagePercentage)
            }
            // Read from every quota rather than the first: two limits on one
            // account need not share a clock, and taking the first window for all
            // of them is how a five-hour limit becomes a week-long plan.
            buckets.append(
                try UsageBucket(
                    id: usage.bucketID,
                    displayName: usage.bucketDisplayName,
                    usagePercentage: percentage,
                    period: try period(of: usage)
                )
            )
        }
        return try UsageSnapshot(updatedAt: recordedAt, buckets: buckets)
    }

    /// The window one of the provider's limits is measured over.
    ///
    /// Taken from the provider rather than the quota, which is the whole reason
    /// exists: a provider that rolls its period over says so, and the
    /// app has to believe it or used-today becomes a total across two cycles.
    private static func period(of usage: ProviderUsage) throws -> QuotaPeriod {
        guard let start = date(usage.periodStart), let end = date(usage.periodEnd) else {
            throw NormalisationError.unreadablePeriod(usage.externalID)
        }
        return try QuotaPeriod(start: start, end: end)
    }

    /// The first instant of a `yyyy-MM-dd` day.
    ///
    /// Parsed in UTC on purpose: a period boundary is a calendar day in the
    /// provider's terms, and resolving it against the user's timezone would move
    /// a period by a day for anyone west of Greenwich. The formatter is made per
    /// call rather than shared, because `ISO8601DateFormatter` is not `Sendable`
    /// and a shared one would be a data race the next time two quotas are read
    /// at once — which must be possible.
    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }

    /// The percentage, when it is one that can be shown as a figure.
    ///
    /// Checked before the bucket is built so a refusal can name the provider's own
    /// bucket and the exact number it sent, which a validation failure raised
    /// further in could not. Non-finite values are refused here for the same
    /// reason: they satisfy no comparison a range check can make sense of, and a
    /// figure that compares false against every limit is not one to display.
    private static func validPercentage(_ value: Double) -> Double? {
        guard value.isFinite, UsageConstants.percentageRange.contains(value) else { return nil }
        return value
    }
}

public enum NormalisationError: Error, Equatable {
    case noBuckets
    case unreadablePeriod(String)
    case usageOutOfRange(String, Double)

    /// The protocol error code this failure should be recorded as.
    ///
    /// A provider that answers with a number the app cannot use is not
    /// unavailable and not rate limited; it is answering wrongly, and the
    /// interface says so rather than showing a number with a footnote.
    public var code: ProviderErrorCode {
        .invalidResponse
    }
}
