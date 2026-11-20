#!/usr/bin/env python3
"""Notify once when the Claude session or weekly limit crosses 80% / 95%.

Run by ~/.claude/statusline.sh and bin/claude-usage.py whenever the limits they cache for the Claude Usage
applet change (a lock keeps two runs from both sending); it reads the newer of the two files. "Already sent" state lives in
~/.local/state/rice/claude-alerts.json. The icons are Clawd tired (80%) and exhausted (95%): usage
shows as tiredness, never nerves.
"""
import fcntl
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CACHES = (HOME / ".cache/claude-usage.json",          # the status line's (a session here): "updated"
          HOME / ".cache/claude-usage-poll.json")     # bin/claude-usage.py's (from Anthropic): "checked"
ALERTS = HOME / ".local/state/rice/claude-alerts.json"
IMAGES = Path(__file__).resolve().parent.parent / "images"


def until(ts, now):
    s = max(0, int(ts - now))
    d, rem = divmod(s, 86400)
    h, m = divmod(rem // 60, 60)
    return f"{d}d {h}h" if d else (f"{h}h {m:02d}m" if h else f"{m}m")


def when(ts):
    t = datetime.fromtimestamp(ts)
    return t.strftime("%H:%M") if t.date() == datetime.now().date() else t.strftime("%a %H:%M")


def newest():
    """The cache with the newest numbers, or None."""
    best, at = None, -1
    for f in CACHES:
        try:
            d = json.loads(f.read_text())
            t = float(d.get("updated", d.get("checked", 0)) or 0)
        except (OSError, ValueError, TypeError, AttributeError):
            continue
        if t > at:
            best, at = d, t
    return best


def main():
    now = time.time()
    data = newest()
    if data is None:
        return
    ALERTS.parent.mkdir(parents=True, exist_ok=True)
    with open(ALERTS.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)        # read, send and save as one step
        try:
            sent = json.loads(ALERTS.read_text())
        except (OSError, ValueError):
            sent = {}
        changed = False
        for key, label in (("five_hour", "session"), ("seven_day", "weekly")):
            w = data.get(key) or {}
            pct, reset = float(w.get("used_percentage") or 0), float(w.get("resets_at") or 0)
            if not reset or reset <= now:
                continue
            for level, look in ((95, "exhausted"), (80, "tired")):
                if pct < level:
                    continue
                k = f"{key}:{round(reset / 60) * 60}:{level}"     # (to the minute: both sources agree)
                if not sent.get(k):
                    sent[k] = changed = True
                    subprocess.run(["notify-send", "-a", "Claude", "-i", str(IMAGES / f"clawd-{look}-big.png"),
                                    f"Claude {label} limit at {pct:.0f}%",
                                    f"Resets in {until(reset, now)} ({when(reset)})"], check=False)
                break
        if changed:
            tmp = ALERTS.with_suffix(".tmp")
            tmp.write_text(json.dumps(sent))
            tmp.replace(ALERTS)


if __name__ == "__main__":
    main()
