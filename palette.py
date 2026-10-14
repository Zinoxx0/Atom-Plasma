"""Wallpaper -> palette for the Plasma rice.

matugen picks the wallpaper's colours (Material You); this module then pulls the
result into a darker, Tokyo Night shaped palette:

  * surfaces use Tokyo Night's lightness ladder (deep navy-black), tinted with
    a blend of the wallpaper hue and Tokyo Night's indigo
  * accents keep the wallpaper's hues but get candy-level lightness/chroma
  * terminal colours are Tokyo Night's, nudged a little toward the wallpaper

Everything is done in OKLCH so lightness steps look even.
"""
import json
import math
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent

TOKYO = {
    "bg": "#1a1b26", "fg": "#c0caf5", "comment": "#565f89",
    "red": "#f7768e", "orange": "#ff9e64", "yellow": "#e0af68", "green": "#9ece6a",
    "teal": "#73daca", "cyan": "#7dcfff", "blue": "#7aa2f7", "magenta": "#bb9af7",
}
TOKYO_HUE = 277.0          # hue of Tokyo Night's backgrounds


# ---------------------------------------------------------------- colour maths
def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb_hex(rgb):
    return "#" + "".join(f"{round(max(0, min(1, c)) * 255):02x}" for c in rgb)


def to_oklch(h):
    r, g, b = (_lin(c) for c in hex_rgb(h))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def _oklch_rgb(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def oklch(L, C, H):
    """OKLCH -> hex, reducing chroma until the colour fits in sRGB."""
    for _ in range(40):
        rgb = _oklch_rgb(L, C, H)
        if all(-1e-4 <= c <= 1 + 1e-4 for c in rgb):
            break
        C *= 0.93
    return rgb_hex(tuple(_gam(max(0.0, min(1.0, c))) for c in rgb))


def mix(a, b, t):
    """Mix two hex colours in linear light (t=0 -> a, t=1 -> b)."""
    ra, rb = [tuple(_lin(c) for c in hex_rgb(x)) for x in (a, b)]
    return rgb_hex(tuple(_gam(x + (y - x) * t) for x, y in zip(ra, rb)))


def hue_toward(h, target, t):
    d = ((target - h + 180) % 360) - 180
    return (h + d * t) % 360


def rgb_csv(h):
    return ",".join(str(round(c * 255)) for c in hex_rgb(h))


# ---------------------------------------------------------------- palette
def matugen(image, scheme):
    out = subprocess.run(
        ["matugen", "image", str(image), "-m", "dark", "-t", scheme,
         "-c", str(HERE / "matugen.toml"), "-j", "hex", "--dry-run"],
        check=True, capture_output=True, text=True).stdout
    return {k: v["default"]["color"] for k, v in json.loads(out)["colors"].items()}


def build(m, settings):
    """m: matugen colours (name -> hex). Returns the rice palette (name -> hex)."""
    tint = settings.get("tokyo_tint", 0.6)       # 0 = pure wallpaper hue, 1 = pure Tokyo Night
    depth = settings.get("depth", 0.0)            # extra darkness for surfaces (OKLCH L)
    candy = settings.get("candy", 1.0)            # accent chroma multiplier

    _, src_c, src_h = to_oklch(m["primary"])
    surf_h = hue_toward(src_h, TOKYO_HUE, tint)
    # grey wallpapers stay neutral-ish; colourful ones get a richer tint
    surf_c = 0.012 + 0.022 * min(1.0, src_c / 0.09)

    p = {}
    ladder = {
        "surface_lowest": 0.155, "background": 0.185, "surface": 0.205,
        "surface_low": 0.222, "surface_container": 0.240, "surface_high": 0.272,
        "surface_highest": 0.305, "outline_variant": 0.370, "outline": 0.520,
    }
    for name, L in ladder.items():
        c = surf_c * (1.6 if name.startswith("outline") else 1.0)
        p[name] = oklch(L - depth, c, surf_h)
    p["on_surface"] = oklch(0.900, 0.030, surf_h)
    p["on_surface_variant"] = oklch(0.760, 0.040, surf_h)
    p["muted"] = oklch(0.580, 0.050, surf_h)

    # accents: wallpaper hues, Tokyo Night brightness
    for role, L, Cmin in (("primary", 0.780, 0.110), ("secondary", 0.800, 0.070),
                          ("tertiary", 0.790, 0.100)):
        _, c, h = to_oklch(m[role])
        C = max(c, Cmin) * candy
        p[role] = oklch(L, C, h)
        p[f"{role}_container"] = oklch(0.360, C * 0.55, h)
        p[f"on_{role}"] = oklch(0.220, C * 0.35, h)
        p[f"on_{role}_container"] = oklch(0.900, C * 0.35, h)
        p[f"{role}_dim"] = oklch(0.640, C * 0.85, h)

    # terminal / status colours: Tokyo Night, harmonised a little toward the accent
    _, _, acc_h = to_oklch(p["primary"])
    for name in ("red", "orange", "yellow", "green", "teal", "cyan", "blue", "magenta"):
        L, C, h = to_oklch(TOKYO[name])
        d = ((acc_h - h + 180) % 360) - 180
        h2 = (h + max(-12, min(12, d * 0.25))) % 360
        p[name] = oklch(L, C, h2)
        p[f"{name}_bright"] = oklch(min(0.93, L + 0.06), C * 0.9, h2)
        p[f"{name}_dim"] = oklch(L - 0.12, C * 0.9, h2)
    p["error"] = p["red"]
    p["claude"] = "#d97757"
    p["shadow"] = "#000000"
    return p
