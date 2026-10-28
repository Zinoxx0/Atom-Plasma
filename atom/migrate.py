"""Upgrades of the rice's saved state, run once each (~/.local/state/rice/state-version).

2 (2026-10-28): per-screen state keyed by display id instead of connector: hand-picked colours, the
  screen driving the theme, presets (format 2, with the layout they were saved on), the keyboards' followed
  screens; settings.json moves from hand-tuned sizes per connector (bar_scale, clock_size, top_scale) to the
  size model (ui: auto, size, top) and desk_media to a display id.
"""
from . import displays, presets, util
from .util import ROOT, STATE

VERSION_FILE = STATE / "state-version"
VERSION = 2


def version():
    try:
        return int(VERSION_FILE.read_text().strip())
    except (OSError, ValueError):
        return 1


def upgrade(ss, ds):
    """Bring the saved state up to VERSION (no-op when it's there)."""
    if version() >= VERSION:
        return
    reg = displays.registry()
    presets.migrate(ss, ds, reg)
    settings_v2(ds, reg)
    rgb_v2(ds, reg)
    util.write_if_changed(VERSION_FILE, f"{VERSION}\n")
    util.log("state upgraded to version %d (display ids)", VERSION)


def settings_v2(ds, reg):
    f = ROOT / "settings.json"
    cfg = util.load_json(f, {}) or {}
    if cfg.get("version", 1) >= 2:
        return
    old = {k: cfg.pop(k) for k in ("bar_scale", "clock_size", "top_scale") if k in cfg}
    ui = cfg.setdefault("ui", {})
    ui.setdefault("auto", True)
    # the hand-tuned sizes were ~1.2x the standard size on the desk monitors: keep that overall feel
    ui.setdefault("size", 1.2 if old else 1.0)
    ui.setdefault("top", 1.05)
    if cfg.get("desk_media"):
        cfg["desk_media"] = displays.id_for(cfg["desk_media"], ds, reg) or cfg["desk_media"]
    cfg["version"] = 2
    util.save_json(f, {"version": 2, **{k: v for k, v in cfg.items() if k != "version"}})


def rgb_v2(ds, reg):
    f = STATE / "rgb.json"
    cfg = util.load_json(f)
    if not isinstance(cfg, dict):
        return
    for s in cfg.values():
        if isinstance(s, dict) and s.get("follow") not in (None, "lead"):
            s["follow"] = displays.id_for(s["follow"], ds, reg) or s["follow"]
    util.save_json(f, cfg)
