"""The screens: which output each Plasma desktop is on, their wallpapers, and everything drawn per screen
from its own palette (palette-<output>.json: the glass band and rim for Glimpse, the desk's layout, which
screen carries the music card and Clawd, each bar's islands and clock size)."""
import hashlib
import json
import subprocess
from pathlib import Path

from . import layout, palette, panel, presets, util
from .util import CACHE, STATE
from .walls import palette_for, with_meta


DESKTOPS_JS = r"""
var out = [];
desktops().forEach(function (d) {
    // a desktop keeps its screen index while that screen is unplugged, and screenGeometry() answers
    // an index past the last screen with screen 0's place
    if (d.screen < 0 || d.screen >= screenCount) return;
    var g = screenGeometry(d.screen);
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    out.push({id: d.id, screen: d.screen, x: g.x, y: g.y,
              image: d.wallpaperPlugin === "org.kde.image" ? d.readConfig("Image") : ""});
});
print(JSON.stringify(out));
"""


SET_JS = r"""
var want = %s;
desktops().forEach(function (d) {
    var url = want[String(d.id)];
    if (!url) return;
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", url);
});
"""


def outputs():
    """Enabled outputs: [{name, label (Laptop / 4K / 1440p), x, y, w, h}] in logical px."""
    try:
        data = json.loads(util.run("kscreen-doctor", "-j").stdout)
    except ValueError:
        return []
    out = []
    for o in data.get("outputs", []):
        if not o.get("enabled"):
            continue
        mode = next((m for m in o.get("modes", []) if m["id"] == o.get("currentModeId")), o)
        h = mode["size"]["height"]
        label = "Laptop" if o["name"].startswith(("eDP", "LVDS", "DSI")) else "4K" if h == 2160 else f"{h}p"
        scale = o.get("scale") or 1
        out.append({"name": o["name"], "label": label, "x": o["pos"]["x"], "y": o["pos"]["y"],
                    "w": round(mode["size"]["width"] / scale), "h": round(h / scale)})
    return out


MATCH = 3      # px: kscreen-doctor and plasmashell can round a fractional-scale position differently


def screens():
    """Screens left to right: output name, label, Plasma screen index (0 = main bar),
    desktop containment ids and the current wallpaper (path, "" if not an image file)."""
    outs = outputs()
    try:
        desks = json.loads(panel.shell(DESKTOPS_JS))
    except (subprocess.CalledProcessError, ValueError):
        return []
    found = {}
    for d in desks:
        # the output at this desktop's place; mirrored outputs share one, and Plasma shows one desktop there
        near = [o for o in outs if abs(o["x"] - d["x"]) <= MATCH and abs(o["y"] - d["y"]) <= MATCH]
        if not near:
            util.warn("desktop %s on Plasma screen %s at %s,%s matches no output (%s)", d["id"], d["screen"],
                      d["x"], d["y"], ", ".join(f'{o["name"]}@{o["x"]},{o["y"]}' for o in outs))
            continue
        o = min(near, key=lambda o: abs(o["x"] - d["x"]) + abs(o["y"] - d["y"]))
        s = found.setdefault(o["name"], dict(o, screen=d["screen"], x=d["x"], y=d["y"], main=d["screen"] == 0,
                                              desktops=[], image=""))
        s["desktops"].append(d["id"])
        img = d["image"].removeprefix("file://")
        if not s["image"] and img and Path(img).is_file():
            s["image"] = img
    return sorted(found.values(), key=lambda s: s["x"])


def set_images(targets, img):
    panel.shell(SET_JS % json.dumps({str(d): f"file://{img}" for s in targets for d in s["desktops"]}))


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
            if old != out:
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
    """The screen whose clock carries the music card and Clawd: settings desk_media while it's plugged in;
    else the only screen; else one beside the main bar's screen (with two, the other one; with more, the
    biggest of those touching it)."""
    names = [s["name"] for s in ss]
    if cfg.get("desk_media") in names:
        return cfg["desk_media"]
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


def scale_for(setting, output, default=1):
    """A size factor from settings.json: one number for every screen, or {output: factor}."""
    if isinstance(setting, (int, float)):
        return setting
    return (setting or {}).get(output, default)


CLOCK_JS = r"""
var want = %s;
panels().forEach(function (p) {
    var pt = want[String(p.id)];
    if (!pt) return;
    p.widgets("org.kde.plasma.digitalclock").forEach(function (w) {
        w.currentConfigGroup = ["Appearance"];
        if (Number(w.readConfig("fontSize")) !== pt) w.writeConfig("fontSize", pt);
    });
});
"""


def size_clocks(bars, names, cfg):
    """Each bar's clock in its screen's size (settings clock_size, points): a bar moves to another
    screen when screens are unplugged (the main bar always sits on screen 0)."""
    want = {str(b["panel"]): pt for b in bars if (pt := scale_for(cfg.get("clock_size"), names.get(b["screen"]), None))}
    if want:
        try:
            panel.shell(CLOCK_JS % json.dumps(want))
        except subprocess.CalledProcessError:
            pass


def apply_screens(ss, cfg, fallback):
    """Each screen's palette (with its overrides), for the widgets on its bar, and its bar's island colours."""
    pals = {}
    ovs = presets.overrides()
    music = media_screen(ss, cfg)
    theme_name = presets.current_theme(ss, ovs)
    for s in ss:
        img = Path(s["image"]) if s["image"] else None
        p = with_meta(palette_for(img, cfg, ovs.get(s["name"])), img) if img else fallback
        g = glass(img, s)
        p = dict(p, _glass=g, _glassBand=GLASS_BAND, _rim=rim(g, p),
                 _scale=scale_for(cfg.get("bar_scale"), s["name"]),         # size of that bar's widgets
                 _topScale=scale_for(cfg.get("top_scale"), s["name"]),      # size of the Glimpse band up top
                 _layout=desk_layout(img, s),                               # the desktop widgets' places (com.zinoxx.desk)
                 _desk={"media": s["name"] == music, "clawd": s["name"] == music, "theme": theme_name})
        util.write_if_changed(STATE / f"palette-{s['name']}.json", json.dumps(p, indent=2) + "\n")
        pals[s["screen"]] = p
    try:
        bars = panel.panels()
    except (subprocess.CalledProcessError, ValueError):
        return
    size_clocks(bars, {s["screen"]: s["name"] for s in ss}, cfg)
    for bar in bars:
        if bar["screen"] not in pals:
            continue
        p = pals[bar["screen"]]
        try:    # one bar that can't be styled (Colorizer changed, say) must not stop the rest of the theme
            patch = {"widgets": panel.widget_settings(p), "configurationOverrides": panel.island_overrides(p, bar)}
        except Exception as e:
            util.warn("bar %s: islands not restyled: %s", bar["panel"], e)
            continue
        # only bars whose islands change: each apply runs in plasmashell and restyles the whole bar
        # (a pick on one screen leaves the other two bars as they are)
        seen = CACHE / "colorizer" / f"{bar['panel']}-{bar['colorizer']}.sha1"
        key = hashlib.sha1(json.dumps(patch, sort_keys=True).encode()).hexdigest()
        try:
            if seen.read_text() == key:
                continue
        except OSError:
            pass
        if panel.colorizer_apply(bar, patch):
            util.write_if_changed(seen, key)
        else:
            util.warn("bar %s: Colorizer didn't take the new islands", bar["panel"])
