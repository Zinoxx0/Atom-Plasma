#!/usr/bin/env python3
"""Atom Plasma's display watcher: when screens are plugged in, unplugged, moved or rescaled, it runs
`rice.py screens-changed`, so every screen gets the whole rice (atom/reconcile.py) and an odd arrangement is
offered a fix.

It sleeps until something happens: KWin rewrites ~/.config/kwinoutputconfig.json whenever the output
configuration changes, and udev reports DRM hotplugs (udevadm monitor). Events come in bursts (a monitor
waking sends several), so it waits until things have been quiet for SETTLE seconds, and never runs two
reconciles at once (a change during one queues one more). It also runs once at the start of the session,
after plasmashell is up (the screens may differ from the last session's).

Unit: systemd/atom-plasma-displayd.service. Log: journalctl --user -u atom-plasma-displayd.
"""
import subprocess
import sys
from pathlib import Path

from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parent
CONFIG = Path.home() / ".config/kwinoutputconfig.json"
SETTLE = 2.5            # seconds of quiet before reconciling
START_WAIT = 90         # seconds to wait for plasmashell at the start


class Watcher:
    def __init__(self):
        self.timer = 0
        self.running = None
        self.again = False
        self.loop = GLib.MainLoop()

    def poke(self, why):
        print("change:", why, flush=True)
        if self.timer:
            GLib.source_remove(self.timer)
        self.timer = GLib.timeout_add(int(SETTLE * 1000), self.fire)

    def fire(self):
        self.timer = 0
        if self.running and self.running.poll() is None:
            self.again = True
            return False
        print("reconciling", flush=True)
        self.running = subprocess.Popen([sys.executable, str(ROOT / "rice.py"), "screens-changed"])
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, self.running.pid, self.done)
        return False

    def done(self, pid, status):
        print("reconciled" if status == 0 else f"reconcile failed ({status})", flush=True)
        if self.again:
            self.again = False
            self.poke("changes during the last run")

    # ------------------------------------------------------------ sources
    def watch_config(self):
        self.monitor = Gio.File.new_for_path(str(CONFIG)).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", lambda m, f, o, ev: ev in (
            Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.RENAMED,
            Gio.FileMonitorEvent.MOVED_IN, Gio.FileMonitorEvent.CREATED) and self.poke("kwinoutputconfig.json"))

    def watch_udev(self):
        self.udev = subprocess.Popen(["udevadm", "monitor", "--udev", "--subsystem-match=drm"],
                                     stdout=subprocess.PIPE, text=True, bufsize=1)
        GLib.io_add_watch(self.udev.stdout, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.udev_line)

    def udev_line(self, src, cond):
        if cond & GLib.IO_HUP:
            print("udevadm monitor ended", flush=True)
            self.loop.quit()        # systemd restarts the service
            return False
        line = src.readline()
        if " change " in line or " add " in line or " remove " in line:
            self.poke("udev " + line.split()[-2] if len(line.split()) > 1 else "udev")
        return True

    def at_start(self, waited=0):
        """Once plasmashell answers on D-Bus: the first reconcile of the session."""
        r = subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell"], capture_output=True)
        if r.returncode == 0 or waited >= START_WAIT:
            self.poke("session start")
            return False
        GLib.timeout_add_seconds(3, self.at_start, waited + 3)
        return False

    def run(self):
        self.watch_config()
        self.watch_udev()
        self.at_start()
        self.loop.run()
        if self.udev.poll() is None:
            self.udev.terminate()


if __name__ == "__main__":
    Watcher().run()
