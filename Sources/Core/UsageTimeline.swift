import Foundation

/// A measurement of one bucket at a known moment, kept so that the change
/// between two moments can be attributed to the days in between.
public struct TimelinePoint: Sendable, Hashable, Codable {
    public let recordedAt: Date
    public let bucketID: String
    public let usagePercentage: Double

    public init(recordedAt: Date, bucketID: String, usagePercentage: Double) throws {
        guard usagePercentage.isFinite,
              UsageConstants.percentageRange.contains(usagePercentage)
        else {
            throw QuotaDomainError.invalidPercentage(usagePercentage)
        }
        self.recordedAt = recordedAt
        self.bucketID = bucketID
        self.usagePercentage = usagePercentage
    }
}

/// The recorded history of a provider's usage, ordered oldest first.
///
/// This exists so that "how much did I use today" is answerable. A provider
/// reports a cumulative percentage for the whole period, so today's spending is
/// the difference between the latest reading and the last reading taken on or
/// before the start of today. Without a baseline the difference is unknown, and
/// the app reports that rather than treating it as zero, which would tell a user
/// they have spent nothing today when in fact the app simply cannot tell.
public struct UsageTimeline: Sendable, Hashable, Codable {
    public let points: [TimelinePoint]

    public init(points: [TimelinePoint]) {
        // Sorted on construction so every consumer can rely on the order instead
        // of re-sorting, and so `Codable` round trips a stable representation.
        self.points = points.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// The latest reading for a bucket at or before an instant.
    public func latestPoint(bucketID: String, asOf reference: Date) -> TimelinePoint? {
        points.last { $0.bucketID == bucketID && $0.recordedAt <= reference }
    }

    /// The last reading for a bucket taken on or before the start of a day.
    ///
    /// This is the baseline: subtracting it from the latest reading isolates the
    /// usage that happened during that day. nil when the app has no reading from
    /// before the day began.
    public func baselinePoint(
        bucketID: String,
        onOrBefore day: Date,
        calendar: Calendar
    ) -> TimelinePoint? {
        let startOfDay = calendar.startOfDay(for: day)
        return latestPoint(bucketID: bucketID, asOf: startOfDay)
    }

    /// How much of a bucket was used between the start of a day and an instant.
    ///
    /// - Returns: nil when the day's usage cannot be established, which happens
    ///   when there is no reading for the day or no baseline from before it. The
    ///   caller must distinguish this from zero, which is what makes a summary
    /// able to say "unknown" rather than "nothing spent today".
    public func usedOn(
        bucketID: String,
        from day: Date,
        to reference: Date,
        calendar: Calendar
    ) -> Double? {
        guard let latest = latestPoint(bucketID: bucketID, asOf: reference) else { return nil }
        guard let baseline = baselinePoint(bucketID: bucketID, onOrBefore: day, calendar: calendar) else {
            return nil
        }
        guard baseline.recordedAt < latest.recordedAt else { return nil }

        let used = latest.usagePercentage - baseline.usagePercentage
        return used >= UsageConstants.minimumPercentage ? used : nil
    }
}
