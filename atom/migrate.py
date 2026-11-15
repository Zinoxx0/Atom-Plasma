"""Upgrades of the rice's saved state, run once each (~/.local/state/rice/state-version).

2 (2026-10-28): per-screen state keyed by display id instead of connector: hand-picked colours, the
  screen driving the theme, presets (format 2, with the layout they were saved on), the keyboards' followed
  screens; settings.json moves from hand-tuned sizes per connector (bar_scale, clock_size, top_scale) to the
  size model (ui: auto, size, top) and desk_media to a display id.
3 (2026-11-15): the top bar gets a size of its own (top.size, on each screen's standard size, like the
  launcher's) instead of following the taskbar's (ui.size x ui.top); it keeps its size on the main screen.
  blur.style is now backdrop.style.
"""
from . import displays, presets, util
from .util import STATE

VERSION_FILE = STATE / "state-version"
VERSION = 3


def version():
    try:
        return int(VERSION_FILE.read_text().strip())
    except (OSError, ValueError):
        return 1


def upgrade(ss, ds):
    """Bring the saved state up to VERSION (no-op when it's there)."""
    v = version()
    if v >= VERSION:
        return
    if v < 2:
        reg = displays.registry()
        presets.migrate(ss, ds, reg)
        settings_v2(ds, reg)
        rgb_v2(ds, reg)
    if v < 3:
        settings_v3(ss)
    util.write_if_changed(VERSION_FILE, f"{VERSION}\n")
    util.log("state upgraded to version %d", VERSION)


def settings_v2(ds, reg):
    cfg = util.user_settings()
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
    util.save_settings({"version": 2, **{k: v for k, v in cfg.items() if k != "version"}})


def settings_v3(ss):
    """ui.top (the top bar's size as a ratio to the taskbar's) -> top.size (x each screen's standard size),
    chosen so the main screen's top bar keeps its size, on the Theme page's 0.05 steps; blur.style ->
    backdrop.style (the Theme page's "Backdrop style")."""
    cfg = util.user_settings()
    changed = False
    ui = cfg.get("ui")
    if isinstance(ui, dict) and "top" in ui:
        ratio = float(ui.pop("top"))
        if "size" not in (cfg.get("top") or {}):
            main = next((s for s in ss if s.get("main")), ss[0] if ss else None)
            if main:
                was, standard = main["ui"] * ratio, main.get("comfort") or 1.0
            else:       # (no screen known: as on a screen of standard size 1)
                was, standard = float(ui.get("size", 1.0)) * ratio, 1.0
            size = round(min(1.8, max(0.8, round(was / standard / 0.05) * 0.05)), 2)
            cfg["top"] = dict(cfg.get("top") or {}, size=size)
        changed = True
    if "blur" in cfg:
        old = cfg.pop("blur")
        if isinstance(old, dict) and "style" in old and "style" not in (cfg.get("backdrop") or {}):
            cfg["backdrop"] = dict(cfg.get("backdrop") or {}, style=old["style"])
        changed = True
    if changed:
        util.save_settings(cfg)


def rgb_v2(ds, reg):
    f = STATE / "rgb.json"
    cfg = util.load_json(f)
    if not isinstance(cfg, dict):
        return
    for s in cfg.values():
        if isinstance(s, dict) and s.get("follow") not in (None, "lead"):
            s["follow"] = displays.id_for(s["follow"], ds, reg) or s["follow"]
    util.save_json(f, cfg)
