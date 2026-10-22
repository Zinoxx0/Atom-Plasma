#!/usr/bin/env python3
"""Atom Plasma: set a wallpaper and re-theme the desktop from it.

    rice.py <image>          set a specific image
    rice.py next|prev        step through ~/Pictures/Wallpapers
    rice.py random           pick a random one
    rice.py restore          re-apply the current wallpaper's theme
    rice.py screens-changed  after screens are plugged in or out: each screen's palette, the desktop
                             clock that carries Clawd, the bars' islands and clock sizes, window borders
    rice.py thumbs           (re)build picker thumbnails
    rice.py walls            the picker's list: wallpaper file names, one per line (thumbnails built)
    rice.py check FILE...    can these be wallpapers (format and readable)? names the ones that can't
    rice.py screens          JSON list of screens and their wallpapers (for the picker)
    rice.py preset save|load|delete <name>
                             presets: every screen's wallpaper (and the one that drives the
                             theme) under a short name, to switch whole looks at once
    rice.py presets          JSON list of the presets, with thumbnails (for the picker)
    rice.py theme show       JSON for the Theme page: a screen's mood, wallpaper swatches, accents
                             (auto and current) and its overrides
    rice.py theme set [--mood M|auto] [--primary HEX] [--secondary HEX] [--tertiary HEX]
                      [--intensity F]
                             hand-picked colours for a screen (--screen, default focused; or all),
                             re-themed live. They last until a new wallpaper is picked on that
                             screen, unless saved: `preset save` keeps them (a preset is a theme)
    rice.py theme reset      back to the wallpaper's own colours

    --screen all|focused|<output>   which screens get the wallpaper (default: focused,
                                    the one KWin reports as active; kglobalaccel caches
                                    a shortcut's Exec line until relogin, so this default
                                    is what plain `rice.py next` shortcuts get)

Each screen keeps its own wallpaper. The last one picked drives the global theme
(colour scheme, terminals, window borders); each bar's islands and the widgets on
it follow their own screen's wallpaper (palette-<output>.json + Colorizer over D-Bus).

Writes / applies:
    ~/.local/state/rice/palette.json            global palette (last wallpaper picked)
    ~/.local/state/rice/palette-<output>.json   per-screen palette for the widgets on that bar, with
                                                `_layout` (layout.py: where the desktop clock and music
                                                card sit on that wallpaper) and `_desk` (com.zinoxx.desk)
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
    rgb.py apply                                keyboards on Automatic (laptop, Razer) light up in the accents
Settings: ~/.config/plasma-rice/settings.json (soft_tint: how far the soft mood's surfaces lean toward
Tokyo Night's indigo, depth: extra darkness for dark surfaces, wallhaven_queries,
bar_scale for the size of a bar's widgets, top_scale for the Glimpse band at the top,
icon_theme, desk_media (the screen whose desktop clock carries the music card and Clawd; by default the
only screen, else one beside the main bar's), clock_size (the bar clock's points, per screen), weather {"city": ...} (weather.py), light_ui: light wallpapers turn the desktop light (frosted Plasma Style "Rice-Light", a light
KDE scheme, white-frost islands and popups; terminals and apps keep a dark twin palette);
each size is one factor for every screen or {output: factor}).
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
import layout  # noqa: E402
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
OVERRIDES = STATE / "overrides.json"    # {output: {mood, primary, secondary, tertiary, intensity}}
LEAD = STATE / "theme-screen"           # the output whose wallpaper drives the global theme
OV_KEYS = ("mood", "primary", "secondary", "tertiary", "intensity")
PRESET_LEN = 10     # names stay short: they're chips in the picker
# what both Pillow (the palette, the layout) and ImageMagick (thumbnails, glass, the login screen) read here;
# the Dolphin menu's MimeType (~/.local/share/kio/servicemenus/rice.desktop) offers the same
EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def settings():
    try:
        return json.loads((HERE / "settings.json").read_text())
    except (OSError, ValueError):
        return {}


_lock = None


def hold_lock():
    """One writer at a time: a shortcut, the Theme page and a hotplug can all run rice.py at once. Taken
    before any state is read for a change, and only once per process (a second flock on a new open of
    the same file would wait for this one)."""
    global _lock
    if _lock is None:
        STATE.mkdir(parents=True, exist_ok=True)
        _lock = open(STATE / "rice.lock", "w")
        fcntl.flock(_lock, fcntl.LOCK_EX)


def unusable(img):
    """Why `img` can't be a wallpaper here, or "" if it can."""
    if img.suffix.lower() not in EXTS:
        return f"isn't a supported format (only {', '.join(sorted(EXTS))})"
    try:
        from PIL import Image
        with Image.open(img) as im:
            if im.format == "JPEG":     # verify() only reads a JPEG's header: decode it, at a fraction of its size
                im.draft("RGB", (480, 270))
                im.load()
            else:                       # PNG: every chunk's CRC, without decoding 20 MB of pixels
                im.verify()
    except Exception as e:      # missing, unreadable, not an image, truncated
        return f"can't be read ({e})"
    return ""


def fail(msg):
    """Stop before anything changed, and say why where it was asked from (a shortcut or Dolphin has no terminal)."""
    run("notify-send", "-a", "Theme", "-i", "dialog-error", "-h", "string:x-canonical-private-synchronous:wallpaper",
        "Theme not changed", msg)
    sys.exit(f"rice.py: {msg}")


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
    if p.get("_scheme") == "light":
        # the status/link hues are made for dark backgrounds (terminals): deepen them for light windows
        def ink(col):
            L, C, H = palette.to_oklch(col)
            return palette.oklch(min(L, 0.52), max(C, 0.10), H)
    else:
        def ink(col):
            return col
    fg = dict(
        ForegroundNormal=p["on_surface"], ForegroundInactive=p["on_surface_variant"],
        ForegroundActive=p["primary"], ForegroundLink=ink(p["blue"]), ForegroundVisited=ink(p["magenta"]),
        ForegroundNegative=ink(p["red"]), ForegroundNeutral=ink(p["yellow"]), ForegroundPositive=ink(p["green"]),
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
    out += ["", "[General]", f"ColorScheme={name}", f"Name=Atom Plasma ({name[-1]})", "accentActiveTitlebar=false",
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
SemanticInputClick=true
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
    names (Rice-<hash>); running sessions on a Rice profile are switched over D-Bus. SemanticInputClick: a
    click in the command line moves the cursor there (the shell marks where it starts: shell/rice.zsh).
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


STYLE = {"dark": "Rice", "light": "Rice-Light"}    # Plasma Style variants (plasma-style/build.py)


def apply_style(p):
    """The Plasma Style matching the theme-driving screen: dark glass, or white frost when it is light.
    Stock popups (tray, clock, notifications) follow it; our own popups paint their own screen's surface."""
    name = STYLE.get(p.get("_scheme"), "Rice")
    current = run("kreadconfig6", "--file", "plasmarc", "--group", "Theme", "--key", "name").stdout.strip()
    if current != name:
        run("plasma-apply-desktoptheme", name)


def apply_scheme(p):
    schemes = HOME / ".local/share/color-schemes"
    current = run("kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme").stdout.strip()
    try:        # unchanged (a colour edit on another screen): leave the apps alone, no repaint
        if current in ("RiceA", "RiceB") and (schemes / f"{current}.colors").read_text() == kde_scheme(p, current):
            return
    except OSError:
        pass
    name = "RiceB" if current == "RiceA" else "RiceA"
    write_if_changed(schemes / f"{name}.colors", kde_scheme(p, name))
    run("plasma-apply-colorscheme", name)


TEMPLATES = {  # template in ~/.config/plasma-rice/templates -> output; {{name}} = palette colour
    "starship.toml": HOME / ".config/starship.toml",
    "shell.zsh": HOME / ".config/zsh/rice-colors.zsh",     # read by shell/rice.zsh
}


def render_templates(p):
    """{{name}} = the colour as #rrggbb, {{name.rgb}} = as r;g;b (for ANSI codes)."""
    import re

    def fill(m):
        c = p.get(m.group(1))
        if not c:
            return m.group(0)
        return palette.rgb_csv(c).replace(",", ";") if m.group(2) else c
    for name, out in TEMPLATES.items():
        src = HERE / "templates" / name
        if src.exists():
            write_if_changed(out, re.sub(r"\{\{(\w+)(\.rgb)?\}\}", fill, src.read_text()))


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
        s = found.setdefault(o["name"], dict(o, screen=d["screen"], x=d["x"], y=d["y"], main=d["screen"] == 0,
                                              desktops=[], image=""))
        s["desktops"].append(d["id"])
        img = d["image"].removeprefix("file://")
        if not s["image"] and img and Path(img).is_file():
            s["image"] = img
    return sorted(found.values(), key=lambda s: s["x"])


def set_images(targets, img):
    build.shell(SET_JS % json.dumps({str(d): f"file://{img}" for s in targets for d in s["desktops"]}))


def palette_for(img, cfg, ov=None):
    """palette v2 (the wallpaper's own colours and character: palette.analyse + build_v2), cached per
    image, settings and overrides (a pick touches up to three screens)."""
    ov = ov or {}
    key = hashlib.sha1(json.dumps(["v2", str(img), img.stat().st_mtime, cfg, ov], sort_keys=True).encode()).hexdigest()[:16]
    f = CACHE / "palettes" / f"{key}.json"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        pass
    p = palette.build_v2(palette.analyse(img), cfg, ov)
    write_if_changed(f, json.dumps(p))
    return p


def overrides():
    try:
        return json.loads(OVERRIDES.read_text())
    except (OSError, ValueError):
        return {}


def save_overrides(ovs):
    write_if_changed(OVERRIDES, json.dumps({o: v for o, v in ovs.items() if v}, indent=2) + "\n")


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


def theme_args(args):
    """--mood/--primary/... from `theme set` into an overrides dict ("auto" or "" drops a key)."""
    out = {}
    for k in OV_KEYS:
        flag = "--" + k
        if flag in args:
            i = args.index(flag)
            v = args[i + 1] if i + 1 < len(args) else ""
            if v in ("auto", ""):       # back to the wallpaper's own
                out[k] = "auto"
                continue
            if k == "mood":
                if v not in palette.MOODS + ("auto", ""):
                    sys.exit(f"mood is one of {', '.join(palette.MOODS)} or auto")
            elif k == "intensity":
                try:
                    v = max(0.3, min(1.5, float(v)))
                except ValueError:
                    sys.exit("intensity is a number, 1 = the wallpaper's own")
            elif v and not (len(v) == 7 and v.startswith("#") and all(c in "0123456789abcdefABCDEF" for c in v[1:])):
                sys.exit(f"{flag} takes a #rrggbb colour")
            out[k] = v.lower() if isinstance(v, str) else v
    return out


def theme_show(s, cfg):
    """What the Theme page needs for one screen."""
    img = Path(s["image"]) if s["image"] else None
    if not img or not img.is_file():
        return {"screen": s["name"], "image": ""}
    ov = overrides().get(s["name"], {})
    auto = palette_for(img, cfg)
    cur = palette_for(img, cfg, ov) if ov else auto
    roles = ("primary", "secondary", "tertiary")
    return {"screen": s["name"], "image": str(img), "thumb": str(thumb(img)),
            "mood": cur["_mood"], "scheme": cur["_scheme"], "autoMood": auto["_mood"],
            "detected": cur["_analysis"]["mood"], "moods": list(palette.MOODS), "lightUi": bool(cfg.get("light_ui")),
            "swatches": cur["_swatches"], "overrides": ov,
            "auto": {r: auto[r] for r in roles}, "current": {r: cur[r] for r in roles},
            "surface": cur["background"], "fg": cur["on_surface"]}


def dark_twin(p, img, cfg, ov=None):
    """Terminals, VS Code, Zen, btop and the prompt stay dark in every mood: for a light palette,
    the same wallpaper drawn the dark way (graphite/soft, palette.build_v2 without light_ui)."""
    if p.get("_scheme") != "light" or not img:
        return p
    ov = {k: v for k, v in (ov or {}).items() if k != "mood"}
    return with_meta(palette_for(img, dict(cfg, light_ui=False), ov), img)


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
    write_if_changed(f, json.dumps(L))
    return L


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
            build.shell(CLOCK_JS % json.dumps(want))
        except subprocess.CalledProcessError:
            pass


def apply_screens(ss, cfg, fallback):
    """Each screen's palette (with its overrides), for the widgets on its bar, and its bar's island colours."""
    pals = {}
    ovs = overrides()
    music = media_screen(ss, cfg)
    theme_name = current_theme(ss, ovs)
    for s in ss:
        img = Path(s["image"]) if s["image"] else None
        p = with_meta(palette_for(img, cfg, ovs.get(s["name"])), img) if img else fallback
        g = glass(img, s)
        p = dict(p, _glass=g, _glassBand=GLASS_BAND, _rim=rim(g, p),
                 _scale=scale_for(cfg.get("bar_scale"), s["name"]),         # size of that bar's widgets
                 _topScale=scale_for(cfg.get("top_scale"), s["name"]),      # size of the Glimpse band up top
                 _layout=desk_layout(img, s),                               # the desktop widgets' places (com.zinoxx.desk)
                 _desk={"media": s["name"] == music, "clawd": s["name"] == music, "theme": theme_name})
        write_if_changed(STATE / f"palette-{s['name']}.json", json.dumps(p, indent=2) + "\n")
        pals[s["screen"]] = p
    try:
        bars = build.panels()
    except (subprocess.CalledProcessError, ValueError):
        return
    size_clocks(bars, {s["screen"]: s["name"] for s in ss}, cfg)
    for bar in bars:
        if bar["screen"] in pals:
            p = pals[bar["screen"]]
            patch = {"widgets": build.widget_settings(p), "configurationOverrides": build.island_overrides(p, bar)}
            # only bars whose islands change: each apply runs in plasmashell and restyles the whole bar
            # (a pick on one screen leaves the other two bars as they are)
            seen = CACHE / "colorizer" / f"{bar['panel']}-{bar['colorizer']}.sha1"
            key = hashlib.sha1(json.dumps(patch, sort_keys=True).encode()).hexdigest()
            try:
                if seen.read_text() == key:
                    continue
            except OSError:
                pass
            if build.colorizer_apply(bar, patch):
                write_if_changed(seen, key)


def apply_rgb():
    """Keyboards on Automatic follow the new accents (rgb.py writes only those whose colours changed).
    In the background: a keyboard is no reason to make the theme wait."""
    subprocess.Popen([sys.executable, str(HERE / "rgb.py"), "apply"], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def stage_login(p, img):
    """The login screen follows the theme: its wallpaper, colours and Plasma Style are staged for the copier
    that `boot.py login` installs (a system unit; the greeter can't read ~). Skipped until it's installed."""
    if not Path("/etc/systemd/system/atom-plasma-greeter.path").exists():
        return
    try:
        import boot     # numpy and PIL: only imported here, off the path of the quick commands
        boot.stage_greeter(img, STYLE.get(p.get("_scheme"), "Rice"))
    except Exception as e:      # the desktop's theme mustn't fail because of the login screen
        print(f"rice.py: login screen: {e}", file=sys.stderr)


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
    write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")
    print(name)


def preset_delete(name):
    ps = presets()
    old = find_preset(ps, name)
    if old:
        ps.remove(old)
        write_if_changed(PRESETS, json.dumps(ps, indent=2) + "\n")


def preset_prepare(name, ss):
    """Puts a preset's wallpapers on every screen but the one that drives the theme, and its
    hand-picked colours (or none) in place, and returns (that image, that screen), which main()
    then picks and themes from like any other pick. Screens the preset doesn't know (or whose
    image is gone) keep what they have."""
    p = find_preset(presets(), name)
    if not p:
        sys.exit(f"no preset named {name!r}")
    have = {s["name"]: s for s in ss}
    usable = {o: img for o, img in p["screens"].items() if o in have and not unusable(Path(img))}
    if not usable:
        sys.exit(f"none of {p['name']!r}'s wallpapers are on a connected screen any more")
    lead = p.get("lead") if p.get("lead") in usable else \
        next((o for o, img in usable.items() if img == p["theme"]), next(iter(usable)))
    save_overrides({o: v for o, v in p.get("overrides", {}).items() if o in have})
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
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            sys.exit("--screen takes all, focused or an output name")
        target = args[i + 1]
        del args[i:i + 2]
    arg = args[0] if args else "random"
    STATE.mkdir(parents=True, exist_ok=True)
    if arg == "thumbs":
        for w in walls():
            thumb(w)
        return
    if arg == "walls":      # the picker's list (file names, thumbnails built): one list of formats, EXTS
        for w in walls():
            thumb(w)
            print(w.name)
        return
    if arg == "check":      # servicemenu.sh: can these files be wallpapers? names the ones that can't
        bad = [f"{f}: {why}" for f in args[1:] if (why := unusable(Path(f).expanduser()))]
        if bad:
            sys.exit("\n".join(bad))
        return
    if arg == "screens":
        ss = screens()
        lead, ovs = lead_screen(ss), overrides()
        for s in ss:
            s["thumb"] = str(thumb(Path(s["image"]))) if s["image"] else ""
            s["lead"] = s["name"] == lead                   # its wallpaper drives the system theme
            s["overrides"] = ovs.get(s["name"], {})         # hand-picked colours
            try:
                s["accent"] = json.loads((STATE / f"palette-{s['name']}.json").read_text())["primary"]
            except (OSError, ValueError, KeyError):
                s["accent"] = ""
        print(json.dumps(ss))
        return
    if arg == "screens-changed":     # plugged in or out: palettes, bars and borders follow (com.zinoxx.desk asks)
        try:
            p = json.loads((STATE / "palette.json").read_text())
        except (OSError, ValueError):
            return
        hold_lock()
        apply_screens(screens(), settings(), p)
        apply_kwin(p)
        return
    if arg == "presets":
        print(json.dumps([dict(p, thumbs={o: str(thumb(Path(img))) for o, img in p["screens"].items()
                                           if Path(img).is_file()}) for p in presets()]))
        return
    if arg == "theme":
        sub = args[1] if len(args) > 1 else "show"
        if sub not in ("show", "set", "reset"):
            sys.exit("rice.py theme show|set|reset")
        if sub != "show":
            hold_lock()     # before overrides.json is read: a re-theme running now may be writing it
        ss, cfg = screens(), settings()
        if not ss:
            sys.exit("couldn't map the screens (is plasmashell running?)")
        asked = target
        if target == "focused":
            target = run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName").stdout.strip() or "all"
        pickd = [s for s in ss if target in ("all", s["name"])]
        if not pickd:
            if asked != "focused":      # a name given by hand: a typo must not edit another screen
                sys.exit(f"no screen named {target!r} (have: {', '.join(s['name'] for s in ss)})")
            pickd = ss[:1]              # KWin's active output isn't one of the mapped screens
        if sub == "show":
            print(json.dumps(theme_show(pickd[0], cfg) if target != "all" else [theme_show(s, cfg) for s in ss]))
            return
        ovs = overrides()
        for s in pickd:
            if sub == "reset":
                ovs.pop(s["name"], None)
            else:
                cur = dict(ovs.get(s["name"], {}), **theme_args(args))
                ovs[s["name"]] = {k: v for k, v in cur.items() if v not in ("", "auto", None)}
        save_overrides(ovs)
        arg, target = "restore", "all"       # re-theme everything from the wallpapers as they are
        args = [arg]

    preset = ""
    if arg == "preset":
        sub, preset = (args[1:3] + ["", ""])[:2]
        if sub not in ("save", "load", "delete"):
            sys.exit("rice.py preset save|load|delete <name>")
        hold_lock()
        if sub == "save":
            preset_save(preset, screens())
            return
        if sub == "delete":
            preset_delete(preset)
            return

    hold_lock()
    tokens.write()      # qml/Rice/Tokens.qml, from the design tokens

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
    if why := unusable(img):    # before anything changes: a file the palette can't read would leave a half theme
        fail(f"{img.name} {why}")
    if arg != "restore" and chosen:
        if not preset:      # a new wallpaper: back to its own colours (a loaded preset brings its own)
            save_overrides({o: v for o, v in overrides().items() if o not in {s["name"] for s in chosen}})
        focused = run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName").stdout.strip()
        lead = one["name"] if one else next((s["name"] for s in chosen if s["name"] == focused), chosen[0]["name"])
        write_if_changed(LEAD, lead + "\n")
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

    lead_ov = overrides().get(lead_screen(ss), {}) if ss else {}
    p = with_meta(palette_for(img, cfg, lead_ov), img)
    # per-screen palettes first: the widgets re-read theirs when the colour scheme changes below
    apply_screens(ss, cfg, p)

    write_if_changed(STATE / "palette.json", json.dumps(p, indent=2) + "\n")
    tp = dark_twin(p, img, cfg, lead_ov)        # terminals and apps
    write_if_changed(HOME / ".config/alacritty/plasma-rice.toml", alacritty(tp))
    render_templates(tp)
    write_if_changed(HOME / ".local/share/plasma/look-and-feel/com.zinoxx.rice/contents/splash/palette.js",
                     ".pragma library\n// Written by ~/.config/plasma-rice/rice.py\n"
                     f"var wallpaper = {json.dumps(str(img))};\n"
                     f"var colors = {json.dumps({k: v for k, v in p.items() if not k.startswith('_')})};\n")
    apply_style(p)
    apply_scheme(p)
    stage_login(p, img)
    apply_kwin(p)
    apply_konsole(tp)
    icons.apply(tp["primary"], cfg.get("icon_theme", "Papirus-Rice"))
    apps.apply(tp)
    apply_rgb()

    if arg != "restore":
        where = one["label"] if one and len(ss) > 1 else "all screens" if len(ss) > 1 else ""
        run("notify-send", "-a", "Theme", "-i", str(thumb(img)), "-h",     # not the full image: plasmashell decodes the icon
            "string:x-canonical-private-synchronous:wallpaper", "Theme updated",
            f"Preset “{preset}”" if preset else img.name + (f" · {where}" if where else ""))


if __name__ == "__main__":
    main()
