import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import Atom
import Atom.Native
import Rice

// The launcher: the bar's jewel (the accent pill) and, when it's clicked or Meta is pressed, a fullscreen
// home screen that opens out of it (Stage.qml, "Atom Home"): pages of rows (your pins and recents, games
// with Steam's art, apps by category) under a hero for the focused item, or the Theme page. Typing
// searches apps, settings, files and maths (KRunner), grouped by kind. Favourites are Plasma's shared
// ones (Kickoff's). Its own data (Steam's art, when apps were used): rice.py launcher-data.
// Meta opens it on the screen of the active window (X-Plasma-Provides: org.kde.plasma.launchermenu);
// Meta+Shift+W opens it on the wallpapers; the wheel over the jewel steps this screen's wallpaper.
// Open/closed lives in Atom.Shell (kind "launcher"), so every bar's launcher agrees on it.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    // the stage is one design size on every screen, scaled like the bar (rice settings bar_scale) and a
    // little larger than the bar's widgets: it has the whole screen
    readonly property real s: pal.uiScale
    readonly property real k: 1.15
    function px(n) { return Math.round(n * s * k) }

    // ------------------------------------------------------------------ open / close (Atom.Shell)
    readonly property var screens: Array.prototype.slice.call(Qt.application.screens)
    // until the item sits in its panel window, Screen.name reports the primary screen
    readonly property var myScreen: root.Window.window ? (screens.find(sc => sc.name === Screen.name) ?? null) : null
    readonly property string myScreenName: myScreen ? myScreen.name : ""
    // (also under the power page opened from it: still open, beneath)
    readonly property bool shown: Shell.screen === myScreenName && (Shell.kind === "launcher" || (!!Shell.under && Shell.under.kind === "launcher"))
    // the bar is docked (a window touches it or is maximized on its screen: its islands flatten, square):
    // Plasma's own panel item says so (Panel.qml touchingWindow, what the bar's looks switch on)
    readonly property var panelElement: { let c = root.parent; while (c) { if (c.hasOwnProperty("touchingWindow")) return c; c = c.parent } return null }
    readonly property bool docked: !!(panelElement && panelElement.touchingWindow)
    // the bar this jewel sits on (global logical px; Plasma places its panel windows itself, so Qt knows
    // where they are): the stage covers it with the wallpaper while open
    readonly property var panelWindow: root.Window.window
    readonly property rect panelRect: panelWindow ? Qt.rect(panelWindow.x, panelWindow.y, panelWindow.width, panelWindow.height)
                                                  : Qt.rect(0, 0, 0, 0)
    function close() { if (Shell.kind === "launcher") Shell.close("launcher") }
    // opening clears the desk: the windows fly into their pins and come back on close (Atom Windows)
    // (in every blur style, and under the power page too: the user, 2026-11-15)
    readonly property bool clearDesk: true
    // the power overlay (the shell's): every screen blurs, the session's actions big on this one
    function openPower(from) { Shell.open("power", Shell.screen || myScreenName, from || null) }
    // Meta (this applet holds the launcher shortcut): open on the screen of the active window, or close.
    // Plasma also expands the applet on activation (activationTogglesExpanded: false would make that
    // "always expand"): its popup is never wanted, so it folds straight back, before it can map (a
    // change made inside this handler is ignored: the next turn of the event loop)
    onExpandedChanged: {
        if (Shell.debug) console.warn("ATOM launcher expanded", root.expanded, Date.now() % 100000)
        if (root.expanded) Qt.callLater(() => { root.expanded = false })
        else if (Shell.kind === "launcher") Shell.refocus()
    }
    Connections {
        target: Plasmoid
        function onActivated() {
            if (Shell.kind === "launcher") { Shell.close("launcher"); return }
            // where the islands are (kwin/rice_islands: the pointer's screen unless fullscreen covers it)
            const scr = Shell.home(root.myScreenName)
            Shell.open("launcher", scr, Shell.island("launcher", scr), { input: "keys" })
        }
    }

    // ------------------------------------------------------------------ KRunner, replaced
    // Atom.Native's KRunner holds KRunner's place on the bus: its shortcut (Alt+Space, Alt+F2, Search; Alt+Shift+F2
    // with the clipboard) and typing on the desktop open the finder, the launcher's search alone (Stage's
    // search-only mode: no backdrop, no home, the windows stay). Every bar has a launcher: the one on the islands'
    // screen answers.
    Component.onCompleted: {
        KRunner.active = true
        root.style = root.styleWanted
        if (!Shell.quitting && !Shell.launcherHost) Shell.launcherHost = root
    }
    Component.onDestruction: {
        hostElect.stop()
        if (Shell.launcherHost === root) Shell.launcherHost = null
    }
    Timer {
        id: hostElect
        interval: 80
        onTriggered: if (!Shell.quitting && !Shell.launcherHost) Shell.launcherHost = root
    }
    Connections {
        target: Shell
        function onLauncherHostChanged() { if (!Shell.quitting && !Shell.launcherHost) hostElect.restart() }
    }
    readonly property bool isHost: Shell.launcherHost === root
    readonly property var host: Shell.launcherHost || root
    Connections {
        target: KRunner
        function onRequested(action, query) {
            const scr = Shell.home((Shell.bar && Shell.bar.pointer) || (root.screens[0] ? root.screens[0].name : ""))
            if (scr === root.myScreenName) root.find(action, query)
        }
    }
    function find(action, query) {
        if (action === "toggle" && Shell.kind === "launcher") { Shell.close("launcher"); return }
        if (action === "clipboard") {
            const reply = DBus.SessionBus.asyncCall({ service: "org.kde.klipper", path: "/klipper", iface: "org.kde.klipper.klipper",
                                                      member: "getClipboardContents", arguments: [] })
            reply.finished.connect(() => {
                const v = reply.isError ? "" : reply.value
                reply.destroy()
                root.find("query", String((v && typeof v === "object" && "value" in v) ? v.value : (v ?? "")).split("\n")[0])
            })
            return
        }
        const st = stages.objectAt(0)?.item
        if (Shell.kind === "launcher" && Shell.screen === myScreenName && st) { st.openSearch(query || ""); return }
        Shell.open("launcher", myScreenName, null, { searchOnly: true, query: query || "" })
    }

    RiceShell {
        id: sh
        onNewData: (source, data) => disconnectSource(source)
    }
    function run(cmd) { sh.connectSource(cmd + " #run") }      // a fixed set of commands: fixed names (RiceShell)

    // Atom Home's Theme page (the stage watches themeAsk), at a row: walls, colours or lights
    property int themeAsk: 0
    property string themeRow: ""
    function openTheme(row) { themeRow = row || ""; themeAsk++ }
    // Meta+Shift+W (bin/wallpapers.sh) posts "themeOpen" on Atom.Native Bus before opening the launcher:
    // read and clear in-process (zero shell fork on normal opens)
    onShownChanged: {
        if (root.shown && !root.stageReady) root.stageReady = true
        Qt.callLater(root.takeStyle)        // a launcher style chosen while it was open applies once it's closed
        if (root.shown) {
            const note = Bus.get("themeOpen")
            if (note && note.tab) {
                Bus.set("themeOpen", null)
                const age = note.at ? Date.now() / 1000 - Number(note.at) : 0
                if (age <= 5 && ["walls", "colours", "lights"].indexOf(note.tab) >= 0) {
                    const tab = note.tab
                    Qt.callLater(() => root.openTheme(tab))
                }
            }
        }
    }
    // the wheel over the emblem: this screen's next / previous wallpaper
    function stepWallpaper(d) { run('python3 "$HOME/.config/plasma-rice/rice.py" ' + (d > 0 ? "next" : "prev") + " --screen '" + Screen.name + "'") }

    // the launcher's own size (settings launcher.size, the Theme page's "Launcher size"), read live
    readonly property real homeSize: Prefs.launcherSize

    // the hero image: chosen here, or this screen's wallpaper
    readonly property var cfg: Plasmoid.configuration

    toolTipMainText: "Apps"
    toolTipSubText: "Search apps, settings, files and maths · Meta"
    preferredRepresentation: compactRepresentation

    // ------------------------------------------------------------------ models (shared across bars via Shell.launcherHost)
    // Only the host bar's launcher applet builds Kicker's RootModel, HomeModel, and (lazily on first
    // search) RunnerModel; other bars' launcher applets reuse them instead of loading 3x catalogs and
    // 27 KRunner plugins at login.
    Instantiator {
        id: rootModelInst
        active: root.isHost
        model: 1
        onObjectAdded: (index, object) => root.collectCategories(object)
        delegate: Kicker.RootModel {
            id: rm
            autoPopulate: false
            appletInterface: root
            flat: true
            sorted: true
            showSeparators: false
            showAllApps: true
            showAllAppsCategorized: false
            showTopLevelItems: false
            showRecentApps: true
            showRecentDocs: false
            showPowerSession: false
            highlightNewlyInstalledApps: false
            onRefreshed: root.collectCategories(rm)
            onCountChanged: root.collectCategories(rm)
            Component.onCompleted: {
                favoritesModel.initForClient("com.zinoxx.launcher")
                refresh()
            }
        }
    }
    readonly property var ownRootModel: rootModelInst.object
    readonly property var ownFavorites: ownRootModel ? ownRootModel.favoritesModel : null
    readonly property var favorites: host.ownFavorites

    // chips: All, Recent, then the menu's categories
    readonly property var catIcons: ({
        "all applications": "apps", "recent applications": "history", "development": "code",
        "education": "school", "games": "sports_esports", "graphics": "palette", "internet": "language",
        "multimedia": "play_circle", "office": "description", "science": "science", "settings": "tune",
        "system": "settings", "utilities": "construction", "help": "help", "lost & found": "inventory_2"
    })
    property var ownCategories: []
    readonly property var categories: host.ownCategories
    property int category: 0
    function collectCategories(src) {
        const R = src || ownRootModel
        if (!R) return
        const out = []
        let all = null, recent = null
        for (let i = 0; i < R.count; i++) {
            const m = R.modelForRow(i)
            const label = String(R.data(R.index(i, 0), Qt.DisplayRole) || "")
            if (!m || !label) continue                      // separator
            if (m.description === "KICKER_ALL_MODEL") all = { label: "All", icon: "apps", model: m }
            else if (i === 0) recent = { label: "Recent", icon: "history", model: m }
            else out.push({ label: label, icon: catIcons[label.toLowerCase()] || "folder", model: m })
        }
        ownCategories = [all, recent].filter(c => c && c.model.count > 0).concat(out)
        if (category >= ownCategories.length) category = 0
    }
    readonly property var browseModel: categories.length ? categories[category].model : null

    // One shared HomeModel for every screen's Stage (pages, Steam art, usage, and AppsPage's byCat)
    Instantiator {
        id: homeModelInst
        active: root.isHost && !!root.ownRootModel
        model: 1
        delegate: HomeModel { launcher: root }
    }
    readonly property var ownHomeModel: homeModelInst.object
    readonly property var homeModel: host.ownHomeModel

    // Lazy KRunner: zero runner plugins load at login; instantiated once on the host upon first search
    property bool runnerWanted: false
    property string hostQuery: ""
    function ensureRunner() {
        if (isHost) runnerWanted = true
        else if (host && host !== root) host.ensureRunner()
    }
    Timer {
        id: runnerWarm
        interval: 4500
        running: root.isHost && !root.runnerWanted && !Shell.quitting
        onTriggered: root.ensureRunner()
    }
    Instantiator {
        id: runnerInst
        active: root.isHost && root.runnerWanted
        model: 1
        delegate: Kicker.RunnerModel {
            appletInterface: root
            favoritesModel: root.ownFavorites
            mergeResults: false
            query: root.hostQuery
            runners: ["krunner_services", "krunner_systemsettings", "calculator", "unitconverter",
                      "krunner_sessions", "krunner_powerdevil", "locations", "baloosearch", "krunner_webshortcuts"]
        }
    }
    Kicker.DragHelper { id: dragHelper; dragIconSize: Kirigami.Units.iconSizes.medium }
    // for the stage (Stage.qml)
    readonly property var ownRunner: runnerInst.object
    readonly property var runnerModel: host.ownRunner
    readonly property var kickerDrag: dragHelper
    readonly property var menu: ctx

    property string query: ""
    onQueryChanged: {
        if (query !== "") ensureRunner()
        if (host) host.hostQuery = query
        selGroup = 0; selRow = 0; Qt.callLater(fixSelection)
        awaiting = query !== ""; awaitCap.restart()
    }
    // KRunner is still working on this query. The model debounces before it starts, so a query
    // counts as pending from the moment it's typed until KRunner says it's done (capped, in case
    // that never comes): no "nothing found" flash while results are on their way
    property bool awaiting: false
    Timer { id: awaitCap; interval: 4000; onTriggered: root.awaiting = false }
    readonly property bool searching: query !== "" && (awaiting || !!(runnerModel && runnerModel.querying))

    // keyboard selection in the results: (group, row), kept on a row that exists
    property int selGroup: 0
    property int selRow: 0
    function groupCount(g) { const m = runnerModel ? runnerModel.modelForRow(g) : null; return m ? m.count : 0 }
    function fixSelection() {
        if (!runnerModel) return
        if (groupCount(selGroup) > selRow) return
        for (let g = 0; g < runnerModel.count; g++)
            if (groupCount(g) > 0) { selGroup = g; selRow = 0; return }
    }
    function moveSelection(d) {
        if (!runnerModel) return
        fixSelection()
        let g = selGroup, r = selRow + d
        while (g >= 0 && g < runnerModel.count) {
            if (r >= 0 && r < groupCount(g)) { selGroup = g; selRow = r; return }
            g += d
            r = d > 0 ? 0 : groupCount(g) - 1
        }
    }
    function activateSelection() {
        if (!runnerModel) return
        fixSelection()
        const m = runnerModel.modelForRow(selGroup)
        if (m && selRow < m.count) launch(m, selRow)
    }
    Connections {
        target: root.runnerModel
        enabled: !!root.runnerModel
        function onCountChanged() { Qt.callLater(root.fixSelection) }
        function onQueryFinished() { root.awaiting = false; Qt.callLater(root.fixSelection) }
    }

    function launch(model, row) {
        model.trigger(row, "", null)
        root.close()
    }
    function isFavorite(id) { return !!id && !!favorites && favorites.isFavorite(id) }
    function toggleFavorite(id) {
        if (!id || !favorites) return
        if (favorites.isFavorite(id)) favorites.removeFavorite(id)
        else favorites.addFavorite(id)
    }

    function greeting(h) { return h < 5 ? "Up late," : h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening," }

    // battery saver (plasma-rice/bin/battery-saver.py): its switch on the hero card shows only while the
    // laptop runs on battery. Plasma's power engine follows UPower's signals, so nothing is polled. When
    // the charger comes back the saver ends by itself (the lights; PowerDevil picks the AC profile)
    P5Support.DataSource {
        engine: "powermanagement"
        connectedSources: ["Battery"]
        onNewData: (source, data) => root.batt = data
    }
    property var batt: ({})
    readonly property bool unplugged: batt["Has Battery"] === true && batt["State"] === "Discharging"
    readonly property bool plugged: batt["Has Battery"] === true && !!batt["State"] && batt["State"] !== "Discharging"
    WatchedJson {
        id: saverFile
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.local/state/rice/battery-saver.json"
        onChanged: root.saverBusy = false
    }
    readonly property bool saverOn: !!(saverFile.value && saverFile.value.on)
    property bool saverBusy: false          // a switch sent, until the file changes
    property bool saverWant: false
    readonly property bool saverShown: saverBusy ? saverWant : saverOn
    function setSaver(on) {
        saverWant = on; saverBusy = true; saverTimeout.restart()
        run('python3 "$HOME/.config/plasma-rice/bin/battery-saver.py" ' + (on ? "on" : "off"))
    }
    Timer { id: saverTimeout; interval: 8000; onTriggered: root.saverBusy = false }    // it was already so
    readonly property bool saverStale: plugged && saverOn
    onSaverStaleChanged: if (saverStale) run('python3 "$HOME/.config/plasma-rice/bin/battery-saver.py" off --plugged')

    // ------------------------------------------------------------------ right-click menu
    PlasmaExtras.Menu {
        id: ctx
        property var target: null          // { model, row, favoriteId }
        // item: the delegate, whose `model` has Kicker's roles by name (favoriteId, actionList): no role
        // numbers, which are Kicker's private enum and can move in a Plasma release
        function openFor(item, model, row) {
            clearMenuItems()
            const roles = item.roles ?? item.model ?? {}      // a HomeTile carries them as roles
            const fav = roles.favoriteId
            target = { model: model, row: row, favoriteId: fav }
            visualParent = item
            if (fav) addMenuItem(menuItem.createObject(ctx, {
                text: root.isFavorite(fav) ? "Unpin from launcher" : "Pin to launcher",
                icon: root.isFavorite(fav) ? "window-unpin" : "window-pin", act: { fav: true } }))
            const acts = roles.actionList || []
            let shown = fav ? 1 : 0, gap = shown > 0       // a line after "Pin", and between action groups
            for (const a of acts) {
                if (a.type === "separator" || a.type === "title") { gap = shown > 0; continue }
                if (/favorite/i.test(a.actionId || "")) continue
                if (gap) addMenuItem(menuItem.createObject(ctx, { separator: true }))
                gap = false
                shown++
                addMenuItem(menuItem.createObject(ctx, { text: a.text, icon: a.icon || "", enabled: !a.disabled, act: a }))
            }
            open(0, item.height + Math.round(10 * root.s))      // under it (the tile it belongs to stays in sight)
        }
    }
    Component {
        id: menuItem
        PlasmaExtras.MenuItem {
            property var act: null
            onClicked: {
                const t = ctx.target
                if (!t || !act) return
                if (act.fav) { root.toggleFavorite(t.favoriteId); return }
                t.model.trigger(t.row, act.actionId, act.actionArgument)
                root.close()
            }
        }
    }

    // ------------------------------------------------------------------ panel: the emblem
    compactRepresentation: Island {
        id: compact
        kind: "launcher"
        args: ({ input: "pointer" })        // (opened by a click: in the pointer's look, no key hints)
        // a pill, not a square: the bar's one wide, accent-filled island (panel/build.py launcher_style)
        Layout.minimumWidth: Math.round(emblem.implicitWidth * 1.8 * root.s)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        property real acc: 0
        onWheel: wheel => {
            acc += wheel.angleDelta.y
            if (Math.abs(acc) >= 120) { root.stepWallpaper(acc < 0 ? 1 : -1); acc = 0 }
        }
        Emblem {
            id: emblem
            anchors.centerIn: parent
            hovered: compact.containsMouse
            pressed: compact.pressed
            open: root.shown
            scale: root.s * 1.12       // vector, stays crisp
            // light on the accent fill: a white core and orbits with a breath of the tertiary,
            // candy satellites
            c1: "#ffffff"
            c2: C.mix(pal.tertiary, "#ffffff", 0.55)
            c3: C.mix(pal.red, "#ffffff", 0.15)
            c4: C.mix(pal.teal, "#ffffff", 0.15)
            glow: "#ffffff"
        }
        // under the pointer it speaks the launcher's focus language: the white ring its tiles wear (the
        // island's own glow brightens with it: panel launcher_style "hovered"). The ring traces the island
        // as it is: a corner notch (atom/panel.py notch + corner), flush with the screen's left and bottom
        // edges, so it runs along the top and the right side only, round only at the top right; square when
        // the bar is docked under a window (its looks flatten the islands: radius 0). The island's glass is
        // this item's rect (Colorizer moves the applet by its margins).
        Shape {
            id: ring
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property real sw: Math.max(2, Math.round(2.5 * root.s))
            readonly property real r: Math.max(0, cornerR - sw / 2)       // concentric with the island's corner
            property real cornerR: root.docked ? 0 : Tokens.radius.md
            Behavior on cornerR { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }    // (the bar's morph: panel DOCK_MS)
            opacity: compact.containsMouse && !root.shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(compact.containsMouse ? 240 : 380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            ShapePath {
                strokeColor: C.alpha(pal.light ? pal.fg : "#ffffff", 0.95)
                strokeWidth: ring.sw
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.MiterJoin
                startX: 0; startY: ring.sw / 2
                PathLine { x: ring.width - ring.sw / 2 - ring.r; y: ring.sw / 2 }
                PathArc { x: ring.width - ring.sw / 2; y: ring.sw / 2 + ring.r; radiusX: ring.r; radiusY: ring.r }
                PathLine { x: ring.width - ring.sw / 2; y: ring.height }
            }
        }
    }

    // never shown (activation and clicks open the stage), but a panel applet draws nothing without one
    fullRepresentation: Item {}
    signal stageEntered()               // the stage's content starts coming in (the grid's apps follow)

    // ------------------------------------------------------------------ the stage (fullscreen, its own surface)
    // One per screen, in the chosen style (settings launcher.style: "simplified" = Stage.qml, or any folder
    // styles/NAME/ with a Stage.qml). Only that style's files are compiled and made: other styles cost nothing.
    // A new choice applies while the launcher is closed (never under an open one); a style that fails to load
    // falls back to simplified.
    readonly property string styleWanted: Shell.styleOverride || Prefs.launcherStyle      // (the override: nested tests only)
    property string style: ""               // what the stages show: set at start, then only by takeStyle (never a binding:
                                            // a binding swapped the launcher the moment the setting changed, open or not)
    // the swap waits for the stage to have closed (its closing animation plays out)
    function takeStyle() {
        if (root.shown || root.style === root.styleWanted) return
        const st = stages.objectAt(0) ? stages.objectAt(0).item : null
        if (st && st.phase && st.phase !== "closed") { styleWait.restart(); return }
        root.style = root.styleWanted
        for (let i = 0; i < stages.count; i++) {
            const l = stages.objectAt(i)
            if (l && String(l.source) !== String(root.styleUrl(root.style)))
                l.setSource(root.styleUrl(root.style), { screenObj: l.modelData, launcher: root, rice: pal, account: me })
        }
        if (root.restyling && root.restyling.style === root.style) {      // asked from the Theme page: open the new one there
            const r = root.restyling
            root.restyling = null
            restyleTimeout.stop()
            Qt.callLater(() => { Shell.open("launcher", r.screen, Shell.island("launcher", r.screen)); Windows.restore(r.screen, "restyle") })
        }
    }
    Timer { id: styleWait; interval: 80; onTriggered: root.takeStyle() }
    onStyleWantedChanged: takeStyle()
    // switching from the Theme page (its "Launcher style"; ThemeModel writes the setting): this launcher closes and the
    // other opens on the same screen once the setting has arrived; the windows stay away in between
    property var restyling: null            // { style, screen }
    function restyle(style) {
        const scr = Shell.screen || root.myScreenName
        root.restyling = { style: style, screen: scr }
        Windows.clear(scr, "restyle")
        restyleTimeout.restart()
        if (Shell.debug) Shell.styleOverride = style      // (the nested tests write no settings: the override stands in)
        root.close()
    }
    Timer {     // the setting never came (the command failed): the windows come back
        id: restyleTimeout; interval: 5000
        onTriggered: if (root.restyling) { Windows.restore(root.restyling.screen, "restyle"); root.restyling = null }
    }
    function styleUrl(name) { return Qt.resolvedUrl(name === "simplified" ? "Stage.qml" : "styles/" + name + "/Stage.qml") }
    // Defer Stage creation until panels settle (~1.2 s + 250 ms stagger per screen, or immediately if
    // the launcher is opened first): avoids transient-screen tears at login (QQmlVMEMetaObject errors)
    // and keeps login off the critical path.
    property bool stageReady: false
    readonly property int screenIdx: myScreen ? Math.max(0, screens.indexOf(myScreen)) : 0
    Timer {
        id: stageDefer
        interval: 1200 + root.screenIdx * 250
        running: !root.stageReady && !!root.myScreen
        onTriggered: root.stageReady = true
    }
    Instantiator {
        id: stages
        model: root.stageReady && root.myScreen ? [root.myScreen] : []
        delegate: Loader {
            id: stageLoader
            required property var modelData
            // (no functions of its own: a delegate being dropped while the screen settles ran one in a dead context)
            Component.onCompleted: setSource(root.styleUrl(root.style || root.styleWanted), { screenObj: modelData, launcher: root, rice: pal, account: me })
            // (a new style: takeStyle reloads the live ones; a handler here ran in a dead delegate's context at start)
            onStatusChanged: if (status === Loader.Error && source !== root.styleUrl("simplified")) {
                console.warn("launcher: the style", root.style, "didn't load; simplified instead")
                setSource(root.styleUrl("simplified"), { screenObj: modelData, launcher: root, rice: pal, account: me })
            }
        }
    }
}
