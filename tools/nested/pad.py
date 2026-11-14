#!/usr/bin/env python3
"""A pretend game controller (uinput) for the nested tests of Atom.Native's Gamepad: it appears, waits for
the rice to notice it, presses what it's told, and goes away.

    pad.py south east west north lb rb start select up down left right [hold:MS] [wait:MS] [stick-right]

up/down/left/right are the D-pad (a hat, like an Xbox pad); hold:MS keeps the next direction held that
long (the rice's own repeat runs meanwhile); stick-right etc. push the left stick all the way and let go.
The device is real for the whole machine while it lives (a second or two): only a surface whose Gamepad is
active (the launcher or the power overlay, open) reads it.
"""
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e

BUTTONS = {"south": e.BTN_SOUTH, "east": e.BTN_EAST, "west": e.BTN_WEST, "north": e.BTN_NORTH,
           "lb": e.BTN_TL, "rb": e.BTN_TR, "start": e.BTN_START, "select": e.BTN_SELECT}
HAT = {"up": (e.ABS_HAT0Y, -1), "down": (e.ABS_HAT0Y, 1), "left": (e.ABS_HAT0X, -1), "right": (e.ABS_HAT0X, 1)}
STICK = {"stick-up": (e.ABS_Y, -32768), "stick-down": (e.ABS_Y, 32767), "stick-left": (e.ABS_X, -32768), "stick-right": (e.ABS_X, 32767)}

caps = {
    e.EV_KEY: list(BUTTONS.values()),
    e.EV_ABS: [(e.ABS_X, AbsInfo(0, -32768, 32767, 16, 128, 0)), (e.ABS_Y, AbsInfo(0, -32768, 32767, 16, 128, 0)),
               (e.ABS_HAT0X, AbsInfo(0, -1, 1, 0, 0, 0)), (e.ABS_HAT0Y, AbsInfo(0, -1, 1, 0, 0, 0))],
}
with UInput(caps, name="Atom test pad", vendor=0x1209, product=0x0001, version=1) as ui:
    time.sleep(1.2)                     # the rice rescans /dev/input 400 ms after a node appears
    hold = 0.06
    for a in sys.argv[1:]:
        if a.startswith("hold:"):
            hold = int(a[5:]) / 1000
            continue
        if a.startswith("wait:"):
            time.sleep(int(a[5:]) / 1000)
            continue
        if a in BUTTONS:
            ui.write(e.EV_KEY, BUTTONS[a], 1); ui.syn(); time.sleep(0.05)
            ui.write(e.EV_KEY, BUTTONS[a], 0); ui.syn()
        elif a in HAT or a in STICK:
            code, v = HAT.get(a) or STICK[a]
            ui.write(e.EV_ABS, code, v); ui.syn(); time.sleep(hold)
            ui.write(e.EV_ABS, code, 0); ui.syn()
            hold = 0.06
        else:
            print("pad.py: unknown", a, file=sys.stderr)
        time.sleep(0.35)
    time.sleep(0.3)
