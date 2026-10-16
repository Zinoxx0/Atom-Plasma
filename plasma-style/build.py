#!/usr/bin/env python3
"""Generate the "Rice" Plasma Style (desktoptheme) into ~/.local/share/plasma/desktoptheme/Rice.

Rounded, translucent frames with hairline outlines and soft shadows, in the spirit of HyDE.
The chrome is NEUTRAL: outlines, washes and "on" fills are white/black alpha, never the colour
scheme's highlight. The scheme follows the last wallpaper picked, so its accent belongs to one
screen and clashed with the other screens (each bar and its popups take their own screen's
palette). Surfaces still use ColorScheme-Background, so text keeps its contrast.

Radii and spacing come from the design tokens (../tokens.py). Re-run after editing, then delete
~/.cache/plasma_theme_Rice*.kcache and restart plasmashell.
"""
import gzip
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tokens import TOKENS  # noqa: E402

OUT = Path.home() / ".local/share/plasma/desktoptheme/Rice"
E = 10  # length of the stretchable edge pieces in the source SVG
RAD = TOKENS["radius"]
SP = TOKENS["space"]
A = TOKENS["alpha"]

WHITE, BLACK = "#ffffff", "#000000"
BG = "ColorScheme-Background"
# Two variants (build(variant)): "dark" = Rice, neutral dark glass with white ink; "light" = Rice-Light,
# white frost with black ink, for when the theme-driving wallpaper is light (palette v2 `_scheme`).
# popups and tooltips: one fixed neutral body. The scheme background is the last-picked wallpaper's colour,
# which tinted popups on the other screens (plum over a blue screen)
VARIANTS = {
    "dark": dict(dir="Rice", name="Atom Plasma", NEUTRAL="#12131a", INK=WHITE, TICK="#14151b", LIGHT=False, SHADOW=1.0),
    "light": dict(dir="Rice-Light", name="Atom Plasma Light", NEUTRAL="#f4f5f8", INK=BLACK, TICK="#ffffff", LIGHT=True,
                  SHADOW=0.55),
}
NEUTRAL, INK, TICK, LIGHT, SHADOW = "#12131a", WHITE, "#14151b", False, 1.0
SHEEN = WHITE           # the wash at the top of frames: a white sheen in both variants

STYLE = """<style type="text/css" id="current-color-scheme">
  .ColorScheme-Text { color:#c0caf5; }
  .ColorScheme-Background { color:#1a1b26; }
  .ColorScheme-ViewBackground { color:#16161e; }
  .ColorScheme-Highlight { color:#7aa2f7; }
  .ColorScheme-NegativeText { color:#f7768e; }
  .ColorScheme-NeutralText { color:#e0af68; }
</style>"""


def svg(body, w=400, h=400):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs>{STYLE}{"".join(DEFS)}</defs>{body}</svg>')


DEFS = []
_gid = [0]


def gid():
    _gid[0] += 1
    return f"g{_gid[0]}"


def paint(colour, op, attr="fill"):
    """Fill (or gradient stop, attr="stop") style for a fixed colour ("#rrggbb") or a colour-scheme class."""
    prop, opac = ("stop-color", "stop-opacity") if attr == "stop" else (attr, attr + "-opacity")
    if colour.startswith("#"):
        return f'style="{prop}:{colour};{opac}:{op:.3f}"'
    return f'class="{colour}" style="{prop}:currentColor;{opac}:{op:.3f}"'


def bounds(x, y, w, h):
    """An invisible rect that gives a group its size."""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>'


def pieces(ox, oy, r):
    """Rects (x, y, w, h) of the nine frame pieces with corner size r."""
    return {
        "topleft": (ox, oy, r, r), "top": (ox + r, oy, E, r), "topright": (ox + r + E, oy, r, r),
        "left": (ox, oy + r, r, E), "center": (ox + r, oy + r, E, E), "right": (ox + r + E, oy + r, r, E),
        "bottomleft": (ox, oy + r + E, r, r), "bottom": (ox + r, oy + r + E, E, r),
        "bottomright": (ox + r + E, oy + r + E, r, r),
    }


CORNERS = ("topleft", "topright", "bottomleft", "bottomright")
# per corner: the arc centre (as a fraction of the piece) and the two arc ends, drawn clockwise
ARC = {"topleft": ((1, 1), (-1, 0), (0, -1)), "topright": ((0, 1), (0, -1), (1, 0)),
       "bottomright": ((0, 0), (1, 0), (0, 1)), "bottomleft": ((1, 0), (0, 1), (-1, 0))}


def _arc(name, x, y, r):
    (fx, fy), a, b = ARC[name]
    return x + fx * r, y + fy * r, a, b


def disc_path(name, x, y, r, rad):
    """Quarter disc of radius `rad` around the corner centre of the r-sized piece at (x, y)."""
    cx, cy, a, b = _arc(name, x, y, r)
    return (f"M{cx + a[0] * rad:g},{cy + a[1] * rad:g} A{rad:g},{rad:g} 0 0 1 {cx + b[0] * rad:g},{cy + b[1] * rad:g} "
            f"L{cx:g},{cy:g} Z")


def ring_path(name, x, y, r, outer, inner):
    """Quarter ring between radii `outer` and `inner` around the corner centre."""
    cx, cy, a, b = _arc(name, x, y, r)
    o, i = outer, max(0.0, inner)
    return (f"M{cx + a[0] * o:g},{cy + a[1] * o:g} A{o:g},{o:g} 0 0 1 {cx + b[0] * o:g},{cy + b[1] * o:g} "
            f"L{cx + b[0] * i:g},{cy + b[1] * i:g} A{i:g},{i:g} 0 0 0 {cx + a[0] * i:g},{cy + a[1] * i:g} Z")


def fill(colour, op, inset=0.0):
    """Frame layer: the rounded body, `inset` px in from the frame's edge."""
    return ("fill", inset, 0.0, colour, op)


def ring(colour, op, width=1.0, inset=0.0):
    """Frame layer: an outline `width` px wide, `inset` px in from the edge. `op` is one alpha
    or (top, sides, bottom), which gives the top edge a sheen like the bar islands have."""
    return ("ring", inset, width, colour, op)


def _edge_op(op, name):
    if not isinstance(op, tuple):
        return op
    top, side, bottom = op
    return top if name.startswith("top") else bottom if name.startswith("bottom") else side


def frame(prefix, ox, oy, r, layers, wash=0.0, margins=None, insets=None, mask=False, shadow=None):
    """One complete frame (nine pieces + hints, optional mask and shadow) as SVG elements.
    `wash`: a white sheen at the top that fades out halfway down."""
    p = (prefix + "-") if prefix else ""
    out = []
    wash_id = None
    if wash:
        wash_id = gid()
        DEFS.append(f'<linearGradient id="{wash_id}" x1="0" y1="0" x2="0" y2="1">'
                    f'<stop offset="0" style="stop-color:{SHEEN};stop-opacity:{wash}"/>'
                    f'<stop offset="0.5" style="stop-color:{SHEEN};stop-opacity:0"/></linearGradient>')
    for name, (x, y, w, h) in pieces(ox, oy, r).items():
        g = [bounds(x, y, w, h)]
        corner = name in CORNERS
        for kind, d, bw, colour, op in layers:
            if kind == "fill":
                if corner:
                    shape = f'<path d="{disc_path(name, x, y, r, r - d)}"'
                else:
                    rx, ry, rw, rh = {"top": (x, y + d, w, h - d), "bottom": (x, y, w, h - d),
                                      "left": (x + d, y, w - d, h), "right": (x, y, w - d, h)}.get(name, (x, y, w, h))
                    shape = f'<rect x="{rx:g}" y="{ry:g}" width="{rw:g}" height="{rh:g}"'
                g.append(f'{shape} {paint(colour, op)}/>')
                if wash_id and d == 0:
                    if name.startswith("top"):
                        g.append(f'{shape} style="fill:{SHEEN};fill-opacity:{wash}"/>')
                    elif name in ("left", "center", "right"):
                        g.append(f'{shape} style="fill:url(#{wash_id})"/>')
            else:
                if corner:
                    path = ring_path(name, x, y, r, r - d, r - d - bw)
                    if isinstance(op, tuple) and len(set(op)) > 1:
                        # fade the alpha along the corner, from the top (or bottom) edge to the side
                        i = gid()
                        a0, a1 = (op[0], op[1]) if name.startswith("top") else (op[1], op[2])
                        DEFS.append(f'<linearGradient id="{i}" gradientUnits="userSpaceOnUse" x1="0" y1="{y}" x2="0" y2="{y + r}">'
                                    f'<stop offset="0" {paint(colour, a0, "stop")}/><stop offset="1" {paint(colour, a1, "stop")}/>'
                                    f'</linearGradient>')
                        g.append(f'<path d="{path}" style="fill:url(#{i})"/>')
                    else:
                        g.append(f'<path d="{path}" {paint(colour, _edge_op(op, name))}/>')
                elif name != "center":
                    rx, ry, rw, rh = {"top": (x, y + d, w, bw), "bottom": (x, y + h - d - bw, w, bw),
                                      "left": (x + d, y, bw, h), "right": (x + w - d - bw, y, bw, h)}[name]
                    g.append(f'<rect x="{rx:g}" y="{ry:g}" width="{rw:g}" height="{rh:g}" {paint(colour, _edge_op(op, name))}/>')
        out.append(f'<g id="{p}{name}">{"".join(g)}</g>')
    if mask:
        mp = (prefix + "-mask-") if prefix else "mask-"
        for name, (x, y, w, h) in pieces(ox, oy + 3 * r + 2 * E + 20, r).items():
            shape = (f'<path d="{disc_path(name, x, y, r, r)}"' if name in CORNERS
                     else f'<rect x="{x}" y="{y}" width="{w}" height="{h}"')
            out.append(f'{shape} id="{mp}{name}" style="fill:#000"/>')
    # stretch (not tile) the edge pieces, so gradients and borders stay smooth
    out.append(f'<rect id="{p}hint-stretch-borders" x="{ox + 2 * r + E + 60}" y="{oy}" width="2" height="2" style="fill-opacity:0"/>')
    hx, hy = ox + 2 * r + E + 30, oy
    for kind, vals in (("margin", margins), ("inset", insets)):
        if vals is None:
            continue
        t, rr, bb, ll = vals
        hp = f"{p}hint-"
        off = 0 if kind == "margin" else 50
        # a zero-sized hint still counts: KSvg reads its width/height
        out += [f'<rect id="{hp}top-{kind}" x="{hx}" y="{hy + off}" width="4" height="{t}" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}bottom-{kind}" x="{hx + 6}" y="{hy + off}" width="4" height="{bb}" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}left-{kind}" x="{hx}" y="{hy + off + 30}" width="{ll}" height="4" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}right-{kind}" x="{hx}" y="{hy + off + 36}" width="{rr}" height="4" style="fill:#f0f;fill-opacity:0"/>']
    if shadow:
        out += shadow_tiles(prefix, ox + 200, oy, r, *shadow)
    return out


def overlay(prefix, ox, oy, r, layers):
    """A state frame drawn exactly over a base frame of radius r (hover, focus). Plasma places
    these outward by their own margins, and KSvg ignores a 0-size margin hint (it falls back to
    the corner size), so the frame is 1 px bigger with a 1 px hint and its layers sit 1 px in."""
    shifted = [(kind, d + 1, bw, colour, op) for kind, d, bw, colour, op in layers]
    return frame(prefix, ox, oy, r + 1, shifted, margins=(1, 1, 1, 1))


def shadow_tiles(prefix, ox, oy, r, size, alpha, dy=0):
    alpha *= SHADOW
    """Soft shadow around a rounded rect: radial corners + linear sides.
    `dy` pushes the shadow down (smaller top padding, larger bottom)."""
    p = (prefix + "-shadow-") if prefix else "shadow-"
    pads = {"top": max(2, size - dy), "bottom": size + dy, "left": size, "right": size}
    stops = [(0.0, 1.0), (0.2, 0.62), (0.45, 0.28), (0.7, 0.09), (1.0, 0.0)]

    def lin(direction):
        i = gid()
        x1, y1, x2, y2 = {"top": (0, 1, 0, 0), "bottom": (0, 0, 0, 1),
                          "left": (1, 0, 0, 0), "right": (0, 0, 1, 0)}[direction]
        s = "".join(f'<stop offset="{o}" style="stop-color:#000;stop-opacity:{alpha * a:.4f}"/>' for o, a in stops)
        DEFS.append(f'<linearGradient id="{i}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>')
        return i

    def rad(cx, cy, reach, inner):
        i = gid()
        f = inner / (inner + reach)
        s = (f'<stop offset="0" style="stop-color:#000;stop-opacity:0"/>'
             f'<stop offset="{max(0, f - 0.001):.4f}" style="stop-color:#000;stop-opacity:0"/>')
        s += "".join(f'<stop offset="{f + (1 - f) * o:.4f}" style="stop-color:#000;stop-opacity:{alpha * a:.4f}"/>'
                     for o, a in stops)
        DEFS.append(f'<radialGradient id="{i}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" '
                    f'r="{inner + reach}">{s}</radialGradient>')
        return i

    out = []
    T, B, L, R_ = pads["top"], pads["bottom"], pads["left"], pads["right"]
    # corner tiles cover padding + corner radius, so the shadow wraps the rounded corner
    tiles = {
        "topleft": (ox, oy, L + r, T + r, (ox + L + r, oy + T + r), max(L, T)),
        "topright": (ox + 100, oy, R_ + r, T + r, (ox + 100, oy + T + r), max(R_, T)),
        "bottomleft": (ox, oy + 100, L + r, B + r, (ox + L + r, oy + 100), max(L, B)),
        "bottomright": (ox + 100, oy + 100, R_ + r, B + r, (ox + 100, oy + 100), max(R_, B)),
    }
    for name, (x, y, w, h, (cx, cy), reach) in tiles.items():
        out.append(f'<rect id="{p}{name}" x="{x}" y="{y}" width="{w}" height="{h}" '
                   f'style="fill:url(#{rad(cx, cy, reach, r)})"/>')
    out += [
        f'<rect id="{p}top" x="{ox + 60}" y="{oy}" width="{E}" height="{T}" style="fill:url(#{lin("top")})"/>',
        f'<rect id="{p}bottom" x="{ox + 60}" y="{oy + 100}" width="{E}" height="{B}" style="fill:url(#{lin("bottom")})"/>',
        f'<rect id="{p}left" x="{ox}" y="{oy + 60}" width="{L}" height="{E}" style="fill:url(#{lin("left")})"/>',
        f'<rect id="{p}right" x="{ox + 100}" y="{oy + 60}" width="{R_}" height="{E}" style="fill:url(#{lin("right")})"/>',
    ]
    hp = p + "hint-"
    hx, hy = ox + 150, oy
    out += [f'<rect id="{hp}top-margin" x="{hx}" y="{hy}" width="2" height="{T}" style="fill-opacity:0"/>',
            f'<rect id="{hp}bottom-margin" x="{hx + 4}" y="{hy}" width="2" height="{B}" style="fill-opacity:0"/>',
            f'<rect id="{hp}left-margin" x="{hx}" y="{hy + 60}" width="{L}" height="2" style="fill-opacity:0"/>',
            f'<rect id="{hp}right-margin" x="{hx}" y="{hy + 64}" width="{R_}" height="2" style="fill-opacity:0"/>']
    return out


def soft_shadow(cx, cy, rad, alpha):
    """Radial shadow disc (for slider and switch handles)."""
    i = gid()
    DEFS.append(f'<radialGradient id="{i}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{rad}">'
                f'<stop offset="0.55" style="stop-color:#000;stop-opacity:{alpha}"/>'
                f'<stop offset="1" style="stop-color:#000;stop-opacity:0"/></radialGradient>')
    return f'<circle cx="{cx}" cy="{cy}" r="{rad}" style="fill:url(#{i})"/>'


def write(rel, elements, w=600, h=600):
    if not any('id="hint-stretch-borders"' in e for e in elements):
        elements = list(elements) + ['<rect id="hint-stretch-borders" x="590" y="590" width="2" height="2" style="fill-opacity:0"/>']
    path = OUT / (rel + ".svgz")
    path.parent.mkdir(parents=True, exist_ok=True)
    data = svg("".join(elements), w, h).encode()
    with gzip.open(path, "wb") as f:
        f.write(data)
    DEFS.clear()


# ---------- the recipe every frame shares ----------
# glass body in the scheme's background, a white hairline a touch brighter along the top (the bar
# islands' sheen), and a faint white wash fading down from the top
def glass(op, outline=(0.16, A["outline"], 0.07), wash=0.035):
    if LIGHT:
        # frost: a dark hairline heavier toward the bottom (light from above), a bright inner line
        # along the top and a stronger white wash
        return dict(layers=[fill(NEUTRAL, op * 0.94), ring(INK, (0.07, 0.11, 0.15)), ring(SHEEN, (0.9, 0.25, 0.0), 1, 1)],
                    wash=0.5)
    return dict(layers=[fill(NEUTRAL, op), ring(INK, outline)], wash=wash)


ON = 0.86        # "on" fills (meters, slider track, checked marks): neutral-bright, never the accent
TRACK = 0.12     # their empty track
FOCUS = 0.55     # keyboard focus rings


def build(variant="dark"):
    global OUT, NEUTRAL, INK, TICK, LIGHT, SHADOW
    v = VARIANTS[variant]
    OUT = OUT.parent / v["dir"]
    NEUTRAL, INK, TICK, LIGHT, SHADOW = v["NEUTRAL"], v["INK"], v["TICK"], v["LIGHT"], v["SHADOW"]
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    lg, md, sm, xs = RAD["lg"], RAD["md"], RAD["sm"], RAD["xs"]

    # Popups, notifications, OSD, KRunner. Content sits space.sm in, so a viewitem (radius sm)
    # nests inside the lg corner: lg - sm = 8
    for rel, op in (("dialogs/background", 0.97), ("translucent/dialogs/background", 0.80),
                    ("solid/dialogs/background", 1.0), ("opaque/dialogs/background", 1.0)):
        write(rel, frame("", 0, 0, lg, **glass(op), margins=(SP["sm"],) * 4, mask=True, shadow=(26, 0.42, 5)))

    # Tooltips
    for rel, op in (("widgets/tooltip", 0.97), ("translucent/widgets/tooltip", 0.86),
                    ("solid/widgets/tooltip", 1.0), ("opaque/widgets/tooltip", 1.0)):
        write(rel, frame("", 0, 0, sm, **glass(op, wash=0.03), margins=(SP["sm"], SP["md"], SP["sm"], SP["md"]),
                         mask=True, shadow=(16, 0.35, 3)))

    # Panel (Panel Colorizer paints the islands on top; this is the base and the blur mask)
    for rel, op in (("widgets/panel-background", 0.92), ("translucent/widgets/panel-background", 0.62),
                    ("solid/widgets/panel-background", 1.0), ("opaque/widgets/panel-background", 1.0)):
        write(rel, frame("", 0, 0, md, **glass(op, outline=(0.14, 0.09, 0.06)), margins=(5, 6, 5, 6),
                         mask=True, shadow=(20, 0.40, 3)))

    # Desktop widgets, Plasma menus and popups
    for rel, op in (("widgets/background", 0.88), ("translucent/widgets/background", 0.66),
                    ("solid/widgets/background", 1.0)):
        write(rel, frame("", 0, 0, lg, **glass(op), margins=(14, 14, 14, 14), mask=True, shadow=(22, 0.36, 4)))

    # Popup headings/footers: invisible, with a faint separator, so they never fight the rounded corners
    els = []
    for i, prefix in enumerate(("header", "footer")):
        ox = i * 120
        for name, (x, y, w, h) in pieces(ox, 0, 10).items():
            g = [bounds(x, y, w, h)]
            line_y = (y + h - 1) if prefix == "header" else y
            if (prefix == "header" and name in ("bottom",)) or (prefix == "footer" and name == "top"):
                g.append(f'<rect x="{x}" y="{line_y}" width="{w}" height="1" {paint(INK, 0.08)}/>')
            els.append(f'<g id="{prefix}-{name}">{"".join(g)}</g>')
    els += ['<rect id="hint-top-margin" x="300" y="0" width="4" height="6" style="fill-opacity:0"/>',
            '<rect id="hint-bottom-margin" x="306" y="0" width="4" height="6" style="fill-opacity:0"/>',
            '<rect id="hint-left-margin" x="300" y="20" width="6" height="4" style="fill-opacity:0"/>',
            '<rect id="hint-right-margin" x="300" y="26" width="6" height="4" style="fill-opacity:0"/>']
    write("widgets/plasmoidheading", els)

    # List items (KRunner results, the calendar, tray popups, menus): soft neutral pills
    els = []
    for i, (prefix, op, bop) in enumerate((("normal", 0.0, 0.0), ("hover", 0.06, 0.07),
                                           ("selected", 0.11, 0.14), ("selected+hover", 0.15, 0.18))):
        layers = [fill(INK, op), ring(INK, bop)] if op else []
        els += frame(prefix, i * 80, 0, sm, layers, margins=(SP["xs"], SP["sm"], SP["xs"], SP["sm"]))
    write("widgets/viewitem", els)

    # Older list items (PlasmaExtras.ListItem): same washes, plus section headers and a separator
    els = []
    for i, (prefix, op, bop) in enumerate((("normal", 0.0, 0.0), ("hover", 0.06, 0.07),
                                           ("pressed", 0.12, 0.14), ("section", 0.04, 0.0))):
        layers = ([fill(INK, op)] + ([ring(INK, bop)] if bop else [])) if op else []
        els += frame(prefix, i * 80, 0, sm, layers, margins=(SP["xs"], SP["sm"], SP["xs"], SP["sm"]))
    els.append(f'<rect id="separator" x="0" y="200" width="40" height="1" {paint(INK, 0.08)}/>')
    write("widgets/listitem", els)

    # Task manager buttons (Glimpse replaced the stock one; kept neutral for anything that uses it)
    els = []
    for i, (prefix, layers) in enumerate((
            ("normal", []),
            ("hover", [fill(INK, 0.06), ring(INK, 0.10)]),
            ("focus", [fill(INK, 0.12), ring(INK, 0.20)]),
            ("attention", [fill("ColorScheme-NeutralText", 0.22), ring("ColorScheme-NeutralText", 0.6)]),
            ("minimized", []),
            ("progress", [fill(INK, 0.18)]))):
        els += frame(prefix, i * 80, 0, sm, layers, margins=(4, 6, 4, 6) if prefix == "normal" else None)
    write("widgets/tasks", els, 900, 400)

    # Active tab: a soft neutral underline, inset from the ends. The panel puts it under the
    # applet whose popup is open (its island lights up too); tab bars (Kickoff's) under the
    # current tab.
    els = []
    for i, (prefix, edge) in enumerate((("south-active-tab", "bottom"), ("active-tab", "bottom"),
                                        ("north-active-tab", "top"))):
        for name, (x, y, w, h) in pieces(i * 100, 0, 12).items():
            g = [bounds(x, y, w, h)]
            if name == edge:
                ly = y + h - 2 if edge == "bottom" else y
                g.append(f'<rect x="{x}" y="{ly}" width="{w}" height="2" class="ColorScheme-Text" '
                         f'style="fill:currentColor;fill-opacity:0.55"/>')
            els.append(f'<g id="{prefix}-{name}">{"".join(g)}</g>')
    write("widgets/tabbar", els)

    # Buttons. Raised: a faint glass wash with a hairline; hover brightens the hairline, pressed
    # deepens the wash. Flat (toolbutton-*): nothing until hovered. Focus: a ring 2 px outside.
    # Corners are xs: CheckBox draws its 16 px box with the "normal" button frame.
    btn = (SP["xs"] + 2,) * 4
    els = []
    els += overlay("hover", 360, 0, xs, [fill(INK, 0.04), ring(INK, 0.26)])
    for i, (prefix, layers, margins) in enumerate((
            ("normal", [fill(INK, 0.06), ring(INK, (0.20, 0.13, 0.10))], btn),
            ("pressed", [fill(INK, 0.13), ring(INK, 0.18)], btn),
            ("toolbutton-hover", [fill(INK, A["hover"]), ring(INK, 0.10)], (SP["xs"],) * 4),
            ("toolbutton-pressed", [fill(INK, A["press"]), ring(INK, 0.14)], (SP["xs"],) * 4))):
        els += frame(prefix, (i % 3) * 120, (i // 3) * 120, xs, layers, margins=margins)
    for i, prefix in enumerate(("focus", "toolbutton-focus")):
        # 2 px outside the button: the frame is that much bigger, its corner concentric
        els += frame(prefix, i * 120, 260, xs + 2, [ring(INK, FOCUS, 1.5)], margins=(2, 2, 2, 2))
    write("widgets/button", els, 600, 400)

    # Text fields (KRunner, search boxes): a slightly lifted well. focus = typing (brighter edge),
    # focusframe = reached with the keyboard (plus a ring outside)
    le = (SP["xs"] + 2, SP["sm"], SP["xs"] + 2, SP["sm"])
    els = frame("base", 0, 0, sm, [fill(INK, 0.05), ring(INK, (0.14, 0.10, 0.08))], margins=le)
    els += overlay("hover", 120, 0, sm, [ring(INK, 0.22)])
    els += overlay("focus", 240, 0, sm, [fill(INK, 0.02), ring(INK, 0.34)])
    els += frame("focusframe", 360, 0, sm + 2, [fill(INK, 0.02, 2), ring(INK, 0.34, 1, 2), ring(INK, FOCUS, 1.5)],
                 margins=(2, 2, 2, 2))
    els.append('<rect id="hint-focus-over-base" x="500" y="300" width="2" height="2" style="fill-opacity:0"/>')
    write("widgets/lineedit", els, 600, 400)

    # Meters (the OSD, notification progress, the battery): 6 px pills, neutral-bright fill
    for rel in ("widgets/bar_meter_horizontal", "widgets/bar_meter_vertical"):
        els = frame("bar-inactive", 0, 0, 3, [fill(INK, TRACK)])
        els += frame("bar-active", 40, 0, 3, [fill(INK, ON)])
        els.append('<rect id="hint-bar-size" x="100" y="0" width="6" height="6" style="fill-opacity:0"/>')
        write(rel, els, 200, 100)

    # Slider: a 4 px track, the filled part neutral-bright, a white knob with a hairline and a soft
    # shadow; hover adds a halo, focus a ring
    els = frame("groove", 0, 0, 2, [fill(INK, TRACK)])
    els += frame("groove-highlight", 40, 0, 2, [fill(INK, ON)])
    els.append('<rect id="hint-handle-size" x="100" y="0" width="18" height="18" style="fill-opacity:0"/>')
    for j, orient in enumerate(("horizontal", "vertical")):
        y = 60 + j * 40
        els += [f'<g id="{orient}-slider-handle">{bounds(0, y, 18, 18)}'
                f'<circle cx="9" cy="{y + 9}" r="8" {paint("#f4f5f8", 1)}/>'
                f'<circle cx="9" cy="{y + 9}" r="7.5" style="fill:none;stroke:{BLACK};stroke-opacity:0.28;stroke-width:1"/></g>',
                f'<g id="{orient}-slider-hover">{bounds(40, y - 4, 26, 26)}'
                f'<circle cx="53" cy="{y + 9}" r="11.5" style="fill:none;stroke:{INK};stroke-opacity:0.16;stroke-width:3"/></g>',
                f'<g id="{orient}-slider-focus">{bounds(80, y - 3, 24, 24)}'
                f'<circle cx="92" cy="{y + 9}" r="11" style="fill:none;stroke:{INK};stroke-opacity:{FOCUS};stroke-width:1.5"/></g>',
                f'<g id="{orient}-slider-shadow">{bounds(120, y - 4, 26, 26)}{soft_shadow(133, y + 10, 12, 0.32)}</g>']
    write("widgets/slider", els, 200, 200)

    # Scroll bars: a slim 6 px pill, a faint track only while hovered
    els = frame("slider", 0, 0, 3, [fill(INK, 0.26)], insets=(4, 4, 4, 4))
    els += frame("mouseover-slider", 40, 0, 3, [fill(INK, 0.46)], insets=(4, 4, 4, 4))
    for j, orient in enumerate(("horizontal", "vertical")):
        els += frame(f"background-{orient}", 80 + j * 50, 0, 5, [fill(INK, 0.05)], insets=(2, 2, 2, 2))
    els.append('<rect id="hint-scrollbar-size" x="200" y="0" width="6" height="6" style="fill-opacity:0"/>')
    write("widgets/scrollbar", els, 300, 200)

    # Switch: off = dim knob on a dark track; on = the track lights up, the knob goes dark.
    # Hovered/focused the knob is white with a dark hairline, which reads on either track.
    def pill3(prefix, y, op, hair):
        """The three pieces (left/center/right) of an 18 px tall pill, with an optional hairline."""
        cap_l, cap_r = f"M9,{y} A9,9 0 0 0 9,{y + 18} Z", f"M21,{y} A9,9 0 0 1 21,{y + 18} Z"
        line_l = f"M9,{y} A9,9 0 0 0 9,{y + 18} L9,{y + 17} A8,8 0 0 1 9,{y + 1} Z"
        line_r = f"M21,{y} A9,9 0 0 1 21,{y + 18} L21,{y + 17} A8,8 0 0 0 21,{y + 1} Z"
        h = (lambda d: f'<path d="{d}" {paint(INK, hair)}/>') if hair else (lambda d: "")
        hc = (f'<rect x="10" y="{y}" width="10" height="1" {paint(INK, hair)}/>'
              f'<rect x="10" y="{y + 17}" width="10" height="1" {paint(INK, hair)}/>') if hair else ""
        return [f'<g id="{prefix}-left">{bounds(0, y, 9, 18)}<path d="{cap_l}" {paint(INK, op)}/>{h(line_l)}</g>',
                f'<g id="{prefix}-center">{bounds(10, y, 10, 18)}<rect x="10" y="{y}" width="10" height="18" {paint(INK, op)}/>{hc}</g>',
                f'<g id="{prefix}-right">{bounds(21, y, 9, 18)}<path d="{cap_r}" {paint(INK, op)}/>{h(line_r)}</g>']

    els = pill3("inactive", 0, TRACK, 0.10) + pill3("active", 30, ON, 0)
    knob = {  # id: (fill colour, alpha, hairline alpha)
        "handle": ("#f4f5f8", 0.78, 0.22 if LIGHT else 0.0), "handle-active": (BG, 1.0, 0.0),
        "handle-hover": ("#ffffff", 1.0, 0.35), "handle-pressed": ("#e4e6ec", 1.0, 0.35)}
    for k, (kid, (colour, op, hair)) in enumerate(knob.items()):
        x = 40 + k * 24
        els.append(f'<g id="{kid}">{bounds(x, 60, 18, 18)}<circle cx="{x + 9}" cy="69" r="7" {paint(colour, op)}/>'
                   + (f'<circle cx="{x + 9}" cy="69" r="6.5" style="fill:none;stroke:{BLACK};stroke-opacity:{hair};stroke-width:1"/>' if hair else "")
                   + '</g>')
    els.append(f'<g id="handle-focus">{bounds(40, 90, 26, 26)}'
               f'<circle cx="53" cy="103" r="11.5" style="fill:none;stroke:{INK};stroke-opacity:{FOCUS};stroke-width:1.5"/></g>')
    els.append(f'<g id="handle-shadow">{bounds(80, 90, 26, 26)}{soft_shadow(93, 104, 11, 0.22)}</g>')
    els.append('<rect id="hint-bar-size" x="150" y="0" width="36" height="18" style="fill-opacity:0"/>')
    write("widgets/switch", els, 200, 140)

    # Check marks. The check box is the 16 px "normal" button; checked, a bright rounded square
    # with a dark tick covers it
    els = [f'<g id="checkbox">{bounds(0, 0, 16, 16)}<rect x="0" y="0" width="16" height="16" rx="{xs}" {paint(INK, ON)}/>'
           f'<path d="M4.2,8.4 L6.9,11 L11.9,5.4" style="fill:none;stroke:{TICK};stroke-width:2;stroke-linecap:round;stroke-linejoin:round"/></g>',
           f'<g id="radiobutton">{bounds(0, 20, 16, 16)}<circle cx="8" cy="28" r="8" {paint(INK, ON)}/>'
           f'<circle cx="8" cy="28" r="3" style="fill:{TICK}"/></g>']
    write("widgets/checkmarks", els, 40, 40)

    # Radio buttons: the same language, round
    els = [f'<g id="normal">{bounds(0, 0, 16, 16)}<circle cx="8" cy="8" r="8" {paint(INK, 0.06)}/>'
           f'<circle cx="8" cy="8" r="7.5" style="fill:none;stroke:{INK};stroke-opacity:0.18;stroke-width:1"/></g>',
           f'<g id="checked">{bounds(20, 0, 16, 16)}<circle cx="28" cy="8" r="8" {paint(INK, ON)}/></g>',
           f'<g id="hover">{bounds(40, 0, 16, 16)}<circle cx="48" cy="8" r="7.5" style="fill:none;stroke:{INK};stroke-opacity:0.34;stroke-width:1"/></g>',
           f'<g id="focus">{bounds(60, -2, 20, 20)}<circle cx="70" cy="8" r="9.25" style="fill:none;stroke:{INK};stroke-opacity:{FOCUS};stroke-width:1.5"/></g>',
           f'<g id="shadow">{bounds(90, -3, 22, 22)}{soft_shadow(101, 9, 10, 0.18)}</g>',
           f'<circle id="symbol" cx="130" cy="8" r="3" style="fill:{TICK}"/>',
           '<rect id="hint-size" x="150" y="0" width="16" height="16" style="fill-opacity:0"/>']
    write("widgets/radiobutton", els, 200, 40)

    # Busy indicator: a neutral arc on a faint track (BusyIndicator rotates it)
    els = [f'<g id="busywidget">{bounds(0, 0, 36, 36)}'
           f'<circle cx="18" cy="18" r="15" style="fill:none;stroke:{INK};stroke-opacity:{TRACK};stroke-width:3"/>'
           f'<path d="M18,3 A15,15 0 0 1 33,18" style="fill:none;stroke:{INK};stroke-opacity:{ON};stroke-width:3;stroke-linecap:round"/></g>']
    write("widgets/busywidget", els, 40, 40)

    (OUT / "metadata.json").write_text(json.dumps({
        "KPlugin": {
            "Authors": [{"Name": "zinoxx"}],
            "Description": "Rounded, translucent, neutral glass. Generated by ~/.config/plasma-rice/plasma-style/build.py",
            "Id": v["dir"], "License": "MIT", "Name": v["name"], "Version": "1.1",
        },
        "X-Plasma-API": "5.0",
    }, indent=2))
    (OUT / "plasmarc").write_text(
        ("[ContrastEffect]\nenabled=true\ncontrast=0.25\nintensity=1.8\nsaturation=1.6\n\n" if LIGHT else
         "[ContrastEffect]\nenabled=true\ncontrast=0.35\nintensity=0.9\nsaturation=1.9\n\n") +
        "[BlurBehindEffect]\nenabled=true\n\n"
        "[AdaptiveTransparency]\nenabled=true\n")
    print("built", OUT)


if __name__ == "__main__":
    for variant in VARIANTS:
        build(variant)
