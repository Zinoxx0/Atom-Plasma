import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.plasma.workspace.dbus as DBus
import Atom
import Atom.Native
import Rice
import "../.."          // the launcher's look-free parts, shared by every style: HomeModel, ThemeModel

// Atom's launcher (settings launcher.style "atom"; designed in the Atom lab, 2026-11-16): the apps as an atom.
// Home's shells are rings around a core that shows what has the focus: Pinned inside, Play (games with their art,
// launchers), Recent outside. Up/down (a pad's D-pad too) turn the ring you're on: the next item comes to the slot,
// left of the core; left/right step to the next ring out or in. The pointer picks an item where it is (nothing
// turns under it), the wheel turns, a click opens. The scene is the backdrop chosen on the Theme page, pulled a
// little out of focus as it opens, lit by the focused item's colour. Every visual part here is this style's own:
// the simplified style (../../Stage.qml) can change without touching it. The window's life (layer shell, the desk
// cleared, the power page over it, following the pointer, resting) mirrors the simplified stage's, which has the
// history of each choice.
Window {
    id: stage
    required property var launcher
    required property var screenObj
    required property RicePalette rice
    required property Account account
    readonly property string screenName: screenObj ? screenObj.name : ""
    // what children get as their `stage` (`stage: stage` inside a child binds the child's own property to itself)
    readonly property Window atomStage: stage

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0
    y: screenObj ? screenObj.virtualY + topGap : 0
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height - topGap : 0
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: phase !== "closed"

    LayerShell.Window.scope: "utility"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                             | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.margins: ({ left: 0, top: topGap, right: 0, bottom: 0 })
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: powerOver ? LayerShell.Window.KeyboardInteractivityNone : LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // ------------------------------------------------------------------ sizes
    // u(): the launcher's unit (as the simplified style's). d(): the lab's pixels: it was drawn on the 1440p with the
    // launcher at 1.10 (unit 0.836), so d keeps those proportions at any size; the atom shrinks further to fit short
    // screens (atomK)
    readonly property real standard: Number(rice.values._standard) || 1
    readonly property real unit: Math.max(0.6, Math.min(0.8 * standard * launcher.homeSize, width / 1440, height / 900))
    function u(n) { return Math.round(n * unit) }
    function d(px) { return px * unit / 0.836 }
    readonly property real side: d(72)
    readonly property real atomK: Math.min(1, (height / 2 - d(60)) / d(590))
    readonly property point atomAt: Qt.point(width * 0.642, height * 0.53)
    FontLoader { id: wide; source: "../../../fonts/HubotSans.ttf" }     // Hubot Sans (OFL): names, numbers, tabs, the time
    readonly property string wideFamily: wide.status === FontLoader.Ready ? wide.name : Tokens.font.display
    // (with an axis set, font.weight no longer reaches the font's wght: wide(width, weight) sets both)
    function wide(w, wt) { return { "wdth": w, "wght": wt } }
    readonly property int openMs: Tokens.ms(1100)
    readonly property int closeMs: Tokens.ms(420)

    // ------------------------------------------------------------------ open / close (as the simplified stage)
    readonly property bool wanted: Shell.screen === screenName
                                   && (Shell.kind === "launcher" || (!!Shell.under && Shell.under.kind === "launcher" && Shell.under.screen === screenName))
    readonly property bool powerOver: wanted && Shell.kind === "power"
    property real coverP: 0
    onPowerOverChanged: {
        coverAnim.stop()
        coverWait.duration = powerOver ? 0 : Tokens.ms(230)
        coverMove.duration = powerOver ? Tokens.ms(220) : Tokens.ms(460)
        coverMove.easing.bezierCurve = powerOver ? Tokens.calmOut : Tokens.calmIn
        coverMove.to = powerOver ? 1 : 0
        coverAnim.start()
        if (!powerOver) Qt.callLater(() => keys.forceActiveFocus())
    }
    SequentialAnimation {
        id: coverAnim
        PauseAnimation { id: coverWait; duration: 0 }
        NumberAnimation { id: coverMove; target: stage; property: "coverP"; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
    }
    property string phase: "closed"             // closed, opening, open, closing
    signal opened()
    onWantedChanged: wanted ? begin() : end()
    property bool finder: false                 // search only, over the windows (KRunner's shortcut)
    property point rippleOrigin: Qt.point(width / 2, height / 2)
    function begin() {
        const a = Shell.anchor
        rippleOrigin = a && screenObj && Shell.screen === screenName
            ? Qt.point(a.x - screenObj.virtualX + a.width / 2, a.y - screenObj.virtualY - topGap + a.height / 2)
            : Qt.point(width / 2, height / 2)
        pointerAt = ""
        finder = !!(Shell.args && Shell.args.searchOnly)
        if (phase === "closed") {
            phase = "opening"
            waitFrame = true            // the desk clears on the first frame (onFrameSwapped)
            opened()
        } else {
            if (launcher.clearDesk && !finder) Windows.clear(screenName)
            phase = "opening"
            closeClock.stop()
            startOpen()
        }
    }
    function end() {
        if (phase === "closed" || phase === "closing") return
        phase = "closing"
        waitFrame = false
        openClock.stop()
        Windows.restore(screenName)
        startClose()
    }
    onPhaseChanged: {
        if (Shell.debug) console.warn("ATOM atom stage", screenName, "phase", phase, Date.now() % 100000)
        if (phase === "opening") { shownAt = Date.now(); coldOpen = idle || gameUp }
        if (phase === "closed") restTimer.restart()
        else { restTimer.stop(); idle = false }
    }
    // its video memory goes back while a fullscreen window is up or after 10 minutes closed (as the simplified's)
    property bool idle: false
    Timer { id: restTimer; interval: 10 * 60 * 1000; onTriggered: stage.idle = true }
    WindowRest { window: stage; resting: stage.phase === "closed" && (stage.idle || stage.gameUp) }
    readonly property bool gameUp: !!(Shell.bar && Shell.bar.covered && Shell.bar.covered.length)
    property bool coldOpen: false
    property double shownAt: 0
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) {
        waitFrame = false
        const took = Date.now() - shownAt
        if (Shell.debug || took >= 50) console.warn("ATOM atom stage first frame", screenName, took, "ms", coldOpen ? "(rested)" : "")
        if (launcher.clearDesk && !finder) Windows.clear(screenName)
        startOpen()
    }

    // ------------------------------------------------------------------ the choreography (one clock per move)
    // opening: the backdrop comes (and the scene pulls a little out of focus), the top and the caption come in, the
    // atom assembles (atomT 0..1: its electrons spiral out of the core); closing fades it all, a little closer
    property real bgO: 0
    property real pullT: 0
    property real topO: 0
    property real capO: 0
    property real atomT: 0
    property real planeO: 0
    property real planeS: 1
    property real openT: 0
    property real closeT: 0
    property var closeFrom: ({})
    NumberAnimation { id: openClock; target: stage; property: "openT"; from: 0; to: stage.openMs; duration: stage.openMs
                      onFinished: { stage.applyOpen(1e9); stage.phase = "open" } }
    NumberAnimation { id: closeClock; target: stage; property: "closeT"; from: 0; to: stage.closeMs; duration: stage.closeMs; onFinished: stage.closed() }
    onOpenTChanged: if (phase === "opening") applyOpen(openT)
    onCloseTChanged: if (phase === "closing") applyClose(closeT)
    function startOpen() { applyOpen(0); openClock.restart() }
    function applyOpen(t) {
        const D = openMs, home = finder ? 0 : 1
        bgO = home * M.track(t, 0, D * 0.45, M.enter)
        pullT = home * M.track(t, 0, D * 0.6, M.enter)
        planeO = M.track(t, D * 0.04, D * 0.5, M.enter)
        planeS = 1
        topO = M.track(t, D * 0.1, D * 0.5, M.enter)
        capO = M.track(t, D * 0.32, D * 0.55, M.enter)
        atomT = M.track(t, D * 0.1, D * 0.9, M.enter)
    }
    function startClose() { closeFrom = { plane: planeO, bg: bgO, pull: pullT }; applyClose(0); closeClock.restart() }
    function applyClose(t) {
        const D = closeMs, f = closeFrom
        planeO = (f.plane ?? 1) * (1 - M.track(t, 0, D * 0.55, M.exit))
        planeS = M.lerp(1, 1.035, M.track(t, 0, D * 0.55, M.exit))
        bgO = (f.bg ?? 1) * (1 - M.track(t, D * 0.12, D * 0.88, M.move))
        pullT = (f.pull ?? 1) * (1 - M.track(t, D * 0.12, D * 0.88, M.move))
    }
    function closed() {
        phase = "closed"
        coverAnim.stop(); coverP = 0
        searching = false
    }

    // ------------------------------------------------------------------ following the pointer (as the simplified's)
    property string pointerAt: ""
    readonly property bool following: stage.wanted && !stage.powerOver && (stage.phase === "opening" || stage.phase === "open")
    onFollowingChanged: if (following && Shell.bar) pointerSeen(Shell.bar.pointer || "")
    Connections { target: Shell; enabled: stage.following; function onBarChanged() { if (Shell.bar) stage.pointerSeen(Shell.bar.pointer || "") } }
    Timer { interval: 150; repeat: true; running: stage.following && !Shell.bar; triggeredOnStart: true; onTriggered: stage.askPointer() }
    function askPointer() {
        const reply = DBus.SessionBus.asyncCall({ service: "org.kde.KWin", path: "/KWin", iface: "org.kde.KWin", member: "activeOutputName", arguments: [] })
        reply.finished.connect(() => {
            const v = reply.isError ? "" : reply.value
            reply.destroy()
            stage.pointerSeen(String((v && typeof v === "object" && "value" in v) ? v.value : (v ?? "")))
        })
    }
    function pointerSeen(name) {
        if (!name || !wanted || phase === "closing") return
        const before = pointerAt
        pointerAt = name
        if (!before || name === before || name === screenName) return
        const there = Shell.island("launcher", name)
        if (!there) return
        Shell.open("launcher", name, there, { query: launcher.query, searchOnly: finder })
    }
    // Glimpse's strip (the top band) is never covered: the stage starts under it
    readonly property var strip: Shell.island("strip", screenName)
    readonly property real topGap: strip && screenObj ? Math.max(0, Math.round(strip.y + strip.height - screenObj.virtualY)) : 0

    // ------------------------------------------------------------------ the data
    HomeModel { id: hm; launcher: stage.launcher }
    readonly property alias home: hm
    property string page: "home"                // home | games | apps | theme
    readonly property var tabs: ["home", "games", "apps"]
    property string pageBefore: "home"
    function setPage(p) {
        if (p === page) return
        if (p === "theme") pageBefore = page === "theme" ? pageBefore : page
        page = p
        if (Shell.debug) console.warn("ATOM atom page", p)
    }
    function stepPage(dd) {
        if (page === "theme") { setPage(pageBefore); return }
        const i = tabs.indexOf(page)
        setPage(tabs[(i + dd + tabs.length) % tabs.length])
    }
    function toggleTheme() { setPage(page === "theme" ? pageBefore : "theme") }
    function openPowerHere() {          // (the shell keeps the launcher under the power page opened from it)
        const b = topBar.powerButton, p = b.mapToGlobal(0, 0)
        launcher.openPower({ x: p.x, y: p.y, width: b.width, height: b.height })
    }
    property date now: new Date()
    Timer { interval: 1000 * (60 - new Date().getSeconds()); running: stage.phase !== "closed"; repeat: true; onTriggered: { stage.now = new Date(); interval = 60000 } }

    // what the page has in focus (the pages report it): the caption, the core and the scene's light follow it
    property var focusItem: null                // { hero }: a game's art for the scene
    property var caption: ({ where: [], name: "" })
    property color focusTint: rice.primary      // the focus's colour (the page reads it off its icon)
    // the page in view: what A, X and the caption's tools do, the hints, which caption button the keys are on (-1: none)
    property var pageApi: null              // { act(i), tool(i), wheel(dy) }
    property var hints: ({ pad: [], keys: [] })
    property int capFocus: -1
    function act(i) { if (pageApi && pageApi.act) pageApi.act(i) }
    function tool(i) { if (pageApi && pageApi.tool) pageApi.tool(i) }
    function launch(it) {
        if (!it || !it.model) return
        it.model.trigger(it.row, "", null)
        launcher.close()
    }

    // ------------------------------------------------------------------ search (KRunner, through the launcher's runner)
    property bool searching: false
    function openSearch(text) {
        searching = true
        launcher.query = text || ""
    }
    function closeSearch() {
        if (finder) { launcher.close(); return }
        searching = false
        launcher.query = ""
    }

    // fresh every time it opens: Home, nothing searched
    onOpened: {
        page = "home"
        searching = false
        launcher.query = ""
        now = new Date()
        Qt.callLater(() => keys.forceActiveFocus())
        if (!finder) sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" launcher-data #data')
        if (finder || (Shell.args && Shell.args.query)) Qt.callLater(() => stage.openSearch(Shell.args.query || ""))
    }
    RiceShell { id: sh; onNewData: (source, data) => disconnectSource(source) }

    // ------------------------------------------------------------------ the scene
    Scene { id: scene; anchors.fill: parent; stage: atomStage }

    // ------------------------------------------------------------------ the content
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        opacity: stage.planeO * (1 - stage.coverP)
        scale: stage.planeS * M.lerp(1, 0.965, stage.coverP)
        Keys.onPressed: event => stage.onKey(event)

        MouseArea {     // bare space: a right click closes (a left one never does: a missed item mustn't)
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => { if (mouse.button === Qt.RightButton) stage.launcher.close() }
            onWheel: wheel => stage.wheeled(wheel)
        }
        // the page in view (only that one exists: a page is made when it's shown)
        Loader { anchors.fill: parent; active: stage.page === "home" && !stage.searching; sourceComponent: homePage }
        TopBar { id: topBar; stage: atomStage }
        Caption { id: cap; stage: atomStage; content: stage.caption; opacity: stage.capO }
        Hints { stage: atomStage }
    }

    Component { id: homePage; HomePage { stage: atomStage } }

    // ------------------------------------------------------------------ keys (a pad's arrive as keys too)
    signal pageKey(var event)           // the page in view handles what's left
    function wheeled(wheel) { if (pageApi && pageApi.wheel) pageApi.wheel(wheel.angleDelta.y || -wheel.pixelDelta.y) }
    function onKey(event) {
        if (powerOver) { event.accepted = true; return }
        if (!Gamepad.sending) Gamepad.inUse = false
        const k = event.key
        if (k === Qt.Key_Escape) { if (searching) closeSearch(); else if (page === "theme") setPage(pageBefore); else launcher.close(); event.accepted = true; return }
        if (k === Qt.Key_Tab) { stepPage(1); event.accepted = true; return }
        if (k === Qt.Key_Backtab) { stepPage(-1); event.accepted = true; return }
        pageKey(event)
        if (event.accepted) return
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            openSearch(event.text === "/" ? "" : event.text)
            event.accepted = true
        }
    }
    Connections {       // the pad's Y: the Theme page
        target: Gamepad
        enabled: stage.wanted && stage.phase === "open"
        function onButton(name) { if (name === "north" && !stage.searching) stage.toggleTheme() }
    }
}
