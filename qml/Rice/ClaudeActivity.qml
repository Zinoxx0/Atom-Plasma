import QtQuick
import QtCore
import Qt.labs.folderlistmodel

// What Claude Code is doing right now, for Clawd: ~/.cache/clawd/activity.json, written by Claude
// Code's hooks (~/.config/plasma-rice/clawd-hook.sh). A watch on its folder (inotify, no polling)
// re-reads it on every write; the file is read with XMLHttpRequest (QML_XHR_ALLOW_FILE_READ=1 in
// plasmashell's environment, see RicePalette.qml).
//
//   ClaudeActivity { id: claude }      Clawd { activity: claude.activity }
//
// activity: thinking | typing | building | reading | web | juggling | sweeping | waiting | done, "idle"
// once the hooks have reported and nothing is going on (Clawd then ignores the status line's `working`),
// "" with no hook data at all.
Item {
    id: ca
    visible: false

    property bool active: true
    property var last: null                     // {event, tool, ts}
    property real now: Date.now() / 1000
    readonly property real age: last ? now - Number(last.ts || 0) : 1e9

    readonly property string activity: {
        if (!last || age > 6 * 3600) return ""
        const e = last.event, t = String(last.tool || "")
        if (e === "stop") return age < 8 ? "done" : "idle"
        if (e === "notify") return age < 600 ? "waiting" : "idle"
        if (e === "end" || age > 180) return "idle"         // ended, or a session that died mid-way
        if (e === "compact") return "sweeping"
        if (e === "prompt" || e === "post") return "thinking"
        if (e !== "pre") return "idle"
        if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(t)) return "typing"
        if (/^(Bash|BashOutput|KillShell|KillBash)$/.test(t)) return "building"
        if (/^(Read|Grep|Glob|LS|NotebookRead)$/.test(t)) return "reading"
        if (/^(WebSearch|WebFetch)$/.test(t) || t.startsWith("mcp__")) return "web"
        if (/^(Task|Agent)$/.test(t)) return "juggling"
        if (t === "TodoWrite" || t === "ExitPlanMode") return "thinking"
        return "typing"
    }

    function read() {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || !x.responseText) return
            try {
                const j = JSON.parse(x.responseText)
                if (j && j.ts) { ca.now = Date.now() / 1000; ca.last = j }
            } catch (e) {}
        }
        x.open("GET", StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/clawd/activity.json")
        x.send()
    }
    FolderListModel {
        folder: ca.active ? StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/clawd" : ""
        nameFilters: ["activity.json"]
        showDirs: false
        onDataChanged: reread.restart()
        onRowsInserted: reread.restart()
    }
    Timer { id: reread; interval: 60; onTriggered: ca.read() }
    // the clock only ticks while something is going on (to let "done" and stale states expire)
    Timer {
        interval: ca.activity === "done" ? 2000 : 20000
        running: ca.active && ca.activity !== "" && ca.activity !== "idle"
        repeat: true
        onTriggered: ca.now = Date.now() / 1000
    }
    Component.onCompleted: read()
}
