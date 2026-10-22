# Quota — Notifications

> What the application says when the user is not looking at it.
> Companion to `spec/0001-definition.md` §55 (low-noise) and §21 (refresh), and
> to `spec/0002-architecture.md` §10 (the channels available to an unsigned build).

---

## 1. What a notification is for

A menu bar application is looked at a few times a day. A notification is for the
moments when **the answer has changed and the change matters**, so the user does
not have to keep the popover open to find out.

Three sentences, and every candidate has to pass all three:

1. **The user would have had to ask the application.** If the popover already
   says it plainly, a notification is a second copy of something visible.
2. **The user can act on it.** "Your weekly allowance is 85% spent" is a fact
   with nothing to do; "Cursor needs to be signed in again" is a fact that only
   the user can clear.
3. **It is worth interrupting for.** Low-noise is a design principle (§55), and
   an application that talks every hour is an application that gets muted.

The application is not a dashboard and the notification is not a shorter
dashboard. It is a doorbell, not a bulletin board.

---

## 2. Two channels, and why the first one is the real one

There are two ways to reach a user who is not looking at the application, and
they are not equally available.

### 2.1 The in-app channel — always on

The application is already on screen, in the menu bar, all day. It can carry a
condition in the figures it shows and in a line under the popover's card.

```text
Cursor ●

26% used

TODAY
6.00% planned

▓▓▓▓▓░░░░░░░

2.00% Used      4.00% Remaining

18 days remaining
Resets 14 October

Updated 2 minutes ago
```

```text
Cursor needs to be signed in again.        ← the condition, in the popover
```

This channel needs **no permission, no signature, and no daemon**. It works in
every build of the application, including the ad-hoc signed one this project
currently ships (§10 of the architecture spec), and it cannot fail silently
because it is the same code path that draws the figures.

**The in-app channel is the primary one.** Every condition that can notify must
be visible in the application without opening anything, and the notification is
an _addition_ to that, never a replacement for it. A condition that exists only
in a notification is a condition the user loses by dismissing it.

### 2.2 The system channel — optional, and degradable

macOS can deliver a notification to Notification Centre, through
`UNUserNotificationCenter`. It is the right thing for a condition the user must
act on while the application is closed.

It is also **not available in every build**:

- it asks the user for permission, and the user can say no;
- the notification daemon identifies an application by its signature, and this
  project has no Developer ID identity, so registration may be refused;
- it cannot be exercised by a test that has no user session.

So the system channel is **optional and must degrade**:

- the application asks for permission only when the user turns the channel on,
  never at first launch;
- if permission is refused or unavailable, the application says so in its own
  words and **everything still works** — the in-app channel carries the whole
  load, and no other part of the application changes;
- nothing is ever scheduled through the system channel that the in-app channel
  cannot also show.

The consequence for the code: delivery is a **seam**, and the policy that
decides _what_ to say is separate from the thing that delivers it. A build
without the system channel is the same build with a different implementation of
one protocol, not a different build.

---

## 3. What may notify

Four conditions, and no others. Each is stated with what it is, when it fires,
and whether the user has to ask for it.

| Kind                    | Fires when                                                                                                | Default | Channel     |
| ----------------------- | --------------------------------------------------------------------------------------------------------- | ------- | ----------- |
| `limitReached`          | A pool's usage reaches 100%.                                                                              | **on**  | both        |
| `providerNeedsAction`   | The provider reports that it needs authentication, or the credential expired.                             | **on**  | both        |
| `dailyShareNearlySpent` | What is left of today's share falls below a threshold the user chose.                                     | off     | both        |
| `readingIsStale`        | No successful reading for longer than the staleness threshold, so the figure on screen is no longer true. | off     | in-app only |

### 3.1 `limitReached`

The allowance is gone. Every other figure the application shows is now moot, and
the user can only wait for the window to turn over. This is the one condition
that is unambiguous, actionable and rare enough to be worth interrupting for.

The notification names the pool, because a provider may meter several and
"Cursor" alone does not say which one ran out.

```text
Cursor · Cursor Models
The allowance for Cursor Models is used up. It resets on 14 October.
```

### 3.2 `providerNeedsAction`

The provider has said it cannot be read without the user. Nothing else in the
application can fix it, and the figures on screen are the last ones that were
read.

```text
Cursor
Cursor needs to be signed in again. The figures shown are from 3 hours ago.
```

The second sentence is required. Without it, the notification invites the user to
open the application and find numbers that look current and are not.

### 3.3 `dailyShareNearlySpent`

The day's own share is nearly used. This is the product's central number — _how
much can I use today_ — and the user can ask for it to be called.

Off by default. The menu bar already shows the day's plan and what is left of
it, so a user who wants to know does not need to be told; the notification is
for the user who wants to be **stopped** when the day is nearly gone.

The threshold is a percentage of the day's share, not an absolute figure: a day
planned at 4% and a day planned at 12% are different days, and "10% left" means
something different in each. The default when the user turns it on is a tenth
of the day's share.

```text
Cursor
8.4% of today's 12.00% is left.
```

### 3.4 `readingIsStale`

The number on screen has stopped being true. The application's own rule is that
stale data is shown as stale — the popover already says "Updated 3 hours ago" —
so this condition is **in-app only**: it is a line in the popover, not a
notification. A user who has muted notifications still needs to know that the
figure they are reading is old, and the only honest way to tell them is to show
it where the figure is.

---

## 4. What may never notify

These are rules, not preferences. Each of them exists because the failure it
prevents is worse than a missing notification.

1. **Nothing may be notified from a stale reading.** A notification is a claim
   about the present. If the last successful read is older than the staleness
   threshold, the application may say the data is old; it may not say what the
   data is.
2. **A condition that still holds does not notify twice.** The state that has
   been notified is remembered (§8). A user who has already been told their
   allowance is used up does not need to be told again on the next poll.
3. **A failure is not a usage event.** A provider that is unreachable, a rate
   limit, a plugin that died — none of these are notifications. They are states
   the popover shows, and `providerNeedsAction` is the only failure that
   notifies, because it is the only one the user can clear.
4. **A provider the user has switched off does not notify.** The kill switch
   (§10 of the architecture spec) is a statement that the provider is not the
   user's problem today.
5. **Nothing notifies about pacing.** The pacing verdict is not in the interface
   any more (§38 of the definition), and a notification that reintroduces it in
   the one place the user cannot glance at would be a worse version of the thing
   that was removed.
6. **Nothing notifies about a date the interface already shows.** "Your quota
   resets tomorrow" is what the days-remaining line says, every time it is
   looked at.
7. **Nothing notifies that the user cannot act on.** "You have used 62% of your
   monthly allowance" is a fact about a period that has weeks left. It is not
   actionable, and it is not a condition.
8. **Nothing notifies outside the quiet hours** unless it is the kind the user
   has said may interrupt (§7).

---

## 5. The anatomy of a notification

A notification is read away from the application, so it must carry its own
context. Four things, always:

- **the quota it is about**, by name — the menu bar shows one quota and the
  notification may be about another;
- **the figures it is quoting**, as figures;
- **what can be done**, or the fact that nothing can be done until a window
  turns over;
- **when the last good reading was**, whenever the condition is about data that
  may be older than the moment it fires.

The system channel's actions are two: **Refresh**, which re-reads the provider,
and **Open**, which opens the window on the quota. The in-app channel's
equivalent is a click on the popover, which is why the popover has to be able
to show the condition on its own.

---

## 6. Where the decision lives

The layering of §2 of the architecture spec applies unchanged: `Core` computes,
`Platform` delivers, `App` presents.

`Core` imports nothing, so the policy cannot take a `ConnectionStatus` or a
`Preferences` — those live in `Platform`, and a policy that reached for them
would be a policy the core could not be tested without. It takes **core values**
and two small core types of its own, and the composition root maps the
platform's state into them.

```swift
// Core — pure. No clock of its own, no I/O, no framework.
public enum NotificationKind: String, Sendable, Codable, CaseIterable {
    case limitReached
    case providerNeedsAction
    case dailyShareNearlySpent
    case readingIsStale
}

/// What the policy needs to know about a provider, in the policy's own terms.
///
/// Mapped from the platform's `ConnectionStatus` by the caller, because the
/// error vocabulary belongs to the plugin contract and the core may not know
/// the contract. A `need` is a fact about the provider's state; everything the
/// interface says about it is the interface's business.
public struct ProviderCondition: Sendable, Equatable {
    public enum Need: String, Sendable, Equatable {
        case none
        case authenticationRequired
        case authenticationExpired
    }

    public let quotaID: UUID
    public let providerID: String
    public let need: Need
    /// Whether the user has switched this provider off, per §10 of the
    /// architecture spec.
    public let isEnabled: Bool
}

/// The user's choices about being told things.
///
/// A preference rather than a policy, in the sense §19 of the definition gives
/// that word: it says what the user wants, and the quota's own policy says how
/// the quota is paced.
public struct NotificationSettings: Sendable, Equatable {
    public var enabledKinds: Set<NotificationKind>
    /// The share of the day's own allocation left below which the user wants to
    /// be told. A fraction of the day's plan, not an absolute figure, because a
    /// day planned at 4% and a day planned at 12% are different days.
    public var dailyShareThreshold: Double
    /// The hours in the user's own calendar during which nothing interrupts.
    public var quietHours: QuietHours
}

public struct NotificationEvent: Sendable, Equatable {
    public let kind: NotificationKind
    public let quotaID: UUID
    public let title: String
    public let body: String
    /// The condition that produced it, so the same condition can be recognised
    /// and not announced twice.
    public let condition: String
}

public enum NotificationPolicy {
    /// What should be said, given what the application knows now and what it has
    /// already said.
    public static func events(
        summaries: [QuotaSummary],
        conditions: [ProviderCondition],
        settings: NotificationSettings,
        alreadyAnnounced: [String: String],
        now: Date,
        calendar: Calendar
    ) -> [NotificationEvent]
}
```

The policy is a **pure function of values**, including the instant, so every
branch of it — a limit reached, an exhausted day, a provider asking for
attention, a condition that has already been announced, a quiet hour — is a test
with no running application and no notification centre.

Delivery is a protocol in `Platform`, with one implementation that talks to the
system and one that records what it was given:

```swift
public protocol NotificationDelivering: Sendable {
    /// Whether the system will accept a notification from this build.
    var isAvailable: Bool { get }
    /// Delivers the events. Returns the events that were delivered, so the
    /// state that is remembered is the state that was really sent.
    func deliver(_ events: [NotificationEvent]) async -> [NotificationEvent]
}
```

The remembered state is written by the caller of `deliver`, and only for what
came back. A delivery that failed must not mark the condition as announced,
or the user would never be told.

**Where the mapping happens.** The composition root — `AppEnvironment` and the
model's continuity pass — turns the platform's `ConnectionStatus` into
`ProviderCondition`s and the platform's `Preferences` into a
`NotificationSettings`, then calls the policy after every refresh. The mapping is
a `switch` over the contract's error cases, and it is the one place in the
application where the plugin contract's vocabulary is turned into the core's.

---

## 7. Quiet hours

Between 22:00 and 08:00 in the user's own calendar, the application does not
interrupt — with one exception, which the user can turn off: `limitReached` is
allowed through, because an allowance that runs out at 23:00 and is found at
09:00 is an allowance that was spent for nothing.

A condition that arises during the quiet hours is **deferred, not dropped**. The
next evaluation after 08:00 asks again: if the condition still holds, it
notifies then; if it has cleared, it does not notify at all. The alternative —
dropping it — would mean a limit that was reached and reset within the night is
never mentioned, which is a silence the user cannot tell from a bug.

The hours are the user's, not the system's: they are resolved from the same
`Calendar` every other figure is resolved from, and they are two numbers in
`Preferences`.

---

## 8. The state that has to be remembered

To honour rule 4.2 — a condition that still holds does not notify twice — the
application has to remember what it has already said. That is a sixth record
family, and it is the first one in the project that is about the application's
own behaviour rather than about a provider's data:

```text
notifications.json
```

| Record                    | Key       | Contents                                                                  |
| ------------------------- | --------- | ------------------------------------------------------------------------- |
| `NotificationStateRecord` | `quotaID` | The condition last announced, per kind, and the instant it was announced. |

It is a family of its own rather than a field on the quota because it is not a
fact about the quota: it is a fact about what the user has been told, and it
survives a quota being deleted and recreated.

The record is written **after** a delivery succeeds, and never before. A
delivery that was refused — no permission, no system channel, a failure — leaves
the condition unannounced, so the next poll tries again.

---

## 9. Testing

| Test                       | What it proves                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------------------- |
| `NotificationPolicyTests`  | Each kind fires on its own condition, and only on that condition.                               |
| `NotificationPolicyTests`  | A condition that has already been announced produces nothing.                                   |
| `NotificationPolicyTests`  | A stale reading produces no event; a fresh one produces the event.                              |
| `NotificationPolicyTests`  | A provider that is switched off produces nothing.                                               |
| `NotificationPolicyTests`  | A condition arising inside the quiet hours is deferred, and fires after them if it still holds. |
| `NotificationStateTests`   | A refused delivery does not mark the condition as announced.                                    |
| `NotificationStateTests`   | A condition that clears and returns notifies again.                                             |
| `NotificationChannelTests` | The in-app channel shows the same conditions as the system channel, so the two cannot disagree. |
| `PopoverNotificationTests` | Every kind that can notify is visible in the popover without the system channel.                |

The last one is the load-bearing test. Rule 2.1 — every condition that can
notify is visible in the application — is the promise that makes the optional
channel safe to be optional, and it is the one that would rot first.

---

## 10. What this milestone does not do

- **It does not add a second source of truth.** Nothing here computes usage.
  Everything the notifications say is read from the summaries the rest of the
  application already shows.
- **It does not make the system channel required.** A build without it is a
  complete build.
- **It does not notify about anything the user has not been shown.** The
  figures in a notification are the figures in the popover.

See `spec/0003-milestones.md` (M-20) for the task list and the exit criterion.
