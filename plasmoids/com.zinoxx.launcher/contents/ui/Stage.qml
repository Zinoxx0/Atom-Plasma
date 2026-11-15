import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.extras as PlasmaExtras
import Atom
import Atom.Native
import Rice

// The launcher as a home screen for the computer ("Atom Home"), on the bare desktop of its screen. One
// focus at a time drives everything: the hero (the focused item large, with its actions) and the backdrop
// (a game fills the room with its own art; an app lights it in its colour). Pages of rows under a top bar
// (Home, Games, Apps; the palette opens a fourth, the Theme page); the focused tile stays at its anchor while
// its row glides under it (rows are lazy ListViews: only what shows exists; drag or wheel them sideways).
// It fades in (the lab's "fade": the frosted backdrop, then the content settling from a little closer, the
// top bar, the hero, the tiles one after another) and fades out. The windows of its screen fly into their
// pins as it opens and come back as it closes (Atom Windows). Each page is built the first time it shows
// and then kept, so switching pages costs only the cross-fade.
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
    y: screenObj ? screenObj.virtualY + topGap : 0
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height - topGap : 0
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
    LayerShell.Window.margins: ({ left: 0, top: topGap, right: 0, bottom: 0 })
    LayerShell.Window.exclusionZone: -1
    // (not while the power page opened from it is over it: claimed again as it folds away, KWin hands the
    // keyboard back; held all along, the power page's ending left the keys with nobody)
    LayerShell.Window.keyboardInteractivity: powerOver ? LayerShell.Window.KeyboardInteractivityNone : LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // ------------------------------------------------------------------ sizes: one design, fit to the screen
    // one design (1440 x 900) sized by the screen's UI size (the rice's bar_scale: what the user picked as
    // comfortable from where they sit), only shrunk further where it wouldn't fit: a big screen shows more,
    // not the same bigger
    // The launcher's own size (the Theme page's "Launcher size": settings launcher.size), on the screen's
    // standard size (how big a pixel looks from where you sit: the theme engine's _standard), never the
    // desktop's size (that one is for the bars and the desk); shrunk only where it wouldn't fit
    readonly property real standard: Number(rice.values._standard) || 1
    readonly property real unit: Math.max(0.6, Math.min(0.8 * standard * launcher.homeSize, width / 1440, height / 900))
    function u(n) { return Math.round(n * unit) }
    readonly property real side: u(76)
    // the rows start under the hero; on a tall screen they sit lower (the hero and the art above get the
    // room), so the page isn't all in its top half
    readonly property real rowsTop: heroTop + heroH + u(26)
    readonly property real barH: u(66)          // the top bar's one control height (a fullscreen page: big)
    // the hero right under the top bar, as tall as its content needs; the rows take everything below it
    readonly property real heroTop: u(26) + barH + u(34)
    readonly property real heroH: theming ? u(290) : u(236)
    readonly property int openMs: Tokens.ms(900)
    readonly property int closeMs: Tokens.ms(420)
    readonly property int focusMs: Tokens.ms(380)
    readonly property int staggerMs: Tokens.ms(26)

    // ------------------------------------------------------------------ open / close
    // (and beneath the power page opened from it: it stays, its content steps back: powerOver)
    readonly property bool wanted: Shell.screen === screenName
                                   && (Shell.kind === "launcher" || (!!Shell.under && Shell.under.kind === "launcher" && Shell.under.screen === screenName))
    readonly property bool powerOver: wanted && Shell.kind === "power"
    // the content steps back while the power page is over it, and comes forward as it folds away (a beat
    // after: the power page's actions leave first), on the calm curves: one room, the content changing
    property real coverP: 0
    onPowerOverChanged: {
        coverAnim.stop()
        // (one thing at a time: out quickly before the power page's content arrives; back only once its
        // content has gone. Measured on a recording: overlapping, the two read as two apps cross-fading)
        coverWait.duration = powerOver ? 0 : Tokens.ms(230)
        coverMove.duration = powerOver ? Tokens.ms(220) : Tokens.ms(460)
        coverMove.easing.bezierCurve = powerOver ? Tokens.calmOut : Tokens.calmIn
        coverMove.to = powerOver ? 1 : 0
        coverAnim.start()
        if (!powerOver) Qt.callLater(() => keys.forceActiveFocus())
        if (Shell.debug) console.warn("ATOM stage", screenName, powerOver ? "under the power page" : "back from the power page")
    }
    SequentialAnimation {
        id: coverAnim
        PauseAnimation { id: coverWait; duration: 0 }
        NumberAnimation { id: coverMove; target: stage; property: "coverP"; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmOut }
    }
    property string phase: "closed"             // closed, opening, open, closing
    signal opened()
    onWantedChanged: wanted ? begin() : end()
    // the finder: only the search field and its results, over whatever is on the screen (no backdrop, no
    // home, the windows stay): what KRunner's shortcut and typing on the desktop open (Atom.Native's krunner
    // bridge: Shell.open("launcher", screen, null, { searchOnly: true, query }))
    property bool finder: false
    // where clear blur ripples out from: the jewel it was opened from (Shell.anchor), else the middle
    property point rippleOrigin: Qt.point(width / 2, height / 2)
    function begin() {
        const a = Shell.anchor
        rippleOrigin = a && screenObj && Shell.screen === screenName
            ? Qt.point(a.x - screenObj.virtualX + a.width / 2, a.y - screenObj.virtualY - topGap + a.height / 2)
            : Qt.point(width / 2, height / 2)
        pointerAt = ""
        pointerMode = false
        pointerSeenAt = Qt.point(-1, -1)
        pointerKnown = false
        aim = null
        aimTrail = []
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
        if (Shell.debug) console.warn("ATOM stage", screenName, "phase", phase, Date.now() % 100000)
        if (Shell.debug && phase === "open") { logFocus(); logLayout() }
        if (phase === "opening") { shownAt = Date.now(); coldOpen = idle || gameUp }
        if (phase === "closed") restTimer.restart()
        else { restTimer.stop(); idle = false }
    }
    // Video memory: an open launcher builds a lot of it (its full-screen scene, the pages' effect layers:
    // ~160 MiB on the 1440p screen, ~330 MiB on the 4K one, measured 2026-11-15), and a closed one kept all of
    // it for good, on every screen it had opened on. It now gives it back while a fullscreen window is up (a
    // game wants it) or after 10 minutes closed. The cost: that next open's first frame uploads it all again
    // (~70 ms, as the first open after login always took) instead of ~7 ms.
    property bool idle: false
    Timer { id: restTimer; interval: 10 * 60 * 1000; onTriggered: stage.idle = true }
    WindowRest {
        window: stage
        resting: stage.phase === "closed" && (stage.idle || stage.gameUp)
    }
    readonly property bool gameUp: !!(Shell.bar && Shell.bar.covered && Shell.bar.covered.length)
    property bool coldOpen: false
    property double shownAt: 0
    // the windows go once the stage is up: mapped, it holds the keyboard, so minimizing the focused window
    // doesn't make KWin focus one on another screen, and closing hands the keyboard back to it
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) {
        waitFrame = false
        const took = Date.now() - shownAt          // (a slow first frame is worth knowing about)
        if (Shell.debug || took >= 50) console.warn("ATOM stage first frame", screenName, took, "ms", coldOpen ? "(rested)" : "")
        if (launcher.clearDesk && !finder) Windows.clear(screenName)
        startOpen()
    }


    // ------------------------------------------------------------------ the choreography (Motion.js tracks)
    // the lab's "fade": the backdrop fades in, the content comes forward from a little closer (1.06), then the
    // top bar, the hero and the tiles one after another; closing fades it all, the content going a little
    // closer as it leaves. One clock per move.
    property real bgO: 0
    property real planeO: 0
    property real planeS: 1
    property real topO: 0
    property real heroO: 0
    property real openT: 0
    property real closeT: 0
    property var closeFrom: ({})
    NumberAnimation { id: openClock; target: stage; property: "openT"; from: 0; to: stage.openTotal; duration: stage.openTotal
                      onFinished: { stage.applyOpen(1e9); stage.phase = "open" } }    // everything at rest, whatever lagged
    NumberAnimation { id: closeClock; target: stage; property: "closeT"; from: 0; to: stage.closeMs; duration: stage.closeMs; onFinished: stage.closed() }
    readonly property real openTotal: openMs * 0.9 + 16 * staggerMs
    onOpenTChanged: if (phase === "opening") applyOpen(openT)
    onCloseTChanged: if (phase === "closing") applyClose(closeT)
    function startOpen() {
        applyOpen(0)
        openClock.restart()
    }
    function applyOpen(t) {
        const d = openMs
        const home = finder ? 0 : 1
        bgO = home * M.track(t, 0, d * 0.65, M.enter)
        planeO = home * M.track(t, d * 0.06, d * 0.8, M.enter)
        planeS = M.lerp(1.06, 1, planeO)
        topO = home * M.track(t, d * 0.16, d * 0.62, M.enter)
        heroO = home * M.track(t, d * 0.2, d * 0.66, M.enter)
        // the rows: their tiles come in from the right, one after another (a dozen a row at most)
        const st = pageState()
        for (let k = 0; k < page.rows.length; k++) {
            const row = rowItem(k)
            if (!row) continue
            const n = k
            row.titleO = n < 0 ? 0 : M.track(t, d * 0.22 + n * 3 * staggerMs, d * 0.6, M.enter)
            const tiles = row.shown()
            for (let i = 0; i < tiles.length; i++) {
                const v = n < 0 ? 0 : M.track(t, d * 0.22 + (n * 3 + Math.min(i, 11)) * staggerMs, d * 0.66, M.enter)
                tiles[i].opacity = v
                tiles[i].enter = (1 - v) * u(80)
            }
        }
        if (t > 0 && !contentIn) contentIn = true
    }
    function startClose() {
        closeFrom = { plane: planeO, bg: bgO }
        applyClose(0)
        closeClock.restart()
    }
    function applyClose(t) {
        const d = closeMs, f = closeFrom
        planeO = (f.plane ?? 1) * (1 - M.track(t, 0, d * 0.55, M.exit))
        planeS = M.lerp(1, 1.035, M.track(t, 0, d * 0.55, M.exit))
        bgO = (f.bg ?? 1) * (1 - M.track(t, d * 0.12, d * 0.88, M.move))
        launchFly.opacity = 1 - M.track(t, 0, d * 0.9, M.move)
    }
    function closed() {
        phase = "closed"
        coverAnim.stop()
        coverP = 0
        contentIn = false
        launchFly.visible = false
        searchOpen = false
        searchP = 0
    }
    property bool contentIn: false
    onContentInChanged: if (contentIn) launcher.stageEntered()

    // ------------------------------------------------------------------ following the pointer
    // While it's open it follows the pointer to another screen, query and all (only a move counts, not where
    // it rested at first). KWin's rice_islands script says which screen the pointer is on the moment it
    // crosses over (Shell.bar.pointer); without it, KWin is asked every 150 ms.
    property string pointerAt: ""
    readonly property bool following: stage.wanted && !stage.powerOver && (stage.phase === "opening" || stage.phase === "open") && stage.launcher.view !== "walls"
    onFollowingChanged: if (following && Shell.bar) pointerSeen(Shell.bar.pointer || "")
    Connections {
        target: Shell
        enabled: stage.following
        function onBarChanged() { if (Shell.bar) stage.pointerSeen(Shell.bar.pointer || "") }
    }
    Timer {
        interval: 150
        repeat: true
        running: stage.following && !Shell.bar
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
        Shell.open("launcher", name, there, { query: launcher.query, searchOnly: finder })
    }

    // The upper bar (Glimpse's strip, the top band) is never covered, moved or resized: the stage starts
    // right under it (a top margin as tall as the band) and lays itself out in the space below
    readonly property var strip: Shell.island("strip", screenName)
    readonly property real topGap: strip && screenObj ? Math.max(0, Math.round(strip.y + strip.height - screenObj.virtualY)) : 0


    // ------------------------------------------------------------------ the data and the focus
    HomeModel { id: hm; launcher: stage.launcher }
    ThemeModel { id: tm; launcher: stage.launcher; rice: stage.rice; screenName: stage.screenName }
    readonly property int themeTab: 3
    property int tab: 0                         // 0 Home, 1 Games, 2 Apps, 3 the Theme page (no tab: the palette)
    property int tabBefore: 0                   // where the Theme page goes back to
    // the Theme page in groups (ThemeModel's headers): the rows of the open ones (Look open to start)
    property var groupsOpen: ({ look: true })
    readonly property var themePage: ({ id: "theme", rows: tm.rows.filter(r => r.header || groupsOpen[r.group]) })
    function toggleGroup(g) {
        const o = Object.assign({}, groupsOpen); o[g] = !o[g]; groupsOpen = o
        if (Shell.debug) console.warn("ATOM theme group", g, o[g] ? "open" : "closed")
        Qt.callLater(() => {        // the header keeps the focus (rows above it may have gone)
            const ri = page.rows.findIndex(r => r.id === "group:" + g)
            if (ri >= 0) { const st = pageState(); st.row = -1; focusAt(ri, 0, "key") }
        })
    }
    readonly property var emptyPage: ({ id: "", rows: [] })
    function pageAt(p) { return p === themeTab ? themePage : hm.pages[p] || emptyPage }
    readonly property var page: pageAt(tab)
    readonly property bool theming: tab === themeTab
    // per page: the active row, the row at the top, each row's focus (by row id)
    // (the Theme page also has lines: "tiles", a row's header "tools" (tool: which), or the "desk" map (desk: which))
    function freshStates() { return [0, 1, 2, 3].map(() => ({ row: 0, idx: {}, lines: {}, line: "tiles", tool: 0, desk: 0, top: 0 })) }
    property var states: freshStates()
    property int focusRev: 0
    function pageState() { return states[tab] }
    function idxOf(rowId) { focusRev; const i = pageState().idx[rowId]; return i === undefined ? 0 : i }
    function rowObj(ri) { return page.rows[ri] || null }
    readonly property var currentItem: {
        focusRev; hm.rev; tm.rev
        const r = rowObj(pageState().row)
        return r ? entryOf(pageState().row, Math.min(idxOf(r.id), slotsOf(pageState().row) - 1)) : null
    }
    // the shown page's row ri (each page is a column of rows, made the first time it shows)
    function rowItem(ri, p) { const pg = pagesRep.itemAt(p === undefined ? tab : p); return pg ? pg.rowAt(ri) : null }
    function currentTile() {
        const r = rowObj(pageState().row), row = rowItem(pageState().row)
        return row && r ? row.tileAt(idxOf(r.id)) : null
    }
    // from "key", the row and the page move to keep the focus at its anchors; from the pointer they don't
    // (the content would slide out from under it)
    // the pointer only focuses what it was moved onto: not what slides under it while the keys, the wheel or
    // a drag move the rows (Qt reports those as hovers too: the focus, the hero and the backdrop would churn)
    property double quietUntil: 0
    // The pointer's intent. A tile takes the focus when the pointer rests on it or slows down over it, not
    // while the pointer only passes over it on its way somewhere else (up to the hero's buttons, across
    // other rows: the focus, and the hero's buttons with it, would change under it before it got there).
    // Only real pointer moves count: when content slides under a still pointer Qt reports a hover too, at the
    // same place in the window.
    // The input used last wins: the pointer moving (really moving: content sliding under a still one doesn't
    // count) makes it the input in use (tiles show its hover and their corner actions, the key hints fade);
    // a key or a pad's button gives it back to them, and a still pointer never takes the focus back.
    property bool pointerMode: false
    property point pointerSeenAt: Qt.point(-1, -1)
    function pointerMoved(at) {
        const known = pointerSeenAt.x >= 0
        const moved = known && Math.abs(at.x - pointerSeenAt.x) + Math.abs(at.y - pointerSeenAt.y) > 1
        pointerSeenAt = at
        if (moved && phase === "open" && !pointerMode) { pointerMode = true; if (Shell.debug) console.warn("ATOM home input pointer") }
    }
    onPointerModeChanged: if (Shell.debug && !pointerMode) console.warn("ATOM home input keys")
    property var aim: null                      // { ri, i }: the tile under the pointer
    property var aimTrail: []                   // its recent places: [{ x, y, t }]
    property bool pointerKnown: false           // a first position seen since opening (that one isn't a move)
    property point pointerAt0: Qt.point(0, 0)
    readonly property real aimSpeed: 0.35       // logical px per ms: slower than this is meant (~350 px/s)
    Timer { id: aimTimer; interval: 60; onTriggered: stage.aimCheck() }
    function pointed(ri, i, at) {
        const moved = !pointerKnown || Math.abs(at.x - pointerAt0.x) + Math.abs(at.y - pointerAt0.y) > 0.5
        const first = !pointerKnown
        pointerKnown = true
        pointerAt0 = at
        aim = { ri: ri, i: i }
        if (first || !moved) return             // where it was when the page came, or content sliding under it
        const now = Date.now()
        aimTrail = aimTrail.filter(p => now - p.t < 150).concat([{ x: at.x, y: at.y, t: now }])
        aimCheck()
    }
    function unpointed(ri, i) { if (aim && aim.ri === ri && aim.i === i) { aim = null; aimTimer.stop() } }
    function aimCheck() {
        if (!aim) return
        const now = Date.now()
        aimTrail = aimTrail.filter(p => now - p.t < 150)
        // its speed: from the oldest place kept to the newest, over the time since the oldest (so a pointer
        // that stops slows down to nothing); one place alone says nothing yet, unless nothing came after it
        // (the trail is kept across tiles and commits: a hand sweeping on doesn't look still on the next tile)
        const tr = aimTrail
        let v = 0
        if (tr.length >= 2) v = Math.hypot(tr[tr.length - 1].x - tr[0].x, tr[tr.length - 1].y - tr[0].y) / Math.max(16, now - tr[0].t)
        else if (tr.length === 1 && now - tr[0].t < 50) v = Infinity
        if (v < aimSpeed) focusAt(aim.ri, aim.i, "mouse")
        else aimTimer.restart()                 // still on its way: look again (a pointer that stops sends nothing)
    }
    // a row's slots: its tiles as shown, and its controls (HomeRow: "Show more" / "Show less"); a row not made yet: its items
    function slotsOf(ri) { const row = rowItem(ri), r = rowObj(ri); return row ? row.slotCount : r ? r.items.length : 0 }
    function entryOf(ri, i) { const row = rowItem(ri), r = rowObj(ri); return row ? row.entryAt(i) : r ? r.items[i] || null : null }
    function rowsMoving() { const pg = pagesRep.itemAt(tab); return !!(pg && pg.moving) }
    function focusAt(ri, i, from) {
        if (from === "mouse" && (Date.now() < quietUntil || rowsMoving())) return
        const st = pageState()
        const r = rowObj(ri)
        if (!r) return
        i = Math.max(0, Math.min(slotsOf(ri) - 1, i))
        if (from === "mouse" && st.line !== "tiles") { st.line = "tiles"; focusRev++ }     // the pointer is on a tile
        if (st.row === ri && idxOf(r.id) === i) return
        st.row = ri
        st.idx[r.id] = i
        if (from === "key") quietUntil = Date.now() + focusMs * 1.5 + 80
        focusRev++
        if (from === "key") ensureVisible(true)
        if (Shell.debug) logFocus(from)
    }
    function step(dx, dy) {
        const st = pageState()
        if (st.line === "top") {        // the top bar: along it, or back down to the rows (the desk map on the Theme page)
            if (dy > 0) { if (theming) setLine("desk", undefined, Math.max(0, deskTargets.indexOf(tm.target))); else setLine("tiles") }
            else if (dx) setLine("top", undefined, Math.max(0, Math.min(topItems.length - 1, st.top + dx)))
            return
        }
        if (theming) { themeStep(dx, dy); return }
        if (dy < 0 && st.row === 0) { setLine("top", undefined, Math.max(0, topItems.indexOf("tab" + tab))); return }
        if (dy) { if (!lineStep(dy)) { const ri = st.row + dy; const r = rowObj(ri); if (r) focusAt(ri, idxOf(r.id), "key") } }
        else { const r = rowObj(st.row); if (r) focusAt(st.row, idxOf(r.id) + dx, "key") }
    }
    // up and down within a row of several lines first (the same column, or the line's last slot), then on
    function lineStep(dy) {
        const st = pageState(), row = rowItem(st.row), r = rowObj(st.row)
        if (!row || !r) return false
        const i = idxOf(r.id), c = row.columns, line = row.lineOf(i) + dy
        if (line < 0 || line >= row.linesShown) return false
        focusAt(st.row, Math.min(row.slotCount - 1, line * c + i % c), "key")
        return true
    }
    // "Show more" / "Show less": two lines more or fewer of that row (the keys stay on the same kind of control,
    // so pressing on keeps going; the pointer's focus stays where it is)
    function rowControl(ri, ctl, from) {
        const st = pageState(), r = rowObj(ri), row = rowItem(ri)
        if (!r || !row) return
        const L = Math.max(1, st.lines[r.id] ?? 1), shownBefore = row.shownItems
        st.lines[r.id] = ctl === "more" ? L + 2 : Math.max(1, L - 2)
        focusRev++
        if (Shell.debug) console.warn("ATOM row", r.id, ctl, "lines", st.lines[r.id])
        if (from === "mouse") return
        Qt.callLater(() => {
            const n = row.shownItems, lay = row.layout
            // more: the first tile it brought; less: its own control again if it's still there, else "Show more"
            const at = ctl === "more" ? shownBefore : lay.less ? n + (lay.more ? 1 : 0) : n
            st.idx[r.id] = -1
            focusAt(ri, Math.min(at, row.slotCount - 1), "key")
        })
    }
    // the top bar's parts the keys walk (Up from the first row; the desk map's line on the Theme page)
    readonly property var topItems: theming ? ["back", "search", "theme", "power"] : ["tab0", "tab1", "tab2", "search", "theme", "power"]
    function topEnter() {
        const id = topItems[pageState().top] || ""
        if (id.startsWith("tab")) { const i = Number(id.slice(3)); if (i !== tab) { setTab(i); Qt.callLater(() => setLine("top", undefined, topItems.indexOf("tab" + i))) } }
        else if (id === "back") setTab(tabBefore)
        else if (id === "search") openSearch("")
        else if (id === "theme") toggleTheme()
        else if (id === "power") openPowerHere()
    }
    function openPowerHere() {
        const p = powerButton.mapToGlobal(0, 0)
        launcher.openPower({ x: p.x, y: p.y, width: powerButton.width, height: powerButton.height })
    }
    function toggleTheme() { setTab(theming ? tabBefore : themeTab) }
    // ---- the Theme page's lines, walked spatially: the desk map at the top; per row its header's tools,
    // then its tiles. Up and down go to the line above or below, left and right along it.
    readonly property var deskTargets: tm.screens.map(x => x.name).concat(["all"])
    function toolsOf(r) { return r && r.tools ? r.tools : [] }
    function canFocusTool(r, i) { const t = toolsOf(r)[i]; return !!t && t.kind !== "value" }
    function firstTool(r, from, d) {
        const n = toolsOf(r).length
        for (let i = Math.max(0, Math.min(n - 1, from)); i >= 0 && i < n; i += d) if (canFocusTool(r, i)) return i
        for (let i = Math.max(0, Math.min(n - 1, from)); i >= 0 && i < n; i -= d) if (canFocusTool(r, i)) return i
        return -1
    }
    function setLine(line, ri, extra) {
        const st = pageState()
        st.line = line
        if (extra !== undefined) { if (line === "tools") st.tool = extra; else if (line === "desk") st.desk = extra; else if (line === "top") st.top = extra }
        if (ri !== undefined && ri !== st.row) { const r = rowObj(ri); focusAt(ri, idxOf(r.id), "key") }
        else { quietUntil = Date.now() + focusMs * 1.5 + 80; focusRev++; if (line === "desk") { const pg = pagesRep.itemAt(tab); if (pg) pg.scrollToY(0, true) } else ensureVisible(true) }
        if (Shell.debug) {
            console.warn("ATOM theme line", line, "row", st.row, line === "tools" ? "tool " + toolsOf(rowObj(st.row))[st.tool].id : line === "desk" ? "desk " + deskTargets[st.desk]
                         : line === "top" ? "top " + topItems[st.top] : "")
            logFocus()          // (and where the tools sit now: the tests click them)
        }
    }
    function themeStep(dx, dy) {
        const st = pageState(), line = st.line || "tiles", r = rowObj(st.row)
        if (dy && line === "tiles" && lineStep(dy)) return     // a row of several lines: its lines first
        if (dy < 0) {
            if (line === "desk") { setLine("top", undefined, topItems.indexOf("theme")); return }
            if (line === "tiles" && firstTool(r, 0, 1) >= 0) { setLine("tools", st.row, firstTool(r, 0, 1)); return }
            if (st.row > 0) { setLine("tiles", st.row - 1); return }
            setLine("desk", undefined, Math.max(0, deskTargets.indexOf(tm.target)))
            return
        }
        if (dy > 0) {
            if (line === "desk") { const t = firstTool(rowObj(0), 0, 1); if (t >= 0) setLine("tools", 0, t); else setLine("tiles", 0); return }
            if (line === "tools") { setLine("tiles"); return }
            const nr = rowObj(st.row + 1)
            if (!nr) return
            const t = firstTool(nr, 0, 1)
            if (t >= 0) setLine("tools", st.row + 1, t); else setLine("tiles", st.row + 1)
            return
        }
        if (line === "tiles") { const rr = rowObj(st.row); if (rr) focusAt(st.row, idxOf(rr.id) + dx, "key") }
        else if (line === "tools") {
            for (let i = st.tool + dx; i >= 0 && i < toolsOf(r).length; i += dx) if (canFocusTool(r, i)) { setLine("tools", undefined, i); return }
        } else if (line === "desk") setLine("desk", undefined, Math.max(0, Math.min(deskTargets.length - 1, st.desk + dx)))
    }
    // Enter on the Theme page: the tile, the tool or the screen the keys are on
    function themeEnter() {
        const st = pageState()
        if (st.line === "tools") { const t = toolsOf(rowObj(st.row))[st.tool]; if (t) toolDo(t.id) }
        else if (st.line === "desk") { const n = deskTargets[st.desk]; if (n) tm.target = n }
        else activateItem(currentItem, currentTile())
    }
    function toolDo(id) {
        if (Shell.debug) console.warn("ATOM theme tool", id)
        tm.tool(id)
    }
    Connections {
        target: tm
        function onOpenFinder() {       // the wallhaven search lives in the detailed panel, opened on it
            stage.launcher.openWallpapers("desktop", "walls")
            Qt.callLater(() => { if (stage.launcher.wallsPane) stage.launcher.wallsPane.discover = true })
        }
    }
    // the Theme page's rows open on what's in use (the theme, this screen's wallpaper, its colours...)
    function focusInUse() {
        const st = states[themeTab]
        let moved = false
        tm.rows.forEach((r, k) => {
            if (st.idx[r.id] !== undefined) return
            const i = r.items.findIndex(it => it.current)
            const row = rowItem(k, themeTab)
            // (only where it shows: one past "Show more" stays folded, the focus at the row's start)
            if (i < 0 || !row || i >= row.shownItems) return
            st.idx[r.id] = i
            moved = true
        })
        if (moved) focusRev++
    }
    Connections { target: tm; function onRevChanged() { stage.focusInUse() } }   // also before the page swap ends
    // Meta+Shift+W: the Theme page, at a row (walls, colours or lights)
    function openTheme(rowId) {
        if (!theming) setTab(themeTab)
        if (!rowId) return
        const id = rowId === "lights" ? "kb-laptop" : rowId
        const go = () => {
            const row = tm.rows.find(x => x.id === id)
            if (row && !groupsOpen[row.group]) { const o = Object.assign({}, groupsOpen); o[row.group] = true; groupsOpen = o }
            Qt.callLater(() => { const r = page.rows.findIndex(x => x.id === id); if (r >= 0) focusAt(r, idxOf(id), "key") })
        }
        if (tm.rows.length) Qt.callLater(go)
        else { const once = () => { tm.revChanged.disconnect(once); Qt.callLater(go) }; tm.revChanged.connect(once) }
    }
    Connections { target: stage.launcher; function onThemeAskChanged() { stage.openTheme(stage.launcher.themeRow) } }
    function logFocus(from) {
        const it = currentItem
        console.warn("ATOM home tab", tab, "row", pageState().row, "item", it ? (it.name || it.key || "") : "-", from ? "(" + from + ")" : "")
        focusLog.restart()          // where the focused tile is, once the page has stopped scrolling (the tests use it)
        if (theming) logLater.restart()
    }
    // where the Theme page's actions and tools sit, once the page has stopped scrolling (the tests click them)
    Timer { id: focusLog; interval: Math.round(stage.focusMs * 1.6) + 120
            onTriggered: { const t = stage.currentTile(); if (t) { const p = t.mapToItem(null, t.width / 2, t.height / 2); console.warn("ATOM home focus at", Math.round(stage.screenObj.virtualX + p.x), Math.round(stage.screenObj.virtualY + stage.topGap + p.y)) } } }
    Timer { id: logLater; interval: Math.round(stage.focusMs * 1.6) + 120; onTriggered: stage.logThemeParts() }
    function logThemeParts() {
        if (theming) Qt.callLater(() => {      // the hero's own actions, where they sit (once it has laid out)
            const h = heroRep.itemAt(heroSlot)
            const th = h ? h.th : null
            if (th) th.extra.forEach((x, i) => { const p = h.extraAt(i); if (p) console.warn("ATOM theme action", x.id, "at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + topGap + p.y)) })
            for (let k = 0; k < page.rows.length; k++) {      // the rows' tools, where they sit
                const row = rowItem(k), tools = toolsOf(rowObj(k))
                for (let i = 0; row && i < tools.length; i++) {
                    const b = row.toolAt(i)
                    if (!b) continue
                    const p = b.mapToItem(null, b.width / 2, b.height / 2)
                    console.warn("ATOM theme tool", tools[i].id, "at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + topGap + p.y))
                }
            }
        })
    }
    function logLayout() {
        const t = currentTile()
        if (t) { const p = t.mapToItem(null, t.width / 2, t.height / 2); console.warn("ATOM home focus at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + topGap + p.y)) }
        const tabsP = tabs.mapToItem(null, 0, 0)
        const at = b => { const q = b.mapToItem(null, b.width / 2, b.height / 2); return Math.round(screenObj.virtualX + q.x) + " " + Math.round(screenObj.virtualY + topGap + q.y) }
        console.warn("ATOM home tabs at", Math.round(screenObj.virtualX + tabsP.x), Math.round(screenObj.virtualY + topGap + tabsP.y), "search at", at(searchButton), "theme at", at(themeButton), "power at", at(powerButton))
    }
    function setTab(i) {
        if (i !== themeTab) i = (i + 3) % 3
        if (i === tab) return
        if (i === themeTab) { tabBefore = tab; tm.reload(); focusInUse() }
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
        ScriptAction { script: {
            const t0 = Date.now()
            stage.tab = tabSwap.next
            rowsSlide.x = tabSwap.dir * stage.u(56)
            stage.settleAll()
            if (Shell.debug) { console.warn("ATOM home tab swap", Date.now() - t0, "ms"); stage.logFocus() }
        } }
        ParallelAnimation {
            NumberAnimation { target: rowsBox; property: "opacity"; to: 1; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
            NumberAnimation { target: rowsSlide; property: "x"; to: 0; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }
        }
    }
    function settleAll() { scrollPage(false) }
    // the page keeps the focused line in sight, moving as little as it can: up to the row's title on its first
    // line (or its tools), down to the line's labels (and the next row's title peeking in, when there's room)
    function ensureVisible(animate) {
        const pg = pagesRep.itemAt(tab), st = pageState(), row = rowItem(st.row), r = rowObj(st.row)
        if (!pg || !row || !r) return
        const top = pg.rowTop(st.row), line = row.lineOf(Math.max(0, idxOf(r.id)))
        const view = rowsBox.height, cy = pg.contentY
        const y0 = line === 0 || st.line === "tools" ? top : top + row.lineY(line) - u(16)
        let y1 = top + row.lineY(line) + row.lineH + row.pad
        if (line === row.linesShown - 1) y1 = Math.min(top + row.fullHeight + u(40), Math.max(y1, top + row.fullHeight))
        let t = cy
        if (y0 < cy) t = y0
        else if (y1 > cy + view) t = Math.max(y0 - u(0), y1 - view)
        if (st.row === 0 && line === 0) t = 0
        pg.scrollToY(t, animate)
    }
    function scrollPage(animate) { ensureVisible(animate) }
    // the wheel (and a touchpad) scrolls the page, as a page; the keys and the pad walk the focus
    function onWheel(ev, pos) {
        const pg = pagesRep.itemAt(tab)
        if (!pg) return
        const px = ev.pixelDelta.y
        pg.scrollBy(px ? -px : -ev.angleDelta.y / 120 * u(110))
        quietUntil = Date.now() + 160         // (content sliding under a still pointer isn't the pointer moving)
    }


    // fresh every time it opens: Home, the first pin, no query
    onOpened: {
        tab = 0
        states = freshStates()
        focusRev++
        launcher.query = ""
        launcher.category = 0
        searchOpen = false
        searchP = 0
        launchFly.visible = false
        launchFly.opacity = 1
        Qt.callLater(settleAll)
        Qt.callLater(() => keys.forceActiveFocus())
        // the focus may be the same item as last time (or have arrived while it was closed): no change to
        // follow, so the hero and the backdrop are given it now
        Qt.callLater(() => {
            const it = currentItem
            if (!it) return
            if (heroItems[heroSlot] !== it) heroShow(it)
            else { const o = heroO2.slice(); o[heroSlot] = 1; heroO2 = o; const x = heroX.slice(); x[heroSlot] = 0; heroX = x }
            bgShown = null
            setBackdrop(it)
        })
        if (!finder) {      // (the finder shows neither the home's art and usage nor the Theme page)
            sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" launcher-data #data')
            tm.reload()     // the Theme page's data, ready before it's asked for (rebuilt only if it changed)
        }
        if (finder || (Shell.args && Shell.args.query)) Qt.callLater(() => stage.openSearch(Shell.args.query || ""))
    }
    RiceShell { id: sh; onNewData: (source, data) => disconnectSource(source) }

    // ------------------------------------------------------------------ the backdrop
    // the backdrop in the blur style chosen on the Theme page, as the power page wears it (Atom Backdrop):
    // noisy matte fades in with the room; clear blur (KWin's live blur can't fade) ripples out from the jewel
    Backdrop {
        id: backdropStyle
        anchors.fill: parent
        window: stage
        pal: stage.rice
        origin: stage.rippleOrigin
        radius: !glass || stage.bgO >= 0.999 ? -1 : reach * stage.bgO
        opacity: !glass ? stage.bgO : 1
        veil: glass ? Prefs.glassVeil : 0       // (clear: the power page's glass, exactly)
        offsetY: stage.topGap                   // (the window starts under the top band: the wallpaper lines up)
        grained: false                  // (the grain goes over the scrims: the launcher draws it, last)
        also: stage.finderShapes        // (the finder's plate: one blur region per window)
    }
    Item {
        id: win
        anchors.fill: parent
        opacity: stage.bgO
        visible: stage.phase !== "closed" && opacity > 0.001
        Item {
            id: backdrop
            anchors.fill: parent

            // an app with no art of its own: the wallpaper, coloured with the app's own colour (its icon's
            // dominant one), and the icon large on the right (two slots, cross-faded)
            Repeater {
                model: 2
                Item {
                    id: glow
                    required property int index
                    anchors.fill: parent
                    opacity: stage.bgSlot === index ? stage.bgGlow[index] : 0
                    visible: opacity > 0.001
                    property var item: stage.bgItems[index]
                    Kirigami.ImageColors { id: glowColors; source: glow.item ? glow.item.icon : "" }
                    readonly property color c: C.appTint(glowColors, stage.rice.primary)
                    Image {     // noisy matte: the frosted wallpaper itself, coloured
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        visible: backdropStyle.matte
                        source: visible ? backdropStyle.frostSource : ""
                        layer.enabled: glow.visible && visible
                        layer.effect: MultiEffect { colorization: 0.55; colorizationColor: glow.c; brightness: 0.04 }
                    }
                    Rectangle {     // clear blur: a breath of its colour on the glass
                        anchors.fill: parent
                        visible: backdropStyle.glass
                        color: C.alpha(glow.c, 0.08)
                    }
                    Kirigami.Icon {     // (a blurred filter: not in no blur)
                        x: parent.width * 0.94 - width; y: parent.height * 0.04
                        width: parent.height * 0.46; height: width
                        visible: !backdropStyle.sharp
                        source: glow.item && visible ? glow.item.icon : ""
                        opacity: 0.5
                        layer.enabled: glow.visible && visible
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
                    visible: opacity > 0.001
                    transformOrigin: Item.Top
                    layer.enabled: visible
                    layer.effect: MultiEffect {     // fades into the room at the bottom
                        maskEnabled: true
                        maskSource: artMask
                        maskThresholdMin: 0.5       // with the spread: smoothstep over the mask's whole 0..1 alpha
                        maskSpreadAtMin: 1.0        // (the defaults let every pixel through: a hard cut where the art ends)
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
            // Text over a picture reads by measure, not by luck: the theme engine says how bright the backdrop
            // gets under the hero and under the rows (the palette's _backdrop for this screen's frosted
            // wallpaper; a game's banner its own, launcher-data's light), and a scrim of the palette's darkest
            // surface comes in exactly as strong as the dimmest text there needs for 4.5:1, and no stronger
            // (a blanket shade turned every wallpaper into the same dark mud)
            Rectangle {     // under the hero: from the left
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(stage.rice.surfaceLowest, stage.scrimHero) }
                    GradientStop { position: 0.4; color: C.alpha(stage.rice.surfaceLowest, stage.scrimHero) }
                    GradientStop { position: 0.62; color: C.alpha(stage.rice.surfaceLowest, stage.scrimHero * 0.45) }
                    GradientStop { position: 0.85; color: C.alpha(stage.rice.surfaceLowest, 0) }
                }
            }
            Rectangle {     // under the rows: one smooth curve from 0% at the top to the bottom of the screen (rowsCurve)
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: stage.rowsCurve[0].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[0].a) }
                    GradientStop { position: stage.rowsCurve[1].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[1].a) }
                    GradientStop { position: stage.rowsCurve[2].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[2].a) }
                    GradientStop { position: stage.rowsCurve[3].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[3].a) }
                    GradientStop { position: stage.rowsCurve[4].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[4].a) }
                    GradientStop { position: stage.rowsCurve[5].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[5].a) }
                    GradientStop { position: stage.rowsCurve[6].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[6].a) }
                    GradientStop { position: stage.rowsCurve[7].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[7].a) }
                    GradientStop { position: stage.rowsCurve[8].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[8].a) }
                    GradientStop { position: stage.rowsCurve[9].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[9].a) }
                    GradientStop { position: stage.rowsCurve[10].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[10].a) }
                    GradientStop { position: stage.rowsCurve[11].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[11].a) }
                    GradientStop { position: stage.rowsCurve[12].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[12].a) }
                    GradientStop { position: stage.rowsCurve[13].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[13].a) }
                    GradientStop { position: stage.rowsCurve[14].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[14].a) }
                    GradientStop { position: stage.rowsCurve[15].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[15].a) }
                    GradientStop { position: stage.rowsCurve[16].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[16].a) }
                    GradientStop { position: stage.rowsCurve[17].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[17].a) }
                    GradientStop { position: stage.rowsCurve[18].p; color: C.alpha(stage.rice.surfaceLowest, stage.rowsCurve[18].a) }
                }
            }
            // a fine grain over it all: the dark, smooth gradients of a blurred picture band in 8 bits; noise
            // breaks the bands up (dithering)
            Image {
                anchors.fill: parent
                visible: backdropStyle.matte        // (clear blur is clear: no grain)
                source: visible ? backdropStyle.grain : ""
                fillMode: Image.Tile
                smooth: false
                opacity: backdropStyle.grainAlpha
            }
        }
    }
    Rectangle {     // the rows' fade at the bottom (when there are more below)
        id: rowsMask
        width: rowsBox.width
        height: rowsBox.height
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0; color: rowsBox.scrolled ? "transparent" : "black" }
            GradientStop { position: Math.min(0.4, stage.u(46) / Math.max(1, rowsBox.height)); color: "black" }
            GradientStop { position: Math.max(0.6, 1 - stage.u(40) / Math.max(1, rowsBox.height)); color: "black" }
            GradientStop { position: 1; color: rowsBox.overflow ? "transparent" : "black" }
        }
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

    // the finder's plate is blurred behind (KWin), through the backdrop's blur (one region per window)
    readonly property var finderShapes: {
        if (!finderCard.visible || finderCard.opacity < 0.5) return []
        finderCard.x; finderCard.y; finderCard.width; finderCard.height          // (mapToItem alone doesn't follow them)
        const p = finderCard.mapToItem(null, 0, 0)
        return [{ x: p.x, y: p.y, width: finderCard.width, height: finderCard.height, radius: finderCard.radius }]
    }

    // ------------------------------------------------------------------ the text's scrims (see the backdrop)
    // how strong a scrim of the darkest surface must be over a backdrop of luminance Yb for text of colour
    // `ink` to reach `ratio` (blending happens on gamma-encoded values: compared there)
    function scrimFor(Yb, ink, ratio) { return C.scrim(Yb, ink, rice.surfaceLowest, ratio) }     // (Rice Color.js)
    // how bright the backdrop gets under the text now: the frosted wallpaper's measure; a game's banner its
    // own (it's 90% strong and fades out down the rows); a wallpaper previewed on the Theme page isn't
    // measured: careful
    readonly property var lightNow: {
        const w = (backdropStyle.sharp ? rice.values._backdropSharp : rice.values._backdrop) || ({})
        // (clear blur: the windows under the glass, unmeasured: as bright as a careful guess, or the
        // wallpaper's measure if it's brighter, under the backdrop's veil)
        const v = backdropStyle.veil, g = y => Math.pow(Math.max(0, y), 1 / 2.2), Ys = C.luminance(rice.surfaceLowest)
        const veiled = y => v > 0 ? Math.pow(v * g(Ys) + (1 - v) * g(Math.max(y, 0.35)), 2.2) : y
        const base = { top: veiled(w.top ?? 0.35), hero: veiled(w.hero ?? 0.35), rows: veiled(w.rows ?? 0.35) }
        const it = bgShown
        const careful = { top: 0.6, hero: 0.6, rows: 0.6 }
        if (theming && it && it.kind) return careful
        const l = it && it.art && it.art.hero ? it.art.light : null
        if (it && it.art && it.art.hero && !(l && l.top !== undefined)) return careful
        return l ? { top: Math.max(base.top, l.top * 0.9), hero: Math.max(base.hero, l.hero * 0.9), rows: Math.max(base.rows, l.rows * 0.7) } : base
    }
    property real scrimHero: scrimFor(lightNow.hero, rice.fgDim, 4.5)
    property real scrimRows: scrimFor(lightNow.rows, rice.fgDim, 4.5)
    // The rows' scrim as one smooth curve (no edge anywhere, the user 2026-11-15): 0% at the top of the page,
    // easing in (smoothstep: flat at both ends) to the strength the rows' text needs right where the first row
    // starts, then on, gently, to a little more at the bottom of the screen. Sampled as gradient stops
    // (a gradient is straight between its stops).
    readonly property var rowsCurve: {
        const H = Math.max(1, height), y1 = Math.max(1, Math.min(H - 1, rowsTop)), S = scrimRows
        const Smax = Math.min(0.94, S + Math.max(0.08, S * 0.3)), ss = t => t * t * (3 - 2 * t)
        const out = []
        for (let i = 0; i <= 10; i++) out.push({ p: (y1 * i / 10) / H, a: S * ss(i / 10) })
        for (let i = 1; i <= 8; i++) out.push({ p: (y1 + (H - y1) * i / 8) / H, a: S + (Smax - S) * ss(i / 8) })
        return out
    }
    Behavior on scrimHero { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    Behavior on scrimRows { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    onLightNowChanged: if (Shell.debug) console.warn("ATOM home scrim hero", scrimFor(lightNow.hero, rice.fgDim, 4.5).toFixed(2), "rows", scrimFor(lightNow.rows, rice.fgDim, 4.5).toFixed(2))

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
        if (!it || it === bgShown || it.ctl) return          // (a row's "Show more" keeps the room as it is)
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
            g[slotTo] = art || paper ? 0 : v
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
        // which input is in use: the pointer's real moves anywhere on the page (stage.pointerMoved)
        HoverHandler { id: pointerWatch }
        readonly property point pointerPos: pointerWatch.point.position
        onPointerPosChanged: stage.pointerMoved(pointerPos)

        MouseArea {     // bare backdrop: a click closes it (a click: not a drag or a swipe that ended here)
            anchors.fill: parent
            enabled: stage.phase === "open" && !stage.searchOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property point at
            onPressed: mouse => at = Qt.point(mouse.x, mouse.y)
            onClicked: mouse => {
                if (Math.hypot(mouse.x - at.x, mouse.y - at.y) > 12) return
                if (stage.launcher.view === "walls") stage.launcher.view = "apps"; else stage.launcher.close()
            }
        }

        Item {
            id: plane
            anchors.fill: parent
            // the search takes the whole room: the page under it goes (only the frosted backdrop stays)
            opacity: stage.planeO * (stage.searchOpen ? 1 - stage.searchP : 1) * (stage.launcher.view === "walls" ? 0 : 1) * (1 - stage.coverP)
            visible: opacity > 0.01
            scale: stage.planeS * M.lerp(1, 0.965, stage.coverP)
            Behavior on opacity { enabled: stage.phase === "open" && !coverAnim.running; NumberAnimation { duration: Tokens.base } }

            // ---- the top bar: the jewel (the logo: Home), the pages on their track, then search, theme, power,
            // the time and you. One control height (barH), a third bigger than a window's; the keys reach it
            // too (up from the first row: the "top" line), so every part has a focus ring as well as a hover
            Item {
                id: topBar
                x: stage.side
                y: stage.u(26)
                width: stage.width - 2 * stage.side
                height: stage.barH
                opacity: stage.topO
                transform: Translate { y: (1 - stage.topO) * -stage.u(18) }
                readonly property string keyOn: (stage.focusRev, stage.pageState().line === "top") ? stage.topItems[stage.pageState().top] || "" : ""
                Row {
                    spacing: stage.u(26)
                    anchors.verticalCenter: parent.verticalCenter
                    JewelChip {         // a round jewel, apart from the tabs: the logo, and the way Home
                        id: homeJewel
                        width: stage.barH; height: stage.barH
                        rice: stage.rice
                        onClicked: stage.tab !== 0 ? stage.setTab(0) : stage.launcher.close()
                    }
                    Row {
                        id: crumb
                        visible: opacity > 0.01
                        opacity: stage.theming ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
                        width: stage.theming ? implicitWidth : 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: stage.u(12)
                        TopButton { height: stage.barH; rice: stage.rice; unit: stage.unit; icon: "arrow_back"; tip: "Back (Esc)"; focused: topBar.keyOn === "back"; onClicked: stage.setTab(stage.tabBefore) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Theme"; color: stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: stage.u(30)
                               layer.enabled: true
                               layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.7; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 } }
                    }
                    Rectangle {         // the pages' track: the one you're on is a solid pill
                        id: tabs
                        width: stage.theming ? 0 : tabRow.width + 2 * stage.u(5)
                        visible: opacity > 0.01
                        opacity: stage.theming ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
                        height: stage.barH
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: C.alpha(stage.rice.surfaceLowest, 0.55)
                        border.width: 1
                        border.color: C.alpha(stage.rice.edge, 0.12)
                        Rectangle {
                            id: tabPill
                            readonly property Item at: (tabRep.count, tabRep.itemAt(stage.tab))     // (count: itemAt doesn't notify)
                            x: (at ? at.x : 0) + stage.u(5)
                            y: stage.u(5)
                            width: at ? at.width : 0
                            height: parent.height - 2 * stage.u(5)
                            radius: height / 2
                            color: stage.rice.light ? stage.rice.fg : "#f3f6fb"
                            Behavior on x { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                            Behavior on width { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                        }
                        Row {
                            id: tabRow
                            x: stage.u(5)
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                id: tabRep
                                model: ["Home", "Games", "Apps"]
                                delegate: Item {
                                    id: tabItem
                                    required property string modelData
                                    required property int index
                                    readonly property bool on: stage.tab === index
                                    width: tabText.implicitWidth + stage.u(48)
                                    height: stage.barH - 2 * stage.u(5)
                                    Text {
                                        id: tabText
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: tabItem.on ? (stage.rice.light ? stage.rice.surfaceLowest : "#0a0d13")
                                             : tabMouse.containsMouse ? stage.rice.fg : stage.rice.fgDim
                                        font.family: Tokens.font.ui
                                        font.weight: Font.Bold
                                        font.pixelSize: stage.u(23)
                                        Behavior on color { ColorAnimation { duration: Tokens.ms(240) } }
                                    }
                                    Rectangle {     // the keys' ring
                                        anchors.fill: parent
                                        anchors.margins: -stage.u(4)
                                        radius: height / 2
                                        color: "transparent"
                                        border.width: Math.max(2, stage.u(2.5))
                                        border.color: stage.rice.light ? stage.rice.fg : "#ffffff"
                                        opacity: topBar.keyOn === "tab" + tabItem.index ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
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
                    spacing: stage.u(14)
                    TopButton { id: searchButton; height: stage.barH; rice: stage.rice; unit: stage.unit; icon: "search"; tip: "Search (just type)"; focused: topBar.keyOn === "search"; onClicked: stage.openSearch("") }
                    TopButton { id: themeButton; height: stage.barH; rice: stage.rice; unit: stage.unit; icon: "palette"; tip: "Theme"; focused: topBar.keyOn === "theme"; lit: stage.theming; onClicked: stage.toggleTheme() }
                    TopButton {
                        id: powerButton
                        height: stage.barH
                        rice: stage.rice; unit: stage.unit
                        icon: "power_settings_new"; tip: "Power"; hotColor: stage.rice.bad
                        focused: topBar.keyOn === "power"
                        onClicked: stage.openPowerHere()
                    }
                    Rectangle { width: 1; height: stage.u(38); anchors.verticalCenter: parent.verticalCenter; color: C.alpha(stage.rice.fg, 0.16) }
                    // the battery saver, while the laptop runs on battery
                    Rectangle {
                        visible: stage.launcher.unplugged || stage.launcher.saverOn
                        anchors.verticalCenter: parent.verticalCenter
                        height: stage.u(56)
                        width: saverRow.implicitWidth + stage.u(36)
                        radius: height / 2
                        color: stage.launcher.saverShown ? C.alpha(stage.rice.green, 0.22) : C.alpha(stage.rice.fg, sm.containsMouse ? 0.14 : 0.08)
                        opacity: stage.launcher.saverBusy ? 0.6 : 1
                        Row {
                            id: saverRow
                            anchors.centerIn: parent
                            spacing: stage.u(7)
                            readonly property real charge: Number(stage.launcher.batt["Percent"]) || 0
                            Text { anchors.verticalCenter: parent.verticalCenter; text: stage.launcher.saverShown ? "eco" : "battery_" + Math.min(6, Math.round(saverRow.charge / 100 * 6)) + "_bar"
                                   color: stage.launcher.saverShown ? stage.rice.green : stage.rice.fg; font.family: Tokens.font.icons; font.pixelSize: stage.u(28) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(saverRow.charge) + "%"; color: stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(20) }
                        }
                        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!stage.launcher.saverBusy) stage.launcher.setSaver(!stage.launcher.saverShown) }
                    }
                    Text {      // (a soft shadow of its own: nothing darkens the top of the page)
                        anchors.verticalCenter: parent.verticalCenter
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.7; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 }
                        text: Qt.formatTime(stage.now, "HH:mm")
                        color: stage.rice.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.Bold
                        font.pixelSize: stage.u(38)
                        font.features: { "tnum": 1 }
                        leftPadding: stage.u(8)
                        rightPadding: stage.u(8)
                    }
                    Rectangle {     // you
                        width: stage.u(60); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: stage.rice.primary }
                            GradientStop { position: 1; color: stage.rice.tertiary }
                        }
                        border.width: 2
                        border.color: C.alpha("#ffffff", 0.18)
                        Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: stage.account.initial; color: stage.rice.onPrimary
                               font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: stage.u(26) }
                        Kirigami.ShadowedImage { id: face; anchors.fill: parent; radius: width / 2; source: stage.account.face; visible: status === Image.Ready; fillMode: Image.PreserveAspectCrop; color: "transparent" }
                    }
                }
            }

            // ---- the hero: the focused item, large (two, cross-faded)
            Item {
                id: heroBox
                x: stage.side
                y: stage.heroTop
                width: Math.min(stage.u(760), stage.width * 0.6)
                height: stage.heroH
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
                        pinned: !th && !!(item && !item.ctl && stage.launcher.isFavorite(item.favId))
                        eyebrow: th ? th.eyebrow : ""
                        primaryText: th ? th.primary : item && item.ctl ? item.name : ""
                        primaryIcon: th ? th.icon : item && item.ctl ? item.icon : ""
                        extraActions: th ? th.extra : []       // (pin and "..." are on the tiles themselves)
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
                y: stage.heroTop + (stage.theming ? 0 : -stage.u(10))
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
                    keyName: (stage.focusRev, stage.theming && stage.pageState().line === "desk") ? stage.deskTargets[stage.pageState().desk] || "" : ""
                    onPicked: name => { tm.target = name }
                }
                Row {
                    id: capRow
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: stage.u(16) }
                    height: stage.u(32)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - allChip.width
                        text: tm.status || ("Editing " + tm.targetLabel)
                        elide: Text.ElideRight
                        color: tm.status ? stage.rice.bad : stage.rice.fgDim
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: stage.u(14.5)
                    }
                    Rectangle {
                        id: allChip
                        anchors.verticalCenter: parent.verticalCenter
                        width: allText.implicitWidth + stage.u(28)
                        height: stage.u(32)
                        radius: height / 2
                        color: tm.target === "all" ? stage.rice.primary : C.alpha(stage.rice.fg, 0.08)
                        Text { id: allText; anchors.centerIn: parent; text: "All screens"; color: tm.target === "all" ? stage.rice.onPrimary : stage.rice.fg
                               font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(14.5) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tm.target = tm.target === "all" ? stage.screenName : "all" }
                        Rectangle {     // the keys' ring
                            anchors.fill: parent
                            anchors.margins: -Math.max(4, stage.u(4))
                            radius: height / 2
                            color: "transparent"
                            border.width: Math.max(2, stage.u(2))
                            border.color: stage.rice.light ? stage.rice.fg : "#ffffff"
                            opacity: (stage.focusRev, stage.theming && stage.pageState().line === "desk" && stage.deskTargets[stage.pageState().desk] === "all") ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                        }
                    }
                }
            }

            // ---- the rows: a row at a time scrolls to the top; the ones above it have gone
            Item {
                id: rowsBox
                x: 0
                y: stage.rowsTop
                width: stage.width
                height: stage.height - stage.rowsTop - stage.u(76)
                clip: true
                // a page taller than the room fades out at the bottom (more below) instead of being cut
                readonly property Item pageNow: (stage.focusRev, pagesRep.count, pagesRep.itemAt(stage.tab))
                readonly property bool overflow: !!pageNow && pageNow.overflow
                readonly property bool scrolled: !!pageNow && pageNow.scrolled      // (rows gone up fade out under the hero)
                layer.enabled: overflow || scrolled
                layer.effect: MultiEffect { maskEnabled: true; maskSource: rowsMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                Item {
                    id: rowsSlide
                    width: parent.width
                    height: parent.height
                    Repeater {
                        id: pagesRep
                        model: 4
                        delegate: Item {
                            id: pg
                            required property int index
                            readonly property var pageObj: stage.pageAt(index)
                            readonly property var st: stage.states[index]
                            property bool made: false           // its rows exist (from the first time it shows on)
                            onVisibleChanged: if (visible) made = true
                            Component.onCompleted: made = visible
                            visible: index === stage.tab
                            width: rowsSlide.width
                            height: rowsSlide.height
                            function rowAt(ri) { return made ? rowsRep.itemAt(ri) : null }
                            // the page scrolls up and down (dragged, by touch or the wheel: the rows no longer move
                            // sideways); the keys keep the focused line in sight (stage.ensureVisible)
                            readonly property bool overflow: flick.contentY + flick.height < flick.contentHeight - 1
                            readonly property bool scrolled: flick.contentY > 1
                            readonly property bool moving: flick.moving || scrollAnim.running
                            function rowTop(ri) { let y = 0; for (let k = 0; k < ri; k++) { const r = rowsRep.itemAt(k); if (r) y += r.implicitHeight } return y }
                            function scrollToY(y, animate) {
                                const t = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), y))
                                scrollAnim.stop()
                                if (animate && Math.abs(t - flick.contentY) > 0.5) { scrollAnim.from = flick.contentY; scrollAnim.to = t; scrollAnim.start() }
                                else flick.contentY = t
                            }
                            function scrollTo(animate) { stage.ensureVisible(animate) }
                            function scrollBy(dy) { scrollAnim.stop(); scrollToY(flick.contentY + dy, false) }
                            readonly property real contentY: flick.contentY
                            NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: Math.round(stage.focusMs * 1.45); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove }
                            Flickable {
                                id: flick
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: col.height + stage.u(24)
                                flickableDirection: Flickable.VerticalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                pressDelay: 0
                                onMovementStarted: { scrollAnim.stop(); stage.quietUntil = Date.now() + 200 }
                                onMovementEnded: if (Shell.debug) console.warn("ATOM page dragged to", Math.round(contentY))
                                MouseArea {     // the bare page between the rows: a click there closes it (as the backdrop's)
                                    width: flick.width
                                    height: Math.max(flick.height, flick.contentHeight)
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    property point at
                                    onPressed: mouse => at = Qt.point(mouse.x, mouse.y)
                                    onClicked: mouse => {
                                        if (flick.moving || Math.hypot(mouse.x - at.x, mouse.y - at.y) > 12) return
                                        if (stage.launcher.view === "walls") stage.launcher.view = "apps"; else stage.launcher.close()
                                    }
                                }
                            Column {
                                id: col
                                width: parent.width
                                Repeater {
                                    id: rowsRep
                                    // by count, so a page rebuilt with the same rows (a theme applied, the data
                                    // refreshed) keeps its rows and only rebinds them: nothing flashes
                                    model: pg.made ? pg.pageObj.rows.length : 0
                                    delegate: HomeRow {
                                        required property int index
                                        readonly property var entry: pg.pageObj.rows[index] || ({ id: "", title: "", shape: "square", items: [], divider: -1 })
                                        width: col.width
                                        row: entry
                                        rice: stage.rice
                                        unit: stage.unit
                                        side: stage.side
                                        focusMs: stage.focusMs
                                        current: (stage.focusRev, pg.st.idx[entry.id] ?? 0)
                                        active: (stage.focusRev, index === pg.st.row)
                                        z: active ? 1 : 0
                                        lines: (stage.focusRev, pg.st.lines[entry.id] ?? 1)
                                        groupOpen: !!stage.groupsOpen[entry.group]
                                        tilesFocused: (stage.focusRev, (pg.st.line || "tiles") === "tiles")
                                        toolFocus: (stage.focusRev, index === pg.st.row && pg.st.line === "tools") ? pg.st.tool : -1
                                        onToolActivated: id => stage.toolDo(id)
                                        pointerMode: stage.pointerMode
                                        isPinned: it => !!it.favId && stage.launcher.isFavorite(it.favId)
                                        onPinToggle: i => { const it = entryAt(i); if (it && it.favId) { if (Shell.debug) console.warn("ATOM home pin", it.favId); stage.launcher.toggleFavorite(it.favId) } }
                                        onPointed: (i, at) => stage.pointed(index, i, at)
                                        onPointerOut: i => stage.unpointed(index, i)
                                        onActivated: (i, tile) => { stage.focusAt(index, i, "mouse"); stage.activateItem(entryAt(i), tile, index) }
                                        onMenu: (i, tile) => stage.itemMenu(entryAt(i), tile)
                                        Component.onCompleted: Qt.callLater(() => { if (index === pg.st.row) pg.scrollTo(false) })
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }

            // ---- the wheel, anywhere on the home: up and down walks the rows, sideways (or with Shift) moves
            // the row under the pointer. A layer over everything that takes only the wheel (a scrolling row
            // would otherwise keep it: a Flickable sees its children's wheel first)
            Item {
                id: wheelLayer
                anchors.fill: parent
                z: 50
                WheelHandler {
                    id: wheelAll
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: ev => stage.onWheel(ev, wheelAll.point.position)
                }
            }

            // ---- the keys, quietly (a controller's buttons once it's the one in use)
            Row {
                x: stage.side
                anchors.bottom: parent.bottom
                anchors.bottomMargin: stage.u(26)
                spacing: stage.u(24)
                opacity: stage.topO * (stage.pointerMode ? 0 : 1)       // the pointer in use: they'd only be in the way
                Behavior on opacity { enabled: stage.phase === "open"; NumberAnimation { duration: Tokens.ms(300) } }
                Repeater {
                    model: Gamepad.inUse ? (stage.theming ? [["✥", "Move"], ["A", "Apply"], ["X", "Options"], ["Y", "Home"], ["B", "Back"]]
                                                          : [["✥", "Move"], ["A", "Open"], ["X", "Options"], ["LB  RB", "Switch"], ["Y", "Theme"], ["B", "Close"]])
                         : stage.theming ? [["←→↑↓", "Move"], ["Enter", "Apply"], ["Esc", "Back"]]
                                         : [["←→↑↓", "Move"], ["Enter", "Open"], ["Tab", "Switch"], ["Type", "Search"], ["Esc", "Close"]]
                    Row {
                        required property var modelData
                        spacing: stage.u(7)
                        readonly property bool face: modelData[0].length === 1      // a pad's round face button
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(stage.u(26), kt.implicitWidth + stage.u(14))
                            height: stage.u(26)
                            radius: parent.face ? height / 2 : stage.u(7)
                            color: "transparent"
                            border.width: 1
                            border.color: C.alpha(stage.rice.fg, 0.22)
                            Text { id: kt; anchors.centerIn: parent; text: modelData[0]; color: stage.rice.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: stage.u(13) }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: stage.rice.muted; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: stage.u(14.5) }
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
                if (stage.finder) { const t = to; return Qt.rect(t.x + t.width * 0.08, t.y - stage.u(10), t.width * 0.84, t.height) }
                const p = searchButton.mapToItem(searchLayer, 0, 0)
                return Qt.rect(p.x, p.y, searchButton.width, searchButton.height)
            }
            readonly property rect to: {
                const w = Math.min(stage.u(760), stage.width * 0.62), h = stage.u(60)
                return Qt.rect((stage.width - w) / 2, stage.u(30) + stage.u(23) - h / 2, w, h)
            }
            MouseArea { anchors.fill: parent; enabled: stage.searchOpen; onClicked: stage.closeSearch() }
            // the finder's card: the field and the results on one glass plate, blurred behind (only the
            // plate: the screen around it stays as it is). It's the field's size until results come, then
            // grows with them.
            RectangularShadow {
                anchors.fill: finderCard
                visible: finderCard.visible
                opacity: finderCard.opacity
                radius: finderCard.radius; blur: stage.u(44); offset.y: stage.u(16); spread: -stage.u(10)
                color: Qt.rgba(0, 0, 0, 0.5)
            }
            Rectangle {
                id: finderCard
                visible: stage.finder && stage.searchP > 0.001
                opacity: Math.min(1, stage.searchP * 1.6)
                readonly property real pad: stage.u(18)
                readonly property real k: results.contentH > 0 ? results.opacity : 0      // the results' share
                property real resB: results.y + results.height      // (results coming in stretch it smoothly)
                Behavior on resB { NumberAnimation { duration: Tokens.ms(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                x: Math.min(field.x, M.lerp(field.x, results.x, k)) - pad
                y: field.y - pad
                width: Math.max(field.x + field.width, M.lerp(field.x + field.width, results.x + results.width, k)) + pad - x
                height: Math.max(field.y + field.height, M.lerp(field.y + field.height, resB, k)) + pad - y
                radius: Math.min(stage.u(34), height / 2)
                color: C.alpha(stage.rice.surfaceLowest, 0.82)
                border.width: 1
                border.color: C.alpha(stage.rice.edge, 0.14)
                MouseArea { anchors.fill: parent }     // a click on the plate isn't a click outside
            }

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
                // the finder's results take what they need (at most the rest of the screen)
                height: stage.finder ? Math.min(stage.height - y - stage.u(50), Math.max(stage.u(120), contentH))
                                     : stage.height - y - stage.u(50)
                launcher: stage.launcher
                rice: stage.rice
                unit: stage.unit
                opacity: stage.launcher.query !== "" ? M.clamp((stage.searchP - 0.3) / 0.7) : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Tokens.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            }
        }

        // ---- the Theme page's editors, at their tiles (an accent's colour; naming a look)
        AccentEditor {
            id: accentEd
            anchors.fill: parent
            z: 60
            rice: stage.rice
            model: tm
            unit: stage.unit
            onClosed: { focus = false; keys.forceActiveFocus() }      // (a FocusScope remembers its focused child)
        }
        NamingCard {
            id: naming
            anchors.fill: parent
            z: 60
            rice: stage.rice
            model: tm
            unit: stage.unit
            onClosed: { focus = false; keys.forceActiveFocus() }      // (a FocusScope remembers its focused child)
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
        // only what Enter (or a click on the tile) does: every other setting sits in its row's header, the
        // screens in the desk map (nothing here for the pointer to travel to across the other rows)
        const busy = tm.busy === it.key
        const n = tm.page ? tm.page.walls.length : 0
        const t = {
            wall: { eyebrow: "Wallpaper · " + it.n + " of " + n, primary: "Set on " + tm.targetLabel, icon: "wallpaper" },
            look: { eyebrow: "Theme", primary: "Load theme", icon: "style" },
            save: { eyebrow: "Theme", primary: "Save as…", icon: "bookmark_add" },
            "colours-auto": { eyebrow: "Colours", primary: "Use automatic", icon: "auto_awesome" },
            mood: { eyebrow: "Mood", primary: "Use " + String(it.name).toLowerCase(), icon: "palette" },
            accent: String(it.role).startsWith("kb:") ? { eyebrow: "Keyboard lighting", primary: "Pick its colour", icon: "colorize" }
                    : { eyebrow: "Accent · " + it.role, primary: "Edit colour", icon: "colorize" },
            size: { eyebrow: "Desktop size", primary: "Use this size", icon: "format_size" },
            lsize: { eyebrow: "Launcher size", primary: "Use this size", icon: "fit_screen" },
            blur: { eyebrow: "Blur style", primary: "Use this style", icon: "blur_on" },
            barstyle: { eyebrow: "Taskbar islands", primary: "Use this style", icon: "dock_to_bottom" },
            kb: { eyebrow: "Keyboard lighting", primary: it.dev === "laptop" ? "Use on the laptop" : "Use on this keyboard", icon: "keyboard" },
            group: { eyebrow: "Settings", primary: groupsOpen[it.group] ? "Collapse" : "Expand", icon: groupsOpen[it.group] ? "expand_less" : "expand_more" },
            light: { eyebrow: "Lighting", primary: "Use on both keyboards", icon: "keyboard" },
        }[it.kind]
        t.extra = []
        if (busy) t.primary = "Applying…"
        return t
    }
    function themeExtra(id) {
        if (id === "all") { tm.target = tm.target === "all" ? screenName : "all"; return }
        if (id.startsWith("fine:")) launcher.openWallpapers("desktop", id.slice(5))
    }
    // the Menu key, a right click, a pad's X: an app's menu (pin, its actions), a theme's (load, update, delete)
    function itemMenu(it, tile) {
        if (!it || !tile) return
        if (Shell.debug) console.warn("ATOM home menu", it.name || it.key)
        if (it.model) { launcher.menu.openFor(tile, it.model, it.row); return }
        if (it.kind === "look") { lookMenu.it = it; lookMenu.visualParent = tile; lookMenu.open(0, tile.height + u(10)) }     // (under it)
        else if (it.kind === "accent") accentEd.openFor(it, tile)
    }
    PlasmaExtras.Menu {
        id: lookMenu
        property var it: null
        PlasmaExtras.MenuItem { text: "Load"; icon: "view-refresh"; onClicked: if (lookMenu.it) tm.apply(lookMenu.it) }
        PlasmaExtras.MenuItem { text: "Save the current look over it"; icon: "document-save"; onClicked: if (lookMenu.it) tm.savePreset(lookMenu.it.name) }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem { text: "Delete"; icon: "edit-delete"; onClicked: if (lookMenu.it) tm.deletePreset(lookMenu.it.name) }
    }
    // Enter, a click or the bright pill: a Theme item applies (or opens the panel it needs), anything else launches
    function activateItem(it, tile, ri) {
        if (!it) return
        if (it.ctl === "group") { toggleGroup(it.group); return }
        if (it.ctl) { rowControl(ri === undefined ? pageState().row : ri, it.ctl, ri === undefined ? "key" : "mouse"); return }
        if (!it.kind) { launchItem(it, tile); return }
        if (it.kind === "save") naming.openAt(tile, tm.suggestName())
        else if (it.kind === "accent") accentEd.openFor(it, tile)
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
        if (finder) { launcher.close(); return }    // the finder is only the search
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
        if (powerOver) { event.accepted = true; return }       // (the power page has the keys)
        pointerMode = false                                 // the keys (or a pad) in use: the pointer's hover goes
        if (!Gamepad.sending) Gamepad.inUse = false         // the keyboard again: its keys in the hints
        if (launcher.view === "walls") return
        const k = event.key
        if (k === Qt.Key_Escape) { if (searchOpen) closeSearch(); else if (theming) setTab(tabBefore); else launcher.close(); event.accepted = true; return }
        if (k === Qt.Key_Tab) { setTab(theming ? tabBefore : tab + 1); event.accepted = true; return }
        if (k === Qt.Key_Backtab) { setTab(theming ? tabBefore : tab - 1); event.accepted = true; return }
        if (k === Qt.Key_Left) { step(-1, 0); event.accepted = true; return }
        if (k === Qt.Key_Right) { step(1, 0); event.accepted = true; return }
        if (k === Qt.Key_Up) { step(0, -1); event.accepted = true; return }
        if (k === Qt.Key_Down) { step(0, 1); event.accepted = true; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (pageState().line === "top") topEnter(); else if (theming) themeEnter(); else activateItem(currentItem, currentTile()); event.accepted = true; return }
        if (k === Qt.Key_Menu) { itemMenu(currentItem, currentTile()); event.accepted = true; return }
        if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_F) { openSearch(""); event.accepted = true; return }
        if (event.text && event.text.trim() && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            openSearch(event.text === "/" ? "" : event.text)
            event.accepted = true
        }
    }

    // the controller's buttons with no key of their own (Atom.Native Gamepad: the rest arrive as keys)
    Connections {
        target: Gamepad
        enabled: stage.wanted && stage.phase === "open"
        function onButton(name) {
            if (name === "north" && stage.launcher.view !== "walls" && !stage.searchOpen) stage.toggleTheme()
        }
    }
    Connections { target: stage.launcher; function onViewChanged() { if (Shell.debug) console.warn("ATOM stage view", stage.launcher.view) } }
    property date now: new Date()
    Timer { running: stage.phase !== "closed"; repeat: true; interval: 10000; triggeredOnStart: true; onTriggered: stage.now = new Date() }
}
