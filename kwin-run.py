#!/usr/bin/env python3
"""Run a one-shot KWin script, and with --answer, wait for what it sends back.

    kwin-run.py [--answer] [--timeout SECONDS] < script.js

The script is loaded, run once and unloaded again (even when something fails). With --answer it can
call `answer(value)` once: kwin-run.py prints the value and exits (1 with nothing printed if no answer
came within the timeout, 2 s by default). KWin scripts can't write files or return anything to whoever
loaded them, so the answer comes back over D-Bus, to a name this process owns for the moment, instead
of being fished out of the journal after a print().

Used by tiling.sh (the focused window's screen) and Glimpse's glimpse-kwin.sh (moving a window).
"""
import os
import sys
import tempfile

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

IFACE = "org.zinoxx.AtomPlasma.KWinRun"


def main(args):
    want = "--answer" in args
    timeout = float(args[args.index("--timeout") + 1]) if "--timeout" in args else 2.0
    js = sys.stdin.read()
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop, got = GLib.MainLoop(), []
    tag = f"AtomPlasma{os.getpid()}"
    if want:
        name = dbus.service.BusName(f"org.zinoxx.KWinRun.P{os.getpid()}", bus)

        class Answer(dbus.service.Object):
            @dbus.service.method(IFACE, in_signature="s")
            def Answer(self, value):
                got.append(str(value))
                loop.quit()

        Answer(name, "/")
        js = (f'function answer(v) {{ callDBus("{name.get_name()}", "/", "{IFACE}", "Answer", String(v)); }}\n'
              + js)
    fd, path = tempfile.mkstemp(prefix="kwin-run-", suffix=".js", dir=os.environ.get("XDG_RUNTIME_DIR"))
    os.write(fd, js.encode())
    os.close(fd)
    # (no introspection: KWin has two loadScript overloads, and the first one listed takes one string)
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting", introspect=False), "org.kde.kwin.Scripting")
    try:
        sid = scripting.loadScript(path, tag)
        bus.get_object("org.kde.KWin", f"/Scripting/Script{sid}", introspect=False).run(dbus_interface="org.kde.kwin.Script")
        if want:
            GLib.timeout_add(int(timeout * 1000), loop.quit)
            loop.run()
    finally:
        try:
            scripting.unloadScript(tag)
        except dbus.DBusException:
            pass
        os.unlink(path)
    if want:
        if not got:
            sys.exit(1)
        print(got[0])


if __name__ == "__main__":
    main(sys.argv[1:])
