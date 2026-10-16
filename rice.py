#!/usr/bin/env python3
"""Plasma rice: set a wallpaper and re-theme the desktop from it.

    rice.py <image>          set a specific image
    rice.py next|prev        step through ~/Pictures/Wallpapers
    rice.py random           pick a random one
    rice.py restore          re-apply the current wallpaper's theme
    rice.py thumbs           (re)build picker thumbnails
    rice.py screens          JSON list of screens and their wallpapers (for the picker)
    rice.py preset save|load|delete <name>
                             presets: every screen's wallpaper (and the one that drives the
                             theme) under a short name, to switch whole looks at once
    rice.py presets          JSON list of the presets, with thumbnails (for the picker)

    --screen all|focused|<output>   which screens get the wallpaper (default: focused,
                                    the one KWin reports as active; kglobalaccel caches
                                    a shortcut's Exec line until relogin, so this default
                                    is what plain `rice.py next` shortcuts get)

Each screen keeps its own wallpaper. The last one picked drives the global theme
(colour scheme, terminals, window borders); each bar's islands and the widgets on
it follow their own screen's wallpaper (palette-<output>.json + Colorizer over D-Bus).

Writes / applies:
    ~/.local/state/rice/palette.json            global palette (last wallpaper picked)
    ~/.local/state/rice/palette-<output>.json   per-screen palette for the widgets on that bar
    ~/.local/share/color-schemes/Rice{A,B}.colors  KDE colour scheme (alternated so
                                                Plasma always sees a "new" scheme)
    ~/.local/share/konsole/Rice-<hash>.*        Konsole scheme + profile, hot-swapped into open sessions
    ~/.config/alacritty/plasma-rice.toml
    templates/*                                 e.g. ~/.config/starship.toml
    kwinrc [Round-Corners]                      gradient window border (primary -> tertiary)
    ~/.local/share/icons/Papirus-Rice           folder colour nearest the accent (icons.py; only when
                                                settings icon_theme is Papirus-Rice)
    look-and-feel/com.zinoxx.rice splash palette
    apps.py                                     VS Code, btop, MangoHud, Zen themes
Settings: ~/.config/plasma-rice/settings.json (scheme, tokyo_tint, depth, candy, wallhaven_queries,
bar_scale for the size of a bar's widgets, top_scale for the Glimpse band at the top,
icon_theme;
each is one factor for every screen or {output: factor}).
The current-wallpaper symlink is ~/.local/state/rice/wallpaper.
"""
import fcntl
import hashlib
import json
import random
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "panel"))
import apps  # noqa: E402
import build  # noqa: E402
import icons  # noqa: E402
import tokens  # noqa: E402
import palette  # noqa: E402

HOME = Path.home()
HERE = Path(__file__).resolve().parent
WALLDIR = HOME / "Pictures/Wallpapers"
STATE = HOME / ".local/state/rice"
CACHE = HOME / ".cache/rice"
THUMBS = CACHE / "thumbs-plasma"
CURRENT = STATE / "wallpaper"
PRESETS = STATE / "presets.json"
PRESET_LEN = 10     # names stay short: they're chips in the picker
EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def settings():
    try:
        return json.loads((HERE / "settings.json").read_text())
    except (OSError, ValueError):
        return {}


def walls():
    return sorted(p for p in WALLDIR.iterdir() if p.suffix.lower() in EXTS) if WALLDIR.is_dir() else []


def thumb(img):
    out = THUMBS / (img.stem + ".jpg")
    if not out.exists() or out.stat().st_mtime < img.stat().st_mtime:
        THUMBS.mkdir(parents=True, exist_ok=True)
        subprocess.run(["magick", str(img) + "[0]", "-resize", "480x270^", "-gravity", "center",
                        "-extent", "480x270", "-quality", "88", str(out)], check=False)
    return out


def pick(arg, cur=None, taken=()):
    """cur: the wallpaper next/prev step from (default: the last one picked);
    taken: wallpapers on other screens, which random avoids when it can."""
    ws = walls()
    if cur is None or arg == "restore":
        try:
            cur = CURRENT.resolve(strict=True)
        except OSError:
            cur = None
    if arg in ("next", "prev"):
        if not ws:
            sys.exit("no wallpapers in " + str(WALLDIR))
        i = ws.index(cur) if cur in ws else -1
        return ws[(i + (1 if arg == "next" else -1)) % len(ws)]
    if arg == "random":
        return random.choice([w for w in ws if w != cur and w not in taken] or [w for w in ws if w != cur] or ws)
    if arg == "restore":
        return cur if cur and cur.exists() else (ws[0] if ws else sys.exit("no wallpaper"))
    p = Path(arg).expanduser().resolve()
    if not p.is_file():
        sys.exit(f"not a file: {p}")
    return p


# ---------------------------------------------------------------- writers
def write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return False
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)
    return True


def kde_scheme(p, name):
    c = palette.rgb_csv
    fg = dict(
        ForegroundNormal=p["on_surface"], ForegroundInactive=p["on_surface_variant"],
        ForegroundActive=p["primary"], ForegroundLink=p["blue"], ForegroundVisited=p["magenta"],
        ForegroundNegative=p["red"], ForegroundNeutral=p["yellow"], ForegroundPositive=p["green"],
        DecorationFocus=p["primary"], DecorationHover=p["primary"],
    )
    groups = {
        "Window": (p["surface"], p["surface_low"]),
        "View": (p["background"], p["surface"]),
        "Button": (p["surface_high"], p["surface_container"]),
        "Header": (p["background"], p["surface"]),
        "Header][Inactive": (p["background"], p["surface"]),
        "Tooltip": (p["surface_container"], p["surface_high"]),
        "Complementary": (p["surface_lowest"], p["background"]),
    }
    out = [f"# Generated by ~/.config/plasma-rice/rice.py from {p.get('_wallpaper', '')}. Do not edit.",
           "[ColorEffects:Disabled]", "Color=56,56,56", "ColorAmount=0", "ColorEffect=0",
           "ContrastAmount=0.65", "ContrastEffect=1", "IntensityAmount=0.1", "IntensityEffect=2", "",
           "[ColorEffects:Inactive]", "ChangeSelectionColor=true", "Color=112,111,110", "ColorAmount=0.025",
           "ColorEffect=2", "ContrastAmount=0.1", "ContrastEffect=2", "Enable=false",
           "IntensityAmount=0", "IntensityEffect=0", ""]
    for g, (bg, alt) in groups.items():
        out.append(f"[Colors:{g}]")
        out += [f"BackgroundNormal={c(bg)}", f"BackgroundAlternate={c(alt)}"]
        out += [f"{k}={c(v)}" for k, v in fg.items()]
        out.append("")
    sel = dict(fg, ForegroundNormal=p["on_primary"], ForegroundInactive=p["on_primary"],
               ForegroundActive=p["on_primary"], ForegroundLink=p["on_primary"])
    out.append("[Colors:Selection]")
    out += [f"BackgroundNormal={c(p['primary'])}", f"BackgroundAlternate={c(p['primary_dim'])}"]
    out += [f"{k}={c(v)}" for k, v in sel.items()]
    out += ["", "[General]", f"ColorScheme={name}", f"Name=Rice ({name[-1]})", "accentActiveTitlebar=false",
            "accentInactiveTitlebar=false", "shadeSortColumn=true", "TitlebarIsAccentColored=false", "",
            "[KDE]", "contrast=4", "",
            "[WM]",
            f"activeBackground={c(p['background'])}", f"activeBlend={c(p['primary'])}",
            f"activeForeground={c(p['on_surface'])}",
            f"inactiveBackground={c(p['background'])}", f"inactiveBlend={c(p['outline_variant'])}",
            f"inactiveForeground={c(p['muted'])}", ""]
    return "\n".join(out)


ANSI = apps.ANSI


def ansi(p):
    """(normal, bright, faint) per ANSI slot: the mapping lives in apps.ansi (VS Code's terminal uses it too)."""
    return apps.ansi(p)


# shared by Konsole and Alacritty, so the two terminals look alike
TERM_FONT = (tokens.TOKENS["font"]["mono"], 11)     # pt: 14.7 px, a step above the UI's 13 px Inter
TERM_PAD = tokens.TOKENS["space"]["lg"]             # px around the text
TERM_OPACITY = 0.85


def konsole(p):
    c, t = palette.rgb_csv, ansi(p)
    out = ["[Background]", f"Color={c(p['background'])}", "", "[BackgroundFaint]",
           f"Color={c(p['background'])}", "", "[BackgroundIntense]", f"Color={c(p['surface'])}", ""]
    for i, n in enumerate(ANSI):
        norm, bright, dim = t[n]
        out += [f"[Color{i}]", f"Color={c(norm)}", "", f"[Color{i}Faint]", f"Color={c(dim)}", "",
                f"[Color{i}Intense]", f"Color={c(bright)}", ""]
    out += ["[Foreground]", f"Color={c(p['on_surface'])}", "", "[ForegroundFaint]",
            f"Color={c(p['on_surface_variant'])}", "", "[ForegroundIntense]", f"Color={c(p['on_surface'])}", "",
            "[General]", "Blur=true", "ColorRandomization=false", "Description=Rice (wallpaper)",
            f"Opacity={TERM_OPACITY}", "Wallpaper=", ""]
    return "\n".join(out)


KONSOLE_PROFILE = """[Appearance]
ColorScheme={name}
Font={font},{size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[Cursor Options]
CursorShape=1
CustomCursorColor={cursor}
CustomCursorTextColor={cursor_text}
UseCustomCursorColor=true

[General]
Command=/usr/bin/zsh
DimValue=40
DimWhenInactive=true
Name={name}
Parent=FALLBACK/
TerminalCenter=true
TerminalMargin={margin}

[Scrolling]
ScrollBarPosition=2
"""


def konsole_tabs(p):
    """Tab bar stylesheet (Konsole shows the bar only with 2+ tabs): quiet pills, the current one an
    accent wash with a hairline, the way the bar's islands mark an open popup. Konsole puts the tabs
    in document mode, so the QTabBar spans the window: painting it like the terminal (same colour,
    same opacity) makes tabs and terminal one surface instead of Darkly's darker translucent strip."""
    r = lambda h, a: f"rgba({palette.rgb_csv(h)}, {round(a * 255)})"   # noqa: E731
    al, rad, sp = tokens.TOKENS["alpha"], tokens.TOKENS["radius"], tokens.TOKENS["space"]
    return f"""/* Generated by ~/.config/plasma-rice/rice.py from the wallpaper palette. Do not edit. */
QTabBar {{ background: {r(p['background'], TERM_OPACITY)}; }}
QTabBar::tab {{
    background: transparent; color: {p['muted']};
    border: 1px solid transparent; border-radius: {rad['sm']}px;
    padding: {sp['xs']}px {sp['md']}px; margin: {sp['sm']}px {sp['xxs']}px {sp['xxs']}px {sp['xxs']}px;
    min-width: 7em; max-width: 22em;
}}
QTabBar::tab:first {{ margin-left: {TERM_PAD - sp['xs']}px; }}
QTabBar::tab:hover:!selected {{ background: {r(p['on_surface'], al['hover'])}; color: {p['on_surface_variant']}; }}
QTabBar::tab:selected {{
    background: {r(p['primary'], al['selected'])}; color: {p['on_surface']};
    border-color: {r(p['primary'], al['outlineStrong'] + 0.1)};
}}
"""


def apply_konsole(p):
    """Konsole caches schemes and profiles by name, so each palette gets fresh
    names (Rice-<hash>); running sessions on a Rice profile are switched over D-Bus.
    Also keeps the window chrome off for good: no menu bar or toolbars (new windows read
    the saved window state, which a window rewrites when it closes), tabs only when needed."""
    d = HOME / ".local/share/konsole"
    c = palette.rgb_csv
    scheme = konsole(p)
    profile = KONSOLE_PROFILE.format(name="{name}", font=TERM_FONT[0], size=TERM_FONT[1], margin=TERM_PAD,
                                     cursor=c(p["primary"]), cursor_text=c(p["on_primary"]))
    name = "Rice-" + hashlib.sha1((scheme + profile).encode()).hexdigest()[:6]
    write_if_changed(d / f"{name}.colorscheme", scheme)
    write_if_changed(d / f"{name}.profile", profile.replace("{name}", name))
    write_if_changed(d / "rice-tabs.css", konsole_tabs(p))
    apps.kde_set("konsolerc", {"Desktop Entry": {"DefaultProfile": f"{name}.profile"}})
    apps.konsole_chrome()       # menu bar, toolbars, tab bar (rice-tabs.css)
    for svc in run("qdbus6").stdout.split():
        if not svc.startswith("org.kde.konsole"):
            continue
        for path in run("qdbus6", svc).stdout.split():
            if path.startswith("/Sessions/") and run("qdbus6", svc, path, "org.kde.konsole.Session.profile").stdout.startswith("Rice"):
                run("qdbus6", svc, path, "org.kde.konsole.Session.setProfile", f"ColorScheme={name}")
    # keep the current and previous generation only (and drop the pre-rice Tokyo Night profile)
    gens = sorted(d.glob("Rice-*.profile"), key=lambda f: f.stat().st_mtime, reverse=True)
    for old in gens[2:]:
        old.unlink(missing_ok=True)
        (d / (old.stem + ".colorscheme")).unlink(missing_ok=True)
    for stale in ("Tokyo Night.profile", "TokyoNight.colorscheme"):
        (d / stale).unlink(missing_ok=True)


def alacritty(p):
    """Colours plus the look shared with Konsole (font, padding, cursor, opacity); alacritty.toml
    imports this file and leaves those keys to it."""
    t = ansi(p)
    font, size = TERM_FONT
    out = ["# Generated by ~/.config/plasma-rice/rice.py. Do not edit.",
           "[window]", f"opacity = {TERM_OPACITY}", "blur = true",
           f"padding = {{ x = {TERM_PAD}, y = {TERM_PAD} }}", "dynamic_padding = true", "",
           "[font]", f"size = {float(size)}"]
    out += [f'{k} = {{ family = "{font}", style = "{s}" }}'
            for k, s in (("normal", "Regular"), ("bold", "Bold"), ("italic", "Italic"), ("bold_italic", "Bold Italic"))]
    out += ["", "[cursor]", 'style = { shape = "Beam", blinking = "Off" }', "unfocused_hollow = true",
            "thickness = 0.15", "", "[colors.primary]",
            f'background = "{p["background"]}"', f'foreground = "{p["on_surface"]}"', "",
            "[colors.cursor]", f'cursor = "{p["primary"]}"', f'text = "{p["on_primary"]}"', "",
            "[colors.selection]", f'background = "{p["primary_container"]}"',
            f'text = "{p["on_primary_container"]}"', ""]
    for section, idx in (("normal", 0), ("bright", 1), ("dim", 2)):
        out.append(f"[colors.{section}]")
        out += [f'{n} = "{t[n][idx]}"' for n in ANSI]
        out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------- apply
def run(*cmd):
    return subprocess.run(cmd, check=False, capture_output=True, text=True)


def apply_scheme(p):
    schemes = HOME / ".local/share/color-schemes"
    current = run("kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout.strip()
    name = "RiceB" if current == "RiceA" else "RiceA"
    write_if_changed(schemes / f"{name}.colors", kde_scheme(p, name))
    run("plasma-apply-colorscheme", name)


TEMPLATES = {  # template in ~/.config/plasma-rice/templates -> output; {{name}} = palette colour
    "starship.toml": HOME / ".config/starship.toml",
}


def render_templates(p):
    import re
    for name, out in TEMPLATES.items():
        src = HERE / "templates" / name
        if src.exists():
            text = re.sub(r"\{\{(\w+)\}\}", lambda m: p.get(m.group(1), m.group(0)), src.read_text())
            write_if_changed(out, text)


KWIN_EFFECTS = {   # effect id -> on; rice_* live in plasma-rice/kwin (apps.py setup links them for KWin)
    "rice_window": True,            # open/close: fade + small scale (replaces glide / scale)
    "rice_popups": True,            # menus, tooltips: fade + short slide (replaces fadingpopups)
    "kwin6_effect_glide": False, "scale": False, "fadingpopups": False,
    # rounded corners + window border: the local build (pkg/kwin-effect-rounded-corners-rice) that
    # colours each window's border from its own screen's palette, under its own id
    "kwin4_effect_shapecorners": False, "kwin4_effect_shapecorners_rice": True,
}
CORNERS = "kwin4_effect_shapecorners_rice"
BLUR_CLASSES = ["zen", "dolphin", "Alacritty"]   # force-blurred: these don't ask for blur KWin 6.7 understands


def apply_kwin(p):
    """Window chrome. ShapeCorners clips every window to the windows radius (tokens md) and draws the
    active window's gradient border (primary -> tertiary, HyDE style) in the palette of the screen the
    window is on ([Round-Corners][Output <name>], read by the patched local build; `p` is the fallback);
    Klassy draws the titlebar and a neutral shadow with the same round corner (a squircle clip would
    leave Klassy's round shadow peeking out at the corners; a tinted shadow can't follow the screen).
    Also keeps the rice's window motion effects loaded and the blur settings."""
    c, r = palette.rgb_csv, tokens.TOKENS["radius"]["md"]
    corners = apps.kde_set("kwinrc", {"Round-Corners": {
        "Size": r, "InactiveCornerRadius": r, "UseSquircleShape": False, "UseNativeDecorationShadows": True,
        "OutlineColor": c(p["primary"]), "OutlineColor2": c(p["tertiary"]),
        "InactiveOutlineColor": c(p["outline_variant"]), "InactiveOutlineColor2": c(p["outline_variant"])}})
    for f in sorted(STATE.glob("palette-*.json")):
        try:
            sp = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        corners |= apps.kde_set("kwinrc", {("Round-Corners", f"Output {f.stem.removeprefix('palette-')}"): {
            "OutlineColor": c(sp["primary"]), "OutlineColor2": c(sp["tertiary"]),
            "InactiveOutlineColor": c(sp["outline_variant"])}})
    blur = apps.kde_set("kwinrc", {"Effect-better-blur-dx": {"BlurStrength": 8, "WindowClasses": "\n".join(BLUR_CLASSES)}})
    deco = apps.kde_set("kwinrc", {"org.kde.kdecoration2": {"ButtonsOnLeft": "M", "ButtonsOnRight": "IAX"}})
    deco |= apps.kde_set("klassy/klassyrc", {
        "Windeco": {"WindowCornerRadius": r},
        "ShadowStyle": {"ShadowSizeActive": "ShadowLarge", "ShadowStrengthActive": 230,
                        "ShadowColorActive": "0,0,0",
                        "ShadowSizeInactive": "ShadowMedium", "ShadowStrengthInactive": 150,
                        "ShadowColorInactive": "0,0,0"}})
    apps.kde_set("kwinrc", {"Plugins": {f"{e}Enabled": on for e, on in KWIN_EFFECTS.items()}})

    fx = "org.kde.kwin.Effects"
    if corners:
        run("qdbus6", "org.kde.KWin", "/Effects", f"{fx}.reconfigureEffect", CORNERS)
    if blur:
        run("qdbus6", "org.kde.KWin", "/Effects", f"{fx}.reconfigureEffect", "better_blur_dx")
    if deco:    # decorations only re-read their settings on a KWin reconfigure (scripts stay as they are)
        run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure")
    installed = HOME / ".local/share/kwin/effects"
    for src in (HERE / "kwin").iterdir():
        if not (installed / src.name).is_symlink():
            installed.mkdir(parents=True, exist_ok=True)
            (installed / src.name).symlink_to(src)
    loaded = set(run("qdbus6", "org.kde.KWin", "/Effects", f"{fx}.loadedEffects").stdout.split())
    for e, on in KWIN_EFFECTS.items():
        if on != (e in loaded):
            run("qdbus6", "org.kde.KWin", "/Effects", f"{fx}.{'loadEffect' if on else 'unloadEffect'}", e)


# ---------------------------------------------------------------- screens
DESKTOPS_JS = r"""
var out = [];
desktops().forEach(function (d) {
    if (d.screen < 0) return;
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
    """Enabled outputs by logical position -> name and a short label (Laptop / 4K / 1440p)."""
    try:
        data = json.loads(run("kscreen-doctor", "-j").stdout)
    except ValueError:
        return {}
    out = {}
    for o in data.get("outputs", []):
        if not o.get("enabled"):
            continue
        mode = next((m for m in o.get("modes", []) if m["id"] == o.get("currentModeId")), o)
        h = mode["size"]["height"]
        label = "Laptop" if o["name"].startswith(("eDP", "LVDS", "DSI")) else "4K" if h == 2160 else f"{h}p"
        scale = o.get("scale") or 1
        out[(o["pos"]["x"], o["pos"]["y"])] = {"name": o["name"], "label": label,
                                               "w": round(mode["size"]["width"] / scale), "h": round(h / scale)}
    return out


def screens():
    """Screens left to right: output name, label, Plasma screen index (0 = main bar),
    desktop containment ids and the current wallpaper (path, "" if not an image file)."""
    outs = outputs()
    try:
        desks = json.loads(build.shell(DESKTOPS_JS))
    except (subprocess.CalledProcessError, ValueError):
        return []
    found = {}
    for d in desks:
        o = outs.get((d["x"], d["y"]))
        if not o:
            continue
        s = found.setdefault(o["name"], dict(o, screen=d["screen"], x=d["x"], main=d["screen"] == 0,
                                              desktops=[], image=""))
        s["desktops"].append(d["id"])
        img = d["image"].removeprefix("file://")
        if not s["image"] and img and Path(img).is_file():
            s["image"] = img
    return sorted(found.values(), key=lambda s: s["x"])


def set_images(targets, img):
    build.shell(SET_JS % json.dumps({str(d): f"file://{img}" for s in targets for d in s["desktops"]}))


def palette_for(img, cfg):
    """matugen + palette.build, cached per image and settings (a pick touches up to three screens)."""
    key = hashlib.sha1(json.dumps([str(img), img.stat().st_mtime, cfg], sort_keys=True).encode()).hexdigest()[:16]
    f = CACHE / "palettes" / f"{key}.json"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        pass
    p = palette.build(palette.matugen(img, cfg.get("scheme", "scheme-tonal-spot")), cfg)
    write_if_changed(f, json.dumps(p))
    return p


def with_meta(p, img):
    return dict(p, _wallpaper=str(img), _thumb=str(thumb(img)))


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
        subprocess.run(["magick", str(img) + "[0]", "-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}",
                        "-gravity", "north", "-crop", f"{w}x{GLASS_BAND}+0+0", "+repage",
                        "-blur", "0x14", "-modulate", "104,150", "-quality", "90", str(out)], check=False)
        for old in d.glob(f"{s['name']}-*.jpg"):
            if old != out:
                old.unlink(missing_ok=True)
    return str(out) if out.exists() else ""


def scale_for(setting, output):
    """A size factor from settings.json: one number for every screen, or {output: factor}."""
    if isinstance(setting, (int, float)):
        return setting
    return (setting or {}).get(output, 1)


def apply_screens(ss, cfg, fallback):
    """Each screen's palette, for the widgets on its bar, and its bar's island colours."""
    pals = {}
    for s in ss:
        img = Path(s["image"]) if s["image"] else None
        p = with_meta(palette_for(img, cfg), img) if img else fallback
        p = dict(p, _glass=glass(img, s), _glassBand=GLASS_BAND,
                 _scale=scale_for(cfg.get("bar_scale"), s["name"]),         # size of that bar's widgets
                 _topScale=scale_for(cfg.get("top_scale"), s["name"]))      # size of the Glimpse band up top
        write_if_changed(STATE / f"palette-{s['name']}.json", json.dumps(p, indent=2) + "\n")
        pals[s["screen"]] = p
    try:
        bars = build.panels()
    except (subprocess.CalledProcessError, ValueError):
        return
    for bar in bars:
        if bar["screen"] in pals:
            p = pals[bar["screen"]]
            build.colorizer_apply(bar, {"widgets": build.widget_settings(p),
                                        "configurationOverrides": build.island_overrides(p, bar)})


def set_lockscreen(img):
    run("kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper",
        "--group", "org.kde.image", "--group", "General", "--key", "Image", f"file://{img}")
    run("kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper",
        "--group", "org.kde.image", "--group", "General", "--key", "PreviewImage", f"file://{img}")


# ---------------------------------------------------------------- presets
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
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps[ps.index(old)] = entry
    else:
        ps.append(entry)
    write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")
    print(name)


def preset_delete(name):
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps.remove(old)
        write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")


def preset_prepare(name, ss):
    """Puts a preset's wallpapers on every screen but the one that drives the theme and returns
    (that image, that screen), which main() then picks and themes from like any other pick.
    Screens the preset doesn't know (or whose image is gone) keep what they have."""
    p = find_preset(presets(), name)
    if not p:
        sys.exit(f"no preset named {name!r}")
    have = {s["name"]: s for s in ss}
    usable = {o: img for o, img in p["screens"].items() if o in have and Path(img).is_file()}
    if not usable:
        sys.exit(f"none of {p['name']!r}'s wallpapers are on a connected screen any more")
    lead = next((o for o, img in usable.items() if img == p["theme"]), next(iter(usable)))
    for o, img in usable.items():
        if o != lead and have[o]["image"] != img:
            set_images([have[o]], Path(img))
            have[o]["image"] = img
    return usable[lead], lead, p["name"]


def main():
    args = sys.argv[1:]
    target = "focused"
    if "--screen" in args:
        i = args.index("--screen")
        target = args[i + 1] if i + 1 < len(args) else "all"
        del args[i:i + 2]
    arg = args[0] if args else "random"
    STATE.mkdir(parents=True, exist_ok=True)
    if arg == "thumbs":
        for w in walls():
            thumb(w)
        return
    if arg == "screens":
        ss = screens()
        for s in ss:
            s["thumb"] = str(thumb(Path(s["image"]))) if s["image"] else ""
        print(json.dumps(ss))
        return
    if arg == "presets":
        print(json.dumps([dict(p, thumbs={o: str(thumb(Path(img))) for o, img in p["screens"].items()
                                           if Path(img).is_file()}) for p in presets()]))
        return
    preset = ""
    if arg == "preset":
        sub, preset = (args[1:3] + ["", ""])[:2]
        if sub == "save":
            preset_save(preset, screens())
            return
        if sub == "delete":
            preset_delete(preset)
            return
        if sub != "load":
            sys.exit("rice.py preset save|load|delete <name>")

    tokens.write()      # qml/Rice/Tokens.qml, from the design tokens
    lock = open(STATE / "rice.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    ss = screens()
    if preset:      # load: the other screens first, then the lead one themes everything like a pick
        arg, target, preset = preset_prepare(preset, ss)
    if target == "focused":
        target = run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName").stdout.strip() or "all"
    chosen = [s for s in ss if target in ("all", s["name"])]
    if ss and not chosen:
        sys.exit(f"no screen named {target!r} (have: {', '.join(s['name'] for s in ss)})")

    one = chosen[0] if len(chosen) == 1 else None
    img = pick(arg, cur=Path(one["image"]).resolve() if one and one["image"] else None,
               taken={Path(s["image"]).resolve() for s in ss if s["image"]})
    cfg = settings()
    tmp = STATE / "wallpaper.tmp"
    tmp.unlink(missing_ok=True)
    tmp.symlink_to(img)
    tmp.replace(CURRENT)

    if arg != "restore":
        if ss:
            set_images(chosen, img)
            for s in chosen:
                s["image"] = str(img)
        else:   # couldn't map screens: old behaviour, every desktop
            run("plasma-apply-wallpaperimage", str(img))
        set_lockscreen(img)

    p = with_meta(palette_for(img, cfg), img)
    # per-screen palettes first: the widgets re-read theirs when the colour scheme changes below
    apply_screens(ss, cfg, p)

    write_if_changed(STATE / "palette.json", json.dumps(p, indent=2) + "\n")
    write_if_changed(HOME / ".config/alacritty/plasma-rice.toml", alacritty(p))
    render_templates(p)
    write_if_changed(HOME / ".local/share/plasma/look-and-feel/com.zinoxx.rice/contents/splash/palette.js",
                     ".pragma library\n// Written by ~/.config/plasma-rice/rice.py\n"
                     f"var wallpaper = {json.dumps(str(img))};\n"
                     f"var colors = {json.dumps({k: v for k, v in p.items() if not k.startswith('_')})};\n")
    apply_scheme(p)
    apply_kwin(p)
    apply_konsole(p)
    icons.apply(p["primary"], cfg.get("icon_theme", "Papirus-Rice"))
    apps.apply(p)

    if arg != "restore":
        where = one["label"] if one and len(ss) > 1 else "all screens" if len(ss) > 1 else ""
        run("notify-send", "-a", "Theme", "-i", str(img), "-h",
            "string:x-canonical-private-synchronous:wallpaper", "Theme updated",
            f"Preset “{preset}”" if preset else img.name + (f" · {where}" if where else ""))


if __name__ == "__main__":
    main()
