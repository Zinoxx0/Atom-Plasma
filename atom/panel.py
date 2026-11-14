"""The Plasma panels as HyDE-style islands (Panel Colorizer): the island looks rice.py pushes to each bar
on every re-theme (widget_settings, island_overrides, colorizer_apply), and the one-time rebuild of the
bars themselves (main(), `panel/build.py`).

Every screen's bar, left to right (the same islands everywhere: they show on ONE screen at a time, the
pointer's unless a fullscreen window covers it; kwin/rice_islands fades the bars in and out):
  [launcher]  [tasks] ........ [Claude | system rings] [status | tiling | power] [clock]
[tiling] is com.zinoxx.tiling (auto-tiling on/off for that screen).
Two looks per bar: free (islands over the wallpaper) and docked (a window is maximized or touches the bar:
a floor fills the gaps up to the window's edge and the islands flatten into it). Both are Colorizer presets
(dock_presets) that its preset auto-loading switches between; its property animations do the morph.
[launcher] is com.zinoxx.launcher (replaces Kickoff); [tasks] is Glimpse (com.zinoxx.glimpse):
pinned apps here, open windows in its top strip.
A stock task manager found on a bar is replaced by it, pins included.

Islands are the groups of widgets between org.kde.plasma.panelspacer widgets.
Widgets are added through plasmashell's scripting API; the order is then
written to AppletOrder with plasmashell stopped (it is read-only at runtime).
Safe to re-run: it only adds what is missing.
"""
import copy
import functools
import json
import math
import os
import subprocess
import time
from pathlib import Path

from . import palette, util
from .tokens import TOKENS
from .util import HOME, ROOT

APPLETSRC = HOME / ".config/plasma-org.kde.plasma.desktop-appletsrc"
# the island styles start from one of Colorizer's own presets (every key it expects, in its current shape);
# atom/data keeps a copy (Colorizer 8.0.0), in case an update renames or drops it
PRESET = Path("/usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/presets/Blur Widgets/settings.json")
PRESET_COPY = ROOT / "atom/data/colorizer-preset.json"
COLORIZER = "luisbocanegra.panel.colorizer"
SPACER = "org.kde.plasma.panelspacer"
TASKS = "com.zinoxx.glimpse"
TILING = "com.zinoxx.tiling"
LAUNCHER = "com.zinoxx.launcher"           # replaces Kickoff (favourites are Plasma's shared ones)
SHELL = "com.zinoxx.shell"                 # draws the bar widgets' panels on one morphing sheet (qml/Atom)
CLOCK = "com.zinoxx.clock"                 # the clock island (its calendar on the sheet); replaces the stock clock
STATUS = "com.zinoxx.status"               # the status island (tray icons, system state, the control center);
                                           # replaces Plasma's system tray
LEGACY_TASKS = ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"]
ISLAND_RADIUS = TOKENS["radius"]["md"]     # islands share the windows' corner radius
# Islands are notches: flush with the screen's bottom edge, rounded only at the top, outlined on three sides.
# The first and last islands (the launcher, the clock) are corner notches: flush with the screen's side too,
# rounded only on their inner top corner (corner()). The bar isn't floating and Colorizer's fixed panel
# padding (BAR_PAD) replaces Plasma's own, so the widgets get the island's whole height and their icons fill
# it instead of floating in padding. (right -1: Plasma's panel layout rounds its widgets' widths down and leaves
# the last logical pixel empty; the bar window clips the one it overshoots by)
BAR_PAD = {"top": 6, "bottom": 0, "left": 0, "right": -1}


def notch(o, r=ISLAND_RADIUS):
    """One island state (Colorizer `widgets.<state>`) shaped as a notch, in place (r=0: docked, square)."""
    o["radius"] = {"enabled": True, "corner": {"topLeft": r, "topRight": r, "bottomRight": 0, "bottomLeft": 0}}
    o["margin"] = {"enabled": True, "side": {"left": 0, "right": 0, "top": 0, "bottom": 0}}
    o["spacing"] = 6
    o["border"].update(enabled=True, width=1, customSides=True)
    o["border"]["custom"]["widths"] = {"left": 1, "right": 1, "top": 1, "bottom": 0}
    return o


def corner(o, side):
    """A notch (one island state, in place) in the screen's bottom-left or bottom-right corner: no rounding
    and no outline on the screen's side."""
    if side in ("left", "right"):
        o["radius"]["corner"]["topLeft" if side == "left" else "topRight"] = 0
        for b in ("border", "borderSecondary"):
            if o.get(b, {}).get("customSides"):
                o[b]["custom"]["widths"][side] = 0
    return o


FLOOR_ALPHA = 0.86        # the docked bar's floor


def panel_settings(p=None, docked=False):
    """Colorizer's `panel` section: BAR_PAD, and (with a palette) the floor. Free, the floor is there but
    clear (the islands are the bar); docked, it fills the gaps and the stretch over the bar's whole height,
    up to the window's edge, with one hairline along its top and the white sheen under it. It stays enabled
    in both looks so its colours ease from one to the other; only its blur switches (Colorizer can't fade a
    blur region)."""
    ps = preset()["panel"]
    n = ps["normal"]
    n["padding"] = {"enabled": True, "side": dict(BAR_PAD)}
    if not p:
        n["enabled"] = False
        return ps
    bg, k = p["background"], 1 if docked else 0

    def color(c, alpha):
        return {"enabled": True, "sourceType": 0, "custom": c, "alpha": alpha}

    n["enabled"] = True
    n["blurBehind"] = docked
    n["backgroundColor"].update(color(mix(mix(bg, "#ffffff", 0.03), p["primary"], 0.03), FLOOR_ALPHA * k))
    n["foregroundColor"]["enabled"] = False
    n["radius"] = {"enabled": True, "corner": {"topLeft": 0, "topRight": 0, "bottomRight": 0, "bottomLeft": 0}}
    n["border"].update(enabled=True, width=1, customSides=True)
    n["border"]["custom"]["widths"] = {"left": 0, "right": 0, "top": 1, "bottom": 0}
    n["border"]["color"].update(color(mix(p["primary"], p.get("tertiary", p["primary"]), 0.5), 0.34 * k))
    n["borderSecondary"].update(enabled=True, customSides=True)
    n["borderSecondary"]["custom"]["widths"] = {"left": 0, "right": 0, "top": 1, "bottom": 0}
    n["borderSecondary"]["color"].update(color("#ffffff", 0.06 * k))
    n["shadow"]["background"]["enabled"] = False
    n["shadow"]["foreground"]["enabled"] = False
    return ps


@functools.cache
def _preset():
    for f in (PRESET, PRESET_COPY):
        try:
            return json.loads(f.read_text())["globalSettings"]
        except (OSError, ValueError, KeyError) as e:
            util.warn("Colorizer preset %s: %s", f, e)
    raise RuntimeError("no Panel Colorizer preset to start the islands from")


def preset():
    """Colorizer's globalSettings skeleton, a fresh copy each time (callers fill it in)."""
    return copy.deepcopy(_preset())


def widget_settings(p=None, docked=False):
    """Island look. Without a palette the colours follow the KDE colour scheme; with one
    (rice.py passes each screen's) they are fixed to it, so every bar matches its own wallpaper."""
    if p:
        return island_style(p, p["primary"], states=False, docked=docked)
    ws = preset()["widgets"]
    w = ws["normal"]
    w["enabled"] = True
    w["blurBehind"] = True
    w["backgroundColor"].update(enabled=True, sourceType=1, systemColor="backgroundColor",
                                systemColorSet="View", alpha=0.72)
    w["foregroundColor"]["enabled"] = False
    notch(w)
    w["border"]["color"].update(enabled=True, sourceType=1, systemColor="highlightColor",
                                systemColorSet="View", alpha=0.32)
    w["shadow"]["background"].update(enabled=True, size=6, xOffset=0, yOffset=2)
    w["shadow"]["background"]["color"].update(sourceType=0, custom="#000000", alpha=0.45)
    w["shadow"]["foreground"]["enabled"] = False
    w["borderSecondary"]["enabled"] = False

    hovered = copy.deepcopy(w)
    hovered["backgroundColor"]["alpha"] = 0.82
    hovered["border"]["color"]["alpha"] = 0.6
    expanded = copy.deepcopy(w)
    expanded["backgroundColor"]["alpha"] = 0.86
    expanded["border"]["color"]["alpha"] = 0.85
    ws.update(normal=w, hovered=hovered, expanded=expanded)
    return ws


mix = palette.mix_srgb     # the islands have always blended in sRGB


def argb(c, alpha):
    return "#%02x%s" % (round(alpha * 255), c.lstrip("#"))


def island_style(p, acc, states=True, fg=False, docked=False):
    """Obsidian glass: a dark body, a white sheen along the top edge, a hairline outline in the island's
    accent and a soft neutral shadow. Text and icons keep their own colours. Hovering brightens the
    outline; an open popup lights it fully and adds a faint accent glow; attention turns it red.
    states=False: no state changes (islands holding several widgets, which would light up only the hovered
    part). On a light screen (palette `_scheme` light) the same recipe makes white frost: a brighter top
    sheen and a softer shadow. fg=True: Colorizer recolours the island's text and symbolic icons to the
    screen's text colour (stock widgets, which otherwise follow the global colour scheme; ours already read
    their screen's palette, and Colorizer would flatten their accent-coloured text).
    docked=True: the same island flattened into the docked bar's floor (panel_settings): clear, square,
    no outline, sheen or shadow; hover and an open popup show as a faint plate, attention as a red edge.
    The body is one solid colour (it was a top-lit gradient): Colorizer eases colours, radii, borders and
    shadows between the two looks, but not gradients."""
    ws = preset()["widgets"]
    w = ws["normal"]
    bg = p["background"]
    light = p.get("_scheme") == "light"
    red = p.get("red", "#f38ba8")

    def color(c, alpha):
        return {"enabled": True, "sourceType": 0, "custom": c, "alpha": alpha}

    def look(lift, fill, edge, sheen, glow=None, shade=None):
        o = copy.deepcopy(w)
        o["enabled"] = True
        o["blurBehind"] = True
        o["backgroundColor"].update(color(mix(mix(bg, "#ffffff", 0.02 + lift), acc, 0.03), fill))
        if fg:
            o["foregroundColor"].update(enabled=True, sourceType=0, custom=p["on_surface"], alpha=1,
                                        saturationEnabled=False, lightnessEnabled=False)
        else:
            o["foregroundColor"]["enabled"] = False
        notch(o, 0 if docked else ISLAND_RADIUS)
        o["border"]["color"].update(color(edge[0], edge[1]) if isinstance(edge, tuple) else color(acc, edge))
        o["borderSecondary"].update(enabled=True, customSides=True)
        o["borderSecondary"]["custom"]["widths"] = {"left": 0, "right": 0, "top": 1, "bottom": 0}
        o["borderSecondary"]["color"].update(color("#ffffff", min(1.0, sheen * 8) if light else sheen))
        # (the same shadow shape in both looks, so only its colour eases)
        o["shadow"]["background"].update(enabled=True, size=glow[1] if glow else 12, xOffset=0, yOffset=glow[2] if glow else 4)
        o["shadow"]["background"]["color"].update(color(glow[0], glow[3]) if glow
                                                  else color("#000000", (0.16 if light else 0.38) if shade is None else shade))
        o["shadow"]["foreground"]["enabled"] = False
        return o

    if docked:
        out = {"normal": look(0, 0, 0, 0, shade=0)}
        if states:
            out["hovered"] = look(0.06, 0.55, 0, 0, shade=0)
            out["expanded"] = look(0.08, 0.7, 0, 0, shade=0)
            out["needsAttention"] = look(0.04, 0.5, (red, 0.75), 0, shade=0)
        return out
    out = {"normal": look(0, 0.76, 0.26, 0.07)}
    if states:
        out["hovered"] = look(0.025, 0.8, 0.55, 0.10)
        out["expanded"] = look(0.04, 0.82, 0.85, 0.12, glow=(acc, 14, 3, 0.24))
        out["needsAttention"] = look(0.02, 0.8, (red, 0.75), 0.08, glow=(red, 12, 3, 0.2))
    return out


def launcher_style(p, docked=False):
    """The launcher's island is the bar's one jewel: filled with the screen's accent (primary to
    tertiary, left to right) instead of neutral glass, a bright sheen along the top, a brighter
    outline and a soft glow of its own colour. Hover lights it up; an open launcher glows fully.
    docked=True: still the jewel (same fill and outline), squared off and without its glow, as the
    docked bar's end cap."""

    def deep(c, top):
        """The accent as a jewel tone: no lighter than `top`, with enough colour to glow (greys stay grey)."""
        L, C, H = palette.to_oklch(c)
        return palette.oklch(min(L, top), max(C, 0.11) if C >= 0.03 else C, H)

    ws = preset()["widgets"]
    w = ws["normal"]
    a, b = deep(p["primary"], 0.56), deep(p.get("tertiary", p["primary"]), 0.48)

    def color(c, alpha):
        return {"enabled": True, "sourceType": 0, "custom": c, "alpha": alpha}

    def look(fill, edge, sheen, glow):
        o = copy.deepcopy(w)
        o["enabled"] = True
        o["blurBehind"] = True
        o["backgroundColor"].update(enabled=True, sourceType=5, alpha=1)
        o["backgroundColor"]["gradient"] = {"orientation": 0, "stops": [
            {"color": argb(mix(a, "#ffffff", 0.10 + sheen * 0.2), fill), "position": 0},
            {"color": argb(mix(b, "#000000", 0.08), fill * 0.92), "position": 1}]}
        o["foregroundColor"]["enabled"] = False
        notch(o, 0 if docked else ISLAND_RADIUS)
        o["border"]["color"].update(color(mix(p["primary"], "#ffffff", 0.25), edge))
        # no top sheen line: Colorizer draws it straight across, past the rounded corners, which shows
        # on a bright island (the gradient carries the light instead)
        o["borderSecondary"]["enabled"] = False
        o["shadow"]["background"].update(enabled=True, size=14, xOffset=0, yOffset=3)
        o["shadow"]["background"]["color"].update(color(p["primary"], 0 if docked else glow))
        o["shadow"]["foreground"]["enabled"] = False
        return o

    return {"normal": look(0.86, 0.6, 0.35, 0.30), "hovered": look(0.94, 0.85, 0.45, 0.45),
            "expanded": look(0.98, 0.95, 0.5, 0.58), "needsAttention": look(0.94, 0.9, 0.45, 0.45)}


# inner side padding for lone widgets that would otherwise touch the island's edge
PADS = {"org.kde.plasma.digitalclock": 10, "org.kde.plasma.showdesktop": 5}


def island_overrides(p, panel, docked=False):
    """Colorizer overrides lighting the islands' outlines with one gradient across the bar,
    primary on the left to tertiary on the right (the top band's rim, mirrored), and padding
    lone clock/show-desktop widgets (PADS). docked=True: the docked look of the same islands."""
    overrides, assoc = {}, []
    isl = islands(panel)
    seen = [n for n, g in enumerate(isl) if any(w != SHELL for _, w in g)]
    sides = {seen[0]: "left", seen[-1]: "right"} if seen else {}
    for n, group in enumerate(isl):
        if n not in seen:                                   # the shell's host alone: nothing to draw
            continue
        t = n / max(1, len(isl) - 1)
        acc = mix(p["primary"], p.get("tertiary", p["primary"]), t)
        real = [w for _, w in group if w != SHELL]          # (the shell's host has no width)
        pad = max((PADS.get(w, 0) for w in real), default=0) if len(real) == 1 else 0
        name = f"Island {n}"
        stock = all(not w.startswith("com.zinoxx.") for w in real)
        if "com.zinoxx.launcher" in real:
            overrides[name] = launcher_style(p, docked)
        else:
            overrides[name] = island_style(p, acc, states=len(real) == 1, fg=stock, docked=docked)
        if pad:
            for o in overrides[name].values():
                o["margin"] = {"enabled": True, "side": dict(o["margin"]["side"], left=pad, right=pad)}
        for o in overrides[name].values():
            corner(o, sides.get(n))
        assoc += [{"id": i, "name": w, "presets": [name]} for i, w in group]
    return {"overrides": overrides, "associations": assoc}


def bar_looks(p, panel):
    """A bar's two looks as Colorizer globalSettings patches: (free, docked)."""
    return tuple({"widgets": widget_settings(p, d), "panel": panel_settings(p, d),
                  "configurationOverrides": island_overrides(p, panel, d)} for d in (False, True))


# the docked morph: Colorizer eases every colour, radius, border and shadow over this long (OutCubic)
DOCK_MS = 260
# the looks' preset files (Colorizer's auto-loading reads a preset from a folder); the nested test session
# keeps its own, so its panels never touch the real ones
PRESETS = Path(os.environ["ATOM_NESTED"]) / "state/colorizer" if os.environ.get("ATOM_NESTED") \
    else util.STATE / "colorizer"


def dock_presets(panel, looks, key):
    """Writes a bar's two looks as Colorizer presets and returns its preset auto-loading settings: the
    free look normally, the docked one while a window touches the bar or one is maximized on its screen.
    Each look gets a new folder per `key` (a hash of both): Colorizer reloads a preset only when its
    folder changes. The bar's older folders go."""
    pid, tag = panel["panel"], key[:12]
    dirs = {}
    for state, look in zip(("free", "docked"), looks):
        g = colorizer_settings()
        g.update(copy.deepcopy(look))
        d = PRESETS / f"{pid}-{tag}-{state}"
        d.mkdir(parents=True, exist_ok=True)
        util.write_if_changed(d / "settings.json", json.dumps({"globalSettings": g}, sort_keys=True) + "\n")
        dirs[state] = str(d)
    for old in PRESETS.glob(f"{pid}-*"):
        if str(old) not in dirs.values() and old.is_dir():
            for f in old.iterdir():
                f.unlink()
            old.rmdir()
    return {"enabled": True, "normal": dirs["free"], "touchingWindow": dirs["docked"],
            "maximized": dirs["docked"], "filterByScreen": True, "filterByActive": False}


def colorizer_settings():
    g = preset()
    g["widgets"] = widget_settings()
    w = g["widgets"]["normal"]

    g["panel"] = panel_settings()
    g["trayWidgets"]["normal"]["enabled"] = False
    g["nativePanel"] = {"background": {"enabled": True, "opacity": 0, "shadow": False},
                        "floatingDialogs": True, "floatingDialogsAllowOverride": True}
    g["stockPanelSettings"] = {k: {"enabled": False, "value": v} for k, v in (
        ("screen", 0), ("position", "bottom"), ("alignment", "center"), ("lengthMode", "fill"),
        ("visibility", "none"), ("opacity", "adaptive"), ("floating", True), ("thickness", 44), ("visible", True))}
    # the stock clock has no inner padding, so its text touched the island border;
    # associations (which widget gets it) are filled in per panel by the JS below
    g["configurationOverrides"] = {"overrides": {CLOCK_PAD: clock_padding(w)}, "associations": []}
    return g


CLOCK_PAD = "Clock padding"


def clock_padding(normal):
    """Colorizer drops every key an override leaves out, so list them all: sections with
    enabled=false fall back to the global settings (colours included), only the margin differs."""
    def defer(d):
        return {k: ({"enabled": False} if "enabled" in v else defer(v)) if isinstance(v, dict) else v
                for k, v in d.items()}
    o = defer(normal)
    o["margin"] = {"enabled": True, "side": dict(normal["margin"]["side"], left=10, right=10)}
    return {"normal": o}


def shell(js):
    """Runs a plasmashell script; returns what it print()s. Over D-Bus from here, not through qdbus6: a
    script is one argument, and a command line's argument can't pass 128 KB (the bars' Colorizer settings,
    every island's look included, can)."""
    import dbus
    try:
        ps = dbus.Interface(dbus.SessionBus().get_object("org.kde.plasmashell", "/PlasmaShell", introspect=False),
                            "org.kde.PlasmaShell")
        return str(ps.evaluateScript(js, timeout=60)).strip()
    except dbus.DBusException as e:
        raise subprocess.CalledProcessError(1, "org.kde.PlasmaShell.evaluateScript", stderr=str(e)) from e






def panels():
    """Panels with a Colorizer: id, Plasma screen index, logical position, colorizer/clock widget ids, widgets
    and their order (AppletOrder, as plasmashell has it now)."""
    return json.loads(shell(util.script("bars", colorizer=COLORIZER)))


def islands(panel):
    """The panel's islands, left to right: lists of (widget id, plugin) between spacers."""
    order = panel.get("order", "")
    types = {w["id"]: w["type"] for w in panel.get("widgets", [])}
    ids = [int(i) for i in order.split(";") if i.strip().isdigit() and int(i) in types]
    ids += [i for i in types if i not in ids]
    out, cur = [], []
    for i in ids:
        if types[i] == SPACER:
            if cur:
                out.append(cur)
            cur = []
        elif types[i] != COLORIZER:
            cur.append((i, types[i]))
    return out + ([cur] if cur else [])


def colorizer_apply(panel, patch, config=None):
    """Replace top-level sections of one panel's Colorizer settings (e.g. widgets,
    configurationOverrides) in one write through plasmashell's scripting API; the widget
    picks it up live. (Its D-Bus route silently drops messages over ~50 KB, and per-island
    overrides are bigger than that.) `config`: Colorizer's own top-level keys, written alongside
    (presetAutoloading, animationDuration)."""
    js = util.script("colorizer-apply", patch=patch, config=config or {}, panel=panel["panel"], colorizer=COLORIZER)
    try:
        return "ok" in shell(js)
    except subprocess.CalledProcessError:
        return False


def colorizer_set(panel, path, value):
    """Edit one panel's Colorizer settings live through its D-Bus service (it saves them too)."""
    svc = f"{COLORIZER}.c{panel['panel']}.w{panel['colorizer']}"
    return subprocess.run(["qdbus6", svc, "/preset", "property", f"{path} {json.dumps(value)}"],
                          capture_output=True, text=True).returncode == 0


def _pos(bar, wid):
    order = [int(i) for i in bar.get("order", "").split(";") if i.strip().isdigit()]
    return order.index(wid) if wid in order else len(order)


def order_for(ids, others=()):
    """A bar's AppletOrder: the template's widgets in place; widgets the template doesn't know (added by the
    user) each get an island right after the stretch. Spare spacers go in the stretch too (one at either end
    of the bar would keep the corner islands off the screen's edge)."""
    s = list(ids["small"])
    k = lambda name: ids.get(name)
    # (meters: Claude and the system rings share one island; status: the tray, the system's state, tiling
    # and power share another)
    seq = [k(LAUNCHER), s[0],
           k(TASKS), ids["expanding"], k(SHELL), k(COLORIZER), s[1],
           k("com.zinoxx.claudeusage"), k("com.zinoxx.sysstats"), s[2],
           k(STATUS), k(TILING), k("com.zinoxx.session"), s[3],
           k(CLOCK)]
    extra = s[4:]
    # a widget that isn't there (its feature is off) leaves its spacer spare
    keep = []
    for i, w in enumerate(seq):
        if w is None:
            continue
        if w in s and keep and (keep[-1] in s or keep[-1] == ids["expanding"]):
            extra.append(w)
            continue
        keep.append(w)
    if keep and keep[-1] in s:          # (the clock missing)
        extra.append(keep.pop())
    seq = keep
    at = seq.index(ids["expanding"]) + 1
    for o in others:
        seq[at:at] = [o] + ([extra.pop(0)] if extra else [])
        at += 2
    at = seq.index(ids["expanding"]) + 1
    return seq[:at] + extra + seq[at:]


def free_clipboard_key():
    """Meta+V belonged to plasmashell's clipboard applet (Klipper's "show-on-mouse-pos"); the status island
    takes it over (its panel shows the clipboard's history), so the old binding lets go of it first."""
    action = ["plasmashell", "show-on-mouse-pos", "plasmashell", "Show Clipboard Items at Mouse Position"]
    subprocess.run(["busctl", "--user", "call", "org.kde.kglobalaccel", "/kglobalaccel", "org.kde.KGlobalAccel",
                    "setForeignShortcutKeys", "asa(ai)", "4", *action, "0"], capture_output=True)


def configure():
    """Every bar's widgets and their settings (adds what's missing, at the end); returns {panel id: ids}.
    Feature widgets (Claude, tiling) only where those features are on (atom/caps.py)."""
    from . import caps
    free_clipboard_key()
    return json.loads(shell(util.script(
        "bars-configure", settings=colorizer_settings(), spacer=SPACER, spacer_px=SPACER_PX, colorizer=COLORIZER,
        clockpad=CLOCK_PAD,
        tasks=TASKS, legacy=LEGACY_TASKS, launcher=LAUNCHER, tiling=TILING, shell=SHELL, clock=CLOCK, status=STATUS,
        with_tiling=caps.feature("tiling"), with_claude=caps.feature("claude"))))


# a new bar's widgets in order ("|" = a small spacer, "~" = the expanding one): added in this order, a new
# panel needs no reordering (an existing one does: AppletOrder, with plasmashell stopped, main())
# Every screen's bar holds the same islands: they show on one screen at a time (kwin/rice_islands).
# The launcher and the clock are the corner notches, so nothing sits outside them: the shell's host (no width,
# but Colorizer would still draw its island's end) and spare spacers go in the stretch.
TEMPLATE = [LAUNCHER, "|", TASKS, "~", SHELL, COLORIZER, "|", "com.zinoxx.claudeusage", "com.zinoxx.sysstats",
            "|", STATUS, TILING, "com.zinoxx.session", "|", CLOCK]
SPACER_PX = 4      # a small spacer's length: with Colorizer's 6 px spacing either side, 16 px between islands
BAR_PX = 49        # a bar's thickness at UI size 1 (logical px): 56 on the desk monitors at today's size


def _qround(x):
    return math.floor(x + 0.5)


def bar_thickness(s):
    """A screen's bar thickness: BAR_PX at its UI size, nudged by a pixel or two where a fractional scale
    would leave the screen's last row of pixels bare under the islands. KWin rounds such a screen's logical
    height (1440 px at 1.15 = 1252.17 -> 1252) and puts a bottom bar's top and height each on the pixel grid,
    so some thicknesses end a row short of the edge (69 on that screen: 1360 + 79 = 1439)."""
    want = round(BAR_PX * s["ui"])
    d = s.get("display") or {}
    scale, h = d.get("scale") or 1, d.get("h")
    if not h or float(scale).is_integer():
        return want
    px, H = _qround(h * scale), round(h)
    reaches = lambda t: _qround((H - t) * scale) + _qround(t * scale) >= px
    return next((t for t in (want, want - 1, want + 1, want - 2, want + 2) if reaches(t)), want)



def ensure_bars(ss, cfg):
    """One rice bar on every screen: a screen without a panel gets one from TEMPLATE, and every bar's
    thickness follows its screen's UI size. Returns the new panels' ids."""
    from . import caps
    off = {w for f, w in (("claude", "com.zinoxx.claudeusage"), ("tiling", TILING)) if not caps.feature(f, cfg)}

    t = TEMPLATE            # without the widgets of features that are off (and the spacer after each)
    widgets = [w for i, w in enumerate(t) if w not in off and not (w == "|" and i and t[i - 1] in off)]
    want = [{"screen": s["screen"], "height": bar_thickness(s), "widgets": widgets} for s in ss]
    made = json.loads(shell(util.script("bars-new", want=want, spacer=SPACER)) or "[]")
    if made:
        configure()         # the new bars' widget settings (Colorizer, clock), as for the rest
    return made


def main():
    ids = configure()
    print("widgets:", json.dumps(ids))
    # widgets on a bar that its template doesn't place (kept, in their current order)
    known = {v for pi in ids.values() for v in pi.values() if isinstance(v, int)} | \
        {x for pi in ids.values() for x in pi["small"]}
    others = {str(b["panel"]): [w["id"] for w in sorted(b["widgets"], key=lambda w: _pos(b, w["id"]))
                                if w["id"] not in known and w["type"] not in (SPACER, COLORIZER)]
              for b in panels()}

    # plasmashell owns appletsrc while running: stop it, set the order, start it again
    subprocess.run(["systemctl", "--user", "stop", "plasma-plasmashell.service"], check=True)
    time.sleep(1)
    rc = APPLETSRC.name
    for pid, panel_ids in ids.items():
        screen = subprocess.run(["kreadconfig6", "--file", rc, "--group", "Containments", "--group", pid,
                                 "--key", "lastScreen"], capture_output=True, text=True).stdout.strip()
        order = ";".join(str(i) for i in order_for(panel_ids, others.get(pid, ())))
        subprocess.run(["kwriteconfig6", "--file", rc, "--group", "Containments", "--group", pid,
                        "--group", "General", "--key", "AppletOrder", order], check=True)
        print(pid, "->", order)
    subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell.service"], check=True)

    # the settings above use scheme colours; rice.py pushes each screen's own palette to its
    # bar through the Colorizer D-Bus services once they are up
    for _ in range(30):
        if f"{COLORIZER}.c" in subprocess.run(["qdbus6"], capture_output=True, text=True).stdout:
            break
        time.sleep(0.5)
    time.sleep(1)
    for f in (HOME / ".cache/rice/colorizer").glob("*.sha1"):     # rice.py skips bars it thinks are current
        f.unlink()
    subprocess.run([str(ROOT / "rice.py"), "restore"], check=False)

