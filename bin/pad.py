#!/usr/bin/env python3
"""Atom Plasma: a game controller drives the desktop (for a TV seen from the couch).

    pad.py run                      the daemon (atom-plasma-pad.service)
    pad.py status                   what it's doing, as JSON: the controllers, the mode, the input used last
    pad.py mode auto|desktop|game   auto: game mode while a game has the focus; desktop / game: held there
    pad.py layout                   the keyboard layout as the on-screen keyboard draws it (JSON)

Desktop mode (Xbox names; another pad's face buttons by their place: X is the left one, Y the top one):
    left stick   the pointer (click it: slow and precise; again: back)     right stick  scrolling, both ways
    D-pad        the arrow keys
    A            click, or Enter after the D-pad (the input used last wins: the stick, or the D-pad)
    X            right click, or the Menu key after the D-pad              B   Esc
    Y            the on-screen keyboard           LB / RB   previous / next tab     LT / RT   back / forward
    View         every window (KWin's Overview)   Menu      the window before (Alt+Tab)
    Guide        the launcher (held: the power page)          Share   a screenshot      R3   middle click
    View + Menu held for a second: game mode on / off (auto again when switched back)
The on-screen keyboard (plasmashell: Atom Pad + KeyboardWindow) takes the buttons while it shows: the D-pad
walks its keys, A types one (a click after the stick), B hides it, X backspace, Y space, LB / RB move the
text cursor, LT shift, RT the next set of keys, View moves it to the top of the screen (or back down), Menu
Enter (the pointer drags it by any bare part). It comes up on its own when a text field
takes the focus right after the controller was used (KWin's input method state, VirtualKeyboard.active).
Game mode: the controller is left to the game (not grabbed, nothing sent) while a game has the focus: a
Steam game, Wine or Proton, a Lutris or Heroic game, gamescope, Steam's Big Picture. Guide held opens the
launcher. The shell's own full-screen surfaces (the launcher, the power page) read the controller
themselves (Atom.Native Gamepad): while one is open this steps back (the shell tells it: Shell(kind)).

How: evdev in, two uinput devices out (a pointer, a keyboard), the controller grabbed in desktop mode so
nothing sees it twice. Idle, it sleeps in poll(); a stick off its centre runs a 250 Hz loop (pointer
speed and scrolling are worked out per tick, sub-pixel remainders kept). Devices made by uinput (this
daemon's, the nested tests' pretend pad, Steam's virtual pads) are never read. KWin's focused window comes
from a small KWin script this loads (Focus over D-Bus). Typing: a key of the active layout (libxkbcommon
says which key makes which character), anything else through Atom Pad's input method (pkg/atom-pad-im: KWin
starts it and lets it commit text into the focused field), or, where that can't (an app without text-input
support), the clipboard, which gets its own back.
D-Bus: org.zinoxx.AtomPad /Pad: Shell, Osk, Focus, Key, Text, Layout, Status, Mode.
Settings (settings.json "pad", all optional): speed (pointer px/s at full tilt, 1700), scroll (wheel notches/s,
18), deadzone (0.14).
"""
import ctypes
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache/rice"
LAYOUT_FILE = CACHE / "pad-keyboard.json"       # the on-screen keyboard reads it (WatchedJson)
NAME = IFACE = "org.zinoxx.AtomPad"
PATH = "/Pad"
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def log(*a):
    print("pad:", *a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------- the keyboard layout
# The on-screen keyboard's character keys, as rows of the main block (evdev codes); the keyboard adds Tab,
# Backspace, Enter, Shift and the rest itself.
ROWS = [[41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
        [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 43],
        [30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40],
        [86, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53]]
DEAD = {"dead_acute": "´", "dead_grave": "`", "dead_circumflex": "^", "dead_tilde": "~", "dead_diaeresis": "¨",
        "dead_cedilla": "¸", "dead_abovering": "°", "dead_caron": "ˇ", "dead_macron": "¯", "dead_breve": "˘",
        "dead_doubleacute": "˝", "dead_ogonek": "˛", "dead_abovedot": "˙"}
SHIFT, ALTGR, CTRL = 1, 2, 4
TEST = os.environ.get("ATOM_PAD_TEST") == "1"       # (tests: a uinput "Atom test pad" counts as a controller)


class Keymap:
    """The active XKB layout through libxkbcommon: what each key types at each level, and back."""

    class Names(ctypes.Structure):
        _fields_ = [("rules", ctypes.c_char_p), ("model", ctypes.c_char_p), ("layout", ctypes.c_char_p),
                    ("variant", ctypes.c_char_p), ("options", ctypes.c_char_p)]

    def __init__(self, layout="us", variant="", model="pc105"):
        self.layout, self.variant = layout, variant
        x = ctypes.CDLL("libxkbcommon.so.0")
        x.xkb_context_new.restype = ctypes.c_void_p
        x.xkb_context_new.argtypes = [ctypes.c_int]
        x.xkb_keymap_new_from_names.restype = ctypes.c_void_p
        x.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(Keymap.Names), ctypes.c_int]
        x.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
        x.xkb_keymap_key_get_syms_by_level.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
                                                       ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
        x.xkb_keysym_to_utf8.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
        x.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
        x.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
        x.xkb_context_unref.argtypes = [ctypes.c_void_p]
        ctx = x.xkb_context_new(0)
        names = Keymap.Names(b"evdev", model.encode(), layout.encode(), variant.encode(), None)
        km = x.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
        if not km:
            x.xkb_context_unref(ctx)
            raise RuntimeError(f"no keymap for {layout}({variant})")
        self.keys = {}          # code -> [label per level]: a character, or a dead key's mark ("" none)
        self.dead = {}          # code -> [dead key name or "" per level]
        for row in ROWS:
            for code in row:
                labels, dead = [], []
                for level in range(4):
                    syms = ctypes.POINTER(ctypes.c_uint32)()
                    n = x.xkb_keymap_key_get_syms_by_level(km, code + 8, 0, level, ctypes.byref(syms))
                    ch, dn = "", ""
                    if n > 0:
                        buf = ctypes.create_string_buffer(16)
                        if x.xkb_keysym_to_utf8(syms[0], buf, 16) > 1:
                            ch = buf.value.decode("utf-8", "replace")
                        else:
                            nb = ctypes.create_string_buffer(64)
                            x.xkb_keysym_get_name(syms[0], nb, 64)
                            dn = nb.value.decode()
                            ch = DEAD.get(dn, "")
                            if not dn.startswith("dead_"):
                                dn = ""
                    labels.append(ch)
                    dead.append(dn)
                self.keys[code] = labels
                self.dead[code] = dead
        x.xkb_keymap_unref(km)
        x.xkb_context_unref(ctx)
        # a character -> the key and level that make it (the first found; dead keys never type themselves)
        self.chars = {}
        for code, labels in self.keys.items():
            for level, ch in enumerate(labels):
                if ch and not self.dead[code][level] and ch not in self.chars:
                    self.chars[ch] = (code, level)
        # (the 102nd key only where it types something no other key does: on a US keyboard it doesn't exist)
        lsgt = self.keys.get(86, [])
        others = {ch for code, labels in self.keys.items() if code != 86 for ch in labels[:2] if ch}     # (plain, shifted)
        self.has102 = bool(lsgt and lsgt[0] and lsgt[0] not in others)

    def rows(self):
        out = []
        for row in ROWS:
            keys = []
            for code in row:
                if code == 86 and not self.has102:
                    continue
                labels = self.keys[code]
                if not any(labels):
                    continue
                keys.append({"code": code, "l": labels, "dead": [bool(d) for d in self.dead[code]]})
            out.append(keys)
        return out

    def json(self):
        return {"layout": self.layout, "variant": self.variant, "rows": self.rows()}


def active_layout():
    """(layout, variant) of KWin's active keyboard layout (org.kde.keyboard), us when it can't say."""
    try:
        import dbus
        o = dbus.SessionBus().get_object("org.kde.keyboard", "/Layouts", introspect=False)
        layouts = o.getLayoutsList(dbus_interface="org.kde.KeyboardLayouts")
        i = int(o.getLayout(dbus_interface="org.kde.KeyboardLayouts"))
        lay = layouts[i] if 0 <= i < len(layouts) else layouts[0]
        return str(lay[0]) or "us", str(lay[1])
    except Exception:
        return "us", ""


# ---------------------------------------------------------------------------- games
GAME_CLASSES = ("gamescope", "steam_proton")
GAME_ENV = (b"SteamAppId=", b"SteamGameId=", b"STEAM_COMPAT_APP_ID=", b"LUTRIS_GAME_UUID=", b"HEROIC_APP_NAME=")
TERMINALS = ("konsole", "org.kde.konsole", "alacritty", "kitty", "foot", "wezterm", "org.wezfurlong.wezterm",
             "xterm", "ghostty", "com.mitchellh.ghostty")


def is_game(info):
    """Does the focused window ({cls, name, pid, caption, full}, from the KWin script) belong to a game?"""
    cls = (info.get("cls") or "").lower()
    if cls.startswith("steam_app_") or cls in GAME_CLASSES:
        return True
    if cls == "steam" and "big picture" in (info.get("caption") or "").lower():
        return True             # (Steam's own couch mode handles the controller)
    pid = int(info.get("pid") or 0)
    if pid <= 0:
        return False
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower()
        if exe.endswith(".exe") or exe.startswith("wine"):
            return True
        env = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
    except OSError:
        return False
    for e in env:
        for k in GAME_ENV:
            if e.startswith(k) and e[len(k):] not in (b"", b"0"):
                return True
    return False


# ---------------------------------------------------------------------------- the KWin script
FOCUS_JS = r"""
// Atom Pad: tell the controller daemon which window has the focus (it leaves the controller to games)
const seen = {};
function report() {
    const w = workspace.activeWindow;
    const info = w ? { cls: String(w.resourceClass || ""), name: String(w.resourceName || ""), pid: w.pid || 0,
                       full: !!w.fullScreen, caption: String(w.caption || "") } : {};
    callDBus("org.zinoxx.AtomPad", "/Pad", "org.zinoxx.AtomPad", "Focus", JSON.stringify(info));
}
function hook(w) {
    if (!w || seen[w.internalId]) return;
    seen[w.internalId] = true;
    w.fullScreenChanged.connect(report);
    w.captionChanged.connect(() => { if (w === workspace.activeWindow) report(); });
}
workspace.windowActivated.connect(w => { hook(w); report(); });
workspace.windowRemoved.connect(w => { delete seen[w.internalId]; });
hook(workspace.activeWindow);
report();
"""
SCRIPT_NAME = "atom-pad-focus"


# ---------------------------------------------------------------------------- the daemon
def run():
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from evdev import AbsInfo, InputDevice, UInput, ecodes as e, ff, list_devices  # noqa: F401
    from gi.repository import Gio, GLib

    from atom import util

    class Out(UInput):
        """A uinput device that doesn't wait to open its own event node: python-evdev retries for 2 s to get
        an InputDevice for it, which the user can't open anyway (its nodes are root's), so every start took 4 s."""
        def _find_device(self, fd):
            return None

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    cfg = (util.settings().get("pad") or {})
    SPEED = float(cfg.get("speed", 1700))           # logical px / s at full tilt (before the boost)
    SCROLL = float(cfg.get("scroll", 18)) * 120     # hi-res wheel units / s at full tilt
    DZ = float(cfg.get("deadzone", 0.14))
    TICK_MS = 4

    def call(service, path, iface, member, *args, sig=None):
        """A D-Bus call that never blocks the loop (its answer is ignored)."""
        try:
            o = bus.get_object(service, path, introspect=False)
            o.get_dbus_method(member, iface)(*args, signature=sig, reply_handler=lambda *a: None,
                                             error_handler=lambda err: log(member, "failed:", err.get_dbus_message()))
        except dbus.DBusException as err:
            log(member, "failed:", err.get_dbus_message())

    def post(data):
        """A message to the shell (Atom Bus topic "pad": the on-screen keyboard, the power page)."""
        call("org.kde.plasmashell", "/Atom", "org.zinoxx.Atom", "Post", "pad", json.dumps(data), sig="ss")

    class Pad:
        """One controller: its axes by role, its face buttons by place."""

        def __init__(self, dev):
            self.dev, self.path, self.name = dev, dev.path, dev.name
            caps = dev.capabilities()
            absinfo = dict(caps.get(e.EV_ABS, []))
            xbox = dev.info.vendor == 0x045E or "xbox" in dev.name.lower() or "x-box" in dev.name.lower()
            # (Xbox pads report their X as BTN_X = 0x133, which the kernel also calls BTN_NORTH: by place it's
            # the left one; Steam's own database says the same, x:b3. Pads that follow the kernel's spec put
            # the left button on BTN_WEST.)
            self.west, self.north = (e.BTN_X, e.BTN_Y) if xbox else (e.BTN_WEST, e.BTN_NORTH)
            if e.ABS_RX in absinfo:         # xpad: the right stick on RX/RY, the triggers on Z/RZ
                right, trig = (e.ABS_RX, e.ABS_RY), (e.ABS_Z, e.ABS_RZ)
            else:                           # Bluetooth (hid-generic): the right stick on Z/RZ, triggers BRAKE/GAS
                right, trig = (e.ABS_Z, e.ABS_RZ), (e.ABS_BRAKE, e.ABS_GAS)
            self.axes = {}
            for code, role in ((e.ABS_X, "lx"), (e.ABS_Y, "ly"), (right[0], "rx"), (right[1], "ry"),
                               (trig[0], "lt"), (trig[1], "rt")):
                if code in absinfo:
                    self.axes[code] = (role, absinfo[code])
            self.v = {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0, "lt": 0.0, "rt": 0.0}
            self.hat = [0, 0]
            self.watch = None
            self.grabbed = False
            self.rumble = None

        def norm(self, role, info, value):
            if role in ("lt", "rt"):
                return max(0.0, min(1.0, (value - info.min) / max(1, info.max - info.min)))
            mid, half = (info.min + info.max) / 2, max(1, (info.max - info.min) / 2)
            return max(-1.0, min(1.0, (value - mid) / half))

        def grab(self, on):
            if on == self.grabbed:
                return
            try:
                self.dev.grab() if on else self.dev.ungrab()
                self.grabbed = on
            except OSError as err:
                log("grab" if on else "ungrab", self.name, err)

        def buzz(self, ms=90, strong=0x3000, weak=0x7000):
            try:
                if self.rumble is not None:
                    self.dev.erase_effect(self.rumble)
                eff = ff.Effect(e.FF_RUMBLE, -1, 0, ff.Trigger(0, 0), ff.Replay(ms, 0),
                                ff.EffectType(ff_rumble_effect=ff.Rumble(strong_magnitude=strong, weak_magnitude=weak)))
                self.rumble = self.dev.upload_effect(eff)
                self.dev.write(e.EV_FF, self.rumble, 1)
            except (OSError, AttributeError):
                pass

    class Daemon:
        def __init__(self):
            self.pads = {}
            self.shell = ""             # the shell's open surface (launcher, power...: they read the pad)
            self.osk = False            # the on-screen keyboard shows
            self.osk_auto = False       # ...because a text field took the focus (it goes with it)
            self.focus = {}
            self.game = False           # a game has the focus
            self.forced = None          # None (auto) | "desktop" | "game"
            self.last = "keys"          # the input used last: "keys" (the D-pad) or "pointer" (the stick)
            self.last_pad_input = 0.0   # when the controller was last used (the keyboard comes up for it)
            self.precise = False
            self.guide_long = False
            self.chordheld = {"view": False, "menu": False}
            self.chord_done = False
            self.held = {}              # a button -> what its press did ([("key"|"btn", code), ...]), to undo on release
            self.timers = {}            # named GLib timeouts
            self.loop_id = None
            self.t_last = 0.0
            self.acc = [0.0, 0.0, 0.0, 0.0]     # sub-unit remainders: pointer x, y, wheel v, h
            self.wheel120 = [0, 0]              # hi-res units not yet a whole notch
            self.full_tilt = 0.0
            self.keymap = None
            self.ptr = Out({e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE],
                               e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL, e.REL_WHEEL_HI_RES,
                                          e.REL_HWHEEL_HI_RES]},
                              name="Atom Pad Pointer", vendor=0x1209, product=0xA70D, version=1)
            self.kbd = Out({e.EV_KEY: list(range(1, 249))}, name="Atom Pad Keys", vendor=0x1209, product=0xA70E,
                              version=1)
            GLib.timeout_add(800, self.flat_pointer)
            self.rescan()
            mon = Gio.File.new_for_path("/dev/input").monitor_directory(Gio.FileMonitorFlags.NONE, None)
            mon.connect("changed", lambda *a: self.later("rescan", 400, self.rescan))
            self.monitor = mon          # (kept: a dropped monitor stops)
            self.load_layout()

        # ---- small helpers
        def later(self, name, ms, fn):
            if name in self.timers:
                GLib.source_remove(self.timers.pop(name))

            def fire():
                self.timers.pop(name, None)
                fn()
                return False
            self.timers[name] = GLib.timeout_add(ms, fire)

        def cancel(self, name):
            if name in self.timers:
                GLib.source_remove(self.timers.pop(name))

        def key(self, code, down):
            self.kbd.write(e.EV_KEY, code, 1 if down else 0)
            self.kbd.syn()

        def tap(self, *codes):
            for c in codes:
                self.kbd.write(e.EV_KEY, c, 1)
                self.kbd.syn()
            for c in reversed(codes):
                self.kbd.write(e.EV_KEY, c, 0)
                self.kbd.syn()

        def button(self, code, down):
            self.ptr.write(e.EV_KEY, code, 1 if down else 0)
            self.ptr.syn()

        def flat_pointer(self):
            """KWin accelerates a mouse's motion; ours is already shaped: flat, at its own speed."""
            try:
                sysname = next((d.name for d in Path("/sys/class/input").glob("event*")
                                if (d / "device/name").read_text().strip() == "Atom Pad Pointer"), "")
                if not sysname:
                    return False
                o = bus.get_object("org.kde.KWin", f"/org/kde/KWin/InputDevice/{sysname}", introspect=False)
                props = dbus.Interface(o, "org.freedesktop.DBus.Properties")
                props.Set("org.kde.KWin.InputDevice", "pointerAccelerationProfileFlat", dbus.Boolean(True), signature="ssv")
                props.Set("org.kde.KWin.InputDevice", "pointerAcceleration", dbus.Double(0.0), signature="ssv")
            except dbus.DBusException as err:
                log("flat pointer:", err.get_dbus_message())
            return False

        # ---- controllers come and go
        def rescan(self):
            paths = set()
            for p in list_devices():
                try:
                    real = os.path.realpath(f"/sys/class/input/{os.path.basename(p)}/device")
                    if "/virtual/input/" in real and not (TEST and Path(real, "name").read_text().strip() == "Atom test pad"):
                        continue                        # made by uinput: ours, test pads, Steam's
                    if p in self.pads:
                        paths.add(p)
                        continue
                    dev = InputDevice(p)
                    caps = dev.capabilities()
                    if e.BTN_SOUTH not in caps.get(e.EV_KEY, []) or e.EV_ABS not in caps:
                        dev.close()
                        continue
                except OSError:
                    continue
                pad = Pad(dev)
                pad.watch = GLib.io_add_watch(dev.fd, GLib.PRIORITY_HIGH, GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP,
                                              lambda fd, cond, pad=pad: self.read(pad, cond))
                self.pads[p] = pad
                paths.add(p)
                log("controller:", pad.name, p)
            for p in list(self.pads):
                if p not in paths:
                    self.drop(self.pads[p])
            self.apply_mode()

        def drop(self, pad):
            log("controller gone:", pad.name)
            if pad.watch:
                GLib.source_remove(pad.watch)
                pad.watch = None
            try:
                pad.dev.close()
            except OSError:
                pass
            self.pads.pop(pad.path, None)
            self.release_all()

        def release_all(self):
            for name in list(self.held):
                self.undo(name)

        # ---- modes
        def mode(self):
            if self.forced == "game" or (self.forced is None and self.game):
                return "game"
            if self.osk:
                return "osk"
            if self.shell in ("launcher", "power"):
                return "shell"
            return "desktop"

        def apply_mode(self):
            m = self.mode()
            for pad in self.pads.values():
                pad.grab(m in ("desktop", "osk"))
            if m in ("game", "shell"):
                self.release_all()
            if getattr(self, "_mode", None) != m:
                log("mode", m)
                self._mode = m

        # ---- reading
        def read(self, pad, cond):
            if cond & (GLib.IO_ERR | GLib.IO_HUP):
                self.drop(pad)
                return False
            try:
                for ev in pad.dev.read():
                    self.event(pad, ev)
            except BlockingIOError:
                pass
            except OSError:
                self.drop(pad)
                return False
            return True

        def event(self, pad, ev):
            m = self.mode()
            # (every mode: the launcher's search asks for the keyboard too) A or the D-pad: what puts you into a text
            # field (B going back to a window whose field still has the focus mustn't bring the keyboard)
            if (ev.type == e.EV_KEY and ev.value == 1 and ev.code == e.BTN_SOUTH) or (ev.type == e.EV_ABS and ev.code in (e.ABS_HAT0X, e.ABS_HAT0Y) and ev.value):
                self.last_pad_input = time.monotonic()
            if ev.type == e.EV_ABS:
                if ev.code in (e.ABS_HAT0X, e.ABS_HAT0Y):
                    i = 0 if ev.code == e.ABS_HAT0X else 1
                    v = (ev.value > 0) - (ev.value < 0)
                    if v != pad.hat[i]:
                        if pad.hat[i]:
                            self.dpad(m, i, pad.hat[i], False)
                        pad.hat[i] = v
                        if v:
                            self.dpad(m, i, v, True)
                    return
                ax = pad.axes.get(ev.code)
                if not ax:
                    return
                role, info = ax
                pad.v[role] = pad.norm(role, info, ev.value)
                if role in ("lt", "rt"):
                    self.trigger(m, pad, role)
                elif m in ("desktop", "osk") and self.loop_id is None and self.moving(pad):
                    self.t_last = time.monotonic()
                    self.loop_id = GLib.timeout_add(TICK_MS, self.tick)
            elif ev.type == e.EV_KEY:
                down = ev.value != 0
                if ev.value == 2:           # (the kernel's own autorepeat on a held button)
                    return
                d = {e.BTN_DPAD_UP: (1, -1), e.BTN_DPAD_DOWN: (1, 1), e.BTN_DPAD_LEFT: (0, -1), e.BTN_DPAD_RIGHT: (0, 1)}.get(ev.code)
                if d:
                    self.dpad(m, d[0], d[1], down)
                    return
                name = {e.BTN_SOUTH: "a", e.BTN_EAST: "b", pad.west: "x", pad.north: "y", e.BTN_TL: "lb",
                        e.BTN_TR: "rb", e.BTN_SELECT: "view", e.BTN_START: "menu", e.BTN_MODE: "guide",
                        e.BTN_THUMBL: "l3", e.BTN_THUMBR: "r3", e.KEY_RECORD: "share"}.get(ev.code)
                if name:
                    self.press(m, name, down)

        def moving(self, pad):
            return math.hypot(pad.v["lx"], pad.v["ly"]) > DZ or math.hypot(pad.v["rx"], pad.v["ry"]) > DZ

        # ---- the sticks: one loop while either is off centre
        def tick(self):
            now = time.monotonic()
            dt = min(0.05, max(0.0, now - self.t_last))
            self.t_last = now
            m = self.mode()
            if m not in ("desktop", "osk"):
                self.loop_id = None
                return False
            # (several pads: the one pushed furthest)
            lx = ly = rx = ry = 0.0
            for p in self.pads.values():
                if math.hypot(p.v["lx"], p.v["ly"]) > math.hypot(lx, ly):
                    lx, ly = p.v["lx"], p.v["ly"]
                if math.hypot(p.v["rx"], p.v["ry"]) > math.hypot(rx, ry):
                    rx, ry = p.v["rx"], p.v["ry"]
            active = False
            r = math.hypot(lx, ly)
            if r > DZ:
                active = True
                t = min(1.0, (r - DZ) / (1 - DZ))
                # held at full tilt for a moment, it speeds up (a wide desktop is crossed in a second or so)
                self.full_tilt = self.full_tilt + dt if t > 0.97 else 0.0
                boost = 1 + min(1.3, max(0.0, self.full_tilt - 0.3) * 2.2)
                speed = SPEED * (t ** 2.3) * boost * (0.3 if self.precise else 1)
                self.acc[0] += lx / r * speed * dt
                self.acc[1] += ly / r * speed * dt
                ix, iy = int(self.acc[0]), int(self.acc[1])
                self.acc[0] -= ix
                self.acc[1] -= iy
                if ix or iy:
                    if ix:
                        self.ptr.write(e.EV_REL, e.REL_X, ix)
                    if iy:
                        self.ptr.write(e.EV_REL, e.REL_Y, iy)
                    self.ptr.syn()
                if self.last != "pointer":
                    self.last = "pointer"
                self.last_pad_input = now
            else:
                self.full_tilt = 0.0
                self.acc[0] = self.acc[1] = 0.0
            r2 = math.hypot(rx, ry)
            if r2 > DZ:
                active = True
                t = min(1.0, (r2 - DZ) / (1 - DZ))
                s = SCROLL * (t ** 2.0)
                self.acc[2] += -ry / r2 * s * dt          # (pushed up: the page goes up, as a wheel turned up)
                self.acc[3] += rx / r2 * s * dt
                wrote = False
                for i, (hi, lo) in ((2, (e.REL_WHEEL_HI_RES, e.REL_WHEEL)), (3, (e.REL_HWHEEL_HI_RES, e.REL_HWHEEL))):
                    n = int(self.acc[i])
                    if not n:
                        continue
                    self.acc[i] -= n
                    self.ptr.write(e.EV_REL, hi, n)
                    w = i - 2
                    self.wheel120[w] += n
                    whole = int(self.wheel120[w] / 120)
                    if whole:
                        self.wheel120[w] -= whole * 120
                        self.ptr.write(e.EV_REL, lo, whole)
                    wrote = True
                if wrote:
                    self.ptr.syn()
                self.last_pad_input = now
            else:
                self.acc[2] = self.acc[3] = 0.0
            if not active:
                self.loop_id = None
                return False
            return True

        # ---- the D-pad
        def dpad(self, m, axis, sign, down):
            name = ("left", "right", "up", "down")[axis * 2 + (sign > 0)]
            if not down:                # (a release always lets go of what the press did, whatever the mode now)
                self.undo("dpad-" + name)
                self.cancel("dpad-repeat")
                if m != "osk":
                    return
            if m in ("game", "shell"):
                return
            if down:
                self.last = "keys"
                self.last_pad_input = time.monotonic()
            if m == "osk":          # the keyboard isn't focused (the text field is): its moves go over D-Bus
                dx, dy = (sign, 0) if axis == 0 else (0, sign)
                if down:
                    post({"osk": "move", "dx": dx, "dy": dy})
                    self.later("dpad-repeat", 380, lambda: self.repeat_move(dx, dy))
                else:
                    self.cancel("dpad-repeat")
                return
            code = {"left": e.KEY_LEFT, "right": e.KEY_RIGHT, "up": e.KEY_UP, "down": e.KEY_DOWN}[name]
            self.do("dpad-" + name, [("key", code)])        # (held: KWin repeats it, as a held arrow key)

        def repeat_move(self, dx, dy):
            if self.mode() != "osk":
                return
            post({"osk": "move", "dx": dx, "dy": dy})
            self.later("dpad-repeat", 115, lambda: self.repeat_move(dx, dy))

        # ---- the triggers (as buttons, with some hysteresis)
        def trigger(self, m, pad, role):
            v, on = pad.v[role], getattr(pad, role + "_on", False)
            if not on and v > 0.55:
                setattr(pad, role + "_on", True)
                self.press(m, role, True)
            elif on and v < 0.35:
                setattr(pad, role + "_on", False)
                self.press(m, role, False)

        # ---- the buttons
        def press(self, m, name, down):
            if name == "guide":
                self.guide(m, down)
                return
            if not down and name in self.held:
                self.undo(name)
            if m == "game":
                if name in ("view", "menu"):
                    self.chord(name, down)
                return
            if m == "shell":
                return
            if name in ("view", "menu"):        # (on release: held together they switch the mode)
                self.chord(name, down)
                return
            if not down:
                self.undo(name)
                return
            if name == "share":
                self.tap(e.KEY_SYSRQ)
            elif m == "osk":
                self.osk_press(name)
            else:
                self.desktop_press(name)

        def do(self, name, actions):
            """Press what a button does and keep it for its release."""
            for kind, code in actions:
                (self.button if kind == "btn" else self.key)(code, True)
            self.held[name] = actions

        def undo(self, name):
            for kind, code in reversed(self.held.pop(name, [])):
                (self.button if kind == "btn" else self.key)(code, False)

        def desktop_press(self, name):
            pointer = self.last == "pointer"
            if name == "a":
                self.do(name, [("btn", e.BTN_LEFT)] if pointer else [("key", e.KEY_ENTER)])
            elif name == "b":
                self.do(name, [("key", e.KEY_ESC)])
            elif name == "x":
                self.do(name, [("btn", e.BTN_RIGHT)] if pointer else [("key", e.KEY_COMPOSE)])
            elif name == "y":
                self.show_keyboard(not self.osk, auto=False)
            elif name == "lb":
                self.do(name, [("key", e.KEY_LEFTCTRL), ("key", e.KEY_LEFTSHIFT), ("key", e.KEY_TAB)])
            elif name == "rb":
                self.do(name, [("key", e.KEY_LEFTCTRL), ("key", e.KEY_TAB)])
            elif name == "lt":
                self.do(name, [("key", e.KEY_LEFTALT), ("key", e.KEY_LEFT)])
            elif name == "rt":
                self.do(name, [("key", e.KEY_LEFTALT), ("key", e.KEY_RIGHT)])
            elif name == "r3":
                self.do(name, [("btn", e.BTN_MIDDLE)])
            elif name == "l3":
                self.precise = not self.precise
                for p in self.pads.values():
                    p.buzz(40 if self.precise else 25)

        def osk_press(self, name):
            if name == "a":
                if self.last == "pointer":
                    self.do(name, [("btn", e.BTN_LEFT)])
                else:
                    post({"osk": "press"})
            elif name == "b":
                self.show_keyboard(False)
            elif name == "x":
                self.do(name, [("key", e.KEY_BACKSPACE)])
            elif name == "y":
                self.do(name, [("key", e.KEY_SPACE)])
            elif name == "lb":
                self.do(name, [("key", e.KEY_LEFT)])
            elif name == "rb":
                self.do(name, [("key", e.KEY_RIGHT)])
            elif name == "lt":
                post({"osk": "shift"})
            elif name == "rt":
                post({"osk": "layer"})
            elif name == "r3":
                self.do(name, [("btn", e.BTN_MIDDLE)])
            elif name == "l3":
                self.precise = not self.precise

        # ---- View / Menu: a tap does theirs (on release), both held for a second switch game mode
        def chord(self, name, down):
            if down:
                self.chordheld[name] = True
                if all(self.chordheld.values()):
                    self.later("chord", 1000, self.chord_fire)
                return
            was = self.chordheld[name]
            self.chordheld[name] = False
            self.cancel("chord")
            if self.chord_done:                 # (the chord's own releases do nothing)
                if not any(self.chordheld.values()):
                    self.chord_done = False
                return
            if not was or any(self.chordheld.values()) or self.mode() in ("game", "shell"):
                return
            if name == "view":
                if self.mode() == "osk":
                    post({"osk": "flip"})       # (the keyboard to the top of the screen, or back down)
                else:
                    call("org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component",
                         "invokeShortcut", "Overview", sig="s")
            elif self.mode() == "osk":
                self.tap(e.KEY_ENTER)
            else:
                self.tap(e.KEY_LEFTALT, e.KEY_TAB)

        def chord_fire(self):
            self.chord_done = True
            game = self.mode() == "game"
            self.forced = None if game and self.forced == "game" else ("desktop" if game else "game")
            if self.forced == "desktop" and not self.game:
                self.forced = None
            self.apply_mode()
            on = self.mode() == "game"
            call("org.kde.plasmashell", "/org/kde/osdService", "org.kde.osdService", "showText",
                 "input-gamepad", "Controller: game mode" if on else "Controller: desktop", sig="ss")
            for p in self.pads.values():
                p.buzz(160 if on else 70)

        # ---- Guide: the launcher, held the power page (in a game: only held, the launcher)
        def guide(self, m, down):
            if down:
                self.guide_long = False
                self.later("guide", 600, self.guide_held)
                return
            if "guide" in self.timers:
                self.cancel("guide")
                if not self.guide_long and m != "game":
                    if self.osk:
                        self.show_keyboard(False)
                    call("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "activateLauncherMenu")

        def guide_held(self):
            self.guide_long = True
            if self.mode() == "game":
                call("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "activateLauncherMenu")
            else:
                post({"action": "power"})
            for p in self.pads.values():
                p.buzz(60)

        # ---- the on-screen keyboard
        def show_keyboard(self, on, auto=False):
            post({"osk": "show" if on else "hide"})
            self.osk_auto = auto and on

        def text_input(self, active):
            """KWin says a text field has (or lost) the focus: the keyboard comes for the controller."""
            if self.mode() == "game":
                return
            recent = time.monotonic() - self.last_pad_input < 3.25    # (the controller just put it there)
            if active and recent and not self.osk:
                log("a text field took the focus: the keyboard comes up")
                self.show_keyboard(True, auto=True)
            elif not active and self.osk and self.osk_auto:
                log("the text field let go: the keyboard goes")
                self.show_keyboard(False)

        # ---- typing (the on-screen keyboard)
        def load_layout(self):
            lay, var = active_layout()
            try:
                self.keymap = Keymap(lay, var)
            except (OSError, RuntimeError) as err:
                log("layout:", err)
                self.keymap = None
                return
            util.write_if_changed(LAYOUT_FILE, json.dumps(self.keymap.json(), ensure_ascii=False) + "\n")
            log("layout", lay, var)

        def type_key(self, code, mods):
            seq = []
            if mods & CTRL:
                seq.append(e.KEY_LEFTCTRL)
            if mods & SHIFT:
                seq.append(e.KEY_LEFTSHIFT)
            if mods & ALTGR:
                seq.append(e.KEY_RIGHTALT)
            self.tap(*seq, code)

        def type_text(self, text):
            """Keys for what the layout types; the rest (a run of it at a time) through the input method, else
            the clipboard."""
            km, rest = self.keymap, ""
            for ch in text + "\0":
                keyed = ch in "\n\t \0" or bool(km and ch in km.chars)
                if keyed and rest:
                    if not self.commit(rest):
                        self.paste(rest)
                    rest = ""
                if ch == "\0":
                    break
                if ch == "\n":
                    self.tap(e.KEY_ENTER)
                elif ch == "\t":
                    self.tap(e.KEY_TAB)
                elif ch == " ":
                    self.tap(e.KEY_SPACE)
                elif keyed:
                    code, level = km.chars[ch]
                    self.type_key(code, (SHIFT if level & 1 else 0) | (ALTGR if level & 2 else 0))
                else:
                    rest += ch

        def commit(self, text):
            """Into the focused text field through Atom Pad's input method (pkg/atom-pad-im, KWin starts it):
            any character, no clipboard. False when it isn't running or no field has the focus."""
            try:
                o = bus.get_object("org.zinoxx.AtomPadIM", "/IM", introspect=False)
                return bool(o.Commit(text, dbus_interface="org.zinoxx.AtomPadIM", timeout=0.5))
            except dbus.DBusException:
                return False

        def paste(self, text):
            """A character the layout can't type: through the clipboard (wl-copy, then Ctrl+V; a terminal's
            Ctrl+Shift+V), which gets what it held back (its text, or its first type) half a second later."""
            def run(argv, data=None):
                try:
                    if argv[0] == "wl-copy":        # (it forks a child that serves the clipboard: never wait on its pipes)
                        subprocess.run(argv, input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1)
                        return b""
                    return subprocess.run(argv, input=data, capture_output=True, timeout=1).stdout
                except (OSError, subprocess.TimeoutExpired):
                    return None
            types = (run(["wl-paste", "--list-types"]) or b"").decode(errors="replace").split()
            kind = next((t for t in types if t.startswith("text/plain")), types[0] if types else None)
            before = run(["wl-paste", "-n", "-t", kind]) if kind else None
            if run(["wl-copy", "--", text]) is None:
                log("paste: no wl-copy")
                return
            term = (self.focus.get("cls") or "").lower() in TERMINALS

            def paste_now():
                self.tap(e.KEY_LEFTCTRL, e.KEY_LEFTSHIFT, e.KEY_V) if term else self.tap(e.KEY_LEFTCTRL, e.KEY_V)
                return False

            def put_back():
                if before is not None:
                    run(["wl-copy", "-t", kind], before)
                else:
                    run(["wl-copy", "--clear"])
                return False
            GLib.timeout_add(60, paste_now)
            GLib.timeout_add(500, put_back)

        # ---- status
        def status(self):
            return {"mode": self.mode(), "forced": self.forced, "game": self.game, "shell": self.shell, "osk": self.osk,
                    "last": self.last, "precise": self.precise, "focus": self.focus,
                    "pads": [{"name": p.name, "path": p.path, "grabbed": p.grabbed} for p in self.pads.values()]}

    d = Daemon()

    class Service(dbus.service.Object):
        @dbus.service.method(IFACE, in_signature="s")
        def Shell(self, kind):
            d.shell = str(kind)
            d.apply_mode()

        @dbus.service.method(IFACE, in_signature="s")
        def Osk(self, state):           # {"shown": bool, "screen": name} (JSON: QML's D-Bus sends numbers as doubles)
            try:
                d.osk = bool(json.loads(str(state)).get("shown"))
            except (ValueError, AttributeError):
                d.osk = False
            if not d.osk:
                d.osk_auto = False
                d.cancel("dpad-repeat")
            d.apply_mode()

        @dbus.service.method(IFACE, in_signature="s")
        def Focus(self, info):
            try:
                d.focus = json.loads(str(info)) or {}
            except ValueError:
                d.focus = {}
            game = is_game(d.focus)
            if game != d.game:
                d.game = game
                if d.forced == "desktop" and not game:
                    d.forced = None
                log("focus", d.focus.get("cls"), "(a game)" if game else "")
            d.apply_mode()

        @dbus.service.method(IFACE, in_signature="s")
        def Key(self, key):             # {"code": evdev code, "mods": 1 shift | 2 AltGr | 4 Ctrl}
            try:
                k = json.loads(str(key))
                d.type_key(int(k["code"]), int(k.get("mods", 0)))
            except (ValueError, KeyError, TypeError) as err:
                log("Key:", err)

        @dbus.service.method(IFACE, in_signature="s")
        def Text(self, text):
            d.type_text(str(text))

        @dbus.service.method(IFACE, out_signature="s")
        def Layout(self):
            return json.dumps(d.keymap.json() if d.keymap else {}, ensure_ascii=False)

        @dbus.service.method(IFACE, out_signature="s")
        def Status(self):
            return json.dumps(d.status())

        @dbus.service.method(IFACE, in_signature="s")
        def Mode(self, m):
            m = str(m)
            d.forced = m if m in ("desktop", "game") else None
            d.apply_mode()

    name = dbus.service.BusName(NAME, bus, do_not_queue=True)
    svc = Service(name, PATH)  # noqa: F841
    log("on the bus as", name.get_name(), bus.get_unique_name())

    # KWin: the focused window (games), and whether a text field has the focus (the keyboard)
    def load_script():
        js = CACHE / "kwin-pad" / f"focus-{os.getpid()}.js"     # (a fresh path: KWin caches scripts by path)
        js.parent.mkdir(parents=True, exist_ok=True)
        for old in js.parent.glob("focus-*.js"):
            old.unlink(missing_ok=True)
        js.write_text(FOCUS_JS)
        try:
            s = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting", introspect=False), "org.kde.kwin.Scripting")
            if s.isScriptLoaded(SCRIPT_NAME):
                s.unloadScript(SCRIPT_NAME)
            sid = s.loadScript(str(js), SCRIPT_NAME)
            bus.get_object("org.kde.KWin", f"/Scripting/Script{sid}", introspect=False).run(dbus_interface="org.kde.kwin.Script")
        except dbus.DBusException as err:
            log("KWin script:", err.get_dbus_message())
        else:
            log("KWin script loaded:", sid)
        return False
    GLib.timeout_add(300, load_script)

    def vk_now():
        try:
            p = dbus.Interface(bus.get_object("org.kde.KWin", "/VirtualKeyboard", introspect=False), "org.freedesktop.DBus.Properties")
            return bool(p.Get("org.kde.kwin.VirtualKeyboard", "active"))
        except dbus.DBusException:
            return None

    def vk_changed(*a):
        # (settled: a field has to keep the focus for a moment; focus passing through a terminal on its way to
        # another window flips it on and off)
        def settle():
            v = vk_now()
            if v is not None:
                d.text_input(v)
        d.later("textfield", 250, settle)
    # (KWin's input method state: `active` follows the focused text field, whether or not an input method is
    # set up; activeClientSupportsTextInput only says the app could have one, and stays true)
    bus.add_signal_receiver(vk_changed, "activeChanged", "org.kde.kwin.VirtualKeyboard", "org.kde.KWin", "/VirtualKeyboard")
    bus.add_signal_receiver(lambda *a: d.load_layout(), "layoutChanged", "org.kde.KeyboardLayouts", None, "/Layouts")
    bus.add_signal_receiver(lambda *a: d.load_layout(), "layoutListChanged", "org.kde.KeyboardLayouts", None, "/Layouts")

    # the shell's state now (it pushes changes: Atom Pad.qml)
    def ask_shell():
        try:
            o = bus.get_object("org.kde.plasmashell", "/Atom", introspect=False)
            st = json.loads(str(o.Peek("padShell", dbus_interface="org.zinoxx.Atom")) or "null") or {}
            d.shell, d.osk = st.get("kind", ""), bool(st.get("osk", False))
            d.apply_mode()
        except (dbus.DBusException, ValueError, AttributeError):
            pass
        return False
    GLib.timeout_add(200, ask_shell)

    loop = GLib.MainLoop()
    from gi.repository import GLibUnix
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 15, loop.quit)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 2, loop.quit)
    log("running")
    try:
        loop.run()
    finally:
        d.release_all()
        for pad in list(d.pads.values()):
            pad.grab(False)
        try:
            s = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting", introspect=False), "org.kde.kwin.Scripting")
            s.unloadScript(SCRIPT_NAME)
        except dbus.DBusException:
            pass
        d.ptr.close()
        d.kbd.close()


def client():
    import dbus
    return dbus.Interface(dbus.SessionBus().get_object(NAME, PATH, introspect=False), IFACE)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "run":
        run()
    elif cmd == "status":
        try:
            print(json.dumps(json.loads(str(client().Status())), indent=2))
        except Exception as err:
            sys.exit(f"pad.py: the daemon isn't running ({err})")
    elif cmd == "mode" and len(argv) > 2 and argv[2] in ("auto", "desktop", "game"):
        client().Mode(argv[2])
        print(argv[2])
    elif cmd == "layout":
        lay, var = active_layout()
        print(json.dumps(Keymap(lay, var).json(), ensure_ascii=False, indent=1))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
