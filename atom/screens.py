"""The screens: which output each Plasma desktop is on, their wallpapers, and everything drawn per screen
from its own palette (palette-<output>.json: the glass band and rim for Glimpse, the desk's layout, which
screen carries the music card and Clawd, each bar's islands and clock size)."""
import hashlib
import json
import subprocess
from pathlib import Path

from . import displays, layout, migrate, palette, panel, presets, util
from .util import CACHE, STATE
from .walls import palette_for, with_meta






def outputs():
    """The enabled displays (atom/displays.py), left to right."""
    return displays.probe()


MATCH = 3      # px: kscreen-doctor and plasmashell can round a fractional-scale position differently


def screens(cfg=None):
    """Screens left to right: display id, connector (`name`), label, Plasma screen index (0 = main bar),
    logical place and size, desktop containment ids, the current wallpaper (path, "" if not an image file),
    the rice's UI size there (`ui`) and the display's details (`display`)."""
    cfg = util.settings() if cfg is None else cfg
    ds = outputs()
    try:
        desks = json.loads(panel.shell(util.script("desktops")))
    except (subprocess.CalledProcessError, ValueError):
        return []
    found = {}
    for d in desks:
        # the display at this desktop's place; mirrored outputs share one, and Plasma shows one desktop there
        near = [o for o in ds if not o.mirror and abs(o.x - d["x"]) <= MATCH and abs(o.y - d["y"]) <= MATCH]
        if not near:
            util.warn("desktop %s on Plasma screen %s at %s,%s matches no output (%s)", d["id"], d["screen"],
                      d["x"], d["y"], ", ".join(f"{o.connector}@{o.x:g},{o.y:g}" for o in ds))
            continue
        o = min(near, key=lambda o: abs(o.x - d["x"]) + abs(o.y - d["y"]))
        s = found.setdefault(o.connector, dict(
            id=o.id, name=o.connector, label=o.label, screen=d["screen"], x=d["x"], y=d["y"],
            w=round(o.w), h=round(o.h), main=d["screen"] == 0, desktops=[], image="",
            ui=displays.ui_scale(o, cfg), comfort=displays.comfort(o),
            display=dict(o.to_json(), sharedEdges=sorted(displays.shared_edges(o, ds)))))
        s["desktops"].append(d["id"])
        img = d["image"].removeprefix("file://")
        if not s["image"] and img and Path(img).is_file():
            s["image"] = img
    out = sorted(found.values(), key=lambda s: s["x"])
    if ds:
        for i, conn in displays.remember(ds).items():
            util.log("display %s moved from %s to %s", i, conn, next(d.connector for d in ds if d.id == i))
        migrate.upgrade(out, ds)
    return out


def set_images(targets, img):
    panel.shell(util.script("set-wallpapers", want={str(d): f"file://{img}" for s in targets for d in s["desktops"]}))


GLASS_BAND = 160   # logical px of the screen top that Glimpse's glass bar can cover


def glass(img, s):
    """The top band of a screen's wallpaper as Plasma shows it (scaled and cropped to the screen),
    blurred and saturated: Glimpse's glass bar shows it aligned with the real desktop (fake backdrop
    blur, so nothing runs on the GPU while the bar sits idle)."""
    w, h = s.get("w"), s.get("h")
    if not img or not w or not h:
        return ""
    d = CACHE / "glass"
    key = hashlib.sha1(f"{img}:{img.stat().st_mtime}:{w}x{h}".encode()).hexdigest()[:10]
    out = d / f"{s['name']}-{key}.jpg"
    if not out.exists():
        d.mkdir(parents=True, exist_ok=True)
        util.run("magick", str(img) + "[0]", "-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}",
                 "-gravity", "north", "-crop", f"{w}x{GLASS_BAND}+0+0", "+repage",
                 "-blur", "0x14", "-modulate", "104,150", "-quality", "90", str(out))
        for old in d.glob(f"{s['name']}-*.jpg"):
            if old != out and old.stem.rsplit("-", 1)[0] == s["name"]:
                old.unlink(missing_ok=True)
    return str(out) if out.exists() else ""


FULL_DIV = 4      # the launcher's backdrop is made at a quarter of the screen: the blur hides the scaling


def glass_full(img, s):
    """The whole screen's wallpaper as Plasma shows it, blurred and a little saturated: the fullscreen
    launcher's backdrop (a static picture, so opening it costs no blur passes). Made small (FULL_DIV) and
    drawn stretched; the blur hides that."""
    w, h = s.get("w"), s.get("h")
    if not img or not w or not h:
        return ""
    d = CACHE / "glass-full"
    key = hashlib.sha1(f"{img}:{img.stat().st_mtime}:{w}x{h}".encode()).hexdigest()[:10]
    out = d / f"{s['name']}-{key}.jpg"
    if not out.exists():
        d.mkdir(parents=True, exist_ok=True)
        sw, sh = max(1, round(w / FULL_DIV)), max(1, round(h / FULL_DIV))
        util.run("magick", str(img) + "[0]", "-resize", f"{sw}x{sh}^", "-gravity", "center", "-extent", f"{sw}x{sh}",
                 "+repage", "-blur", "0x9", "-modulate", "100,135", "-quality", "92", str(out))
        for old in d.glob(f"{s['name']}-*.jpg"):
            if old != out and old.stem.rsplit("-", 1)[0] == s["name"]:
                old.unlink(missing_ok=True)
    return str(out) if out.exists() else ""


def wall_fit(img, s):
    """The screen's wallpaper scaled and cropped to exact device pixels (matching Plasma's desktop fit),
    stripped and saved as a fast-decoding JPEG: sharp backdrops (noise, none) decode this in milliseconds
    instead of resizing a 10+ MB original every time."""
    w, h = s.get("w"), s.get("h")
    if not img or not w or not h:
        return ""
    scale = float((s.get("display") or {}).get("scale", 1.0) or 1.0)
    pw, ph = max(1, round(w * scale)), max(1, round(h * scale))
    d = CACHE / "wall-fit"
    key = hashlib.sha1(f"{img}:{img.stat().st_mtime}:{pw}x{ph}".encode()).hexdigest()[:10]
    out = d / f"{s['name']}-{key}.jpg"
    if not out.exists():
        d.mkdir(parents=True, exist_ok=True)
        util.run("magick", str(img) + "[0]", "-resize", f"{pw}x{ph}^", "-gravity", "center", "-extent", f"{pw}x{ph}",
                 "+repage", "-strip", "-quality", "92", str(out))
        for old in d.glob(f"{s['name']}-*.jpg"):
            if old != out and old.stem.rsplit("-", 1)[0] == s["name"]:
                old.unlink(missing_ok=True)
    return str(out) if out.exists() else ""


RIM_STOPS = 12


def rim(glass_img, p):
    """The top band's glow line, left to right: the colour of the wallpaper under each stretch of
    the top edge (the glass strip, so aligned with the real desktop), lit up to read as light
    (bright, saturated) and pulled a little toward the primary so it stays one family. Greys take
    the primary's hue. Glimpse draws it as gradient stops along its rim."""
    if not glass_img:
        return []
    from PIL import Image
    try:
        cols = Image.open(glass_img).convert("RGB").resize((RIM_STOPS, 1), Image.BOX)
    except OSError:
        return []
    _, _, ph = palette.to_oklch(p["primary"])
    mood = p.get("_mood", "soft")
    out = []
    for i in range(RIM_STOPS):
        L, C, H = palette.to_oklch("#%02x%02x%02x" % cols.getpixel((i, 0)))
        if mood == "light":     # graphite, which reads on the black strip and on the white frost
            out.append(palette.oklch(0.60, 0.006, 255) if C < 0.03 else
                       palette.oklch(0.62, min(0.14, max(0.08, C * 1.6)), palette.hue_toward(H, ph, 0.25)))
            continue
        if mood in ("void", "graphite"):
            out.append(palette.oklch(min(0.92, max(0.80, L + 0.3)), 0.008, 255))   # starlight / silver
            continue
        H = palette.hue_toward(ph if C < 0.03 else H, ph, 0.25)
        lo, hi = (0.16, 0.26) if mood == "neon" else (0.1, 0.19)
        out.append(palette.oklch(min(0.86, max(0.70, L + 0.25)), min(hi, max(lo, C * 2.0)), H))
    return out


def desk_layout(img, s):
    """Where the desktop widgets sit on this screen's wallpaper (layout.py), cached per image and size."""
    w, h = s.get("w"), s.get("h")
    if not img or not w or not h:
        return None
    key = hashlib.sha1(f"{img}:{img.stat().st_mtime}:{w}x{h}:{layout.VERSION}".encode()).hexdigest()[:16]
    f = CACHE / "layout" / f"{key}.json"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        pass
    L = layout.place(img, w, h)
    L.pop("_cost", None)
    util.write_if_changed(f, json.dumps(L))
    return L


def media_screen(ss, cfg):
    """The screen whose clock carries the music card and Clawd (its connector): settings desk_media (a display
    id, or a connector) while it's plugged in;
    else the only screen; else one beside the main bar's screen (with two, the other one; with more, the
    biggest of those touching it)."""
    want = cfg.get("desk_media")
    chosen = next((s for s in ss if want and want in (s.get("id"), s["name"])), None)
    if chosen:
        return chosen["name"]
    if not ss:
        return ""
    area = lambda s: (s.get("w") or 0) * (s.get("h") or 0)
    main = next((s for s in ss if s["main"]), None)
    others = [s for s in ss if s is not main]
    if not main or not others:
        return max(ss, key=area)["name"]

    def gap(s):
        dx = max(s["x"] - (main["x"] + main["w"]), main["x"] - (s["x"] + s["w"]), 0)
        dy = max(s["y"] - (main["y"] + main["h"]), main["y"] - (s["y"] + s["h"]), 0)
        return max(dx, dy)
    near = [s for s in others if gap(s) <= 2] or [min(others, key=gap)]     # positions are rounded
    return max(near, key=area)["name"]


TOP_SIZE = 1.05    # the top bar's own size on each screen's standard size (settings top.size)
TOP_RANGE = (0.6, 2.0)


def top_size(cfg):
    """The top bar's own size (Glimpse's strip and the shelf it opens; the Theme page's "Top bar size"): times
    each screen's standard size, apart from the taskbar's size (ui)."""
    try:
        v = float((cfg.get("top") or {}).get("size", TOP_SIZE))
    except (TypeError, ValueError):
        return TOP_SIZE
    return round(min(TOP_RANGE[1], max(TOP_RANGE[0], v)), 2)


def top_scale(s, cfg):
    """The top bar's scale on screen s (palette _topScale), from s's standard size (`comfort`). Settings from
    before it had a size of its own (ui.top: a ratio to the taskbar's size) keep that until migrate.py moves
    them to top.size."""
    ui = cfg.get("ui") or {}
    if "top" in ui:
        return round(s["ui"] * float(ui["top"]), 2)
    return round(s.get("comfort", 1.0) * top_size(cfg), 2)


def retop(cfg=None):
    """Only the top bar's size in every screen's palette (`rice.py top size`): Glimpse and the desk read their
    palette live, so nothing else has to run. Each palette carries its screen's standard size (_standard)."""
    cfg = util.settings() if cfg is None else cfg
    changed = 0
    for f in sorted(STATE.glob("palette-*.json")):
        p = util.load_json(f)
        if not isinstance(p, dict) or "_standard" not in p:
            continue
        t = top_scale({"ui": p.get("_scale", 1.0), "comfort": p["_standard"]}, cfg)
        if p.get("_topScale") != t:
            changed += util.write_if_changed(f, json.dumps(dict(p, _topScale=t), indent=2) + "\n")
    return changed


CLOCK_PT = 11      # the bar clock's points at UI size 1 (settings ui.clock_pt)


def clock_pt(s, cfg):
    return round(float((cfg.get("ui") or {}).get("clock_pt", CLOCK_PT)) * s["ui"])


def size_clocks(bars, by_screen, cfg):
    """Each bar's clock in its screen's size (ui.clock_pt x that screen's UI size): a bar moves to another
    screen when screens are unplugged (the main bar always sits on screen 0)."""
    want = {str(b["panel"]): clock_pt(by_screen[b["screen"]], cfg) for b in bars if b["screen"] in by_screen}
    if want:
        try:
            panel.shell(util.script("clock-sizes", want=want))
        except subprocess.CalledProcessError:
            pass


def screen_palette(s, img, cfg, overrides=None, fallback=None, desk=None):
    """Screen s's palette with its wallpaper `img` (a Path, or None: `fallback`): the theme engine's colours
    plus what its widgets read (the glass and frost, the text zones' measures, its sizes, the desk's layout,
    the docked bar's floor). `desk`: {media, clawd, theme} for the desk widgets."""
    p = with_meta(palette_for(img, cfg, overrides), img) if img else fallback
    g = glass(img, s)
    gf = glass_full(img, s)
    wf = wall_fit(img, s)
    return dict(p, _glass=g, _glassBand=GLASS_BAND, _rim=rim(g, p), _glassFull=gf, _wallFit=wf,
                _backdrop=palette.zone_light(gf) if gf else {},             # how bright the launcher's backdrop gets under its text
                _backdropSharp=palette.zone_light(img, aspect=s["w"] / s["h"]) if s.get("w") and s.get("h") else {},  # (no blur: the wallpaper itself)
                _scale=s["ui"],                                             # size of that bar's widgets
                _standard=s.get("comfort", 1.0),                            # the screen's standard size (the launcher's base)
                _topScale=top_scale(s, cfg),                                # size of the top bar (Glimpse's band)
                _display={k: s["display"][k] for k in ("id", "name", "label", "portrait", "sharedEdges", "scale")},
                _layout=desk_layout(img, s),                                # the desktop widgets' places (com.zinoxx.desk)
                _desk=desk or {"media": False, "clawd": False, "theme": ""},
                _floor=panel.floor(p))                                      # the docked bar's floor (Atom FloorWindow)


def apply_screens(ss, cfg, fallback):
    """Each screen's palette (with its overrides), for the widgets on its bar, and its bar's island colours."""
    from . import modules
    pals = {}
    ovs = presets.overrides()
    music = media_screen(ss, cfg)
    theme_name = presets.current_theme(ss, ovs)
    clawd_on = modules.is_enabled("claude", cfg) and bool(modules.module_config("claude", cfg).get("clawd_desk", True))
    for s in ss:
        img = Path(s["image"]) if s["image"] else None
        p = screen_palette(s, img, cfg, ovs.get(s["id"]), fallback,
                           {"media": s["name"] == music, "clawd": (s["name"] == music) and clawd_on, "theme": theme_name})
        util.write_if_changed(STATE / f"palette-{s['name']}.json", json.dumps(p, indent=2) + "\n")
        pals[s["screen"]] = p
    try:
        bars = panel.panels()
    except (subprocess.CalledProcessError, ValueError):
        return
    size_clocks(bars, {s["screen"]: s for s in ss}, cfg)
    restyle_bars(bars, pals)


def restyle_bars(bars=None, pals=None):
    """Every bar's islands in their screen's palette (pals: Plasma screen index -> palette; default: the
    palettes already written), applied where they changed. `rice.py bar style` runs only this."""
    if bars is None:
        try:
            bars = panel.panels()
        except (subprocess.CalledProcessError, ValueError):
            return
    if pals is None:
        pals = {}
        for s in screens():
            p = util.load_json(STATE / f"palette-{s['name']}.json")
            if p:
                pals[s["screen"]] = p
    for bar in bars:
        if bar["screen"] not in pals:
            continue
        p = pals[bar["screen"]]
        try:    # one bar that can't be styled (Colorizer changed, say) must not stop the rest of the theme
            looks = panel.bar_looks(p, bar)     # (free, docked)
        except Exception as e:
            util.warn("bar %s: islands not restyled: %s", bar["panel"], e)
            continue
        # only bars whose islands change: each apply runs in plasmashell and restyles the whole bar
        # (a pick on one screen leaves the other two bars as they are)
        seen = CACHE / "colorizer" / f"{bar['panel']}-{bar['colorizer']}.sha1"
        key = hashlib.sha1(json.dumps([looks, panel.DOCK_MS], sort_keys=True).encode()).hexdigest()
        try:
            if seen.read_text() == key:
                continue
        except OSError:
            pass
        # the free look now, and both as presets Colorizer switches between when a window touches the bar
        config = {"presetAutoloading": panel.dock_presets(bar, looks, key),
                  "animatePropertyChanges": True, "animationDuration": panel.DOCK_MS}
        if panel.colorizer_apply(bar, looks[0], config):
            util.write_if_changed(seen, key)
        else:
            util.warn("bar %s: Colorizer didn't take the new islands", bar["panel"])
