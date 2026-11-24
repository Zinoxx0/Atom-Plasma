// Rice islands: every screen has a rice bar, but its islands show on ONE screen at a time.
//
//   - the pointer's screen, once the pointer has been there for `settle` ms (a short beat: sweeping across
//     a screen on the way somewhere else moves nothing, and arriving still feels instant);
//   - unless a fullscreen window covers that screen's bar (a movie, a game: fullscreen AND in front of the
//     docks, KWin's active layer; a fullscreen window you clicked away from on the same screen drops
//     behind the bar and no longer counts). Then the islands go to the best free screen: the most
//     pixels, the nearest to the pointer's screen on a tie;
//   - every screen covered: no islands anywhere.
//   - the shell's own full-screen surfaces move them the same way (the launcher: its screens are the shell's
//     Bus state "cover", read back over D-Bus whenever one of its windows comes or goes), but they aren't
//     fullscreen windows to the rest of the shell: they're posted apart ("cover", not "covered").
//
// The bars are faded here, in the compositor, as whole windows: the islands' blur fades with them (a fade
// inside plasmashell would leave the blurred shapes behind). The leaving bar fades out while the arriving
// one fades in, quickly, with the rice's calm curves. Hidden bars keep their place (their space stays
// reserved, so no window ever resizes when the islands move) and are fully transparent.
//
// plasmashell is told over D-Bus (Atom.Native Bus, /Atom Post "bar"): which screen holds the islands, which
// screens are covered and the pointer's screen, so the widgets on hidden bars can rest and Clawd stays one.
// Settings: kwinrc [Script-rice_islands] settle, fadeIn, fadeOut, gap (ms).
import QtQuick
import org.kde.kwin

Item {
    id: root

    readonly property int settle: KWin.readConfig("settle", 70)
    readonly property int fadeIn: KWin.readConfig("fadeIn", 180)
    readonly property int fadeOut: KWin.readConfig("fadeOut", 120)
    readonly property int gap: KWin.readConfig("gap", 0)
    // the rice's calm curves (atom/tokens.py), as Easing.BezierSpline points
    readonly property var calmIn: [0.16, 1, 0.3, 1, 1, 1]
    readonly property var calmOut: [0.55, 0, 0.75, 0.2, 1, 1]
    // KWin's layers, bottom up: desktop 0, below 1, normal 2, dock 3, then above, the active fullscreen one...
    // (their numbers above the docks moved between KWin versions: only "in front of the docks" is relied on)
    readonly property int dockLayer: 3

    property string target: "?"                 // the screen with the islands; "" = none (all covered), "?" = not yet
    property string pointer: ""                 // the pointer's screen
    property var pointerRect: null
    property var covered: ({})                  // screen name -> true

    // a rice bar: plasmashell's dock along the bottom edge of its screen
    function isBar(w) {
        if (!w || w.deleted || !w.dock || w.resourceClass !== "plasmashell" || !w.output) return false
        const g = w.frameGeometry, o = w.output.geometry
        return Math.abs(g.y + g.height - (o.y + o.height)) < 2 && g.height < o.height / 4 && g.width > o.width / 2
    }
    function bars() { return Workspace.stackingOrder.filter(isBar) }

    property var shellCover: []                 // the screens the shell's launcher covers (Bus "cover")
    function taken(name) { return covered[name] || shellCover.indexOf(name) >= 0 }
    function coveredNow() {
        const c = {}
        for (const w of Workspace.stackingOrder)
            if (!w.deleted && w.fullScreen && !w.minimized && w.output && w.layer > dockLayer) c[w.output.name] = true
        return c
    }
    function pixels(o) {
        return Math.round(o.geometry.width * o.devicePixelRatio) * Math.round(o.geometry.height * o.devicePixelRatio)
    }
    function choose() {
        if (pointer && !taken(pointer)) return pointer
        const outs = Array.from(Workspace.screens)
        const free = outs.filter(o => !taken(o.name))
        if (!free.length) return ""
        const from = outs.find(o => o.name === pointer)
        const dist = o => {
            if (!from) return 0
            const a = from.geometry, b = o.geometry
            return Math.hypot(a.x + a.width / 2 - b.x - b.width / 2, a.y + a.height / 2 - b.y - b.height / 2)
        }
        free.sort((a, b) => pixels(b) - pixels(a) || dist(a) - dist(b))
        return free[0].name
    }

    // ------------------------------------------------------------------ fading the bars
    property var fades: ({})                    // window id -> its running fade
    Component {
        id: fader
        SequentialAnimation {
            id: seq
            property QtObject win
            property string key
            property real to: 1
            property int wait: 0
            property int length: 300
            property var curve: [0.16, 1, 0.3, 1, 1, 1]
            PauseAnimation { duration: seq.wait }
            NumberAnimation {
                target: seq.win; property: "opacity"; to: seq.to; duration: seq.length
                easing.type: Easing.BezierSpline; easing.bezierCurve: seq.curve
            }
            onStopped: {
                if (root.fades[seq.key] === seq) delete root.fades[seq.key]
                seq.destroy()
            }
        }
    }
    function fade(w, to, animate) {
        const key = String(w.internalId)
        // forget it first, then stop it; an entry can outlive its animation (the launcher's windows coming
        // and going on two screens re-ran this mid-fade) and a destroyed one has no stop() any more
        const old = fades[key]
        delete fades[key]
        if (old && typeof old.stop === "function") old.stop()
        if (!animate || Math.abs(w.opacity - to) < 0.01) { w.opacity = to; return }
        const arriving = to > w.opacity
        const a = fader.createObject(root, { win: w, key: key, to: to, wait: arriving ? gap : 0,
                                             length: arriving ? fadeIn : fadeOut, curve: arriving ? calmIn : calmOut })
        fades[key] = a
        a.start()
    }
    function shown(w) { return target === "?" || w.output.name === target }
    function apply(next, animate) {
        if (next !== target) {
            target = next
            for (const w of bars()) fade(w, shown(w) ? 1 : 0, animate)
        } else {
            // windows that showed up since (a restarted plasmashell's bars) or were left mid-way
            for (const w of bars())
                if (!fades[String(w.internalId)] && Math.abs(w.opacity - (shown(w) ? 1 : 0)) > 0.01) w.opacity = shown(w) ? 1 : 0
        }
        post()
    }

    // ------------------------------------------------------------------ telling plasmashell
    DBusCall {
        id: shellCall
        service: "org.kde.plasmashell"; path: "/Atom"; dbusInterface: "org.zinoxx.Atom"; method: "Post"
    }
    DBusCall {
        id: peekCall
        service: "org.kde.plasmashell"; path: "/Atom"; dbusInterface: "org.zinoxx.Atom"; method: "Peek"
        arguments: ["cover"]
        onFinished: returnValue => {
            let screens = []
            try { const v = JSON.parse(String(returnValue[0])); screens = v && v.screens ? v.screens : [] } catch (e) {}
            if (JSON.stringify(screens) === JSON.stringify(root.shellCover)) return
            root.shellCover = screens
            recheck.restart()
        }
    }
    // a window of the shell came or went (the launcher maps only while it's open): ask what it covers now
    function shellWindow(w) { return w && w.resourceClass === "plasmashell" && !root.isBar(w) }
    property string sent: ""
    function post(force) {
        const msg = JSON.stringify({ screen: target === "?" ? "" : target, covered: Object.keys(covered).sort(), cover: shellCover.slice().sort(), pointer: pointer })
        if (msg === sent && !force) return
        sent = msg
        shellCall.arguments = ["bar", msg]
        shellCall.call()
    }

    // ------------------------------------------------------------------ what moves the islands
    function locate() {
        const p = Workspace.cursorPos
        const r = pointerRect
        if (r && p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height) return false
        const o = Workspace.screenAt(p)
        if (!o || o.name === pointer) return false
        pointer = o.name
        pointerRect = { x: o.geometry.x, y: o.geometry.y, width: o.geometry.width, height: o.geometry.height }
        return true
    }
    Connections {
        target: Workspace
        function onCursorPosChanged() {
            if (!root.locate()) return
            root.post()
            if (root.pointer === root.target || root.choose() === root.target) settleTimer.stop()
            else settleTimer.restart()
        }
        function onWindowAdded(w) {
            root.watch(w)
            if (root.shellWindow(w)) peekCall.call()
            if (root.isBar(w)) {
                w.opacity = root.shown(w) ? 1 : 0           // a new bar never flashes up
                resend.restart()                            // plasmashell (re)started: tell it again
            }
            recheck.restart()
        }
        function onWindowRemoved(w) { if (root.shellWindow(w)) peekCall.call(); recheck.restart() }
        function onWindowActivated(w) {
            if (root.shellWindow(w) || root.shellCover.length > 0) peekCall.call()
            recheck.restart()
        }
        function onScreensChanged() { root.pointerRect = null; root.pointer = ""; root.locate(); recheck.restart() }
    }
    function watch(w) {
        w.fullScreenChanged.connect(recheck.restart)
        w.minimizedChanged.connect(recheck.restart)
        w.outputChanged.connect(recheck.restart)
        if (w.dock) w.frameGeometryChanged.connect(recheck.restart)
    }
    Timer { id: settleTimer; interval: root.settle; onTriggered: root.apply(root.choose(), true) }
    Timer {
        id: recheck
        interval: 50        // activation, layers and fullscreen settle together
        onTriggered: {
            if (root.shellCover.length > 0) peekCall.call()
            root.covered = root.coveredNow()
            // the pointer on its way to another screen: only a newly covered bar can't wait for it
            if (settleTimer.running && root.target !== "?" && !root.taken(root.target)) { root.post(); return }
            root.apply(root.choose(), true)
        }
    }
    Timer { id: resend; interval: 1500; onTriggered: { root.post(true); late.restart() } }
    Timer { id: late; interval: 4000; onTriggered: root.post(true) }

    Component.onCompleted: {
        for (const w of Workspace.stackingOrder) watch(w)
        locate()
        covered = coveredNow()
        apply(choose(), false)
    }
    // switched off: every bar shows again
    Component.onDestruction: {
        for (const w of bars()) w.opacity = 1
    }
}
