import Core
import Foundation

/// When a period turns over, in the interface's own words.
///
/// One wording, because the quota panel and the provider panel both say it
/// about the same kind of instant, and two copies of a sentence drift apart.
enum ResetCaption {
    /// The caption for a period's end, or nil when the period is over.
    ///
    /// Silent once the period has ended: an expired period has no reset still
    /// to come — the next one arrives with the provider's next answer — and
    /// naming an instant already past as "when usage resets" would be a
    /// countdown to nothing.
    ///
    /// The date and the time together, not just the day, because a reset is an
    /// instant: a weekly or session limit that turns over at 14:00 is not the
    /// same fact as one that turns over at midnight.
    static func caption(
        for period: QuotaPeriod,
        asOf reference: Date,
        calendar: Calendar
    ) -> String? {
        guard period.status(asOf: reference) == .active else { return nil }
        let instant = LayoutMetrics.date(period.end, template: template, calendar: calendar)
        return "Resets \(instant)."
    }

    /// The date-and-time skeleton the caption is written from.
    ///
    /// A template rather than a fixed pattern because the order and separators
    /// are the locale's to decide, the same rule the other written dates in the
    /// interface follow.
    private static let template = "dMMMyjm"
}
