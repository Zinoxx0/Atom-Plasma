#!/usr/bin/env python3
"""The agenda for the bar's clock (com.zinoxx.clock): Portuguese holidays (offline, with Lisbon's 13 June)
and the events of a Google Calendar read from its secret iCal address, recurring ones expanded. Cached in
~/.cache/rice/calendar.json (replaced whole, so widgets watching it see the change) and refreshed at most
every 15 minutes. (Not "calendar.py": that would shadow Python's calendar module for every script here.)

    agenda.py                   print the calendar (fetching first when the cache is stale)
    agenda.py --force           fetch now
    agenda.py set-url URL       remember the secret iCal address (~/.config/atom-plasma/secrets.json,
                                readable by you only: it's a password to the calendar); "" forgets it
    agenda.py status            where things stand, without the address

Events: a week back to 60 days ahead; holidays: last year to next year. Settings (settings.json "calendar"): {"holidays": "pt",
"municipal": "lisbon"} (municipal: "" for none). Needs python-icalendar and
python-recurring-ical-events for the events; holidays work without them.
"""
import datetime as dt
import fcntl
import json
import os
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

from atom import util

CACHE = util.CACHE
OUT = CACHE / "calendar.json"
SECRETS = Path.home() / ".config/atom-plasma/secrets.json"
MAX_AGE = 15 * 60
BACK, AHEAD = 7, 60


# ------------------------------------------------------------------ holidays
def easter(year):
    """Gregorian Easter Sunday (Anonymous Gregorian algorithm)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = (h + l - 7 * m + 114) % 31 + 1
    return dt.date(year, month, day)


MUNICIPAL = {"lisbon": ((6, 13), "Santo António"), "porto": ((6, 24), "São João")}


def holidays(year, municipal="lisbon"):
    """Portugal's national holidays for a year (and one city's), as {date: name}."""
    e = easter(year)
    out = {
        dt.date(year, 1, 1): "New Year's Day",
        e - dt.timedelta(days=2): "Good Friday",
        e: "Easter",
        dt.date(year, 4, 25): "Freedom Day",
        dt.date(year, 5, 1): "Labour Day",
        e + dt.timedelta(days=60): "Corpus Christi",
        dt.date(year, 6, 10): "Portugal Day",
        dt.date(year, 8, 15): "Assumption Day",
        dt.date(year, 10, 5): "Republic Day",
        dt.date(year, 11, 1): "All Saints' Day",
        dt.date(year, 12, 1): "Restoration of Independence",
        dt.date(year, 12, 8): "Immaculate Conception",
        dt.date(year, 12, 25): "Christmas Day",
    }
    if municipal in MUNICIPAL:
        (mo, d), name = MUNICIPAL[municipal]
        out.setdefault(dt.date(year, mo, d), name)
    return out


# ------------------------------------------------------------------ events
def secret_url():
    try:
        return (json.loads(SECRETS.read_text()).get("calendar") or {}).get("ical", "")
    except (OSError, ValueError):
        return ""


def set_url(url):
    SECRETS.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = json.loads(SECRETS.read_text())
    except (OSError, ValueError):
        data = {}
    data.setdefault("calendar", {})["ical"] = url.strip()
    fd = os.open(SECRETS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(SECRETS, 0o600)


def _when(v):
    """An event boundary as (ISO string in local time, all-day?)."""
    if isinstance(v, dt.datetime):
        if v.tzinfo is None:
            v = v.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
        return v.astimezone().isoformat(timespec="minutes"), False
    return v.isoformat(), True


def events_from_ics(data, start, end):
    """The events of an iCalendar (bytes) between two dates, recurring ones expanded, sorted by start."""
    import icalendar
    import recurring_ical_events
    cal = icalendar.Calendar.from_ical(data)
    name = str(cal.get("X-WR-CALNAME", "") or "")
    out = []
    for ev in recurring_ical_events.of(cal).between(start, end):
        s = ev.get("DTSTART")
        if s is None:
            continue
        e = ev.get("DTEND")
        s_iso, all_day = _when(s.dt)
        if e is not None:
            e_iso, _ = _when(e.dt)
        elif all_day:
            e_iso = (s.dt + dt.timedelta(days=1)).isoformat()
        else:
            e_iso = s_iso
        out.append({
            "title": str(ev.get("SUMMARY", "") or "(no title)"),
            "start": s_iso,
            "end": e_iso,
            "allDay": all_day,
            "location": str(ev.get("LOCATION", "") or ""),
            "calendar": name,
        })
    out.sort(key=lambda x: (x["start"], x["title"]))
    return out


def fetch():
    cfg = util.settings().get("calendar") or {}
    today = dt.date.today()
    start, end = today - dt.timedelta(days=BACK), today + dt.timedelta(days=AHEAD)
    hol = {}
    if (cfg.get("holidays") or "pt") == "pt":       # whole years: the month grid can go back and forth
        for y in range(today.year - 1, today.year + 2):
            for d, n in holidays(y, cfg.get("municipal", "lisbon")).items():
                hol[d.isoformat()] = n
    out = {"updated": int(time.time()), "from": start.isoformat(), "to": end.isoformat(),
           "holidays": hol, "events": [], "source": "none", "error": ""}
    url = secret_url()
    if url:
        out["source"] = "ical"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "atom-plasma-calendar"})
            with urllib.request.urlopen(req, timeout=15) as r:
                out["events"] = events_from_ics(r.read(), start, end)
        except ImportError:
            out["error"] = "python-icalendar / python-recurring-ical-events are missing"
        except Exception as e:      # a bad address or a network hiccup: keep the last good events
            out["error"] = f"{type(e).__name__}: {e}"[:200]
            try:
                old = json.loads(OUT.read_text())
                out["events"] = old.get("events", [])
            except (OSError, ValueError):
                pass
    return out


def write(data):
    CACHE.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CACHE, prefix=".calendar-", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, OUT)        # replaced, not rewritten: WatchedJson sees replacements


def main():
    args = sys.argv[1:]
    if args[:1] == ["set-url"]:
        set_url(args[1] if len(args) > 1 else "")
        args = ["--force"]
    if args[:1] == ["status"]:
        try:
            d = json.loads(OUT.read_text())
        except (OSError, ValueError):
            d = {}
        print(json.dumps({"address": "set" if secret_url() else "none", "events": len(d.get("events", [])),
                          "holidays": len(d.get("holidays", {})), "updated": d.get("updated"),
                          "error": d.get("error", "")}))
        return
    force = "--force" in args
    CACHE.mkdir(parents=True, exist_ok=True)
    with open(CACHE / "calendar.lock", "w") as lock:      # several clocks ask at once: one fetch
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            fresh = time.time() - json.loads(OUT.read_text()).get("updated", 0) < MAX_AGE
        except (OSError, ValueError):
            fresh = False
        if force or not fresh:
            write(fetch())
    print(OUT.read_text())


if __name__ == "__main__":
    main()
