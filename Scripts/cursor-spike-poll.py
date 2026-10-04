#!/usr/bin/env python3
"""Continuous Cursor usage poll for the spike.

Reads the local session token, calls the current-period and usage-summary
endpoints, and appends a redacted record to a JSONL log. Never writes the
token, cookie, or unauthorised response bodies.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

STATE_DB = Path.home() / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
ACCESS_TOKEN_KEY = "cursorAuth/accessToken"
BUSY_TIMEOUT_MS = 5000
ORIGIN = "https://cursor.com"
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
USAGE_URL = "https://cursor.com/api/dashboard/get-current-period-usage"
SUMMARY_URL = "https://cursor.com/api/usage-summary"

def read_token() -> tuple[str, str]:
    con = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True)
    con.execute(f"PRAGMA busy_timeout={BUSY_TIMEOUT_MS}")
    row = con.execute(
        "SELECT value FROM ItemTable WHERE key = ?", (ACCESS_TOKEN_KEY,)
    ).fetchone()
    if not row:
        raise SystemExit("access token missing from Cursor state database")
    token = row[0].decode() if isinstance(row[0], bytes) else row[0]
    payload_b64 = token.split(".")[1]
    payload_b64 += "=" * (-len(payload_b64) % 4)
    payload = json.loads(base64.urlsafe_b64decode(payload_b64))
    if payload.get("type") != "session":
        raise SystemExit("token is not a session token")
    user_id = str(payload["sub"]).split("|")[-1]
    return token, user_id

def cookie_header(user_id: str, token: str) -> str:
    return f"WorkosCursorSessionToken={quote(user_id + '::' + token, safe='')}"

def call(method: str, url: str, headers: dict, body: bytes | None = None):
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, dict(response.headers), raw, time.monotonic() - started
    except urllib.error.HTTPError as error:
        raw = error.read()
        return error.code, dict(error.headers), raw, time.monotonic() - started

def fingerprint(obj: object) -> list[str]:
    if isinstance(obj, dict):
        return sorted(obj.keys())
    return [type(obj).__name__]

def summarise_usage(body: dict) -> dict:
    plan = body.get("planUsage") or {}
    return {
        "billingCycleStart": body.get("billingCycleStart"),
        "billingCycleEnd": body.get("billingCycleEnd"),
        "includedSpend": plan.get("includedSpend"),
        "limit": plan.get("limit"),
        "autoPercentUsed": plan.get("autoPercentUsed"),
        "apiPercentUsed": plan.get("apiPercentUsed"),
        "totalPercentUsed": plan.get("totalPercentUsed"),
        "enabled": body.get("enabled"),
        "topKeys": fingerprint(body),
    }

def summarise_summary(body: dict) -> dict:
    plan = ((body.get("individualUsage") or {}).get("plan")) or {}
    return {
        "billingCycleStart": body.get("billingCycleStart"),
        "billingCycleEnd": body.get("billingCycleEnd"),
        "used": plan.get("used"),
        "limit": plan.get("limit"),
        "remaining": plan.get("remaining"),
        "autoPercentUsed": plan.get("autoPercentUsed"),
        "apiPercentUsed": plan.get("apiPercentUsed"),
        "topKeys": fingerprint(body),
    }

def poll_once(cookie: str) -> dict:
    headers = {
        "Content-Type": "application/json",
        "Cookie": cookie,
        "User-Agent": UA,
        "Origin": ORIGIN,
        "Referer": "https://cursor.com/dashboard/spending",
    }
    usage_status, usage_headers, usage_raw, usage_ms = call(
        "POST", USAGE_URL, headers, b"{}"
    )
    summary_status, summary_headers, summary_raw, summary_ms = call(
        "GET",
        SUMMARY_URL,
        {"Cookie": cookie, "User-Agent": UA},
    )

    record = {
        "at": datetime.now(timezone.utc).isoformat(),
        "usage": {
            "status": usage_status,
            "elapsedMs": round(usage_ms * 1000),
            "rateLimited": usage_status == 429,
            "retryAfter": usage_headers.get("Retry-After") or usage_headers.get("retry-after"),
        },
        "summary": {
            "status": summary_status,
            "elapsedMs": round(summary_ms * 1000),
            "rateLimited": summary_status == 429,
            "retryAfter": summary_headers.get("Retry-After")
            or summary_headers.get("retry-after"),
        },
    }

    if usage_status == 200:
        try:
            record["usage"]["body"] = summarise_usage(json.loads(usage_raw))
        except json.JSONDecodeError:
            record["usage"]["parseError"] = True
    elif usage_status in (401, 403):
        record["usage"]["authFailed"] = True

    if summary_status == 200:
        try:
            record["summary"]["body"] = summarise_summary(json.loads(summary_raw))
        except json.JSONDecodeError:
            record["summary"]["parseError"] = True
    elif summary_status in (401, 403):
        record["summary"]["authFailed"] = True

    return record

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--interval",
        type=int,
        default=300,
        help="seconds between polls (default 300)",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=86400,
        help="total seconds to run (default 86400)",
    )
    parser.add_argument(
        "--log",
        type=Path,
        default=Path(".build/cursor-spike-poll/poll.jsonl"),
        help="JSONL output path",
    )
    args = parser.parse_args()

    args.log.parent.mkdir(parents=True, exist_ok=True)
    token, user_id = read_token()
    cookie = cookie_header(user_id, token)
    deadline = time.monotonic() + args.duration
    print(
        f"polling every {args.interval}s for {args.duration}s → {args.log}",
        flush=True,
    )

    while True:
        record = poll_once(cookie)
        with args.log.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
        print(
            f"{record['at']} usage={record['usage']['status']} "
            f"summary={record['summary']['status']}",
            flush=True,
        )
        if time.monotonic() >= deadline:
            break
        time.sleep(args.interval)

    print("poll window complete", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
