import QtQuick
import QtQuick.Window
import QtCore
import org.kde.layershell as LayerShell
import org.kde.plasma.workspace.dbus as DBus
import Atom
import Atom.Native
import Rice
import "../.."          // the launcher's look-free parts, shared by every style: HomeModel, ThemeModel
import "../../manager"  // Atom Manager (the settings page) and its gear, the same in every style

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
    // the colours every part wears: the screen's palette, or a wallpaper's being previewed on the Theme page (they glide
    // from one to the other: RicePalette eases its roles)
    property var previewValues: null
    RicePalette { id: lookPal; given: true; values: stage.previewValues || stage.rice.values }
    readonly property RicePalette look: lookPal

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
    // the caption's width (left): narrower on Games, so the library gets the room (its banners: as many as fit)
    readonly property real capWidth: page === "games" && !searching ? d(560) : d(780)
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
        zone = "page"
        // the input it was opened with (its hints show only that one's: the user, 2026-11-23): the pad's Guide, a
        // click on the jewel, else the keys (Meta). A follow from another screen keeps the one in use.
        if (!(Shell.args && Shell.args.carry)) {
            const padded = Date.now() - Shell.padOpened < 1500
            input = padded ? "pad" : Shell.args && Shell.args.input === "pointer" ? "pointer" : "keys"
            if (padded) Gamepad.inUse = true
        }
        pointerKnown = false
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
        if (Shell.debug && phase === "open") {      // where the top's buttons are (the nested tests click them: look-launcher.sh)
            const at = b => { const q = b.mapToItem(null, b.width / 2, b.height / 2); return Math.round(screenObj.virtualX + q.x) + " " + Math.round(screenObj.virtualY + topGap + q.y) }
            console.warn("ATOM home tabs at 0 0 search at", at(topBar.searchButton), "theme at", at(topBar.themeButton), "power at", at(topBar.powerButton))
        }
        if (phase === "open") { perfReport("opening"); if (dataWanted) { dataWanted = false; sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" launcher-data #data') } }
        if (phase === "closed") perfReport("closing")
        if (phase === "opening" || phase === "closing") { perfT = []; perfG = [] }
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
    // a probe for the choreography's smoothness: with ~/.cache/rice/perf present (or under Shell.debug), each opening
    // and closing logs its frames: "ATOM perf opening: N frames, mean, worst, over 10 ms"
    property bool perfOn: false
    property var perfT: []
    property var perfG: []                  // the GUI thread's heartbeat (2 ms timer): its gaps are stalls
    Timer { interval: 2; repeat: true; running: (stage.perfOn || Shell.debug) && (stage.phase === "opening" || stage.phase === "closing"); onTriggered: stage.perfG.push(Date.now()) }
    Component.onCompleted: {
        const x = new XMLHttpRequest()
        try { x.open("GET", StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/rice/perf", false); x.send(); perfOn = x.responseText.length > 0 } catch (e) { perfOn = false }
    }
    function perfReport(what) {
        const t = perfT; perfT = []
        const g = perfG; perfG = []
        const stalls = g.slice(1).map((v, i) => v - g[i]).filter(v => v > 8)
        if (!(perfOn || Shell.debug) || t.length < 3) return
        const d = t.slice(1).map((v, i) => v - t[i]), worst = Math.max(...d)
        console.warn("ATOM perf", what, screenName + ":", d.length, "frames, mean", (d.reduce((a, b) => a + b, 0) / d.length).toFixed(1), "ms, worst", worst, "ms, over 10 ms:", d.filter(v => v > 10).length, "| GUI stalls > 8 ms:", stalls.join(" "), "|", d.join(" "))
    }
    onFrameSwapped: {
        if ((perfOn || Shell.debug) && (phase === "opening" || phase === "closing")) perfT.push(Date.now())
        if (waitFrame) frameOne()
    }
    function frameOne() {
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
        const D = openMs, home = 1          // (the finder too: the same scene, over the windows, which stay)
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
        // just arrived: the screen it left gives its windows back and may still read as active for a moment (KWin's
        // activeOutputName follows the active window: it bounced the launcher between screens, nested 2026-11-23)
        if (Date.now() - shownAt < 400) { pointerAt = before; return }
        const there = Shell.island("launcher", name)
        if (Shell.debug) console.warn("ATOM stage pointer moved from", before, "to", name, there ? "(following)" : "(no launcher there)")
        if (!there) return
        Shell.open("launcher", name, there, { query: launcher.query, searchOnly: finder, carry: carryState() })
    }
    // what follows the launcher to another screen (the user, 2026-11-23: moving to another monitor brought it back to
    // Home): the page, the one the Theme page returns to, the search, the page's own focus (pageApi.save/restore)
    function carryState() {
        return { page: page, pageBefore: pageBefore, searching: searching,
                 focus: pageApi && pageApi.save ? pageApi.save() : null }
    }
    // Glimpse's strip (the top band) is never covered: the stage starts under it
    readonly property var strip: Shell.island("strip", screenName)
    readonly property real topGap: strip && screenObj ? Math.max(0, Math.round(strip.y + strip.height - screenObj.virtualY)) : 0

    // ------------------------------------------------------------------ the data
    HomeModel { id: hm; launcher: stage.launcher }
    readonly property alias home: hm
    property string page: "home"                // home | games | apps | theme | manager (Atom Manager)
    readonly property var tabs: ["home", "apps", "games"]
    property string pageBefore: "home"
    // a page (or the search) comes in as the launcher does: its rings spiral out of the core (one short clock)
    property double pageAsked: 0
    NumberAnimation { id: pageClock; target: stage; property: "atomT"; from: 0; to: 1; duration: Tokens.ms(820) }
    function pageIn() { pageAsked = Date.now(); if (phase === "open") pageClock.restart() }
    onSearchingChanged: pageIn()
    function pageLoaded(name) { if (Shell.debug) console.warn("ATOM atom page made", name, Date.now() - pageAsked, "ms") }
    function setPage(p) {
        if (p === page) return
        pageIn()
        if (p === "theme" || p === "manager") pageBefore = page === "theme" || page === "manager" ? pageBefore : page
        page = p
        if (Shell.debug) console.warn("ATOM atom page", p)
    }
    function stepPage(dd) {
        if (page === "theme" || page === "manager") { setPage(pageBefore); return }
        const i = tabs.indexOf(page)
        setPage(tabs[(i + dd + tabs.length) % tabs.length])
    }
    function toggleTheme() { setPage(page === "theme" ? pageBefore : "theme") }
    // Atom Manager (the gear at the bottom right, F1, the pad's View): at a section ("updates" from the banner)
    property string managerAt: ""
    function toggleManager(sec) {
        if (page === "manager") { if (sec && pageApi && pageApi.openSection) pageApi.openSection(sec); else setPage(pageBefore); return }
        if (searching) closeSearch()
        managerAt = sec || ""
        zone = "page"
        setPage("manager")
    }
    function takeKeys() { keys.forceActiveFocus() }         // (an editor on the Theme page closed)
    // Meta+Shift+W: the Theme page, at a section (walls, colours or lights)
    Connections {
        target: stage.launcher
        enabled: stage.wanted
        function onThemeAskChanged() {
            if (stage.page !== "theme") stage.setPage("theme")
            else if (stage.pageApi && stage.pageApi.openSection) stage.pageApi.openSection(stage.launcher.themeRow)
        }
    }
    function openPowerHere() {          // (the shell keeps the launcher under the power page opened from it)
        const b = topBar.powerButton, p = b.mapToGlobal(0, 0)
        launcher.openPower({ x: p.x, y: p.y, width: b.width, height: b.height })
    }
    property date now: new Date()
    Timer { interval: 1000 * (60 - new Date().getSeconds()); running: stage.phase !== "closed"; repeat: true; onTriggered: { stage.now = new Date(); interval = 60000 } }

    // what the page has in focus (the pages report it): the caption, the core and the scene's light follow it
    property var focusItem: null                // { hero }: a game's art for the scene
    property var caption: ({ where: [], name: "" })
    property color focusTint: look.primary      // the focus's colour (the page reads it off its icon)
    // the page in view: what A, X and the caption's tools do, the hints, which caption button the keys are on (-1: none)
    property var pageApi: null              // { act(i), tool(i), wheel(dy, at): at = the pointer, in the page }
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

    // fresh every time it opens (Home, nothing searched), unless it follows the pointer from another screen
    onOpened: {
        pageAsked = Date.now()
        const carry = Shell.args && Shell.args.carry && !finder ? Shell.args.carry : null
        if (carry && Shell.debug) console.warn("ATOM stage carried page", carry.page)
        searching = false
        page = carry ? carry.page || "home" : "home"
        pageBefore = carry ? carry.pageBefore || "home" : "home"
        if (carry && carry.focus) { const f = carry.focus; Qt.callLater(() => { if (stage.pageApi && stage.pageApi.restore) stage.pageApi.restore(f) }) }
        if (!carry || !carry.searching) launcher.query = ""
        now = new Date()
        Qt.callLater(() => keys.forceActiveFocus())
        dataWanted = !finder       // (fetched once it has opened: forking plasmashell mid-animation stalled its frames)
        if (finder || (Shell.args && Shell.args.query) || (carry && carry.searching)) Qt.callLater(() => stage.openSearch(Shell.args.query || ""))
    }
    property bool dataWanted: false
    RiceShell { id: sh; onNewData: (source, data) => { disconnectSource(source); if (source.indexOf("#scan") >= 0) stage.say("Library up to date") } }
    function shell(cmd) { sh.connectSource(cmd) }          // (fixed commands only: each one is its own source name)
    // a short line of news over the hints (scan done, ...)
    property string news: ""
    function say(t) { news = t; newsTimer.restart() }
    Timer { id: newsTimer; interval: 2200; onTriggered: stage.news = "" }

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
            onPressed: if (Shell.debug) console.warn("ATOM atom bare press")
            onClicked: mouse => { if (mouse.button === Qt.RightButton) stage.launcher.close() }
            onWheel: wheel => stage.wheeled(wheel.angleDelta.y || -wheel.pixelDelta.y, Qt.point(wheel.x, wheel.y))
        }
        // the page in view (only that one exists: a page is made when it's shown)
        Loader { anchors.fill: parent; active: stage.page === "home" && !stage.searching; sourceComponent: homePage; onLoaded: stage.pageLoaded("home") }
        Loader { anchors.fill: parent; active: stage.searching; sourceComponent: searchPage; onLoaded: stage.pageLoaded("search") }
        Loader { anchors.fill: parent; active: stage.page === "apps" && !stage.searching; sourceComponent: appsPage; onLoaded: stage.pageLoaded("apps") }
        Loader { anchors.fill: parent; active: stage.page === "games" && !stage.searching; sourceComponent: gamesPage; onLoaded: stage.pageLoaded("games") }
        Loader { anchors.fill: parent; active: stage.page === "theme" && !stage.searching; sourceComponent: themePage; onLoaded: stage.pageLoaded("theme") }
        Loader { anchors.fill: parent; active: stage.page === "manager" && !stage.searching; sourceComponent: managerPage; onLoaded: stage.pageLoaded("manager") }
        // the wheel, over the page (the simplified's wheelLayer): a layer that takes only the wheel. Under the page, the
        // bare MouseArea above missed it more often than not (nested, 2026-11-22). Not on the Theme page: its grids
        // scroll themselves first (the bare MouseArea still hands it the rest)
        Item {
            anchors.fill: parent
            z: 50
            enabled: stage.page !== "theme" && stage.page !== "manager"
            WheelHandler {
                id: wheelAll
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: ev => stage.wheeled(ev.angleDelta.y || -ev.pixelDelta.y, wheelAll.point.position)
            }
        }
        Text {      // news (a scan done...)
            x: stage.side; y: stage.height - stage.d(110)
            text: stage.news; color: stage.look.fg; opacity: stage.news ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(240) } }
            font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.d(16)
        }
        TopBar { id: topBar; stage: atomStage }
        // (the Theme page and Atom Manager have their own header and footer: the shared pages)
        Caption { id: cap; stage: atomStage; content: stage.caption; opacity: stage.capO; visible: stage.page !== "theme" && stage.page !== "manager" }
        Hints { stage: atomStage; visible: stage.page !== "theme" && stage.page !== "manager" }
        ManagerButton {     // Atom Manager's gear, bottom right (the shared pages have their hints there)
            look: stage.look
            unit: stage.unit
            x: stage.width - stage.side - width
            y: stage.height - height - stage.d(28)
            visible: stage.page !== "theme" && stage.page !== "manager"
            opacity: stage.topO
            glyph: !stage.keysShown ? "" : stage.input === "pad" ? "⧉" : "F1"
            onOpen: sec => stage.toggleManager(sec)
        }
    }

    Component { id: homePage; HomePage { stage: atomStage } }
    Component { id: searchPage; SearchPage { stage: atomStage } }
    Component { id: appsPage; AppsPage { stage: atomStage } }
    Component { id: gamesPage; GamesPage { stage: atomStage } }
    Component { id: themePage; ThemePage { stage: atomStage } }
    Component {
        id: managerPage
        ManagerPage {
            id: mgr
            anchors.fill: parent
            launcher: stage.launcher
            rice: stage.rice
            look: stage.look
            screenName: stage.screenName
            unit: stage.unit
            topInset: stage.d(140)
            wideFamily: stage.wideFamily
            veil: 0.42
            active: stage.zone !== "top"
            opacity: stage.capO
            origin: Qt.point(stage.screenObj ? stage.screenObj.virtualX : 0, (stage.screenObj ? stage.screenObj.virtualY : 0) + stage.topGap)
            onLeave: stage.enterTop()
            onGiveKeys: stage.takeKeys()
            Component.onCompleted: {
                stage.pageApi = { key: e => mgr.key(e), wheel: dy => mgr.wheel(dy), openSection: s => mgr.openSection(s),
                                  save: () => ({ section: mgr.section }), restore: f => { if (f.section) mgr.setSection(f.section, true) },
                                  enter: () => mgr.setSection(mgr.section, true) }
                stage.hints = { pad: [], keys: [] }
                stage.caption = { where: [], name: "" }
                const sec = stage.managerAt
                stage.managerAt = ""
                Qt.callLater(() => mgr.openSection(sec || "updates"))
            }
        }
    }

    // ------------------------------------------------------------------ the input in use: its hints only
    // "pointer" (nothing shown: the user, 2026-11-23), "keys" or "pad". A real pointer move makes it the pointer
    // (content sliding under a still one doesn't move it here: this layer never moves); a key or a pad's button the
    // keys or the pad.
    property string input: "keys"
    onInputChanged: { if (input === "pointer") zone = "page"; if (Shell.debug) console.warn("ATOM atom input", input) }
    property bool pointerKnown: false
    property point pointerLast: Qt.point(0, 0)
    HoverHandler {
        target: null
        onPointChanged: {
            const p = point.position
            if (stage.pointerKnown && Math.abs(p.x - stage.pointerLast.x) + Math.abs(p.y - stage.pointerLast.y) > 1 && stage.phase !== "closed")
                stage.input = "pointer"
            stage.pointerKnown = true
            stage.pointerLast = p
        }
    }
    readonly property bool keysShown: input !== "pointer"

    // ------------------------------------------------------------------ the top bar, for the keys and the pad
    // (the user, 2026-11-23: Theme and power couldn't be reached without the pointer). The pad's Menu (≡) or F10
    // from anywhere, Up from the top of a grid, or up past the Theme page's top; Left/Right walk it, A/Enter picks,
    // Down or B goes back to the page.
    property string zone: "page"                // page | top
    property int topAt: 0
    readonly property var topItems: ["jewel", "home", "apps", "games", "search", "theme", "power"].concat(launcher.unplugged || launcher.saverOn ? ["saver"] : [])
    readonly property string topKeyed: zone === "top" && keysShown ? topItems[topAt] || "" : ""
    function enterTop(at) {
        zone = "top"
        const i = topItems.indexOf(at || (page === "theme" ? "theme" : page))
        topAt = i >= 0 ? i : 0
        if (Shell.debug) console.warn("ATOM atom top", topItems[topAt])
    }
    function leaveTop() {
        zone = "page"
        if ((page === "theme" || page === "manager") && pageApi && pageApi.enter) pageApi.enter()
        if (Shell.debug) console.warn("ATOM atom top left")
    }
    function topKey(k) {
        if (k === Qt.Key_Left || k === Qt.Key_Right) {
            topAt = Math.max(0, Math.min(topItems.length - 1, topAt + (k === Qt.Key_Right ? 1 : -1)))
            if (Shell.debug) console.warn("ATOM atom top", topItems[topAt])
            return true
        }
        if (k === Qt.Key_Down || k === Qt.Key_Escape) { leaveTop(); return true }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { topPick(topItems[topAt]); return true }
        return k === Qt.Key_Up
    }
    function topPick(id) {
        if (Shell.debug) console.warn("ATOM atom top pick", id)
        if (id === "jewel") { if (page !== "home") setPage("home"); else launcher.close(); return }
        if (id === "home" || id === "apps" || id === "games") { setPage(id); return }
        if (id === "search") { zone = "page"; openSearch(""); return }
        if (id === "theme") { toggleTheme(); if (page === "theme") zone = "page"; return }
        if (id === "power") { openPowerHere(); return }
        if (id === "saver" && !launcher.saverBusy) launcher.setSaver(!launcher.saverShown)
    }

    // ------------------------------------------------------------------ keys (a pad's arrive as keys too)
    signal pageKey(var event)           // the page in view handles what's left
    function wheeled(dy, at) { if (Shell.debug) console.warn("ATOM atom stage wheel", dy, Math.round(at.x), Math.round(at.y)); if (pageApi && pageApi.wheel) pageApi.wheel(dy, at) }
    function onKey(event) {
        if (powerOver) { event.accepted = true; return }
        if (!Gamepad.sending) Gamepad.inUse = false
        input = Gamepad.sending ? "pad" : "keys"
        const k = event.key
        if (k === Qt.Key_F10 && !searching) { zone === "top" ? leaveTop() : enterTop(); event.accepted = true; return }
        if (k === Qt.Key_F1) { toggleManager(""); event.accepted = true; return }
        if (zone === "top") {
            if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { stepPage(k === Qt.Key_Tab ? 1 : -1); enterTop(); event.accepted = true; return }
            if (topKey(k)) { event.accepted = true; return }
        }
        // the Theme page first (it walks its own parts; B/Esc it doesn't take leaves it)
        if ((page === "theme" || page === "manager") && !searching && pageApi && pageApi.key && pageApi.key(event)) { event.accepted = true; return }
        if (k === Qt.Key_Escape) { if (searching) closeSearch(); else if (page === "theme" || page === "manager") setPage(pageBefore); else launcher.close(); event.accepted = true; return }
        if (searching) {        // the query takes letters, spaces and Backspace; the arrows and Enter go to the results
            if (k === Qt.Key_Backspace) { launcher.query = launcher.query.slice(0, -1); event.accepted = true; return }
            if (event.text && event.text.length && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                launcher.query += event.text; event.accepted = true; return }
        }
        if (k === Qt.Key_Tab) { stepPage(1); event.accepted = true; return }
        if (k === Qt.Key_Backtab) { stepPage(-1); event.accepted = true; return }
        pageKey(event)
        if (event.accepted) return
        if (k === Qt.Key_Up && !searching) { enterTop(); event.accepted = true; return }    // (up past a page's top)
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            openSearch(event.text === "/" ? "" : event.text)
            event.accepted = true
        }
    }
    Connections {       // the pad's Y: the Theme page; its Menu (≡): the top bar
        target: Gamepad
        enabled: stage.wanted && stage.phase === "open"
        function onButton(name) {
            stage.input = "pad"
            if (name === "start" && !stage.powerOver) { stage.zone === "top" ? stage.leaveTop() : stage.enterTop(); return }
            if (name === "select" && !stage.powerOver) { stage.toggleManager(""); return }        // (View: Atom Manager)
            if (name !== "north" || stage.searching) return
            if (stage.page === "theme" && stage.pageApi && stage.pageApi.north && stage.pageApi.north()) return     // (the Theme page's Y: shuffle)
            stage.toggleTheme()
        }
    }
}
