import QtQuick
import QtCore
import "WatchSupport.js" as WatchSupport

// Live Antigravity / Gemini activity from two zero-polling event-driven sources:
//   1. Native Antigravity hooks: ~/.cache/gemini/activity.json (written by bin/gemini-hook.sh)
//   2. T3 Code live run state:   watches ~/.t3/userdata/statev2.sqlite-wal via Atom.Native FileWatch
//      and queries bin/t3-activity.py (read-only SQLite, ~10 ms) only when the WAL changes.
// Drives the soft quadrupole gravity waves around the Gemini star while Gemini/Antigravity works.
Item {
    id: ga
    visible: false

    property bool active: true
    property var last: null                     // {event, tool, model, ts} from hook
    property bool t3Running: false              // true while T3 Code has an active antigravity run
    property real now: Date.now() / 1000
    readonly property string homeDir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    readonly property string cacheDir: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "")
    readonly property real age: last ? Math.max(0, now - Number(last.ts || 0)) : 1e9

    readonly property string hookActivity: {
        if (!last || age > 6 * 3600) return ""
        const e = String(last.event || "")
        if (e === "stop") return age < 10 ? "done" : "idle"
        if (e === "end" || age > 150) return "idle"
        if (e === "pre" || e === "start") return "thinking"
        if (e === "post" || e === "tool") return "working"
        return "idle"
    }
    readonly property bool hookWorking: hookActivity === "thinking" || hookActivity === "working"
    readonly property bool working: t3Running || hookWorking
    readonly property string activity: t3Running ? "working" : hookActivity
    readonly property string tool: last && hookWorking ? String(last.tool || "") : ""
    readonly property string model: last ? String(last.model || "") : ""

    // 1. Native hooks cache
    WatchedJson {
        id: file
        path: ga.cacheDir + "/gemini/activity.json"
        active: ga.active
        onChanged: if (file.value && file.value.ts) { ga.now = Date.now() / 1000; ga.last = file.value }
    }
    Timer {
        interval: ga.age < 30 ? 2000 : 15000
        running: ga.active && ga.hookActivity !== "" && ga.hookActivity !== "idle"
        repeat: true
        onTriggered: ga.now = Date.now() / 1000
    }

    // 2. T3 Code live run state (event-driven via FileWatch on statev2.sqlite-wal; zero polling when idle)
    property bool probing: false
    property bool probeAgain: false
    property real lastProbeMs: 0
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#t3act") >= 0) {
                ga.probing = false
                const out = String(data["stdout"] ?? "").trim()
                if (out) {
                    try {
                        const r = JSON.parse(out)
                        ga.t3Running = Number(r.running || 0) > 0
                    } catch (e) {}
                }
                if (ga.probeAgain) {
                    ga.probeAgain = false
                    t3Debounce.restart()
                }
            }
            disconnectSource(source)
        }
    }
    function probeT3() {
        if (!active) return
        if (probing) { probeAgain = true; return }
        probing = true
        lastProbeMs = Date.now()
        sh.connectSource('python3 "$HOME/.config/plasma-rice/bin/t3-activity.py" antigravity #t3act')
    }
    function scheduleProbe() {
        if (!active) return
        // While already known running, avoid spamming during dense streaming writes, but ALWAYS
        // run a trailing-edge check ~600 ms after writes stop so completion clears immediately.
        const since = Date.now() - lastProbeMs
        t3Debounce.interval = t3Running && since < 2000 ? 750 : 250
        t3Debounce.restart()
    }
    Timer { id: t3Debounce; interval: 250; onTriggered: ga.probeT3() }

    property QtObject walWatch: null
    property QtObject dbWatch: null
    Component.onCompleted: {
        walWatch = WatchSupport.make(ga)
        if (walWatch) {
            walWatch.path = ga.homeDir + "/.t3/userdata/statev2.sqlite-wal"
            walWatch.changed.connect(ga.scheduleProbe)
        }
        dbWatch = WatchSupport.make(ga)
        if (dbWatch) {
            dbWatch.path = ga.homeDir + "/.t3/userdata/statev2.sqlite"
            dbWatch.changed.connect(ga.scheduleProbe)
        }
        if (active) probeT3()
    }
    onActiveChanged: if (active) probeT3()
}
