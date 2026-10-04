# Cursor feasibility spike report

> M-13 · recorded 2026-09-26 against a Pro individual account on this Mac.
> Continuous poll closed 2026-09-30. Status: **go**.

## Decision

**Go.** Cursor is viable as the first real provider plugin (M-14).

The local session token, synthesised dashboard cookie, current-period usage
endpoint, and usage-summary fallback all work without reading any other
application's cookie store. The unofficial nature of the endpoints is the main
fragility and is acceptable for an explicitly unofficial integration.

A no-go was not taken. No replacement provider is named.

## Mechanisms

| Mechanism                                                | Verified | Evidence                                                                                                         | Fragility                                                                                                                          |
| -------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Read-only SQLite open of `state.vscdb` with busy timeout | Yes      | DB size ≈ 9.8 GB (> 2 GB). `PRAGMA busy_timeout=5000` succeeded while Cursor was running.                        | Path and schema (`ItemTable` / `cursorAuth/accessToken`) are undocumented and can move.                                            |
| Session access token + JWT subject                       | Yes      | JWT `type` = `session`, `sub` = `google-oauth2\|user_…`, issuer `authentication.cursor.sh`.                      | Token rotation; API-key shaped tokens must be rejected (`type != session`).                                                        |
| Session cookie synthesis                                 | Yes      | `WorkosCursorSessionToken=<userID>%3A%3A<token>` authenticates `cursor.com` endpoints.                           | Cookie format is reverse-engineered.                                                                                               |
| `POST /api/dashboard/get-current-period-usage`           | Yes      | HTTP 200 with `Origin: https://cursor.com`. HTTP 403 `Invalid origin for state-changing request` without Origin. | CSRF/origin rules and path can change.                                                                                             |
| `GET /api/usage-summary` fallback                        | Yes      | HTTP 200; billing cycle dates agree with current-period (ms vs ISO8601).                                         | Same unofficial surface.                                                                                                           |
| `POST api2…/GetCurrentPeriodUsage` with Bearer           | Yes      | Same body shape as the dashboard POST.                                                                           | Alternate path; M-14 may prefer Bearer to avoid cookie synthesis, but the spike locks the cookie+Origin path TASK-304/305 require. |
| No third-party cookie store                              | Yes      | All credentials came from Cursor's own `state.vscdb`.                                                            | N/A                                                                                                                                |

## Percentage semantics (TASK-307)

On the recorded account:

| Source                           | Value                          |
| -------------------------------- | ------------------------------ |
| `includedSpend / limit`          | `2000 / 2000` → **100%**       |
| `individualUsage.plan.remaining` | **0**                          |
| `autoPercentUsed` / display copy | ≈ **11%** / "You've used 10%…" |
| `displayMessage`                 | "You've hit your usage limit"  |

**Rule for Quota:** plan-bucket `usagePercentage = clamp(0…100, includedSpend/limit×100)` when `limit > 0`; otherwise fall back to `autoPercentUsed` / `totalPercentUsed`. The cents fields match the hard stop and `remaining: 0`. The `*PercentUsed` fields disagree with spent/limit on this account and are treated as dashboard copy, not the planning meter.

API / named-models bucket: `apiPercentUsed` (0 on this account).

## Buckets (TASK-308)

Two buckets with meaningful values:

1. `plan` — included plan spend against included limit (`$20 included` here).
2. `api` — named-model / API pool via `apiPercentUsed`.

## Billing cycle (TASK-309)

- Start: `2026-09-22T10:46:32Z`
- End: `2026-10-22T10:46:32Z`
- Duration: 30 days
- **Not** calendar-month aligned (starts on day 22).

Both endpoints agree on these bounds.

## Legacy request-count model (TASK-310)

`GET /api/usage?user=` returns `gpt-4` request counters with `maxRequestUsage: null` and the same `startOfMonth`. No usable cap on this Pro account. Modern `planUsage` / `individualUsage.plan` is the path to normalise; legacy is detected and ignored when no cap is present.

## Absolute on-demand cap (TASK-311)

`individualUsage.onDemand` is `enabled: false` with `limit: null`. No absolute on-demand cap is available for this individual Pro account. Documented as absent.

## Continuous polling (TASK-312 / TASK-313)

Started 2026-09-26 via:

```sh
python3 Scripts/cursor-spike-poll.py --interval 300 --duration 86400 \
  --log .build/cursor-spike-poll/poll.jsonl
```

Log: `.build/cursor-spike-poll/poll.jsonl` (203 samples).

| Metric                         | Result                                                        |
| ------------------------------ | ------------------------------------------------------------- |
| Window                         | 2026-09-26T18:36Z → 2026-09-30T02:59Z (**80.4 h**)            |
| Probe interval                 | 300 s (median gap 301 s; larger gaps only when the Mac slept) |
| `get-current-period-usage`     | **203 / 203** HTTP 200                                        |
| `usage-summary`                | **203 / 203** HTTP 200                                        |
| Rate limiting (429)            | **0**                                                         |
| Auth failures (401 / 403)      | **0**                                                         |
| Response shape (`topKeys`)     | **Unchanged** on both endpoints across the whole window       |
| Billing cycle bounds           | Identical on every sample                                     |
| Latency (usage / summary, p95) | ≈ 570 ms / ≈ 515 ms                                           |

**Minimum viable poll interval (TASK-313):** **300 seconds**. At that cadence
there was no rate limiting and no shape or auth break across more than three
days. A shorter interval was not required for product pacing and was not
validated; M-14 should keep suggesting 300 s (clamped by the platform minimum).

## Fixtures and tests

- `Tests/CursorProviderTests/Fixtures/*.json` — the redacted responses, since the
  spike's own copy went when the spike target did.
- `swift test --filter CursorProviderTests` — fixture and decoder tests (no
  network).
- Live cases behind `QUOTA_LIVE_TESTS`.

## Go / no-go (TASK-316)

**Go** for M-14 Cursor provider plugin. The poll window confirmed response
stability for 80+ hours at 300 s. Fragility to disclose in the product:
unofficial dashboard endpoints and local SQLite session token.
