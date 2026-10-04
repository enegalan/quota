# Quota — Product & Technical Specification

## 1. Product Overview

Quota is a native macOS application that automatically monitors quota usage and plans the remaining quota across the remaining days of a billing or usage period.

The core question Quota answers is:

> **“How much of my remaining quota can I use on each day until the end of the period?”**

Quota is primarily a **quota pacing and planning application**, not a usage dashboard.

The user should not normally have to manually enter daily consumption. When a supported provider plugin is installed and connected, Quota retrieves actual usage automatically and continuously recalculates the allocation plan.

---

# 2. Core Concept

Quota is based on three separate concepts:

```text
Actual Usage
     ↓
Allocation Policy
     ↓
Allocation Plan
```

### Actual Usage

The amount of quota already consumed.

Actual usage is retrieved automatically from the configured provider plugin.

### Allocation Policy

The user's preference for how remaining quota should be distributed.

Examples:

* Evenly across every remaining day
* Weekdays only
* Different weights for different weekdays
* Custom daily allocations

### Allocation Plan

The resulting calculated amount of quota available for each day.

The plan is generated from:

```text
Current Usage
+ Quota Period
+ Remaining Days
+ Allocation Policy
↓
Allocation Plan
```

Actual usage and planned allocation must always remain separate concepts.

---

# 3. Product Philosophy

Quota is a **planning and pacing engine**, not simply a usage tracker.

A usage dashboard answers:

> “How much have I used?”

Quota answers:

> “Given what I have already used and how much time remains, how much can I use each day?”

If actual usage changes, the future plan automatically adapts.

The user should not have to manually recalculate anything.

---

# 4. Provider Plugin Architecture

Provider integrations are implemented as **optional plugins**.

Quota itself contains the generic quota engine and application UI, while provider-specific functionality is installed only when the user needs it.

Provider plugins must **not be installed or activated by default**.

A user who only uses Cursor should not need to install or carry provider integrations for Claude, Gemini, OpenAI, or other services.

---

# 5. Provider Plugin Responsibilities

A provider plugin is responsible for everything provider-specific.

This includes:

* Provider authentication
* Provider API communication
* Provider-specific endpoints
* Provider-specific local integrations
* Parsing provider responses
* Usage normalization
* Period detection
* Provider-specific quota rules
* Provider-specific errors
* Authentication expiration
* Provider rate limits
* Provider-specific refresh mechanisms

The plugin converts provider-specific information into Quota's generic representation.

The Quota Core must never need to know how a particular provider works.

---

# 6. Provider Plugin Boundary

The architectural boundary is:

```text
Provider Plugin
       ↓
UsageSnapshot
       ↓
Quota Core
       ↓
Allocation Plan
       ↓
UI
```

The Quota Core must not contain provider-specific logic.

It must not know about:

* Cursor
* Claude
* Claude Code
* OpenAI
* ChatGPT
* Gemini
* Tokens
* Dollars
* Requests
* Models
* Provider-specific APIs
* Provider-specific authentication

---

# 7. Provider Plugin Lifecycle

A provider can exist in several states:

```text
Not Installed
     ↓
Installing
     ↓
Installed
     ↓
Connected
     ↓
Synchronizing
```

It may also enter:

```text
Installation Failed
Authentication Required
Authentication Expired
Update Available
Disabled
```

The UI must communicate these states clearly.

---

# 8. Provider Catalog

Quota must expose a provider catalog from within the application.

The catalog represents providers that can be installed.

Example:

```text
Available Providers

Cursor
Claude Code
ChatGPT
Gemini
...
```

The catalog must distinguish between:

```text
Available
Installed
Connected
```

Installing a provider must not automatically create a quota.

The user installs the provider first and then connects/configures it when creating a quota.

---

# 9. Provider Installation

Provider plugins must be installable directly from the Quota UI.

Example:

```text
Provider

Cursor

Track your Cursor usage automatically.

[ Install ]
```

After installation:

```text
Cursor

Installed · Not Connected

[ Connect ]
```

The user must not need to manually download plugin files or configure the provider through Terminal for normal supported workflows.

---

# 10. Provider Uninstallation

The user must be able to uninstall a provider plugin from Quota.

Uninstalling a provider must clearly explain what happens to quotas currently using that provider.

Possible behavior:

```text
Cursor is used by 2 quotas.

Uninstalling this provider will stop automatic
usage synchronization for these quotas.

[ Cancel ] [ Uninstall ]
```

Existing quota data should not be silently deleted.

Cached usage information may remain available, but the quota must be marked as unable to synchronize.

---

# 11. Provider Updates

Provider plugins should be independently updateable where technically possible.

Quota should support:

```text
Installed
Update Available
Updating
Updated
Update Failed
```

A provider update must not require updating the entire Quota application unless the plugin architecture technically requires it.

---

# 12. Provider Catalog Distribution

The provider catalog must be separate from the Quota Core.

The catalog should contain metadata such as:

```text
Provider ID
Display Name
Description
Version
Compatibility
Installation Information
Capabilities
```

The architecture should allow new providers to become available without requiring changes to the allocation engine.

The exact distribution mechanism for plugins must be selected during technical implementation.

The MVP must establish a mechanism that supports:

* Installing providers from the UI
* Removing providers
* Provider versioning
* Provider compatibility checks
* Provider updates
* Safe failure handling

---

# 13. Provider Discovery Before Implementation

Before implementing a provider plugin, Quota must determine how its usage information can be retrieved reliably.

For every provider, investigate:

1. Official usage APIs.
2. Official authentication mechanisms.
3. Official desktop applications.
4. Existing provider CLIs.
5. Local usage information.
6. Authenticated web endpoints where technically appropriate.
7. Available quota types.
8. Multiple simultaneous limits.
9. Exact vs approximate usage.
10. Period start/end detection.
11. Refresh limitations.
12. Rate limits.
13. Authentication expiration.
14. Offline behavior.
15. Stability of the integration mechanism.
16. Whether the mechanism is appropriate for third-party software.

A provider must not be implemented based solely on assumptions about its internal behavior.

---

# 14. Provider Integration Strategy

Different providers may require completely different mechanisms.

Possible implementations include:

### Official API

```text
Quota
  ↓
Provider API
  ↓
UsageSnapshot
```

### Local CLI

```text
Quota
  ↓
Provider CLI
  ↓
UsageSnapshot
```

### Local Application

```text
Quota
  ↓
Provider Application Integration
  ↓
UsageSnapshot
```

### Authenticated Provider Endpoint

```text
Quota
  ↓
Authenticated Endpoint
  ↓
UsageSnapshot
```

### Manual Fallback

```text
User
  ↓
Manual Usage
  ↓
UsageSnapshot
```

Manual input is only a fallback/testing mechanism and is not the primary product experience.

---

# 15. Usage Provider Protocol

Every provider plugin must expose a generic provider interface to the Quota Core.

Conceptually:

```swift
protocol QuotaUsageProvider {
    var name: String { get }

    func fetchUsage() async throws -> UsageSnapshot
}
```

The exact protocol may evolve during implementation.

The important requirement is that provider-specific details stop at the plugin boundary.

---

# 16. Usage Snapshot

The normalized provider result should contain the information required by the core.

Conceptually:

```swift
struct UsageSnapshot {
    let updatedAt: Date
    let buckets: [UsageBucket]
}

struct UsageBucket {
    let id: String
    let displayName: String
    let usagePercentage: Double
    let period: QuotaPeriod
}
```

The period belongs to a bucket, not to the snapshot. A provider may meter
several limits that do not reset together — a five-hour allowance and a weekly
one, say — and one window for the whole reading can only describe a provider
whose limits share a clock.

Each limit a provider reports carries its own window, and each limit a quota
watches is read from the period of the bucket it names. A quota that names no
bucket reads the provider's primary, as it did before; a quota whose bucket the
provider has stopped reporting has no window to read and is reported as waiting
for that limit rather than being given another limit's window.

For example:

```text
Provider:
260,000 units used
1,000,000 unit quota

Plugin:
usagePercentage = 26%

Core:
26% used
74% remaining
```

The core does not need to know what the original units were.

---

# 17. Provider Capabilities

Different providers may expose different information.

A provider may support:

* Automatic usage retrieval
* Automatic period detection
* Multiple quotas
* Historical usage
* Background refresh
* OAuth
* Local authentication

Another provider may expose only a subset.

The plugin architecture must allow capabilities to be represented without introducing provider-specific logic into the core.

If a provider cannot automatically determine information such as the period end, the UI may request that information from the user.

---

# 18. MVP Provider Requirement

The MVP must include:

* The generic provider/plugin architecture.
* Provider catalog.
* UI provider installation.
* UI provider removal.
* Mock provider.
* **At least one real provider plugin.**

The MVP does **not** require implementing every AI provider.

The first real provider should be selected after investigating which provider offers the most reliable way to retrieve usage automatically.

Additional providers are independent extensions.

---

# 19. Recommended Development Order

Implementation should proceed in this order:

```text
1. Quota Core
2. Allocation Engine
3. Mock Provider
4. Provider Plugin Boundary
5. Provider Manager
6. Provider Catalog
7. Plugin Installation UI
8. First Real Provider Research
9. First Real Provider Plugin
10. Provider Connection Flow
11. macOS UI
12. Calendar
13. Persistence
14. Reliability / Error Handling
```

This allows the core to be developed and tested without depending on an external provider.

---

# 20. Synchronization Lifecycle

The normal lifecycle is:

```text
Provider Plugin
      ↓
Fetch Usage
      ↓
Normalize
      ↓
UsageSnapshot
      ↓
Update Quota
      ↓
Recalculate Allocation Plan
      ↓
Update UI
```

When actual usage changes:

```text
New UsageSnapshot
      ↓
Remaining Quota Changes
      ↓
Allocation Plan Recalculated
      ↓
Future Allocations Updated
```

The user does not need to manually trigger recalculation.

---

# 21. Refresh Strategy

Quota should support automatic provider refresh.

Depending on the provider, this may use:

* Periodic polling
* macOS background refresh
* Refresh when Quota launches
* Refresh when the menu bar popover opens
* Manual refresh
* Refresh after connectivity returns

The refresh frequency must respect:

* Provider rate limits
* API restrictions
* Battery usage
* Network usage

---

# 22. Synchronization State

Quota must expose the freshness of usage data.

Examples:

```text
Updated 2 minutes ago
```

```text
Updated 3 hours ago
```

If synchronization fails:

```text
Unable to update usage.
Showing data from 3 hours ago.
```

The latest successful snapshot should be retained locally.

---

# 23. Offline Behavior

Quota should continue working with the latest cached snapshot when the provider is unavailable.

The UI must clearly indicate that the information is stale.

When connectivity returns, Quota should refresh the provider and recalculate the plan.

---

# 24. Quota Model

A quota should conceptually contain:

```text
id
name
providerID
periodStart
periodEnd
currentUsagePercentage
usageUpdatedAt
allocationPolicy
createdAt
updatedAt
```

The quota references the provider plugin responsible for synchronizing its usage.

---

# 25. Remaining Quota

Remaining quota is:

```text
remainingPercentage = 100 - currentUsagePercentage
```

Example:

```text
Usage: 26%
Remaining: 74%
```

Invalid provider values must be rejected or handled explicitly.

---

# 26. Remaining Days

The allocation engine determines the remaining calendar days between:

```text
Current Date
Period End
```

The current day and final day are included while the quota period is active.

The implementation must correctly handle:

* Month boundaries
* Year boundaries
* Leap years
* Daylight saving time
* Local calendar rules
* Future periods
* Expired periods

Date calculations must use calendar dates rather than assuming every day is exactly 24 hours.

---

# 27. Allocation Plan

An allocation plan contains the planned quota percentage for each eligible date.

Example:

```text
September 16 → 4%
September 17 → 4%
September 18 → 4%
...
September 30 → 4%
```

The sum of the allocations should correspond to the quota being distributed according to the selected policy.

---

# 28. Allocation Policies

Quota must support:

## Even Distribution

Remaining quota is distributed evenly across all eligible remaining days.

Example:

```text
Remaining quota: 60%
Remaining days: 15

Daily allocation:
4%
```

## Weekly Pattern

The user can define relative weights for each weekday.

Example:

```text
Monday     1
Tuesday    1
Wednesday  1
Thursday   1
Friday     1
Saturday   0
Sunday     0
```

Zero-weight days receive no allocation.

Weights are relative preferences, not percentages.

Example:

```text
Monday     2
Tuesday    1
Wednesday  1
Thursday   1
Friday     2
```

Monday and Friday receive twice the allocation weight of the other eligible weekdays.

## Custom Daily Allocation

The user can define explicit allocations for specific dates.

Example:

```text
Sep 20 → 8%
Sep 21 → 2%
Sep 22 → 0%
Sep 23 → 10%
```

The daily shares are entered on a calendar of the period, one day at a time, with
the total of the policy always visible beside the days that make it up. The
calendar is the same one the plan is shown on, so a month looks the same wherever
it appears.

```text
Assigned                                              100.00%
Every percent of the allowance has a day.
```

The editor must not let a policy ask for more than the whole allowance: a
custom policy is the user's own share of their quota, and a total above 100% could
only be satisfied by scaling every day back down. A day is therefore held at what
is left of the allowance after the other days:

```text
Assigned                                              100.00%
30.00% is all this day can take.
```

A period of 30 days does not divide into a hundred whole percents, so the policy
must be fillable in one press, and the filled figures must add up to exactly 100%
as they are displayed:

```text
29 days → 3.33%
1 day   → 3.43%
        ───────
         100.00%
```

A policy stored before this ceiling existed may hold more than 100%, and must
remain editable rather than stuck: lowering a day is always allowed, and the way
out of an overfilled policy is a day at a time or the one-press fill.

---

# 29. Custom Allocation Validation

Custom allocations must support:

### Exact

```text
Planned: 40%
Remaining: 40%
```

### Underallocated

```text
Planned: 35%
Remaining: 40%

Unallocated: 5%
```

### Overallocated

```text
Planned: 45%
Remaining: 40%

Overallocated: 5%
```

These states must be clearly communicated.

---

# 30. No Eligible Days

If a policy produces no eligible days while quota remains:

```text
Remaining quota: 20%
Eligible days: 0
```

Quota must not silently discard the remaining quota.

The UI must explicitly communicate the situation.

---

# 31. Dynamic Recalculation

Dynamic recalculation is a core feature.

Example:

```text
Current usage: 40%
Remaining: 60%
Days: 15
```

The plan is generated.

The provider later reports:

```text
Current usage: 45%
Remaining: 55%
```

Quota automatically recalculates the remaining plan.

The user does not enter the new usage manually.

---

# 32. Actual Usage vs Planned Allocation

These concepts must remain separate in the domain model and UI.

Example:

```text
Today's planned allocation: 8%
Today's actual usage:       5%
Remaining today:            3%
```

Actual usage comes from the provider.

Planned allocation comes from the allocation engine.

---

# 33. Intraday Recalculation

If actual usage changes during the day, Quota must recalculate the remaining allocation without double-counting consumption.

The calculation must distinguish between:

```text
Actual usage already consumed
```

and:

```text
Allocation still available
```

The exact semantics of today's allocation must be deterministic and covered by unit tests.

---

# 34. Calendar View

Quota must provide a calendar showing the allocation plan.

Each day may display:

* Planned allocation
* Actual usage
* Remaining planned allowance

The calendar must distinguish:

* Past
* Today
* Future
* Zero-allocation days
* Days outside the active period

Example:

```text
Sep 21   5%
Sep 22   5%
Sep 23   5%  ← Today
Sep 24   5%
Sep 25   5%
```

The calendar must follow the user's first day of the week: the first of a month
appears under its own weekday, and the cells before it are empty rather than
filled with days of the month before.

The calendar must explain its own marks. A day distinguished only by a shade of
grey asks the user to learn a colour code, so the calendar shows what each mark
stands for:

```text
■ Today   ◻ Selected   □ Nothing planned   ▨ Outside period
```

A month the user cannot page past must not offer the arrows that would page past
it, and the calendar must say which months it may be moved through.

---

# 35. Calendar Interaction

Selecting a date should display relevant information.

Example:

```text
September 23

Planned:   5%
Actual:    3%
Remaining: 2%
```

Future dates display planned allocations.

Past dates primarily display historical information.

The selected day's figures sit directly under the calendar, in the order they are
asked for, so the calendar stays the thing being read.

Month navigation is a keyboard-reachable control, and the selected day is brought
into view whichever month is showing: a day selected from a list below the
calendar is not on a page the user cannot see.

---

# 36. Today's Allowance

The primary user-facing value is today's available allocation.

Example:

```text
TODAY

Planned       6%
Used          2%
Remaining     4%
```

The UI must make clear whether each value represents:

* Planned usage
* Actual usage
* Remaining available usage

---

# 37. Future Allocation

Quota must allow users to see how much they can use on future days.

This is shown by the calendar, on the day each share belongs to, rather than by a
list of the coming days. A list would be a second rendering of figures the
calendar already carries, in a fixed order, and its length would grow with the
period: a yearly quota would list three hundred and sixty rows in front of the
calendar that answers the same question. The calendar is paged a month at a time
and shows every day of the period, so nothing is lost by not repeating it.

Example — a month's grid, each day carrying its own share:

```text
       M     T     W     T     F     S     S
 1   3.3%  3.3%  3.3%  3.3%  3.3%  3.3%  3.3%
 2   3.3%  3.3%  3.3%  3.3%  3.3%  0%    0%
 3   3.3%  3.3%  3.3%  3.3%  3.3%  0%    0%
```

Today's share is also in the summary figures, and the selected day's in full
beneath the grid.

Future allocation is a core product feature.

---

# 38. Pacing Status

Quota should calculate a descriptive pacing state.

Possible states:

```text
On Pace
Ahead of Pace
Behind Pace
Quota Exhausted
Period Expired
```

These states describe the relationship between actual usage and the current plan.

Quota should not silently modify the user's allocation policy because of pacing status.

---

# 39. Menu Bar

Quota operates primarily as a menu bar application. The menu bar is the primary
entry; a management window handles editing (providers, quotas, calendars,
custom policies).

The menu bar indicator should expose today's relevant allowance, as what has
been used of it out of the day's planned allocation. The two figures are shown
together because a percentage of a day and a percentage of a period read the
same and are not the same claim, and they are written apart rather than as one
fraction: at menu bar size `6%/8%` reads as a single number, which is the one
reading both figures are there to prevent.

Examples:

```text
Quota · 2% / 8%
```

Where today's spending cannot be established, the used figure is a dash
and the plan is still shown:

```text
Quota · — / 8%
```

The indicator shows one quota. Where a user has several, they choose which one
the indicator speaks for, and the choice is remembered across launches. Until
they choose, the first quota stands in. A quota that has been deleted does not
leave the indicator blank; another quota stands in until one is chosen again.

---

# 40. Main Popover

The main popover should show:

* Quota name
* Provider
* Usage percentage
* Remaining percentage
* Today's planned allocation
* Today's actual usage
* Today's remaining allowance
* Days remaining
* Pacing status
* Last synchronization time
* Calendar access
* Settings access

Example:

```text
Cursor

26% used
74% remaining

TODAY
Planned       6%
Used          2%
Remaining     4%

18 days remaining

On Pace

Updated 2 minutes ago
```

The popover shows every quota, not only the one the menu bar indicator speaks
for. The chosen quota is shown in full and marked, and the others are listed
beside it; selecting one of them makes it the one the indicator speaks for. The
question the indicator's single number raises — *which of my quotas is that?* —
cannot be answered from a panel that hides the rest.

Example:

```text
Cursor  ●

26% used
74% remaining

TODAY
Planned       6%
Used          2%
Remaining     4%

18 days remaining

On Pace

Updated 2 minutes ago
─────────────────────────
OTHER QUOTAS
Claude                        71%
OpenAI                        12%
```

---

# 40a. Management Window

The management window is where a quota is read and edited, and it is a window in
its own right rather than a panel in the menu bar: a month of days cannot be
edited usefully in a status-item panel.

The window is a list of quotas beside the selected quota's detail.

```text
┌──────────────────┬──────────────────────────────────────────┐
│ Cursor      26%  │ ALLOWANCE                                │
│ Claude      71%  │ 26% used              74% remaining       │
│ OpenAI      12%  │ ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│                  ├──────────────────────────────────────────┤
│                  │ TODAY                                    │
│                  │ Planned     6%      Used      2%          │
│                  │ Remaining   4%                            │
│                  │                                          │
│                  │ 18 days remaining          On Pace        │
│                  ├──────────────────────────────────────────┤
│                  │ CALENDAR                                 │
│                  │ September 2026                ‹     ›    │
│                  │  M    T    W    T    F    S    S          │
│                  │     1    2    3    4    5    6    7       │
│                  │   3.3  3.3  3.3  3.3  3.3  3.3  3.3       │
│                  │     8    9   10   11   12   13   14       │
│                  │   3.3  3.3  3.3  3.3  3.3  3.3  3.3       │
│                  ├──────────────────────────────────────────┤
│                  │ POLICY                                   │
│                  │ Even distribution                        │
└──────────────────┴──────────────────────────────────────────┘
```

Each quota in the list states how much of its allowance is used, so a quota does
not have to be opened to be known. The detail is grouped into titled sections, and
a section's figures are the same figures the popover shows for the same instant.

A day of the plan is not also listed beside the calendar: the calendar carries
each day's share on the day itself, and a list of the same figures in a column
would be a second rendering of it that grows with the period. The one thing about
the plan the calendar cannot show is whether the plan adds up at all, so that —
and only that — is stated above the grid.

The window must be usable from the keyboard: adding a quota and refreshing are
commands, not controls the pointer has to find.

The selected quota is removed by a control in its own section, so a quota is
never deleted by a stray click on the thing the user was reading.

---

# 41. First Launch Experience

On first launch, Quota should not assume which providers the user uses.

The user should be presented with a provider discovery experience.

Example:

```text
Welcome to Quota

Connect a service to automatically
track your quota usage.

[ Browse Providers ]
```

The user then chooses and installs the required provider plugin.

No provider plugin should be installed automatically unless explicitly required by the Quota application itself.

---

# 42. Quota Creation Flow

Creating a quota should follow this general flow:

```text
Add Quota
    ↓
Choose Provider
    ↓
Provider Installed?
   ↙       ↘
 No         Yes
 ↓           ↓
Install    Connect
 ↓           ↓
      Authenticate
            ↓
      Retrieve Usage
            ↓
      Detect Period
            ↓
    Choose Allocation Policy
            ↓
        Create Quota
```

When a provider is not installed, the user should be able to install it directly from this flow.

---

# 43. Provider Management UI

Quota should have a dedicated provider management area.

Example:

```text
Settings
└── Providers

Installed

Cursor
Connected
[ Manage ] [ Uninstall ]

Claude Code
Not Connected
[ Connect ] [ Uninstall ]

Available

Gemini
[ Install ]

ChatGPT
[ Install ]
```

The exact UI is subject to design iteration.

---

# 44. Authentication

Authentication remains provider-specific.

Possible mechanisms include:

* OAuth
* API keys
* Existing local credentials
* CLI authentication
* macOS Keychain
* Provider-specific mechanisms

Secrets must not be stored in plain application preferences.

The macOS Keychain should be preferred where appropriate.

---

# 45. Provider Errors

Provider failures should be translated into generic application states.

Examples:

```text
Authentication Required
Authentication Expired
Provider Unavailable
Rate Limited
Usage Unavailable
Invalid Response
Unsupported Quota
Plugin Error
Unknown Error
```

The application should retain cached data when appropriate.

---

# 46. Multiple Quotas

The architecture must support multiple quotas.

Examples:

```text
Cursor — Monthly quota
Claude Code — Weekly quota
OpenAI — Monthly quota
```

Each quota has its own:

* Provider
* Usage snapshot
* Period
* Allocation policy
* Allocation plan
* Synchronization state

Quotas are independent.

A provider may back one quota per bucket. A second quota on the same provider
and the same bucket is refused: it would read exactly the same numbers as the
first and differ only in how they are divided, so the application would be
showing two panels disagreeing about one set of readings with nothing to tell
the user which is the real one. A provider that meters several pools is
entitled to a quota per pool, and those read genuinely different numbers.

A quota that names no bucket reads the provider's primary, so it stands in the
way of every quota on that provider in either order: the application cannot know
which identifier a provider calls primary without reading it, and the two
records it would otherwise create describe one set of readings.

A provider is closed off in the quota creation flow once every limit it meters
has a quota, and only then: a row cannot know which limits a provider meters
without reading it, so the last of the limits is decided by the picker, which is
where they are in hand. A quota created outside the flow anyway is refused with
a message naming the quota already in the way.

---

# 47. Persistence

Quota should persist locally:

* Quotas
* Installed provider metadata
* Provider configuration
* Allocation policies
* Cached usage snapshots
* Synchronization metadata
* User preferences

Sensitive credentials should use Keychain where appropriate.

---

# 48. Project Architecture

A possible project structure:

```text
Quota/
├── App/
│   ├── App.swift
│   └── AppEnvironment.swift
│
├── Domain/
│   ├── Quota.swift
│   ├── QuotaPeriod.swift
│   ├── UsageSnapshot.swift
│   ├── Allocation.swift
│   ├── AllocationPlan.swift
│   ├── AllocationPolicy.swift
│   ├── AllocationEngine.swift
│   ├── PacingStatus.swift
│   └── PacingCalculator.swift
│
├── Providers/
│   ├── ProviderProtocol.swift
│   ├── ProviderManager.swift
│   ├── ProviderCatalog.swift
│   └── PluginInstaller.swift
│
├── Persistence/
│   ├── Models/
│   └── Repositories/
│
├── Features/
│   ├── Onboarding/
│   ├── MenuBar/
│   ├── Dashboard/
│   ├── Calendar/
│   ├── Providers/
│   ├── QuotaEditor/
│   └── Settings/
│
└── Resources/
```

Provider implementations themselves should be isolated from the core application according to the final plugin distribution architecture.

---

# 49. Plugin Distribution Architecture

The exact technical mechanism for provider plugins must be determined during implementation.

Possible approaches include:

* Dynamically loaded bundles
* Separate provider processes
* Executable-based plugins
* Swift Package-based modules distributed with separate application components
* Another native macOS extension mechanism

The chosen mechanism must support the product requirements:

* Optional installation
* Installation from UI
* Uninstallation
* Versioning
* Updates
* Compatibility checks
* Error isolation
* Secure execution
* Provider-specific dependencies

A provider plugin should not be able to compromise the stability of the Quota Core.

The final implementation should prefer strong process or module isolation where practical.

---

# 50. Testing

The Quota Core must have comprehensive unit tests.

Required tests include:

### Even Distribution

* Equal allocation
* Fractional percentages
* One remaining day

### Weekly Pattern

* Weekdays only
* Zero-weight weekends
* Different weekday weights
* No eligible days

### Dynamic Usage

```text
40% used → allocation calculated
45% used → allocation recalculated
```

### Custom Allocation

* Exact allocation
* Underallocation
* Overallocation
* Zero allocation
* Missing dates

### Calendar

* Month boundaries
* Year boundaries
* Leap years
* Daylight saving transitions

### Periods

* Future period
* Active period
* Expired period

### Synchronization

* Successful refresh
* Failed refresh
* Stale snapshot
* Recovery after failure
* Provider period changes

### Plugin Management

* Installation
* Installation failure
* Uninstallation
* Update
* Update failure
* Compatibility failure
* Missing provider
* Disabled provider

---

# 51. Mock Provider

A mock provider is required for development and automated testing.

Example:

```text
Usage: 26%
Period: September 1 → September 30
```

and:

```text
Usage: 45%
Period: September 1 → September 30
```

The mock provider allows the entire Quota Core and UI to be developed without network access.

---

# 52. Provider Integration Testing

Provider plugins must be tested independently from the core.

Provider tests verify:

```text
Provider Response
      ↓
UsageSnapshot
```

Core tests verify:

```text
UsageSnapshot
      ↓
AllocationPlan
```

Core tests must never depend on a live external provider.

---

# 53. Security

Quota may access authenticated provider accounts.

Requirements:

* Never store credentials in plain text.
* Prefer macOS Keychain.
* Never log access tokens.
* Minimize permissions.
* Minimize stored provider data.
* Keep credentials isolated from the domain layer.
* Validate installed plugin packages before installation.
* Verify plugin compatibility.
* Protect the plugin installation/update process from tampering.

---

# 54. Privacy

Quota should be local-first.

The MVP should not require:

* A Quota account
* A Quota backend
* Quota-owned cloud storage
* Uploading usage data to Quota servers

Provider plugins communicate with their respective providers when retrieving usage.

Quota should store usage information locally.

---

# 55. Design Principles

Quota should be:

* Native
* Lightweight
* Local-first
* Automatic
* Provider-agnostic
* Plugin-based
* Modular
* Transparent
* Deterministic
* Easy to understand
* Low-noise

The interface should emphasize:

> **How much can I use today?**

and:

> **How much can I use on future days?**

---

# 56. End-to-End Example

The user installs Quota.

No AI providers are installed.

The user opens:

```text
Settings → Providers
```

and installs:

```text
Cursor
```

The user connects Cursor.

Cursor's plugin retrieves:

```text
Usage: 40%
Period: September 1 → September 30
```

The plugin converts this into:

```text
UsageSnapshot
    usagePercentage = 40
    periodStart = September 1
    periodEnd = September 30
```

Quota calculates:

```text
Remaining quota: 60%
```

The user selects:

```text
Monday-Friday: 1
Saturday-Sunday: 0
```

Quota generates the allocation plan.

Later, Cursor reports:

```text
Usage: 46%
```

The plugin returns the new snapshot.

Quota automatically calculates:

```text
Remaining quota: 54%
```

and regenerates the future allocation plan.

The user does nothing manually.

---

# 57. MVP Definition of Done

The MVP is complete when:

1. Quota runs as a native macOS menu bar application.
2. The Quota Core is independent of provider implementations.
3. Provider plugins are optional.
4. No AI provider plugin is installed by default.
5. Users can browse available providers from inside Quota.
6. Users can install providers from inside Quota.
7. Users can uninstall providers from inside Quota.
8. Provider installation has clear success/failure states.
9. Provider versions and compatibility are handled.
10. A provider can be connected after installation.
11. The MVP contains a mock provider.
12. The MVP contains at least one real provider plugin.
13. The real provider can retrieve usage automatically.
14. The provider returns a normalized `UsageSnapshot`.
15. The quota period is detected automatically when supported.
16. Current usage updates automatically.
17. Remaining quota is calculated automatically.
18. Remaining calendar days are calculated automatically.
19. An allocation plan is generated automatically.
20. Even distribution is supported.
21. Weekly patterns are supported.
22. Custom daily allocations are supported.
23. Actual usage and planned allocation are clearly separated.
24. The allocation plan recalculates when actual usage changes.
25. Today's allowance is clearly displayed.
26. Future daily allocations are visible.
27. A calendar displays the allocation plan.
28. Pacing status is displayed.
29. Provider synchronization status is displayed.
30. Stale provider data is clearly identified.
31. The latest successful usage snapshot is cached locally.
32. Provider authentication is handled securely.
33. Provider failures do not corrupt the Quota Core.
34. The allocation engine has comprehensive unit tests.
35. Plugin management has automated tests.
36. The real provider plugin has integration tests.
37. Core tests do not require network access.
38. Adding another provider does not require changes to the allocation engine.
39. No manual daily usage entry is required when automatic provider integration is available.

---

# 58. Implementation Priority

The implementation priority is:

```text
P0 — Core
    Quota domain
    UsageSnapshot
    AllocationPolicy
    AllocationEngine
    Pacing
    Persistence

P0 — Plugin System
    Provider protocol
    Provider manager
    Provider catalog
    Plugin installation
    Plugin lifecycle
    Plugin persistence

P0 — First Provider
    Provider research
    Authentication
    Usage retrieval
    Period detection
    Normalization
    Error handling

P0 — Main Product UI
    Onboarding
    Provider installation
    Quota creation
    Menu bar
    Dashboard
    Calendar

P1 — Reliability
    Background refresh
    Offline behavior
    Stale data
    Plugin updates
    Authentication expiration

P2 — Expansion
    Additional providers
    Notifications
    Advanced allocation strategies
    Historical analytics
```

---

# 59. Final Architectural Principle

The fundamental architecture is:

```text
┌──────────────────────────────────────────┐
│                  Quota                   │
│                                          │
│  Core                                    │
│  ├── Quota                               │
│  ├── Allocation Engine                   │
│  ├── Pacing                              │
│  ├── Calendar                            │
│  └── Persistence                         │
│                                          │
│  Plugin Manager                          │
│  ├── Catalog                             │
│  ├── Installer                           │
│  ├── Updates                             │
│  └── Lifecycle                           │
└──────────────────┬───────────────────────┘
                   │
          Optional Plugins
                   │
       ┌───────────┼───────────┐
       ↓           ↓           ↓
    Cursor     Claude Code   Gemini
       │           │           │
       └───────────┼───────────┘
                   ↓
             UsageSnapshot
                   ↓
             Quota Core
                   ↓
            Allocation Plan
                   ↓
                  UI
```

The fundamental rule is:

> **Providers know how to obtain usage. Quota knows how to plan usage. The UI knows how to present the plan.**

Provider integrations are **optional, independently managed extensions**. The user installs only the providers they actually use.

Adding a new AI provider must therefore mean adding a new plugin, not modifying the Quota Core or allocation engine.
