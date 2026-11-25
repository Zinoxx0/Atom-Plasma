#!/usr/bin/env python3
"""Notify once when a Gemini usage window (5h or weekly) crosses 80% / 95%.

Reads the newer of:
  - ~/.t3/caches/antigravity.json   (T3 Code's live Antigravity quota cache)
  - ~/.cache/gemini-usage.json      (standalone CLI / custom adapter cache)

Respects modules.gemini.enabled and modules.gemini.config.alerts in ~/.config/atom-plasma/settings.json.
"Already sent" state lives in ~/.local/state/rice/gemini-alerts.json.
"""
import fcntl
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
T3_CACHE = HOME / ".t3/caches/antigravity.json"
LOCAL_CACHE = HOME / ".cache/gemini-usage.json"
SETTINGS = HOME / ".config/atom-plasma/settings.json"
ALERTS = HOME / ".local/state/rice/gemini-alerts.json"


def _epoch(v):
    if v is None or v == "":
        return 0.0
    if isinstance(v, (int, float)):
        return float(v / 1000.0 if v > 1e12 else v)
    if isinstance(v, str):
        try:
            return float(datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())
        except ValueError:
            return 0.0
    return 0.0


def _alerts_enabled():
    try:
        cfg = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        return True
    mod = (cfg.get("modules") or {}).get("gemini") or {}
    if mod.get("enabled") is False:
        return False
    return bool((mod.get("config") or {}).get("alerts", True))


def parse_windows(data):
    """Extract (timestamp, [(id, label, pct, reset_epoch)]) from either T3 antigravity.json
    or a standalone gemini-usage.json."""
    if not isinstance(data, dict):
        return 0.0, []
    ul = data.get("usageLimits") if isinstance(data.get("usageLimits"), dict) else data
    ts = max(_epoch(ul.get("checkedAt")), _epoch(ul.get("updated")), _epoch(ul.get("checked")), _epoch(data.get("checkedAt")))
    out = []
    wins = ul.get("windows")
    if isinstance(wins, list):
        for w in wins:
            if not isinstance(w, dict):
                continue
            wid = str(w.get("id") or "")
            if wid not in ("gemini-5h", "gemini-weekly"):
                continue
            label = "5-hour" if wid == "gemini-5h" else "weekly"
            pct = float(w.get("usedPercent") if w.get("usedPercent") is not None else w.get("used_percentage") or 0)
            reset = _epoch(w.get("resetsAt") or w.get("resets_at"))
            out.append((wid, label, pct, reset))
        return ts, out
    for key, wid, label in (("five_hour", "gemini-5h", "5-hour"), ("seven_day", "gemini-weekly", "weekly")):
        w = ul.get(key)
        if isinstance(w, dict):
            pct = float(w.get("used_percentage") if w.get("used_percentage") is not None else w.get("usedPercent") or 0)
            reset = _epoch(w.get("resets_at") or w.get("resetsAt"))
            out.append((wid, label, pct, reset))
    return ts, out


def newest():
    """Return the parsed windows list from whichever cache file is newest, or []."""
    best_ts, best_wins = -1.0, []
    for path in (T3_CACHE, LOCAL_CACHE):
        try:
            d = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        ts, wins = parse_windows(d)
        if wins and ts > best_ts:
            best_ts, best_wins = ts, wins
    return best_wins


def until(ts, now):
    s = max(0, int(ts - now))
    d, rem = divmod(s, 86400)
    h, m = divmod(rem // 60, 60)
    return f"{d}d {h}h" if d else (f"{h}h {m:02d}m" if h else f"{m}m")


def when(ts):
    t = datetime.fromtimestamp(ts)
    return t.strftime("%H:%M") if t.date() == datetime.now().date() else t.strftime("%a %H:%M")


def main():
    if not _alerts_enabled():
        return
    now = time.time()
    wins = newest()
    if not wins:
        return
    ALERTS.parent.mkdir(parents=True, exist_ok=True)
    with open(ALERTS.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            sent = json.loads(ALERTS.read_text())
        except (OSError, ValueError):
            sent = {}
        changed = False
        for wid, label, pct, reset in wins:
            if not reset or reset <= now:
                continue
            for level in (95, 80):
                if pct < level:
                    continue
                k = f"{wid}:{round(reset / 60) * 60}:{level}"
                if not sent.get(k):
                    sent[k] = changed = True
                    subprocess.run([
                        "notify-send", "-a", "Gemini", "-i", "dialog-information",
                        f"Gemini {label} limit at {pct:.0f}%",
                        f"Resets in {until(reset, now)} ({when(reset)})",
                    ], check=False)
                break
        if changed:
            tmp = ALERTS.with_suffix(".tmp")
            tmp.write_text(json.dumps(sent))
            tmp.replace(ALERTS)


if __name__ == "__main__":
    main()
