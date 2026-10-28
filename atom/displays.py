"""The displays: what is plugged in, which monitor each one is, whether their arrangement makes sense, and how
big the rice's UI should be on each.

Identity. Connector names (DP-1, HDMI-A-1) change with ports, cables, docks and GPU routing (the 4K went from
DP-3 on the iGPU to DP-1 on the NVIDIA on 2026-10-28 and lost its settings), so everything the rice keeps per
screen is keyed by the monitor's own identity from its EDID: maker, product code and serial
("AUS-2755-SBLMQS095780"). A panel without a serial (laptop panels) is the maker and product alone; two
identical serial-less monitors are told apart by connector. The registry (displays.json) remembers each
monitor's connectors and a name, so state that still names a connector can be mapped.

Arrangement. KWin takes every panel/strut that intersects an output away from that output's maximize area,
so overlapping outputs shrink each other (the "maximize preview is a band" bug). check() finds overlaps,
screens that touch nothing (a gap: the pointer can't cross), and the edges each screen shares with another
(top-edge gestures can't work on a shared edge); fix() proposes positions with the overlaps and gaps closed.

UI size. One standard for every screen: the CSS reference pixel, a visual angle of about 0.0213 degrees
(one pixel at 96 dpi seen from 28 inches). From a screen's physical size, its logical resolution and a
typical viewing distance for that kind of screen, comfort() says how many of the rice's logical pixels make
one reference pixel there. A 1080p laptop panel seen up close gets a smaller UI than a 27" desk monitor, and
an 8K left at scale 1 gets a much bigger one. Settings: ui {auto, size} and displays {<id>: {size}}.
"""
import glob
import json
import math
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

from . import util
from .util import STATE

REGISTRY = STATE / "displays.json"

# PNP maker ids -> names people know (EDID only carries the three letters)
MAKERS = {"AUS": "ASUS", "ACR": "Acer", "AOC": "AOC", "APP": "Apple", "AUO": "AU Optronics", "BNQ": "BenQ",
          "BOE": "BOE", "CMN": "Innolux", "DEL": "Dell", "ENC": "Eizo", "GBT": "Gigabyte", "GSM": "LG",
          "HWP": "HP", "IVM": "iiyama", "LEN": "Lenovo", "LGD": "LG Display", "MSI": "MSI", "NEC": "NEC",
          "PHL": "Philips", "SAM": "Samsung", "SDC": "Samsung Display", "SHP": "Sharp", "SNY": "Sony",
          "VSC": "ViewSonic", "XMI": "Xiaomi", "HKC": "HKC", "KOS": "KOIOS"}
INTERNAL = ("eDP", "LVDS", "DSI")
KSCREEN_PANEL = 7                       # KScreen::Output::Type::Panel


@dataclass
class Display:
    connector: str
    x: float                            # logical px, as KWin lays the desktop out
    y: float
    w: float
    h: float
    scale: float = 1.0
    px_w: int = 0                       # the mode, in device pixels (before rotation)
    px_h: int = 0
    hz: float = 0.0
    mm_w: int = 0                       # physical size as the monitor reports it (0 = unknown)
    mm_h: int = 0
    rotation: int = 1                   # KScreen: 1 none, 2 left, 4 inverted, 8 right
    internal: bool = False
    primary: bool = False
    mirror: bool = False                # shows another output's picture (KScreen replication): overlaps by design
    maker: str = ""
    model: str = ""
    serial: str = ""
    product: str = ""
    id: str = ""

    @property
    def right(self):
        return self.x + self.w

    @property
    def bottom(self):
        return self.y + self.h

    @property
    def portrait(self):
        return self.h > self.w

    @property
    def diag_mm(self):
        return math.hypot(self.mm_w, self.mm_h) if self.physical_known else 0.0

    @property
    def physical_known(self):
        """EDID sizes are often missing (0), or just the aspect ratio in cm (16x9 for projectors and TVs)."""
        return self.mm_w >= 100 and self.mm_h >= 60

    @property
    def name(self):
        """What people call it: 'Laptop', 'ASUS VG27UQ1A', or the connector when the EDID says nothing."""
        if self.internal:
            return "Laptop"
        maker = MAKERS.get(self.maker, self.maker)
        return " ".join(p for p in (maker, self.model) if p) or self.connector

    @property
    def label(self):
        """A short tag for the screen map: Laptop / 4K / 1440p / 8K, with 'portrait' when it is."""
        if self.internal:
            return "Laptop"
        short = min(self.px_w, self.px_h) or round(min(self.w, self.h) * self.scale)
        tag = {2160: "4K", 2880: "5K", 4320: "8K"}.get(short, f"{short}p")
        return tag + (" portrait" if self.portrait else "")

    def to_json(self):
        d = asdict(self)
        d.update(name=self.name, label=self.label, portrait=self.portrait, right=self.right, bottom=self.bottom)
        return d


# ---------------------------------------------------------------------------------------------- EDID
def parse_edid(b):
    """Maker (PNP id), product code, serial (the text one if there is one) and name from an EDID block."""
    if len(b) < 128 or b[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        return {}
    m = (b[8] << 8) | b[9]
    maker = "".join(chr(((m >> s) & 31) + 64) for s in (10, 5, 0))
    out = {"maker": maker if maker.isalpha() else "", "product": "%04x" % (b[10] | b[11] << 8),
           "serial": "", "model": "", "mm_w": b[21] * 10, "mm_h": b[22] * 10}
    num = int.from_bytes(b[12:16], "little")
    for i in range(54, 126, 18):
        d = b[i:i + 18]
        if d[0] == 0 and d[1] == 0 and d[3] in (0xFC, 0xFF):
            text = d[5:18].split(b"\n")[0].decode("ascii", "replace").strip()
            out["model" if d[3] == 0xFC else "serial"] = text
    if not out["serial"] and num not in (0, 0x01010101, 0xFFFFFFFF):      # 0x01010101: "no serial" filler
        out["serial"] = str(num)
    return out


def edids():
    """{connector: parsed EDID} for every connected connector, from sysfs."""
    out = {}
    for f in glob.glob("/sys/class/drm/card*-*/edid"):
        conn = Path(f).parent.name.split("-", 1)[1]
        try:
            info = parse_edid(Path(f).read_bytes())
        except OSError:
            continue
        if info:
            out[conn] = info
    return out


def identity(d, twins=()):
    """A monitor's id: maker-product-serial; without a serial, maker-product, plus the connector when another
    connected monitor has the same maker-product (identical twins can't be told apart any other way)."""
    if not d.maker:
        return "conn:" + d.connector
    base = f"{d.maker}-{d.product}"
    if d.serial:
        return f"{base}-{d.serial}"
    return f"{base}@{d.connector}" if base in twins else base


# ---------------------------------------------------------------------------------------------- probing
def parse(kscreen, eds):
    """Displays from `kscreen-doctor -j` output and EDIDs (pure, so topologies can be tested)."""
    out = []
    for o in kscreen.get("outputs", []):
        if not o.get("enabled") or not o.get("connected", True):
            continue
        mode = next((m for m in o.get("modes", []) if m.get("id") == o.get("currentModeId")), None)
        size = (mode or {}).get("size") or o.get("size") or {"width": 0, "height": 0}
        pw, ph = int(size["width"]), int(size["height"])
        scale = float(o.get("scale") or 1)
        rot = int(o.get("rotation") or 1)
        lw, lh = (ph, pw) if rot in (2, 8) else (pw, ph)
        e = eds.get(o["name"], {})
        mm = o.get("sizeMM") or {}
        model = e.get("model", "")
        if model.startswith(o["name"] + "-"):       # KWin-style "eDP-1-N156HMA-GA1"
            model = model[len(o["name"]) + 1:]
        out.append(Display(
            connector=o["name"], x=float(o["pos"]["x"]), y=float(o["pos"]["y"]), w=lw / scale, h=lh / scale,
            scale=scale, px_w=pw, px_h=ph, hz=float((mode or {}).get("refreshRate") or 0),
            mm_w=int(mm.get("width") or e.get("mm_w") or 0), mm_h=int(mm.get("height") or e.get("mm_h") or 0),
            rotation=rot, internal=o["name"].startswith(INTERNAL) or o.get("type") == KSCREEN_PANEL,
            primary=o.get("priority") == 1, mirror=bool(o.get("replicationSource")), maker=e.get("maker", ""), model=model,
            serial=e.get("serial", ""), product=e.get("product", "")))
    if out and not any(d.primary for d in out):
        out[0].primary = True
    seen, twins = set(), set()
    for d in out:
        key = f"{d.maker}-{d.product}"
        if not d.serial and d.maker:
            (twins if key in seen else seen).add(key)
    for d in out:
        d.id = identity(d, twins)
    return sorted(out, key=lambda d: (d.x, d.y))


def probe():
    """The enabled displays now, left to right ([] if KScreen can't be asked)."""
    try:
        data = json.loads(util.run("kscreen-doctor", "-j").stdout)
    except (ValueError, AttributeError):
        return []
    return parse(data, edids())


# ---------------------------------------------------------------------------------------------- registry
def registry():
    """{id: {name, label, connectors: [newest first], seen: epoch}}: every monitor this machine has had."""
    return util.load_json(REGISTRY, {}) or {}


def remember(ds, now=None):
    """Note the displays in the registry; returns {id: old connector} for monitors that changed connector."""
    reg, moved = registry(), {}
    now = int(now or time.time()) // 3600 * 3600        # to the hour: the file only changes when something does
    for d in ds:
        e = reg.setdefault(d.id, {"connectors": []})
        conns = e.get("connectors", [])
        if conns and conns[0] != d.connector:
            moved[d.id] = conns[0]
        e.update(name=d.name, label=d.label, seen=now,
                 connectors=[d.connector] + [c for c in conns if c != d.connector][:7])
    util.save_json(REGISTRY, reg)
    return moved


def id_for(key, ds=None, reg=None):
    """A display id for `key`, which may already be an id or a connector name: the display on that connector
    now, else the monitor that last used it. "" if nothing knows it."""
    if not key:
        return ""
    ds = probe() if ds is None else ds
    reg = registry() if reg is None else reg
    if key in reg or any(d.id == key for d in ds):
        return key
    now = next((d.id for d in ds if d.connector == key), "")
    if now:
        return now
    return next((i for i, e in sorted(reg.items(), key=lambda kv: -kv[1].get("seen", 0))
                 if key in e.get("connectors", [])), "")


# ---------------------------------------------------------------------------------------------- arrangement
EPS = 0.5           # logical px: positions are whole numbers, fractional sizes leave sub-pixel seams


def overlap(a, b):
    """(width, height) of the area two displays share, or None."""
    w = min(a.right, b.right) - max(a.x, b.x)
    h = min(a.bottom, b.bottom) - max(a.y, b.y)
    return (w, h) if w > EPS and h > EPS else None


def shared_edges(d, ds):
    """The sides of `d` that another display continues past (the pointer crosses there instead of stopping)."""
    sides = set()
    for o in ds:
        if o is d:
            continue
        along_x = min(d.right, o.right) - max(d.x, o.x) > 1
        along_y = min(d.bottom, o.bottom) - max(d.y, o.y) > 1
        if along_x and abs(o.bottom - d.y) <= 1:
            sides.add("top")
        if along_x and abs(o.y - d.bottom) <= 1:
            sides.add("bottom")
        if along_y and abs(o.right - d.x) <= 1:
            sides.add("left")
        if along_y and abs(o.x - d.right) <= 1:
            sides.add("right")
    return sides


def touching(a, b):
    """Do two displays share an edge stretch (or overlap)?"""
    gx = max(a.x - b.right, b.x - a.right)
    gy = max(a.y - b.bottom, b.y - a.bottom)
    return (gx <= 1 and gy < -1) or (gy <= 1 and gx < -1) or overlap(a, b) is not None


def check(ds):
    """What's wrong with an arrangement: {"overlaps": [[conn, conn, w, h]], "apart": [conn...]} (apart: not
    connected to the rest by any shared edge, so the pointer can't get there)."""
    out = {"overlaps": [], "apart": []}
    ds = [d for d in ds if not d.mirror]
    for i, a in enumerate(ds):
        for b in ds[i + 1:]:
            if (o := overlap(a, b)):
                out["overlaps"].append([a.connector, b.connector, round(o[0], 2), round(o[1], 2)])
    if len(ds) > 1:
        group, todo = set(), [next((d for d in ds if d.primary), ds[0])]
        while todo:
            d = todo.pop()
            if d.connector in group:
                continue
            group.add(d.connector)
            todo += [o for o in ds if o.connector not in group and touching(d, o)]
        out["apart"] = [d.connector for d in ds if d.connector not in group]
    return out


def fix(ds):
    """Positions that close overlaps and gaps with the smallest moves: the primary stays put, the others are
    placed one by one (nearest first), each pushed out of whatever it overlaps along the shorter way, then
    slid onto the nearest placed screen if it ended up apart. Returns {connector: (x, y)} for the ones that
    move ({} when the arrangement is fine)."""
    ds = [d for d in ds if not d.mirror]
    if len(ds) < 2:
        return {}
    import copy
    orig = {d.connector: (d.x, d.y) for d in ds}
    ds = [copy.copy(d) for d in ds]
    anchor = next((d for d in ds if d.primary), ds[0])
    placed = [anchor]
    centre = lambda d: (d.x + d.w / 2, d.y + d.h / 2)
    ax, ay = centre(anchor)
    for d in sorted((d for d in ds if d is not anchor), key=lambda d: math.dist(centre(d), (ax, ay))):
        for _ in range(4 * len(ds)):
            hit = next((p for p in placed if overlap(p, d)), None)
            if not hit:
                break
            moves = [(hit.right - d.x, 0), (hit.x - d.right, 0), (0, hit.bottom - d.y), (0, hit.y - d.bottom)]
            dx, dy = min(moves, key=lambda m: abs(m[0]) + abs(m[1]))
            d.x, d.y = math.ceil(d.x + dx) if dx > 0 else math.floor(d.x + dx), \
                math.ceil(d.y + dy) if dy > 0 else math.floor(d.y + dy)
        if not any(touching(d, p) for p in placed):
            best = None
            for p in placed:
                for nx, ny in ((math.ceil(p.right), d.y), (math.floor(p.x - d.w), d.y),
                               (d.x, math.ceil(p.bottom)), (d.x, math.floor(p.y - d.h))):
                    t = copy.copy(d)
                    t.x, t.y = nx, ny
                    # keep it alongside: clamp the other axis so the edges share a stretch
                    if nx != d.x:
                        t.y = min(max(t.y, p.y - t.h + 64), p.bottom - 64)
                    else:
                        t.x = min(max(t.x, p.x - t.w + 64), p.right - 64)
                    if any(overlap(t, q) for q in placed):
                        continue
                    cost = abs(t.x - d.x) + abs(t.y - d.y)
                    if best is None or cost < best[0]:
                        best = (cost, t.x, t.y)
            if best:
                d.x, d.y = best[1], best[2]
        placed.append(d)
    # KScreen keeps the layout's top-left at 0,0: shift back if the fix pushed something past it
    mx, my = min(d.x for d in placed), min(d.y for d in placed)
    for d in placed:
        d.x, d.y = d.x - min(mx, 0), d.y - min(my, 0)
    return {d.connector: (int(d.x), int(d.y)) for d in placed if (d.x, d.y) != orig[d.connector]}


def proposal(ds):
    """fix() as kscreen-doctor arguments, or ""."""
    return " ".join(f"output.{c}.position.{x},{y}" for c, (x, y) in sorted(fix(ds).items()))


# ---------------------------------------------------------------------------------------------- UI size
REF_RAD = math.radians(0.0213)      # the CSS reference pixel's visual angle
LAPTOP_MM = 500                     # typical viewing distances (mm)


def distance_mm(d):
    """How far people usually sit from this kind of screen: a laptop panel at arm's bend, a desk monitor about
    its own diagonal away (60-90 cm), a TV-sized screen much further."""
    if d.internal:
        return LAPTOP_MM
    diag = d.diag_mm or 686         # unknown size: a 27" desk monitor
    if diag > 1100:                 # > 43": a TV
        return diag * 1.6
    return min(max(diag, 600), 900)


def pitch_mm(d):
    """Millimetres per logical pixel along the width (a guess from the resolution when the size is unknown:
    a 24" at 1080p, a 27" above it)."""
    if d.physical_known:
        mm = d.mm_h if d.rotation in (2, 8) else d.mm_w      # the EDID size is for the unrotated panel
        return mm / d.w
    short = min(d.px_w, d.px_h) or 1080
    diag_in = 24 if short <= 1200 else 27 if short <= 2160 else 32
    width_mm = diag_in * 25.4 * 16 / math.hypot(16, 9)
    return width_mm / (d.w if not d.portrait else d.h)


def comfort(d):
    """The standard size for this screen: how many logical px make one reference pixel (rounded to 0.05)."""
    angle = pitch_mm(d) / distance_mm(d)
    return round(round(REF_RAD / angle / 0.05) * 0.05, 2)


def ui_scale(d, cfg):
    """The rice's UI size on this display: its own size if one was set (displays {<id>: {size}}), else with
    ui.auto (default) the standard size times the overall preference ui.size, else ui.size alone. Kept to
    0.6-3.5."""
    ui = cfg.get("ui") or {}
    own = ((cfg.get("displays") or {}).get(d.id) or {}).get("size")
    if own:
        s = float(own)
    elif ui.get("auto", True):
        s = comfort(d) * float(ui.get("size", 1.0))
    else:
        s = float(ui.get("size", 1.0))
    return round(min(3.5, max(0.6, s)), 2)


SCALES = [s / 100 for s in range(100, 401, 5)]      # the steps Plasma's display settings offer


def whole(d, s):
    """Does scale `s` give this display a whole-number logical size (no sub-pixel seam at its edges)?"""
    return (d.px_w / s).is_integer() and (d.px_h / s).is_integer()


def scale_advice(d):
    """Plasma's own scale, when it's far off the standard size for this screen (everything else, the stock
    widgets and the apps, would be tiny or huge there): a better one, else None. Whole-number sizes first."""
    c = comfort(d)
    if 0.75 <= c <= 1.4:
        return None
    want = d.scale * c
    near = [s for s in SCALES if abs(s - want) <= 0.15]
    return min([s for s in near if whole(d, s)] or near or SCALES, key=lambda s: abs(s - want))


def seam_free(d):
    """The nearest scale to the current one with a whole-number logical size (within 0.15), when the current
    one leaves a fraction (3840 / 1.7 = 2258.82): None if it's already whole or there's none close."""
    if whole(d, d.scale):
        return None
    near = [s for s in SCALES if whole(d, s) and abs(s - d.scale) <= 0.15]
    return min(near, key=lambda s: abs(s - d.scale)) if near else None


def summary(ds, cfg):
    """Everything the screen map and `rice.py displays` show."""
    issues = check(ds)
    return {"displays": [dict(d.to_json(), comfort=comfort(d), ui=ui_scale(d, cfg), scaleAdvice=scale_advice(d),
                              seamFree=seam_free(d), sharedEdges=sorted(shared_edges(d, ds))) for d in ds],
            "issues": issues, "fix": proposal(ds) if issues["overlaps"] or issues["apart"] else ""}


# ---------------------------------------------------------------------------------------------- doctor
ASKED = STATE / "displays-asked"        # the arrangement last asked about (asked once per arrangement)


def describe(issues, ds):
    """The problems in words, for a notification."""
    names = {d.connector: d.label for d in ds}
    out = [f"{names.get(a, a)} and {names.get(b, b)} overlap by {w:g} × {h:g} px" for a, b, w, h in issues["overlaps"]]
    out += [f"{names.get(c, c)} doesn't touch the other screens (the pointer can't get there)" for c in issues["apart"]]
    return "; ".join(out)


def apply_fix(args):
    """Run a proposal (kscreen-doctor arguments). True if KScreen took it."""
    r = util.run("kscreen-doctor", *args.split())
    return r is not None and r.returncode == 0


def ask(ds=None):
    """If the arrangement has a problem not asked about yet: one notification naming it, with "Fix it" (the
    user's rule: ask first, never move screens silently). Blocks until it's answered or dismissed, so run it
    in the background. Returns True if it fixed something."""
    ds = probe() if ds is None else ds
    issues = check(ds)
    args = proposal(ds) if issues["overlaps"] or issues["apart"] else ""
    if not args:
        ASKED.unlink(missing_ok=True)
        return False
    key = ";".join(f"{d.id}@{d.x:g},{d.y:g},{d.w:g}x{d.h:g}" for d in ds)
    try:
        if ASKED.read_text() == key:
            return False
    except OSError:
        pass
    util.write_if_changed(ASKED, key)
    r = util.run("notify-send", "-a", "Displays", "-i", "preferences-desktop-display", "-u", "critical",
                 "-A", "fix=Fix it", "-A", "ignore=Leave it", "--wait",
                 "Screens are arranged oddly", describe(issues, ds) + ". Windows can end up the wrong size (KWin "
                 "takes one screen's bars away from the other). Fix it moves them edge to edge.",
                 quiet=True, timeout=24 * 3600)
    if r is None or r.stdout.strip() != "fix":
        return False
    ok = apply_fix(args)
    util.log("displays: %s %s", "fixed with" if ok else "couldn't apply", args)
    return ok


def report(ds, cfg):
    """`rice.py displays` in words."""
    s = summary(ds, cfg)
    lines = []
    for d in s["displays"]:
        lines.append(f"{d['connector']:<10} {d['name']} ({d['label']}, {d['px_w']}x{d['px_h']} @{d['scale']:g}, "
                     f"{d['mm_w']}x{d['mm_h']} mm){'  main' if d['primary'] else ''}")
        lines.append(f"{'':<10} id {d['id']} · at {d['x']:g},{d['y']:g} · {d['w']:.6g}x{d['h']:.6g} logical"
                     f" · shares {', '.join(d['sharedEdges']) or 'no edge'}")
        lines.append(f"{'':<10} UI size {d['ui']} (standard {d['comfort']})"
                     + (f" · Plasma scale {d['scaleAdvice']:g} would suit it better" if d["scaleAdvice"] else "")
                     + (f" · scale {d['seamFree']:g} would avoid sub-pixel seams" if d["seamFree"] else ""))
    lines.append("arrangement: " + (describe(s["issues"], ds) or "fine"))
    if s["fix"]:
        lines.append(f"fix: kscreen-doctor {s['fix']}   (rice.py displays --fix)")
    return "\n".join(lines)
