# Quota — Architecture

> The architectural contract. Data schemas, layer responsibilities, the plugin
> wire protocol, persistence layout, invariants, and the guards that enforce them.
> Companion to `spec/0001-definition.md` (product and technical specification) and
> `spec/0003-milestones.md` (execution checklist).

---

## 1. The governing rule

> **Providers know how to obtain usage. Quota knows how to plan usage. The UI knows
> how to present the plan.**

Everything below exists to make that rule structurally true rather than merely
intended. A rule enforced by the shape of the code survives a deadline. A rule
enforced by discipline does not.

---

## 2. Layers

A layer exists **only if it crosses a physical boundary**. There are three such
boundaries, therefore three layers plus the composition root. There is no fourth
layer, and adding one requires justifying a new physical boundary.

| #   | Layer    | Module      | Single responsibility                                                              | May import               |
| --- | -------- | ----------- | ---------------------------------------------------------------------------------- | ------------------------ |
| 1   | Core     | `Core`      | Domain model and pure calculation. No I/O, no network, no files, no ambient clock. | nothing                  |
| 2   | Contract | `PluginKit` | The only vocabulary shared with plugins. Does not know the app exists.             | nothing                  |
| 3   | Platform | `Platform`  | All I/O: files, Keychain, host networking, processes, installation, the clock.     | Core, Contract           |
| 4   | App      | `App`       | SwiftUI interface and the composition root.                                        | Core, Contract, Platform |
| —   | Plugins  | `Plugins/*` | One provider each, in its own package.                                             | Contract only            |

### 2.1 Why Contract is a layer and not a file

`PluginKit` is the vocabulary a plugin shares with the host. It cannot live
inside `Platform`, because a provider package that imported `Platform`
would drag the entire I/O layer into every plugin and would make §6 impossible to
guarantee. It cannot live inside `Core`, because the core is the thing plugins
are forbidden from knowing.

So it is its own module, with no dependencies at all, and every plugin depends on
it exclusively. This is the only reason that module exists.

### 2.2 What deliberately has no layer of its own

These are recorded because their absence is a decision, not an oversight.

- **No repository per aggregate.** One `QuotaStore` actor with five typed
  accessors. Five files for five kinds of record is ceremony, not architecture.
- **No view model per feature.** One `@Observable AppModel`. Views are pure
  functions of `QuotaSummary` values.
- **No dependency injection container.** Explicit wiring in `AppEnvironment`.
- **No protocol without a real seam.** Exactly two: `QuotaStore` and `PluginHost`.
  Everything else is a concrete struct. A protocol whose only implementations are
  the real one and a test double, with no second real implementation and no
  genuine substitution, is indirection with no payoff.

### 2.3 The two protocol boundaries

```
QuotaStore          persistence          two implementations: in-memory (tests),
                                         file (application)
PluginHost          plugin execution     one implementation, tested with a real
                                         child process built from fixtures
```

---

## 3. Data schemas

These are the canonical shapes. They resolve the places where
`spec/0001-definition.md` says "conceptually" or leaves a gap.

### 3.1 Core — usage

```swift
/// One metered pool of quota. A provider with a single allowance reports one
/// bucket; a provider with several pools reports one per pool.
///
/// The window is here rather than on the snapshot because it is this pool's: a
/// provider may meter a five-hour allowance and a weekly one, and no single
/// snapshot-wide window describes both. It is required, so a reading that does not
/// say when a limit resets is refused rather than paced against an assumption.
struct UsageBucket: Sendable, Equatable, Codable, Identifiable {
    let id: String              // provider-scoped, stable across refreshes
    let displayName: String     // shown to the user verbatim
    let usagePercentage: Double // 0...100, validated on construction
    let period: QuotaPeriod     // the window THIS pool is measured over
    let limitDescription: String?  // display only, NEVER used in arithmetic
}

struct UsageSnapshot: Sendable, Equatable, Codable {
    let updatedAt: Date
    let buckets: [UsageBucket]  // non-empty, ids unique

    var primaryBucket: UsageBucket
    var remainingPercentage: Double   // 100 - primaryBucket.usagePercentage

    /// The window of the pool a quota reads. `nil` only when the quota names a
    /// pool this reading does not carry — the provider has stopped metering it.
    /// Nil rather than falling back to the primary, because another pool's window
    /// is not that quota's: a five-hour limit paced against a week is a plan for
    /// a quota the user does not have.
    func period(forBucket id: String?) -> QuotaPeriod?
}
```

A quota naming no bucket reads the primary, which is what `period(forBucket: nil)`
resolves to; the distinction is between "the primary pool" and "a pool this
reading no longer has".

Validation happens in initialisers, not at the call site, because a provider
plugin is out-of-process code and the core cannot trust it (§25: invalid provider
values must be rejected or handled explicitly).

### 3.2 Core — period and dates

```swift
/// A calendar date with no time and no zone. The key that makes the §26 class of
/// bugs impossible: a day is a day, not 86 400 seconds.
struct LocalDate: Sendable, Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int
    // Codable as ISO "YYYY-MM-DD"
    // distance(to:) counts days, not seconds
}

struct QuotaPeriod: Sendable, Equatable, Codable {
    let start: Date
    let end: Date                        // end >= start, enforced

    enum Status { case future, active, expired }
    func status(asOf: Date) -> Status    // derived, never stored
    func remainingDays(through: Date, calendar: Calendar) -> Int  // inclusive
    func elapsedDays(since: Date, calendar: Calendar) -> Int
    var totalDays: Int
}
```

### 3.3 Core — quota

```swift
struct Quota: Sendable, Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    let providerID: ProviderID
    let bucketID: String
    var period: QuotaPeriod     // provider overwrites when it supports auto-detect
    var policy: AllocationPolicy
    let createdAt: Date
    var updatedAt: Date
}
```

**Deviation from §24, recorded deliberately.** §24 lists `currentUsagePercentage`
and `usageUpdatedAt` among a quota's fields. §2, §32, and §59 require actual usage
and planned allocation to remain separate concepts. Both cannot hold if the quota
itself stores a usage number.

Resolution: **`Quota` never stores usage.** Usage lives only in `UsageSnapshot`,
persisted separately and keyed by quota and bucket. The UI composes the two into
`QuotaSummary` at the presentation layer. This is the interpretation of §2 that
§24 must yield to, and it is asserted by a test in M-03.

A quota references a **bucket**, not only a provider, because a provider may
expose several metered pools. A Cursor Pro account reports two.

### 3.4 Core — policies and plans

```swift
struct WeekdayWeights: Sendable, Equatable, Codable {
    var weights: [Int: Int]        // 1 = Monday ... 7 = Sunday, >= 0
    static let weekdaysOnly: Self
    static let uniform: Self
    func weight(for date: LocalDate, calendar: Calendar) -> Int
}

enum AllocationPolicy: Sendable, Equatable, Codable {
    case even
    case weekly(weekdayWeights: WeekdayWeights)
    case custom(assignments: [LocalDate: Double])   // percentages >= 0
    // custom Codable uses a discriminating `kind` field
}

struct Allocation: Sendable, Equatable, Codable {
    let date: LocalDate
    let percentage: Double
}

enum AllocationValidation: Sendable, Equatable, Codable {
    case exact
    case underallocated(unassigned: Double)
    case overallocated(exceeding: Double)
    case noEligibleDays(retained: Double)   // §30, quota is never discarded
}

struct AllocationPlan: Sendable, Equatable {
    let quotaID: UUID
    let generatedAt: Date
    let totalRemaining: Double
    let allocations: [Allocation]           // ascending by date, today inclusive
    let validation: AllocationValidation
    let period: QuotaPeriod
}
```

### 3.5 Core — timeline

```swift
/// Local accumulation of a provider's cumulative figure, so that "used today" can
/// be derived. No provider reports daily consumption, so this is the only way to
/// satisfy §32 and §36.
struct UsageSample: Sendable, Equatable, Codable {
    let recordedAt: Date
    let cumulativePercentage: Double
}

struct UsageTimeline: Sendable, Equatable, Codable {
    let quotaID: UUID
    let bucketID: String
    private(set) var samples: [UsageSample]   // ascending by date

    mutating func record(_ percentage: Double, at: Date)
    func baseline(forDayContaining date: Date, calendar: Calendar) -> UsageSample?
    func usedToday(on date: Date, calendar: Calendar) -> TodayUsage
}

enum TodayUsage: Sendable, Equatable {
    case known(Double)
    case unknown(reason: UnknownReason)

    enum UnknownReason: Sendable, Equatable {
        case noBaseline          // first sync of the day: no honest value exists
        case periodRollover      // cumulative went down: a new period began
    }
}
```

`unknown` is never collapsed to `0`. Showing zero would be a fabricated fact, and
§55 requires the interface to be transparent.

### 3.6 Core — pacing and presentation values

```swift
enum PacingStatus: Sendable, Equatable, Codable {
    case onPace, aheadOfPace, behindPace, quotaExhausted, periodExpired
}

struct PacingResult: Sendable, Equatable {
    let status: PacingStatus
    let expectedPercentage: Double
    let actualPercentage: Double
    let tolerance: Double
}

/// The single value the interface consumes. Composes domain values; adds no
/// calculation of its own.
struct QuotaSummary: Sendable, Equatable {
    let quota: Quota
    let snapshot: UsageSnapshot?
    let plan: AllocationPlan?
    let pacing: PacingResult?
    let today: TodayAllowance
    let upcoming: [FutureAllocation]
    let isStale: Bool
}

struct TodayAllowance: Sendable, Equatable {
    let planned: Double
    let used: TodayUsage        // unknown is representable and shown as such
    var remaining: Double?      // nil when `used` is unknown
}

struct FutureAllocation: Sendable, Equatable, Identifiable {
    var id: LocalDate
    let date: LocalDate
    let percentage: Double
}
```

### 3.7 Contract — the plugin vocabulary

```swift
struct ProviderID: Sendable, Hashable, Codable {
    let rawValue: String    // non-empty, no whitespace, validated on construction
}

struct ProviderCapabilities: OptionSet, Sendable, Codable {
    static let automaticUsage
    static let automaticPeriod
    static let multipleQuotas
    static let historicalUsage
    static let backgroundRefresh
    static let localAuthentication
}

struct ProviderDescriptor: Sendable, Codable {
    let id: ProviderID
    let displayName: String
    let description: String
    let capabilities: ProviderCapabilities
    let protocolRange: ProtocolRange
}

struct ProtocolRange: Sendable, Codable {
    let minimum: Version      // semantic
    let maximumExclusive: Version
    func contains(_ version: Version) -> Bool
}

enum ProviderErrorCode: String, Sendable, Codable {
    case authRequired, authExpired, providerUnavailable, rateLimited,
         usageUnavailable, invalidResponse, unsupportedQuota, pluginError, unknown
}
```

The nine cases are exactly §45. Their raw values cross the process boundary and
are therefore frozen for the lifetime of protocol version 1.

```swift
struct CatalogEntry: Sendable, Codable {
    let id: ProviderID
    let version: Version
    let minimumAppVersion: Version
    let protocolRange: ProtocolRange
    let contentHash: String          // SHA-256, verified before extraction
    let isUnofficial: Bool           // surfaced as a visible notice
    let capabilities: ProviderCapabilities
}
```

The catalog is the only description of a provider that ships as a file. There is
no per-plugin manifest: a provider's executable is named by the convention
`quota-provider-<id>` (`PluginLayout.executableName`), the host builds everything
else it needs to launch from the catalog and the installed layout, and the
installer refuses an archive that does not contain the executable that
convention resolves to. A provider that declared its own name and version in an
artifact would be a second source of truth for facts the host already holds, and
one nothing in the type system would keep in step with the first.

### 3.8 Contract — the wire protocol

Newline-delimited JSON over the plugin's standard input and standard output.
Standard error is for logs and is never parsed as protocol.

```
host  → {"id":1,"method":"describe","params":{}}
plugin← {"id":1,"result":{"id":"cursor","displayName":"Cursor","description":"…",
                           "capabilities":["automaticUsage","automaticPeriod",
                                           "multipleQuotas"],
                           "protocolRange":{"minimum":"1.0.0",
                                            "maximumExclusive":"2.0.0"}}}

host  → {"id":2,"method":"fetchUsage",
         "value":{"kind":"fetchUsage","value":{"localDate":"2026-09-25"}}}
plugin← {"id":2,"result":{"kind":"usage","value":{
             "quotas":[
              {"externalID":"models","displayName":"Cursor Models",
               "bucketID":"cursor.models","bucketDisplayName":"Cursor Models",
               "usagePercentage":63.3,
               "periodStart":"2026-09-01","periodEnd":"2026-10-01",
               "updatedAt":"2026-09-25T10:00:00Z"},
              {"externalID":"other","displayName":"Other Models",
               "bucketID":"cursor.other","bucketDisplayName":"Other Models",
               "usagePercentage":12.4,
               "periodStart":"2026-09-25","periodEnd":"2026-09-28",
               "updatedAt":"2026-09-25T10:00:00Z"}],
             "supportsHistorical":false}}}
```

A result is a **list of limits, each with its own window**, not a reading with
one window and several pools under it. The two shapes cannot both be true, and
which one a plugin uses decides whether one host can pace a five-hour limit and
a weekly one at the same time.

plugin← {"id":2,"error":{"code":"authRequired","message":"Sign in to Cursor again"}}

````

`PluginRequest` and `PluginResponse` are `Codable` with an identifier used for
correlation. Unknown fields are ignored, so a newer plugin can add fields without
breaking an older host. Methods are `describe`, `connect`, `disconnect`, and
`fetchUsage`.

The error **message** is provider-authored display text. The core never
interprets it, never matches on it, and never branches on it. Only the code is
part of the contract.

`PluginKit` also ships `PluginSide`, the child half of the protocol, so that
a plugin never reimplements framing, correlation, or decoding. A plugin author
writes one function and gets the rest.

### 3.9 Platform — persisted records

One JSON file per family, under `~/Library/Application Support/Quota/`.

| File               | Contents           | Key                               | Written by                           |
| ------------------ | ------------------ | --------------------------------- | ------------------------------------ |
| `quotas.json`      | `[QuotaRecord]`    | `id`                              | `quotaRepository`                    |
| `snapshots.json`   | `[SnapshotRecord]` | `quotaID + bucketID + accountKey` | `snapshotRepository`                 |
| `timelines.json`   | `[TimelineRecord]` | `quotaID + bucketID`              | `timelineRepository`                 |
| `providers.json`   | `[ProviderRecord]` | `id`                              | `providerRepository`                 |
| `preferences.json` | `Preferences`      | —                                 | `preferencesRepository`              |
| `catalog.json`     | `[CatalogEntry]`   | `id`                              | shipped in the app bundle, read only |

Every record carries the schema version it was written at, and every file is
read through one migrator that knows how to move it forward before anything else
looks at it. Version 2 exists because the period moved onto `UsageBucket`: a
version 1 snapshot carried one `periodStart`/`periodEnd` pair for the whole
reading and is rewritten with that window on every bucket it had. That is what it
recorded — one provider, one window — so nothing it claims is falsified by the
new shape; the file it was read from, not a guess about its buckets, is what
chooses whether the copy happens.

```swift
struct QuotaRecord: Sendable, Codable {
    var schemaVersion: Int
    var quota: Quota
}

struct SnapshotRecord: Sendable, Codable {
    var schemaVersion: Int
    var quotaID: UUID
    var bucketID: String
    var accountKey: String?     // nil when the provider is account-agnostic
    var snapshot: UsageSnapshot
}

struct TimelineRecord: Sendable, Codable {
    var schemaVersion: Int
    var quotaID: UUID
    var bucketID: String
    var timeline: UsageTimeline
}

enum ProviderState: String, Sendable, Codable {
    case notInstalled, installing, installed, connected, synchronizing,
         installationFailed, authRequired, authExpired,
         updateAvailable, updating, updateFailed,
         disabled, incompatible, missing
}

struct ProviderRecord: Sendable, Codable {
    var schemaVersion: Int
    var id: ProviderID
    var version: Version
    var relativePath: String
    var state: ProviderState
    var installedAt: Date
    var contentHash: String
    var lastError: ProviderErrorCode?
}

struct ConnectionStatus: Sendable, Codable {
    var providerID: ProviderID
    var accountLabel: String?
    var lastSuccessfulSync: Date?
    var lastError: ProviderErrorCode?
    var nextRefreshAt: Date?
}

struct Preferences: Sendable, Codable {
    var menuBarFormat: MenuBarFormat    // percentage, dot, icon
    var refreshInterval: TimeInterval
    var staleAfter: TimeInterval
    var disabledProviders: Set<ProviderID>   // the per-provider kill switch
}
````

`catalog.json` entries, which are what the interface renders:

```swift
struct CatalogEntry: Sendable, Codable {
    var id: ProviderID
    var displayName: String
    var summary: String
    var version: Version
    var minimumAppVersion: Version
    var protocolRange: ProtocolRange
    var source: PluginSource          // bundled, local file, or remote URL
    var contentHash: String
    var isUnofficial: Bool
}
```

No capabilities here, on purpose. What a provider can do is a fact about the
provider, so it is the provider that states it, in the descriptor it answers
`describe` with (§3.8); a second copy in the catalog would be a claim about
something nobody had asked yet, in a file nothing reads. A catalog written by an
older build still loads: the extra key is ignored rather than refused.

### 3.10 Platform — secrets

Credentials live in the macOS Keychain and nowhere else.

```
service: com.quota.app
account: "<providerID>.<keyName>"
```

A provider that needs no stored secret, because it reads one the provider's own
application already manages, stores nothing. A provider that does store one uses
this account naming and nothing else. Secrets are never written to a
`QuotaStore` file, never logged, and never included in a diagnostic dump.

### 3.11 App — the observable surface

```swift
@Observable final class AppModel {
    private(set) var summaries: [QuotaSummary]
    private(set) var catalog: [CatalogEntry]
    private(set) var connections: [ProviderID: ConnectionStatus]
    // plus commands, which mutate through Platform and never from a view
}

enum AppEnvironment {
    static func live() -> AppEnvironment     // the composition root
    static func preview() -> AppEnvironment  // mock provider, fixed clock
}
```

The interface reads `summaries` and issues commands. It never formats a
percentage, never computes a date, and never branches on a provider identity.

---

## 4. The engine

```swift
enum AllocationEngine {
    static func plan(
        remaining: Double,
        policy: AllocationPolicy,
        period: QuotaPeriod,
        today: LocalDate,
        calendar: Calendar
    ) -> AllocationPlan
}
```

Every input is explicit. The engine never calls `Date()`, never reads a time zone
from the system, and never touches a locale. Same inputs produce identical output,
which is what makes §50's test requirements satisfiable at all.

**Eligible days** are computed by calendar iteration, never by adding a fixed
number of seconds:

```swift
var day = today
while day <= period.end(calendar: calendar) {
    eligible.append(day)
    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
    day = LocalDate(date: next, calendar: calendar)
}
```

**Rounding** uses the largest-remainder method, so the invariant
`Σ allocations == remaining` holds within epsilon for every policy. Naive
independent rounding breaks it, and a user whose daily numbers do not add up to
their remaining quota has been told the product is wrong.

**Determinism contract**, enforced by tests: no ambient clock, no system time
zone, no locale, no unordered iteration in a value that reaches the interface.
A `Calendar` and a `LocalDate` are always parameters.

---

## 5. Invariants

These are the rules whose violation is a defect. Each has a test.

1. `Σ allocation.percentage == plan.totalRemaining`, within `sumEpsilon`.
2. Allocations are ascending by date and contain no date outside
   `[today, period.end]`.
3. A plan with zero eligible days reports `noEligibleDays(retained:)`; the
   undelivered amount is never discarded silently.
4. `Quota` contains no usage figure, ever.
5. A failed refresh never destroys the last successful snapshot.
6. A reading is never served past the `period.end` of the pool its quota watches,
   and never served against another pool's window when that pool is missing from
   the reading.
7. `TodayUsage.unknown` is never rendered as `0`.
8. Pacing never mutates an `AllocationPolicy`.
9. No credential or token appears in any `QuotaStore` payload, any log line, or
   any diagnostic dump.
10. No provider name string literal appears anywhere in `Sources/`.
11. A plugin that hangs, crashes, or emits garbage cannot prevent the core from
    responding.
12. Two quotas on the same provider and different buckets never share state, and
    two quotas on the same provider and the same bucket cannot both exist. A quota
    that names no bucket reads the primary, so it conflicts with every quota on
    its provider.
13. A reading filed against a quota whose bucket the provider no longer reports
    adds no timeline point and changes no period: a point for a pool that is not
    in the reading would be a zero, and a zero reads as "nothing spent".
14. A quota is corrected only by the window of the bucket it watches, so two
    quotas on one provider cannot reset each other's timeline.
15. A provider is never installed at first launch; installing one never creates a
    quota.
16. Date arithmetic never adds a fixed number of seconds to advance a day.
17. The quota the menu bar indicator speaks for is the user's own choice, is
    stored, and a choice naming a quota that no longer exists leaves the indicator
    showing some quota rather than nothing.

---

## 6. Layer and naming discipline

Rules 10, 11, 15, 16 and the layer graph are part of the product contract. The
SwiftPM target graph in `Package.swift` is the physical expression of the layer
graph: `Core` and `PluginKit` have no package dependencies;
`Platform` depends on both; `App` depends on all three; each provider
under `Plugins/` is its own package that depends only on `PluginKit`.
Provider name literals stay out of `Sources/`. Numeric policy lives in
`*Constants.swift` files (see §7). Review and the Definition of Done checklist
catch regressions; there is no separate mechanical guard script.

## 7. Constants

Numeric policy lives in one place per layer, in a `*Constants.swift` file, with
unit-bearing names.

```swift
// Sources/Core/Constants/AllocationConstants.swift
enum AllocationConstants {
    static let percentageScale: Double = 100.0
    static let defaultWeekdayWeight: Int = 1
    static let pacingTolerance: Double = 0.05
    static let upcomingDayWindow: Int = 7
    static let sumEpsilon: Double = 0.000_001
}

// Sources/Platform/Constants/RefreshConstants.swift
enum RefreshConstants {
    static let minimumInterval: TimeInterval = 60
    static let defaultInterval: TimeInterval = 300
    static let jitterFraction: Double = 0.15
    static let maximumBackoff: TimeInterval = 600
    static let freshnessWarningAge: TimeInterval = 900
    static let staleAge: TimeInterval = 3600
    static let pluginHandshakeTimeout: TimeInterval = 10
    static let pluginCallTimeout: TimeInterval = 20
}
```

## 8. The plugin lifecycle

```
notInstalled → installing → installed → connected → synchronizing
                   ↓                                    ↓
          installationFailed                    authRequired, authExpired
                                                        ↓
                                                  updateAvailable → updating → updated
                                                        ↓              ↓
                                                  disabled      updateFailed

Plus: incompatible, missing   (independent of the flow, not stages within it)
```

This is §7 with the two terminal states added that §11 and §12 require. The
interface shows the state and the action it permits. Installing a provider never
creates a quota; the user installs, then connects, then creates a quota.

## 9. Synchronization

```
plugin process
    ↓ fetchUsage
UsageSnapshot
    ↓ record into timeline        (enables "used today")
    ↓ store as last good snapshot (survives failure)
    ↓ recompute AllocationPlan    (no user action, ever)
QuotaSummary
    ↓
interface
```

Failure at any step keeps the last good snapshot, records the error, and reports
freshness. Nothing is ever discarded and nothing is ever invented.

## 10. Security posture

- **Not sandboxed.** Quota reads another application's SQLite store and requires
  unrestricted outbound network. The entitlement set is minimal, and the
  justification is recorded in the readme.
- **Keychain for everything secret.** Service `com.quota.app`. Never a
  preferences file, never a log line, never a diagnostic dump.
- **Plugins are verified before execution.** Content hash, then static code
  signature, then the presence of the executable the naming convention resolves
  to, then activation. A failed check writes nothing.
- **Plugin execution is isolated.** A plugin is a child process with a sanitised
  environment, a bounded call timeout, and termination on hang. It cannot take the
  application down with it.
- **Network egress belongs to the provider.** Quota itself has no backend, no
  account, and no storage of the user's usage (§54).

## 11. Traceability

The full Definition of Done trace, mapping all thirty-nine items of
`spec/0001-definition.md` §57 to the milestone and task that closes each, is
Appendix B of `spec/0003-milestones.md`. It is kept with the checklist rather than
here, because it changes as the checklist is executed and this document changes
only when the architecture does.
