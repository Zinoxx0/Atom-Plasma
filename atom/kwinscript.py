"""One-shot KWin scripts: load, run once, unload (even when something fails). With answer=True the script
can call `answer(value)` once and run() returns it as a string ("" if nothing came within `timeout`).
KWin scripts can't write files or return anything to whoever loaded them, so the answer comes back over
D-Bus, to a name this process owns for the moment, instead of being fished out of the journal."""
import itertools
import os
import tempfile

IFACE = "org.zinoxx.AtomPlasma.KWinRun"
_calls = itertools.count()


def run(js, answer=False, timeout=2.0):
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop, got, holder = GLib.MainLoop(), [], None
    n = next(_calls)
    tag, path_ = f"AtomPlasma{os.getpid()}_{n}", f"/a{n}"      # one of each per call: run() may be called again
    if answer:
        name = dbus.service.BusName(f"org.zinoxx.KWinRun.P{os.getpid()}", bus)

        class Answer(dbus.service.Object):
            @dbus.service.method(IFACE, in_signature="s")
            def Answer(self, value):
                got.append(str(value))
                loop.quit()

        holder = Answer(name, path_)
        js = (f'function answer(v) {{ callDBus("{name.get_name()}", "{path_}", "{IFACE}", "Answer", String(v)); }}\n'
              + js)
    fd, path = tempfile.mkstemp(prefix="kwin-run-", suffix=".js", dir=os.environ.get("XDG_RUNTIME_DIR"))
    os.write(fd, js.encode())
    os.close(fd)
    # (no introspection: KWin has two loadScript overloads, and the first one listed takes one string)
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting", introspect=False), "org.kde.kwin.Scripting")
    try:
        sid = scripting.loadScript(path, tag)
        bus.get_object("org.kde.KWin", f"/Scripting/Script{sid}", introspect=False).run(dbus_interface="org.kde.kwin.Script")
        if answer:
            GLib.timeout_add(int(timeout * 1000), loop.quit)
            loop.run()
    except dbus.DBusException:
        return ""
    finally:
        try:
            scripting.unloadScript(tag)
        except dbus.DBusException:
            pass
        if holder:
            holder.remove_from_connection()
        os.unlink(path)
    return got[0] if got else ""
