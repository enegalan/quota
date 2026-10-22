# Quota — Claude Code feasibility spike report

> **Status: not started.** The spike has not been run.
>
> This file is the **shape** of the report, not the report. It exists so that the
> spike has somewhere to write, so that the links to it are not broken, and so
> that the questions the spike must answer are written down before the answers
> are found.
>
> The plan it answers is `spec/0007-claude-spike-plan.md`. The milestone is M-18
> in `spec/0003-milestones.md`, and the decision it closes is M-18 TASK-421.

---

## 1. The decision

<!-- Filled in by TASK-421. One of: go / conditional go / no-go. -->

**Decision:** _not yet taken_

**Conditions, if the decision is a conditional go:**

<!--
Each condition must be a question that can be closed, and a statement of what
changes in the plugin when it is closed. "U-01: the five-hour window starts at
the first message rather than at a wall-clock boundary. While this is open, the
window is derived from the transcript and the derivation is stated in every
bucket's description."
-->

## 2. The three tiers

Every fact the plugin relies on is placed in one of the three tiers of §2 of the
spike plan. This section is the whole point of the report: **a reader must be
able to tell, at a glance, what was observed and what was believed.**

| Tier     | Fact | Evidence | Date |
| -------- | ---- | -------- | ---- |
| Verified |      |          |      |
| Assumed  |      |          |      |
| Unknown  |      |          |      |

## 3. The local layout

<!-- C-01, C-04, C-07, C-08, C-09 -->

**Where the transcripts live:**

**How a project path becomes a directory name:**

**How the account is identified, and what the label is when it cannot be:**

**Whether the transcripts can be read read-only while Claude Code is running:**

**The plugin's own configuration, and where it lives:**

## 4. The transcript format

<!-- C-02, C-03, C-06 -->

**The fields the plugin reads:**

| Field | Meaning | Read? |
| ----- | ------- | ----- |
|       |         |       |

**The fields the plugin never reads, and why:**

**What happens to a malformed, truncated or empty line:**

## 5. The windows

<!-- C-05, and U-01, U-02 -->

**How a message is attributed to a day:**

**How the five-hour window's start is derived:**

**How the weekly window's start is derived:**

**Which of these is verified, and which is assumed:**

## 6. The allowance

<!-- C-10, and U-03, U-04 -->

| Plan | Model | Window | Allowance | Source | Tier |
| ---- | ----- | ------ | --------- | ------ | ---- |

**What the user can override, and where:**

**Whether cache tokens count against the limit, and how the plugin is told:**

## 7. The mechanism

<!-- TASK-420 -->

**The mechanism chosen:**

**The seam that lets the other mechanism replace it:**

**Why:**

## 8. The questions that remain open

<!-- U-01 to U-07 -->

| #    | Question | What would close it | What would change if the answer differs |
| ---- | -------- | ------------------- | --------------------------------------- |
| U-01 |          |                     |                                         |

## 9. The fixture corpus

<!-- TASK-414 -->

| Fixture | What it exercises |
| ------- | ----------------- |

**Which of the fixtures are synthetic, and how the report says so:**

## 10. What the plugin reads of the user

<!-- §7 of the spike plan -->

**What the plugin reads, and what it refuses to read:**

**What it logs, and what it never logs:**

**What leaves the machine:**

## 11. The privacy of the local mechanism

The plugin reads the user's prompts and the source they had open, because that
is where the usage record is. This section is what the user is shown, in the
application, before the provider is connected.
