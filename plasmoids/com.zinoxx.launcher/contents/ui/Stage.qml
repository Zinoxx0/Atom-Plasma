import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus
import Atom
import Atom.Native
import "Rice"
import "Rice/Color.js" as C
import "Motion.js" as M

// The launcher as a home screen for the computer ("Atom Home"), on the bare desktop of its screen. One
// focus at a time drives everything: the hero (the focused item large, with its actions) and the backdrop
// (a game fills the room with its own art; an app lights it in its colour). Pages of rows under a top bar
// (Home, Games, Apps); the focused tile stays at its anchor while its row glides under it.
// It opens out of the jewel: a window of the screen's frosted wallpaper grows out of the bar's jewel to the
// whole screen while the jewel lifts off and flies up to lead the top bar; closing folds it all back. The
// windows of its screen fly into their pins as it opens and come back as it closes (Atom Windows).
// Launching grows the tile into the screen (a game's cover becomes its banner) before it lets go.
// Typing searches (KRunner): the magnifier opens into a field, the results come down under it.
// Everything is the screen's palette (the theme engine): accents, text, surfaces, the glow, light moods.
// Mapped only while open: unmapping hands the keyboard back to the window that had it.
Window {
    id: stage
    required property var launcher
    required property var screenObj
    required property RicePalette rice
    required property Account account
    readonly property string screenName: screenObj ? screenObj.name : ""

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0
    y: screenObj ? screenObj.virtualY : 0
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height : 0
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: phase !== "closed"

    // a scope KWin knows ("utility": no special window, not outlined by the rounded-corners effect), on the
    // top layer (above the bar and every window; Glimpse's opened band goes to the overlay above it)
    LayerShell.Window.scope: "utility"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                             | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // ------------------------------------------------------------------ sizes: one design, fit to the screen
    readonly property real unit: Math.max(0.6, Math.min(2.2, Math.min(width / 1440, height / 900)))
    function u(n) { return Math.round(n * unit) }
    readonly property real side: u(76)
    readonly property real rowsTop: u(448)
    readonly property int openMs: Tokens.ms(900)
    readonly property int closeMs: Tokens.ms(420)
    readonly property int focusMs: Tokens.ms(380)
    readonly property int staggerMs: Tokens.ms(26)

    // ------------------------------------------------------------------ open / close
    readonly property bool wanted: Shell.kind === "launcher" && Shell.screen === screenName
    property string phase: "closed"             // closed, opening, open, closing
    property rect jewel: Qt.rect(0, 0, 0, 0)    // the bar's jewel (window coordinates)
    signal opened()
    function local(r) {
        if (!r || !screenObj) return Qt.rect(u(16), height - u(48), u(74), u(46))
        return Qt.rect(r.x - screenObj.virtualX, r.y - screenObj.virtualY, r.width, r.height)
    }
    onWantedChanged: wanted ? begin() : end()
    function begin() {
        jewel = local(Shell.anchor || Shell.island("launcher", screenName))
        pointerAt = ""
        if (phase === "closed") {
            phase = "opening"
            waitFrame = true            // the desk clears on the first frame (onFrameSwapped)
            opened()
        } else {
            if (launcher.clearDesk) Windows.clear(screenName)
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
        if (phase === "closed") keepWall.restart()
        if (Shell.debug) console.warn("ATOM stage", screenName, "phase", phase, Date.now() % 100000)
        if (Shell.debug && phase === "open") { logFocus(); logLayout() }
    }
    // the windows go once the stage is up: mapped, it holds the keyboard, so minimizing the focused window
    // doesn't make KWin focus one on another screen, and closing hands the keyboard back to it
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) {
        waitFrame = false
        if (launcher.clearDesk) Windows.clear(screenName)
        startOpen()
    }

    // ------------------------------------------------------------------ the choreography (Motion.js tracks)
    // what the moves set: the window (0 = the jewel, 1 = the screen), the jewel's flight, the content
    property real winP: 0
    property real washO: 0
    property real flyP: 0
    property bool flying: false
    property bool flyHome: false                // the flight goes back to the bar
    property real planeO: 0
    property real planeS: 1
    property real topO: 0
    property real heroO: 0
    property real coverO: 0                     // the bar under the wallpaper
    property real openT: 0
    property real closeT: 0
    property var closeFrom: ({})
    NumberAnimation { id: openClock; target: stage; property: "openT"; from: 0; to: stage.openTotal; duration: stage.openTotal; onFinished: stage.phase = "open" }
    NumberAnimation { id: closeClock; target: stage; property: "closeT"; from: 0; to: stage.closeMs; duration: stage.closeMs; onFinished: stage.closed() }
    readonly property real openTotal: openMs * 1.06 + 12 * staggerMs
    onOpenTChanged: if (phase === "opening") applyOpen(openT)
    onCloseTChanged: if (phase === "closing") applyClose(closeT)
    function startOpen() {
        flyHome = false
        applyOpen(0)
        openClock.restart()
    }
    function applyOpen(t) {
        const d = openMs
        coverO = 1
        winP = M.track(t, 0, d * 0.72, M.enter)
        washO = 1 - M.track(t, d * 0.02, d * 0.42, M.move)
        flyP = M.track(t, d * 0.02, d * 0.48, M.move)
        flying = t < d * 0.52
        planeO = M.track(t, d * 0.2, d * 0.8, M.enter)
        planeS = M.lerp(1.04, 1, planeO)
        topO = M.track(t, d * 0.3, d * 0.62, M.enter)
        heroO = M.track(t, d * 0.34, d * 0.66, M.enter)
        // the rows: their tiles come in from the right, one after another
        for (let k = 0; k < rowsRep.count; k++) {
            const row = rowsRep.itemAt(k)
            if (!row) continue
            const n = k - pageState().scroll
            row.titleO = n < 0 ? 0 : M.track(t, d * 0.36 + n * 3 * staggerMs, d * 0.6, M.enter)
            const tiles = row.shown()
            for (let i = 0; i < tiles.length; i++) {
                const v = n < 0 ? 0 : M.track(t, d * 0.36 + (n * 3 + i) * staggerMs, d * 0.66, M.enter)
                tiles[i].opacity = v
                tiles[i].enter = (1 - v) * u(80)
            }
        }
        if (t > 0 && !contentIn) contentIn = true
    }
    function startClose() {
        closeFrom = { plane: planeO, wash: washO, win: winP, fly: launchFly.visible ? 1 : 0 }
        flyHome = true
        applyClose(0)
        closeClock.restart()
    }
    function applyClose(t) {
        const d = closeMs, f = closeFrom
        planeO = (f.plane ?? 1) * (1 - M.track(t, 0, d * 0.55, M.exit))
        planeS = M.lerp(1, 1.035, M.track(t, 0, d * 0.55, M.exit))
        flying = true
        flyP = 1 - M.track(t, 0, d * 0.88, M.move)
        winP = (f.win ?? 1) * (1 - M.track(t, d * 0.12, d * 0.88, M.move))
        washO = M.lerp(f.wash ?? 0, 1, M.track(t, d * 0.45, d * 0.5, M.enter))
        launchFly.opacity = 1 - M.track(t, 0, d * 0.8, M.move)
    }
    function closed() {
        phase = "closed"
        flying = false
        coverO = 0
        contentIn = false
        launchFly.visible = false
        searchOpen = false
        searchP = 0
    }
    property bool contentIn: false
    onContentInChanged: if (contentIn) launcher.stageEntered()

    // ------------------------------------------------------------------ following the pointer
    // While it's open, KWin is asked every 150 ms which screen the pointer is on; when it moved to another
    // screen, the launcher goes there, query and all (only a move counts, not where it rested at first)
    property string pointerAt: ""
    Timer {
        interval: 150
        repeat: true
        running: stage.wanted && (stage.phase === "opening" || stage.phase === "open") && stage.launcher.view !== "walls"
        triggeredOnStart: true
        onTriggered: stage.askPointer()
    }
    function askPointer() {
        const reply = DBus.SessionBus.asyncCall({ service: "org.kde.KWin", path: "/KWin", iface: "org.kde.KWin",
                                                  member: "activeOutputName", arguments: [] })
        reply.finished.connect(() => {
            const v = reply.isError ? "" : reply.value
            reply.destroy()
            stage.pointerSeen(String((v && typeof v === "object" && "value" in v) ? v.value : (v ?? "")))
        })
    }
    function pointerSeen(name) {
        if (!name || !wanted || phase === "closing" || launcher.view === "walls") return
        const before = pointerAt
        pointerAt = name
        if (!before || name === before || name === screenName) return
        const there = Shell.island("launcher", name)
        if (Shell.debug) console.warn("ATOM stage pointer moved from", before, "to", name, there ? "(following)" : "(no launcher there)")
        if (!there) return
        Shell.open("launcher", name, there, { query: launcher.query })
    }

    // Glimpse's strip (the top band) stays usable: the pointer goes through to it there
    readonly property var strip: Shell.island("strip", screenName)
    InputMask {
        window: stage
        enabled: !!stage.strip && stage.screenObj !== null
        shapes: {
            const t = stage.strip ? Math.max(0, stage.strip.y + stage.strip.height - stage.screenObj.virtualY) : 0
            return [{ x: 0, y: t, width: stage.width, height: Math.max(0, stage.height - t), radius: 0 }]
        }
    }

    // ------------------------------------------------------------------ the bar steps aside under the wallpaper
    // (drawn as the desktop draws it), so the jewel can leave it; loaded while open and a while after
    readonly property rect barArea: {
        const r = launcher.panelRect
        if (!r || r.width <= 0 || !screenObj) return Qt.rect(0, 0, 0, 0)
        const m = u(20)
        const x0 = Math.max(0, r.x - screenObj.virtualX - m), y0 = Math.max(0, r.y - screenObj.virtualY - m)
        const x1 = Math.min(width, r.x - screenObj.virtualX + r.width + m), y1 = Math.min(height, r.y - screenObj.virtualY + r.height + m)
        return Qt.rect(x0, y0, Math.max(0, x1 - x0), Math.max(0, y1 - y0))
    }
    Timer { id: keepWall; interval: 120000 }
    Item {
        enabled: false
        x: stage.barArea.x
        y: stage.barArea.y
        width: stage.barArea.width
        height: stage.barArea.height
        clip: true
        visible: opacity > 0.001
        opacity: bareWall.status === Image.Ready ? stage.coverO : 0
        Image {
            id: bareWall
            x: -parent.x
            y: -parent.y
            width: stage.width
            height: stage.height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            readonly property real dpr: stage.screenObj ? stage.screenObj.devicePixelRatio : 1
            sourceSize: Qt.size(Math.round(stage.width * dpr), Math.round(stage.height * dpr))
            source: stage.rice.wallpaper && (stage.phase !== "closed" || keepWall.running) ? "file://" + stage.rice.wallpaper : ""
        }
    }

    // ------------------------------------------------------------------ the data and the focus
    HomeModel { id: hm; launcher: stage.launcher }
    ThemeModel { id: tm; launcher: stage.launcher; rice: stage.rice; screenName: stage.screenName }
    readonly property int themeTab: 3
    property int tab: 0                         // 0 Home, 1 Games, 2 Apps, 3 the Theme page (no tab: the palette)
    property int tabBefore: 0                   // where the Theme page goes back to
    readonly property var page: tab === themeTab ? ({ id: "theme", rows: tm.rows, rev: tm.rev })
                              : hm.pages.length ? hm.pages[Math.min(tab, hm.pages.length - 1)] : ({ rows: [] })
    readonly property bool theming: tab === themeTab
    // per page: the active row, the row at the top, each row's focus (by row id)
    property var states: [{ row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }]
    property int focusRev: 0
    function pageState() { return states[tab] }
    function idxOf(rowId) { focusRev; const i = pageState().idx[rowId]; return i === undefined ? 0 : i }
    function rowObj(ri) { return page.rows[ri] || null }
    readonly property var currentItem: {
        focusRev; hm.rev; tm.rev
        const r = rowObj(pageState().row)
        return r ? r.items[Math.min(idxOf(r.id), r.items.length - 1)] || null : null
    }
    function currentTile() {
        const row = rowsRep.itemAt(pageState().row)
        return row ? row.tileAt(idxOf(page.rows[pageState().row].id)) : null
    }
    // from "key", the row and the page move to keep the focus at its anchors; from the pointer they don't
    // (the content would slide out from under it)
    function focusAt(ri, i, from) {
        const st = pageState()
        const r = rowObj(ri)
        if (!r) return
        i = Math.max(0, Math.min(r.items.length - 1, i))
        if (st.row === ri && idxOf(r.id) === i) return
        st.row = ri
        st.idx[r.id] = i
        if (from === "key") st.scroll = ri
        focusRev++
        if (from === "key") {
            const row = rowsRep.itemAt(ri)
            if (row) row.settle(true)
        }
        if (Shell.debug) logFocus()
    }
    function step(dx, dy) {
        const st = pageState()
        if (dy) { const ri = st.row + dy; const r = rowObj(ri); if (r) focusAt(ri, idxOf(r.id), "key") }
        else { const r = rowObj(st.row); if (r) focusAt(st.row, idxOf(r.id) + dx, "key") }
    }
    function toggleTheme() { setTab(theming ? tabBefore : themeTab) }
    // the Theme page's rows open on what's in use (the theme, this screen's wallpaper, its colours...)
    function focusInUse() {
        const st = states[themeTab]
        let moved = false
        tm.rows.forEach((r, k) => {
            if (st.idx[r.id] !== undefined) return
            const i = r.items.findIndex(it => it.current)
            if (i < 0) return
            st.idx[r.id] = i
            moved = true
            const row = theming ? rowsRep.itemAt(k) : null
            if (row) row.settle(false)
        })
        if (moved) focusRev++
    }
    Connections { target: tm; function onRevChanged() { stage.focusInUse() } }   // also before the page swap ends
    // Meta+Shift+W: the Theme page, at a row (walls, colours or lights)
    function openTheme(rowId) {
        if (!theming) setTab(themeTab)
        if (!rowId) return
        const id = rowId === "lights" ? "lighting" : rowId
        const go = () => { const r = tm.rows.findIndex(x => x.id === id); if (r >= 0) focusAt(r, idxOf(id), "key") }
        if (tm.rows.length) Qt.callLater(go)
        else { const once = () => { tm.revChanged.disconnect(once); Qt.callLater(go) }; tm.revChanged.connect(once) }
    }
    Connections { target: stage.launcher; function onThemeAskChanged() { stage.openTheme(stage.launcher.themeRow) } }
    function logFocus() {
        const it = currentItem
        console.warn("ATOM home tab", tab, "row", pageState().row, "item", it ? (it.name || it.key || "") : "-")
        if (theming) Qt.callLater(() => {      // the hero's own actions, where they sit (once it has laid out)
            const h = heroRep.itemAt(heroSlot)
            const th = h ? h.th : null
            if (th) th.extra.forEach((x, i) => { const p = h.extraAt(i); if (p) console.warn("ATOM theme action", x.id, "at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + p.y)) })
        })
    }
    function logLayout() {
        const t = currentTile()
        if (t) { const p = t.mapToItem(null, t.width / 2, t.height / 2); console.warn("ATOM home focus at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + p.y)) }
        const tabsP = tabs.mapToItem(null, 0, 0)
        const at = b => { const q = b.mapToItem(null, b.width / 2, b.height / 2); return Math.round(screenObj.virtualX + q.x) + " " + Math.round(screenObj.virtualY + q.y) }
        console.warn("ATOM home tabs at", Math.round(screenObj.virtualX + tabsP.x), Math.round(screenObj.virtualY + tabsP.y), "search at", at(searchButton), "theme at", at(themeButton))
    }
    function setTab(i) {
        if (i !== themeTab) i = (i + 3) % 3
        if (i === tab) return
        if (i === themeTab) { tabBefore = tab; tm.reload(); Qt.callLater(focusInUse) }
        const dir = i > tab ? 1 : -1
        tabSwap.dir = dir
        tabSwap.next = i
        tabSwap.restart()
    }
    SequentialAnimation {
        id: tabSwap
        property int dir: 1
        property int next: 0
        ParallelAnimation {
            NumberAnimation { target: rowsBox; property: "opacity"; to: 0; duration: Tokens.ms(170); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
            NumberAnimation { target: rowsSlide; property: "x"; to: -tabSwap.dir * stage.u(36); duration: Tokens.ms(170); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
        }
        ScriptAction { script: { stage.tab = tabSwap.next; rowsSlide.x = tabSwap.dir * stage.u(56); Qt.callLater(stage.settleAll); if (Shell.debug) stage.logFocus() } }
        ParallelAnimation {
            NumberAnimation { target: rowsBox; property: "opacity"; to: 1; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
            NumberAnimation { target: rowsSlide; property: "x"; to: 0; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
        }
    }
    function settleAll() {
        for (let k = 0; k < rowsRep.count; k++) { const r = rowsRep.itemAt(k); if (r) r.settle(false) }
        pageY.enabled = false
        pageCol.y = -rowTop(pageState().scroll)
        pageY.enabled = true
    }
    function rowTop(ri) { let y = 0; for (let k = 0; k < ri; k++) { const r = rowsRep.itemAt(k); if (r) y += r.height } return y }

    // fresh every time it opens: Home, the first pin, no query
    onOpened: {
        tab = 0
        states = [{ row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }, { row: 0, scroll: 0, idx: {} }]
        focusRev++
        launcher.query = ""
        launcher.category = 0
        searchOpen = false
        searchP = 0
        launchFly.visible = false
        launchFly.opacity = 1
        Qt.callLater(settleAll)
        Qt.callLater(() => keys.forceActiveFocus())
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" launcher-data #data')
        if (Shell.args && Shell.args.query) Qt.callLater(() => stage.openSearch(Shell.args.query))
    }
    RiceShell { id: sh; onNewData: (source, data) => disconnectSource(source) }

    // ------------------------------------------------------------------ the window: the backdrop, out of the jewel
    Item {
        id: win
        readonly property real p: stage.winP
        readonly property real jr: Math.round(stage.jewel.height * 0.32)
        x: M.lerp(stage.jewel.x, 0, p)
        y: M.lerp(stage.jewel.y, 0, p)
        width: M.lerp(stage.jewel.width, stage.width, p)
        height: M.lerp(stage.jewel.height, stage.height, p)
        visible: stage.phase !== "closed" && p > 0.001
        clip: true
        readonly property real round: M.lerp(jr, 0, p) + Math.sin(p * Math.PI) * stage.u(30)
        layer.enabled: p > 0 && p < 1
        layer.effect: MultiEffect { maskEnabled: true; maskSource: winMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        Item {
            id: backdrop
            x: -win.x
            y: -win.y
            width: stage.width
            height: stage.height

            Image {     // the screen's wallpaper, frosted (the theme engine's glass)
                anchors.fill: parent
                anchors.margins: -stage.u(20)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                readonly property string pre: stage.rice.values._glassFull || ""
                source: pre ? "file://" + pre : stage.rice.wallpaper ? "file://" + stage.rice.wallpaper : ""
                sourceSize.width: pre ? 0 : 96
            }
            // an app lights the room in its colour (two layers, cross-faded)
            Repeater {
                model: 2
                Item {
                    id: glow
                    required property int index
                    anchors.fill: parent
                    opacity: stage.bgSlot === index ? stage.bgGlow[index] : 0
                    property var item: stage.bgItems[index]
                    Kirigami.ImageColors { id: glowColors; source: glow.item ? glow.item.icon : "" }
                    readonly property color c: C.appTint(glowColors, stage.rice.primary)
                    Shape {
                        x: parent.width * 0.27; y: -parent.height * 0.6
                        width: parent.width * 0.85; height: width
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: glowShape.w / 2; centerY: glowShape.w / 2; centerRadius: glowShape.w / 2
                                focalX: centerX; focalY: centerY
                                GradientStop { position: 0; color: C.alpha(glow.c, 0.55 * Math.max(0.4, stage.rice.glow)) }
                                GradientStop { position: 0.55; color: C.alpha(glow.c, 0.16 * Math.max(0.4, stage.rice.glow)) }
                                GradientStop { position: 1; color: C.alpha(glow.c, 0) }
                            }
                            PathRectangle { x: 0; y: 0; width: glowShape.w; height: glowShape.w; radius: glowShape.w / 2 }
                        }
                        QtObject { id: glowShape; readonly property real w: stage.width * 0.85 }
                    }
                    Kirigami.Icon {
                        x: parent.width * 0.94 - width; y: parent.height * 0.04
                        width: parent.height * 0.46; height: width
                        source: glow.item ? glow.item.icon : ""
                        opacity: 0.5
                        layer.enabled: true
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.4 }
                    }
                }
            }
            // a game fills it with its own art, drifting a little as it arrives
            Repeater {
                model: 2
                Image {
                    id: art
                    required property int index
                    x: 0; y: 0
                    width: parent.width
                    height: parent.height * 0.78
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                    source: stage.bgItems[index] && stage.bgItems[index].art ? stage.bgItems[index].art.hero : ""
                    opacity: stage.bgSlot === index ? stage.bgArt[index] : 0
                    transformOrigin: Item.Top
                    layer.enabled: true
                    layer.effect: MultiEffect {     // fades into the room at the bottom
                        maskEnabled: true
                        maskSource: artMask
                    }
                    NumberAnimation on scale { id: drift; running: false; from: 1.07; to: 1; duration: Tokens.ms(9000); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 0.6, 0.3, 1, 1, 1] }
                    onSourceChanged: if (source != "" && !stage.launcher.unplugged && !stage.launcher.saverOn) drift.restart(); else { drift.stop(); scale = 1 }
                }
            }
            Repeater {
                model: 2
                Item {
                    id: paper
                    required property int index
                    anchors.fill: parent
                    readonly property var it: stage.paperItems[index]
                    opacity: stage.bgSlot === index ? stage.bgPaper[index] : 0
                    visible: opacity > 0.001
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: paper.it && paper.it.thumb ? "file://" + paper.it.thumb : ""
                        smooth: true
                    }
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(stage.width, stage.height)
                        source: paper.it && paper.it.image ? "file://" + paper.it.image : ""
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(300) } }
                    }
                }
            }
            // shade for the text: the palette's own darkest surface (light in a light mood), heavier at the left
            // and under the rows, and the dim over everything
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(stage.rice.surfaceLowest, 0.78) }
                    GradientStop { position: 0.32; color: C.alpha(stage.rice.surfaceLowest, 0.45) }
                    GradientStop { position: 0.62; color: C.alpha(stage.rice.surfaceLowest, 0.08) }
                    GradientStop { position: 0.8; color: C.alpha(stage.rice.surfaceLowest, 0) }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: C.alpha(stage.rice.surfaceLowest, 0.35) }
                    GradientStop { position: 0.18; color: C.alpha(stage.rice.surfaceLowest, 0) }
                    GradientStop { position: 0.42; color: C.alpha(stage.rice.surfaceLowest, 0) }
                    GradientStop { position: 0.68; color: C.alpha(stage.rice.surfaceLowest, 0.75) }
                    GradientStop { position: 1; color: C.alpha(stage.rice.surfaceLowest, 0.9) }
                }
            }
            Rectangle { anchors.fill: parent; color: C.alpha(stage.rice.surfaceLowest, 0.26) }
        }
        // the jewel's colour, fading into the backdrop as the window opens
        Shape {
            x: -win.x
            y: -win.y
            width: stage.width
            height: stage.height
            opacity: stage.washO
            visible: opacity > 0.01
            preferredRendererType: Shape.CurveRenderer
            readonly property real cx: stage.jewel.x + stage.jewel.width / 2
            readonly property real cy: stage.jewel.y + stage.jewel.height / 2
            readonly property real r: Math.hypot(Math.max(cx, stage.width - cx), Math.max(cy, stage.height - cy)) * 0.9
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: washShape.cx; centerY: washShape.cy; centerRadius: washShape.r
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: C.alpha(stage.rice.primary, 0.85) }
                    GradientStop { position: 0.12; color: C.alpha(stage.rice.primary, 0.5) }
                    GradientStop { position: 0.35; color: C.alpha(stage.rice.tertiary, 0.18) }
                    GradientStop { position: 0.65; color: C.alpha(stage.rice.tertiary, 0) }
                }
                PathRectangle { x: 0; y: 0; width: stage.width; height: stage.height }
            }
            QtObject { id: washShape; readonly property real cx: stage.jewel.x + stage.jewel.width / 2; readonly property real cy: stage.jewel.y + stage.jewel.height / 2
                       readonly property real r: Math.hypot(Math.max(cx, stage.width - cx), Math.max(cy, stage.height - cy)) * 0.9 }
        }
    }
    Rectangle {     // the window's shape while it grows (the mask)
        id: winMask
        width: win.width
        height: win.height
        radius: win.round
        visible: false
        layer.enabled: true
    }
    Rectangle {     // the game art's fade into the room
        id: artMask
        width: stage.width
        height: stage.height * 0.78
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0; color: "black" }
            GradientStop { position: 0.45; color: "black" }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // ------------------------------------------------------------------ the backdrop follows the focus
    property var bgItems: [null, null]
    property var paperItems: [null, null]       // the Theme page: { thumb, image } of the wallpaper shown
    property var bgPaper: [0, 0]
    property var bgArt: [0, 0]
    property var bgGlow: [0, 0]
    property int bgSlot: 0
    property var bgShown: null
    Timer { id: bgDelay; interval: 110; onTriggered: stage.setBackdrop(stage.currentItem) }
    onCurrentItemChanged: { if (phase === "closed") return; heroShow(currentItem); bgDelay.restart() }
    function paperOf(it) {
        if (it.kind === "wall") return { thumb: it.thumb, image: it.path }
        if (it.kind === "look") return { thumb: it.thumb, image: it.image }
        const here = tm.screens.find(s => s.name === screenName)
        return here ? { thumb: here.thumb, image: here.image } : { thumb: "", image: rice.wallpaper }
    }
    function setBackdrop(it) {
        if (!it || it === bgShown) return
        bgShown = it
        const next = bgSlot ^ 1
        const items = bgItems.slice(); items[next] = it.kind ? null : it; bgItems = items
        const papers = paperItems.slice(); papers[next] = it.kind ? paperOf(it) : null; paperItems = papers
        bgFade.paper = !!it.kind
        const hasArt = !!(it.art && it.art.hero)
        bgFade.slotFrom = bgSlot
        bgFade.slotTo = next
        bgFade.art = hasArt
        bgSlot = next
        bgFade.restart()
    }
    NumberAnimation {
        id: bgFade
        property int slotFrom: 0
        property int slotTo: 1
        property bool art: false
        property bool paper: false
        target: bgFade; property: "v"; from: 0; to: 1
        duration: Math.max(Tokens.ms(420), Math.round(stage.focusMs * 1.8))
        easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove
        property real v: 0
        onVChanged: {
            const a = stage.bgArt.slice(), g = stage.bgGlow.slice(), w = stage.bgPaper.slice()
            a[slotTo] = art && !paper ? v * 0.9 : 0
            g[slotTo] = art || paper ? 0 : v * 0.6
            w[slotTo] = paper ? v : 0
            a[slotFrom] = a[slotFrom] * (1 - v)
            g[slotFrom] = g[slotFrom] * (1 - v)
            w[slotFrom] = w[slotFrom] * (1 - v)
            stage.bgArt = a
            stage.bgGlow = g
            stage.bgPaper = w
        }
    }

    // ------------------------------------------------------------------ the content: comes forward as one
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => stage.onKey(event)

        MouseArea {     // bare backdrop: a click closes it
            anchors.fill: parent
            enabled: stage.phase === "open" && !stage.searchOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: { if (stage.launcher.view === "walls") stage.launcher.view = "apps"; else stage.launcher.close() }
        }

        Item {
            id: plane
            anchors.fill: parent
            opacity: stage.planeO * (stage.searchOpen ? 1 - 0.9 * stage.searchP : 1) * (stage.launcher.view === "walls" ? 0 : 1)
            visible: opacity > 0.01
            scale: stage.planeS
            Behavior on opacity { enabled: stage.phase === "open"; NumberAnimation { duration: Tokens.base } }

            // ---- the top bar: the jewel (Home), the pages, then search, theme, power, the time and you
            Item {
                id: top
                x: stage.side
                y: stage.u(30)
                width: stage.width - 2 * stage.side
                height: stage.u(46)
                opacity: stage.topO
                transform: Translate { y: (1 - stage.topO) * -stage.u(18) }
                Row {
                    spacing: stage.u(18)
                    anchors.verticalCenter: parent.verticalCenter
                    JewelChip {
                        id: homeJewel
                        width: stage.u(64); height: stage.u(44)
                        rice: stage.rice
                        opacity: stage.flying ? 0 : 1
                        onClicked: stage.tab !== 0 ? stage.setTab(0) : stage.launcher.close()
                    }
                    Row {
                        id: crumb
                        visible: opacity > 0.01
                        opacity: stage.theming ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
                        width: stage.theming ? implicitWidth : 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: stage.u(8)
                        TopButton { rice: stage.rice; unit: stage.unit; icon: "arrow_back"; tip: "Back (Esc)"; onClicked: stage.setTab(stage.tabBefore) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Theme"; color: stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(21) }
                    }
                    Item {
                        id: tabs
                        width: stage.theming ? 0 : tabRow.width
                        visible: opacity > 0.01
                        opacity: stage.theming ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
                        height: stage.u(42)
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            id: tabPill
                            readonly property Item at: tabRep.itemAt(stage.tab)
                            x: at ? at.x : 0
                            width: at ? at.width : 0
                            height: parent.height
                            radius: height / 2
                            color: C.alpha(stage.rice.fg, 0.12)
                            border.width: 1
                            border.color: C.alpha(stage.rice.edge, 0.14)
                            Behavior on x { NumberAnimation { duration: Tokens.ms(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                            Behavior on width { NumberAnimation { duration: Tokens.ms(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                        }
                        Row {
                            id: tabRow
                            spacing: stage.u(4)
                            Repeater {
                                id: tabRep
                                model: ["Home", "Games", "Apps"]
                                delegate: Item {
                                    required property string modelData
                                    required property int index
                                    width: tabText.implicitWidth + stage.u(40)
                                    height: stage.u(42)
                                    Text {
                                        id: tabText
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: stage.tab === index || tabMouse.containsMouse ? stage.rice.fg : stage.rice.fgDim
                                        font.family: Tokens.font.ui
                                        font.weight: Font.DemiBold
                                        font.pixelSize: stage.u(16.5)
                                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                    }
                                    MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stage.setTab(index) }
                                }
                            }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: stage.u(10)
                    TopButton { id: searchButton; rice: stage.rice; unit: stage.unit; icon: "search"; tip: "Search (just type)"; onClicked: stage.openSearch("") }
                    TopButton { id: themeButton; rice: stage.rice; unit: stage.unit; icon: "palette"; tip: "Theme"; onClicked: stage.toggleTheme()
                                color: stage.theming ? C.alpha(stage.rice.fg, 0.16) : C.alpha(stage.rice.fg, hot ? 0.1 : 0) }
                    TopButton {
                        id: powerButton
                        rice: stage.rice; unit: stage.unit
                        icon: "power_settings_new"; tip: "Power"; hotColor: stage.rice.bad
                        onClicked: {
                            const p = powerButton.mapToGlobal(0, 0)
                            stage.launcher.openPower({ x: p.x, y: p.y, width: powerButton.width, height: powerButton.height })
                        }
                    }
                    Rectangle { width: 1; height: stage.u(22); anchors.verticalCenter: parent.verticalCenter; color: C.alpha(stage.rice.fg, 0.14) }
                    // the battery saver, while the laptop runs on battery
                    Rectangle {
                        visible: stage.launcher.unplugged || stage.launcher.saverOn
                        anchors.verticalCenter: parent.verticalCenter
                        height: stage.u(36)
                        width: saverRow.implicitWidth + stage.u(26)
                        radius: height / 2
                        color: stage.launcher.saverShown ? C.alpha(stage.rice.green, 0.22) : C.alpha(stage.rice.fg, sm.containsMouse ? 0.14 : 0.08)
                        opacity: stage.launcher.saverBusy ? 0.6 : 1
                        Row {
                            id: saverRow
                            anchors.centerIn: parent
                            spacing: stage.u(6)
                            readonly property real charge: Number(stage.launcher.batt["Percent"]) || 0
                            Text { anchors.verticalCenter: parent.verticalCenter; text: stage.launcher.saverShown ? "eco" : "battery_" + Math.min(6, Math.round(saverRow.charge / 100 * 6)) + "_bar"
                                   color: stage.launcher.saverShown ? stage.rice.green : stage.rice.fg; font.family: Tokens.font.icons; font.pixelSize: stage.u(18) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(saverRow.charge) + "%"; color: stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(13.5) }
                        }
                        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!stage.launcher.saverBusy) stage.launcher.setSaver(!stage.launcher.saverShown) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatTime(stage.now, "HH:mm")
                        color: stage.rice.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: stage.u(18)
                        font.features: { "tnum": 1 }
                        leftPadding: stage.u(4)
                        rightPadding: stage.u(4)
                    }
                    Rectangle {     // you
                        width: stage.u(38); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: stage.rice.primary }
                            GradientStop { position: 1; color: stage.rice.tertiary }
                        }
                        border.width: 2
                        border.color: C.alpha("#ffffff", 0.18)
                        Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: stage.account.initial; color: stage.rice.onPrimary
                               font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: stage.u(16) }
                        Kirigami.ShadowedImage { id: face; anchors.fill: parent; radius: width / 2; source: stage.account.face; visible: status === Image.Ready; fillMode: Image.PreserveAspectCrop; color: "transparent" }
                    }
                }
            }

            // ---- the hero: the focused item, large (two, cross-faded)
            Item {
                id: heroBox
                x: stage.side
                y: stage.u(104)
                width: Math.min(stage.u(760), stage.width * 0.6)
                height: stage.u(312)
                opacity: stage.heroO
                transform: Translate { y: (1 - stage.heroO) * stage.u(24) }
                Repeater {
                    id: heroRep
                    model: 2
                    HomeHero {
                        required property int index
                        anchors.fill: parent
                        rice: stage.rice
                        unit: stage.unit
                        item: stage.heroItems[index]
                        readonly property var th: stage.themeHero(item)
                        pinned: !th && !!(item && stage.launcher.isFavorite(item.favId))
                        eyebrow: th ? th.eyebrow : ""
                        primaryText: th ? th.primary : ""
                        primaryIcon: th ? th.icon : ""
                        extraActions: th ? th.extra : null
                        onExtra: (i, from) => stage.themeExtra(th.extra[i].id)
                        opacity: stage.heroO2[index]
                        transform: Translate { x: stage.heroX[index] }
                        onPrimary: { const t = stage.currentTile(); stage.activateItem(stage.currentItem, t) }
                        onPin: if (stage.currentItem) stage.launcher.toggleFavorite(stage.currentItem.favId)
                        onMore: from => { const t = stage.currentTile(); if (t && stage.currentItem) stage.launcher.menu.openFor(t, stage.currentItem.model, stage.currentItem.row) }
                    }
                }
            }

            // ---- the Theme page: the screens as they sit on the desk (the rice's DeskMap): the one being edited
            // ringed, the one that themes the system starred; what the focused item would put on each
            Rectangle {
                id: screensCard
                anchors.right: parent.right
                anchors.rightMargin: stage.side
                y: stage.u(118) + (stage.theming ? 0 : -stage.u(10))
                width: stage.u(470)
                height: stage.u(206)
                radius: stage.u(26)
                visible: opacity > 0.01
                opacity: stage.theming ? stage.heroO : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.ms(380) } }
                Behavior on y { NumberAnimation { duration: Tokens.ms(480); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                color: C.alpha(stage.rice.surfaceLowest, 0.5)
                border.width: 1
                border.color: C.alpha(stage.rice.edge, 0.1)
                DeskMap {
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: capRow.top; margins: stage.u(18) }
                    pal: stage.rice
                    screens: tm.screens
                    focusName: tm.target === "all" ? stage.screenName : tm.target
                    linked: tm.target === "all"
                    preview: stage.previewMap
                    onPicked: name => { tm.target = name }
                }
                Row {
                    id: capRow
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: stage.u(16) }
                    height: stage.u(28)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - allChip.width
                        text: tm.status || ("Editing " + tm.targetLabel)
                        elide: Text.ElideRight
                        color: tm.status ? stage.rice.bad : stage.rice.muted
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: stage.u(12.5)
                    }
                    Rectangle {
                        id: allChip
                        anchors.verticalCenter: parent.verticalCenter
                        width: allText.implicitWidth + stage.u(24)
                        height: stage.u(28)
                        radius: height / 2
                        color: tm.target === "all" ? stage.rice.primary : C.alpha(stage.rice.fg, 0.08)
                        Text { id: allText; anchors.centerIn: parent; text: "All screens"; color: tm.target === "all" ? stage.rice.onPrimary : stage.rice.fgDim
                               font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(12.5) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: stage.themeExtra("all") }
                    }
                }
            }

            // ---- the rows: a row at a time scrolls to the top; the ones above it have gone
            Item {
                id: rowsBox
                x: 0
                y: stage.rowsTop
                width: stage.width
                height: stage.height - stage.rowsTop - stage.u(58)
                clip: true
                Item {
                    id: rowsSlide
                    width: parent.width
                    height: parent.height
                    Column {
                        id: pageCol
                        width: parent.width
                        y: { stage.focusRev; return -stage.rowTop(stage.pageState().scroll) }
                        Behavior on y { id: pageY; NumberAnimation { duration: Math.round(stage.focusMs * 1.45); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                        Repeater {
                            id: rowsRep
                            // by count, so a page rebuilt with the same rows (a theme applied, the data refreshed)
                            // keeps its rows and tiles and only rebinds them: nothing flashes
                            model: stage.page.rows.length
                            delegate: HomeRow {
                                id: hrow
                                required property int index
                                readonly property var entry: stage.page.rows[index] || ({ id: "", title: "", shape: "square", items: [], divider: -1 })
                                width: pageCol.width
                                row: entry
                                rice: stage.rice
                                unit: stage.unit
                                side: stage.side
                                focusMs: stage.focusMs
                                current: stage.idxOf(entry.id)
                                active: (stage.focusRev, index === stage.pageState().row)
                                opacity: (stage.focusRev, index < stage.pageState().scroll) ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
                                onPointed: i => stage.focusAt(index, i, "mouse")
                                onActivated: (i, tile) => { stage.focusAt(index, i, "mouse"); stage.activateItem(entry.items[i], tile) }
                                onMenu: (i, tile) => { const it = entry.items[i]; if (it.model) stage.launcher.menu.openFor(tile, it.model, it.row) }
                                Component.onCompleted: Qt.callLater(() => settle(false))
                            }
                        }
                    }
                }
                // the wheel walks the rows (and along a row with shift or a sideways wheel)
                WheelHandler {
                    property real acc: 0
                    onWheel: ev => {
                        const sideways = (ev.modifiers & Qt.ShiftModifier) || Math.abs(ev.angleDelta.x) > Math.abs(ev.angleDelta.y)
                        acc += sideways ? (ev.angleDelta.x || ev.angleDelta.y) : ev.angleDelta.y
                        if (Math.abs(acc) < 120) return
                        const d = acc < 0 ? 1 : -1
                        acc = 0
                        if (sideways) stage.step(d, 0)
                        else stage.step(0, d)
                    }
                }
            }

            // ---- the keys, quietly
            Row {
                x: stage.side
                anchors.bottom: parent.bottom
                anchors.bottomMargin: stage.u(24)
                spacing: stage.u(22)
                opacity: stage.topO
                Repeater {
                    model: stage.theming ? [["←→↑↓", "Move"], ["Enter", "Apply"], ["Esc", "Back"]]
                                         : [["←→↑↓", "Move"], ["Enter", "Open"], ["Tab", "Switch"], ["Type", "Search"], ["Esc", "Close"]]
                    Row {
                        required property var modelData
                        spacing: stage.u(7)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(stage.u(22), kt.implicitWidth + stage.u(12))
                            height: stage.u(22)
                            radius: stage.u(6)
                            color: "transparent"
                            border.width: 1
                            border.color: C.alpha(stage.rice.fg, 0.2)
                            Text { id: kt; anchors.centerIn: parent; text: modelData[0]; color: stage.rice.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(11.5) }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: stage.rice.muted; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: stage.u(12.5) }
                    }
                }
            }
        }

        // ---- search: the magnifier opens into a field, the results come down under it
        Item {
            id: searchLayer
            anchors.fill: parent
            visible: stage.searchP > 0.001
            readonly property rect from: {
                stage.planeO
                const p = searchButton.mapToItem(searchLayer, 0, 0)
                return Qt.rect(p.x, p.y, searchButton.width, searchButton.height)
            }
            readonly property rect to: {
                const w = Math.min(stage.u(760), stage.width * 0.62), h = stage.u(60)
                return Qt.rect((stage.width - w) / 2, stage.u(30) + stage.u(23) - h / 2, w, h)
            }
            MouseArea { anchors.fill: parent; enabled: stage.searchOpen; onClicked: stage.closeSearch() }
            Rectangle {
                id: field
                x: M.lerp(searchLayer.from.x, searchLayer.to.x, stage.searchP)
                y: M.lerp(searchLayer.from.y, searchLayer.to.y, stage.searchP)
                width: M.lerp(searchLayer.from.width, searchLayer.to.width, stage.searchP)
                height: M.lerp(searchLayer.from.height, searchLayer.to.height, stage.searchP)
                radius: height / 2
                opacity: Math.min(1, stage.searchP * 3)
                color: C.alpha(stage.rice.surfaceLowest, 0.74)
                border.width: 1
                border.color: C.alpha(stage.rice.edge, 0.14)
                MouseArea { anchors.fill: parent; onClicked: query.forceActiveFocus() }
                Text {
                    id: lens
                    x: stage.u(22)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: stage.rice.primary
                    font.family: Tokens.font.icons
                    font.pixelSize: stage.u(26)
                }
                TextInput {
                    id: query
                    anchors { left: lens.right; leftMargin: stage.u(14); right: busy.left; rightMargin: stage.u(12); top: parent.top; bottom: parent.bottom }
                    verticalAlignment: TextInput.AlignVCenter
                    opacity: M.clamp((stage.searchP - 0.45) / 0.55)
                    color: stage.rice.fg
                    selectionColor: stage.rice.primary
                    selectedTextColor: stage.rice.onPrimary
                    font.family: Tokens.font.ui
                    font.pixelSize: stage.u(21)
                    clip: true
                    onTextChanged: stage.launcher.query = text
                    Keys.onPressed: event => stage.onSearchKey(event)
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !query.text && !query.preeditText
                        text: "Search apps, games, settings, files… or do maths"
                        color: stage.rice.muted
                        font: query.font
                        elide: Text.ElideRight
                    }
                }
                Busy {
                    id: busy
                    anchors { right: parent.right; rightMargin: stage.u(20); verticalCenter: parent.verticalCenter }
                    visible: stage.launcher.searching
                    running: visible
                    implicitWidth: stage.u(18); implicitHeight: implicitWidth
                    color: stage.rice.primary
                }
            }
            HomeSearch {
                id: results
                x: (stage.width - width) / 2
                y: stage.u(132) + (1 - opacity) * -stage.u(14)
                width: Math.min(stage.u(1120), stage.width * 0.9)
                height: stage.height - y - stage.u(50)
                launcher: stage.launcher
                rice: stage.rice
                unit: stage.unit
                opacity: stage.launcher.query !== "" ? M.clamp((stage.searchP - 0.3) / 0.7) : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Tokens.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            }
        }

        // ---- the Theme page (WallpaperPane) in a frosted card, for now
        Frost {
            id: wallsCard
            readonly property real w: Math.min(stage.u(1220), stage.width - 2 * stage.u(40))
            backdrop: frostTex
            visible: opacity > 0.01
            width: w
            height: stage.height - 2 * stage.u(56)
            x: Math.round((stage.width - w) / 2)
            y: stage.u(56) + (stage.launcher.view === "walls" ? 0 : stage.u(24))
            opacity: stage.launcher.view === "walls" && stage.contentIn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
            Behavior on y { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } }
            radius: Tokens.radius.xl
            tintAlpha: 0.66
            rimA: stage.rice.primary
            rimB: stage.rice.tertiary
            MouseArea { anchors.fill: parent }
            Loader {
                anchors.fill: parent
                anchors.margins: Tokens.space.xl
                active: stage.launcher.view === "walls" || item !== null
                enabled: stage.launcher.view === "walls"
                onEnabledChanged: if (enabled && item) Qt.callLater(() => item.forceActiveFocus())
                onLoaded: { stage.launcher.wallsPane = item; if (stage.launcher.openTab) item.tab = stage.launcher.openTab; stage.launcher.openTab = ""; item.forceActiveFocus() }
                sourceComponent: WallpaperPane {
                    cfg: stage.launcher.cfg
                    mode: "desktop"
                    screenName: stage.screenName
                    onBack: { stage.launcher.view = "apps"; Qt.callLater(() => keys.forceActiveFocus()) }
                }
            }
        }
    }
    // the frosted card's texture (the screen's glass, as the old stage had it)
    Item {
        id: frostArt
        width: stage.width
        height: stage.height
        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            readonly property string pre: stage.rice.values._glassFull || ""
            source: pre ? "file://" + pre : stage.rice.wallpaper ? "file://" + stage.rice.wallpaper : ""
            sourceSize.width: pre ? 0 : 96
        }
    }
    ShaderEffectSource { id: frostTex; width: stage.width; height: stage.height; visible: false; sourceItem: frostArt; hideSource: true; live: stage.launcher.view === "walls" }

    // ------------------------------------------------------------------ the hero follows the focus (cross-fade)
    property var heroItems: [null, null]
    property var heroO2: [0, 0]
    property var heroX: [0, 0]
    property int heroSlot: 0
    function heroShow(it) {
        if (!it || heroItems[heroSlot] === it) return
        const next = heroSlot ^ 1
        const items = heroItems.slice(); items[next] = it; heroItems = items
        heroFade.slotFrom = heroSlot
        heroFade.slotTo = next
        heroFade.o0 = heroO2[heroSlot]
        heroSlot = next
        heroFade.restart()
        if (phase === "opening") heroFade.complete()
    }
    NumberAnimation {
        id: heroFade
        property int slotFrom: 0
        property int slotTo: 1
        property real o0: 1
        property real v: 0
        target: heroFade; property: "v"; from: 0; to: 1
        duration: Math.round(stage.focusMs * 1.3)
        onVChanged: {
            const d = 1.3, o = stage.heroO2.slice(), x = stage.heroX.slice()
            const out = M.track(v * d, 0, 0.45, M.exit), inn = M.track(v * d, 0.18, 1.1, M.enter)
            o[slotFrom] = o0 * (1 - out); x[slotFrom] = -out * stage.u(10)
            o[slotTo] = inn; x[slotTo] = (1 - inn) * stage.u(20)
            stage.heroO2 = o
            stage.heroX = x
        }
    }

    // ------------------------------------------------------------------ the jewel's flight, between the bar and the top bar
    JewelChip {
        id: flyJewel
        visible: stage.flying && stage.phase !== "closed"
        rice: stage.rice
        readonly property real v: stage.flyP
        readonly property real bow: Math.sin(v * Math.PI) * stage.u(70)
        readonly property real lift: 1 + Math.sin(v * Math.PI) * 0.1
        width: M.lerp(stage.jewel.width, stage.u(64), v) * lift
        height: M.lerp(stage.jewel.height, stage.u(44), v) * lift
        x: M.lerp(stage.jewel.x + stage.jewel.width / 2, stage.side + stage.u(32), v) + bow - width / 2
        y: M.lerp(stage.jewel.y + stage.jewel.height / 2, stage.u(30) + stage.u(23), v) - height / 2
        radius: M.lerp(win.jr, stage.u(15), v)
        glowing: true
    }

    // ------------------------------------------------------------------ launching: the tile grows into the screen
    Item {
        id: launchFly
        visible: false
        property rect from: Qt.rect(0, 0, 0, 0)
        property var item: null
        property real p: 0
        readonly property bool art: !!(item && item.art && item.art.hero)
        x: M.lerp(from.x, 0, p)
        y: M.lerp(from.y, 0, p)
        width: M.lerp(from.width, stage.width, p)
        height: M.lerp(from.height, stage.height, p)
        layer.enabled: visible
        layer.effect: MultiEffect { maskEnabled: true; maskSource: flyMask }
        Rectangle {
            anchors.fill: parent
            color: launchFly.art ? "#000000" : C.mix(flyColors.c, "#0b0f16", 0.5)
            QtObject { id: flyColors; readonly property color c: C.appTint(flyIc, stage.rice.primary) }
            Kirigami.ImageColors { id: flyIc; source: launchFly.item ? launchFly.item.icon : "" }
        }
        Image {
            anchors.fill: parent
            visible: launchFly.art
            source: launchFly.art ? launchFly.item.art.hero : ""
            fillMode: Image.PreserveAspectCrop
        }
        Image {
            anchors.fill: parent
            visible: !!(launchFly.item && launchFly.item.art && launchFly.item.art.portrait)
            source: visible ? launchFly.item.art.portrait : ""
            fillMode: Image.PreserveAspectCrop
            opacity: 1 - Math.min(1, launchFly.p * 1.8)
        }
        Kirigami.Icon {
            visible: !launchFly.art
            anchors.centerIn: parent
            width: M.lerp(Math.min(launchFly.from.width, launchFly.from.height) * 0.56, Math.min(stage.width, stage.height) * 0.22, launchFly.p)
            height: width
            source: launchFly.item ? launchFly.item.icon : ""
        }
        NumberAnimation on p { id: launchGrow; running: false; from: 0; to: 1; duration: Tokens.ms(620); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove; onFinished: stage.launcher.close() }
    }
    Rectangle { id: flyMask; width: launchFly.width; height: launchFly.height; radius: M.lerp(stage.u(22), 0, launchFly.p); visible: false; layer.enabled: true }
    // the Theme page's items: what the hero says and offers for each
    function themeHero(it) {
        if (!it || !it.kind) return null
        const busy = tm.busy === it.key
        const all = { id: "all", icon: "select_all", tip: tm.target === "all" ? "Edit only this screen" : "Edit every screen", on: tm.target === "all" }
        const fine = t => ({ id: "fine:" + t, icon: "tune", tip: "Fine-tune" })
        const n = tm.page ? tm.page.walls.length : 0
        const t = {
            wall: { eyebrow: "Wallpaper · " + it.n + " of " + n, primary: "Set on " + tm.targetLabel, icon: "wallpaper", extra: [all, { id: "fine:walls", icon: "travel_explore", tip: "Find more (wallhaven), the whole collection" }] },
            look: { eyebrow: "Theme", primary: "Load theme", icon: "style", extra: [fine("walls")] },
            save: { eyebrow: "Theme", primary: "Name it", icon: "bookmark_add", extra: [] },
            "colours-auto": { eyebrow: "Colours", primary: "Use automatic", icon: "auto_awesome", extra: [all, fine("colours")] },
            mood: { eyebrow: "Mood", primary: "Use " + String(it.name).toLowerCase(), icon: "palette", extra: [all, fine("colours")] },
            accent: { eyebrow: "Accent · " + it.role, primary: "Pick a colour", icon: "colorize", extra: [fine("colours")] },
            size: { eyebrow: "Size", primary: "Use this size", icon: "format_size", extra: [fine("size")] },
            light: { eyebrow: "Lighting", primary: "Use on both keyboards", icon: "keyboard", extra: [fine("lights")] },
        }[it.kind]
        if (busy) t.primary = "Applying…"
        return t
    }
    function themeExtra(id) {
        if (id === "all") { tm.target = tm.target === "all" ? screenName : "all"; return }
        if (id.startsWith("fine:")) launcher.openWallpapers("desktop", id.slice(5))
    }
    // Enter, a click or the bright pill: a Theme item applies (or opens the panel it needs), anything else launches
    function activateItem(it, tile) {
        if (!it) return
        if (!it.kind) { launchItem(it, tile); return }
        if (it.kind === "save") launcher.openWallpapers("desktop", "walls")
        else if (it.kind === "accent") launcher.openWallpapers("desktop", "colours")
        else tm.apply(it)
        if (Shell.debug) console.warn("ATOM home apply", it.key)
    }
    // what the focused Theme item would put on each screen, for the desk map: {connector: {thumb, how, from}}
    readonly property var previewMap: {
        const it = currentItem
        if (!theming || !it) return null
        if (it.kind === "wall") {
            const out = {}
            for (const s of tm.targets) out[s.name] = { thumb: it.thumb, how: "same" }
            return out
        }
        if (it.kind === "look" && it.preset && it.preset.plan) {
            const out = {}
            for (const conn in it.preset.plan) out[conn] = Object.assign({ thumb: (it.preset.thumbs || {})[conn] || "" }, it.preset.plan[conn])
            return out
        }
        return null
    }
    function launchItem(it, tile) {
        if (!it || (phase !== "open" && phase !== "opening")) return
        const r = tile ? tile.mapToItem(null, 0, 0, tile.width, tile.height) : Qt.rect(width / 2 - u(60), height / 2 - u(60), u(120), u(120))
        launchFly.item = it
        launchFly.from = r
        launchFly.p = 0
        launchFly.opacity = 1
        launchFly.visible = true
        it.model.trigger(it.row, "", null)
        launchGrow.restart()
        if (Shell.debug) console.warn("ATOM home launch", it.name)
    }

    // ------------------------------------------------------------------ search
    property bool searchOpen: false
    property real searchP: 0
    Behavior on searchP { NumberAnimation { duration: Math.max(Tokens.ms(360), Math.round(stage.focusMs * 1.3)); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    function openSearch(text) {
        if (Shell.debug) console.warn("ATOM home search", JSON.stringify(text))
        if (!searchOpen) { searchOpen = true; searchP = 1 }
        query.text = text || ""
        query.cursorPosition = query.text.length
        query.forceActiveFocus()
    }
    function closeSearch() {
        if (!searchOpen) return
        searchOpen = false
        searchP = 0
        query.text = ""
        query.focus = false
        keys.forceActiveFocus()
    }
    function onSearchKey(event) {
        const L = launcher
        if (event.key === Qt.Key_Escape) { if (query.text) query.text = ""; else closeSearch(); event.accepted = true }
        else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) { L.moveSelection(1); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { L.moveSelection(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (L.query) L.activateSelection(); event.accepted = true }
    }

    // ------------------------------------------------------------------ keys
    function onKey(event) {
        if (launcher.view === "walls") return
        const k = event.key
        if (k === Qt.Key_Escape) { if (searchOpen) closeSearch(); else if (theming) setTab(tabBefore); else launcher.close(); event.accepted = true; return }
        if (k === Qt.Key_Tab) { setTab(theming ? tabBefore : tab + 1); event.accepted = true; return }
        if (k === Qt.Key_Backtab) { setTab(theming ? tabBefore : tab - 1); event.accepted = true; return }
        if (k === Qt.Key_Left) { step(-1, 0); event.accepted = true; return }
        if (k === Qt.Key_Right) { step(1, 0); event.accepted = true; return }
        if (k === Qt.Key_Up) { step(0, -1); event.accepted = true; return }
        if (k === Qt.Key_Down) { step(0, 1); event.accepted = true; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { activateItem(currentItem, currentTile()); event.accepted = true; return }
        if (k === Qt.Key_Menu) { const t = currentTile(); if (t && currentItem && currentItem.model) launcher.menu.openFor(t, currentItem.model, currentItem.row); event.accepted = true; return }
        if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_F) { openSearch(""); event.accepted = true; return }
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            openSearch(event.text === "/" ? "" : event.text)
            event.accepted = true
        }
    }

    Connections { target: stage.launcher; function onViewChanged() { if (Shell.debug) console.warn("ATOM stage view", stage.launcher.view) } }
    property date now: new Date()
    Timer { running: stage.phase !== "closed"; repeat: true; interval: 10000; triggeredOnStart: true; onTriggered: stage.now = new Date() }
}
