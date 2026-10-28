"""Make the desktop match the screens plugged in now: every screen gets the whole rice, whatever is connected.

Run after any change of screens (atom-displayd, `rice.py screens-changed`), safe to run any time:
  1. wallpapers  a screen showing no wallpaper of ours (Plasma's default, or none) mirrors the main screen's
                 (the user's rule: a new screen starts as a copy of the main one)
  2. desks       one com.zinoxx.desk applet on every screen's desktop (clock, status, music, Clawd)
  3. bars        a rice bar on every screen (main template on Plasma screen 0, secondary elsewhere), each as
                 thick as its screen's UI size asks (atom/panel.py ensure_bars)
  4. tiling      a screen Krohnkite hasn't had this session gets its layout (floating unless set to tile)
  5. palettes    each screen's palette, bar islands, clock size, window borders (screens.apply_screens)
  6. tidy        state for connectors that aren't there any more (palette files, glass bands, border sections)
"""
import json
import subprocess
from pathlib import Path

from . import displays, kde, kwin, panel, screens, tiling, util
from .util import CACHE, HOME, STATE

DESK = "com.zinoxx.desk"
DESK_PX = 54



def is_ours(img):
    """A wallpaper the user chose (anything but nothing or Plasma's stock ones)."""
    return bool(img) and not str(img).startswith("/usr/share/wallpapers/")


def ensure_wallpapers(ss):
    """Screens without a wallpaper of ours get the main screen's. Returns the screens changed."""
    main = next((s for s in ss if s["main"] and is_ours(s["image"])), None) \
        or next((s for s in ss if is_ours(s["image"])), None)
    if not main:
        return []
    fresh = [s for s in ss if not is_ours(s["image"])]
    if fresh:
        screens.set_images(fresh, Path(main["image"]))
        for s in fresh:
            s["image"] = main["image"]
        util.log("new screens %s mirror %s's wallpaper", ", ".join(s["name"] for s in fresh), main["name"])
    return fresh


def ensure_desks():
    try:
        return json.loads(panel.shell(util.script("desks", desk=DESK, px=DESK_PX)) or "[]")
    except (subprocess.CalledProcessError, ValueError):
        return []


def tidy(ss):
    """Per-connector state of screens that aren't plugged in: their palette files (the widgets of a screen
    that comes back read a fresh one), glass bands and border colour sections."""
    here = {s["name"] for s in ss}
    if not here:
        return
    for f in STATE.glob("palette-*.json"):
        if f.stem.removeprefix("palette-") not in here:
            f.unlink(missing_ok=True)
    for f in (CACHE / "glass").glob("*.jpg"):
        if f.name.rsplit("-", 1)[0] not in here:
            f.unlink(missing_ok=True)
    have = kde.kde_read(HOME / ".config/kwinrc")
    gone = {g: {k: None for k in keys} for g, keys in have.items()
            if len(g) == 2 and g[0] == "Round-Corners" and g[1].startswith("Output ") and g[1][7:] not in here}
    if gone:
        kde.kde_set("kwinrc", gone)


def run(palette=None):
    """Everything above, in order. `palette` is the theme's (palette.json): without one (a fresh install
    that hasn't themed yet) the palettes step waits for the first wallpaper pick."""
    util.hold_lock()
    cfg = util.settings()
    ss = screens.screens(cfg)
    if not ss:
        util.warn("reconcile: no screens mapped (is plasmashell running?)")
        return
    ensure_wallpapers(ss)
    added = ensure_desks()
    if added:
        util.log("desk applets added to desktops %s", added)
    try:
        made = panel.ensure_bars(ss, cfg)
        if made:
            util.log("bars made for new screens: %s", made)
    except (subprocess.CalledProcessError, ValueError) as e:
        util.warn("bars: %s", e)
    tiling.apply_new(displays.probe())
    p = palette or util.load_json(STATE / "palette.json")
    if p:
        screens.apply_screens(ss, cfg, p)
        kwin.apply_kwin(p)
    tidy(ss)
