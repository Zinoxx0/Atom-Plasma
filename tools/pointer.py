#!/usr/bin/env python3
"""Drive the real cursor with a uinput absolute pointer, to test hover and click UI.
It moves the user's cursor, so don't run it while they're using the mouse.

    pointer.py move X Y [hold_s]          logical coordinates over the whole workspace
    pointer.py click X Y [left|right|middle]

As a module: `with Pointer() as p: p.move(x, y); p.click()`.
"""
import json
import subprocess
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e


def outputs():
    """Enabled outputs as {name, x, y, w, h} in logical pixels, from kscreen-doctor."""
    outs = json.loads(subprocess.run(["kscreen-doctor", "-j"], capture_output=True, text=True).stdout)["outputs"]
    res = []
    for o in outs:
        if not o.get("enabled"):
            continue
        scale = o.get("scale", 1)
        w, h = round(o["size"]["width"] / scale), round(o["size"]["height"] / scale)
        if o.get("rotation", 1) in (2, 8):
            w, h = h, w
        res.append({"name": o["name"], "x": o["pos"]["x"], "y": o["pos"]["y"], "w": w, "h": h})
    return res


def workspace():
    """Logical size of the whole desktop (all outputs)."""
    return (max(o["x"] + o["w"] for o in outputs()), max(o["y"] + o["h"] for o in outputs()))


BUTTONS = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}


class Pointer:
    def __init__(self):
        self.w, self.h = workspace()
        caps = {
            e.EV_KEY: list(BUTTONS.values()),
            e.EV_ABS: [(e.ABS_X, AbsInfo(0, 0, self.w - 1, 0, 0, 0)),
                       (e.ABS_Y, AbsInfo(0, 0, self.h - 1, 0, 0, 0))],
        }
        self.dev = UInput(caps, name="rice-test-pointer")
        time.sleep(0.6)     # let KWin pick the device up

    def move(self, x, y, steps=1):
        for i in range(1, steps + 1):
            self.dev.write(e.EV_ABS, e.ABS_X, int(x))
            self.dev.write(e.EV_ABS, e.ABS_Y, int(y))
            self.dev.syn()

    def glide(self, x0, y0, x1, y1, ms=300):
        """Move in small steps, so hover handlers see the pointer travel."""
        n = max(2, ms // 16)
        for i in range(n + 1):
            t = i / n
            self.move(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
            time.sleep(0.016)

    def click(self, button="left"):
        b = BUTTONS[button]
        self.dev.write(e.EV_KEY, b, 1); self.dev.syn(); time.sleep(0.05)
        self.dev.write(e.EV_KEY, b, 0); self.dev.syn()

    def close(self):
        self.dev.close()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] not in ("move", "click"):
        sys.exit(__doc__)
    x, y = float(sys.argv[2]), float(sys.argv[3])
    with Pointer() as p:
        p.move(x, y)
        if sys.argv[1] == "click":
            time.sleep(0.15)
            p.click(sys.argv[4] if len(sys.argv) > 4 else "left")
        time.sleep(float(sys.argv[4]) if sys.argv[1] == "move" and len(sys.argv) > 4 else 0.3)
