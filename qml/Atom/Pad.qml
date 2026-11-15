pragma Singleton
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import Atom.Native

// The shell's half of the game controller (bin/pad.py, atom-plasma-pad.service, which drives the desktop
// with it). It tells the daemon what the shell has open (the launcher and the power page read the
// controller themselves: Shell(kind)) and holds the on-screen keyboard's state, which Keyboard (on each
// screen's sheet window) draws. The daemon talks back on the Bus, topic "pad":
//   { osk: "show" | "hide" | "toggle" | "move" (dx, dy) | "press" | "shift" | "layer" }   { action: "power" }
// and types what the keyboard's keys say: Key({code, mods}) a key of the active layout, Text(s) anything.
QtObject {
    id: pad

    property bool oskShown: false
    property string oskScreen: ""           // the screen it shows on: the focused window's, when it came up
    property string layer: "letters"        // letters | accents
    property int shift: 0                   // 0 off, 1 the next key, 2 locked (letters)
    property bool altgr: false              // the next key at its AltGr level
    signal move(int dx, int dy)             // the D-pad, while the keyboard shows (its focus moves)
    signal press()                          // A on the focused key

    function call(member, args) {
        const r = DBus.SessionBus.asyncCall({ service: "org.zinoxx.AtomPad", path: "/Pad", iface: "org.zinoxx.AtomPad",
                                              member: member, arguments: args })
        r.finished.connect(() => r.destroy())
    }
    // the daemon learns the shell's state (and asks for it with Peek "padShell" when it starts)
    function tell() {
        Bus.set("padShell", { kind: Shell.kind, osk: oskShown })
        call("Shell", [Shell.kind])
        call("Osk", [JSON.stringify({ shown: oskShown, screen: oskScreen })])
    }
    function show(scr) {
        oskScreen = scr || Windows.activeScreen || Shell.home("")
        shift = 0
        altgr = false
        oskShown = true
        tell()
        if (Shell.debug) console.warn("ATOM pad keyboard shown on", oskScreen)
    }
    function hide() {
        if (!oskShown) return
        oskShown = false
        layer = "letters"
        tell()
        if (Shell.debug) console.warn("ATOM pad keyboard hidden")
    }
    // typing (the daemon presses the keys: they reach the focused text field as a keyboard's would)
    function key(code, mods) {
        if (Shell.debug) { console.warn("ATOM pad key", code, mods); return }       // (the nested tests: never for real)
        call("Key", [JSON.stringify({ code: code, mods: mods || 0 })])
    }
    function text(s) {
        if (Shell.debug) { console.warn("ATOM pad text", s); return }
        call("Text", [String(s)])
    }
    function take(d) {
        if (!d) return
        if (d.action === "power") { Shell.toggle("power", Windows.activeScreen || Shell.home(""), null); return }
        switch (d.osk) {
        case "show": show(); break
        case "hide": hide(); break
        case "toggle": oskShown ? hide() : show(); break
        case "move": move(d.dx || 0, d.dy || 0); break
        case "press": press(); break
        case "shift": shift = (shift + 1) % 3; break
        case "layer": layer = layer === "letters" ? "accents" : "letters"; break
        }
    }
    property Connections busWatch: Connections {
        target: Bus
        function onMessage(topic, data) { if (topic === "pad") pad.take(data) }
    }
    property Connections shellWatch: Connections {
        target: Shell
        function onKindChanged() { pad.tell() }
    }
    Component.onCompleted: tell()           // (plasmashell started again: the keyboard isn't up any more)
}
