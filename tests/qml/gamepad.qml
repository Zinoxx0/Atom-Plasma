// Atom.Native's Gamepad turned off from inside its own read: what happens when B closes the launcher (its
// Escape reaches a key handler that closes the surface) or A launches an app (a `button` handler does).
// tests/test_gamepad.py runs this offscreen and plays tools/nested/pad.py against it: a pretend pad
// appears, presses B, then A, then holds down, then goes away. Each time the Gamepad is off, it comes back
// on a moment later, as when the launcher opens again.
import QtQuick
import QtQuick.Window
import Atom.Native

Window {
    id: w
    width: 200
    height: 100
    visible: true

    function log(s) { console.log("pad " + s) }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            w.log("key " + e.key)
            if (e.key === Qt.Key_Escape) Gamepad.active = false      // B: the launcher closes on its Escape
        }
    }
    Connections {
        target: Gamepad
        function onButton(name) {
            w.log("button " + name)
            if (name === "south") Gamepad.active = false             // A: a launch closes it from the signal
        }
        function onPresentChanged() { w.log("present " + Gamepad.present) }
        function onActiveChanged() {
            w.log("active " + Gamepad.active)
            if (!Gamepad.active) again.start()
        }
    }
    Timer { id: again; interval: 250; onTriggered: Gamepad.active = true }
    Timer { interval: 15000; running: true; onTriggered: { w.log("timeout"); Qt.exit(1) } }

    Component.onCompleted: {
        requestActivate()
        Gamepad.active = true
        log("ready")
    }
}
