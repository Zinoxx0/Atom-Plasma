"""Themes (presets): every screen's wallpaper, the screen that drives the theme and the hand-picked colours
under a short name; and the hand-picked colours themselves (overrides), per display.

Everything here is keyed by display id (atom/displays.py: the monitor's EDID identity), not by connector, so
a monitor keeps its colours and its place in a theme when it moves to another port.

A theme remembers the screens it was saved on (`layout`: id, name, label, place and size, main, image,
hand-picked colours). Loaded on another set of screens, plan() maps it:
  1. same monitor            -> its own wallpaper (and colours)
  2. by role                 -> the theme's main screen to the main screen now, then the theme's other
                                screens to the remaining ones, left to right
  3. screens still left over -> the main screen's wallpaper (a new screen mirrors the main one; the user
                                changes it from there)
"""
import json
import sys
from pathlib import Path

from . import displays, util
from .util import STATE
from .walls import CURRENT

PRESETS = STATE / "presets.json"
OVERRIDES = STATE / "overrides.json"    # {display id: {mood, primary, secondary, tertiary, intensity}}
LEAD = STATE / "theme-screen"           # the display id whose wallpaper drives the global theme
FORMAT = 2                              # presets.json entries: 1 = {screens: {connector: image}}, 2 = layout

PRESET_LEN = 10     # names stay short: they're chips in the picker


def presets():
    try:
        return json.loads(PRESETS.read_text())
    except (OSError, ValueError):
        return []


def save_presets(ps):
    util.write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")


def preset_name(name):
    name = " ".join(str(name).split())[:PRESET_LEN]
    if not name:
        sys.exit("a preset needs a name")
    return name


def find_preset(ps, name):
    return next((p for p in ps if p["name"].lower() == name.lower()), None)


def current_wallpaper():
    try:
        return str(CURRENT.resolve(strict=True))
    except OSError:
        return ""


def preset_save(name, ss):
    """Every screen as it is now (wallpaper, place, hand-picked colours) and the one driving the global
    theme; a preset with the same name (any case) is replaced in place, keeping its entries for monitors
    that aren't plugged in now."""
    name = preset_name(name)
    shown = [s for s in ss if s["image"]]
    if not shown:
        sys.exit("no wallpapers to save")
    ovs, lead = overrides(), lead_screen(ss)
    layout = []
    for s in shown:
        e = {k: s.get(k) for k in ("id", "name", "label", "x", "y", "w", "h", "main", "image")}
        e["name"] = s.get("display", {}).get("name") or s["name"]      # the monitor's name, not the connector
        if ovs.get(s["id"]):
            e["overrides"] = ovs[s["id"]]
        layout.append(e)
    theme = current_wallpaper()
    lead_entry = next((e for e in layout if e["id"] == lead), None)
    entry = {"name": name, "format": FORMAT, "layout": layout,
             "theme": theme if any(e["image"] == theme for e in layout) else layout[0]["image"]}
    entry["lead"] = lead if lead_entry and lead_entry["image"] == entry["theme"] else \
        next(e["id"] for e in layout if e["image"] == entry["theme"])
    ps = presets()
    old = find_preset(ps, name)
    if old:
        # saved again on fewer screens: the monitors that aren't plugged in keep what the theme had for them
        here = {e["id"] for e in layout}
        entry["layout"] += [e for e in old.get("layout", []) if e.get("id") not in here]
        ps[ps.index(old)] = entry
    else:
        ps.append(entry)
    save_presets(ps)
    print(name)


def preset_delete(name):
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps.remove(old)
        save_presets(ps)


def plan(p, ss):
    """Where a theme's wallpapers go on the screens now: {screen id: {image, overrides, from (theme screen
    id), how ("same" | "role" | "mirror")}}. See the module docstring for the rules."""
    layout = [e for e in p.get("layout", []) if e.get("image")]
    if not layout or not ss:
        return {}
    out, used = {}, set()
    for s in ss:                                                # 1. the same monitor
        e = next((e for e in layout if e["id"] == s["id"]), None)
        if e:
            out[s["id"]] = dict(image=e["image"], overrides=e.get("overrides") or {}, how="same", **{"from": e["id"]})
            used.add(e["id"])
    left = [s for s in ss if s["id"] not in out]                # 2. by role: main first, then left to right
    spare = sorted((e for e in layout if e["id"] not in used), key=lambda e: (not e.get("main"), e.get("x", 0)))
    for s in sorted(left, key=lambda s: (not s.get("main"), s.get("x", 0))):
        if not spare:
            break
        e = spare.pop(0)
        out[s["id"]] = dict(image=e["image"], overrides=e.get("overrides") or {}, how="role", **{"from": e["id"]})
    main = next((s for s in ss if s.get("main")), ss[0])        # 3. the rest mirror the main screen
    src = out.get(main["id"]) or next(iter(out.values()), None) \
        or dict(image=layout[0]["image"], overrides=layout[0].get("overrides") or {}, **{"from": layout[0]["id"]})
    for s in ss:
        if s["id"] not in out:
            out[s["id"]] = dict(image=src["image"], overrides=src["overrides"], how="mirror", **{"from": src["from"]})
    return out


def current_theme(ss, ovs):
    """The saved theme the screens show right now (what plan() would put on them, the same hand-picked colours,
    the same wallpaper driving the theme), or ""."""
    cur = current_wallpaper()
    for p in presets():
        want = plan(p, ss)
        if want and p.get("theme") == cur and all(
                s["image"] == want[s["id"]]["image"] and (ovs.get(s["id"]) or {}) == want[s["id"]]["overrides"]
                for s in ss if s["id"] in want):
            return p["name"]
    return ""


def overrides():
    try:
        return json.loads(OVERRIDES.read_text())
    except (OSError, ValueError):
        return {}


def save_overrides(ovs):
    util.write_if_changed(OVERRIDES, json.dumps({o: v for o, v in ovs.items() if v}, indent=2) + "\n")


def set_lead(display_id):
    util.write_if_changed(LEAD, display_id + "\n")


def lead_screen(ss):
    """The display id whose wallpaper drives the global theme: the last one picked on; if that monitor isn't
    plugged in, the screen showing the theme's wallpaper, else the main screen."""
    ids = [s["id"] for s in ss]
    try:
        lead = LEAD.read_text().strip()
    except OSError:
        lead = ""
    if lead in ids:
        return lead
    cur = current_wallpaper()
    showing = next((s["id"] for s in ss if s["image"] and str(Path(s["image"]).resolve()) == cur), "")
    return showing or next((s["id"] for s in ss if s.get("main")), ids[0] if ids else "")


# ---------------------------------------------------------------------------------------------- migration
def migrate(ss, ds, reg=None):
    """Connector-keyed state from before display ids (2026-10-28) -> display ids: overrides, the lead screen,
    presets (format 1 -> 2). A connector nothing knows any more becomes "conn:<name>". Safe to re-run."""
    reg = displays.registry() if reg is None else reg
    ids = {s["id"] for s in ss} | set(reg)

    def to_id(key):
        if key in ids or key.startswith("conn:"):
            return key
        return displays.id_for(key, ds, reg) or "conn:" + key

    ovs = overrides()
    new = {to_id(k): v for k, v in ovs.items()}
    if new != ovs:
        save_overrides(new)
    try:
        lead = LEAD.read_text().strip()
    except OSError:
        lead = ""
    if lead and to_id(lead) != lead:
        set_lead(to_id(lead))

    ps, changed = presets(), False
    here = {s["id"]: s for s in ss}
    for n, p in enumerate(ps):
        if p.get("format", 1) >= FORMAT:
            continue
        layout = []
        for conn, img in (p.get("screens") or {}).items():
            i = to_id(conn)
            s, r = here.get(i, {}), reg.get(i) or {}
            e = {"id": i, "name": r.get("name") or s.get("display", {}).get("name") or conn,
                 "label": r.get("label") or s.get("label") or conn,
                 "x": s.get("x", len(layout) * 2000), "y": s.get("y", 0), "w": s.get("w", 1920), "h": s.get("h", 1080),
                 "main": bool(s.get("main")), "image": img}
            if (p.get("overrides") or {}).get(conn):
                e["overrides"] = p["overrides"][conn]
            layout.append(e)
        if not layout:
            continue
        if not any(e["main"] for e in layout):
            layout[0]["main"] = True
        lead = to_id(p["lead"]) if p.get("lead") else next((e["id"] for e in layout if e["image"] == p.get("theme")), "")
        theme = next((e["image"] for e in layout if e["id"] == lead), layout[0]["image"])
        ps[n] = {"name": p["name"], "format": FORMAT, "layout": layout, "lead": lead or layout[0]["id"], "theme": theme}
        changed = True
    if changed:
        save_presets(ps)
