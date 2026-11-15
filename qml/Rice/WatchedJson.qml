import QtQuick
import Qt.labs.folderlistmodel
import "WatchSupport.js" as WatchSupport

// A JSON file, read again whenever it changes (inotify, no polling) with XMLHttpRequest (no process:
// plasmashell runs with QML_XHR_ALLOW_FILE_READ=1). Bursts of changes are read once (`debounce`). An
// unchanged file leaves `value` alone (a new object would re-run every binding on it), and a file read
// half-written keeps the last good value until the next change.
// The watch is Atom.Native's FileWatch where it exists (plasmashell): one inotify instance for the whole
// process, no thread, a stat per change. Elsewhere (the splash, the logout screen, qml6 tests) a
// FolderListModel on the folder: a thread and an inotify instance each, and the folder listed again on every
// change in it (with 90 of them, plasmashell had 91 threads and 94 inotify instances; 2026-11-15).
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
    function poke() { if (active) reread.restart() }

    property QtObject watch: null
    Component {
        id: folderWatch
        FolderListModel {
            // (never an empty folder: that means the current directory, here the whole home folder)
            folder: wj.folder ? "file://" + wj.folder : "file:///nonexistent"
            nameFilters: wj.file ? [wj.file] : ["-"]
            showDirs: false
            onDataChanged: wj.poke()
            onRowsInserted: wj.poke()
            onRowsRemoved: wj.poke()
        }
    }
    Timer { id: reread; interval: wj.debounce; onTriggered: wj.read() }
    Component.onCompleted: {
        watch = WatchSupport.make(wj)
        if (watch) {
            watch.path = Qt.binding(() => wj.path)
            watch.changed.connect(wj.poke)
        } else {
            watch = folderWatch.createObject(wj)
        }
        if (active) read()
    }
    onActiveChanged: if (active) read()
    onPathChanged: { raw = ""; if (active) read() }
}
