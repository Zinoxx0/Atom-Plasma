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
import "theme"         // ThemeStudio: the Theme page, the same in every launcher style

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
    readonly property bool following: stage.wanted && !stage.powerOver && (stage.phase === "opening" || stage.phase === "open")
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
        if (!name || !wanted || phase === "closing") return
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
    readonly property Item searchButton: topBar.searchButton     // (where the search field grows from: StageSearch)
    readonly property real topGap: strip && screenObj ? Math.max(0, Math.round(strip.y + strip.height - screenObj.virtualY)) : 0


    // ------------------------------------------------------------------ the data and the focus
    HomeModel { id: hm; launcher: stage.launcher }
    ThemeModel { id: tm; launcher: stage.launcher; rice: stage.rice; screenName: stage.screenName }
    readonly property int themeTab: 3
    property int tab: 0                         // 0 Home, 1 Games, 2 Apps, 3 the Theme page (no tab: the palette)
    property int tabBefore: 0                   // where the Theme page goes back to
    // the Theme page is ThemeStudio (theme/): the same page in every launcher style (the user, 2026-11-21), with its
    // own focus; this stage gives it the keys (onKey), the wheel, the pad's Y, and wears what it previews
    // (studioPreview: the room's picture and the palette it draws with, lookPal)
    property var previewValues: null
    RicePalette { id: lookPal; given: true; values: stage.previewValues || stage.rice.values }
    readonly property Item studio: studioLoader.item
    readonly property var emptyPage: ({ id: "", rows: [] })
    function pageAt(p) { return p === themeTab ? emptyPage : hm.pages[p] || emptyPage }
    readonly property var page: pageAt(tab)
    readonly property bool theming: tab === themeTab
    // per page: the active row, the row at the top, each row's focus (by row id)
    // (the Theme page: line "top" while the keys are on the top bar, "studio" while ThemeStudio has them)
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
            if (dy > 0) { if (theming) setLine("studio"); else setLine("tiles") }
            else if (dx) setLine("top", undefined, Math.max(0, Math.min(topItems.length - 1, st.top + dx)))
            return
        }
        if (theming) return         // (ThemeStudio walks its own: onKey hands it the keys first)
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
    // the top bar's parts the keys walk (Up from the first row; up past the Theme page's top)
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
        const p = topBar.powerButton.mapToGlobal(0, 0)
        launcher.openPower({ x: p.x, y: p.y, width: topBar.powerButton.width, height: topBar.powerButton.height })
    }
    function toggleTheme() { setTab(theming ? tabBefore : themeTab) }
    function setLine(line, ri, extra) {
        const st = pageState()
        st.line = line
        if (extra !== undefined && line === "top") st.top = extra
        if (ri !== undefined && ri !== st.row) { const r = rowObj(ri); focusAt(ri, idxOf(r.id), "key") }
        else { quietUntil = Date.now() + focusMs * 1.5 + 80; focusRev++; if (!theming) ensureVisible(true) }
        if (Shell.debug) { console.warn("ATOM home line", line, line === "top" ? "top " + topItems[st.top] : ""); logFocus() }
    }
    // Meta+Shift+W: the Theme page, at a section (walls, colours or lights)
    property string themeAt: ""
    function openTheme(rowId) {
        if (!theming) { themeAt = rowId || ""; setTab(themeTab) }
        else if (studio) studio.openSection(rowId)
    }
    Connections { target: stage.launcher; function onThemeAskChanged() { stage.openTheme(stage.launcher.themeRow) } }
    function logFocus(from) {
        const it = currentItem
        console.warn("ATOM home tab", tab, "row", pageState().row, "item", it ? (it.name || it.key || "") : "-", from ? "(" + from + ")" : "")
        focusLog.restart()          // where the focused tile is, once the page has stopped scrolling (the tests use it)
    }
    Timer { id: focusLog; interval: Math.round(stage.focusMs * 1.6) + 120
            onTriggered: { const t = stage.currentTile(); if (t) { const p = t.mapToItem(null, t.width / 2, t.height / 2); console.warn("ATOM home focus at", Math.round(stage.screenObj.virtualX + p.x), Math.round(stage.screenObj.virtualY + stage.topGap + p.y)) } } }
    function logLayout() {
        const t = currentTile()
        if (t) { const p = t.mapToItem(null, t.width / 2, t.height / 2); console.warn("ATOM home focus at", Math.round(screenObj.virtualX + p.x), Math.round(screenObj.virtualY + topGap + p.y)) }
        const tabsP = topBar.tabStrip.mapToItem(null, 0, 0)
        const at = b => { const q = b.mapToItem(null, b.width / 2, b.height / 2); return Math.round(screenObj.virtualX + q.x) + " " + Math.round(screenObj.virtualY + topGap + q.y) }
        console.warn("ATOM home tabs at", Math.round(screenObj.virtualX + tabsP.x), Math.round(screenObj.virtualY + topGap + tabsP.y), "search at", at(topBar.searchButton), "theme at", at(topBar.themeButton), "power at", at(topBar.powerButton))
    }
    function setTab(i) {
        if (i !== themeTab) i = (i + 3) % 3
        if (i === tab) return
        if (i === themeTab) {       // the Theme page opens fresh, its keys in it (ThemeStudio)
            tabBefore = tab
            const ss = states.slice(); ss[themeTab] = freshStates()[themeTab]; ss[themeTab].line = "studio"; states = ss
            focusRev++
        }
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
    // a click on bare space (the backdrop, the page between the rows): the right button closes the launcher; the
    // left one never does (the user, 2026-11-15: a missed tile closing it was annoying)
    function bareClick(button) {
        if (Shell.debug) console.warn("ATOM stage bare click", button === Qt.RightButton ? "right" : "left")
        if (button === Qt.RightButton) launcher.close()
    }
    // the wheel (and a touchpad) scrolls the page, as a page; the keys and the pad walk the focus
    function onWheel(ev, pos) {
        if (theming) { if (studio) studio.wheel(ev.pixelDelta.y || ev.angleDelta.y / 120 * u(110)); return }
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
            room.shown = null
            room.show(it)
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
    StageRoom {
        id: room
        anchors.fill: parent
        stage: stage
        style: backdropStyle
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

    // the finder's plate is blurred behind (KWin), through the backdrop's blur (one region per window)
    readonly property var finderShapes: {
        if (!searchLayer.finderCard.visible || searchLayer.finderCard.opacity < 0.5) return []
        searchLayer.finderCard.x; searchLayer.finderCard.y; searchLayer.finderCard.width; searchLayer.finderCard.height          // (mapToItem alone doesn't follow them)
        const p = searchLayer.finderCard.mapToItem(null, 0, 0)
        return [{ x: p.x, y: p.y, width: searchLayer.finderCard.width, height: searchLayer.finderCard.height, radius: searchLayer.finderCard.radius }]
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
        const it = room.shown
        const careful = { top: 0.6, hero: 0.6, rows: 0.6 }
        if (theming) return careful
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
    Timer { id: bgDelay; interval: 110; onTriggered: room.show(stage.currentItem) }
    onCurrentItemChanged: { if (phase === "closed") return; heroShow(currentItem); bgDelay.restart() }
    function paperOf(it) {
        if (it.kind === "wall") return { thumb: it.thumb, image: it.path }
        const here = tm.screens.find(s => s.name === screenName)
        return here ? { thumb: here.thumb, image: here.image } : { thumb: "", image: rice.wallpaper }
    }

    // the Theme page's preview: the room shows that wallpaper (else the screen's own), the page wears its palette
    function studioPreview(values, image, thumb) {
        previewValues = values
        if (phase === "closed") return
        room.show(image ? { kind: "wall", thumb: thumb, path: image } : { kind: "screen" })
    }

    // ------------------------------------------------------------------ the top's gradient (2026-11-16, the user: "a
    // basic tasteful dark gradient" behind the top bar): from the top edge, in the backdrop's deepest colour (so light
    // on a light theme), under everything of the content; not in the finder (it's over the windows)
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: stage.u(250)
        visible: !stage.finder && opacity > 0.01
        opacity: stage.topO * (1 - stage.coverP)
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(stage.rice.surfaceLowest, 0.78) }
            GradientStop { position: 0.45; color: C.alpha(stage.rice.surfaceLowest, 0.38) }
            GradientStop { position: 1; color: C.alpha(stage.rice.surfaceLowest, 0) }
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

        MouseArea {     // bare backdrop: a right click closes it (a click: not a drag or a swipe that ended here)
            anchors.fill: parent
            enabled: stage.phase === "open" && !stage.searchOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property point at
            onPressed: mouse => at = Qt.point(mouse.x, mouse.y)
            onClicked: mouse => { if (Math.hypot(mouse.x - at.x, mouse.y - at.y) <= 12) stage.bareClick(mouse.button) }
        }

        Item {
            id: plane
            anchors.fill: parent
            // the search takes the whole room: the page under it goes (only the frosted backdrop stays)
            opacity: stage.planeO * (stage.searchOpen ? 1 - stage.searchP : 1) * (1 - stage.coverP)
            visible: opacity > 0.01
            scale: stage.planeS * M.lerp(1, 0.965, stage.coverP)
            Behavior on opacity { enabled: stage.phase === "open" && !coverAnim.running; NumberAnimation { duration: Tokens.base } }

            // ---- the top bar: the jewel (the logo: Home), the pages on their track, then search, theme, power,
            // the time and you. One control height (barH), a third bigger than a window's; the keys reach it
            // too (up from the first row: the "top" line), so every part has a focus ring as well as a hover
            StageTopBar {
                id: topBar
                stage: stage
            }

            // ---- the hero: the focused item, large (two, cross-faded)
            Item {
                id: heroBox
                x: stage.side
                y: stage.heroTop
                width: Math.min(stage.u(760), stage.width * 0.6)
                height: stage.heroH
                opacity: stage.heroO * (stage.theming ? 0 : 1)
                visible: opacity > 0.01
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
                        pinned: !!(item && !item.ctl && stage.launcher.isFavorite(item.favId))
                        primaryText: item && item.ctl ? item.name : ""
                        primaryIcon: item && item.ctl ? item.icon : ""
                        opacity: stage.heroO2[index]
                        transform: Translate { x: stage.heroX[index] }
                        onPrimary: stage.heroPrimary()
                        onPin: if (stage.currentItem) stage.launcher.toggleFavorite(stage.currentItem.favId)
                        onMore: from => { const t = stage.currentTile(); if (t && stage.currentItem) stage.launcher.menu.openFor(t, stage.currentItem.model, stage.currentItem.row) }
                    }
                }
            }

            // ---- the Theme page: ThemeStudio, made when it shows (it fades and slides with the tab swap)
            Loader {
                id: studioLoader
                anchors.fill: parent
                active: stage.theming
                opacity: rowsBox.opacity
                transform: Translate { x: rowsSlide.x }
                onLoaded: if (stage.themeAt) { const r = stage.themeAt; stage.themeAt = ""; Qt.callLater(() => item.openSection(r)) }
                sourceComponent: ThemeStudio {
                    launcher: stage.launcher
                    model: tm
                    rice: stage.rice
                    look: lookPal
                    screenName: stage.screenName
                    unit: stage.unit
                    topInset: stage.u(92) + stage.unit * 46 / 0.836
                    active: (stage.focusRev, stage.states[stage.themeTab].line !== "top")
                    veil: 0.34
                    origin: Qt.point(stage.screenObj ? stage.screenObj.virtualX : 0, (stage.screenObj ? stage.screenObj.virtualY : 0) + stage.topGap)
                    onPreview: (values, image, thumb) => stage.studioPreview(values, image, thumb)
                    onLeave: stage.setLine("top", undefined, stage.topItems.indexOf("theme"))
                    onGiveKeys: keys.forceActiveFocus()
                    Component.onDestruction: stage.studioPreview(null, "", "")
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
                            // (never the Theme page's: ThemeStudio is that page, and this one's bare Flickable and its
                            // click catcher sat over it and ate every click and hover below the hero's line)
                            visible: index === stage.tab && index !== stage.themeTab
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
                                MouseArea {     // the bare page between the rows: as the backdrop (stage.bareClick)
                                    width: flick.width
                                    height: Math.max(flick.height, flick.contentHeight)
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    property point at
                                    onPressed: mouse => at = Qt.point(mouse.x, mouse.y)
                                    onClicked: mouse => { if (!flick.moving && Math.hypot(mouse.x - at.x, mouse.y - at.y) <= 12) stage.bareClick(mouse.button) }
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
                                        tilesFocused: (stage.focusRev, (pg.st.line || "tiles") === "tiles")
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
                opacity: stage.topO * (stage.pointerMode || stage.theming ? 0 : 1)       // the pointer in use: they'd only be in the way (the Theme page has its own)
                Behavior on opacity { enabled: stage.phase === "open"; NumberAnimation { duration: Tokens.ms(300) } }
                Repeater {
                    model: Gamepad.inUse ? [["✥", "Move"], ["A", "Open"], ["X", "Options"], ["LB  RB", "Switch"], ["Y", "Theme"], ["B", "Close"]]
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
        StageSearch {
            id: searchLayer
            stage: stage
        }


    }

    // ------------------------------------------------------------------ the hero follows the focus (cross-fade)
    property var heroItems: [null, null]
    property var heroO2: [0, 0]
    property var heroX: [0, 0]
    property int heroSlot: 0
    function heroShow(it) {
        if (!it || heroItems[heroSlot] === it) return
        const was = heroItems[heroSlot]
        if (was && it.key && was.key === it.key && !heroFade.running) {     // (the same item, rebuilt: no cross-fade)
            const items = heroItems.slice(); items[heroSlot] = it; heroItems = items
            return
        }
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
    LaunchFlight {
        id: launchFly
        stage: stage
    }
    // the Menu key, a right click, a pad's X: an app's menu (pin, its actions), a theme's (load, update, delete)
    function itemMenu(it, tile) {
        if (!it || !tile) return
        if (Shell.debug) console.warn("ATOM home menu", it.name || it.key)
        if (it.model) launcher.menu.openFor(tile, it.model, it.row)
    }
    // the hero's bright pill: what Enter does
    function heroPrimary() { activateItem(currentItem, currentTile()) }
    // Enter, a click or the bright pill: a row's control ("Show more"), or the item launches
    function activateItem(it, tile, ri) {
        if (!it) return
        if (it.ctl) { rowControl(ri === undefined ? pageState().row : ri, it.ctl, ri === undefined ? "key" : "mouse"); return }
        launchItem(it, tile)
    }
    function launchItem(it, tile) {
        if (!it || (phase !== "open" && phase !== "opening")) return
        const r = tile ? tile.mapToItem(null, 0, 0, tile.width, tile.height) : Qt.rect(width / 2 - u(60), height / 2 - u(60), u(120), u(120))
        launchFly.fly(it, r)
        it.model.trigger(it.row, "", null)
        if (Shell.debug) console.warn("ATOM home launch", it.name)
    }

    // ------------------------------------------------------------------ search
    property bool searchOpen: false
    property real searchP: 0
    Behavior on searchP { NumberAnimation { duration: Math.max(Tokens.ms(360), Math.round(stage.focusMs * 1.3)); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    function openSearch(text) {
        if (Shell.debug) console.warn("ATOM home search", JSON.stringify(text))
        if (!searchOpen) { searchOpen = true; searchP = 1 }
        searchLayer.query.text = text || ""
        searchLayer.query.cursorPosition = searchLayer.query.text.length
        searchLayer.query.forceActiveFocus()
    }
    function closeSearch() {
        if (finder) { launcher.close(); return }    // the finder is only the search
        if (!searchOpen) return
        searchOpen = false
        searchP = 0
        searchLayer.query.text = ""
        searchLayer.query.focus = false
        keys.forceActiveFocus()
    }
    function onSearchKey(event) {
        const L = launcher
        if (event.key === Qt.Key_Escape) { if (searchLayer.query.text) searchLayer.query.text = ""; else closeSearch(); event.accepted = true }
        else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) { L.moveSelection(1); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { L.moveSelection(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (L.query) L.activateSelection(); event.accepted = true }
    }

    // ------------------------------------------------------------------ keys
    function onKey(event) {
        if (powerOver) { event.accepted = true; return }       // (the power page has the keys)
        pointerMode = false                                 // the keys (or a pad) in use: the pointer's hover goes
        if (!Gamepad.sending) Gamepad.inUse = false         // the keyboard again: its keys in the hints
        const k = event.key
        if (theming && !searchOpen && pageState().line !== "top" && studio && studio.key(event)) { event.accepted = true; return }
        if (k === Qt.Key_Escape) { if (searchOpen) closeSearch(); else if (theming) setTab(tabBefore); else launcher.close(); event.accepted = true; return }
        if (k === Qt.Key_Tab) { setTab(theming ? tabBefore : tab + 1); event.accepted = true; return }
        if (k === Qt.Key_Backtab) { setTab(theming ? tabBefore : tab - 1); event.accepted = true; return }
        if (k === Qt.Key_Left) { step(-1, 0); event.accepted = true; return }
        if (k === Qt.Key_Right) { step(1, 0); event.accepted = true; return }
        if (k === Qt.Key_Up) { step(0, -1); event.accepted = true; return }
        if (k === Qt.Key_Down) { step(0, 1); event.accepted = true; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (pageState().line === "top") topEnter(); else if (!theming) activateItem(currentItem, currentTile()); event.accepted = true; return }
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
            if (name !== "north" || stage.searchOpen) return
            if (stage.theming && stage.studio && stage.studio.north()) return       // (the Theme page's Y: shuffle)
            stage.toggleTheme()
        }
    }
    property date now: new Date()
    Timer { running: stage.phase !== "closed"; repeat: true; interval: 10000; triggeredOnStart: true; onTriggered: stage.now = new Date() }
}
