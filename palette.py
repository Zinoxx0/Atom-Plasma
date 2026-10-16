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


# ================================================================ v2: colours with the wallpaper's character
# matugen's Material You tones, lifted to one pastel lightness over a fixed navy ladder, made every
# wallpaper look alike (a red one came out peach, white and black ones lavender). v2 reads the
# wallpaper itself in OKLab and keeps its character:
#
#   neon      vivid wallpapers: accents at the edge of the gamut (red -> blood/neon red, purple ->
#             bright violet), dark surfaces tinted with the hue
#   soft      calm, dusky ones: their true hues, softer, on the dark ladder
#   light     white or calm-light ones: a light, frosted UI with silver (or pastel) accents
#   void      black ones: true-black surfaces, starlight-white accents, glow only where it's active
#   graphite  grey ones: silver on dark
#
# The output keeps v1's keys (every consumer reads those), plus _mood, _scheme, _glow, _edge,
# _swatches and _analysis for the Theme page.

def _lab(r, g, b):
    """sRGB 0..255 -> OKLab."""
    r, g, b = (_lin(c / 255) for c in (r, g, b))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def _lab_hex(L, a, b):
    return oklch(L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360)


def analyse(img, k=6):
    """The wallpaper's character: mean lightness and chroma, how much of it is vivid, its
    chroma-weighted hue, and k colour clusters (k-means in OKLab), heaviest first."""
    from PIL import Image
    im = Image.open(img).convert("RGB")
    im.thumbnail((96, 96))
    raw = im.tobytes()
    px = [_lab(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]
    n = len(px)
    chroma = [math.hypot(p[1], p[2]) for p in px]
    L = sum(p[0] for p in px) / n
    C = sum(chroma) / n
    vivid = sum(1 for c in chroma if c > 0.10) / n
    sa, sb = sum(p[1] for p in px), sum(p[2] for p in px)
    hue = math.degrees(math.atan2(sb, sa)) % 360
    # how much of the colour points one way (1 = one hue throughout, 0 = opposite hues cancelling)
    consistency = math.hypot(sa, sb) / max(1e-9, sum(chroma))

    # k-means, seeded deterministically from lightness quantiles
    order = sorted(range(n), key=lambda i: px[i][0])
    cent = [px[order[int((j + 0.5) * n / k)]] for j in range(k)]
    for _ in range(10):
        sums = [[0.0, 0.0, 0.0, 0] for _ in range(k)]
        for p in px:
            j = min(range(k), key=lambda j: (p[0] - cent[j][0]) ** 2 + (p[1] - cent[j][1]) ** 2 + (p[2] - cent[j][2]) ** 2)
            s = sums[j]
            s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; s[3] += 1
        cent = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) if s[3] else cent[j] for j, s in enumerate(sums)]
    weights = [s[3] / n for s in sums]
    clusters = sorted(({"L": c[0], "C": math.hypot(c[1], c[2]), "H": math.degrees(math.atan2(c[2], c[1])) % 360,
                        "w": w, "hex": _lab_hex(*c)} for c, w in zip(cent, weights) if w > 0),
                      key=lambda c: -c["w"])
    return {"L": L, "C": C, "vivid": vivid, "hue": hue, "consistency": consistency, "clusters": clusters}


MOODS = ("neon", "soft", "light", "void", "graphite")


def mood_of(a):
    if a["C"] < 0.02:                       # no colour to speak of
        return "light" if a["L"] >= 0.62 else "void" if a["L"] <= 0.35 else "graphite"
    if a["L"] >= 0.72 and a["C"] < 0.13:   # light and only moderately coloured: pastel, on the light UI
        return "light"
    if a["vivid"] >= 0.30 or a["C"] >= 0.09:
        return "neon"
    return "soft"


def _hue_dist(a, b):
    return abs((a - b + 180) % 360 - 180)


def _cmax(L, H):
    """The most chroma sRGB allows at this lightness and hue."""
    lo, hi = 0.0, 0.4
    for _ in range(18):
        mid = (lo + hi) / 2
        if all(-1e-4 <= c <= 1 + 1e-4 for c in _oklch_rgb(L, mid, H)):
            lo = mid
        else:
            hi = mid
    return lo


def _accent_hues(a):
    """Primary, secondary and tertiary hues (and the clusters' chroma): the strongest chromatic
    cluster first, then the next ones at least 30 degrees away; a one-hue wallpaper gets a
    tight family around its hue (a bright neighbour and a deep one)."""
    chromatic = [c for c in a["clusters"] if c["C"] > 0.04]
    if not chromatic:
        return [(a["hue"], 0.0)] * 3, True
    chromatic.sort(key=lambda c: -(c["w"] ** 0.6) * c["C"])
    # a wallpaper whose colour mostly points one way reads as that hue (a navy-and-magenta one as
    # violet), even if its biggest cluster sits off to one side
    if a.get("consistency", 0) >= 0.55:
        lead = dict(min(chromatic, key=lambda c: _hue_dist(c["H"], a["hue"])), H=a["hue"])
        chromatic = [lead] + [c for c in chromatic if _hue_dist(c["H"], a["hue"]) >= 30]
    picks = [chromatic[0]]
    for c in chromatic[1:]:
        if all(_hue_dist(c["H"], p["H"]) >= 30 for p in picks) and c["w"] >= 0.04:
            picks.append(c)
        if len(picks) == 3:
            break
    h0, c0 = picks[0]["H"], picks[0]["C"]
    mono = len(picks) == 1
    if mono:
        return [(h0, c0), ((h0 + 5) % 360, c0), ((h0 - 10) % 360, c0)], True
    if len(picks) == 2:
        return [(h0, c0), ((h0 + 5) % 360, c0), (picks[1]["H"], picks[1]["C"])], False
    return [(p["H"], p["C"]) for p in picks], False


def _neon_L(h):
    """Lightness at which a hue looks most vivid on dark: yellows and greens need more of it."""
    if 75 <= h < 150:
        return 0.82
    if 150 <= h < 215:
        return 0.78
    if 215 <= h < 275:
        return 0.63
    if 275 <= h < 330:
        return 0.62
    return 0.64


def build_v2(a, settings=None, ov=None):
    """a: analyse(); ov: Theme page overrides {mood, primary, secondary, tertiary, intensity}.
    Returns the rice palette (v1 keys + meta)."""
    settings = settings or {}
    ov = ov or {}
    mood = ov.get("mood") if ov.get("mood") in MOODS else mood_of(a)
    k = float(ov.get("intensity", 1.0))
    hues, mono = _accent_hues(a)
    light = mood == "light"
    p = {}

    # ---- accents
    def accent(role, i, h, c):
        if mood == "neon":
            L = _neon_L(h) + (0.07 if i == 1 else -0.06 if (i == 2 and mono) else 0)
            col = oklch(L, _cmax(L, h) * 0.94 * min(1.0, k), h)
        elif mood == "soft":
            L = (0.80, 0.84, 0.74)[i]
            col = oklch(L, max(0.07, min(0.14, c * 1.3)) * k, h)
        elif mood == "light":
            if a["C"] < 0.02:               # white: silver and graphite, the faintest cool tint
                L = (0.36, 0.62, 0.50)[i]
                col = oklch(L, 0.006, 255)
            else:                           # calm-light: its pastel hues, deep enough to read on frost
                L = (0.56, 0.62, 0.52)[i]
                col = oklch(L, min(0.14, max(0.08, c * 1.6)) * k, h)
        elif mood == "void":                # starlight
            col = oklch((0.80, 0.62, 0.90)[i], 0.012, 255)
        else:                               # graphite
            col = oklch((0.84, 0.68, 0.76)[i], 0.008, h)
        return col

    for i, role in enumerate(("primary", "secondary", "tertiary")):
        h, c = hues[i]
        col = ov.get(role) or accent(role, i, h, c)
        L, C, H = to_oklch(col)
        p[role] = col
        on_dark = L > 0.6                    # light accents carry dark text
        p[f"on_{role}"] = oklch(0.17, min(C, 0.05), H) if on_dark else oklch(0.97, min(C, 0.02), H)
        if light:
            p[f"{role}_container"] = oklch(0.90, min(C * 0.4, 0.05), H)
            p[f"on_{role}_container"] = oklch(0.26, min(C, 0.08), H)
            p[f"{role}_dim"] = oklch(min(0.80, L + 0.12), C * 0.8, H)
        else:
            p[f"{role}_container"] = oklch(0.30, C * 0.5, H)
            p[f"on_{role}_container"] = oklch(0.92, C * 0.3, H)
            p[f"{role}_dim"] = oklch(max(0.40, L - 0.14), C * 0.9, H)

    # ---- surfaces
    _, _, ph = to_oklch(p["primary"])
    if light:
        tint = 0.0 if a["C"] < 0.02 else min(0.02, a["C"] * 0.3)
        ladder = {"surface_lowest": 0.985, "background": 0.965, "surface": 0.950, "surface_low": 0.935,
                  "surface_container": 0.915, "surface_high": 0.890, "surface_highest": 0.860,
                  "outline_variant": 0.800, "outline": 0.620}
        sh, sc = (ph if tint else 255), max(tint, 0.004)
        fg = (0.24, 0.40, 0.55)
    elif mood == "void":
        ladder = {"surface_lowest": 0.050, "background": 0.070, "surface": 0.090, "surface_low": 0.105,
                  "surface_container": 0.120, "surface_high": 0.150, "surface_highest": 0.180,
                  "outline_variant": 0.260, "outline": 0.400}
        sh, sc = 255, 0.0
        fg = (0.90, 0.72, 0.52)
    else:
        ladder = {"surface_lowest": 0.140, "background": 0.170, "surface": 0.190, "surface_low": 0.207,
                  "surface_container": 0.225, "surface_high": 0.257, "surface_highest": 0.290,
                  "outline_variant": 0.360, "outline": 0.510}
        if mood == "neon":
            sh, sc = ph, 0.038 * min(1.2, k)
        elif mood == "soft":
            sh = hue_toward(ph, TOKYO_HUE, settings.get("tokyo_tint", 0.35))
            sc = 0.024
        else:
            sh, sc = ph, 0.005
        fg = (0.91, 0.76, 0.58)
    for name, L in ladder.items():
        p[name] = oklch(L - settings.get("depth", 0.0) * (0 if light else 1),
                        sc * (1.5 if name.startswith("outline") else 1.0), sh)
    p["on_surface"] = oklch(fg[0], min(sc, 0.03) if not light else 0.012, sh)
    p["on_surface_variant"] = oklch(fg[1], min(sc * 1.3, 0.04) if not light else 0.015, sh)
    p["muted"] = oklch(fg[2], min(sc * 1.6, 0.05) if not light else 0.018, sh)

    # ---- status and terminal colours: Tokyo Night's, nudged toward the accent. Terminals stay
    # dark in every mood, so these are dark-background colours; ok/warn/bad follow the scheme.
    for name in ("red", "orange", "yellow", "green", "teal", "cyan", "blue", "magenta"):
        L, C, h = to_oklch(TOKYO[name])
        d = ((ph - h + 180) % 360) - 180
        h2 = (h + max(-12, min(12, d * 0.25))) % 360
        p[name] = oklch(L, C, h2)
        p[f"{name}_bright"] = oklch(min(0.93, L + 0.06), C * 0.9, h2)
        p[f"{name}_dim"] = oklch(L - 0.12, C * 0.9, h2)
    for key, name in (("ok", "green"), ("warn", "yellow"), ("bad", "red")):
        L, C, h = to_oklch(p[name])
        p[key] = oklch(0.50, max(C, 0.12), h) if light else p[name]
    p["error"] = p["red"]
    p["claude"] = "#d97757"
    p["shadow"] = "#000000"

    # ---- meta
    p["_mood"] = mood
    p["_scheme"] = "light" if light else "dark"
    p["_glow"] = {"neon": 1.0, "soft": 0.7, "graphite": 0.4, "void": 0.35, "light": 0.15}[mood]
    p["_edge"] = "#000000" if light else "#ffffff"
    p["_swatches"] = [c["hex"] for c in a["clusters"]]
    p["_analysis"] = {"L": round(a["L"], 3), "C": round(a["C"], 3), "vivid": round(a["vivid"], 3),
                      "hue": round(a["hue"]), "consistency": round(a.get("consistency", 0), 2), "mood": mood_of(a)}
    return p
