#!/usr/bin/env python3
"""Atom Plasma: keyboard lighting, without the vendors' apps.

    rgb.py status               JSON for the launcher's Lighting tab: each keyboard, whether it can be reached,
                                its settings, its effects, and the colours it shows now
    rgb.py apply [--device ID] [--force]
                                light the keyboards as their settings say. rice.py runs it after every
                                re-theme (only keyboards on Automatic whose colours changed get written);
                                the udev rule's user unit runs it with --force when the Razer connects
    rgb.py set <ID|all> [--mode auto|manual] [--style S] [--follow lead|<output>] [--effect E]
                        [--colour HEX] [--colour2 HEX] [--brightness 0..100] [--on true|false]
                                change a keyboard's settings and light it
    rgb.py watch                the keyboards go dark while every screen is off (DPMS: idle, Turn Off Screen,
                                a locked session going dark) and get back the brightness they had when the
                                screens wake. Runs as atom-plasma-rgb-watch.service

Keyboards (ID):
    laptop   the ASUS laptop's own, one zone, through asusd (asusctl; its D-Bus policy lets wheel and users
             in, so no root)
    razer    a Razer keyboard, every key, over hidraw with the protocol OpenRazer documents (90-byte HID
             feature reports): needs /etc/udev/rules.d/70-atom-plasma-rgb.rules (RULE below), which gives the
             logged-in user the device and starts atom-plasma-rgb.service when it connects

Automatic follows a screen's palette (palette-<output>.json; "lead" is the screen that drives the theme):
solid = its primary, gradient = primary -> tertiary across the keys (like the bar's outline), breathe and
starlight = the two together. LEDs aren't a screen: automatic colours get more chroma, and every colour is
sent in linear light with its strongest channel at full, so dark or greyish accents still light up as
themselves (graphite and void come out a tinted white); brightness is its own setting.
Gradients live in the keyboard's RAM: under them the Razer keeps a stored static primary, which it shows
from power-on until this runs.
Units: systemd/ here, linked into ~/.config/systemd/user (the watcher is enabled for the graphical session).
Settings: ~/.local/state/rice/rgb.json; while the screens are off, rgb-dark.json there holds the levels to put back
(apply leaves the keyboards alone meanwhile).
"""
import contextlib
import fcntl
import functools
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from atom import palette, util
from atom.util import CACHE, STATE

SETTINGS = STATE / "rgb.json"
SEEN = CACHE / "rgb"                    # <id>.json: what each keyboard was last sent
LEAD = STATE / "theme-screen"
DARK = STATE / "rgb-dark.json"          # the screens are off: each keyboard's brightness from before
UNIT = "atom-plasma-rgb.service"
RULE_PATH = "/etc/udev/rules.d/70-atom-plasma-rgb.rules"
RULE = ('SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="%04x", TAG+="uaccess", '
        'TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="' + UNIT + '"')
LEVELS = ("off", "low", "med", "high")  # asusd's brightness steps

# effects each keyboard does by hand: (id, name, colours it takes)
EFFECTS = {
    "laptop": [("static", "Static", 1), ("breathe", "Breathe", 2), ("pulse", "Pulse", 1),
               ("spectrum", "Spectrum", 0), ("wave", "Rainbow wave", 0)],
    "razer": [("static", "Static", 1), ("gradient", "Gradient", 2), ("breathe", "Breathe", 2),
              ("starlight", "Starlight", 2), ("reactive", "Reactive", 1), ("spectrum", "Spectrum", 0),
              ("wave", "Rainbow wave", 0)],
}
# Automatic: the style -> the effect it runs and the accents it takes
STYLES = {"solid": ("static", ("primary",)), "gradient": ("gradient", ("primary", "tertiary")),
          "breathe": ("breathe", ("primary", "tertiary")), "starlight": ("starlight", ("primary", "tertiary"))}
STYLE_NAMES = {"solid": "Solid", "gradient": "Gradient", "breathe": "Breathe", "starlight": "Starlight"}
DEVICE_STYLES = {"laptop": ["solid", "breathe"], "razer": ["gradient", "solid", "breathe", "starlight"]}

# Razer keyboards: USB product id -> name, key matrix, the interface its lighting listens on, transaction id
# (from OpenRazer's driver and daemon)
RAZER = {0x0293: {"name": "Razer BlackWidow V4 X", "rows": 6, "cols": 22, "iface": 2, "txn": 0x1F}}


# ---------------------------------------------------------------- settings
def builtin_output():
    """The laptop's own panel (the laptop keyboard follows it by default)."""
    for p in sorted(STATE.glob("palette-*.json")):
        name = p.stem[len("palette-"):]
        if name.startswith(("eDP", "LVDS")):
            return name
    return "lead"


def defaults():
    return {
        "laptop": {"mode": "auto", "style": "solid", "follow": builtin_output(), "effect": "static",
                   "colour": "#7aa2f7", "colour2": "#bb9af7", "brightness": 33, "on": True},
        "razer": {"mode": "auto", "style": "gradient", "follow": "lead", "effect": "static",
                  "colour": "#7aa2f7", "colour2": "#bb9af7", "brightness": 80, "on": True},
    }


def load():
    out = defaults()
    try:
        saved = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        saved = {}
    for dev, s in saved.items():
        if dev in out and isinstance(s, dict):
            out[dev].update({k: v for k, v in s.items() if k in out[dev]})
    return out


def save(cfg):
    util.save_json(SETTINGS, cfg)


def is_hex(v):
    return isinstance(v, str) and len(v) == 7 and v.startswith("#") and all(c in "0123456789abcdefABCDEF" for c in v[1:])


def set_args(dev, args, strict=True):
    """--mode/--style/... from `set` into a settings patch for one keyboard. Not strict (`set all`): a style or
    effect this keyboard doesn't have leaves it as it is."""
    out = {}
    for k in ("mode", "style", "follow", "effect", "colour", "colour2", "brightness", "on"):
        flag = "--" + k
        if flag not in args:
            continue
        i = args.index(flag)
        v = args[i + 1] if i + 1 < len(args) else ""
        if k == "mode" and v not in ("auto", "manual"):
            sys.exit("mode is auto or manual")
        elif k in ("style", "effect") and v not in (DEVICE_STYLES[dev] if k == "style" else [e[0] for e in EFFECTS[dev]]):
            if strict:
                sys.exit(f"{dev} has no {k} {v!r}")
            continue
        elif k in ("colour", "colour2"):
            if not is_hex(v):
                sys.exit(f"{flag} takes a #rrggbb colour")
            v = v.lower()
        elif k == "brightness":
            try:
                v = max(0, min(100, round(float(v))))
            except ValueError:
                sys.exit("brightness is 0..100")
        elif k == "on":
            v = v.lower() in ("1", "true", "on", "yes")
        elif k == "follow" and not v:
            sys.exit("follow is lead or an output name")
        out[k] = v
    return out


# ---------------------------------------------------------------- colours
def lead():
    try:
        return LEAD.read_text().strip()
    except OSError:
        return ""


def screen_palette(follow):
    """The palette of the screen a keyboard follows (the global one if that screen has none)."""
    name = lead() if follow == "lead" else follow
    for p in ([STATE / f"palette-{name}.json"] if name else []) + [STATE / "palette.json"]:
        try:
            return name, json.loads(p.read_text())
        except (OSError, ValueError):
            continue
    return name, {"primary": "#7aa2f7", "tertiary": "#bb9af7"}


def vivid(h):
    """An accent as a keyboard should wear it: more chroma (pastels read as white on LEDs), mid lightness
    (yellows keep theirs, or they turn orange). Near-greys stay grey: graphite and void are meant to be silver."""
    L, C, H = palette.to_oklch(h)
    if C < 0.025:
        return palette.oklch(0.8, C, H)
    return palette.oklch(max(0.65, min(0.85, L)), min(0.37, C * 1.6 + 0.03), H)


def led(h):
    """A screen colour -> the LED's 0..255 channels: linear light, the strongest channel at full."""
    lin = [palette._lin(c) for c in palette.hex_rgb(h)]
    top = max(lin)
    if top < 1e-3:
        return (0, 0, 0)
    return tuple(round(c / top * 255) for c in lin)


def plan(dev, s):
    """What a keyboard should show: (effect, [screen colours]) from its settings."""
    if s["mode"] == "auto":
        style = s["style"] if s["style"] in DEVICE_STYLES[dev] else DEVICE_STYLES[dev][0]
        effect, roles = STYLES[style]
        _, p = screen_palette(s["follow"])
        return effect, [vivid(p.get(r, "#7aa2f7")) for r in roles]
    effect = s["effect"] if s["effect"] in [e[0] for e in EFFECTS[dev]] else "static"
    n = next(e[2] for e in EFFECTS[dev] if e[0] == effect)
    return effect, [s["colour"], s["colour2"]][:n]


def frame(colours, rows, cols):
    """A gradient over the key matrix, mostly left to right with a little slant (rows of 0..255 triples)."""
    a, b = colours[0], colours[-1]
    span = (cols - 1) * 0.85 + (rows - 1) * 0.15 or 1
    return [[led(palette.mix(a, b, (c * 0.85 + r * 0.15) / span)) for c in range(cols)] for r in range(rows)]


# ---------------------------------------------------------------- laptop: asusd
@functools.cache
def aura_path():
    """asusd's keyboard lighting object (/xyz/ljones/aura/<model>: tuf here), or "" without asusd."""
    r = subprocess.run(["busctl", "--system", "--list", "tree", "xyz.ljones.Asusd"],
                       capture_output=True, text=True, check=False)
    return next((line for line in r.stdout.split() if line.startswith("/xyz/ljones/aura/")), "")


def asus_present():
    return bool(aura_path())


def asus_name():
    try:
        fam = Path("/sys/class/dmi/id/product_family").read_text().strip()
    except OSError:
        fam = ""
    return (fam.replace("ASUS ", "") or "Laptop") + " keyboard"


def asus_level():
    """asusd's brightness step now (0..3; the Fn keys change it too), or None."""
    if not aura_path():
        return None
    r = subprocess.run(["busctl", "--system", "get-property", "xyz.ljones.Asusd", aura_path(),
                        "xyz.ljones.Aura", "Brightness"], capture_output=True, text=True, check=False)
    try:
        return int(r.stdout.split()[1])
    except (IndexError, ValueError):
        return None


def asusctl(*args):
    r = subprocess.run(["asusctl", *args], capture_output=True, text=True, check=False)
    if r.returncode:
        raise RuntimeError(f"asusctl {' '.join(args)}: {(r.stderr or r.stdout).strip()}")


def asus_apply(effect, colours, s, look=True, level=True):
    if not lit(s):
        asusctl("leds", "set", "off")
        return
    h = ["%02x%02x%02x" % led(c) for c in colours]
    if look and effect == "static":
        asusctl("aura", "effect", "static", "-c", h[0])
    elif look and effect == "breathe":
        asusctl("aura", "effect", "breathe", "--colour", h[0], "--colour2", h[-1], "--speed", "med")
    elif look and effect == "pulse":
        asusctl("aura", "effect", "pulse", "-c", h[0])
    elif look and effect == "spectrum":
        asusctl("aura", "effect", "rainbow-cycle", "--speed", "med")
    elif look and effect == "wave":
        asusctl("aura", "effect", "rainbow-wave", "--direction", "right", "--speed", "med")
    if level:
        asusctl("leds", "set", LEVELS[min(3, 1 + (s["brightness"] - 1) * 3 // 100)])


# ---------------------------------------------------------------- Razer: hidraw
def _ioc(nr, size):     # _IOC(_IOC_READ | _IOC_WRITE, 'H', nr, size)
    return (3 << 30) | (size << 16) | (ord("H") << 8) | nr


HIDIOCSFEATURE = _ioc(0x06, 91)     # report id 0 + 90 bytes
HIDIOCGFEATURE = _ioc(0x07, 91)
VARSTORE, NOSTORE, BACKLIGHT = 0x01, 0x00, 0x05
STATUS = {1: "busy", 3: "failed", 4: "timed out", 5: "not supported"}


def razer_find():
    """(product id, info, /dev/hidrawN of its lighting interface) for a known Razer keyboard, or None."""
    for d in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        try:
            hid = next(line.split("=", 1)[1] for line in (d / "device/uevent").read_text().split("\n")
                       if line.startswith("HID_ID="))
            bus, vendor, product = (int(x, 16) for x in hid.split(":"))
            iface = int((d / "device/../bInterfaceNumber").read_text(), 16)
        except (OSError, StopIteration, ValueError):
            continue
        if vendor == 0x1532 and product in RAZER and iface == RAZER[product]["iface"]:
            return product, RAZER[product], "/dev/" + d.name
    return None


def report(info, cls, cmd, size, args=()):
    """A 90-byte Razer report: status, transaction id, remaining packets (2), protocol, data size, command
    class, command id, 80 bytes of arguments, CRC (XOR of bytes 2..87), reserved."""
    r = bytearray(90)
    r[1], r[5], r[6], r[7] = info["txn"], size, cls, cmd
    r[8:8 + len(args)] = bytes(args)
    crc = 0
    for b in r[2:88]:
        crc ^= b
    r[88] = crc
    return r


def razer_send(fd, r):
    """Send a report, then read the reply until the keyboard stops being busy; returns the reply."""
    fcntl.ioctl(fd, HIDIOCSFEATURE, bytes(1) + bytes(r))
    for _ in range(25):
        time.sleep(0.002)
        buf = bytearray(91)
        fcntl.ioctl(fd, HIDIOCGFEATURE, buf, True)
        status = buf[1]
        if status == 0x02:
            return bytes(buf[1:])
        if status != 0x01:
            break
    raise RuntimeError(f"Razer command {r[6]:02x}:{r[7]:02x} {STATUS.get(status, f'status {status}')}")


def razer_apply(effect, colours, s, found, look=True, level=True):
    if not found:
        raise RuntimeError("not connected")
    _, info, path = found
    rows, cols = info["rows"], info["cols"]
    rgb = [led(c) for c in colours]
    fd = os.open(path, os.O_RDWR)
    try:
        def fx(eid, size, extra=()):    # extended matrix effect, kept on the keyboard (VARSTORE)
            razer_send(fd, report(info, 0x0F, 0x02, size, [VARSTORE, BACKLIGHT, eid, *extra]))
        if level:
            razer_send(fd, report(info, 0x0F, 0x04, 0x03,
                                  [VARSTORE, BACKLIGHT, round(s["brightness"] * 255 / 100) if lit(s) else 0]))
        if not look or not lit(s):
            return
        if effect in ("static", "gradient"):    # a gradient sits on a stored static, its first colour
            fx(0x01, 0x09, [0, 0, 1, *rgb[0]])
        elif effect == "breathe":
            fx(0x02, 0x0C, [2, 0, 2, *rgb[0], *rgb[-1]])
        elif effect == "spectrum":
            fx(0x03, 0x06)
        elif effect == "wave":
            fx(0x04, 0x06, [1, 0x28])
        elif effect == "reactive":
            fx(0x05, 0x09, [0, 2, 1, *rgb[0]])
        elif effect == "starlight":
            fx(0x07, 0x0C, [0, 2, 2, *rgb[0], *rgb[-1]])
        if effect == "gradient":
            for r, row in enumerate(frame(colours, rows, cols)):
                razer_send(fd, report(info, 0x0F, 0x03, 5 + 3 * cols,
                                      [0, 0, r, 0, cols - 1, *(c for key in row for c in key)]))
            razer_send(fd, report(info, 0x0F, 0x02, 0x0C, [NOSTORE, 0x00, 0x08]))   # show the custom frame
    finally:
        os.close(fd)


# ---------------------------------------------------------------- the keyboards
def devices():
    """[{id, name, connected, ready, why, rule}] for the keyboards this machine has."""
    out = []
    asus = asus_present()
    out.append({"id": "laptop", "name": asus_name() if asus else "Laptop keyboard", "zones": "one zone",
                "connected": asus, "ready": asus, "why": "" if asus else "asusd isn't running", "rule": ""})
    found = razer_find()
    if found:
        pid, info, path = found
        ok = os.access(path, os.R_OK | os.W_OK)
        out.append({"id": "razer", "name": info["name"], "zones": "every key", "connected": True, "ready": ok,
                    "why": "" if ok else "needs a one-time setup", "rule": "" if ok else RULE % pid,
                    "setup": "" if ok else setup_command(pid)})
    else:
        out.append({"id": "razer", "name": "Razer keyboard", "zones": "every key", "connected": False,
                    "ready": False, "why": "not connected", "rule": ""})
    return out


def setup_command(pid):
    return (f"sudo tee {RULE_PATH} >/dev/null <<'EOF'\n{RULE % pid}\nEOF\n"
            "sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=hidraw")


def lit(s):
    return bool(s["on"]) and s["brightness"] > 0


def apply(cfg, only=None, force=False, force_level=False, keep_level=()):
    """Light each keyboard (or `only` one) with what changed since it was last sent: its look (effect and
    colours) and its brightness apart, so a re-theme leaves a brightness set with the keyboard's own keys
    alone. Forced (it just connected): everything; force_level (the tab set it): the brightness;
    keep_level: keyboards whose brightness was just put back (wake), never their brightness."""
    errors = []
    for d in devices():
        dev = d["id"]
        if only not in (None, "all", dev) or not d["ready"]:
            continue
        if DARK.exists():       # the screens are off: wake() catches up (forced: everything, it reconnected)
            if force:
                (SEEN / f"{dev}.json").unlink(missing_ok=True)
            continue
        s = cfg[dev]
        effect, colours = plan(dev, s)
        now = {"look": [effect, colours] if lit(s) else None, "level": [s["brightness"], bool(s["on"])]}
        seen = SEEN / f"{dev}.json"
        try:
            was = {} if force else json.loads(seen.read_text())
        except (OSError, ValueError):
            was = {}
        look, level = was.get("look") != now["look"], force_level or was.get("level") != now["level"]
        level = level and dev not in keep_level
        if not (look or level):
            continue
        try:
            if dev == "laptop":
                asus_apply(effect, colours, s, look, level)
            else:
                razer_apply(effect, colours, s, razer_find(), look, level)
        except (OSError, RuntimeError) as e:
            errors.append(f"{d['name']}: {e}")
            seen.unlink(missing_ok=True)
            continue
        SEEN.mkdir(parents=True, exist_ok=True)
        seen.write_text(json.dumps(now))
    return errors


# ---------------------------------------------------------------- screens off
def connectors():
    return [c for c in Path("/sys/class/drm").glob("card*-*") if (c / "dpms").exists()]


def screens_off(conns=None):
    """Every connected display is powered down. DRM's sysfs keeps each connector's DPMS state current
    (KWin's atomic commits update it on both GPUs; a connector also reads "disabled" while off, so only
    "connected" picks the screens)."""
    states = []
    for c in conns if conns is not None else connectors():
        try:
            if (c / "status").read_text().strip() == "connected":
                states.append((c / "dpms").read_text().strip())
        except OSError:
            continue
    return bool(states) and all(st == "Off" for st in states)


def razer_level(found):
    """The Razer's brightness now (0..255; its own keys change it too)."""
    _, info, path = found
    fd = os.open(path, os.O_RDWR)
    try:
        return razer_send(fd, report(info, 0x0F, 0x84, 0x03, [VARSTORE, BACKLIGHT]))[10]
    finally:
        os.close(fd)


def razer_set_level(found, level):
    _, info, path = found
    fd = os.open(path, os.O_RDWR)
    try:
        razer_send(fd, report(info, 0x0F, 0x04, 0x03, [VARSTORE, BACKLIGHT, level]))
    finally:
        os.close(fd)


def dark(laptop_level):
    """Screens off: note each keyboard's brightness, then turn them off. laptop_level: asusd's step from
    while the screens were still on (PowerDevil zeroes it itself when it turns them off on idle)."""
    if DARK.exists():
        return
    was = {}
    DARK.write_text("{}\n")       # first: an apply from now on leaves the keyboards alone
    for d in devices():
        if not d["ready"]:
            continue
        try:
            if d["id"] == "laptop" and laptop_level:
                was["laptop"] = laptop_level
                asusctl("leds", "set", "off")
            elif d["id"] == "razer":
                found = razer_find()
                level = razer_level(found)
                if level:
                    was["razer"] = level
                    razer_set_level(found, 0)
        except (OSError, RuntimeError, IndexError) as e:
            print(f"rgb.py: dark: {d['name']}: {e}", file=sys.stderr)
        DARK.write_text(json.dumps(was) + "\n")     # as it goes: a keyboard that fails later still comes back


def wake():
    """Screens back on: the brightness each keyboard had, then whatever changed meanwhile."""
    try:
        was = json.loads(DARK.read_text())
    except (OSError, ValueError):
        was = {}
    DARK.unlink(missing_ok=True)
    for d in devices():
        if not d["ready"] or d["id"] not in was:
            continue
        try:
            if d["id"] == "laptop":
                asusctl("leds", "set", LEVELS[max(0, min(3, int(was["laptop"])))])
            else:
                razer_set_level(razer_find(), max(0, min(255, int(was["razer"]))))
        except (OSError, RuntimeError, ValueError) as e:
            print(f"rgb.py: wake: {d['name']}: {e}", file=sys.stderr)
    for e in apply(load(), keep_level=set(was)):
        print(f"rgb.py: wake: {e}", file=sys.stderr)


def watch():
    """Once a second: are the screens off? While they're on, also keep asusd's brightness step (every 5 s,
    over one open D-Bus connection: no process per sample). The connectors are listed again every 30 s.
    A rgb-dark.json left by a session that ended dark is woken on the first tick."""
    import dbus     # only here: the CLI commands stay quick to start
    props, conns = None, []
    laptop_level, tick = None, 0
    while True:
        try:
            if tick % 30 == 0:
                conns = connectors()
            off = screens_off(conns)
            if off != DARK.exists():
                with locked():
                    if off:
                        dark(laptop_level)
                    else:
                        wake()
            if not off and tick % 5 == 0:
                if props is None:
                    aura_path.cache_clear()     # asusd may have restarted
                    props = dbus.Interface(dbus.SystemBus().get_object("xyz.ljones.Asusd", aura_path() or "/xyz/ljones/aura"),
                                           "org.freedesktop.DBus.Properties")
                laptop_level = int(props.Get("xyz.ljones.Aura", "Brightness"))
        except Exception as e:      # asusd restarting, a keyboard unplugged mid-command: try again next tick
            props = None
            print(f"rgb.py: watch: {e}", file=sys.stderr)
        tick += 1
        time.sleep(1)


def status(cfg):
    out = []
    for d in devices():
        dev = d["id"]
        s = dict(cfg[dev])
        if dev == "laptop" and d["ready"] and s["on"]:     # show a step set with the Fn keys as it is
            step = asus_level()
            if step is not None and step != (0 if s["brightness"] <= 0 else min(3, 1 + (s["brightness"] - 1) * 3 // 100)):
                s["brightness"] = round(step * 100 / 3)
        effect, colours = plan(dev, s)
        screen, _ = screen_palette(s["follow"])
        out.append(dict(d, settings=s, effect=effect, colours=colours,
                        led=["#%02x%02x%02x" % led(c) for c in colours], screen=screen,
                        effects=[{"id": e, "name": n, "colours": k} for e, n, k in EFFECTS[dev]],
                        styles=[{"id": st, "name": STYLE_NAMES[st]} for st in DEVICE_STYLES[dev]]))
    # each screen's two accents as keyboards wear them, so the tab can preview a style before it's sent
    pals = {}
    for p in STATE.glob("palette-*.json"):
        try:
            v = json.loads(p.read_text())
            pals[p.stem[len("palette-"):]] = [vivid(v["primary"]), vivid(v["tertiary"])]
        except (OSError, ValueError, KeyError):
            continue
    return {"devices": out, "lead": lead(), "palettes": pals}


def run(cmd, args):
    cfg = load()
    if cmd == "set":
        dev = args[1] if len(args) > 1 else "all"
        if dev not in ("all", *cfg):
            sys.exit(f"no keyboard {dev!r} (have: {', '.join(cfg)})")
        for k in cfg:
            if dev in ("all", k):
                cfg[k].update(set_args(k, args[2:], strict=dev != "all"))
        save(cfg)
        errors = apply(cfg, dev, force_level="--brightness" in args or "--on" in args)
    else:
        only = args[args.index("--device") + 1] if "--device" in args and args.index("--device") + 1 < len(args) else None
        errors = apply(cfg, only, force="--force" in args)
    if errors:
        sys.exit("\n".join(errors))


@contextlib.contextmanager
def locked():
    """One writer at a time: hotplug, a re-theme, the tab and the watcher can all run at once."""
    STATE.mkdir(parents=True, exist_ok=True)
    with open(STATE / "rgb.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    cfg = load()
    if cmd == "status":
        print(json.dumps(status(cfg)))
        return
    if cmd == "watch":
        watch()
        return
    if cmd not in ("apply", "set"):
        sys.exit(__doc__)
    with locked():
        run(cmd, args)


if __name__ == "__main__":
    main()
