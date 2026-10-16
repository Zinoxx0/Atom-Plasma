import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasma5support as P5Support
import org.kde.layershell as LayerShell
import "Rice"
import "Rice/Color.js" as C

// Glimpse: the bar keeps only launchers (lit when the app runs anywhere); every open window,
// from every screen, lives in a slim band along the top edge of each screen, corner to corner,
// that looks like part of the display's bezel. On hover it opens: one icon per app (several windows
// stack behind it), live thumbnails of the hovered app's windows under it, media on the right.
// One instance per bar; each instance owns the band, the opened band ("shelf") and the
// fullscreen edge of its own screen.
// Clicking a window: minimized -> restore here, on another screen -> slide here,
// here and focused -> minimize, here -> focus. Clicking an app icon does that to the app's most
// relevant window (see pickWindow). Middle-click: a new window of that app (on a thumbnail: close it).
PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    fullRepresentation: BarLaunchers { g: root }

    readonly property var cfg: Plasmoid.configuration

    // ------------------------------------------------------------------ palette and sizes
    // this screen's wallpaper palette (rice.py), which also names the pre-blurred wallpaper band
    // used as the glass backdrop
    RicePalette { id: ricePal; output: root.screenName }
    readonly property alias pal: ricePal
    readonly property real uiScale: pal.uiScale        // bar widgets (rice settings "bar_scale")
    readonly property real topScale: pal.topScale      // the top band (rice settings "top_scale")
    function px(v) { return Math.round(v * topScale) }

    readonly property int stripHeight: Math.round(cfg.stripHeight * topScale)
    readonly property int barH: 44                     // the opened band: fixed, only its contents scale
    readonly property int iconSize: Math.min(px(28), barH - 10)
    readonly property int slot: iconSize + px(16)
    readonly property int fillet: 14                   // the rounded "screen corners" under the band
    readonly property int tabH: px(22)                 // the label tab that drips from the lip
    readonly property int leftPad: fillet + 6
    // room the shelf leaves for the icons (screen width minus the media module): slots shrink to fit
    property real iconRoom: 0
    readonly property int appCount: {
        let n = 0
        for (const g of groups) n += g.apps.count
        return n
    }
    readonly property int fitSlot: iconRoom > 0 && appCount > 0
        ? Math.max(iconSize + px(4), Math.min(slot, Math.floor(iconRoom / appCount))) : slot

    readonly property color cDeep: pal.surfaceLowest
    readonly property color cFg: pal.fg
    readonly property color cFgDim: pal.fgDim
    readonly property color cPrimary: pal.primary
    readonly property color cOnPrimary: pal.onPrimary
    readonly property color cTertiary: pal.tertiary
    readonly property color cRed: pal.red
    readonly property url glassUrl: pal.values._glass ? "file://" + pal.values._glass : ""
    readonly property int glassBand: pal.values._glassBand || 160
    // the glass colour wash: accent on the left, deep in the middle (icons stay legible), tertiary
    // right. Light, so the backdrop reads as glass rather than paint.
    readonly property color washA: C.alpha(cPrimary, 0.30)
    readonly property color washB: C.alpha(cDeep, 0.40)
    readonly property color washC: C.alpha(cTertiary, 0.26)
    // the bezel: near black, with a hint of the palette so it isn't dead flat
    readonly property color cBezel: Qt.rgba(cDeep.r * 0.35, cDeep.g * 0.35, cDeep.b * 0.35, 1)

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.endsWith("#outputs")) {
                try {
                    const map = {}
                    for (const o of JSON.parse(data["stdout"]).outputs)
                        if (o.enabled) map[o.name] = { h: o.size.height, scale: o.scale || 1 }
                    root.outputs = map
                } catch (e) {}
            } else if (data["exit code"]) {
                console.warn("glimpse:", source, data["stderr"])
            }
            disconnectSource(source)
        }
    }
    // real resolution and scale of each output (Qt reports the scale rounded up, 2 for 1.25 and 1.7)
    property var outputs: ({})
    function readOutputs() { sh.connectSource("kscreen-doctor -j #outputs") }
    onScreensChanged: readOutputs()
    Component.onCompleted: readOutputs()
    readonly property real dpr: outputs[screenName] ? outputs[screenName].scale : 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    // ------------------------------------------------------------------ screens
    readonly property var screens: Array.prototype.slice.call(Qt.application.screens)
        .sort((a, b) => a.virtualX - b.virtualX || a.virtualY - b.virtualY)
    // until the item sits in its panel window, Screen.name reports the primary screen
    readonly property var myScreen: root.Window.window ? (screens.find(s => s.name === Screen.name) ?? null) : null
    readonly property string screenName: myScreen ? myScreen.name : ""
    readonly property rect myGeometry: myScreen ? Qt.rect(myScreen.virtualX, myScreen.virtualY, myScreen.width, myScreen.height)
                                                : Qt.rect(0, 0, 0, 0)
    function sameRect(a, b) {
        return !!a && !!b && Math.abs(a.x - b.x) < 2 && Math.abs(a.y - b.y) < 2
            && Math.abs(a.width - b.width) < 2 && Math.abs(a.height - b.height) < 2
    }
    function isMine(geo) { return sameRect(geo, myGeometry) }
    onMyGeometryChanged: scheduleScan()
    function screenFor(geo) {
        return screens.find(s => sameRect(geo, Qt.rect(s.virtualX, s.virtualY, s.width, s.height))) ?? null
    }
    function isLaptop(s) { return !!s && /^(eDP|LVDS|DSI)/.test(s.name) }
    function modeHeight(s) { return outputs[s.name] ? outputs[s.name].h : Math.round(s.height * s.devicePixelRatio) }
    // a screen in a word, for tags: Laptop / 4K / 1440p
    function screenLabel(s) {
        if (!s) return ""
        if (isLaptop(s)) return i18n("Laptop")
        const h = modeHeight(s)
        return h >= 2160 ? "4K" : h + "p"
    }
    // ...and in two characters, for the tag on an icon (the laptop gets a glyph instead)
    function screenShort(s) {
        if (!s) return ""
        const h = modeHeight(s)
        return h >= 2160 ? "4K" : h >= 1440 ? "2K" : h >= 1080 ? "HD" : h + "p"
    }

    // ------------------------------------------------------------------ models
    // every window, most recently used first: launcher state, fullscreen check, picking a window.
    // filterHidden must stay off: on Wayland minimized windows report IsHidden.
    TaskManager.TasksModel {
        id: allTasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortLastActivated
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        onDataChanged: root.scheduleScan()
        onRowsInserted: { root.scheduleScan(); root.scheduleRepublish() }
        onRowsRemoved: { root.scheduleScan(); root.scheduleRepublish() }
        onModelReset: { root.scheduleScan(); root.scheduleRepublish() }
        onActiveTaskChanged: root.scheduleScan()
        onLayoutChanged: root.scheduleRepublish()
        onRowsMoved: root.scheduleRepublish()
    }
    KItemModels.KSortFilterProxyModel {
        id: recentWindows
        sourceModel: allTasks
        filterRowCallback: (row, parent) => allTasks.data(allTasks.index(row, 0, parent), TaskManager.AbstractTasksModel.IsWindow) === true
    }

    // the resting strip: one pill per window, by app name, then by when it opened: a window keeps
    // its place when it changes screen or title, so positions can be learned by heart
    TaskManager.TasksModel {
        id: alphaTasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortAlpha
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
    }
    KItemModels.KSortFilterProxyModel {
        id: alphaWindows
        sourceModel: alphaTasks
        filterRowCallback: (row, parent) => alphaTasks.data(alphaTasks.index(row, 0, parent), TaskManager.AbstractTasksModel.IsWindow) === true
    }

    // the opened band: one icon per app (an app with several windows is a group), in the same order
    function appFilter(model) {
        return (row, parent) => {
            const i = model.index(row, 0, parent)
            return model.data(i, TaskManager.AbstractTasksModel.IsWindow) === true
                || model.data(i, TaskManager.AbstractTasksModel.IsGroupParent) === true
        }
    }
    TaskManager.TasksModel {
        id: alphaAppTasks
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: TaskManager.TasksModel.SortAlpha
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        // a window joining or leaving a group changes no row here: re-read the icons' state
        onDataChanged: root.scheduleScan()
        onRowsInserted: root.scheduleScan()
        onRowsRemoved: root.scheduleScan()
    }
    KItemModels.KSortFilterProxyModel {
        id: alphaApps
        sourceModel: alphaAppTasks
        filterRowCallback: root.appFilter(alphaAppTasks)
    }
    TaskManager.TasksModel {
        id: recentAppTasks
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: TaskManager.TasksModel.SortLastActivated
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterHidden: false
        onRowsInserted: root.scheduleScan()
        onRowsRemoved: root.scheduleScan()
    }
    KItemModels.KSortFilterProxyModel {
        id: recentApps
        sourceModel: recentAppTasks
        filterRowCallback: root.appFilter(recentAppTasks)
    }

    // one window list per screen, left to right (only for the "by screen" order)
    property var screenTasks: []
    Instantiator {
        id: perScreen
        model: root.cfg.order === "screen" ? root.screens : []
        delegate: ScreenTasks {
            required property var modelData
            screenInfo: modelData
        }
        onObjectAdded: Qt.callLater(root.collectScreens)
        onObjectRemoved: Qt.callLater(root.collectScreens)
    }
    function collectScreens() {
        const list = []
        for (let i = 0; i < perScreen.count; i++) {
            const o = perScreen.objectAt(i)
            if (o) list.push(o)
        }
        screenTasks = list
    }
    // windows: the strip's pills; apps: the opened band's icons
    readonly property var groups: cfg.order === "recent" ? [{ screen: null, windows: recentWindows, apps: recentApps }]
        : cfg.order === "screen" ? screenTasks.map(st => ({ screen: st.screenInfo, windows: st.windows, apps: st.apps }))
        : [{ screen: null, windows: alphaWindows, apps: alphaApps }]
    // first group with windows: later non-empty groups get a hairline divider in front
    readonly property int firstGroup: {
        for (let i = 0; i < groups.length; i++)
            if (groups[i].windows.count > 0) return i
        return -1
    }

    // pinned apps
    TaskManager.TasksModel {
        id: launcherTasks
        launcherList: root.cfg.launchers
        separateLaunchers: true
        launchInPlace: false
        hideActivatedLaunchers: false
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual
        filterByScreen: false
        filterByVirtualDesktop: false
        filterByActivity: false
    }
    KItemModels.KSortFilterProxyModel {
        id: launchers
        sourceModel: launcherTasks
        filterRowCallback: (row, parent) => launcherTasks.data(launcherTasks.index(row, 0, parent), TaskManager.AbstractTasksModel.IsLauncher) === true
    }
    readonly property alias launchers: launchers
    readonly property alias launcherTasks: launcherTasks
    // called by Kickoff's "Pin to Task Manager" (X-Plasma-Provides: org.kde.plasma.multitasking)
    function addLauncher(url) {
        const u = String(url)
        if (u && !cfg.launchers.includes(u)) cfg.launchers = cfg.launchers.concat([u])
    }
    function hasLauncher(url) { return cfg.launchers.includes(String(url)) }
    function removeLauncher(url) { cfg.launchers = cfg.launchers.filter(u => u !== String(url)) }
    // a dropped .desktop file: store app-menu entries as applications:<id>, like the stock task manager
    function launcherUrlFor(url) {
        const u = String(url)
        const m = u.match(/^file:\/\/.*\/applications\/([^/]+\.desktop)$/)
        return m ? "applications:" + m[1] : u
    }
    // Meta+1..9 (plasmashell calls this on the org.kde.plasma.multitasking provider): the Nth pinned
    // app on the bar, so per app. Running: the click rules on its most relevant window; else launch it.
    function activateTaskAtIndex(index) {
        const i = Number(index)
        if (!(i >= 0 && i < launchers.count)) return
        const R = TaskManager.AbstractTasksModel
        const idx = launchers.index(i, 0)
        if (!actOnApp(launchers.data(idx, R.AppId), launchers.data(idx, R.LauncherUrlWithoutIcon)))
            launcherTasks.requestActivate(launchers.mapToSource(idx))
    }
    function removeLauncherAt(i) {
        const l = cfg.launchers.slice()
        l.splice(i, 1)
        cfg.launchers = l
    }

    // ------------------------------------------------------------------ live state
    property var running: ({})          // app key -> { count, active, attention }
    property string runningKey: ""
    property bool fsMode: false          // a fullscreen window covers this screen
    property int tick: 0                 // bumped on every model change: the band's icons re-read their windows
    signal republish()
    function scheduleScan() { Qt.callLater(scan) }
    function scheduleRepublish() { Qt.callLater(() => root.republish()) }
    function appKeys(appId, url) {
        const k = []
        if (appId) k.push("id:" + String(appId).toLowerCase())
        if (url && String(url)) k.push("url:" + String(url))
        return k
    }
    function infoFor(appId, url, map) {
        for (const key of appKeys(appId, url))
            if (map[key]) return map[key]
        return null
    }
    function covers(g, s) {
        return !!g && g.x <= s.x + 1 && g.y <= s.y + 1
            && g.x + g.width >= s.x + s.width - 1 && g.y + g.height >= s.y + s.height - 1
    }
    // runs on every model change (titles change often): only publish what actually changed
    function scan() {
        const R = TaskManager.AbstractTasksModel
        const map = {}
        let fs = false
        let top = true          // allTasks is most recent first: the first window on this screen is on top
        for (let i = 0; i < allTasks.count; i++) {
            const idx = allTasks.index(i, 0)
            if (allTasks.data(idx, R.IsWindow) !== true) continue
            const min = allTasks.data(idx, R.IsMinimized) === true
            const active = allTasks.data(idx, R.IsActive) === true
            const attention = allTasks.data(idx, R.IsDemandingAttention) === true
            for (const key of appKeys(allTasks.data(idx, R.AppId), allTasks.data(idx, R.LauncherUrlWithoutIcon))) {
                const e = map[key] || (map[key] = { count: 0, active: false, attention: false })
                e.count++
                e.active = e.active || (active && !min)
                e.attention = e.attention || attention
            }
            // fullscreen: the top window here is fullscreen, or borderless and covering the whole screen
            // (games, players). Maximized ones never count: they only grow into the band's space.
            if (top && !min && isMine(allTasks.data(idx, R.ScreenGeometry))) {
                top = false
                fs = allTasks.data(idx, R.IsFullScreen) === true
                    || (allTasks.data(idx, R.IsMaximized) !== true && covers(allTasks.data(idx, R.Geometry), myGeometry))
            }
        }
        const key = JSON.stringify(map)
        if (key !== runningKey) {
            runningKey = key
            running = map
        }
        if (fs !== fsMode) fsMode = fs
        tick++
    }

    // an app's windows: the children of its group, or the row itself when it has just one
    function windowsOf(model, idx, tick) {      // tick: only there to re-run a binding on model changes
        if (!model || !idx || !idx.valid) return []
        if (model.data(idx, TaskManager.AbstractTasksModel.IsGroupParent) !== true) return [idx]
        const out = []
        const n = model.rowCount(idx)
        for (let i = 0; i < n; i++) out.push(model.index(i, 0, idx))
        return out
    }
    // what a thumbnail shows about one window
    function windowInfo(model, idx) {
        const R = TaskManager.AbstractTasksModel
        if (!model || !idx || !idx.valid) return null
        const ids = model.data(idx, R.WinIdList)
        const min = model.data(idx, R.IsMinimized) === true
        const geo = model.data(idx, R.ScreenGeometry)
        return {
            uuid: ids && ids.length ? String(ids[0]) : "",
            title: model.data(idx, Qt.DisplayRole) || "",
            minimized: min,
            active: !min && model.data(idx, R.IsActive) === true,
            here: isMine(geo),
            where: screenFor(geo),
            geometry: model.data(idx, R.Geometry)
        }
    }
    // what an app icon shows: how many windows, focused, any here, all minimized, and (when none is
    // out here) the screen of its most recent window elsewhere
    function appState(model, idx, tick) {
        const R = TaskManager.AbstractTasksModel
        const s = { count: 0, active: false, here: false, minimized: false, attention: false, where: null }
        let allMin = true, latest = -1
        for (const w of windowsOf(model, idx)) {
            const min = model.data(w, R.IsMinimized) === true
            const geo = model.data(w, R.ScreenGeometry)
            s.count++
            s.active = s.active || (!min && model.data(w, R.IsActive) === true)
            s.attention = s.attention || model.data(w, R.IsDemandingAttention) === true
            allMin = allMin && min
            if (min) continue
            if (isMine(geo)) { s.here = true; continue }
            const t = model.data(w, R.LastActivated)
            const ms = t ? new Date(t).getTime() : 0
            if (ms > latest) { latest = ms; s.where = screenFor(geo) }
        }
        s.minimized = s.count > 0 && allMin
        if (s.here) s.where = null
        return s
    }

    // ------------------------------------------------------------------ actions
    readonly property string helper: Qt.resolvedUrl("../code/glimpse-kwin.sh").toString().replace(/^file:\/\//, "")
    function bringHere(ids) {
        const id = ids && ids.length ? String(ids[0]) : ""
        if (!/^[{}0-9a-fA-F-]+$/.test(id) || !/^[A-Za-z0-9_.-]+$/.test(screenName)) {
            console.warn("glimpse: cannot move window", id, "to", screenName)
            return
        }
        sh.connectSource("sh '" + helper + "' bring '" + id + "' '" + screenName + "' #run" + Date.now())
    }
    // the click rules, on one window
    function actOn(model, idx) {
        const R = TaskManager.AbstractTasksModel
        if (!idx || !idx.valid) return
        if (!isMine(model.data(idx, R.ScreenGeometry)))
            bringHere(model.data(idx, R.WinIdList))                 // restore or slide it onto this screen
        else if (model.data(idx, R.IsMinimized) === true || model.data(idx, R.IsActive) !== true)
            model.requestActivate(idx)
        else
            model.requestToggleMinimized(idx)
    }
    // the window an app click acts on: focused here (-> minimize) > open here > minimized here >
    // anywhere else; the most recent first within a tier
    function pickWindow(model, list) {
        const R = TaskManager.AbstractTasksModel
        let best = null, bestScore = -1
        for (const idx of list) {
            const here = isMine(model.data(idx, R.ScreenGeometry))
            const min = model.data(idx, R.IsMinimized) === true
            const tier = !here ? 0 : min ? 1 : model.data(idx, R.IsActive) === true ? 3 : 2
            const t = model.data(idx, R.LastActivated)
            const score = tier * 1e14 + (t ? new Date(t).getTime() : 0)
            if (score > bestScore) { best = idx; bestScore = score }
        }
        return best
    }
    function actOnTile(model, idx) {
        const w = pickWindow(model, windowsOf(model, idx))
        if (w) actOn(model, w)
    }
    // a launcher of a running app follows the same rules, on that app's most relevant window
    function actOnApp(appId, url) {
        const R = TaskManager.AbstractTasksModel
        const keys = appKeys(appId, url)
        const list = []
        for (let i = 0; i < allTasks.count; i++) {
            const idx = allTasks.index(i, 0)
            if (allTasks.data(idx, R.IsWindow) !== true) continue
            if (appKeys(allTasks.data(idx, R.AppId), allTasks.data(idx, R.LauncherUrlWithoutIcon)).some(k => keys.includes(k)))
                list.push(idx)
        }
        const best = pickWindow(allTasks, list)
        if (best) actOn(allTasks, best)
        return best !== null
    }
    function closeApp(model, idx) {
        for (const w of windowsOf(model, idx)) model.requestClose(w)
    }

    // ------------------------------------------------------------------ open / close
    property bool shelfOpen: false
    property bool shelfMapped: false     // the opened band's window is up (the strip lets it have the pointer)
    property bool shelfShown: false      // ...and fully drawn: only then does the resting band hide
    property bool menuOpen: false        // a tile's context menu is up: keep the band open
    signal shelfRevealed()
    signal shelfClosing()
    Timer {
        id: closeTimer
        onTriggered: {
            if (root.menuOpen || root.stripHovered || root.shelfHovered) return
            root.shelfOpen = false
            root.hoverTile = null
            root.thumbTile = null
        }
    }
    // leaving the opened band closes it at once; the short grace covers hand-offs between the strip,
    // the band and the fullscreen edge, whose leave and enter arrive as two events
    readonly property int handOff: 80
    function closeIn(ms) { closeTimer.interval = ms; closeTimer.restart() }
    // The strip always takes the pointer, open or not, so the band can come back the moment the
    // pointer does: nothing waits for a window to map or a closing animation to end. Only pushing
    // against the very edge of the screen opens it; hovering the strip just readies the pills.
    property bool stripHovered: false
    property real edgeX: 0              // where the pointer met the edge: the rim lights up from there
    function stripHover(on) {
        stripHovered = on
        if (on) closeTimer.stop()
        else if (shelfOpen && !shelfHovered) closeIn(handOff)
    }
    function edgeTouched(x) {
        if (shelfOpen) return
        edgeX = x
        openNow()
    }
    // the opened band counts as one area: the band itself, plus the label tab and the thumbnails under it
    property bool bandHovered: false
    property bool dropHovered: false
    readonly property bool shelfHovered: bandHovered || dropHovered
    onShelfHoveredChanged: {
        if (shelfHovered) closeTimer.stop()
        else if (!menuOpen) closeIn(20)     // just enough for a hand-off to the strip in the same frame
    }
    function openNow() { closeTimer.stop(); shelfOpen = true }

    // ------------------------------------------------------------------ hover: lens, tab, thumbnails
    property IconTile hoverTile: null    // the icon under the pointer (object-typed: a destroyed tile nulls it)
    property IconTile lensTile: null     // the icon the lens and the tab sit under (lingers over gaps)
    property IconTile thumbTile: null    // the app whose thumbnails are out
    onHoverTileChanged: {
        if (hoverTile) {
            lensHold.stop(); thumbOut.stop()
            lensTile = hoverTile
            if (thumbTile) thumbTile = hoverTile         // already out: follow the pointer at once
            else if (cfg.thumbnails) thumbIn.restart()
        } else {
            lensHold.restart()
            thumbOut.restart()
        }
    }
    onDropHoveredChanged: if (dropHovered) { lensHold.stop(); thumbOut.stop() } else if (!hoverTile) { lensHold.restart(); thumbOut.restart() }
    // gliding over a gap keeps the lens out; moving down onto the tab keeps the thumbnails coming
    Timer {
        id: lensHold
        interval: 140
        onTriggered: if (!root.hoverTile && !root.dropHovered) { root.lensTile = root.thumbTile; thumbIn.stop() }
    }
    Timer { id: thumbIn; interval: 200; onTriggered: if (root.shelfOpen && root.lensTile) root.thumbTile = root.lensTile }
    Timer { id: thumbOut; interval: 300; onTriggered: if (!root.hoverTile && !root.dropHovered) { root.thumbTile = null; root.lensTile = null } }
    onShelfOpenChanged: if (!shelfOpen) { thumbIn.stop(); thumbTile = null; lensTile = null }

    // ------------------------------------------------------------------ resting pill
    Component {
        id: pillDelegate
        Item {
            id: pill
            required property int index
            required property var model
            readonly property bool minimized: model.IsMinimized === true
            readonly property bool active: model.IsActive === true && !minimized
            readonly property bool here: root.isMine(model.ScreenGeometry)
            readonly property bool hair: root.cfg.glimpseStyle === "hairline"
            readonly property color tint: C.appTint(colors, root.cFg)
            Kirigami.ImageColors { id: colors; source: pill.model.decoration }
            // whole device pixels, so the pills stay crisp at fractional scales
            function snap(v) { return root.snap(v) }
            // a little wider while the hover delay runs: the band is about to open
            width: snap((hair ? (active ? 26 : 16) : (active ? 18 : 9)) * root.topScale + (root.stripHovered ? 3 : 0))
            height: ListView.view ? ListView.view.height : root.stripHeight
            Behavior on width { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }

            // the focused window's light leaks out from under the bezel
            Shape {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height / 2
                width: 64
                height: 64
                visible: opacity > 0
                opacity: pill.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.slow } }
                transform: Scale { origin.x: 32; origin.y: 32; yScale: 0.32 }
                ShapePath {
                    strokeWidth: -1
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 32; centerY: 32; centerRadius: 32
                        focalX: 32; focalY: 32
                        GradientStop { position: 0; color: C.alpha(pill.tint, 0.6) }
                        GradientStop { position: 0.45; color: C.alpha(pill.tint, 0.22) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathRectangle { x: 0; y: 0; width: 64; height: 64 }
                }
            }
            // the app's own colour: full here, faint when it lives on another screen, a ring when minimized
            Rectangle {
                width: parent.width
                height: pill.hair ? pill.snap(1.5) : pill.snap(Math.max(2, root.cfg.stripHeight * 0.5 * root.topScale))
                y: pill.snap((parent.height - height) / 2)
                radius: height / 2
                color: pill.minimized ? "transparent"
                     : pill.active ? Qt.lighter(pill.tint, 1.12) : C.alpha(pill.tint, pill.here ? 0.85 : 0.4)
                border.width: pill.minimized ? 1 : 0
                border.color: C.alpha(pill.tint, 0.65)
                Behavior on color { ColorAnimation { duration: Tokens.slow } }
            }

            // KWin's minimize animation (magic lamp) flies into this pill
            function publish() {
                const view = pill.ListView.view
                const win = pill.Window.window
                if (!pill.here || !view || !win) return
                const p = pill.mapToItem(null, 0, 0)
                view.model.sourceModel.requestPublishDelegateGeometry(view.model.mapToSource(view.model.index(pill.index, 0)),
                    Qt.rect(win.x + p.x, win.y + p.y, pill.width, Math.max(pill.height, 8)), pill)
            }
            Timer { id: pub; interval: 450; onTriggered: pill.publish() }
            onHereChanged: pub.restart()
            onXChanged: pub.restart()
            Component.onCompleted: pub.restart()
            Connections { target: root; function onRepublish() { pub.restart() } }
        }
    }

    // ------------------------------------------------------------------ the resting band (always there)
    // Two windows per screen: the band, drawn click-through and as tall as its rounded corners, and an
    // invisible strip over it that reserves the space, catches the pointer and opens the band.
    // Both step aside while a fullscreen window covers the screen.
    Instantiator {
        model: root.myScreen && root.cfg.showStrip ? [root.myScreen] : []
        delegate: Window {
            id: bandWin
            required property var modelData
            screen: modelData
            x: modelData.virtualX               // keep Qt's idea of the position on this screen,
            y: modelData.virtualY               // or it re-homes the window to another one
            transientParent: null
            visible: !root.fsMode
            color: "transparent"
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
            width: modelData.width
            height: root.stripHeight + root.fillet
            LayerShell.Window.scope: "dock"
            LayerShell.Window.layer: LayerShell.Window.LayerTop
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            LayerShell.Window.activateOnShow: false
            LayerShell.Window.wantsToBeOnActiveScreen: false

            Item {
                anchors.fill: parent
                // hidden only once the opened band is fully drawn over it, so the hand-off never flickers
                visible: !root.shelfShown
                Notch {
                    anchors.fill: parent
                    solid: true
                    bandH: root.stripHeight
                    fillet: root.fillet
                    bezel: root.cBezel
                    rimA: root.cPrimary
                    rimB: root.cTertiary
                }
                Row {
                    id: pillRow
                    x: root.leftPad
                    height: root.stripHeight
                    spacing: root.snap(7)
                    Repeater {
                        model: root.groups
                        delegate: ListView {
                            required property var modelData
                            height: pillRow.height
                            width: contentWidth
                            visible: count > 0
                            orientation: ListView.Horizontal
                            interactive: false
                            spacing: root.snap(3)
                            model: modelData.windows
                            delegate: pillDelegate
                            onXChanged: root.scheduleRepublish()
                            add: Transition { NumberAnimation { property: "scale"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter } }
                            remove: Transition { NumberAnimation { property: "scale"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit } }
                            displaced: Transition { NumberAnimation { property: "x"; duration: Tokens.base; easing.type: Tokens.move } }
                        }
                    }
                }
            }
        }
    }
    Instantiator {
        model: root.myScreen && root.cfg.showStrip ? [root.myScreen] : []
        delegate: Window {
            id: stripWin
            required property var modelData
            screen: modelData
            x: modelData.virtualX
            y: modelData.virtualY
            transientParent: null
            visible: !root.fsMode
            color: "transparent"
            // the opened band is mapped after it (so it is stacked above) and takes the pointer while open
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
            width: modelData.width
            height: root.stripHeight
            LayerShell.Window.scope: "dock"
            LayerShell.Window.layer: LayerShell.Window.LayerTop
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
            LayerShell.Window.exclusionZone: root.stripHeight
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            LayerShell.Window.activateOnShow: false
            LayerShell.Window.wantsToBeOnActiveScreen: false

            // a hidden or destroyed window gets no leave event
            onVisibleChanged: if (!visible && root.stripHovered) root.stripHover(false)
            Component.onDestruction: if (root.stripHovered) root.stripHover(false)
            // a MouseArea, not a HoverHandler: it reports every move, including the one that ends on the edge
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: {
                    root.stripHover(containsMouse)
                    if (containsMouse && mouseY < 1) root.edgeTouched(mouseX)
                }
                onPositionChanged: mouse => { if (mouse.y < 1) root.edgeTouched(mouse.x) }
                onClicked: mouse => { root.edgeX = mouse.x; root.openNow() }
            }
        }
    }

    // ------------------------------------------------------------------ the opened band
    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: ShelfWindow { g: root }
    }

    // ------------------------------------------------------------------ fullscreen edge
    // Only exists while a fullscreen window covers this screen: rest on the top edge for
    // dwellDelay ms (a line fills meanwhile) and the band drops in over the fullscreen window.
    Instantiator {
        model: root.myScreen && root.fsMode ? [root.myScreen] : []
        delegate: Window {
            id: edgeWin
            required property var modelData
            screen: modelData
            x: modelData.virtualX
            y: modelData.virtualY
            transientParent: null
            visible: true
            color: "transparent"
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
            width: modelData.width
            height: 3
            LayerShell.Window.scope: "dock"
            LayerShell.Window.layer: LayerShell.Window.LayerOverlay
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            LayerShell.Window.activateOnShow: false
            LayerShell.Window.wantsToBeOnActiveScreen: false

            Rectangle {
                id: dwell
                anchors.horizontalCenter: parent.horizontalCenter
                height: 2
                width: 0
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.35; color: root.cPrimary }
                    GradientStop { position: 0.65; color: root.cTertiary }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            HoverHandler {
                id: edgeHover
                onHoveredChanged: {
                    if (hovered) {
                        closeTimer.stop()
                        if (!root.shelfOpen) dwellAnim.restart()
                    } else {
                        dwellAnim.stop()
                        dwell.width = 0
                        if (root.shelfOpen && !root.shelfHovered) root.closeIn(root.handOff)
                    }
                }
            }
            SequentialAnimation {
                id: dwellAnim
                NumberAnimation { target: dwell; property: "width"; from: 0; to: edgeWin.width * 0.42; duration: root.cfg.dwellDelay; easing.type: Easing.InOutQuad }
                ScriptAction { script: { root.edgeX = edgeHover.point.position.x; root.openNow(); dwell.width = 0 } }
            }
        }
    }
}
