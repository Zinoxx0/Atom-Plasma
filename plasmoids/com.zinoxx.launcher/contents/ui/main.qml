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
import "Rice"
import "Rice/Color.js" as C

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
    readonly property bool shown: Shell.kind === "launcher" && Shell.screen === myScreenName
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
    readonly property bool clearDesk: true
    // the power overlay (the shell's): every screen blurs, the session's actions big on this one
    function openPower(from) { Shell.open("power", Shell.screen || myScreenName, from || null) }
    // Meta (this applet holds the launcher shortcut): open on the screen of the active window, or close.
    // Plasma also expands the applet on activation (activationTogglesExpanded: false would make that
    // "always expand"): its popup is never wanted, so it folds straight back, before it can map (a
    // change made inside this handler is ignored: the next turn of the event loop)
    onExpandedChanged: {
        if (Shell.debug) console.warn("ATOM launcher expanded", expanded, Date.now() % 100000)
        if (expanded) Qt.callLater(() => { root.expanded = false })
    }
    Connections {
        target: Plasmoid
        function onActivated() {
            if (Shell.kind === "launcher") { Shell.close("launcher"); return }
            // where the islands are (kwin/rice_islands: the pointer's screen unless fullscreen covers it)
            const scr = Shell.home(root.myScreenName)
            Shell.open("launcher", scr, Shell.island("launcher", scr))
        }
    }

    // ------------------------------------------------------------------ KRunner, replaced
    // Atom.Native's KRunner holds KRunner's place on the bus: its shortcut (Alt+Space, Alt+F2, Search; Alt+Shift+F2
    // with the clipboard) and typing on the desktop open the finder, the launcher's search alone (Stage's
    // search-only mode: no backdrop, no home, the windows stay). Every bar has a launcher: the one on the islands'
    // screen answers.
    Component.onCompleted: KRunner.active = true
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
        const st = stages.objectAt(0)
        if (Shell.kind === "launcher" && Shell.screen === myScreenName && st) { st.openSearch(query || ""); return }
        Shell.open("launcher", myScreenName, null, { searchOnly: true, query: query || "" })
    }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#mode") >= 0) {      // the note names the Theme page's tab to open on
                const tab = String(data["stdout"] ?? "").trim()
                if (["walls", "colours", "lights"].indexOf(tab) >= 0) root.openTheme(tab)
            }
            disconnectSource(source)
        }
    }
    function run(cmd) { sh.connectSource(cmd + " #run") }      // a fixed set of commands: fixed names (RiceShell)

    // what the right side shows: the apps, or the wallpapers (to set them, or to pick the hero)
    property string view: "apps"
    property string wallMode: "desktop"
    function openWallpapers(mode, tab) {
        wallMode = mode; view = "walls"
        if (tab && wallsPane) wallsPane.tab = tab
        else openTab = tab || ""
    }
    // Atom Home's Theme page (the stage watches themeAsk), at a row: walls, colours or lights
    property int themeAsk: 0
    property string themeRow: ""
    function openTheme(row) { themeRow = row || ""; themeAsk++ }
    // the detailed Theme panels (Fine-tune) once its Loader (inside the popup, out of this scope's reach) has made it
    property Item wallsPane: null
    property string openTab: ""         // a tab asked for before the Theme page was first built
    // Meta+Shift+W (~/.local/share/applications/net.local.rice-wallpapers.desktop) leaves a note,
    // then opens the launcher: read it once per opening
    onShownChanged: {
        if (root.shown) sh.connectSource('f="$HOME/.local/state/rice/launcher-open"; cat "$f" 2>/dev/null; rm -f "$f" #mode')
        else { view = "apps"; wallMode = "desktop" }
    }
    // the wheel over the emblem: this screen's next / previous wallpaper
    function stepWallpaper(d) { run('python3 "$HOME/.config/plasma-rice/rice.py" ' + (d > 0 ? "next" : "prev") + " --screen '" + Screen.name + "'") }

    // the hero image: chosen here, or this screen's wallpaper
    readonly property var cfg: Plasmoid.configuration

    toolTipMainText: "Apps"
    toolTipSubText: "Search apps, settings, files and maths · Meta"
    preferredRepresentation: compactRepresentation

    // ------------------------------------------------------------------ models
    Kicker.RootModel {
        id: rootModel
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
        onRefreshed: root.collectCategories()
        onCountChanged: root.collectCategories()
        Component.onCompleted: {
            favoritesModel.initForClient("com.zinoxx.launcher")
            refresh()
        }
    }
    readonly property var favorites: rootModel.favoritesModel

    // chips: All, Recent, then the menu's categories
    readonly property var catIcons: ({
        "all applications": "apps", "recent applications": "history", "development": "code",
        "education": "school", "games": "sports_esports", "graphics": "palette", "internet": "language",
        "multimedia": "play_circle", "office": "description", "science": "science", "settings": "tune",
        "system": "settings", "utilities": "construction", "help": "help", "lost & found": "inventory_2"
    })
    property var categories: []
    property int category: 0
    function collectCategories() {
        const out = [], R = rootModel
        let all = null, recent = null
        for (let i = 0; i < R.count; i++) {
            const m = R.modelForRow(i)
            const label = String(R.data(R.index(i, 0), Qt.DisplayRole) || "")
            if (!m || !label) continue                      // separator
            if (m.description === "KICKER_ALL_MODEL") all = { label: "All", icon: "apps", model: m }
            else if (i === 0) recent = { label: "Recent", icon: "history", model: m }
            else out.push({ label: label, icon: catIcons[label.toLowerCase()] || "folder", model: m })
        }
        categories = [all, recent].filter(c => c && c.model.count > 0).concat(out)
        if (category >= categories.length) category = 0
    }
    readonly property var browseModel: categories.length ? categories[category].model : null

    Kicker.RunnerModel {
        id: runner
        appletInterface: root
        favoritesModel: rootModel.favoritesModel
        mergeResults: false
        runners: ["krunner_services", "krunner_systemsettings", "calculator", "unitconverter",
                  "krunner_sessions", "krunner_powerdevil", "locations", "baloosearch", "krunner_webshortcuts"]
    }
    Kicker.DragHelper { id: dragHelper; dragIconSize: Kirigami.Units.iconSizes.medium }
    // for the stage (Stage.qml)
    readonly property var runnerModel: runner
    readonly property var kickerDrag: dragHelper
    readonly property var menu: ctx

    property string query: ""
    onQueryChanged: {
        runner.query = query; selGroup = 0; selRow = 0; Qt.callLater(fixSelection)
        awaiting = query !== ""; awaitCap.restart()
    }
    // KRunner is still working on this query. The model debounces before it starts, so a query
    // counts as pending from the moment it's typed until KRunner says it's done (capped, in case
    // that never comes): no "nothing found" flash while results are on their way
    property bool awaiting: false
    Timer { id: awaitCap; interval: 4000; onTriggered: root.awaiting = false }
    readonly property bool searching: query !== "" && (awaiting || runner.querying)

    // keyboard selection in the results: (group, row), kept on a row that exists
    property int selGroup: 0
    property int selRow: 0
    function groupCount(g) { const m = runner.modelForRow(g); return m ? m.count : 0 }
    function fixSelection() {
        if (groupCount(selGroup) > selRow) return
        for (let g = 0; g < runner.count; g++)
            if (groupCount(g) > 0) { selGroup = g; selRow = 0; return }
    }
    function moveSelection(d) {
        fixSelection()
        let g = selGroup, r = selRow + d
        while (g >= 0 && g < runner.count) {
            if (r >= 0 && r < groupCount(g)) { selGroup = g; selRow = r; return }
            g += d
            r = d > 0 ? 0 : groupCount(g) - 1
        }
    }
    function activateSelection() {
        fixSelection()
        const m = runner.modelForRow(selGroup)
        if (m && selRow < m.count) launch(m, selRow)
    }
    Connections {
        target: runner
        function onCountChanged() { Qt.callLater(root.fixSelection) }
        function onQueryFinished() { root.awaiting = false; Qt.callLater(root.fixSelection) }
    }

    function launch(model, row) {
        model.trigger(row, "", null)
        root.close()
    }
    function isFavorite(id) { return !!id && favorites.isFavorite(id) }
    function toggleFavorite(id) {
        if (!id) return
        if (favorites.isFavorite(id)) favorites.removeFavorite(id)
        else favorites.addFavorite(id)
    }

    function greeting(h) { return h < 5 ? "Up late," : h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening," }

    // battery saver (plasma-rice/battery-saver.py): its switch on the hero card shows only while the
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
        run('python3 "$HOME/.config/plasma-rice/battery-saver.py" ' + (on ? "on" : "off"))
    }
    Timer { id: saverTimeout; interval: 8000; onTriggered: root.saverBusy = false }    // it was already so
    readonly property bool saverStale: plugged && saverOn
    onSaverStaleChanged: if (saverStale) run('python3 "$HOME/.config/plasma-rice/battery-saver.py" off --plugged')

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
    Instantiator {
        id: stages
        model: root.myScreen ? [root.myScreen] : []
        delegate: Stage {
            required property var modelData
            screenObj: modelData
            launcher: root
            rice: pal
            account: me
        }
    }
}
