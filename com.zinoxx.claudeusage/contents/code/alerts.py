#!/usr/bin/env python3
"""Notify once when the Claude session or weekly limit crosses 80% / 95%.

Run every minute by the Claude Usage applet (one per bar it's on: a lock keeps two runs from both
sending). "Already sent" state lives in ~/.local/state/rice/claude-alerts.json. The icons are Clawd
tired (80%) and exhausted (95%): usage shows as tiredness, never nerves.
"""
import fcntl
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
                k = f"{key}:{int(reset)}:{level}"
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
