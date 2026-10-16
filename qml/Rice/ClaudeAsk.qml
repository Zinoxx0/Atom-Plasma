import QtQuick
import QtCore
import Qt.labs.folderlistmodel

// A check-in Claude raised with ~/.config/plasma-rice/ask.sh (~/.local/state/rice/ask.json): Clawd's
// big "!" on the bars and the desktop. It stays up until the user marks it done (the popup's Done
// button, or a click on the desktop Clawd) or Claude clears it once the user has answered in chat.
// Nothing else takes it down: no timeout, and it survives plasmashell restarts and reboots (the file
// lives in ~/.local/state). Watched with inotify (no polling), read with XMLHttpRequest (see
// RicePalette.qml), so it costs nothing while nothing changes.
//
//   ClaudeAsk { id: checkIn }      checkIn.asking, checkIn.msg; checkIn.done() marks it done
Item {
    id: ca
    visible: false

    property bool active: true
    property var ask: null                      // {id, msg, since, ack}
    readonly property bool asking: ask !== null && !(Number(ask.ack) > 0)
    readonly property string msg: asking ? String(ask.msg ?? "") : ""

    property string dir: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/state/rice"
    function read() {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (!x.responseText) { ca.ask = null; return }                  // cleared
            try { ca.ask = JSON.parse(x.responseText) } catch (e) {}       // half written: the next change reads it
        }
        x.open("GET", ca.dir + "/ask.json")
        x.send()
    }
    function done() {
        if (!ask) return
        ask = Object.assign({}, ask, { ack: Math.floor(Date.now() / 1000) })
        sh.connectSource('sh "$HOME/.config/plasma-rice/ask.sh" --ack #ack')
    }
    RiceShell { id: sh }

    // (the folder stays set: an empty FolderListModel folder means the current directory)
    FolderListModel {
        folder: ca.dir
        nameFilters: ["ask.json"]
        showDirs: false
        onDataChanged: if (ca.active) reread.restart()
        onRowsInserted: if (ca.active) reread.restart()
        onRowsRemoved: if (ca.active) reread.restart()
    }
    Timer { id: reread; interval: 60; onTriggered: ca.read() }
    // a safety net in case a change was ever missed: one file read a minute, no process
    Timer { interval: 60000; running: ca.active; repeat: true; onTriggered: ca.read() }
    Component.onCompleted: if (active) read()
    onActiveChanged: if (active) read()
}
