# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.8] - 2026-10-20

### Fixed

- A provider's allowance period that begins part-way through a day now covers
  that day. The provider reports the exact instant its allowance starts, and
  the calendar asked about the day's midnight — so the first day of the period
  was drawn as a day outside it, while the plan beside it planned that day.

## [1.3.7] - 2026-10-20

### Fixed

- A provider's page now shows the result of an action taken from it. The page
  reloaded while the app was still reading, so it read the provider list as it
  was before the action — and an update pressed inside the page looked as
  though it had done nothing.

## [1.3.6] - 2026-10-20

### Changed

- The pacing verdict now says what it is a verdict about: the usage and the
  planned share it compares are written under it. "Ahead of Pace" on its own
  says a pace without saying what it is a pace of, which is a puzzle to anyone
  whose provider has just restarted its allowance.

## [1.3.5] - 2026-10-19

### Fixed

- A provider's update is checked twice before it is called a failure. A plugin
  that has just been unpacked is one the machine has never run, and the first
  run of a new binary can fail for reasons that have nothing to do with the
  binary — so an update that failed on the first attempt now tries again.
- Updating a provider that is already on the version this build ships does
  nothing, instead of being refused as a failure. The button had nothing to do
  and said it had failed.

## [1.3.4] - 2026-10-19

### Fixed

- A provider action that fails now says why. The reason was put up in the
  banner and then wiped by the reload that followed the action, so pressing
  Update on a provider that could not be updated did nothing at all.
- The provider list is brought up to date even when the quota panels could not
  be built, so a provider that was just updated does not keep offering the
  action that was already taken.

## [1.3.3] - 2026-10-19

### Fixed

- A provider that dies while the app is talking to it no longer takes the app
  down with it. Writing to a plugin that has gone raised a signal the app did
  not handle, and the app closed with it — losing the menu bar item over a
  provider that crashed.

## [1.3.2] - 2026-10-19

### Fixed

- A provider's page reads itself again after an action taken from it. An
  update, a sign-in or a removal now shows in the page that was used, instead
  of the page having to be closed and opened again to see what the click had
  done.

## [1.3.1] - 2026-10-19

### Fixed

- Updating a provider no longer leaves it signed out. The new version is the
  same provider as the old one — the same account, still connected — and an
  update that failed now leaves the version and the connection the user had, so
  it can be retried without removing the provider and starting again.
- The reasons an install or an update can fail are now said in the app's own
  words, instead of the system's words for an error it has never heard of.

## [1.3.0] - 2026-10-19

### Added

- Every provider has a page. Clicking a provider opens it: the account it reads
  as, the version on this machine and the one in this build, the protocol it
  speaks, how often it is asked, and the limits it meters with the window each
  of them turns over on. The page is read from what the app already knows, so
  it shows the same figures the rest of the window is showing.

### Changed

- The providers list is built around that click. The mark sits on a tile of its
  own, the whole card opens the page rather than one corner of it, and the
  pointer is answered with an outline and a disclosure that moves, without
  flooding the card with colour.
- The calendar's month selector and the days it selects are drawn as two
  things: the arrows now flank the month they move, the month sits on a tile of
  its own, and the jump to today is offered by the month menu rather than by a
  button beside it that looked like it was editing the month's title.
- A day with nothing allocated is a day planned at zero, and is drawn like any
  other day with that figure in it. Only a day outside the period is greyed out,
  and the calendar's key says so and nothing else.
- The weekly policy's seven days are given room to breathe, and the calendar
  leaves more space between the month selector and the grid.

### Fixed

- "Used today" is measured from the day's first reading when the app has no
  reading from before the day, instead of showing a dash. A day the app did not
  see from the start can only be measured from where it started watching.
- The jump to today now selects today, so the figures under the calendar stop
  describing a day the calendar is no longer showing.

## [1.2.0] - 2026-10-19

### Added

- A quota's card now says when the provider's window turns over — the date and
  the hour the allowance resets — in the popover and in the detail view, beside
  the countdown that answers the same question in days.

### Changed

- The today panel leads with the day's plan as a figure, in the same idiom the
  allowance card uses, with the bar beneath it drawing the day against that
  plan. The figures below it are the two measurements alone, used and remaining,
  so a plan and a reading are never set side by side as though both were
  readings.

### Fixed

- A provider's reset hour is no longer rounded away to midnight. The window is
  carried as the instant the provider reported, end to end, so a quota that
  resets at 10:46 says 10:46.
- A window corrected to its exact instants no longer wipes the recorded
  history. Only the points from before the new window's start are dropped — the
  ones metered by the cycle it replaced — so "used today" survives a correction
  that changed no cycle at all.

## [1.1.0] - 2026-10-18

### Added

- Each provider now shows its own logo beside its name — in the providers list,
  the quota creation flow, and a quota's account line. The mark ships inside the
  provider's own package (`Plugins/<id>/logo.png`) and the build script files it
  in the application bundle under the provider's identifier. A provider without
  a logo falls back to the generic provider symbol rather than an empty space,
  and the build refuses a packaged provider that ships none.
- A shared `ProviderSupport` library — credentials, JWT, an HTTP client, and a
  reader for a provider application's local state — that provider plugins build
  on. The Cursor provider is rewritten over it, so its behaviour lives in one
  place with its own tests instead of being repeated per provider.
- `PROVIDERS.md`: the AI coding providers Quota supports, plans to support, or
  is researching, and what it paces for each.

### Changed

- The today panel leads with a bar: the day's plan is its track, the spend is
  its fill, and what remains is what is left of the track, with the three
  figures beside it. The proportion is read at a glance rather than worked out
  from two numbers.
- The README was rewritten and shortened.

## [1.0.6] - 2026-10-16

### Fixed

- Past days in a quota's calendar keep their planned allocation after a recalculation, instead of losing it. The calendar now retains each past day's plan alongside the current plan's figures for today and beyond.
- The Cursor provider no longer triggers a repeated macOS Keychain consent prompt while refreshing. Keychain entries that need interactive access are skipped and the next token source is used.

## [1.0.5] - 2026-10-15

### Added

- Maintainer release skill (`release-version`) covering changelog, version bump,
  verification, commit, tagging, push, and watching the release workflow.

### Changed

- Polished the menu bar popover: a usage ring, tinted progress indication, larger
  footer buttons with readable (white) labels, and consistent spacing so the ring
  is no longer clipped.

## [1.0.3] - 2026-10-14

### Changed

- Percentages in the menu bar label and the calendars are shown to at most two
  decimals, the precision a plan is itself expressed in. A provider's reading
  can carry more places than the plan it is compared against, and printing them
  beside a two-place plan claimed a confidence neither figure has.

## [1.0.2] - 2026-10-14

### Fixed

- The plugin host's concurrent-calls test no longer races the handshake. Its two
  calls could start in either order, and a usage call that reached the host before
  the process was up returned without sending its request — leaving the fake
  plugin holding a single request and the launch to time out. The usage call now
  waits for the process to be up, so the case tests id-based correlation rather
  than the scheduler. The application itself is unchanged.

## [1.0.1] - 2026-10-14

### Fixed

- An unset signing identity now means ad-hoc. A signing secret that is not
  configured reaches the bundle step as an empty string, which is defined, and
  `codesign --sign ""` is a keychain lookup for an identity named `""` — so a
  release with no secret failed to sign rather than signing ad-hoc.
- The release workflow reads the tag and version it resolved. The names it wrote
  and the names the later steps read disagreed in case, so the packaging and
  publishing steps saw an unbound variable in place of the version and produced an
  asset nobody could name.
- The release job builds with the compiler the tests are written for. The
  toolchain is chosen by one script that asks for Swift 6.3 by version and refuses
  to downgrade, and the Apple Silicon job runs on the image whose Xcode is the one
  the suite targets.
- `pfctl` is looked up instead of named: it lives in different directories across
  macOS releases, and the test job no longer fails because it could not find a
  firewall at a path that had moved.
- A test target no longer declares a resource directory it does not have.

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
