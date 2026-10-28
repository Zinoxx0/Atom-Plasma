#!/usr/bin/env python3
"""Atom Plasma: battery saver, the switch on the launcher's hero card (shown only while the laptop runs on
battery).

    battery-saver.py status     JSON: {"on": bool, "since": epoch seconds, ...}
    battery-saver.py on         the power profile goes to Power Save (power-profiles-daemon: the CPU's energy
                                preference "power", the ASUS firmware profile Quiet with its lower power limits
                                and quieter fans), the keyboard lights go off (both keyboards, rgb.py) and each
                                screen drops to its lowest refresh rate of 60 Hz or more at the same resolution
                                (kscreen-doctor; the laptop's 144 -> 60)
    battery-saver.py off [--plugged]
                                back as it was: the keyboards that were lit light up again, each screen gets its
                                refresh rate back and the profile from before returns, each unless it was changed
                                meanwhile. --plugged (the launcher saw the charger come back): PowerDevil picks
                                the AC profile itself, so all but the profile

The refresh rate is the one screen setting it may change (the user's choice, 2026-10-28): never brightness,
dimming, screen-off or sleep.
State: ~/.local/state/rice/battery-saver.json, replaced atomically (the launcher watches it).
"""
import json
import sys
import time

from atom import util
from atom.util import ROOT, STATE

FILE = STATE / "battery-saver.json"
RGB = ROOT / "rgb.py"
SAVER = "power-saver"


def load():
    s = util.load_json(FILE, {})
    return s if isinstance(s, dict) else {}


def profile():
    r = util.run("powerprofilesctl", "get", quiet=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def set_profile(name):
    util.run("powerprofilesctl", "set", name)


def outputs():
    """The screens that are on: (name, current mode, modes), from kscreen-doctor."""
    r = util.run("kscreen-doctor", "-j", quiet=True)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return []
    out = []
    for o in d.get("outputs", []):
        if o.get("connected") and o.get("enabled"):
            modes = {m["id"]: m for m in o.get("modes", [])}
            if o.get("currentModeId") in modes:
                out.append((o["name"], modes[o["currentModeId"]], list(modes.values())))
    return out


def set_mode(name, mode_id):
    util.run("kscreen-doctor", f"output.{name}.mode.{mode_id}")


def slow_screens():
    """Each screen down to its lowest rate of 60 Hz or more at its resolution: {output: [mode it had, mode
    set]} by mode name (ids can change when a screen is plugged in again)."""
    done = {}
    for name, cur, modes in outputs():
        same = [m for m in modes if m["size"] == cur["size"] and 59.5 <= m["refreshRate"] < cur["refreshRate"] - 1]
        if same:
            low = min(same, key=lambda m: m["refreshRate"])
            set_mode(name, low["id"])
            done[name] = [cur["name"], low["name"]]
    return done


def restore_screens(saved):
    """Back to the rate each screen had, unless it was changed since (or isn't plugged in)."""
    for name, cur, modes in outputs():
        was, ours = (saved.get(name) or [None, None])[:2]
        back = next((m for m in modes if m["name"] == was), None)
        if back and cur["name"] == ours:
            set_mode(name, back["id"])


def lit_keyboards():
    """The keyboards whose lighting is on in rgb.py's settings (plugged in or not: one unplugged now
    stays off when it comes back, until the saver ends)."""
    r = util.run(sys.executable, str(RGB), "status")
    try:
        return [d["id"] for d in json.loads(r.stdout)["devices"] if d["settings"].get("on")]
    except (ValueError, KeyError, TypeError):
        return []


def lights(ids, on):
    for dev in ids:
        util.run(sys.executable, str(RGB), "set", dev, "--on", "true" if on else "false")


def turn_on():
    if load().get("on"):
        return
    was = profile()
    keyboards = lit_keyboards()
    if was and was != SAVER:
        set_profile(SAVER)
    lights(keyboards, False)
    screens = slow_screens()
    util.save_json(FILE, {"on": True, "since": int(time.time()), "profile": was, "keyboards": keyboards,
                          "screens": screens})
    util.log("battery saver on (profile was %s, lights off: %s, screens: %s)", was or "?",
             ", ".join(keyboards) or "none", ", ".join(f"{k} {a} -> {b}" for k, (a, b) in screens.items()) or "none")


def turn_off(plugged=False):
    s = load()
    if not s.get("on"):
        return
    was = s.get("profile") or ""
    if not plugged and was and was != SAVER and profile() == SAVER:
        set_profile(was)
    lights(s.get("keyboards") or [], True)
    restore_screens(s.get("screens") or {})
    util.save_json(FILE, {"on": False, "since": int(time.time())})
    util.log("battery saver off%s", " (plugged in)" if plugged else "")


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "status":
        print(json.dumps({"on": False, **load()}))
        return
    if cmd not in ("on", "off"):
        sys.exit(__doc__)
    util.hold_lock("battery-saver")     # every bar has a launcher: they may all react to the charger at once
    if cmd == "on":
        turn_on()
    else:
        turn_off("--plugged" in args)


if __name__ == "__main__":
    main()
