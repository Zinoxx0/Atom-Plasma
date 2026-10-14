#!/usr/bin/env python3
"""Notify once when the Claude session or weekly limit crosses 80% / 95%.

Run every minute by the Claude Usage applet. "Already sent" state lives in
~/.local/state/rice/claude-alerts.json.
"""
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache/claude-usage.json"
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


def main():
    now = time.time()
    try:
        data = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        return
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
        for level, mood in ((95, "panic"), (80, "sweat")):
            if pct < level:
                continue
            k = f"{key}:{int(reset)}:{level}"
            if not sent.get(k):
                sent[k] = changed = True
                subprocess.run(["notify-send", "-a", "Claude", "-i", str(IMAGES / f"clawd-{mood}-big.png"),
                                f"Claude {label} limit at {pct:.0f}%",
                                f"Resets in {until(reset, now)} ({when(reset)})"], check=False)
            break
    if changed:
        ALERTS.parent.mkdir(parents=True, exist_ok=True)
        ALERTS.write_text(json.dumps(sent))


if __name__ == "__main__":
    main()
