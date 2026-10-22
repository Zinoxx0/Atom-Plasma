"""Themes (presets): every screen's wallpaper, the screen that drives the theme and the hand-picked colours
under a short name; and the hand-picked colours themselves (overrides), per screen."""
import json
import sys
from pathlib import Path

from . import util
from .util import STATE
from .walls import CURRENT

PRESETS = STATE / "presets.json"
OVERRIDES = STATE / "overrides.json"    # {output: {mood, primary, secondary, tertiary, intensity}}
LEAD = STATE / "theme-screen"           # the output whose wallpaper drives the global theme


PRESET_LEN = 10     # names stay short: they're chips in the picker


def presets():
    try:
        return json.loads(PRESETS.read_text())
    except (OSError, ValueError):
        return []


def preset_name(name):
    name = " ".join(str(name).split())[:PRESET_LEN]
    if not name:
        sys.exit("a preset needs a name")
    return name


def find_preset(ps, name):
    return next((p for p in ps if p["name"].lower() == name.lower()), None)


def preset_save(name, ss):
    """The wallpaper of every screen now, and the one driving the global theme; a preset with the
    same name (any case) is replaced in place."""
    name = preset_name(name)
    walls_now = {s["name"]: s["image"] for s in ss if s["image"]}
    if not walls_now:
        sys.exit("no wallpapers to save")
    try:
        theme = str(CURRENT.resolve(strict=True))
    except OSError:
        theme = ""
    entry = {"name": name, "screens": walls_now,
             "theme": theme if theme in walls_now.values() else next(iter(walls_now.values()))}
    ovs = {o: v for o, v in overrides().items() if o in walls_now and v}
    if ovs:
        entry["overrides"] = ovs                # hand-picked colours: a preset is a whole theme
    lead = lead_screen(ss)
    if walls_now.get(lead) == entry["theme"]:
        entry["lead"] = lead
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps[ps.index(old)] = entry
    else:
        ps.append(entry)
    util.write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")
    print(name)


def preset_delete(name):
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps.remove(old)
        util.write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")


def current_theme(ss, ovs):
    """The saved theme the screens show right now (same wallpapers, same hand-picked colours, the same
    screen driving the theme), or ""."""
    try:
        cur = str(CURRENT.resolve(strict=True))
    except OSError:
        cur = ""
    now = {s["name"]: s["image"] for s in ss}
    for p in presets():
        known = [o for o in p["screens"] if o in now]
        if known and all(now[o] == p["screens"][o] for o in known) and p.get("theme") == cur \
                and all((ovs.get(o) or {}) == (p.get("overrides", {}).get(o) or {}) for o in known):
            return p["name"]
    return ""


def overrides():
    try:
        return json.loads(OVERRIDES.read_text())
    except (OSError, ValueError):
        return {}


def save_overrides(ovs):
    util.write_if_changed(OVERRIDES, json.dumps({o: v for o, v in ovs.items() if v}, indent=2) + "\n")


def lead_screen(ss):
    """The screen whose wallpaper drives the global theme: the last one picked on."""
    names = [s["name"] for s in ss]
    try:
        name = LEAD.read_text().strip()
    except OSError:
        name = ""
    if name in names:
        return name
    try:
        cur = str(CURRENT.resolve(strict=True))
    except OSError:
        cur = ""
    return next((s["name"] for s in ss if s["image"] and str(Path(s["image"]).resolve()) == cur), names[0] if names else "")
