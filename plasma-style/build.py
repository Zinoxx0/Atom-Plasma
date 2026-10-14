#!/usr/bin/env python3
"""Generate the "Rice" Plasma Style (desktoptheme) into ~/.local/share/plasma/desktoptheme/Rice.

Rounded, translucent frames with an accent-tinted hairline border and soft
shadows, in the spirit of HyDE. Colours come from the active colour scheme
(ColorScheme-* classes), so the style follows the wallpaper palette with no
regeneration needed. Re-run after editing the numbers below.
"""
import gzip
import json
import shutil
from pathlib import Path

OUT = Path.home() / ".local/share/plasma/desktoptheme/Rice"
E = 10  # length of the stretchable edge pieces in the source SVG

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


def pieces(ox, oy, r):
    """Rects (x, y, w, h) of the nine frame pieces with corner size r."""
    return {
        "topleft": (ox, oy, r, r), "top": (ox + r, oy, E, r), "topright": (ox + r + E, oy, r, r),
        "left": (ox, oy + r, r, E), "center": (ox + r, oy + r, E, E), "right": (ox + r + E, oy + r, r, E),
        "bottomleft": (ox, oy + r + E, r, r), "bottom": (ox + r, oy + r + E, E, r),
        "bottomright": (ox + r + E, oy + r + E, r, r),
    }


def corner_path(name, x, y, r, inset=0.0):
    """Quarter disc filling the corner piece at (x, y), shrunk by `inset`."""
    R = r - inset
    if name == "topleft":
        cx, cy = x + r, y + r
        return f"M{cx - R},{cy} A{R},{R} 0 0 1 {cx},{cy - R} L{cx},{cy} Z"
    if name == "topright":
        cx, cy = x, y + r
        return f"M{cx},{cy - R} A{R},{R} 0 0 1 {cx + R},{cy} L{cx},{cy} Z"
    if name == "bottomleft":
        cx, cy = x + r, y
        return f"M{cx},{cy + R} A{R},{R} 0 0 1 {cx - R},{cy} L{cx},{cy} Z"
    cx, cy = x, y  # bottomright
    return f"M{cx + R},{cy} A{R},{R} 0 0 1 {cx},{cy + R} L{cx},{cy} Z"


def ring_path(name, x, y, r, b):
    """Border ring of width b along the rounded corner."""
    o, i = r, r - b
    if name == "topleft":
        cx, cy = x + r, y + r
        return (f"M{cx - o},{cy} A{o},{o} 0 0 1 {cx},{cy - o} L{cx},{cy - i} "
                f"A{i},{i} 0 0 0 {cx - i},{cy} Z")
    if name == "topright":
        cx, cy = x, y + r
        return (f"M{cx},{cy - o} A{o},{o} 0 0 1 {cx + o},{cy} L{cx + i},{cy} "
                f"A{i},{i} 0 0 0 {cx},{cy - i} Z")
    if name == "bottomleft":
        cx, cy = x + r, y
        return (f"M{cx},{cy + o} A{o},{o} 0 0 1 {cx - o},{cy} L{cx - i},{cy} "
                f"A{i},{i} 0 0 0 {cx},{cy + i} Z")
    cx, cy = x, y
    return (f"M{cx + o},{cy} A{o},{o} 0 0 1 {cx},{cy + o} L{cx},{cy + i} "
            f"A{i},{i} 0 0 0 {cx + i},{cy} Z")


def edge_border(name, x, y, w, h, b):
    return {"top": (x, y, w, b), "bottom": (x, y + h - b, w, b),
            "left": (x, y, b, h), "right": (x + w - b, y, b, h)}.get(name)


def frame(prefix, ox, oy, r, fill="ColorScheme-Background", fill_op=0.8,
          border="ColorScheme-Highlight", border_op=0.3, b=1.0, wash_op=0.0,
          margins=None, mask=True, shadow=None, center_fill=True):
    """One complete frame (pieces + mask + hints + shadow) as SVG elements."""
    p = (prefix + "-") if prefix else ""
    out = []
    wash = None
    if wash_op:
        wash = gid()
        DEFS.append(f'<linearGradient id="{wash}" x1="0" y1="0" x2="0" y2="1">'
                    f'<stop offset="0" class="ColorScheme-Highlight" style="stop-color:currentColor;stop-opacity:{wash_op}"/>'
                    f'<stop offset="0.5" class="ColorScheme-Highlight" style="stop-color:currentColor;stop-opacity:0"/>'
                    f'</linearGradient>')
    for name, (x, y, w, h) in pieces(ox, oy, r).items():
        g = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>']
        corner = name in ("topleft", "topright", "bottomleft", "bottomright")
        if fill and (center_fill or name != "center"):
            shape = (f'<path d="{corner_path(name, x, y, r)}"' if corner
                     else f'<rect x="{x}" y="{y}" width="{w}" height="{h}"')
            g.append(f'{shape} class="{fill}" style="fill:currentColor;fill-opacity:{fill_op}"/>')
            if wash and name.startswith("top"):
                g.append(f'{shape} class="ColorScheme-Highlight" style="fill:currentColor;fill-opacity:{wash_op}"/>')
            elif wash and name in ("left", "center", "right"):
                g.append(f'{shape} style="fill:url(#{wash})"/>')
        if border and border_op:
            if corner:
                g.append(f'<path d="{ring_path(name, x, y, r, b)}" class="{border}" '
                         f'style="fill:currentColor;fill-opacity:{border_op}"/>')
            else:
                eb = edge_border(name, x, y, w, h, b)
                if eb:
                    g.append(f'<rect x="{eb[0]}" y="{eb[1]}" width="{eb[2]}" height="{eb[3]}" class="{border}" '
                             f'style="fill:currentColor;fill-opacity:{border_op}"/>')
        out.append(f'<g id="{p}{name}">{"".join(g)}</g>')
    if mask:
        mp = (prefix + "-mask-") if prefix else "mask-"
        for name, (x, y, w, h) in pieces(ox, oy + 3 * r + 2 * E + 20, r).items():
            corner = name in ("topleft", "topright", "bottomleft", "bottomright")
            shape = (f'<path d="{corner_path(name, x, y, r)}"' if corner
                     else f'<rect x="{x}" y="{y}" width="{w}" height="{h}"')
            out.append(f'{shape} id="{mp}{name}" style="fill:#000"/>')
    # stretch (not tile) the edge pieces, so gradients and borders stay smooth
    out.append(f'<rect id="{p}hint-stretch-borders" x="{ox + 2 * r + E + 60}" y="{oy}" width="2" height="2" style="fill-opacity:0"/>')
    if margins is not None:
        hp = p + "hint-"
        t, rr, bb, ll = margins
        hx, hy = ox + 2 * r + E + 30, oy
        out += [f'<rect id="{hp}top-margin" x="{hx}" y="{hy}" width="4" height="{t}" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}bottom-margin" x="{hx + 6}" y="{hy}" width="4" height="{bb}" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}left-margin" x="{hx}" y="{hy + 30}" width="{ll}" height="4" style="fill:#f0f;fill-opacity:0"/>',
                f'<rect id="{hp}right-margin" x="{hx}" y="{hy + 36}" width="{rr}" height="4" style="fill:#f0f;fill-opacity:0"/>']
    if shadow:
        out += shadow_tiles(prefix, ox + 200, oy, r, *shadow)
    return out


def shadow_tiles(prefix, ox, oy, r, size, alpha, dy=0):
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


def write(rel, elements, w=600, h=600):
    if not any('id="hint-stretch-borders"' in e for e in elements):
        elements = list(elements) + ['<rect id="hint-stretch-borders" x="590" y="590" width="2" height="2" style="fill-opacity:0"/>']
    path = OUT / (rel + ".svgz")
    path.parent.mkdir(parents=True, exist_ok=True)
    data = svg("".join(elements), w, h).encode()
    with gzip.open(path, "wb") as f:
        f.write(data)
    DEFS.clear()


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    # Popups, notifications, KRunner
    for rel, op in (("dialogs/background", 0.97), ("translucent/dialogs/background", 0.80),
                    ("solid/dialogs/background", 1.0)):
        write(rel, frame("", 0, 0, 18, fill_op=op, border_op=0.32, wash_op=0.07 if op < 1 else 0.05,
                         margins=(10, 10, 10, 10), shadow=(26, 0.42, 5)))

    # Tooltips
    for rel, op in (("widgets/tooltip", 0.97), ("translucent/widgets/tooltip", 0.86),
                    ("solid/widgets/tooltip", 1.0), ("opaque/widgets/tooltip", 1.0)):
        write(rel, frame("", 0, 0, 12, fill_op=op, border_op=0.28, margins=(8, 10, 8, 10), shadow=(16, 0.35, 3)))

    # Panel (Panel Colorizer paints the islands on top; this is the base and the blur mask)
    for rel, op in (("widgets/panel-background", 0.92), ("translucent/widgets/panel-background", 0.62),
                    ("solid/widgets/panel-background", 1.0), ("opaque/widgets/panel-background", 1.0)):
        write(rel, frame("", 0, 0, 16, fill_op=op, border_op=0.22, margins=(5, 6, 5, 6), shadow=(20, 0.40, 3)))

    # Desktop widgets
    for rel, op in (("widgets/background", 0.88), ("translucent/widgets/background", 0.66),
                    ("solid/widgets/background", 1.0)):
        write(rel, frame("", 0, 0, 20, fill_op=op, border_op=0.22, margins=(14, 14, 14, 14), shadow=(22, 0.36, 4)))

    # Popup headings/footers: invisible, with a faint separator, so they never fight the rounded corners
    els = []
    for i, prefix in enumerate(("header", "footer")):
        ox = i * 120
        for name, (x, y, w, h) in pieces(ox, 0, 10).items():
            g = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>']
            line_y = (y + h - 1) if prefix == "header" else y
            if (prefix == "header" and name in ("bottom",)) or (prefix == "footer" and name == "top"):
                g.append(f'<rect x="{x}" y="{line_y}" width="{w}" height="1" class="ColorScheme-Text" '
                         f'style="fill:currentColor;fill-opacity:0.10"/>')
            els.append(f'<g id="{prefix}-{name}">{"".join(g)}</g>')
    els += ['<rect id="hint-top-margin" x="300" y="0" width="4" height="6" style="fill-opacity:0"/>',
            '<rect id="hint-bottom-margin" x="306" y="0" width="4" height="6" style="fill-opacity:0"/>',
            '<rect id="hint-left-margin" x="300" y="20" width="6" height="4" style="fill-opacity:0"/>',
            '<rect id="hint-right-margin" x="300" y="26" width="6" height="4" style="fill-opacity:0"/>']
    write("widgets/plasmoidheading", els)

    # List items (Kickoff, tray popups, KRunner results): soft rounded pills
    els = []
    for i, (prefix, op, bop) in enumerate((("normal", 0.0, 0.0), ("hover", 0.14, 0.30),
                                           ("selected", 0.26, 0.45), ("selected+hover", 0.32, 0.55))):
        els += frame(prefix, i * 80, 0, 9, fill="ColorScheme-Highlight", fill_op=op, border_op=bop,
                     mask=False, margins=(4, 8, 4, 8))
    els.append('<rect id="hint-tile" x="500" y="500" width="2" height="2" style="fill-opacity:0"/>')
    write("widgets/viewitem", els)

    # Task manager buttons
    els = []
    for i, (prefix, fill, op, border, bop) in enumerate((
            ("normal", None, 0.0, None, 0.0),
            ("hover", "ColorScheme-Text", 0.08, "ColorScheme-Text", 0.12),
            ("focus", "ColorScheme-Highlight", 0.20, "ColorScheme-Highlight", 0.55),
            ("attention", "ColorScheme-NeutralText", 0.22, "ColorScheme-NeutralText", 0.6),
            ("minimized", None, 0.0, None, 0.0),
            ("progress", "ColorScheme-Highlight", 0.30, None, 0.0))):
        els += frame(prefix, i * 80, 0, 10, fill=fill, fill_op=op, border=border, border_op=bop, mask=False,
                     margins=(4, 6, 4, 6) if prefix == "normal" else None)
    write("widgets/tasks", els, 900, 400)

    # Active tab: a soft neutral underline, inset from the ends. The panel puts it under the
    # applet whose popup is open (its island lights up too); tab bars (Kickoff's) under the
    # current tab. Neutral, because the scheme's highlight follows another screen's wallpaper.
    els = []
    for i, (prefix, edge) in enumerate((("south-active-tab", "bottom"), ("active-tab", "bottom"),
                                        ("north-active-tab", "top"))):
        for name, (x, y, w, h) in pieces(i * 100, 0, 12).items():
            g = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>']
            if name == edge:
                ly = y + h - 2 if edge == "bottom" else y
                g.append(f'<rect x="{x}" y="{ly}" width="{w}" height="2" class="ColorScheme-Text" '
                         f'style="fill:currentColor;fill-opacity:0.55"/>')
            els.append(f'<g id="{prefix}-{name}">{"".join(g)}</g>')
    write("widgets/tabbar", els)

    (OUT / "metadata.json").write_text(json.dumps({
        "KPlugin": {
            "Authors": [{"Name": "zinoxx"}],
            "Description": "Rounded, translucent, wallpaper-coloured. Generated by ~/.config/plasma-rice/plasma-style/build.py",
            "Id": "Rice", "License": "MIT", "Name": "Rice", "Version": "1.0",
        },
        "X-Plasma-API": "5.0",
    }, indent=2))
    (OUT / "plasmarc").write_text(
        "[ContrastEffect]\nenabled=true\ncontrast=0.35\nintensity=0.9\nsaturation=1.9\n\n"
        "[BlurBehindEffect]\nenabled=true\n\n"
        "[AdaptiveTransparency]\nenabled=true\n")
    print("built", OUT)


if __name__ == "__main__":
    build()
