#!/usr/bin/env python3
"""A bare StatusNotifierWatcher for the nested session (kded6 isn't running there): it keeps the list of
tray icons and of hosts, and says when icons come and go. Just enough for Atom.Native's Tray and Qt's
QSystemTrayIcon to find each other."""
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

IFACE = "org.kde.StatusNotifierWatcher"


class Watcher(dbus.service.Object):
    def __init__(self, bus):
        self.bus = bus
        self.items, self.hosts = [], []
        super().__init__(bus, "/StatusNotifierWatcher")
        bus.add_signal_receiver(self.owner_changed, "NameOwnerChanged", "org.freedesktop.DBus")

    @dbus.service.method(IFACE, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, spec, sender=None):
        if spec.startswith("/"):        # an object path: on the caller's connection
            spec = sender + spec
        if spec not in self.items:
            self.items.append(spec)
            self.StatusNotifierItemRegistered(spec)
            self.PropertiesChanged(IFACE, {"RegisteredStatusNotifierItems": dbus.Array(self.items, "s")}, [])

    @dbus.service.method(IFACE, in_signature="s")
    def RegisterStatusNotifierHost(self, name):
        if name not in self.hosts:
            self.hosts.append(name)
            self.StatusNotifierHostRegistered()

    @dbus.service.signal(IFACE, signature="s")
    def StatusNotifierItemRegistered(self, spec): pass

    @dbus.service.signal(IFACE, signature="s")
    def StatusNotifierItemUnregistered(self, spec): pass

    @dbus.service.signal(IFACE, signature="")
    def StatusNotifierHostRegistered(self): pass

    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated): pass

    def props(self):
        return {"RegisteredStatusNotifierItems": dbus.Array(self.items, "s"),
                "IsStatusNotifierHostRegistered": bool(self.hosts), "ProtocolVersion": 0}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self.props()[prop]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props()

    def owner_changed(self, name, old, new):
        if new:
            return
        for spec in [s for s in self.items if s.split("/")[0] == name]:
            self.items.remove(spec)
            self.StatusNotifierItemUnregistered(spec)
        self.hosts = [h for h in self.hosts if h != name]


DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
keep = dbus.service.BusName("org.kde.StatusNotifierWatcher", bus)
w = Watcher(bus)
print("watcher up", flush=True)
GLib.MainLoop().run()
