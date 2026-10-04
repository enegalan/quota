# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-04

### Added

- A release for every tag: pushing `v*` builds `Quota.app` for Apple Silicon and
  Intel, runs the same checks CI runs, and attaches both zips and their SHA-256
  checksums to that tag's GitHub Release. The workflow refuses a tag that
  disagrees with the bundle's own version, because a tag and a bundle that name
  different versions is one download with two answers. It can also be re-run for
  an existing tag without cutting a new one.
- A management window beside the menu bar: the quotas on the left with how much of
  each allowance is used, the selected quota's detail on the right in titled
  sections — allowance, today, calendar, policy — and a toolbar for adding and
  refreshing. Adding and refreshing are keyboard commands.
- One month grid, shared by the plan's calendar and the custom policy editor, so
  both draw a month the same way. It follows the user's first day of the week,
  marks today and the selected day, explains its own marks, pages a month at a
  time within the period, and keeps the selected day in view.
- The custom policy editor fills a period in one press, and the figures it writes
  add up to exactly 100% as they are displayed — thirty days do not divide into a
  hundred whole percents, and a period that cannot be divided evenly could not
  otherwise be filled by hand in any reasonable number of steps.
- A day chosen in the custom policy editor says what it is allowed to take when
  that is less than the whole allowance, so a control that stops is not a mystery.
- `MonthLayout` tests for the month's length, its first weekday, and its leading
  blanks; `QuotaPeriod.localDates(in:)` for the days a period has; and rendered
  checks that both calendars draw, that the first weekday moves the days, and that
  the grid is not clipped by the width it is given. The rendered PNGs are written
  to `.build/snapshots`.
- The popover lists every quota, with the one the menu bar item speaks for shown in
  full and marked, and the rest as rows that can be clicked to promote. The choice is
  saved, so the number beside the menu bar item is the one the user picked rather than
  whichever quota happened to be loaded first.
- Several windows on one provider. A provider whose limits do not reset together — a
  five-hour allowance and a weekly one — can now back a quota for each of them.
  Every quota is paced, planned, and drawn against the window its own limit
  reports, so a five-hour quota resets in five hours instead of being measured
  against the week its neighbour resets in, and neither quota's history disturbs
  the other's.
- The quota creation flow picks which of a provider's limits a new quota watches,
  shows the days left in that window rather than in a guess at one, and will not
  offer a limit that already has a quota.
- A quota whose limit the provider has stopped reporting now says it is waiting
  for that limit, keeping the last numbers it really did measure. It does not
  adopt another limit's window or invent a reading: a number from somewhere else,
  or a fabricated zero, both read as "nothing spent".
- A provider and bucket that already has a quota cannot be given a second one. The
  creation flow says so on the row rather than at Create, and a policy edit still
  rewrites the quota being edited — the rule is on creating, not on every write.

### Changed

- Which providers a build offers is decided by packaging them: whatever sits in
  the bundle's `Providers` directory is what the application offers, and each one
  installs through the same path as a downloaded provider. There is no separate
  list of providers to keep in step with the packages, so a provider could not be
  built, shipped and still missing from what the application offered.
- A provider plugin now has to say its version as `major.minor.patch`, and has to
  fall inside the protocol range the application speaks. A plugin that reports a
  partial version, or one built for another range, is refused with the reason
  rather than run and failing later in a way that reads as the provider's fault.
- A limit is now measured over a window of its own: the period moved from the whole
  reading onto each limit, where it is the property of the thing it describes.
  Snapshots stored before this are rewritten on first read — a reading that
  recorded one window for everything is given that window on each of its limits,
  which is exactly what it said — and other stored files are re-stamped
  unchanged.
- A quota that watches a provider's primary limit stands in the way of every limit
  on that provider, whichever order the two are created in. Which identifier a
  provider calls primary is only known by reading it, and the alternative is two
  quotas describing one set of numbers.
- The menu bar item reads `Quota · 2% / 8%`: what has been used of today, out of
  what the day planned, spaced apart so the eye does not read one number where
  there are two. A figure that cannot be established shows as a dash in the
  numerator and the plan is still given.
- A custom policy cannot be given more than 100% in the editor: a day is held at
  what is left of the allowance after the other days. Lowering a day is always
  allowed, so a policy stored before the ceiling existed is still editable and
  walkable back down.
- The quota detail no longer lists the coming days' allocations beside the
  calendar. Every day of the period carries its own share in the calendar, so the
  list was a second rendering of the same figures — and one that grew with the
  period, listing a year of rows in front of the calendar answering the same
  question. Whether the plan adds up is still stated, above the grid, because no
  day of the grid can say it.
- Quota creation shows the steps it is on as a numbered trail, with the steps that
  do not apply to the chosen provider absent from it.

### Fixed

- The application can be built for release again. Its layers had been importing
  each other with `@testable`, which only compiles when a module is built for
  testing — that is, in a debug build. Every release build failed to compile, so
  `make bundle --release` could not produce a distributable and CI had never
  caught it because CI bundles a debug build.
- A quota with no figure prints a dash rather than `0%`. Two quotas could both
  read as untouched allowances — one whose limit the provider had stopped
  reporting, one never read at all — and neither has spent nothing; neither has
  been measured, which the dash says and a zero did not.
- A provider reporting several limits with different windows no longer has all but
  the first measured against the first one's window. One window described the
  whole reading, so the others were either refused or silently corrected to a
  cycle they were never on.
- Today's remaining is derived from the same used figure the today block shows, so
  planned, used, and remaining always add up. Recomputing used from the timeline
  beside a remaining value baked earlier could disagree (for example 0.8% used of
  a 3% plan with 2.5% left).
- A month asked for by a day other than the first is now drawn as the whole month
  it belongs to. It was counted forward from the day it was handed, so a calendar
  showing the fifteenth of a month would have shown a month beginning on the
  fifteenth and running on into the next one.
- The month grid now draws the empty cells before the first of the month, so a day
  sits in the column its own weekday falls in. The blanks were computed and then
  not drawn, and every month was one day out of place.

### Security

- Nothing yet.

### Deprecated

- Nothing yet.

### Known Issues

- A quota whose limit a provider _renames_ waits for that limit forever. The quota
  is kept rather than removed, so a rename and a temporary disappearance are told
  apart from storage alone — and nothing in the interface can move a quota onto the
  provider's new name for it. Until a quota can be repointed at another of its
  provider's limits, that quota shows a dash until it is deleted and created again.

## [0.1.0] - 2026-09-26

### Added

- Native macOS menu bar application with popover, calendar, and quota creation.
- Allocation engine (even, weekly, custom) with pacing and usage timeline.
- Plugin host, catalog, installer, sync coordinator, and mock provider.
- Cursor provider plugin (unofficial): reads the local Cursor session and the
  dashboard usage endpoints; normalises two usage pools into a `UsageSnapshot`.
- Background refresh with low-power suspension, configurable poll interval, and
  diagnostic dump (no credentials).

### Changed

- Catalog enables Cursor as an unofficial, optional provider.
- Tooling no longer ships architectural guard scripts or a magic-number
  allowlist; layer and naming rules stay in the architecture spec and review.

### Fixed

- Refresh planning now executes coordinator refreshes instead of only computing
  due IDs.

### Security

- Credentials are Keychain-only; Cursor session tokens are never persisted by
  Quota; unauthorised response bodies are not logged.

### Deprecated

- Nothing.

### Known Issues

- The Cursor integration is **unofficial**. Cursor has removed or changed
  dashboard endpoints without notice in the past. See
  [spec/0004-cursor-spike-report.md](spec/0004-cursor-spike-report.md). Follow-up
  tracking: open a GitHub issue titled "Cursor unofficial integration breakage"
  when the first production break is observed.
- The M-13 twenty-four-hour poll may still be running; treat the 300s poll
  interval as provisional until that log is closed.
- Remote (URL-fetched) provider artifacts are refused until code-signature
  verification beyond the passthrough verifier ships.
