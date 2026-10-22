# Quota — Usage history

> What the application knows about the past, and the view that shows it.
> Companion to `spec/0001-definition.md` §32 (intraday recalculation), §35
> (calendar interaction) and §58 (historical analytics), and to
> `spec/0002-architecture.md` §3.5 (the timeline).

---

## 1. What is already recorded

Every successful reading is appended to a **timeline**: one point per reading,
holding the instant, the pool, and the cumulative percentage the provider
reported.

```text
TimelinePoint { recordedAt, bucketID, usagePercentage }
```

The timeline exists to answer one question — _how much was used today_ — and it
answers it by taking the difference between two readings around the day.
`UsageTimeline.usedDuring` is that rule, and it is the **one** rule: the
calendar's day cell, the today block and the history view must not each have
their own.

The rule has **four** answers, not two, and the history view has to keep all
four apart:

| Case                                      | What the day is                | How the figure is reached                                                                      |
| ----------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------- |
| There is a reading from before the day    | the day's use, exactly         | the difference between the last reading before the day and the last reading of it              |
| The meter started or reset during the day | a **floor**, not the whole day | the difference between the day's first reading and its last                                    |
| The day has not begun                     | nothing spent                  | zero — a fact, because no reading could attribute spending to an instant that has not happened |
| There is no usable reading in the day     | **unknown**                    | nothing; the figure is absent                                                                  |

Two properties of the timeline shape everything below.

**It only knows what it saw.** A day the application did not run through has no
baseline, so its usage is _unknown_ — not zero. The distinction is already
enforced (`TodayUsage.unknown`, and `usedDuring` returning `nil`), and the
history view inherits it rather than inventing a second convention.

**It is bounded.** The timeline keeps the most recent 5 000 points per pool. At
the default five-minute poll that is about **seventeen days**; at a one-minute
poll, three and a half. A month-long allowance is therefore only partly covered
by the raw points, and a history view that drew a month of days from them would
be drawing two thirds of the month and saying nothing about the rest.

---

## 2. What the calendar already shows, and what the history view adds

The calendar already carries a day's planned share, a day's actual use and what
is left of it, one month at a time, with the selected day's figures underneath.
A history view that redrew that would be a second rendering of the same figures
in a different shape.

So the history view is not a second calendar. It answers a question the calendar
cannot:

> **What is the shape of my spending?**

The calendar answers _what did I spend on the 14th_. The history view answers
_how do I spend across a month — heavy on Mondays, nothing at the weekend, one
big day at the end_ — which is the question a user asks when they are deciding
what the **policy** should be. A weekly policy is a guess until the user can see
that their weekends are empty.

Three things, then:

1. **The shape**, at a glance, over the whole period rather than a month at a
   time.
2. **The days the application could not see**, drawn as what they are.
3. **The average**, because a shape without a scale is a drawing.

---

## 3. The honest limit: a plan is rebalanced, so yesterday's plan is gone

The allocation plan is **recomputed on every successful reading**, and it
balances the _remaining_ allowance across the _remaining_ days. The plan for
Tuesday is not stored anywhere; on Wednesday it no longer exists as a fact about
Tuesday. It is not a record, it is a current intention.

This has one consequence that shapes the whole design:

> **"Planned versus actual" for a past day cannot be computed from what the
> application has.**

The plan holds allocations for today and onwards only. For a day that has
passed there is no planned share to compare against — not because it was
discarded, but because a rebalanced plan never had one for that day.

Two ways out, and the difference between them is the difference between a true
figure and a plausible one.

### 3.1 Option A — compare against the plan as it is now (not recommended)

Draw the current plan's daily share as a line and the measured days as bars.

The line is **wrong for every past day**: it is today's plan, applied to last
Tuesday. The comparison would look meaningful and mean nothing, and a user who
acted on it would be acting on a number the application made up. This is the
same failure as the pacing verdict that was removed in 1.3.11 — a figure that
compares two things that do not belong together.

### 3.2 Option B — record the plan as it was (the honest way)

Record, once a day, the share the plan gave each day — and record it **at the
moment the day began**, so the value is the last plan that applied to it.

```text
The plan said 4.10% for Wednesday. You used 6.30%.
```

This is a small addition: one number per day per pool, the same shape as the
daily usage rollup of §4. It is truthful, and it is the only version of the
comparison a user can act on.

### 3.3 The decision

**The history view ships without the plan comparison, and says what it is
showing instead** (Option A is rejected; §3.1). The comparison is a **separate
milestone**, and it is worth doing because it is what turns a chart of spending
into a check on the policy.

Until then, the scale of the chart is **the average of the measured days**,
which is a fact about the past and not a comparison of two different things:

```text
4.20% a day over 23 measured days
```

---

## 4. The daily rollup

The timeline's seventeen days are not enough to draw a month, and thinning the
points (keeping one per hour) would lose the resolution that makes _used today_
exact. So the past gets a **second, permanent record**: one row per day per
pool, holding what the application measured that day.

```text
dailyusage.json

DailyUsageRecord {
    quotaID, bucketID, accountKey,
    date: LocalDate,
    measurement: DailyMeasurement
}
```

`DailyMeasurement` carries the four answers of §1 rather than a single number,
because a number cannot say whether it is a measurement, a floor, or an absence:

```swift
public enum DailyMeasurement: Sendable, Equatable {
    /// Measured against a reading from before the day: the day's exact use.
    case exact(Double)
    /// Measured from the day's first reading, because the meter started or
    /// reset during the day. A floor: at least this much was used.
    case floor(Double)
    /// The day has not begun.
    case notYet
    /// The day cannot be measured: there is no usable reading in it.
    case unknown
}
```

The rules:

- **A row is written when the day is over.** A day's use is the difference
  between two readings, and the second of them does not exist until the day has
  ended. A row written at 23:50 would be a row about a day that had not
  finished.
- **A row is written once.** A day is measured once, when it ends. A refresh
  later in the next day does not rewrite it.
- **A day that cannot be measured is stored as unknown, not as zero.** The
  same rule as everywhere else: unknown means "the application was not
  watching", and zero means "the application watched and nothing was spent". A
  day the machine was asleep is not a day of no work.
- **A day measured from its first reading is stored as a floor, and stays
  one.** A day on which the meter reset is a day whose use is _at least_ the
  figure, and a rollup that quietly upgraded a floor into a measurement would
  overstate the past.
- **The row is derived from the timeline, by `usedDuring`.** The history view
  and the calendar therefore cannot disagree about a day: they are the same
  rule, asked of the same record.

The file is small — thirty rows a month per pool — and it is what makes the
history view possible at all.

---

## 5. The view

### 5.1 Where it lives

In the quota's detail, in the window, as a section between **TODAY** and
**CALENDAR**:

```text
┌──────────────────┬──────────────────────────────────────────┐
│ Cursor      26%  │ ALLOWANCE                                │
│ Claude      71%  │ 26% used              74% remaining       │
│ OpenAI      12%  │ ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│                  ├──────────────────────────────────────────┤
│                  │ TODAY                                    │
│                  │ Planned     6.00%   Used      2.00%      │
│                  │ Remaining   4.00%                         │
│                  ├──────────────────────────────────────────┤
│                  │ USAGE                                     │
│                  │  ▁  ▃  ▅  ▂  ▁  ▁  ▄  █  ▂  ▁  ▁  ▃  ▂   │
│                  │  4.20% a day over 23 measured days         │
│                  │  ▨  ▨     ▨                              │
│                  ├──────────────────────────────────────────┤
│                  │ CALENDAR                                 │
│                  │ September 2026                ‹     ›    │
│                  │  M    T    W    T    F    S    S          │
│                  │     1    2    3    4    5    6    7       │
│                  │   3.3  3.3  3.3  3.3  3.3  3.3  3.3       │
└──────────────────┴──────────────────────────────────────────┘
```

### 5.2 What it draws

- **One bar per day of the period**, from the start of the period to today.
  Future days are not drawn: the calendar's grid is where a plan that has not
  happened is shown, and a chart of a future that has no measurement would be a
  chart of the plan wearing the clothes of a record.
- **The bar's height is the day's measured use**, as a share of the allowance —
  the same unit as every other figure in the application, so a bar can be
  compared with a figure without conversion.
- **The bar's scale is the largest measured day**, not the allowance. A month's
  allowance is 100% and a day's use is a few percent, so a scale of 100 would
  draw every day as a hairline. The scale is labelled, so the reader knows what
  the tallest bar is.
- **A day measured from its first reading is drawn with a mark**, because it is
  a floor and not a measurement: the bar says _at least this much_. A floor
  drawn like a measurement would overstate the past, which is the one thing a
  chart of the past must not do.
- **A day the application could not measure is drawn as a gap, not as an empty
  bar.** An empty bar and a gap mean different things, and the difference is
  exactly the difference between "nothing spent" and "not watched".
- **The caption** carries the average, the number of measured days, and the
  number of days that could not be.

### 5.3 What it does not draw

- **No cumulative line.** A cumulative curve is the provider's own figure
  redrawn, and the provider's dashboard already draws it better.
- **No trend line, no moving average, no forecast.** The application is a
  planner, and a forecast is a claim about the future that the plan already
  makes in a form the user can check.
- **No second copy of the plan.** The plan is the calendar's job.

### 5.4 The connection to the calendar

A bar is selectable, and selecting one selects that day in the calendar below
and moves the calendar's month to it. The calendar already has a selected day
whose figures sit under the grid (§35), so the two views are two ways of
reaching one selection rather than two selections.

---

## 6. The caption, and the honesty it carries

The caption is not decoration. It is where the view states what it can and
cannot know.

```text
4.20% a day over 23 measured days
2 days were not measured — the app was not running
```

And when the application has only been watching for a short time:

```text
2.10% a day over 6 measured days
Watching since 12 October
```

The second line matters more than it looks. A user who has had the application
for a week and sees a chart of six days should know that the other twenty-four
days of the period are not a quiet period — they are days the application was
not there.

---

## 7. Data and layering

The derivation belongs in `Core`, beside the rule it uses:

```swift
extension UsageTimeline {
    /// Every day of the period the application can account for, with what was
    /// used on it.
    public func dailyUsage(
        bucketID: String,
        from: LocalDate,
        to: LocalDate,
        calendar: Calendar
    ) -> [DailyUsage]
}

public struct DailyUsage: Sendable, Equatable, Identifiable {
    public let date: LocalDate
    public let measurement: DailyMeasurement
    public var id: LocalDate { date }
}
```

The presentation is a value the interface renders, in the same shape as
`CalendarMonth` and `QuotaPresentation`: the view decides nothing.

```text
Core      UsageTimeline.dailyUsage — the rule, and the only rule
Platform  DailyUsageRepository — the rollup file, written when a day ends
App       UsageHistoryPresenter — the days, the scale, the caption
```

The rollup is written by the coordinator, at the same moment it notices that a
day has ended — which it already has to notice, because the timeline's day
boundary is what makes _used today_ correct.

---

## 8. Testing

| Test                           | What it proves                                                              |
| ------------------------------ | --------------------------------------------------------------------------- |
| `DailyUsageTests`              | A day with a reading from before it is measured exactly.                    |
| `DailyUsageTests`              | A day whose meter reset during it is a floor, and stays a floor.            |
| `DailyUsageTests`              | A day with no usable reading is unknown, never zero.                        |
| `DailyUsageTests`              | A day that has not happened is zero, because nothing could have been spent. |
| `DailyUsageRollupTests`        | A day is written once, when it ends, and is not rewritten.                  |
| `DailyUsageRollupTests`        | A day the application could not measure is written as unknown, not as zero. |
| `DailyUsageRollupTests`        | A floor is written as a floor, and is never upgraded to a measurement.      |
| `UsageHistoryPresenterTests`   | The caption states the average, the number of measured days, and the gaps.  |
| `UsageHistoryPresenterTests`   | The caption says when the application started watching.                     |
| `UsageHistoryPresenterTests`   | The history view and the calendar report the same figure for the same day.  |
| `UsageHistoryInteractionTests` | Selecting a bar selects that day in the calendar.                           |

The second test in the first pair and the second test in the second pair are the
same rule applied to two records, and they are the reason the rollup cannot
quietly disagree with the timeline.

---

## 9. What this milestone does not do

- **It does not compare against a plan.** §3.3 says why, and §3.2 says what
  would make it possible.
- **It does not show days outside the period**, and it does not show the
  provider's cumulative figure.
- **It does not invent a measurement for a day the application did not see.**

See `spec/0003-milestones.md` (M-21) for the task list and the exit criterion.
