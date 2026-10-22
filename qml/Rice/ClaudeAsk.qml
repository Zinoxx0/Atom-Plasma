import QtQuick
import QtCore

// A check-in Claude raised with ~/.config/plasma-rice/ask.sh (~/.local/state/rice/ask.json): Clawd's
// big "!" on the bars and the desktop. It stays up until the user marks it done (the popup's Done
// button, or a click on the desktop Clawd) or Claude clears it once the user has answered in chat.
// Nothing else takes it down: no timeout, and it survives plasmashell restarts and reboots (the file
// lives in ~/.local/state). Watched with inotify (no polling), read with XMLHttpRequest (WatchedJson),
// so it costs nothing while nothing changes.
//
//   ClaudeAsk { id: checkIn }      checkIn.asking, checkIn.msg; checkIn.done() marks it done
//
// Other notices of the same shape use it too, with their own `file` and `ackCommand`: the important
// update the update check found (update-check.py, update.json).
Item {
    id: ca
    visible: false

    property bool active: true
    property string file: "ask.json"
    property string ackCommand: 'sh "$HOME/.config/plasma-rice/ask.sh" --ack'
    property var ask: null                      // {id, msg, since, ack} (+ the notice's own fields)
    readonly property bool asking: ask !== null && !(Number(ask.ack) > 0)
    readonly property string msg: asking ? String(ask.msg ?? "") : ""

    property string dir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.local/state/rice"
    function read() { file.read() }
    function done() {
        if (!ask) return
        ask = Object.assign({}, ask, { ack: Math.floor(Date.now() / 1000) })
        sh.connectSource(ca.ackCommand + " #ack")
    }
    RiceShell { id: sh }

    WatchedJson {
        id: file
        path: ca.dir + "/" + ca.file
        active: ca.active
        onChanged: ca.ask = file.value          // null once it's cleared
    }
    // a safety net in case a change was ever missed: one file read a minute, no process
    Timer { interval: 60000; running: ca.active; repeat: true; onTriggered: file.read() }
}
