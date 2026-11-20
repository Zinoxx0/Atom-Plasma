#!/usr/bin/env python3
"""Claude's usage limits straight from Anthropic, for the Claude Usage island and the desk's Clawd.

The status line (~/.claude/statusline.sh or bin/claude-statusline.sh) writes ~/.cache/claude-usage.json only
while a Claude Code session runs here, so after a reboot, or while Claude was used on the web, the phone or
another computer, the rings kept old numbers. This asks the usage endpoint Claude Code's /usage reads and
writes ~/.cache/claude-usage-poll.json in the status line's shape:

    {"checked": <when>, "five_hour": {"used_percentage": 6, "resets_at": <epoch s or null>}, "seven_day": {...}}

qml/Rice/ClaudeUsage.qml shows whichever file is newer (Clawd's working and resting still follow the sessions
here: the status line's file).
atom-plasma-claude-usage.timer runs it at login and every 5 minutes; a run is skipped while a session here
writes the numbers itself. When the numbers change, the widget's alerts.py checks the 80% / 95% notices.

It reads Claude Code's sign-in (~/.claude/.credentials.json) and never changes it: an expired access token
(Claude Code not run for ~8 h) waits until Claude Code next starts and renews it.

    claude-usage.py           check (unless a session here wrote the numbers in the last 4 minutes)
    claude-usage.py --force   check now
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent
CREDS = HOME / ".claude/.credentials.json"
LINE = HOME / ".cache/claude-usage.json"            # the status line's
OUT = HOME / ".cache/claude-usage-poll.json"
ALERTS = ROOT / "plasmoids/com.zinoxx.claudeusage/contents/code/alerts.py"
URL = "https://api.anthropic.com/api/oauth/usage"
WINDOWS = ("five_hour", "seven_day")
FRESH = 240         # s: a session here wrote the numbers this recently, no need to ask


def read(path):
    try:
        v = json.loads(path.read_text())
        return v if isinstance(v, dict) else None
    except (OSError, ValueError):
        return None


def window(w):
    """One window as the endpoint gives it ({"utilization": 6.0, "resets_at": "2026-11-20T19:30:00.41+00:00"},
    or null before the window starts) in the status line's shape. The reset is rounded to the minute: the
    endpoint has sub-second times, the status line whole minutes, and alerts.py marks a notice as sent by it."""
    w = w if isinstance(w, dict) else {}
    try:
        pct = max(0.0, float(w.get("utilization") or 0))
    except (TypeError, ValueError):
        pct = 0.0
    pct = int(pct) if pct == int(pct) else round(pct, 1)
    reset = None
    try:
        if w.get("resets_at"):
            reset = round(datetime.fromisoformat(str(w["resets_at"]).replace("Z", "+00:00")).timestamp() / 60) * 60
    except ValueError:
        pass
    return {"used_percentage": pct, "resets_at": reset}


def stamp(d):
    """When a cache file's numbers were last known right: the status line's `updated`, the poll's `checked`."""
    try:
        return float(d.get("updated", d.get("checked", 0)) or 0) if d else 0
    except (TypeError, ValueError):
        return 0


def newest(*files):
    """The cache file with the newest numbers (None when there are none)."""
    files = [f for f in files if f]
    return max(files, key=stamp) if files else None


def poll_record(data, now):
    """The poll file for the endpoint's answer `data`."""
    return {"checked": int(now), **{k: window(data.get(k)) for k in WINDOWS}}


def token(now):
    """Claude Code's access token, or None (with why) when there's none or it has expired."""
    oauth = (read(CREDS) or {}).get("claudeAiOauth") or {}
    if not oauth.get("accessToken"):
        return None, "not signed in to Claude Code"
    if float(oauth.get("expiresAt") or 0) / 1000 <= now + 60:
        return None, "Claude Code's sign-in has expired; it renews the next time Claude Code starts"
    return oauth["accessToken"], ""


def fetch(tok):
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {tok}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
        "User-Agent": "atom-plasma-claude-usage",
    })
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def main():
    now = time.time()
    line = read(LINE)
    if "--force" not in sys.argv and line and now - stamp(line) < FRESH:
        return 0
    tok, why = token(now)
    if not tok:
        print(why, file=sys.stderr)
        return 0
    try:
        data = fetch(tok)
    except urllib.error.HTTPError as e:
        print(f"usage endpoint: HTTP {e.code}", file=sys.stderr)
        return 1
    except (OSError, ValueError) as e:       # offline (at boot, on a train): the next run tries again
        print(f"usage endpoint unreachable: {e}", file=sys.stderr)
        return 0
    if not isinstance(data, dict):
        print("usage endpoint: unexpected answer", file=sys.stderr)
        return 1
    poll = read(OUT)
    rec = poll_record(data, time.time())
    before = newest(line, poll) or {}
    tmp = OUT.with_name(OUT.name + ".tmp")
    tmp.write_text(json.dumps(rec, separators=(",", ":")) + "\n")
    os.replace(tmp, OUT)
    if any(rec[k] != before.get(k) for k in WINDOWS) and ALERTS.exists():
        subprocess.run([sys.executable, str(ALERTS)], check=False, timeout=30)
    return 0


if __name__ == "__main__":
    sys.exit(main())
