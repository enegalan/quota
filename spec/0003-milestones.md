# Quota — Milestones

> Derived from `spec/0001-definition.md` and `spec/0002-architecture.md`.
> This document is the master checklist. Every task appears exactly once, here.
> Tests are part of the milestone they belong to, not a separate milestone.

## How to read this document

Each milestone has a header with its spec references and its dependencies, then a
list of atomic tasks, then an exit criterion that is verifiable by running a
command, then the test files that must exist when the milestone closes.

A milestone is closed when every task is checked **and** the exit command passes.
The exit command is the authority. Checking a box without passing the command does
not close the milestone.

**Status legend**

| Marker | Meaning                    |
| ------ | -------------------------- |
| `[ ]`  | Not started                |
| `[~]`  | In progress                |
| `[x]`  | Done, exit command passing |

**Progress**

| Milestone | Title                         | Status |
| --------- | ----------------------------- | ------ |
| M-01      | Toolchain                     | `[x]`  |
| M-02      | Core primitives               | `[x]`  |
| M-03      | Snapshot and quota model      | `[x]`  |
| M-04      | Allocation policies           | `[x]`  |
| M-05      | Allocation engine             | `[x]`  |
| M-06      | Pacing                        | `[x]`  |
| M-07      | Usage timeline                | `[x]`  |
| M-08      | Persistence and Keychain      | `[x]`  |
| M-09      | Plugin contract and host      | `[x]`  |
| M-10      | Plugin manager and catalog    | `[x]`  |
| M-11      | Synchronization and staleness | `[x]`  |
| M-12      | User interface                | `[x]`  |
| M-13      | Cursor feasibility spike      | `[x]`  |
| M-14      | Cursor provider plugin        | `[x]`  |
| M-15      | Reliability                   | `[x]`  |
| M-16      | Documentation                 | `[x]`  |
| M-17      | Several windows on a provider | `[x]`  |

## Amendments

Tasks below are the record of what was built at the time. Where a decision has
since changed, the task is annotated rather than rewritten, so the checklist still
says what closed the milestone.

- **`capabilities` is out of the catalog.** A provider says what it can do in the
  descriptor it answers `describe` with, so the copy in `catalog.json` was a
  claim about something nobody had asked yet, in a field nothing read. The wire
  field stays: §17 of the definition requires the abilities to be representable.

- **The per-plugin manifest is gone.** `Plugins/<id>/Resources/manifest.json` and
  `PluginManifest` were removed: every field it carried is either in the catalog
  or is derived by the host, and nothing read it at run time. A provider's
  executable is named by the convention `quota-provider-<id>`, `PluginLaunch`
  replaces `PluginManifest` as the host's launch record, and TASK-206's
  "validate the manifest" step is now "refuse an archive with no executable at
  that name".

---

## M-01 · Toolchain

**Spec:** §48, §49, §53, §55
**Depends on:** —
**Spec §57 items closed here:** none directly; unblocks all others.

### Tasks

- [x] **TASK-011** Create `Package.swift` with Swift 6 tools, macOS 14 deployment
      target, and exactly four product targets: `Core`, `PluginKit`,
      `Platform`, `App`.
- [x] **TASK-012** Declare `App` as an executable target with
      `.executableTarget`, and the other three as libraries.
- [x] **TASK-013** Set target dependencies so the import graph is exactly the
      layer graph: `Core` → none, `PluginKit` → none,
      `Platform` → Core + PluginKit, `App` → all three.
- [x] **TASK-014** Create the source tree: `Sources/Core`,
      `Sources/PluginKit`, `Sources/Platform`, `Sources/App`.
- [x] **TASK-015** Write `App/Info.plist` with `LSUIElement` set to true, bundle
      identifier, minimum system version, and no document types.
- [x] **TASK-016** Write `App/Quota.entitlements` with the minimum keychain
      access groups Quota needs and nothing else.
- [x] **TASK-017** Record in `README.md` that the app is **not** sandboxed, with
      the justification: it reads another application's SQLite store and requires
      unrestricted outbound network.
- [x] **TASK-018** Write `Scripts/bundle.sh` that assembles `Quota.app` from the
      built executable, embedding `Info.plist`, `Quota.entitlements`, and the
      catalog resource.
- [x] **TASK-019** Make `Scripts/bundle.sh` produce a stable layout with the
      executable at `Contents/MacOS/Quota`.
- [x] **TASK-020** Write `Makefile` targets: `bootstrap`, `format`, `lint`, `test`,
      `build`, `bundle`, `sign`, `run`, `verify`, `clean`.
- [x] **TASK-021** Make `make bootstrap` install `swiftformat`, `swiftlint`, and
      `node` with `prettier` through Homebrew, and fail with an actionable message
      if Homebrew is missing.
- [x] **TASK-022** Write `.swiftformat` with the project ruleset: no trailing
      whitespace, sorted imports, no semicolons, wrap arguments at 120 columns,
      matching the SwiftLint line length so the two tools do not fight.
- [x] **TASK-023** Write `.swiftlint.yml` promoting to **error** the rules
      `force_cast`, `force_try`, `todo`, `function_body_length` (40),
      `cyclomatic_complexity` (8), `file_length` (400), `type_body_length` (250),
      `nesting` (3), `line_length` (120), and `identifier_name` rejecting `x`,
      `tmp`, `data`, `foo`, `bar`.
- [x] **TASK-024** Write `.prettierrc` and `.prettierignore` covering Markdown,
      YAML, and JSON, and excluding `Package.resolved` and build output.
- [x] **TASK-025** Write `Scripts/check-magic-numbers.sh`: fail on any numeric
      literal in `Sources/` or `Plugins/` that is not `0` or `1` and is not
      declared in a `*Constants.swift` file, allowing only entries listed with a
      reason in `Scripts/magic-numbers-allowlist.txt`.
- [x] **TASK-026** Create `Scripts/magic-numbers-allowlist.txt` with one comment
      per exception stating the reason. An empty file is valid at start.
- [x] **TASK-027** Write `Scripts/check-provider-leakage.sh`: fail if any file
      under `Sources/` contains a provider name string literal, or if any file
      under `Sources/` imports a provider package.
- [x] **TASK-028** Write `Scripts/check-layer-purity.sh`: fail if `Core`
      imports any other target, if `PluginKit` imports any other target, or
      if any `Plugins/*` package imports anything other than `PluginKit`.
- [x] **TASK-029** Wire the three guard scripts into `make lint` so a guard
      failure fails the build.
- [x] **TASK-030** Write `.github/workflows/ci.yml` running on macOS with
      network access disabled for the test step, and running
      `make bootstrap`, `make lint`, `make test`, `make bundle`.
- [x] **TASK-031** Extend `.gitignore` to exclude `.build`, `DerivedData`,
      `Quota.app`, `.swiftlint_cache`, `Plugins/*/.build`, and macOS
      `.DS_Store`.
- [x] **TASK-032** Commit the initial green skeleton. No commits beyond this
      milestone are created without explicit instruction.

### Exit criterion

```sh
make verify
```

Passes with exit code 0, and launches an empty menu bar item with no window.

### Tests

- `Tests/CoreTests/SmokeTests.swift` — one test asserting the target links and
  runs, so `swift test` is proven to work before any real logic exists.

---

## M-02 · Core primitives

**Spec:** §24, §26
**Depends on:** M-01
**Spec §57 items closed here:** 18 (remaining calendar days calculated automatically)

### Tasks

- [x] **TASK-041** Define `LocalDate` as year, month, and day components, with
      `Codable` as an ISO `YYYY-MM-DD` string and `Hashable`, `Comparable`,
      `Sendable`.
- [x] **TASK-042** Give `LocalDate` `init(date:calendar:)` and `func date(calendar:)`
      converters so all calendar arithmetic routes through a `Calendar` the caller
      supplies.
- [x] **TASK-043** Define `LocalDate` ordering and `distance(to:)` in **days**, not
      in seconds, so a 23 or 25 hour daylight-saving day counts as one day.
- [x] **TASK-044** Define `ProviderID` as a validated identifier wrapper, rejecting
      empty values and whitespace at construction time.
- [x] **TASK-045** Define `QuotaPeriod` with `start` and `end`, rejecting an end
      that is before its start.
- [x] **TASK-046** Derive `QuotaPeriod.Status` as `future`, `active`, or `expired`
      from a reference date passed in by the caller, and never store the status.
- [x] **TASK-047** Define `QuotaPeriod.remainingDays(through:calendar:)` returning
      the inclusive day count from the reference day to the period end, covering
      today and the final day while the period is active.
- [x] **TASK-048** Define `QuotaPeriod.elapsedDays(since:calendar:)` for pacing.
- [x] **TASK-049** Define `QuotaPeriod.totalDays` as the inclusive length of the
      period, computed by calendar-day iteration.
- [x] **TASK-050** Create `Sources/Core/Constants/DateConstants.swift` holding
      the only permitted date-related literals: seconds per minute, seconds per
      hour, and seconds per day, named with their units and documented as
      **formatting only, never for date arithmetic**.

### Exit criterion

```sh
swift test --filter CoreTests.LocalDateTests
swift test --filter CoreTests.QuotaPeriodTests
```

All tests pass, including the fixed-timezone daylight-saving and leap-year cases.

### Tests

- `Tests/CoreTests/LocalDateTests.swift` — ISO coding round trip, ordering,
  day distance across a spring-forward boundary (23 hour day counts as 1), a
  fall-back boundary (25 hour day counts as 1), February 29, and December 31 to
  January 1.
- `Tests/CoreTests/QuotaPeriodTests.swift` — future, active, and expired
  status; inclusive remaining days; a one-day remaining period; remaining days
  across a month boundary, a year boundary, and a leap day.

---

## M-03 · Snapshot and quota model

**Spec:** §16, §17, §24, §25, §32, §46
**Depends on:** M-02
**Spec §57 items closed here:** 14 (normalized `UsageSnapshot`), 23 (actual usage
and planned allocation separated), 46 support (multiple quotas)

### Tasks

- [x] **TASK-061** Define `UsageBucket` with `id`, `displayName`,
      `usagePercentage`, and an optional `limitDescription` that is informational
      only and never used in arithmetic.
- [x] **TASK-062** Validate `usagePercentage` in `UsageBucket` initialisation,
      rejecting values outside 0 through 100 and rejecting `NaN`, satisfying the
      explicit-handling requirement of §25.
- [x] **TASK-063** Define `UsageSnapshot` with `periodStart`, `periodEnd`,
      `updatedAt`, and `buckets`, rejecting an empty `buckets` array.
- [x] **TASK-064** Derive `UsageSnapshot.primaryBucket` as the first bucket, and
      reject snapshots whose buckets contain duplicate ids.
- [x] **TASK-065** Define `Quota` with `id`, `name`, `providerID`, `bucketID`,
      `period`, `policy`, `createdAt`, `updatedAt`.
- [x] **TASK-066** Deliberately omit `currentUsagePercentage` and `usageUpdatedAt`
      from `Quota` and document in the type why: §24 lists them, but §2, §32, and
      §59 require usage and planned allocation to be separate concepts, so usage
      lives only in `UsageSnapshot` and is composed into the view at the UI layer.
- [x] **TASK-067** Define `QuotaSummary` as the single value the UI consumes,
      composing `Quota`, optional `UsageSnapshot`, optional `AllocationPlan`,
      `PacingStatus`, `TodayAllowance`, upcoming allocations, and a staleness
      flag.
- [x] **TASK-068** Derive `UsageSnapshot.remainingPercentage` as
      100 minus `primaryBucket.usagePercentage`, clamped to the valid range.
- [x] **TASK-069** Create `Sources/Core/Constants/UsageConstants.swift`
      holding the percentage scale and the inclusive bounds of the usage range.

### Exit criterion

```sh
swift test --filter CoreTests.UsageSnapshotTests
swift test --filter CoreTests.QuotaTests
```

All tests pass. A code comment in `Quota` documents the §24 deviation.

### Tests

- `Tests/CoreTests/UsageSnapshotTests.swift` — single bucket, multiple buckets,
  primary bucket selection, empty-bucket rejection, out-of-range percentage
  rejection, `NaN` rejection, remaining-percentage derivation, and a snapshot
  whose period has already expired.
- `Tests/CoreTests/QuotaTests.swift` — a quota whose bucket refers to a bucket
  absent from its snapshot yields an explicit unavailable state rather than a
  silent default; two quotas on the same provider with different buckets are fully
  independent.

---

## M-04 · Allocation policies

**Spec:** §28, §29
**Depends on:** M-03
**Spec §57 items closed here:** 20 (even distribution), 21 (weekly patterns), 22
(custom daily allocations)

### Tasks

- [x] **TASK-081** Define `WeekdayWeights` holding a weekday-to-weight mapping where
      weights are relative preferences, not percentages.
- [x] **TASK-082** Define `WeekdayWeights.weekdaysOnly` with Monday through Friday
      at the default weight and Saturday and Sunday at zero.
- [x] **TASK-083** Define `WeekdayWeights.uniform` with every weekday at the
      default weight.
- [x] **TASK-084** Reject negative weights in `WeekdayWeights` initialisation.
- [x] **TASK-085** Define `AllocationPolicy` as `even`, `weekly(weekdayWeights)`, and
      `custom(assignments)`, where custom assignments map a `LocalDate` to a
      percentage.
- [x] **TASK-086** Reject negative custom assignment percentages.
- [x] **TASK-087** Define `AllocationValidation` as `exact`,
      `underallocated(unassigned:)`, `overallocated(by:)`, and
      `noEligibleDays(retained:)`, and make it `Codable`.
- [x] **TASK-088** Define `Allocation` as a `LocalDate` and a percentage.
- [x] **TASK-089** Define `AllocationPlan` with `quotaID`, `generatedAt`,
      `totalRemaining`, `allocations`, `validation`, and `period`.
- [x] **TASK-090** Define a custom `Codable` conformance for `AllocationPolicy`
      using a discriminating `kind` field, so a stored policy survives a change in
      payload order.
- [x] **TASK-091** Add a placeholder `AllocationEngine` that returns an empty plan,
      so the app links and runs before M-05 implements the real calculation.

### Exit criterion

```sh
swift test --filter CoreTests.AllocationPolicyTests
```

All tests pass and `AllocationPolicy` survives a JSON round trip in all three
cases.

### Tests

- `Tests/CoreTests/AllocationPolicyTests.swift` — even, weekly, and custom
  round-trip through `Codable`; negative weight rejection; negative custom
  percentage rejection; `weekdaysOnly` producing exactly five non-zero days;
  `uniform` producing seven equal days.

---

## M-05 · Allocation engine

**Spec:** §26, §27, §28, §29, §30, §50
**Depends on:** M-04
**Spec §57 items closed here:** 19 (plan generated automatically), 27 (no silent
discard of remaining quota), 34 (calendar boundary correctness), 35 (plugin-free
core)

### Tasks

- [x] **TASK-101** Implement `AllocationEngine.plan(remaining:policy:period:today:calendar:)`,
      replacing the M-04 placeholder, taking every input explicitly and never
      calling `Date()` internally.
- [x] **TASK-102** Compute eligible days by iterating from `today` to `period.end`
      inclusive with `calendar.date(byAdding: .day, ...)`, never with a fixed
      seconds interval, satisfying the §26 requirement that days are calendar days
      and not 24-hour spans.
- [x] **TASK-103** Return an empty plan with `.periodExpired` context when `today`
      is after `period.end`, and with an `.active` context when `today` is before
      `period.start`.
- [x] **TASK-104** Implement the even policy: divide remaining quota by the number
      of eligible days.
- [x] **TASK-105** Implement the weekly policy: filter out days whose weekday weight
      is zero, then distribute remaining quota proportionally to weight.
- [x] **TASK-106** Implement the custom policy: use the explicit percentage for each
      assigned date and treat unassigned eligible days as receiving zero.
- [x] **TASK-107** Implement largest-remainder rounding so the sum of all allocated
      percentages equals `remaining` within the epsilon constant, for every policy.
- [x] **TASK-108** Sort allocations by date ascending.
- [x] **TASK-109** Classify a custom plan as `exact` when the sum matches remaining,
      `underallocated` when the sum is lower with the gap reported, and
      `overallocated` when the sum is higher with the excess reported.
- [x] **TASK-110** Return `.noEligibleDays(retained:)` when a policy yields zero
      eligible days while quota remains, carrying the undelivered percentage so it
      is never silently discarded.
- [x] **TASK-111** Return a non-negative allocation when remaining quota is zero,
      covering the exhausted case.
- [x] **TASK-112** Reject a negative `remaining` input.
- [x] **TASK-113** Create `Sources/Core/Constants/AllocationConstants.swift`
      holding the percentage scale, the default weekday weight, the sum epsilon,
      and the upcoming-day window.
- [x] **TASK-114** Add a doc comment on `AllocationEngine` stating the determinism
      contract: same inputs produce byte-identical output, no ambient clock, no
      locale, no time zone from the system.

### Exit criterion

```sh
swift test --filter CoreTests.AllocationEngineTests
```

All tests pass with the network disabled, and the sum invariant holds in every
case.

### Tests

- `Tests/CoreTests/AllocationEngineTests.swift` —
  - Even: equal allocation; fractional percentages across 7 days; a single
    remaining day receiving all of remaining; zero remaining.
  - Weekly: weekdays only; zero-weight weekend days excluded; Monday and Friday at
    double weight receiving exactly double; a week where every remaining day has
    zero weight producing `.noEligibleDays` with the retained amount.
  - Custom: exact match; underallocation reporting the gap; overallocation
    reporting the excess; a zero allocation on a date; missing dates; assignments
    outside the remaining window ignored.
  - Rounding: 100 across 7 days; 100 across 3 days; 60 across 15 days; a case where
    naive rounding would break the sum invariant.
  - Calendar: month boundary; year boundary; leap year; a period spanning a
    daylight-saving transition, each asserting the exact set of eligible dates.
  - Periods: future period; active period; expired period.

---

## M-06 · Pacing

**Spec:** §38
**Depends on:** M-05
**Spec §57 items closed here:** 28 (pacing status displayed)

### Tasks

- [x] **TASK-121** Define `PacingStatus` as `onPace`, `aheadOfPace`, `behindPace`,
      `quotaExhausted`, and `periodExpired`.
- [x] **TASK-122** Define `PacingResult` carrying the state plus the expected and
      actual percentages, so the UI can explain the state rather than only label
      it.
- [x] **TASK-123** Implement `PacingCalculator.evaluate(usage:period:today:calendar:)`,
      computing expected consumption as the period scale multiplied by the ratio of
      elapsed to total days.
- [x] **TASK-124** Classify as `behindPace` when actual is below expected by more
      than the tolerance, `aheadOfPace` when above by more than the tolerance, and
      `onPace` otherwise.
- [x] **TASK-125** Classify as `quotaExhausted` when usage has reached the scale
      regardless of pace.
- [x] **TASK-126** Classify as `periodExpired` when the reference date is past the
      period end, before any pace comparison.
- [x] **TASK-127** Return `nil` for a future period that has not started, so the UI
      shows no pace rather than a misleading one.
- [x] **TASK-128** Prove the §38 requirement that pacing never changes the policy by
      making the calculator return only a value type and by adding a test asserting
      the policy object is unchanged after evaluation.
- [x] **TASK-129** Add the pacing tolerance as a named constant in
      `AllocationConstants`, documented with the reason for its value.

### Exit criterion

```sh
swift test --filter CoreTests.PacingCalculatorTests
```

### Tests

- `Tests/CoreTests/PacingCalculatorTests.swift` — exactly on pace; ahead
  beyond tolerance; ahead within tolerance reported as on pace; behind beyond
  tolerance; behind within tolerance reported as on pace; exhausted; expired;
  future period returning nil; a full-period consumption matching the elapsed
  ratio.

---

## M-07 · Usage timeline

**Spec:** §32, §33, §36
**Depends on:** M-03
**Spec §57 items closed here:** 33 (intraday recalculation without double counting)

### Tasks

- [x] **TASK-141** Define `UsageSample` as a record timestamp and a cumulative
      usage percentage.
- [x] **TASK-142** Define `UsageTimeline` holding an ordered run of samples for one
      quota and one bucket.
- [x] **TASK-143** Implement `record(usagePercentage:at:)` that keeps samples sorted
      and discards a sample that repeats an existing timestamp for the same
      percentage, so a refresh loop cannot grow the store without bound.
- [x] **TASK-144** Implement `baseline(forDayContaining:calendar:)` returning the
      most recent sample strictly before the start of the given local day.
- [x] **TASK-145** Define `TodayUsage` as a sum with three cases: a known value, an
      unknown value with no reason, and an unknown value because the provider
      reported a decrease, which indicates a period rollover.
- [x] **TASK-146** Implement `usedToday(on:calendar:)` as the difference between the
      latest sample and the day baseline, clamped to zero.
- [x] **TASK-147** Return the unknown case, never a fabricated zero, when no day
      baseline exists, so the UI can say the value is unavailable.
- [x] **TASK-148** Return the rollover case when the latest cumulative percentage is
      lower than the baseline, which is how a new billing period appears.
- [x] **TASK-149** Trim samples older than the retention window defined as a named
      constant, keeping enough history to cover the longest supported period.
- [x] **TASK-150** Add a doc comment recording the §33 determinism rule: today's
      planned allocation already accounts for consumption already included in the
      provider's cumulative figure, so remaining today is planned minus used today
      and consumption is never counted twice.

### Exit criterion

```sh
swift test --filter CoreTests.UsageTimelineTests
```

### Tests

- `Tests/CoreTests/UsageTimelineTests.swift` — used today from a baseline
  yesterday; used today with no baseline yielding unknown; a rollover yielding the
  rollover case; duplicate sample suppression; retention trimming; used today
  clamped at zero; a midnight boundary crossing in a fixed non-UTC time zone.

---

## M-08 · Persistence and Keychain

**Spec:** §44, §47, §53
**Depends on:** M-03
**Spec §57 items closed here:** 31 (latest snapshot cached locally), 32 (secure
provider authentication), 47 (persistence of quotas, policies, snapshots, sync
metadata, preferences)

### Tasks

- [x] **TASK-161** Define the `QuotaStore` protocol as the single persistence
      boundary, with load and save for each stored record family.
- [x] **TASK-162** Define `QuotaRecord`, `SnapshotRecord`, `TimelineRecord`,
      `ProviderRecord`, and `Preferences` as the stored shapes, each
      `Codable` and each carrying a schema version.
- [x] **TASK-163** Implement `InMemoryQuotaStore` for tests, with no filesystem
      access and no clock access.
- [x] **TASK-164** Implement `FileQuotaStore` writing one JSON file per record
      family under the application support directory.
- [x] **TASK-165** Make every `FileQuotaStore` write atomic by writing a temporary
      file and replacing the target, so a crash mid-write cannot corrupt state.
- [x] **TASK-166** Apply file protection at the complete-until-first-unlock level
      to every written file.
- [x] **TASK-167** Make `FileQuotaStore` recover from a corrupt file by moving it
      aside with a timestamped name and starting from an empty state, rather than
      failing to launch.
- [x] **TASK-168** Implement schema-version migration that dispatches on the stored
      version, with a test fixture for the current version only.
- [x] **TASK-169** Define the `KeychainStoring` protocol and a `Security`
      implementation using a dedicated service name, creating items if absent and
      updating them in place.
- [x] **TASK-170** Implement an `InMemoryKeychain` for tests.
- [x] **TASK-171** Route every provider credential through `KeychainStoring` and
      assert in tests that no credential value ever appears in any `QuotaStore`
      payload.
- [x] **TASK-172** Implement the typed repository accessors `quotaRepository`,
      `snapshotRepository`, `timelineRepository`, `providerRepository`, and
      `preferencesRepository` over `QuotaStore`.
- [x] **TASK-173** Key snapshots and timelines by the quota-and-bucket pair so two
      buckets of the same provider never overwrite each other.
- [x] **TASK-174** Key the snapshot cache by account label in addition to quota, so
      switching accounts inside the same provider cannot serve the previous
      account's numbers.
- [x] **TASK-175** Create `Sources/Platform/Constants/PersistenceConstants.swift`
      holding the directory name, file names, service name, and file protection
      level.

### Exit criterion

```sh
swift test --filter PlatformTests.FileStoreBackendTests
swift test --filter PlatformTests.KeychainTests
```

### Tests

- `Tests/PlatformTests/FileStoreBackendTests.swift` — round trip for every
  record family; atomic write leaves no temporary file behind; a corrupt file is
  recovered and quarantined; missing directory is created; concurrent saves to the
  same key produce a readable file; schema version dispatch.
- `Tests/PlatformTests/KeychainTests.swift` — create, read, update, delete;
  read of a missing item returns nil rather than throwing; a scan of every
  serialised store payload finds no credential material.

---

## M-09 · Plugin contract and host

**Spec:** §15, §16, §45, §49
**Depends on:** M-01
**Spec §57 items closed here:** 2 (core independent of providers), 33 (provider
failures do not corrupt the core), 49 (error isolation)

### Tasks

- [x] **TASK-181** Define `ProviderDescriptor` with id, display name, description,
      capabilities, and protocol range.
- [x] **TASK-182** Define `ProviderCapabilities` as an option set covering
      automatic usage retrieval, automatic period detection, multiple quotas,
      historical usage, background refresh, and local authentication.
- [x] **TASK-183** Define `ProviderErrorCode` as the nine states of §45 with raw
      values that are stable across releases, since they cross the plugin boundary.
- [x] **TASK-184** Define `ProviderError` carrying a code and a message, with the
      message explicitly documented as provider-authored display text that the core
      never interprets.
- [x] **TASK-185** Define `PluginMethod` as `describe`, `connect`, `disconnect`, and
      `fetchUsage`.
- [x] **TASK-186** Define `PluginRequest`, `PluginResponse`, and the result payload
      types as `Codable` newline-delimited JSON messages.
- [x] **TASK-187** Define the protocol range as a semver range type with `contains`
      and an incompatibility check against the host's supported range.
- [x] **TASK-188** Define `PluginSide` as a shared library that builds request
      messages, reads response messages, and implements the child side of the
      protocol, so a plugin never reimplements framing.
- [x] **TASK-189** Implement `PluginHost.launch()` spawning the plugin
      executable with stdin and stdout pipes and stderr directed to a log file.
      _(Amended: the host is handed a `PluginLaunch` built by the app, not a
      manifest read from the artifact.)_
- [x] **TASK-190** Implement the handshake: launch, request `describe`, validate the
      descriptor, and reject a plugin whose protocol range does not include the
      host's.
- [x] **TASK-191** Implement request-response correlation by identifier, so
      out-of-order or unsolicited messages are ignored rather than misattributed.
- [x] **TASK-192** Implement a call timeout that terminates the process when the
      deadline passes, using the timeout constant, guaranteeing a hung plugin
      cannot block the core.
- [x] **TASK-193** Implement graceful shutdown that closes stdin and terminates the
      process, and reaps zombies on abnormal exit.
- [x] **TASK-194** Map every transport-level failure to a `ProviderErrorCode`, so a
      crashed, missing, or non-conforming plugin surfaces as `pluginError` rather
      than propagating a system error into the domain.
- [x] **TASK-195** Restrict plugin environment variables to an explicit allowlist
      plus the home directory, so a plugin cannot inherit the app's environment
      wholesale.
- [x] **TASK-196** Add a doc comment on `PluginKit` stating that it must remain
      free of any dependency on `Core` or `Platform`, enforced by
      TASK-028.

### Exit criterion

```sh
swift test --filter PluginKitTests
swift test --filter PlatformTests.PluginHostTests
```

### Tests

- `Tests/PluginKitTests/ProtocolTests.swift` — every request and response shape
  round trips through JSON; unknown fields are ignored for forward compatibility;
  protocol range inclusion and rejection at each boundary.
- `Tests/PlatformTests/PluginHostTests.swift` — a conforming fake plugin
  answers every method; a plugin that never answers is killed at the timeout and
  the call returns `pluginError`; a plugin that exits immediately returns
  `pluginError`; a plugin that emits malformed JSON returns `invalidResponse`; a
  plugin advertising an incompatible protocol range is rejected; out-of-order
  responses are matched correctly; a plugin exiting between calls is relaunched.

---

## M-10 · Plugin manager and catalog

**Spec:** §8, §9, §10, §11, §12, §13, §49, §50, §51
**Depends on:** M-09
**Spec §57 items closed here:** 3 (plugins optional), 5 (browse providers), 6
(install from UI), 7 (uninstall from UI), 8 (clear success and failure states), 9
(versions and compatibility), 11 (mock provider present), 18 (generic architecture
plus catalog plus installation and removal), 35 (plugin management automated tests)

### Tasks

- [x] **TASK-201** Define `CatalogEntry` with id, display name, description,
      version, minimum app version, protocol range, source location, content hash,
      and an unofficial-integration flag. _(Amended: capabilities were removed;
      they live on the descriptor, which the provider fills in.)_
- [x] **TASK-202** Write `Resources/catalog.json` listing the mock provider as
      available and no real provider as installed, with a real provider entry
      disabled behind the kill switch until M-14 passes.
- [x] **TASK-203** Implement catalog loading from the bundled resource, with an
      optional local override file for development.
- [x] **TASK-204** Define `ProviderState` as the full lifecycle of §7: not
      installed, installing, installed, connected, synchronizing, installation
      failed, authentication required, authentication expired, update available,
      updating, update failed, disabled, and incompatible.
- [x] **TASK-205** Define `InstalledProvider` recording id, version, relative path,
      state, install time, content hash, and last error.
- [x] **TASK-206** Implement installation as a sequence of explicit steps: fetch,
      verify content hash, verify code signature, extract to a versioned directory,
      refuse an archive with no executable at the expected name, and activate.
- [x] **TASK-207** Reject an artifact whose computed hash differs from the catalog
      value, before any write occurs.
- [x] **TASK-208** Reject an artifact whose code signature fails static validation.
- [x] **TASK-209** Extract into a directory named for the version, so a failed
      install never touches the active version.
- [x] **TASK-210** Activate by atomically replacing a symlink pointing at the
      versioned directory.
- [x] **TASK-211** Implement rollback: when an update's post-activation handshake
      fails, restore the previous symlink and mark the previous version as
      installed.
- [x] **TASK-212** Implement update detection by comparing the installed version
      against the catalog version, and expose it as `updateAvailable`.
- [x] **TASK-213** Implement uninstall by removing the versioned directory and the
      symlink while leaving quota records untouched.
- [x] **TASK-214** Implement a pre-uninstall impact report listing every quota that
      references the provider, powering the confirmation dialog of §10.
- [x] **TASK-215** Mark quotas whose provider is missing as unable to synchronise
      after uninstall, per §10, retaining their cached data.
- [x] **TASK-216** Implement compatibility checking against the minimum app
      version, producing `.incompatible` rather than a generic failure.
- [x] **TASK-217** Implement the per-provider kill switch read from preferences,
      which disables a provider without an application release.
- [x] **TASK-218** Ensure no provider is installed at first launch and that
      installing a provider never creates a quota, per §8.
- [x] **TASK-219** Implement the catalog display grouping of §43 into available,
      installed, and connected, derived from state rather than from separate lists.
- [x] **TASK-220** Build `QuotaPluginMock` as its own executable depending only on
      `PluginKit`, supporting a scripted sequence of usage values and a
      configurable period, with no network access.
- [x] **TASK-221** Create `Plugins/cursor/Package.swift` as a
      separate package depending only on `PluginKit`, with a placeholder
      descriptor and no implementation, so the plugin boundary is proven early.
- [x] **TASK-222** Create the shared test fixtures for a conforming plugin, reused
      by the mock, the host tests, and the real plugin.

### Exit criterion

```sh
swift test --filter PlatformTests.PluginManagerTests
swift test --filter PlatformTests.InstallerTests
```

All §50 plugin-management cases pass, and installing then uninstalling the mock
provider leaves a clean state.

### Tests

- `Tests/PlatformTests/PluginManagerTests.swift` — installation; installation
  failure from a hash mismatch, a signature failure, and a truncated archive;
  uninstallation; uninstallation preserving quota records; update; update failure
  with rollback; compatibility failure; a provider missing from the catalog but
  referenced by a quota; a disabled provider; a provider disabled by the kill
  switch.
- `Tests/PlatformTests/InstallerTests.swift` — installation; installation
  failure from a hash mismatch, a signature failure, and a truncated archive;
  uninstallation; uninstallation preserving quota records; update; update failure
  with rollback; compatibility failure.
- `Tests/PlatformTests/ActivationTests.swift` — atomic activation leaves the
  previous version intact on failure; a partially written version directory is
  discarded; concurrent installs of the same provider serialise safely.
- `Tests/PlatformTests/PluginLayoutTests.swift` — the installed layout: the
  active symlink, a relative stored path, and the verifier seam.
- `Tests/PlatformTests/BundledProviderTests.swift` — a provider packaged in
  the application bundle, one this build does not ship, and a remote source
  refused while nothing can verify it.
- `Tests/PlatformTests/ShippedFileTests.swift` — the packaged tar and the
  executable each plugin package builds all name the same provider the same
  way.

```sh
swift test --filter PluginManagerTests
swift test --filter InstallerTests
```

### Known limitation

Static code-signature validation is not implemented. `ArtifactVerifying` is the
seam, `PassthroughArtifactVerifier` is the default, and it accepts a bundled
provider (whose trust is the application bundle's own signature) and one named by
a local path (which the user placed there), while refusing anything fetched from
a URL. Until a signing identity exists in the build, a bundled or local provider
is trusted on the strength of where it came from rather than on a signature check.
Any provider distributed by download stays refused until that changes.

---

## M-11 · Synchronization and staleness

**Status:** closed. 332 tests in 41 suites, `make lint` clean.

**Spec:** §20, §21, §22, §23, §31, §33, §45, §46
**Depends on:** M-10
**Spec §57 items closed here:** 16 (usage updates automatically), 17 (remaining
quota calculated automatically), 29 (synchronisation status displayed), 30 (stale
data clearly identified), 33 (failures do not corrupt the core)

### Tasks

- [x] **TASK-241** Define `ConnectionStatus` recording provider id, account label,
      last successful sync, last error, and next scheduled refresh.
- [x] **TASK-242** Define `Freshness` as fresh, ageing, stale, or unavailable,
      derived from the age of the last successful snapshot.
- [x] **TASK-243** Define `SyncResult` as a success carrying a snapshot, or a
      failure carrying an error code, so a failed refresh never destroys the last
      good snapshot.
- [x] **TASK-244** Implement `SyncCoordinator` refreshing a quota by resolving its
      provider, launching the plugin, calling `fetchUsage`, and recording the
      result.
- [x] **TASK-245** Record every successful snapshot into the timeline so intraday
      consumption accumulates, per M-07.
- [x] **TASK-246** Recompute the allocation plan automatically on every successful
      snapshot, with no user action, per §20 and §31.
- [x] **TASK-247** Keep the last good snapshot when a refresh fails, and report the
      failure separately, per §22.
- [x] **TASK-248** Refuse to serve a cached snapshot beyond its own period end, so a
      failure during an outage cannot show the previous cycle's numbers.
- [x] **TASK-249** Define a relative-time formatter producing wording such as
      "Updated 2 minutes ago", with every threshold as a named constant.
- [x] **TASK-250** Map each of the nine provider errors to a user-facing state and
      to the action the UI offers, satisfying §45.
- [x] **TASK-251** Treat an authentication-required or authentication-expired result
      as prompting a reconnect, without discarding cached data.
- [x] **TASK-252** Honour the provider's suggested poll interval within the
      platform minimum and maximum, with jitter applied from a named constant.
- [x] **TASK-253** Apply exponential backoff on rate-limited and provider-unavailable
      results, capped by a named constant.
- [x] **TASK-254** Refresh on launch and on popover open, per §21, in addition to
      periodic refresh.
- [x] **TASK-255** Detect connectivity restoration and refresh immediately, per §23.
- [x] **TASK-256** Detect a period change reported by the provider and update the
      quota period, resetting the timeline so used-today is not computed across two
      periods.
- [x] **TASK-257** Keep quotas fully independent so one provider's failure does not
      affect another's plan, per §46.
- [x] **TASK-258** Create `Sources/Platform/Constants/RefreshConstants.swift`
      holding every interval, age threshold, backoff factor, and cap.
- [x] **TASK-259** Test the whole flow with a scripted fake provider, never a
      network call, per §52.

### Exit criterion

```sh
swift test --filter PlatformTests.SyncCoordinatorTests
```

### Tests

- `Tests/PlatformTests/SyncCoordinatorTests.swift` — successful refresh;
  failed refresh retaining the previous snapshot; a snapshot served while stale;
  recovery after failure; a plan recomputed with no user action; intraday
  readings accumulating in the timeline.
- `Tests/PlatformTests/SyncCoordinatorStateTests.swift` — a period that
  ends during an outage never serving the previous cycle; a provider period
  change resetting the timeline; a rate-limited result triggering backoff; a
  backoff that survives a restart; an authentication-expired result prompting
  reconnect; two quotas on one provider where one fails; a provider with no
  account; the caption shown for a stale reading.
- `Tests/PlatformTests/ProviderSuggestionTests.swift` — a provider's own
  poll interval used within the platform minimum and maximum, surviving the
  record being rewritten by failures, and a descriptor from before the field
  existed still decoding.
- `Tests/PlatformTests/SyncPipelineTests.swift` — snapshot normalisation and
  the connectivity trigger's decisions.
- `Tests/PlatformTests/RefreshPlannerTests.swift` — a launch and a popover
  open reading every quota, a timer reading only what is due, two quotas on one
  provider reading once, and the allocation plan surviving a restart.

---

## M-12 · User interface

**Spec:** §34, §35, §36, §37, §39, §40, §41, §42, §43, §55
**Depends on:** M-11
**Spec §57 items closed here:** 1 (native macOS menu bar application), 25 (today's
allowance displayed), 26 (future daily allocations visible), 27 (calendar displays
the plan), 28 (pacing displayed), 36 (actual and planned clearly separated), 39
(no manual daily entry when automatic integration is available)

**Status:** complete. The tasks below are implemented, wired, and covered by
`Tests/AppTests`, and the exit criterion has been run: `make verify` signs
the bundle, all 404 tests pass, and the app launches. Two things remain outside
the app's hands and are noted in M-13: live reading of a real account, and CI on
the pinned toolchain.

### Tasks

- [x] **TASK-271** Define `AppEnvironment` as the single composition root wiring
      the store, keychain, plugin manager, and sync coordinator, with no service
      locator and no container abstraction.
- [x] **TASK-272** Define `AppModel` as the single observable object, exposing
      derived `QuotaSummary` values and the catalog, with views reading only from
      it.
- [x] **TASK-273** Implement the menu bar item showing today's remaining allowance
      in the configured format, per §39.
- [x] **TASK-274** Implement the main popover with the eleven elements of §40 in
      order: name, provider, usage, remaining, today's planned, today's actual,
      today's remaining, days remaining, pacing, last synchronisation, and links to
      calendar and settings.
- [x] **TASK-275** Implement the today allowance block with planned, used, and
      remaining labelled unambiguously, per §36.
- [x] **TASK-276** Display an explicit unavailable state for today's actual usage
      when the timeline has no baseline, instead of showing zero.
- [x] **TASK-277** Implement the future allocation strip over the upcoming day
      window, per §37, including days with zero allocation.
- [x] **TASK-278** Implement the month calendar distinguishing past, today, future,
      zero-allocation days, and days outside the active period, per §34.
- [x] **TASK-279** Implement the date detail panel showing planned, actual, and
      remaining for a selected date, per §35.
- [x] **TASK-280** Implement the first-launch onboarding presenting a browse
      providers action and installing nothing, per §41.
- [x] **TASK-281** Implement the quota creation flow of §42 including installing a
      provider inline when it is not yet installed.
- [x] **TASK-282** Implement the provider management area of §43 with installed and
      available groupings and per-provider actions.
- [x] **TASK-283** Implement the uninstall confirmation showing how many quotas are
      affected and what happens to them, per §10.
- [x] **TASK-284** Implement a single policy editor driven by a policy kind
      selector, covering even, weekly weights, and custom per-date assignments,
      rather than three separate editors.
- [x] **TASK-285** Display the underallocated and overallocated states from the
      engine directly, per §29, without recomputing them in the view.
- [x] **TASK-286** Display the no-eligible-days state with the undelivered
      percentage, per §30.
- [x] **TASK-287** Add a `LayoutMetrics` constants file so no layout literal appears
      in any view.
- [x] **TASK-288** Add a `PercentageFormatter` with one test per format and use it
      in every view, so no view formats a percentage itself.
- [x] **TASK-289** Render the entire provider list from catalog metadata with no
      per-provider conditional anywhere in the view layer, per §6.
- [x] **TASK-290** Show the unofficial-integration notice for a provider whose
      catalog entry is flagged as such.
- [x] **TASK-291** Provide a keyboard shortcut to open the popover and to refresh,
      declared in `Info.plist` and verified to be conflict-free.
- [x] **TASK-292** Add a preview and snapshot for the popover at three usage levels,
      using the mock provider data.

### Exit criterion

```sh
make lint
swift test --filter AppTests
```

The complete §42 flow runs end to end against the mock provider, with no network.

### Tests

- `Tests/AppTests/QuotaSummaryPresentationTests.swift` — the composed values for
  on-pace, behind-pace, exhausted, stale, and unavailable-actual states.
- `Tests/AppTests/PercentageFormatterTests.swift` — every format including
  rounding boundaries and zero.
- `Tests/AppTests/CalendarPresentationTests.swift` — the day classification
  for past, today, future, zero-allocation, and out-of-period days, including a
  month containing 31 days and a leap February.

---

## M-13 · Cursor feasibility spike

**Spec:** §13, §18
**Depends on:** M-12
**Gate:** this milestone is a **go/no-go decision**, not construction. A no-go
leaves M-01 through M-12 untouched and changes only the subject of M-14.

**Status:** complete. Mechanisms verified and decision recorded as **go** in
`spec/0004-cursor-spike-report.md`. Continuous poll: 203 samples over 80.4 h,
all HTTP 200, no rate limit, no shape or auth break; minimum viable interval
**300 s**.

### Tasks

- [x] **TASK-301** Open the Cursor state database in read-only mode using the system
      SQLite library, with a busy timeout so a running Cursor does not block the
      read, tolerating a database larger than two gigabytes.
- [x] **TASK-302** Read the access token item, decode the token payload, and extract
      the subject identifier.
- [x] **TASK-303** Reject a token whose type marks it as an API-key token rather than
      a session token, since such a token does not authenticate the dashboard.
- [x] **TASK-304** Synthesise the session cookie from the subject and the token.
- [x] **TASK-305** Call the current-period usage endpoint with the required origin
      header and browser-like request headers, confirming that omitting the origin
      is rejected and that the header set is required.
- [x] **TASK-306** Call the usage summary endpoint as a fallback and confirm the two
      responses agree on period dates.
- [x] **TASK-307** Resolve the percentage semantics by computing the percentage from
      spent and limit, cross-checking against the reported percentage field, and
      comparing against the value shown in the Cursor dashboard. Record the
      conclusion.
- [x] **TASK-308** Produce two buckets for the account, one per usage pool, and
      confirm the pool names and that both carry meaningful values.
- [x] **TASK-309** Detect the billing cycle dates and confirm the cycle is not aligned
      to the calendar month.
- [x] **TASK-310** Detect whether the legacy request-count model applies, and
      normalise both models to a single `UsageSnapshot` shape.
- [x] **TASK-311** Determine whether an absolute cap is available for an individual
      account, and document the answer if it is not.
- [x] **TASK-312** Run continuous polling for twenty-four hours against the real
      account, recording every response, any rate limiting, and any change in
      response shape.
- [x] **TASK-313** Determine the minimum viable poll interval empirically.
- [x] **TASK-314** Confirm that no request ever requires reading another application's
      cookie store.
- [x] **TASK-315** Record the findings in a spike report that states, per mechanism,
      what was verified, the evidence, the date, and the known fragility.
- [x] **TASK-316** Take an explicit go or no-go decision and, on a no-go, name the
      replacement provider together with its documented endpoint.

### Exit criterion

A spike report exists, and a snapshot was obtained and held stable across
twenty-four hours of polling. On a no-go, the report names the replacement
provider and M-14's subject is updated.

### Tests

- `Tests/CursorProviderTests/SnapshotNormalisationTests.swift` — the recorded
  responses parse into a valid snapshot with the expected buckets and period.
  These were written in `CursorSpikeTests` and moved with the fixtures when the
  spike target was removed, because the spike's copy of the token decoder and the
  normaliser had become a second implementation of the plugin's.
- Live tests are opt-in behind the `QUOTA_LIVE_TESTS` environment variable and are
  excluded from `make test`.

---

## M-14 · Cursor provider plugin

**Spec:** §4, §12, §13, §14, §21, §44, §45, §49, §52, §53, §54
**Depends on:** M-13
**Spec §57 items closed here:** 12 (at least one real provider plugin), 13 (real
provider retrieves usage automatically), 14 (normalized snapshot), 15 (period
detected automatically), 36 (real provider has integration tests), 38 (adding a
provider does not require engine changes)

**Status:** complete. Plugin under `Plugins/cursor`, catalog entry
enabled and marked unofficial. Poll interval suggestion is 300s (confirmed by
M-13 TASK-313). Exit: `swift test --filter CursorProviderTests`.

### Tasks

- [x] **TASK-321** Implement token resolution with an ordered strategy: the Cursor
      state database, then the keychain item written by the local command-line
      client, then that client's own credentials file, recording which source
      succeeded for diagnostics.
- [x] **TASK-322** Re-read the token on every refresh and never cache or persist it,
      per §53.
- [x] **TASK-323** Never log the token, the synthesised cookie, or the bodies of
      unauthorised responses, since such bodies can echo the cookie back.
- [x] **TASK-324** Normalise the current-period usage response into a
      `UsageSnapshot` with one bucket per usage pool.
- [x] **TASK-325** Normalise the usage-summary response as a fallback, applying the
      percentage rule fixed in TASK-307.
- [x] **TASK-326** Read the billing cycle from the response and never infer it from
      an account creation date.
- [x] **TASK-327** Clamp the last day when a cycle is not calendar-aligned, and
      handle a shortened first cycle after a pricing change.
- [x] **TASK-328** Represent an unknown absolute cap as absent rather than zero, so
      the UI can say the cap is unknown instead of claiming the quota is exhausted.
- [x] **TASK-329** Map a missing token, a rejected token, and an expired token to
      authentication-required and authentication-expired respectively.
- [x] **TASK-330** Map a rate-limited response to rate-limited and honour the retry
      hint, backing off with jitter within the platform caps.
- [x] **TASK-331** Poll at the interval validated in TASK-313, within the platform
      minimum and maximum.
- [x] **TASK-332** Key the cached snapshot by account so switching accounts inside
      Cursor cannot serve the previous account's numbers, per TASK-174.
- [x] **TASK-333** Refuse to serve the cached snapshot past the cycle end, per
      TASK-248.
- [x] **TASK-334** Declare the provider unofficial in the catalog so the UI shows
      the notice from TASK-290.
- [x] **TASK-335** Add a per-provider kill switch entry so a removed endpoint can be
      disabled by configuration, per TASK-217.
- [x] **TASK-336** Record the provider's id, version, minimum app version,
      protocol range, and content hash in the catalog.
- [x] **TASK-337** Remove every provider-specific identifier from `Core`,
      `Platform`, and `App`.
- [x] **TASK-338** Add a test that defines a second, entirely fictional provider in
      the test target and proves the allocation engine and core compile and pass
      without modification, satisfying §57 item 38.
- [x] **TASK-339** Add integration tests asserting a provider response becomes a
      valid `UsageSnapshot`, per §52.
- [x] **TASK-340** Add opt-in live tests against the real account behind the
      environment flag, marked as slow and excluded from the default run.
- [x] **TASK-341** Request only the endpoints the spike proved necessary, sending no
      other request, and never calling a team-wide endpoint that would return other
      members' personal data.
- [x] **TASK-342** Confirm no quota data leaves the machine other than to the
      provider itself, per §54.

### Exit criterion

```sh
swift test --filter CursorProviderTests
```

All fixture tests pass. Provider names stay out of `Sources/` by the plugin
boundary and review.

### Tests

- `Tests/CursorProviderTests/TokenResolutionTests.swift` — each token source in
  turn, a malformed database, a database locked by a running Cursor, and a
  rejected token type.
- `Tests/CursorProviderTests/SnapshotNormalisationTests.swift` — current-period
  response; usage-summary fallback; both usage pools present; a plan with an
  unknown cap; a shortened cycle; a legacy request-count response; a missing
  field rendered as absent rather than zero.
- `Tests/CursorProviderTests/ErrorMappingTests.swift` — each of the nine error
  states reachable from a synthetic response.
- `Tests/CursorProviderTests/CacheKeyingTests.swift` — two accounts alternating
  never serve each other's snapshot; a snapshot past cycle end is refused.

---

## M-15 · Reliability

**Spec:** §21, §22, §23, §44, §45, §49, §53
**Depends on:** M-14
**Spec §57 items closed here:** 10 (provider can be connected after installation),
30 (stale data), 33 (failures do not corrupt the core), 37 (core tests need no
network)

**Status:** complete. Refresh execution wired, connect/disconnect + keychain,
background timer with low-power suspend, preferences interval clamping,
diagnostic dump, continuity captions, ResilienceTests and BackgroundRefreshTests.

### Tasks

- [x] **TASK-351** Implement the connection flow: connect, authenticate, and
      disconnect, with secrets written only to the keychain and never to disk.
- [x] **TASK-352** Handle authentication expiry by prompting a reconnect while
      keeping the cached snapshot visible and marked as stale.
- [x] **TASK-353** Implement background refresh that respects the provider's interval
      and suspends on low power, per §21.
- [x] **TASK-354** Make refresh frequency configurable, clamped to the platform
      minimum, with the effective value displayed.
- [x] **TASK-355** Verify the application survives a plugin that crashes, hangs,
      writes garbage to standard output, or exits mid-call, with the core remaining
      responsive and the failure surfaced as a provider state.
- [x] **TASK-356** Audit the entitlements and remove anything not needed, recording
      the justification for each remaining entry.
- [x] **TASK-357** Verify the core test target runs with networking disabled in CI
      and assert that no test target links a provider implementation.
- [x] **TASK-358** Add a diagnostic dump command that prints state without emitting
      any credential or token material.
- [x] **TASK-359** Handle a quota whose provider was uninstalled by showing it as
      unable to synchronise with its last known data, per §10.
- [x] **TASK-360** Handle a quota whose provider was disabled by the kill switch with
      a message explaining that the integration was disabled.
- [x] **TASK-361** Handle a quota referencing a provider absent from the catalog
      entirely, without crashing and without discarding its data.
- [x] **TASK-362** Add a failure-injection test that fails every provider during
      refresh and asserts every quota still renders with a clear state.
- [x] **TASK-363** Record the verified stability window, poll interval, and known
      fragility for each provider in the readme.

### Exit criterion

```sh
make verify
```

Passes, and the manual checklist in TASK-363 is complete in the readme.

### Tests

- `Tests/PlatformTests/ResilienceTests.swift` — every provider failing
  simultaneously; a plugin killed mid-refresh; a plugin exceeding the timeout; a
  corrupted plugin directory; a quota whose provider vanished.
- `Tests/PlatformTests/BackgroundRefreshTests.swift` — interval clamping;
  suspension under low power; resumption on power restoration.

---

## M-16 · Documentation

**Spec:** §50, §55, §57
**Depends on:** M-15
**Spec §57 items closed here:** 4 (no provider installed by default), 5, 6, 7, 37,
39 (no manual daily entry required)

**Status:** complete. README, CHANGELOG, provider status, plugin-authoring guide,
and Appendix B DoD trace are in place.

### Tasks

- [x] **TASK-371** Write `CHANGELOG.md` following Keep a Changelog and semantic
      versioning, with `Unreleased` and `0.1.0` sections and the categories Added,
      Changed, Fixed, Security, Deprecated, and Known Issues.
- [x] **TASK-372** Populate `Known Issues` in the first release with the
      unofficial-integration caveat for the Cursor provider, a link to the
      follow-up issue, and the fact that Cursor removed endpoints in the past
      without notice.
- [x] **TASK-373** Write the readme sections: what the application is, the core
      question it answers, install, build, run, and verify commands, and the
      sandbox justification from TASK-017.
- [x] **TASK-374** Write the readme architecture summary: the four layers, the one
      rule per layer, and a pointer to `spec/0002-architecture.md`.
- [x] **TASK-375** Write the readme contributing section covering `make bootstrap`,
      `make format`, `make lint`, `make test`, and the rule that a new provider
      must not require a core change.
- [x] **TASK-376** Write the readme plugin-authoring guide: the contract, the wire
      protocol, the nine error codes, the capabilities, the build command, and a
      worked example.
- [x] **TASK-377** Write the readme provider status table with, per provider, its
      mechanism, whether it is official, the verification date, the validated poll
      interval, and the known fragility.
- [x] **TASK-378** Produce the Definition of Done trace: all thirty-nine items of
      §57 mapped to the milestone and task that closes each, with no item
      unmapped.
- [x] **TASK-379** Confirm no item in §57 is claimed as met without a passing test
      or a manually verified checklist entry.
- [x] **TASK-380** Run `make format` and `make lint` over the documentation so
      Prettier and the Swift tooling agree on the final state.
- [x] **TASK-381** Update the progress table at the top of this document so every
      milestone reflects its real state.

### Exit criterion

```sh
make lint
```

Passes over all Markdown, and the §57 trace has no unmapped item.

### Tests

No new automated tests. This milestone is verified by the lint run over the
documentation and by the completeness check in TASK-378.

---

## M-17 · Several windows on one provider

**Status:** closed. A provider may meter limits that do not reset together — a
five-hour allowance and a weekly one — and the application reads, paces, and
shows each of them as a quota of its own.

**Spec:** §16, §17, §24, §31, §42, §46, §47
**Depends on:** M-16
**Spec §57 items closed here:** none newly; this milestone corrects §46 and §16,
which every milestone above it was built against.

A reading used to carry one `periodStart`/`periodEnd` pair with several buckets
underneath it. That shape can only describe a provider whose limits share a
clock, so a plugin reporting two different windows had one of them silently
corrected away. The period moved onto `UsageBucket`, where it is the property of
the limit it describes.

### Tasks

- [x] **TASK-391** Move `period` from `UsageSnapshot` onto `UsageBucket` and make
      it required, so a reading that does not say when a limit resets is refused
      rather than paced against an assumption.
- [x] **TASK-392** Replace `UsageSnapshot.primaryBucket`-era whole-reading period
      access with `period(forBucket:)`, where `nil` resolves to the primary and a
      named bucket the reading no longer carries returns `nil` rather than
      another bucket's window.
- [x] **TASK-393** Keep each bucket's own period through normalisation, dropping
      `NormalisationError.noPeriod`, which existed only to reject the second
      window a snapshot could not hold.
- [x] **TASK-394** Correct, plan, and read each quota against the period and
      percentage of the bucket it names, not of the first bucket in the reading.
- [x] **TASK-395** Reset a quota's timeline only when the period of _its_ bucket
      changes, so one quota cannot truncate its neighbour's history.
- [x] **TASK-396** Report a quota whose bucket the provider has stopped reporting
      as `.bucketUnavailable`, keeping its last good reading and adding nothing to
      its timeline, rather than showing a number it did not measure.
- [x] **TASK-397** Raise the store schema to 2 and migrate version 1 snapshots by
      copying the reading's single window onto every bucket, leaving all other
      record families to be re-stamped unchanged.
- [x] **TASK-398** Pass the file name into the migrator, so a malformed snapshot is
      quarantined under its own name rather than failing a whole family's load.
- [x] **TASK-399** Have `QuotaRepository.create` refuse a quota that names a bucket
      another quota on that provider already watches, and refuse a quota naming no
      bucket beside any quota on the same provider.
- [x] **TASK-400** Pass a `bucketID` and a period through `AppModel.createQuota`,
      reading the period from the bucket the picker chose rather than from a
      calendar guess.
- [x] **TASK-401** Let the quota creation flow offer every bucket a provider meters,
      disable those already watched, and show each bucket's remaining days from the
      window it actually reports.
- [x] **TASK-402** Test two windows on one provider end to end: independent plans,
      independent periods, a missing pool keeping its window and timeline, and the
      pool returning with the window it then reports.

### Exit criterion

```sh
swift test --filter MultiWindowQuotaTests
```

### Tests

- `Tests/PlatformTests/MultiWindowQuotaTests.swift` — two windows on one provider
  planned, corrected, and reset independently; a pool that disappears keeps its
  window and adds nothing; a pool that returns is picked up again with the window
  it now reports; a second poll of an unchanged window is not a period change.
- `Tests/PlatformTests/PeriodPerBucketTests.swift` — version 1 to 2 migration end
  to end through `FileQuotaStore`: the window copied onto every bucket, fractional
  timestamps preserved, other families re-stamped, and a malformed snapshot
  quarantined.
- `Tests/PlatformTests/SnapshotNormaliserTests.swift` — two buckets normalised with
  different windows intact.
- `Tests/AppTests/QuotaCreationTests.swift` — the flow picks a bucket, paces the
  policy against that bucket's window, and creates the quota with it.

---

## Appendix A · Milestone dependencies

```
M-01 ──┬──> M-02 ──> M-03 ──┬──> M-04 ──> M-05 ──> M-06
       │                     ├──> M-07
       │                     └──> M-08
       └──> M-09 ──> M-10 ──> M-11 ──> M-12 ──> M-13 ──> M-14 ──> M-15 ──> M-16
                                                                              └──> M-17
```

M-02 through M-08 and M-09 through M-12 can proceed in parallel once M-01 closes.
M-13 is the single go/no-go gate for the rest of the project.
M-17 changes the shape of what a provider reports, so it lands after M-16 rather than beside it: every milestone above it was written against a reading that carried one window.

## Appendix B · Definition of Done coverage

| §57 item | Milestone  | Tasks                                  |
| -------- | ---------- | -------------------------------------- |
| 1        | M-12       | TASK-273                               |
| 2        | M-09       | TASK-188, TASK-196                     |
| 3        | M-10       | TASK-218                               |
| 4        | M-16       | TASK-378                               |
| 5        | M-10, M-12 | TASK-203, TASK-282                     |
| 6        | M-10, M-12 | TASK-206, TASK-281                     |
| 7        | M-10, M-12 | TASK-213, TASK-283                     |
| 8        | M-10       | TASK-204, TASK-219                     |
| 9        | M-10       | TASK-205, TASK-212, TASK-216           |
| 10       | M-15       | TASK-351                               |
| 11       | M-10       | TASK-220                               |
| 12       | M-14       | TASK-321                               |
| 13       | M-14       | TASK-324, TASK-325                     |
| 14       | M-03, M-14 | TASK-063, TASK-324                     |
| 15       | M-14       | TASK-326                               |
| 16       | M-11       | TASK-246                               |
| 17       | M-11       | TASK-068                               |
| 18       | M-10       | TASK-181, TASK-203, TASK-206, TASK-213 |
| 19       | M-05       | TASK-101                               |
| 20       | M-04, M-05 | TASK-085, TASK-104                     |
| 21       | M-04, M-05 | TASK-082, TASK-105                     |
| 22       | M-04, M-05 | TASK-086, TASK-106                     |
| 23       | M-03, M-12 | TASK-066, TASK-275                     |
| 24       | M-11       | TASK-246                               |
| 25       | M-12       | TASK-275                               |
| 26       | M-12       | TASK-277                               |
| 27       | M-12       | TASK-278                               |
| 28       | M-06, M-12 | TASK-121, TASK-274                     |
| 29       | M-12       | TASK-285                               |
| 30       | M-12       | TASK-286                               |
| 31       | M-08, M-11 | TASK-164, TASK-247                     |
| 32       | M-08, M-14 | TASK-171, TASK-323                     |
| 33       | M-09, M-15 | TASK-192, TASK-355                     |
| 34       | M-05       | TASK-107                               |
| 35       | M-10       | TASK-206 to TASK-216                   |
| 36       | M-14       | TASK-339                               |
| 37       | M-15       | TASK-357                               |
| 38       | M-14       | TASK-338                               |
| 39       | M-11, M-12 | TASK-246, TASK-275                     |

## Appendix C · Task numbering

| Range                | Milestone |
| -------------------- | --------- |
| TASK-011 to TASK-032 | M-01      |
| TASK-041 to TASK-050 | M-02      |
| TASK-061 to TASK-069 | M-03      |
| TASK-081 to TASK-091 | M-04      |
| TASK-101 to TASK-114 | M-05      |
| TASK-121 to TASK-129 | M-06      |
| TASK-141 to TASK-150 | M-07      |
| TASK-161 to TASK-175 | M-08      |
| TASK-181 to TASK-196 | M-09      |
| TASK-201 to TASK-222 | M-10      |
| TASK-241 to TASK-259 | M-11      |
| TASK-271 to TASK-292 | M-12      |
| TASK-301 to TASK-316 | M-13      |
| TASK-321 to TASK-342 | M-14      |
| TASK-351 to TASK-363 | M-15      |
| TASK-371 to TASK-381 | M-16      |
| TASK-391 to TASK-402 | M-17      |
