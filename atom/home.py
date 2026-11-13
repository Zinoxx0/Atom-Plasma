"""The launcher's own data (com.zinoxx.launcher, "Atom Home"), what Kicker's models don't carry:

  games   Steam's art for the installed games (the library cache: cover, hero banner, logo, header), keyed
          by the desktop file Steam made for each game (Exec ... steam://rungameid/<appid>)
  usage   when each app was last used and how much (KActivities' score cache, what Kicker's recents read),
          keyed by desktop file id

`rice.py launcher-data` writes it to ~/.cache/rice/launcher.json (atomically, only when it changed): the
launcher runs it as it opens and reads the file live (WatchedJson). Nothing here is slow: a directory walk
of the games' art and one read-only query."""
import json
import os
import re
import sqlite3
import time
from pathlib import Path

from . import util

HOME = Path.home()
STEAM_CACHE = HOME / ".local/share/Steam/appcache/librarycache"
ACTIVITY_DB = HOME / ".local/share/kactivitymanagerd/resources/database"
OUT = util.CACHE / "launcher.json"

# the art's file names, best first: newer games keep them in hashed subfolders, older ones flat
ART = {"portrait": ("library_600x900.jpg", "library_capsule.jpg"), "hero": ("library_hero.jpg",),
       "logo": ("logo.png",), "header": ("library_header.jpg", "header.jpg")}


def app_dirs():
    """Where desktop files live, the user's first (XDG_DATA_HOME, then XDG_DATA_DIRS)."""
    data_home = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
    dirs = [data_home / "applications"]
    for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(Path(d) / "applications")
    return [d for d in dirs if d.is_dir()]


def steam_games(dirs=None):
    """desktop id -> Steam appid, for the desktop files Steam made (their Exec runs steam://rungameid/N)."""
    out = {}
    for d in dirs if dirs is not None else app_dirs():
        for f in sorted(d.rglob("*.desktop")):
            did = str(f.relative_to(d)).replace("/", "-")
            if did in out:
                continue
            try:
                m = re.search(r"^Exec=.*steam://rungameid/(\d+)", f.read_text(errors="replace"), re.M)
            except OSError:
                continue
            if m:
                out[did] = m.group(1)
    return out


def art(appid, cache=STEAM_CACHE):
    """A game's art in Steam's library cache: role -> file path ("" roles left out)."""
    root = Path(cache) / str(appid)
    if not root.is_dir():
        return {}
    files = {}
    for f in sorted(root.rglob("*")):
        if f.is_file():
            files.setdefault(f.name, f)
    out = {}
    for role, names in ART.items():
        found = next((files[n] for n in names if n in files), None)
        if found:
            out[role] = str(found)
    return out


def usage(db=ACTIVITY_DB):
    """desktop id -> {"last": unix time, "score": KActivities' score}, every activity together."""
    out = {}
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = c.execute("select targettedResource, cachedScore, lastUpdate from ResourceScoreCache "
                         "where targettedResource like 'applications:%'").fetchall()
    except sqlite3.Error:
        return out
    for res, score, last in rows:
        did = res[len("applications:"):]
        old = out.get(did, {"last": 0, "score": 0.0})
        out[did] = {"last": max(old["last"], int(last or 0)), "score": round(old["score"] + float(score or 0), 2)}
    return out


def build(dirs=None, cache=STEAM_CACHE, db=ACTIVITY_DB):
    games = {}
    for did, appid in steam_games(dirs).items():
        a = art(appid, cache)
        games[did] = dict(a, appid=appid)
    return {"games": games, "usage": usage(db)}


def write():
    """`rice.py launcher-data`: write the file if anything changed; says where it is."""
    data = build()
    changed = util.write_if_changed(OUT, json.dumps(dict(data, version=1), sort_keys=True, indent=1))
    if changed:
        # the time of the last change rides along without making every run a change
        meta = OUT.with_name("launcher.updated")
        meta.write_text(str(int(time.time())))
    return str(OUT)
