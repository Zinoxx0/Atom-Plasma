import QtQuick
import Qt.labs.folderlistmodel

// A JSON file, read again whenever it changes: a watch on its folder (inotify, no polling) and
// XMLHttpRequest (no process: plasmashell runs with QML_XHR_ALLOW_FILE_READ=1). The writers replace the
// file (a temp file, then a rename), so one write is one change; bursts are read once (`debounce`).
// An unchanged file leaves `value` alone (a new object would re-run every binding on it), and a file
// read half-written keeps the last good value until the next change.
//
//   WatchedJson { id: f; path: "/home/me/.cache/claude-usage.json"; onChanged: ... }    f.value, f.raw
Item {
    id: wj
    visible: false

    property string path: ""            // absolute
    property bool active: true          // inactive: no reads (the watch stays, it costs nothing)
    property int debounce: 60           // ms
    property var value: null            // the parsed file; null while it's missing or empty
    property string raw: ""             // the text `value` came from
    property bool answered: false       // a read has come back at all (without QML_XHR_ALLOW_FILE_READ, none does)
    signal changed()

    readonly property string folder: path.slice(0, path.lastIndexOf("/"))
    readonly property string file: path.slice(path.lastIndexOf("/") + 1)

    function read() {
        if (!path) return
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            // (a read can land after this watcher was destroyed, e.g. a desk window remade at start)
            if (x.readyState !== XMLHttpRequest.DONE || typeof wj.take !== "function") return
            wj.answered = true
            wj.take(x.responseText || "")
        }
        x.open("GET", "file://" + path)
        x.send()
    }
    // also for text read some other way (RicePalette's `cat` fallback)
    function take(t) {
        if (t === raw) return
        if (!t) { raw = ""; value = null; changed(); return }
        try {
            const v = JSON.parse(t)
            raw = t
            value = v
            changed()
        } catch (e) {}
    }

    FolderListModel {
        // (never an empty folder: that means the current directory, here the whole home folder)
        folder: wj.folder ? "file://" + wj.folder : "file:///nonexistent"
        nameFilters: wj.file ? [wj.file] : ["-"]
        showDirs: false
        onDataChanged: if (wj.active) reread.restart()
        onRowsInserted: if (wj.active) reread.restart()
        onRowsRemoved: if (wj.active) reread.restart()
    }
    Timer { id: reread; interval: wj.debounce; onTriggered: wj.read() }
    Component.onCompleted: if (active) read()
    onActiveChanged: if (active) read()
    onPathChanged: { raw = ""; if (active) read() }
}
