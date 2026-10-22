# Quota — Claude Code feasibility spike

> The plan for the gate that decides whether Quota can read Claude Code's usage.
> Companion to `spec/0001-definition.md` §13 (provider discovery) and
> `spec/0004-cursor-spike-report.md` (the same gate, run for Cursor).
>
> **This document is a plan, not a report.** The findings go into
> `spec/0008-claude-spike-report.md`, and the decision goes there too.

---

## 1. The constraint that shapes the whole spike

**The project owner has no Claude account and does not use Claude Code.**

That rules out the method M-13 used, which was to watch a real account for
twenty-four hours and record every response. It also rules out the obvious
alternative — "ask a colleague to run it" — because a provider that only one
person can test is a provider that will break unnoticed.

So this spike is not the Cursor spike with a different provider. It is a
different kind of investigation, and the difference has to be designed for
rather than discovered halfway through:

|                    | Cursor (M-13)                          | Claude Code (this spike)                                        |
| ------------------ | -------------------------------------- | --------------------------------------------------------------- |
| Account available  | yes                                    | **no**                                                          |
| What was measured  | live responses, over 80 h              | **synthetic fixtures**                                          |
| What was verified  | the mechanism against the real service | the mechanism against **the documented format**                 |
| What was left open | rate limits, stability                 | **the window arithmetic, the allowance, the limits themselves** |
| Gate               | go / no-go                             | go / **conditional go** / no-go                                 |

The spike therefore has one job above all: **separate what can be settled on
this machine from what cannot, and write the second list down precisely enough
that it can be closed later by anyone with an account.**

---

## 2. Three tiers of confidence

Every fact the plugin will rely on is placed in one of three tiers, and the
plugin's behaviour differs for each. This is the core idea of the spike, and it
is what makes building ahead of the verification defensible.

| Tier         | Meaning                                                                          | Where it comes from                 | What the plugin does with it                            |
| ------------ | -------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------- |
| **Verified** | Observed on this machine, or stated by a document that specifies it              | a fixture, a test, a cited document | relied upon                                             |
| **Assumed**  | Believed from the documentation or from the shape of the mechanism, not observed | a document, a reasonable inference  | relied upon, but **fails loudly** when it does not hold |
| **Unknown**  | Cannot be known without an account                                               | —                                   | **not relied upon**; the plugin says it does not know   |

The rule that makes this work: **the plugin never guesses a number it cannot
derive.** A tier-2 fact that turns out to be wrong must produce a refusal
(`invalidResponse`, `usageUnavailable`), never a plausible-looking percentage.
A wrong number is worse than no number, because the whole product is a number
the user trusts enough to pace their work against.

---

## 3. The two candidate mechanisms

Claude Code's subscription allowance is metered in **tokens**, in **two
windows**: a rolling five-hour session window, and a weekly limit per model.
There are two places those numbers could come from.

### 3.1 Mechanism A — the local transcript

Claude Code writes a session transcript per project as JSONL, under
`~/.claude/projects/<slug>/<session-id>.jsonl`. Each assistant turn carries the
model it used and a usage record.

**What it gives:**

- tokens used, per model, per moment — which is what the plan meters;
- the timestamps, so the window boundaries can be derived;
- no network, no credential, no rate limit, and **no account needed to read it**.

**What it costs:**

- **it is not a documented API.** It is an implementation detail of the CLI and
  it can change in any release, with no notice and no deprecation;
- it exists only where Claude Code has been run, so a user who has never used it
  has nothing to read — which is _correct_, but must be said rather than shown
  as an empty quota;
- reading it means reading **the user's prompts and their code**, which the
  plugin must handle carefully (§7).

### 3.2 Mechanism B — the account's own usage endpoint

Claude Code's CLI asks Anthropic's backend for the remaining allowance and the
reset instant, which is what `/status` and the status line display.

**What it gives:**

- the exact numbers the user's own CLI shows — no allowance table, no estimate;
- the reset instants as the service states them, rather than as derived.

**What it costs:**

- it needs an OAuth credential and an account, so it **cannot be built or tested
  here at all**;
- it is an undocumented internal endpoint and may be gated, rate limited, or
  changed without notice;
- its response shape is unknown, so the normaliser would have to be written
  against a guess.

### 3.3 The decision the spike has to make

**Mechanism A is built first; Mechanism B is the upgrade.**

The reasoning is not "A is better". It is that **A is the only one that can be
built and tested on this machine**, and a mechanism that cannot be tested is a
mechanism whose fragility is unknown. A is also the one that degrades more
gracefully: it needs nothing from the network, so it keeps working when the
endpoint changes, when the account is not signed in, and when the user is
offline.

The plugin is written so that **the mechanism is a seam**: the reader is one
type with two implementations, and swapping in the endpoint reader later is a
change inside the plugin package, not a change to the host or to the data model.

---

## 4. What the plugin will compute, and the hard part in the middle

Claude Code's quota is not one number. It is, per model:

- a **five-hour rolling window**, with a token allowance, and
- a **weekly window**, with a token allowance.

Quota's model already carries this: a provider reports **several buckets**, and
each bucket is a window with its own usage. M-17 made that shape, so Claude
Code does not need a new domain concept — it needs a reader.

The hard part is the middle of the computation:

```text
usagePercentage = tokensUsedInWindow / allowanceOfWindow × 100
```

The numerator is measurable. **The denominator is not**, and it is where the
spike has to be honest.

### 4.1 The allowance problem

The allowances are published by Anthropic per plan and per model, and they
change. They are not in the transcript. So a plugin that reports a percentage
must know the allowance, and there are exactly three ways to get it:

| Option                               | How                                                                                                 | What it costs                                                                      |
| ------------------------------------ | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| **A. A table of published limits**   | the plugin ships the published figures per plan and model, and the user says which plan they are on | the table goes stale, and a stale table produces wrong percentages that look right |
| **B. The user states the allowance** | the user tells the plugin how many tokens the window allows                                         | honest and exact, but it asks the user for work the app is supposed to do          |
| **C. The service states it**         | Mechanism B, or a `status` output the CLI writes                                                    | the most correct, and the one that needs an account                                |

**The decision: A with B as the override, and C as the destination.**

- The plugin ships a table of the published allowances, marked as an estimate
  everywhere it is used.
- The user can override the allowance per plan and per model in the plugin's own
  configuration file, and the override wins.
- The plugin's report carries the word "estimated" in its `limitDescription`
  whenever the figure came from the built-in table rather than from the user or
  the service. **The interface shows that word**, because a percentage whose
  denominator is a guess must not look like one whose denominator is known.

This is the same discipline the Cursor plugin already follows with the
unofficial notice: the plugin says what it is, and the interface says it too.

### 4.2 The window arithmetic

The five-hour window is defined as beginning with the first message of a
session, and the weekly window resets at a weekly boundary tied to the
subscription. Both are derivable from local timestamps — but both are
**tier 2 (assumed)** until observed.

The spike therefore treats the window arithmetic as the highest-risk part of
the plugin and designs for it:

- the window start is derived from the transcript, never from the clock at read
  time;
- the derivation is stated in the bucket's `limitDescription` ("five-hour window
  from 14:02"), so a wrong derivation is visible on screen rather than buried;
- the fixture corpus includes a session that crosses a window boundary and a
  session that starts a new one after a long gap, because those are the two
  cases where the arithmetic is wrong if it is wrong.

---

## 5. The tasks

The spike is a list of questions and a list of artefacts. Each task below
produces something checkable.

### 5.1 What can be settled without an account

| #    | Question                                                                     | How it is settled                                                                   | Result                                                |
| ---- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------- |
| C-01 | Where do transcripts live, and what is the layout of a project directory?    | read the local filesystem, and the published documentation                          | a written layout, tier 1                              |
| C-02 | What does a transcript line look like?                                       | a synthetic fixture modelled on the documented format                               | a written format, tier 1                              |
| C-03 | Which fields carry the usage, and which carry the model?                     | the fixture                                                                         | a written field map, tier 1                           |
| C-04 | How is a project path turned into a directory name?                          | fixtures with spaces, dots, dashes, non-ASCII, and a path that differs only in case | a written rule, tier 1                                |
| C-05 | How are messages attributed to a day, and to a window?                       | fixtures spanning midnight and spanning a window boundary                           | a written rule, tier 1                                |
| C-06 | What happens when a line is malformed, truncated, or empty?                  | fixtures                                                                            | a written rule, tier 1                                |
| C-07 | How is the account identified, and what is the label?                        | the keychain item's shape and `~/.claude.json`, read without values                 | a written rule, tier 1                                |
| C-08 | Can the plugin read the transcripts with a read-only handle, without a lock? | a real directory with a file open for append                                        | a written answer, tier 1                              |
| C-09 | What is the plugin's own configuration, and where does it live?              | design                                                                              | a written answer, tier 1                              |
| C-10 | What is the allowance table, and what does each entry rest on?               | the published limits, each cited                                                    | a cited table, tier 2 where the source is a blog post |

### 5.2 What cannot be settled without an account

These are the questions the spike is _not_ allowed to guess at. Each one is
written with what it would take to close it and what would change in the design
if the answer went either way — so the person who eventually has an account can
close them without re-reading the design.

| #    | Question                                                                                                  | What would close it                                                     | If the answer is different                                                                                      |
| ---- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| U-01 | Is the five-hour window's start the first message, or a fixed wall-clock boundary?                        | an account, and the CLI's `/status` read against the transcript         | if it is wall-clock, the window start is read from a different source and the derivation changes                |
| U-02 | Does the weekly window reset on a fixed weekday, and if so, which?                                        | an account, across two week boundaries                                  | if it is a rolling seven days, the weekly bucket's period is a window and not a date range                      |
| U-03 | Are the published allowances accurate for a given plan, and do they vary by model?                        | an account on each plan                                                 | if they do, the built-in table is wrong and the user override becomes the primary path                          |
| U-04 | Do cache-read and cache-creation tokens count against the limit?                                          | an account, with the CLI's own figure compared against the transcript's | if they do not count, the numerator must exclude them, and the fixture corpus has to say so                     |
| U-05 | Does the CLI write the transcripts when it is used through an IDE integration, or only from the terminal? | an account, used both ways                                              | if only from the terminal, the plugin's scope must say "the terminal", in the interface, not only in the readme |
| U-06 | Is there an endpoint that states the remaining allowance exactly?                                         | an account and a captured response                                      | if yes, it is Mechanism B, and it replaces the allowance table entirely                                         |
| U-07 | Does the CLI keep a machine-readable record of its own status?                                            | an account, and a look at the CLI's state directory                     | if yes, it is a third mechanism, cheaper and more exact than either                                             |

**U-01, U-03 and U-04 are the load-bearing ones.** If the window start is not
the first message, the plugin's central computation changes; if the allowances
are wrong, every percentage is wrong; if cache tokens do not count, the
numerator is wrong. The plugin ships with all three marked as assumed, and the
plugin's report says so.

---

## 6. The fixture corpus

The plugin is written against **synthetic transcripts**, in the same spirit as
the Cursor plugin's recorded responses: a fixture that resembles the real thing
is a fixture the parser can be tested against, and a fixture that resembles the
_awkward_ parts of the real thing is worth ten that resemble the easy parts.

| Fixture                              | What it exercises                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------ |
| A plain session                      | the normal path: several assistant turns, one model, usage on each             |
| A session with tool calls            | tool results carry no usage, and must not be counted                           |
| A session with caching               | `cache_creation` and `cache_read` tokens, counted or excluded per U-04         |
| A session with two models            | two buckets, and a bucket per model per window                                 |
| A session crossing midnight          | day attribution                                                                |
| A session crossing a window boundary | the window arithmetic of §4.2                                                  |
| A session after a long gap           | the start of a new window                                                      |
| A truncated final line               | a transcript written by a running process, and a crash                         |
| An empty file                        | a session that did nothing                                                     |
| A hostile project directory          | a path with spaces, dots, non-ASCII, and two paths differing only in case      |
| A clock-skewed timestamp             | a timestamp in the future, and one in the past relative to the day             |
| An unknown field                     | a new field in a future CLI release, which must be ignored rather than refused |

The fixtures are **hand-written and marked as synthetic**, in their own
directory, with a header saying so. They are never presented as recorded data,
and the plugin's report says which fixtures are synthetic — a test corpus that
looks like real data is a corpus that will be believed.

---

## 7. Reading the user's transcripts

This deserves its own section because it is the part of this provider that is
different in kind from Cursor's.

A transcript contains **the user's prompts and the source code they had open**.
The plugin reads the file. It must not read the parts it does not need.

The rules:

1. **Only usage fields are extracted.** The parser reads the model, the usage
   counters and the timestamp. It never reads the message body, and there is no
   code path that copies one.
2. **Nothing is logged.** Not a line, not a truncated line, not a field name
   that happens to be a prompt. The plugin's diagnostics carry counts and
   timestamps, never content.
3. **Nothing leaves the machine.** The plugin makes no network request at all
   under Mechanism A. §54 of the definition is not merely respected; there is no
   egress to respect.
4. **The plugin reads what it needs and stops.** The reader opens the file
   read-only, reads it line by line, and closes it. It never copies, never
   indexes, never caches a transcript.
5. **The user is told.** The first time the Claude Code provider is connected,
   the interface says what the plugin reads and where it reads it from. A user
   who does not know their prompts are being read is a user who finds out from
   a bug report.

---

## 8. The gate

The spike closes with a decision, and the decision is one of three.

**Go.** Every tier-2 fact in §5.2 that the plugin depends on has been verified.
The plugin is built without qualification.

**Conditional go.** The mechanism is sound — the fixture corpus parses, the
window arithmetic is consistent, the plugin reads the transcripts read-only —
but U-01, U-03 or U-04 remain open. Then:

- the plugin is built and shipped;
- it is declared **unofficial**, as the Cursor plugin is;
- every figure it reports is marked **estimated** in the interface, and the
  mark is not optional and not hidden behind a disclosure;
- the open questions stay on the list, in `spec/0008-claude-spike-report.md`,
  each with what would close it.

**No-go.** The transcript does not carry a recoverable usage record, or the
window cannot be derived from local timestamps at all. Then the provider is
dropped, and the milestone says which provider replaces it — as M-13's TASK-316
requires of a no-go.

The most likely outcome is the conditional go, and the design above is built to
make it safe: the estimated figures are labelled, the plugin refuses rather than
guesses, and the failure mode of a wrong allowance is a visibly wrong number
rather than a silent one.

### 8.1 The exit criterion

```sh
swift test --filter ClaudeProviderTests
```

The fixtures parse into valid snapshots, the window arithmetic is exercised
across the boundaries in the corpus, the malformed cases are handled, and the
report exists with its three tiers and its decision.

---

## 9. What the spike does not do

- **It does not claim to have tested the real service.** Nothing in the report
  may say "verified" about a fact that was only read in a document.
- **It does not invent a second provider.** If the local mechanism fails, the
  decision is a no-go with a named replacement, not a quiet pivot.
- **It does not promise an exact percentage.** The plugin's contract is
  "tokens used, against a stated allowance", and the allowance's provenance is
  part of the report.

See `spec/0003-milestones.md` (M-18) for the task list.
