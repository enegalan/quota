import Core
import Foundation

/// One day as the calendar shows it.
///
/// The classification is done once, here, so a view cannot disagree with itself
/// about whether a day is in the past. The calendar must distinguish five
/// states and a view that computed any of them inline would be five decisions
/// repeated in as many places.
struct CalendarDay: Sendable, Hashable, Identifiable {
    /// Where a day sits, in the order the calendar needs to treat them.
    enum Kind: String, Sendable, CaseIterable, Comparable {
        /// Before today, and inside the period: history, not a plan.
        case past
        /// Today.
        case today
        /// After today, and inside the period: a plan not yet spent.
        case future
        /// Inside the period, but with nothing allocated.
        case zeroAllocation
        /// Outside the period entirely.
        case outOfPeriod

        /// The order the calendar treats the states in, taken from the
        /// declaration order above rather than from a second table of integers
        /// that could fall out of step with it.
        private var order: Int {
            Kind.allCases.firstIndex(of: self) ?? 0
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.order < rhs.order
        }

        /// Whether a day in this state is part of the active period.
        ///
        /// The calendar greys out everything else, and a day outside the period
        /// has no allocation because it is not a day the user can spend.
        var isWithinPeriod: Bool {
            self != .outOfPeriod
        }
    }

    let date: LocalDate
    let kind: Kind

    /// The share of the allowance planned for this day.
    ///
    /// Zero for a day with nothing allocated to it, and nil only for a day
    /// outside the period, which is not a day the user can spend.
    let planned: Double?

    /// What was actually used, if it can be established.
    let actual: Double?

    /// What is left of the day's allowance.
    ///
    /// The whole share for a day that has not begun, today's remainder for
    /// today, and what a day ended short by for one that has passed. Nil when
    /// the day's usage is unknown.
    let remaining: Double?

    var id: LocalDate {
        date
    }

    init(
        date: LocalDate,
        kind: Kind,
        planned: Double? = nil,
        actual: Double? = nil,
        remaining: Double? = nil
    ) {
        self.date = date
        self.kind = kind
        self.planned = planned
        self.actual = actual
        self.remaining = remaining
    }
}

/// A month of days, ready to render, plus the reference points a view needs to
/// lay it out.
struct CalendarMonth: Sendable, Hashable {
    /// The first day of the month, in the user's calendar.
    let firstDay: LocalDate

    /// Every day cell of the month's grid, including the leading blanks for
    /// days of the previous month, so the grid can be rendered without the view
    /// working out where the first of the month falls.
    let cells: [CalendarDay]

    /// The same days without the leading blanks, for a list-style rendering.
    ///
    /// The blanks are dropped by position rather than by their kind or their
    /// month. A blank carries the month's first date, because that is the only
    /// date a grid can put in an empty cell, so a filter on either of those
    /// cannot tell a blank from a real day that happens to share them — and a
    /// list that showed a phantom day for every leading blank would put the
    /// month's length out by one row.
    var days: [CalendarDay] {
        Array(cells.dropFirst(leadingBlankCount))
    }

    /// Where a month's first day sits, so the grid's leading blanks can be drawn.
    ///
    /// The user's first weekday is honoured rather than assumed: a calendar
    /// starting on Monday for most of the world should not start on Sunday
    /// because the code was written in one.
    let leadingBlankCount: Int
}

/// Builds calendar months out of a plan, a timeline, and a reference instant.
///
/// Everything the calendar knows comes in through the initialiser — the plan,
/// the timeline, the calendar, and "now" — so a month can be built for any
/// instant in a test without a fixture file, and so the same value cannot be
/// computed twice with two different answers.
struct CalendarPresenter: Sendable {
    private let plan: AllocationPlan?
    private let timeline: UsageTimeline?
    private let allowance: TodayAllowance?
    private let bucketID: String?
    private let calendar: Calendar
    private let reference: Date

    /// - Parameter allowance: today's allowance as the summary resolved it. It
    ///   is passed in rather than recomputed because the remaining figure needs
    ///   the day's actual usage, which is the timeline's to answer, and two
    ///   places each subtracting it would be two chances to disagree about
    ///   whether today has a baseline at all.
    init(
        plan: AllocationPlan?,
        timeline: UsageTimeline?,
        allowance: TodayAllowance?,
        bucketID: String?,
        calendar: Calendar,
        reference: Date
    ) {
        self.plan = plan
        self.timeline = timeline
        self.allowance = allowance
        self.bucketID = bucketID
        self.calendar = calendar
        self.reference = reference
    }

    /// The instant every day in this presenter is classified against.
    var referenceDate: Date {
        reference
    }

    /// The days a calendar may act on: the plan's, or nothing if there is no plan.
    ///
    /// Asked of the plan rather than recomputed from the quota's stored period,
    /// because the plan is what the calendar is drawing: a quota whose stored
    /// period has been superseded by a plan would show days the plan does not
    /// cover, and a day the plan does not cover has nothing to show.
    var availableDates: Set<LocalDate> {
        guard let plan else { return [] }
        return Set(plan.period.localDates(in: calendar))
    }

    /// The plan's period, which bounds the months a calendar may be paged to.
    var period: QuotaPeriod? {
        plan?.period
    }

    /// Every day of the month containing `date`, classified and filled in.
    ///
    /// The month's shape comes from `MonthLayout`, the same implementation the
    /// custom policy editor's calendar is drawn from: two calendars in one window
    /// that disagreed about where a month started would be a seam nobody could
    /// name and everybody would see.
    ///
    /// - Throws: `QuotaDomainError.invalidDate` when `date` cannot be
    ///   decomposed into a real month, which the calendar cannot do for an
    ///   instant it does not represent.
    func month(containing date: Date) throws -> CalendarMonth {
        let today = LocalDate(date: reference, calendar: calendar)
        let layout = MonthLayout.month(containing: date, calendar: calendar)
        var cells: [CalendarDay] = []
        cells.reserveCapacity(layout.leadingBlankCount + layout.days.count)
        for _ in 0 ..< layout.leadingBlankCount {
            cells.append(CalendarDay(date: layout.firstDay, kind: .outOfPeriod))
        }
        cells.append(contentsOf: layout.days.map { classified($0, today: today) })
        return CalendarMonth(
            firstDay: layout.firstDay,
            cells: cells,
            leadingBlankCount: layout.leadingBlankCount
        )
    }

    /// One day, classified and filled in.
    ///
    /// Public on its own because the detail panel is asked about a single
    /// date that need not be in the month currently on screen.
    func day(_ date: LocalDate, today: LocalDate? = nil) -> CalendarDay {
        classified(date, today: today)
    }

    /// `day`, named for the closure that builds a month.
    ///
    /// A month is a map over days, and a closure called `day` over a value also
    /// called `day` would be one of the two hiding the other.
    private func classified(_ date: LocalDate, today: LocalDate? = nil) -> CalendarDay {
        let todayDate = today ?? LocalDate(date: reference, calendar: calendar)
        let allocation = plan?.allocation(on: date)?.percentage
        let kind = classify(date: date, today: todayDate, planned: allocation)
        guard kind.isWithinPeriod else {
            return CalendarDay(date: date, kind: kind)
        }
        let planned = kind == .zeroAllocation ? 0 : allocation
        let actual = actual(on: date)
        return CalendarDay(
            date: date,
            kind: kind,
            // A day with nothing allocated to it is a day planned at zero. The
            // policy either gave it nothing or said nothing about it, and to
            // the reader those are the same claim: a day of the month with
            // nothing set aside for it.
            planned: planned,
            actual: actual,
            remaining: remaining(on: date, kind: kind, planned: planned, actual: actual)
        )
    }

    /// Five calendar day states, decided in one place.
    ///
    /// Order matters: a day outside the period is out of period even if it is in
    /// the past, because there is nothing to show for it. Within the period,
    /// today outranks a zero allocation, because a day that is today and has
    /// nothing allocated is still today and the interface has to be able to say
    /// so.
    private func classify(date: LocalDate, today: LocalDate, planned: Double?) -> CalendarDay.Kind {
        guard isWithinPeriod(date) else { return .outOfPeriod }
        if date == today {
            return .today
        }
        if date < today {
            return .past
        }
        // A day with no allocation entry at all is a day with nothing
        // allocated, which is what must be told apart from a funded day.
        // Treating only an explicit zero as empty would render a day the policy
        // never mentioned exactly like a day it funded, and the two are the
        // distinction the state exists for.
        guard let planned, planned > 0 else { return .zeroAllocation }
        return .future
    }

    /// Whether a date falls inside the plan's period, in part or in whole.
    ///
    /// Asked of the day rather than of the day's first instant: a period that
    /// begins at ten in the morning still covers the morning of its first day,
    /// and asking at midnight would call that day outside the period — while the
    /// plan, which plans against days, includes it. The calendar would then
    /// contradict the plan it is drawn from.
    private func isWithinPeriod(_ date: LocalDate) -> Bool {
        guard let plan else { return false }
        return plan.period.status(on: date, calendar: calendar) == .active
    }

    /// What was used on a day, or nil when that cannot be established.
    ///
    /// Delegated to the timeline's one rule for a day's usage, so this cell and
    /// the today block cannot disagree about the same day: exact when a reading
    /// from before the day exists, the day's first-reading floor when the meter
    /// started or reset during it, and zero for a day that has not begun.
    private func actual(on date: LocalDate) -> Double? {
        guard let start = date.date(calendar: calendar) else { return nil }
        // A day that has not begun has spent nothing, which is known without any
        // history: the timeline can state it and so can this, and requiring one
        // would make a day's spending depend on a reading that could not have
        // happened yet.
        guard let timeline, let bucketID else {
            return calendar.startOfDay(for: reference) <= start ? 0 : nil
        }
        return timeline.usedDuring(bucketID: bucketID, day: start, to: reference, calendar: calendar)
    }

    /// What is left of the day's allowance.
    ///
    /// For today this is the summary's own figure, so the calendar cannot show a
    /// remainder the today block disagrees with. For any other day it is the
    /// part of the day's share that was not spent: the whole share for a day
    /// that has not begun, and what the day ended short by for one that has.
    /// Nil when the day's usage is unknown, because the subtraction cannot be
    /// done without it.
    private func remaining(
        on date: LocalDate,
        kind: CalendarDay.Kind,
        planned: Double?,
        actual: Double?
    ) -> Double? {
        if kind == .today, let allowance, allowance.date == date {
            return allowance.remainingAfterToday
        }
        guard let planned, let actual else { return nil }
        let remaining = planned - actual
        return remaining > 0 ? remaining : 0
    }
}
