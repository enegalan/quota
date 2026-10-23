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
        guard let latest = latestPoint(bucketID: bucketID, asOf: reference), let baseline = baselinePoint(
            bucketID: bucketID,
            onOrBefore: day,
            calendar: calendar
        ), baseline.recordedAt < latest.recordedAt else { return nil }

        let used = latest.usagePercentage - baseline.usagePercentage
        return used >= UsageConstants.minimumPercentage ? used : nil
    }

    /// The first reading for a bucket taken on or after a day began.
    ///
    /// The other end of the day's measurement: the reading a day's spending is
    /// measured from when there is no reading from before the day.
    public func firstPoint(
        bucketID: String,
        onOrAfter day: Date,
        calendar: Calendar
    ) -> TimelinePoint? {
        let startOfDay = calendar.startOfDay(for: day)
        return points.first { $0.bucketID == bucketID && $0.recordedAt >= startOfDay }
    }

    /// How much of a bucket was used between the day's first reading and an
    /// instant.
    ///
    /// A floor on the day's usage rather than the day's usage: it is what the
    /// app saw, and whatever was spent before that first reading is not in it
    /// and cannot be recovered from it.
    ///
    /// - Returns: the usage measured and the instant it was measured from, or
    ///   nil when the day has no reading, or only one.
    public func usedSinceFirstReadingOn(
        bucketID: String,
        onOrAfter day: Date,
        to reference: Date,
        calendar: Calendar
    ) -> (used: Double, since: Date)? {
        guard let first = firstPoint(bucketID: bucketID, onOrAfter: day, calendar: calendar), let latest = latestPoint(
            bucketID: bucketID,
            asOf: reference
        ), first.recordedAt < latest.recordedAt else { return nil }

        let used = latest.usagePercentage - first.usagePercentage
        guard used >= UsageConstants.minimumPercentage else { return nil }
        return (used, first.recordedAt)
    }

    /// How much of a bucket was used during a whole day, as the summary and the
    /// calendar must both report it.
    ///
    /// The one rule for a day's usage, so a day's calendar cell and the today
    /// block cannot disagree about the same day: the exact figure when a reading
    /// from before the day exists, the day's first-reading floor when the meter
    /// started (or reset) during the day, and zero for a day that has not
    /// begun — which is a fact rather than an estimate, because no reading could
    /// attribute spending to an instant that has not happened.
    ///
    /// - Returns: nil when the day's usage cannot be established at all, which
    ///   is a day with no usable reading in it, not a day with nothing spent on
    ///   it.
    public func usedDuring(
        bucketID: String,
        day: Date,
        to reference: Date,
        calendar: Calendar
    ) -> Double? {
        let start = calendar.startOfDay(for: day)
        guard start <= reference else { return 0 }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let end = min(dayEnd, reference)
        if let used = usedOn(bucketID: bucketID, from: start, to: end, calendar: calendar) {
            return used
        }
        return usedSinceFirstReadingOn(
            bucketID: bucketID,
            onOrAfter: start,
            to: end,
            calendar: calendar
        )?.used
    }
}
