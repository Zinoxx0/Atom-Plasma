import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.kitemmodels as KItemModels
import org.kde.layershell as LayerShell

// Glimpse: the bar keeps only launchers (lit when the app runs anywhere); every open window,
// from every screen, lives in a slim band along the top edge of each screen, corner to corner,
// that looks like part of the display's bezel. On hover it springs open, its pills popping out
// into icons, its lower lip turning to glass. One instance per bar; each instance owns the band,
// the opened bar ("shelf") and the fullscreen edge of its own screen.
// Clicking a window: minimized -> restore here, on another screen -> slide here,
// here and focused -> minimize, here -> focus. Middle-click: a new window of that app.
PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration
    readonly property int stripHeight: Math.round(cfg.stripHeight * topScale)
    readonly property bool reduceMotion: Kirigami.Units.longDuration <= 1
    function ms(d) { return reduceMotion ? 0 : d }

    // the opened bar
    readonly property int barH: 44          // height of the opened band
    readonly property int iconSize: Math.round(26 * topScale)
    readonly property int slot: Math.round(40 * topScale)
    // hovered icons grow, but stay inside the band (it doesn't grow with topScale)
    readonly property real hoverMag: Math.min(1.3, 34 / iconSize)
    readonly property int fillet: 14        // the rounded "screen corners" under the band
    readonly property int tabH: 24          // the label tab that drips from the lip
    readonly property int leftPad: fillet + 6

    // ------------------------------------------------------------------ palette
    // Same source as the other rice widgets: this screen's wallpaper palette (rice.py), which also
    // names the pre-blurred wallpaper band used as the glass backdrop.
    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    // size of the resting strip, its pills and the opened band's icons (rice settings "top_scale")
    readonly property real topScale: pal._topScale || 1
    function col(n, f) { return pal[n] ?? f }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // an app's own colour, from its icon (Kirigami.ImageColors): the most vivid sizeable swatch,
    // lifted to a candy pastel that reads on the dark bezel. Monochrome icons get the text colour.
    function appTint(ic) {
        const pal = ic ? ic.palette : null
        let best = null, score = 0
        for (let i = 0; pal && i < pal.length; i++) {
            const c = pal[i].color, r = pal[i].ratio
            if (r < 0.04 || c.hslSaturation < 0.28 || c.hslLightness < 0.12 || c.hslLightness > 0.92) continue
            const sc = c.hslSaturation * Math.sqrt(r)
            if (sc > score) { best = c; score = sc }
        }
        if (!best) return cFg
        return Qt.hsla(best.hslHue, Math.min(1, best.hslSaturation * 1.1), Math.max(0.62, Math.min(0.76, best.hslLightness)), 1)
    }
    readonly property color cDeep: col("surface_lowest", "#11111b")
    readonly property color cSurface: col("surface", "#181825")
    readonly property color cFg: col("on_surface", Kirigami.Theme.textColor)
    readonly property color cFgDim: col("on_surface_variant", "#bac2de")
    readonly property color cMuted: col("muted", "#7f849c")
    readonly property color cPrimary: col("primary", Kirigami.Theme.highlightColor)
    readonly property color cOnPrimary: col("on_primary", "#1e1e2e")
    readonly property color cTertiary: col("tertiary", "#f9e2af")
    readonly property color cRed: col("red", "#f38ba8")
    readonly property url glassUrl: pal._glass ? "file://" + pal._glass : ""
    readonly property int glassBand: pal._glassBand || 160
    // the glass colour wash: accent on the left, deep in the middle (icons stay legible), tertiary right
    readonly property color washA: alpha(cPrimary, 0.48)
    readonly property color washB: alpha(cDeep, 0.52)
    readonly property color washC: alpha(cTertiary, 0.42)
    // the bezel: near black, with a hint of the palette so it isn't dead flat
    readonly property color cBezel: Qt.rgba(cDeep.r * 0.35, cDeep.g * 0.35, cDeep.b * 0.35, 1)

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const tag = source.split("#pal ")[1]
            if (tag !== undefined) {
                if (tag.split(" ")[0] === root.screenName)
                    try { root.pal = JSON.parse(data["stdout"]) } catch (e) {}
            } else if (data["exit code"]) {
                console.warn("glimpse:", source, data["stderr"])
            }
            disconnectSource(source)
        }
    }
    function refreshPalette() {
        if (!screenName) return
        sh.connectSource('cat "$HOME/.local/state/rice/palette-' + screenName + '.json" 2>/dev/null || cat "$HOME/.local/state/rice/palette.json" #pal ' + screenName + ' ' + Date.now())
    }
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refreshPalette()
    onScreenNameChanged: refreshPalette()
    Component.onCompleted: refreshPalette()

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
    function screenLabel(s) {
        if (!s) return ""
        if (/^(eDP|LVDS|DSI)/.test(s.name)) return i18n("Laptop")
        const h = Math.round(s.height * s.devicePixelRatio)
        return h >= 2160 ? "4K" : h + "p"
    }

    // ------------------------------------------------------------------ models
    // every window, most recently used first: launcher state, fullscreen check, "recent" order.
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

    // every window by app name, then by when it opened: a window keeps its place when it changes
    // screen or title, so positions can be learned by heart
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

    // one window list per screen, left to right
    property var screenTasks: []
    Instantiator {
        id: perScreen
        model: root.screens
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
    readonly property var groups: cfg.order === "recent" ? [{ screen: null, windows: recentWindows }]
        : cfg.order === "screen" ? screenTasks.map(st => ({ screen: st.screenInfo, windows: st.windows }))
        : [{ screen: null, windows: alphaWindows }]
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
    // Meta+1..9 (plasmashell calls this on the org.kde.plasma.multitasking provider)
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
    function actOn(model, idx) {
        const R = TaskManager.AbstractTasksModel
        if (!idx.valid) return
        if (!isMine(model.data(idx, R.ScreenGeometry)))
            bringHere(model.data(idx, R.WinIdList))                 // restore or slide it onto this screen
        else if (model.data(idx, R.IsMinimized) === true || model.data(idx, R.IsActive) !== true)
            model.requestActivate(idx)
        else
            model.requestToggleMinimized(idx)
    }
    function actOnRow(proxy, row) { actOn(proxy.sourceModel, proxy.mapToSource(proxy.index(row, 0))) }
    function newInstanceRow(proxy, row) { proxy.sourceModel.requestNewInstance(proxy.mapToSource(proxy.index(row, 0))) }
    // a launcher of a running app follows the same rules, on that app's most relevant window
    function actOnApp(appId, url) {
        const R = TaskManager.AbstractTasksModel
        const keys = appKeys(appId, url)
        // focused here (-> minimize) > open here > minimized here > anywhere else; most recent first within a tier
        let best = null, bestScore = -1
        for (let i = 0; i < allTasks.count; i++) {
            const idx = allTasks.index(i, 0)
            if (allTasks.data(idx, R.IsWindow) !== true) continue
            if (!appKeys(allTasks.data(idx, R.AppId), allTasks.data(idx, R.LauncherUrlWithoutIcon)).some(k => keys.includes(k)))
                continue
            const here = isMine(allTasks.data(idx, R.ScreenGeometry))
            const min = allTasks.data(idx, R.IsMinimized) === true
            const tier = !here ? 0 : min ? 1 : allTasks.data(idx, R.IsActive) === true ? 3 : 2
            const t = allTasks.data(idx, R.LastActivated)
            const score = tier * 1e14 + (t ? new Date(t).getTime() : 0)
            if (score > bestScore) { best = idx; bestScore = score }
        }
        if (best) actOn(allTasks, best)
        return best !== null
    }

    function esc(s) { return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function describe(t) {
        const where = t.minimized ? i18n("minimized") : t.here ? i18n("on this screen") : i18n("on %1", screenLabel(t.where))
        const verb = t.minimized || !t.here ? i18n("click to bring here") : t.active ? i18n("click to minimize") : i18n("click to focus")
        return "<b>" + esc(t.title) + "</b>  <font color='" + cFgDim + "'>" + where + " · " + verb + "</font>"
    }

    // ------------------------------------------------------------------ open / close
    property bool shelfOpen: false
    property bool shelfShown: false      // the opened bar's window is mapped (the resting band hides meanwhile)
    property Item hoverTile: null       // Item-typed, so a destroyed tile nulls it
    property bool menuOpen: false       // a tile's context menu is up: keep the bar open
    signal shelfRevealed()
    signal shelfClosing()
    Timer { id: openTimer; interval: root.cfg.hoverDelay; onTriggered: root.shelfOpen = true }
    Timer {
        id: closeTimer
        onTriggered: {
            if (root.menuOpen || root.stripHovered || root.shelfHovered) return
            root.shelfOpen = false
            root.hoverTile = null
        }
    }
    // leaving the opened bar closes it at once; the longer grace covers hand-offs, when the bar maps
    // over the strip (or the fullscreen edge) and the pointer has yet to enter it
    readonly property int handOff: 250
    function closeIn(ms) { closeTimer.interval = ms; closeTimer.restart() }
    property bool stripHovered: false
    function stripHover(on) {
        stripHovered = on
        if (on) { closeTimer.stop(); if (!shelfOpen) openTimer.restart() }
        else { openTimer.stop(); if (shelfOpen && !shelfHovered) closeIn(handOff) }
    }
    property bool shelfHovered: false
    function shelfHover(on) {
        shelfHovered = on
        if (on) closeTimer.stop()
        else if (!menuOpen) closeIn(20)     // just enough for a hand-off to the strip in the same frame
    }
    function openNow() { openTimer.stop(); closeTimer.stop(); shelfOpen = true }

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
            readonly property color tint: root.appTint(colors)
            Kirigami.ImageColors { id: colors; source: pill.model.decoration }
            // a little wider while the hover delay runs: the bar is about to open
            width: (hair ? (active ? 26 : 16) : (active ? 18 : 9)) * root.topScale + (root.stripHovered ? 3 : 0)
            height: ListView.view ? ListView.view.height : root.stripHeight
            Behavior on width { SpringAnimation { spring: 4.5; damping: 0.22; epsilon: 0.05 } }

            // the focused window's light leaks out from under the bezel
            Shape {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height / 2
                width: 64
                height: 64
                visible: opacity > 0
                opacity: pill.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.ms(320) } }
                transform: Scale { origin.x: 32; origin.y: 32; yScale: 0.32 }
                ShapePath {
                    strokeWidth: -1
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 32; centerY: 32; centerRadius: 32
                        focalX: 32; focalY: 32
                        GradientStop { position: 0; color: root.alpha(pill.tint, 0.6) }
                        GradientStop { position: 0.45; color: root.alpha(pill.tint, 0.22) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathRectangle { x: 0; y: 0; width: 64; height: 64 }
                }
            }
            // the app's own colour: full here, faint when it lives on another screen, a ring when minimized
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: pill.hair ? 1.5 : Math.max(2, root.cfg.stripHeight * 0.5 * root.topScale)
                radius: height / 2
                color: pill.minimized ? "transparent"
                     : pill.active ? Qt.lighter(pill.tint, 1.12) : root.alpha(pill.tint, pill.here ? 0.85 : 0.4)
                border.width: pill.minimized ? 1 : 0
                border.color: root.alpha(pill.tint, 0.65)
                Behavior on color { ColorAnimation { duration: root.ms(320) } }
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

    // ------------------------------------------------------------------ icon in the opened bar
    Component {
        id: iconDelegate
        Item {
            id: tile
            required property int index
            required property var model
            readonly property bool minimized: model.IsMinimized === true
            readonly property bool active: model.IsActive === true && !minimized
            readonly property bool here: root.isMine(model.ScreenGeometry)
            readonly property var where: root.screenFor(model.ScreenGeometry)
            readonly property string title: model.display || model.AppName || ""
            readonly property bool hovered: ma.containsMouse
            readonly property color tint: root.appTint(colors)
            Kirigami.ImageColors { id: colors; source: tile.model.decoration }
            property real pop: 0          // 0 = folded into its pill, 1 = out
            property int delay: 0
            width: root.slot + (name.visible ? name.width + 4 : 0)
            height: root.barH

            // icon: pops out of the bar, magnifies on hover, squashes on click
            Kirigami.Icon {
                id: icon
                x: (root.slot - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: root.iconSize
                height: root.iconSize
                source: tile.model.decoration
                opacity: Math.min(1, tile.pop * 2.2) * (tile.minimized ? 0.45 : tile.here ? 1 : 0.9)
                property real mag: tile.hovered ? (ma.pressed ? 1.05 : root.hoverMag) : 1
                Behavior on mag { SpringAnimation { spring: 5; damping: 0.2; epsilon: 0.005 } }
                scale: (0.15 + 0.85 * tile.pop) * mag
                transform: [
                    Translate { y: (1 - tile.pop) * -16 + (tile.hovered ? -3 : 0) },
                    Scale { id: squash; origin.x: root.iconSize / 2; origin.y: root.iconSize }
                ]
            }
            // app name, when enabled in the settings
            Text {
                id: name
                visible: root.cfg.showNames
                x: root.slot - 4
                anchors.verticalCenter: icon.verticalCenter
                width: Math.min(implicitWidth, 120)
                text: tile.model.AppName || tile.title
                elide: Text.ElideRight
                opacity: Math.max(0, Math.min(1, tile.pop)) * (tile.minimized ? 0.5 : 1)
                color: tile.here ? root.cFg : root.cFgDim
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: tile.active ? Font.DemiBold : Font.Medium
            }
            // focused: glowing accent bar
            Rectangle {
                anchors.horizontalCenter: icon.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                width: tile.active ? 14 : 0
                height: 3
                radius: 1.5
                opacity: tile.pop > 0.5 ? 1 : 0
                Behavior on width { SpringAnimation { spring: 4; damping: 0.22; epsilon: 0.05 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.cPrimary }
                    GradientStop { position: 1; color: root.cTertiary }
                }
                layer.enabled: tile.active
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: root.cPrimary; shadowBlur: 0.6; shadowOpacity: 0.9; shadowVerticalOffset: 0; shadowHorizontalOffset: 0 }
            }
            // here: dot; minimized: ring
            Rectangle {
                anchors.horizontalCenter: icon.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                visible: !tile.active && (tile.here || tile.minimized)
                width: 4
                height: 4
                radius: 2
                opacity: tile.pop > 0.5 ? 1 : 0
                color: tile.minimized ? "transparent" : root.alpha(root.cFg, 0.85)
                border.width: tile.minimized ? 1 : 0
                border.color: root.alpha(root.cFg, 0.6)
            }
            // lives on another screen: gradient tag
            Rectangle {
                visible: !tile.here && !tile.minimized && tile.where !== null
                x: icon.x + icon.width - 9
                y: 3
                height: 11
                width: tag.implicitWidth + 7
                radius: 5.5
                scale: tile.pop
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.cPrimary }
                    GradientStop { position: 1; color: root.cTertiary }
                }
                Text {
                    id: tag
                    anchors.centerIn: parent
                    text: root.screenLabel(tile.where)
                    color: root.cOnPrimary
                    font.family: "Inter"
                    font.pixelSize: 8
                    font.weight: Font.Black
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onContainsMouseChanged: {
                    if (containsMouse) root.hoverTile = tile
                    else if (root.hoverTile === tile) root.hoverTile = null
                }
                onClicked: mouse => {
                    const view = tile.ListView.view
                    if (!view) return
                    if (mouse.button === Qt.RightButton) { tileMenu.openRelative(); return }
                    if (mouse.button === Qt.MiddleButton) root.newInstanceRow(view.model, tile.index)
                    else root.actOnRow(view.model, tile.index)
                    squashAnim.restart()
                }
            }
            PlasmaExtras.Menu {
                id: tileMenu
                visualParent: tile
                readonly property string url: String(tile.model.LauncherUrlWithoutIcon || "")
                onStatusChanged: {
                    root.menuOpen = status === PlasmaExtras.Menu.Open || status === PlasmaExtras.Menu.Opening
                    if (!root.menuOpen && !root.shelfHovered) root.closeIn(root.handOff)
                }
                PlasmaExtras.MenuItem {
                    visible: tileMenu.url !== ""
                    text: root.hasLauncher(tileMenu.url) ? i18n("Unpin from bar") : i18n("Pin to bar")
                    icon: root.hasLauncher(tileMenu.url) ? "window-unpin" : "window-pin"
                    onClicked: root.hasLauncher(tileMenu.url) ? root.removeLauncher(tileMenu.url) : root.addLauncher(tileMenu.url)
                }
                PlasmaExtras.MenuItem {
                    text: i18n("New window")
                    icon: "window-new"
                    onClicked: if (tile.ListView.view) root.newInstanceRow(tile.ListView.view.model, tile.index)
                }
                PlasmaExtras.MenuItem {
                    text: i18n("Close window")
                    icon: "window-close"
                    onClicked: {
                        const v = tile.ListView.view
                        if (v) v.model.sourceModel.requestClose(v.model.mapToSource(v.model.index(tile.index, 0)))
                    }
                }
            }
            SequentialAnimation {
                id: squashAnim
                ParallelAnimation {
                    NumberAnimation { target: squash; property: "xScale"; to: 1.3; duration: root.ms(80); easing.type: Easing.OutQuad }
                    NumberAnimation { target: squash; property: "yScale"; to: 0.72; duration: root.ms(80); easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: squash; property: "xScale"; to: 1; duration: root.ms(620); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
                    NumberAnimation { target: squash; property: "yScale"; to: 1; duration: root.ms(620); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
                }
            }
            // pop out, one after another, when the bar opens; fold back in when it closes
            Connections {
                target: root
                function onShelfRevealed() {
                    tile.delay = root.ms(40 + Math.min(14, Math.round(tile.mapToItem(null, 0, 0).x / root.slot)) * 18)
                    foldAnim.stop()
                    popAnim.restart()
                }
                function onShelfClosing() {
                    popAnim.stop()
                    foldAnim.restart()
                }
            }
            SequentialAnimation {
                id: popAnim
                PropertyAction { target: tile; property: "pop"; value: 0 }
                PauseAnimation { duration: tile.delay }
                NumberAnimation { target: tile; property: "pop"; to: 1; duration: root.ms(560); easing.type: Easing.OutElastic; easing.amplitude: 1.15; easing.period: 0.4 }
            }
            NumberAnimation { id: foldAnim; target: tile; property: "pop"; to: 0; duration: root.ms(120); easing.type: Easing.InQuad }
            // a window that shows up while the bar is open pops straight out
            Component.onCompleted: if (root.shelfShown) { tile.delay = 0; popAnim.restart() }
        }
    }

    // ------------------------------------------------------------------ the resting band (always there)
    // Two windows per screen: the band, drawn click-through and as tall as its rounded corners, and an
    // invisible strip over it that reserves the space, catches the pointer and opens the bar.
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
                visible: !root.shelfShown       // the opened bar starts from this very shape, so the hand-off is seamless
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
                    spacing: 7
                    Repeater {
                        model: root.groups
                        delegate: ListView {
                            required property var modelData
                            height: pillRow.height
                            width: contentWidth
                            visible: count > 0
                            orientation: ListView.Horizontal
                            interactive: false
                            spacing: 3
                            model: modelData.windows
                            delegate: pillDelegate
                            onXChanged: root.scheduleRepublish()
                            add: Transition { NumberAnimation { property: "scale"; from: 0; to: 1; duration: root.ms(520); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.4 } }
                            remove: Transition { NumberAnimation { property: "scale"; to: 0; duration: root.ms(160); easing.type: Easing.InBack } }
                            displaced: Transition { NumberAnimation { property: "x"; duration: root.ms(420); easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
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
            // KWin may stack it above the opened bar: let the bar have the pointer while it is up
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | (root.shelfShown ? Qt.WindowTransparentForInput : 0)
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
            HoverHandler { onHoveredChanged: root.stripHover(hovered) }
            TapHandler { onTapped: root.openNow() }
        }
    }

    // ------------------------------------------------------------------ the opened bar
    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: Window {
            id: shelfWin
            required property var modelData
            screen: modelData
            x: modelData.virtualX
            y: modelData.virtualY
            transientParent: null
            visible: false
            color: "transparent"
            // below the lip it is see-through (fillets, label tab, haze): click-through the moment it closes
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | (root.shelfOpen ? 0 : Qt.WindowTransparentForInput)
            width: modelData.width
            height: Math.ceil(root.stripHeight + (root.barH - root.stripHeight) * 1.2) + Math.ceil(root.tabH * 1.25)
            LayerShell.Window.scope: "dock"
            LayerShell.Window.layer: root.fsMode ? LayerShell.Window.LayerOverlay : LayerShell.Window.LayerTop
            LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
            LayerShell.Window.exclusionZone: -1
            LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
            LayerShell.Window.activateOnShow: false
            LayerShell.Window.wantsToBeOnActiveScreen: false

            property real morph: 0            // 0 = the resting band, 1 = the opened bar (overshoots)
            readonly property real lip: Math.max(0, Math.min(1, morph))
            readonly property real bandH: Math.max(root.stripHeight, root.stripHeight + (root.barH - root.stripHeight) * morph)
            // rebuilt mid-animation (screen change): don't leave the resting band hidden
            Component.onDestruction: { root.shelfShown = false; root.shelfOpen = false; root.hoverTile = null; root.menuOpen = false; root.shelfHovered = false }

            Connections {
                target: root
                function onShelfOpenChanged() {
                    if (root.shelfOpen) {
                        closeMorph.stop()
                        shelfWin.visible = true
                        root.shelfShown = true
                        openMorph.restart()
                        root.shelfRevealed()
                    } else {
                        openMorph.stop()
                        root.shelfClosing()
                        closeMorph.restart()
                    }
                }
            }

            // the label tab drips from the lip under the hovered icon and rides along with the lens
            property string tabText: ""
            readonly property string liveText: root.hoverTile ? root.describe(root.hoverTile) : ""
            onLiveTextChanged: if (liveText) tabText = liveText      // keeps its text while it retracts
            property bool tabWanted: false
            Timer { id: tabHold; interval: 140; onTriggered: shelfWin.tabWanted = false }   // gliding over a gap keeps it out
            Connections {
                target: root
                function onHoverTileChanged() {
                    if (root.hoverTile) { tabHold.stop(); shelfWin.tabWanted = true }
                    else tabHold.restart()
                }
            }
            property real tabDrop: tabWanted && morph > 0.85 ? root.tabH : 0
            Behavior on tabDrop { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.05 } }
            property real tabWidth: Math.min(width - 2 * root.fillet - 40, tabLabel.implicitWidth + 28)
            Behavior on tabWidth { enabled: shelfWin.tabDrop > 1; SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.1 } }
            readonly property real tabGrown: Math.max(0, Math.min(1, tabDrop / root.tabH))

            Notch {
                id: notch
                anchors.fill: parent
                bandH: shelfWin.bandH
                fillet: root.fillet
                glass: shelfWin.lip
                tabX: lens.x + lens.width / 2
                tabW: shelfWin.tabWidth * (0.55 + 0.45 * shelfWin.tabGrown)     // a droplet that widens as it drops
                tabH: Math.max(0, shelfWin.tabDrop) * shelfWin.lip
                backdrop: root.glassUrl
                backdropSize: Qt.size(shelfWin.width, root.glassBand)
                bezel: root.cBezel
                tintA: root.washA
                tintB: root.washB
                tintC: root.washC
                rimA: root.cPrimary
                rimB: root.cTertiary
                glow: root.cPrimary
            }
            Text {
                id: tabLabel
                x: notch.tL + 14
                y: shelfWin.bandH
                width: Math.max(0, notch.tabW - 28)
                height: notch.tabH
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: shelfWin.tabText
                textFormat: Text.StyledText
                elide: Text.ElideRight
                opacity: Math.max(0, Math.min(1, (notch.tabH - 12) / 10))
                color: root.cFg
                font.family: "Inter"
                font.pixelSize: 11
            }

            // the band itself: the only part that counts as "on the bar"
            Item {
                id: band
                width: parent.width
                height: shelfWin.bandH
                HoverHandler { onHoveredChanged: root.shelfHover(hovered) }

                // liquid lens under the hovered icon: each edge springs on its own, the leading edge
                // faster, so it stretches toward the target and snaps back
                Rectangle {
                    id: lens
                    property real edgeL: 0
                    property real edgeR: 0
                    property bool toRight: true
                    property real lead: 5.5
                    property real lag: 2.6
                    property color tint: root.hoverTile ? root.hoverTile.tint : root.cPrimary     // glows in the hovered app's colour
                    Behavior on tint { ColorAnimation { duration: root.ms(200) } }
                    // while invisible it jumps straight to the first target instead of sliding in from the last one
                    Behavior on edgeL { enabled: lens.opacity > 0.05; SpringAnimation { spring: lens.toRight ? lens.lag : lens.lead; damping: 0.24; epsilon: 0.05 } }
                    Behavior on edgeR { enabled: lens.opacity > 0.05; SpringAnimation { spring: lens.toRight ? lens.lead : lens.lag; damping: 0.24; epsilon: 0.05 } }
                    x: edgeL
                    width: Math.max(0, edgeR - edgeL)
                    y: 5
                    height: Math.max(0, band.height - 11)
                    radius: Math.min(12, height / 2)
                    opacity: root.hoverTile && shelfWin.morph > 0.6 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: root.ms(140) } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: root.alpha("#ffffff", 0.16) }
                        GradientStop { position: 1; color: root.alpha(lens.tint, 0.34) }
                    }
                    border.width: 1
                    border.color: root.alpha("#ffffff", 0.22)
                    function aim(t) {
                        const p = t.mapToItem(band, 0, 0)
                        const l = p.x + 2, r = p.x + t.width - 2
                        toRight = l >= edgeL
                        edgeL = l
                        edgeR = r
                    }
                    Connections {
                        target: root
                        function onHoverTileChanged() { if (root.hoverTile) lens.aim(root.hoverTile) }
                    }
                }

                Row {
                    id: icons
                    x: root.leftPad
                    y: (band.height - root.barH) / 2
                    height: root.barH
                    spacing: 0
                    Repeater {
                        model: root.groups
                        delegate: Row {
                            id: group
                            required property var modelData
                            required property int index
                            visible: list.count > 0
                            spacing: 0
                            Item {          // hairline between screens
                                visible: group.index > root.firstGroup
                                width: 11
                                height: root.barH
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 1
                                    height: parent.height * 0.42 * shelfWin.lip
                                    color: root.alpha(root.cFg, 0.22)
                                }
                            }
                            ListView {
                                id: list
                                height: root.barH
                                width: contentWidth
                                orientation: ListView.Horizontal
                                interactive: false
                                spacing: 0
                                model: group.modelData.windows
                                delegate: iconDelegate
                                add: Transition {
                                    NumberAnimation { property: "scale"; from: 0.2; to: 1; duration: root.ms(560); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.4 }
                                }
                                remove: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "scale"; to: 0.1; duration: root.ms(200); easing.type: Easing.InBack; easing.overshoot: 2 }
                                        NumberAnimation { property: "opacity"; to: 0; duration: root.ms(180) }
                                    }
                                }
                                displaced: Transition { NumberAnimation { property: "x"; duration: root.ms(420); easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                            }
                        }
                    }
                    Text {          // nothing open yet
                        visible: root.firstGroup < 0
                        height: root.barH
                        leftPadding: 4
                        verticalAlignment: Text.AlignVCenter
                        opacity: shelfWin.lip
                        text: i18n("No open windows")
                        color: root.cFgDim
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }

            // opens with a springy overshoot; closes at once, folding the icons back into the lip
            NumberAnimation {
                id: openMorph
                target: shelfWin
                property: "morph"
                to: 1
                duration: root.ms(300)
                easing.type: Easing.OutBack
                easing.overshoot: 2.4
            }
            SequentialAnimation {
                id: closeMorph
                NumberAnimation { target: shelfWin; property: "morph"; to: 0; duration: root.ms(190); easing.type: Easing.OutCubic }
                ScriptAction {
                    script: {
                        if (!root.shelfOpen) {
                            shelfWin.visible = false
                            root.shelfShown = false
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ fullscreen edge
    // Only exists while a fullscreen window covers this screen: rest on the top edge for
    // dwellDelay ms (a line fills meanwhile) and the bar drops in over the fullscreen window.
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
                ScriptAction { script: { root.openNow(); dwell.width = 0 } }
            }
        }
    }

    // ------------------------------------------------------------------ the bar: launchers
    fullRepresentation: Item {
        id: bar
        readonly property int iconSize: Math.max(16, Math.min(Math.round(Kirigami.Units.iconSizes.medium * root.uiScale), height - 12))
        Layout.fillHeight: true
        Layout.minimumWidth: launcherRow.implicitWidth
        Layout.preferredWidth: launcherRow.implicitWidth
        Layout.maximumWidth: launcherRow.implicitWidth

        DropArea {
            anchors.fill: parent
            onEntered: drag => { drag.accepted = drag.hasUrls && drag.urls.some(u => String(u).endsWith(".desktop")) }
            onDropped: drop => {
                for (const u of drop.urls)
                    if (String(u).endsWith(".desktop")) root.addLauncher(root.launcherUrlFor(u))
                drop.acceptProposedAction()
            }
        }
        Row {
            id: launcherRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Repeater {
                model: launchers
                delegate: Item {
                    id: lb
                    required property int index
                    required property var model
                    readonly property var info: root.infoFor(model.AppId, model.LauncherUrlWithoutIcon, root.running)
                    readonly property int count: info ? info.count : 0
                    readonly property bool focused: info ? info.active : false
                    readonly property bool attention: info ? info.attention : false
                    readonly property color tint: root.appTint(colors)     // the app's own colour, as in the top band
                    Kirigami.ImageColors { id: colors; source: lb.model.decoration }
                    property bool launching: false
                    width: bar.iconSize + 12
                    height: bar.height
                    onCountChanged: {
                        if (count > 0 && launching) { launching = false; arrive.restart() }
                    }

                    function launch(newInstance) {
                        const idx = launchers.mapToSource(launchers.index(lb.index, 0))
                        if (newInstance) launcherTasks.requestNewInstance(idx)
                        else launcherTasks.requestActivate(idx)
                        launching = lb.count === 0     // single-window apps never show a second one
                        launchTimeout.restart()
                    }
                    Timer { id: launchTimeout; interval: 6000; onTriggered: lb.launching = false }

                    Rectangle {
                        anchors.centerIn: parent
                        width: bar.iconSize + 8
                        height: width
                        radius: 8
                        color: root.alpha(root.cFg, ma.pressed ? 0.15 : ma.containsMouse ? 0.09 : 0)
                        Behavior on color { ColorAnimation { duration: root.ms(140) } }
                    }
                    Shape {          // "glow" mark
                        id: glow
                        anchors.centerIn: icon
                        width: bar.iconSize * 1.7
                        height: width
                        visible: root.cfg.launcherMark === "glow" && lb.count > 0
                        opacity: lb.focused ? 1 : 0.5
                        Behavior on opacity { NumberAnimation { duration: root.ms(220) } }
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: glow.width / 2; centerY: glow.height / 2; centerRadius: glow.width / 2
                                focalX: centerX; focalY: centerY
                                GradientStop { position: 0; color: root.alpha(lb.attention ? root.cRed : lb.tint, 0.6) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                            PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height }
                        }
                    }
                    Kirigami.Icon {
                        id: icon
                        anchors.centerIn: parent
                        width: bar.iconSize
                        height: width
                        source: lb.model.decoration
                        property real mag: ma.pressed ? 0.82 : ma.containsMouse ? 1.14 : 1
                        Behavior on mag { SpringAnimation { spring: 5; damping: 0.2; epsilon: 0.005 } }
                        scale: mag
                        transform: [
                            Translate {
                                y: ma.containsMouse && !ma.pressed ? -3 : 0
                                Behavior on y { SpringAnimation { spring: 5; damping: 0.22; epsilon: 0.05 } }
                            },
                            Scale { id: arriveScale; origin.x: icon.width / 2; origin.y: icon.height }
                        ]
                    }
                    SequentialAnimation {         // waiting for the app to show up
                        running: lb.launching && !root.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { target: icon; property: "opacity"; to: 0.35; duration: 480; easing.type: Easing.InOutSine }
                        NumberAnimation { target: icon; property: "opacity"; to: 1; duration: 480; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) icon.opacity = 1
                    }
                    SequentialAnimation {         // ...and a hop when it does
                        id: arrive
                        ParallelAnimation {
                            NumberAnimation { target: arriveScale; property: "yScale"; to: 1.3; duration: root.ms(120); easing.type: Easing.OutQuad }
                            NumberAnimation { target: arriveScale; property: "xScale"; to: 0.85; duration: root.ms(120) }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: arriveScale; property: "yScale"; to: 1; duration: root.ms(700); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
                            NumberAnimation { target: arriveScale; property: "xScale"; to: 1; duration: root.ms(700); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
                        }
                    }
                    Row {            // "dots" mark: one per window (max 3); dash = focused
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        spacing: 2
                        visible: root.cfg.launcherMark === "dots"
                        Repeater {
                            model: Math.min(lb.count, 3)
                            delegate: Rectangle {
                                required property int index
                                readonly property bool lead: index === 0 && lb.focused
                                width: lead ? 10 : 4
                                height: 4
                                radius: 2
                                color: lb.attention ? root.cRed : lead ? Qt.lighter(lb.tint, 1.1) : root.alpha(lb.tint, 0.75)
                                Behavior on width { SpringAnimation { spring: 4.5; damping: 0.22; epsilon: 0.05 } }
                                Behavior on color { ColorAnimation { duration: root.ms(200) } }
                                scale: 0
                                Component.onCompleted: popIn.start()
                                NumberAnimation on scale { id: popIn; running: false; to: 1; duration: root.ms(520); easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.4 }
                            }
                        }
                    }
                    Rectangle {      // "underline" mark
                        visible: root.cfg.launcherMark === "underline" && lb.count > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: lb.focused ? bar.iconSize * 0.9 : bar.iconSize * 0.45
                        height: 2
                        radius: 1
                        color: lb.attention ? root.cRed : lb.focused ? lb.tint : root.alpha(lb.tint, 0.6)
                        Behavior on width { SpringAnimation { spring: 4.5; damping: 0.22; epsilon: 0.05 } }
                    }

                    PlasmaCore.ToolTipArea {
                        anchors.fill: parent
                        mainText: lb.model.AppName || lb.model.display || ""
                        subText: lb.count ? i18np("1 window · middle-click for a new one", "%1 windows · middle-click for a new one", lb.count)
                                          : i18n("Not running")
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { menu.openRelative(); return }
                                if (mouse.button === Qt.MiddleButton || lb.count === 0) { lb.launch(mouse.button === Qt.MiddleButton); return }
                                root.actOnApp(lb.model.AppId, lb.model.LauncherUrlWithoutIcon)
                            }
                        }
                    }
                    PlasmaExtras.Menu {
                        id: menu
                        visualParent: lb
                        PlasmaExtras.MenuItem {
                            text: i18n("New window")
                            icon: "window-new"
                            onClicked: lb.launch(true)
                        }
                        PlasmaExtras.MenuItem {
                            text: i18n("Unpin from bar")
                            icon: "window-unpin"
                            onClicked: root.removeLauncherAt(lb.index)
                        }
                    }
                }
            }
        }
    }
}
