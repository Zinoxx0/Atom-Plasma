#!/usr/bin/env python3
"""Read-only probe of active T3 Code runs for a provider (default: antigravity).

Reads ~/.t3/userdata/statev2.sqlite in read-only mode (no writes, no locks held) and prints:
    {"running": <int>, "status": "running"|"idle", "ts": <epoch>}

Used by qml/Rice/GeminiActivity.qml (triggered only via inotify when statev2.sqlite-wal changes,
zero polling when idle) so Gemini's Antigravity gravity waves animate in real time while T3 Code
is actively thinking or running tools, and settle calmly the moment the turn finishes.
"""
import json
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

DB = Path.home() / ".t3/userdata/statev2.sqlite"
ACTIVE_STATUSES = ("preparing", "starting", "running")
STALE_SECONDS = 2 * 3600


def _iso_epoch(s):
    if not s:
        return 0.0
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def query(provider="antigravity", db_path=None, now=None):
    db = Path(db_path) if db_path else DB
    now = time.time() if now is None else float(now)
    if not db.is_file():
        return {"running": 0, "status": "idle", "ts": int(now)}
    con = None
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=0.2)
        rows = con.execute(
            "SELECT status, requested_at FROM orchestration_v2_projection_runs "
            "WHERE provider = ? AND completed_at IS NULL AND status IN ('preparing', 'starting', 'running')",
            (provider,),
        ).fetchall()
        active = 0
        for _, req in rows:
            t = _iso_epoch(req)
            if t <= 0 or (now - t) < STALE_SECONDS:
                active += 1
        return {"running": active, "status": "running" if active > 0 else "idle", "ts": int(now)}
    except sqlite3.Error:
        return {"running": 0, "status": "idle", "ts": int(now)}
    finally:
        if con is not None:
            try:
                con.close()
            except sqlite3.Error:
                pass


def main():
    provider = sys.argv[1] if len(sys.argv) > 1 else "antigravity"
    print(json.dumps(query(provider)))


if __name__ == "__main__":
    main()
