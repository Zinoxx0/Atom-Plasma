import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import "Rice"
import "Rice/Color.js" as C
import "Rice/SessionActions.js" as Session

// A calm, wallpaper-lit app launcher in the style of the session menu. Left: a hero card of
// this screen's wallpaper (or a picture chosen with its pencil, placed by hand) with the time,
// a greeting and session shortcuts. Right: a search field over pinned apps, category chips and
// the app grid, or the wallpaper picker (WallpaperPane). Typing searches apps, settings, files
// and maths (KRunner), grouped by kind. Favourites are Plasma's shared ones (Kickoff's).
// Meta opens it (X-Plasma-Provides: org.kde.plasma.launchermenu); Meta+Shift+W opens it on the
// wallpapers; the wheel over the emblem steps this screen's wallpaper.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    // the popup is one design size on every screen, scaled like the bar (rice settings bar_scale)
    readonly property real s: pal.uiScale
    function px(n) { return Math.round(n * s) }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#mode") >= 0) {      // the note names the Theme page's tab to open on
                const tab = String(data["stdout"] ?? "").trim()
                if (["walls", "colours", "lights"].indexOf(tab) >= 0) root.openWallpapers("desktop", tab)
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
    // the Theme page once its Loader (inside the popup, out of this scope's reach) has made it
    property Item wallsPane: null
    property string openTab: ""         // a tab asked for before the Theme page was first built
    // Meta+Shift+W (~/.local/share/applications/net.local.rice-wallpapers.desktop) leaves a note,
    // then opens the launcher: read it once per opening
    onExpandedChanged: {
        if (root.expanded) sh.connectSource('f="$HOME/.local/state/rice/launcher-open"; cat "$f" 2>/dev/null; rm -f "$f" #mode')
        else { view = "apps"; wallMode = "desktop" }
    }
    // the wheel over the emblem: this screen's next / previous wallpaper
    function stepWallpaper(d) { run('python3 "$HOME/.config/plasma-rice/rice.py" ' + (d > 0 ? "next" : "prev") + " --screen '" + Screen.name + "'") }

    // the hero image: chosen here, or this screen's wallpaper
    readonly property var cfg: Plasmoid.configuration
    function setHero(path) { cfg.heroImage = path || "" }
    FileDialog {
        id: browseDialog
        title: "Choose the hero image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif)", "All files (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        // the popup stays open while the dialog has the focus
        onVisibleChanged: root.hideOnWindowDeactivate = !visible
        onAccepted: root.setHero(String(selectedFile).replace(/^file:\/\//, ""))
    }

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
        root.expanded = false
    }
    function isFavorite(id) { return !!id && favorites.isFavorite(id) }
    function toggleFavorite(id) {
        if (!id) return
        if (favorites.isFavorite(id)) favorites.removeFavorite(id)
        else favorites.addFavorite(id)
    }

    // session shortcuts in the hero card: the session menu's list (Rice/SessionActions.js); restart and
    // shut down go through the rice logout screen (org.kde.LogoutPrompt)
    readonly property var sessionActions: Session.pick(["lock", "sleep", "reboot", "shutdown"])
    function greeting(h) { return h < 5 ? "Up late," : h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening," }

    // ------------------------------------------------------------------ right-click menu
    PlasmaExtras.Menu {
        id: ctx
        property var target: null          // { model, row, favoriteId }
        // item: the delegate, whose `model` has Kicker's roles by name (favoriteId, actionList): no role
        // numbers, which are Kicker's private enum and can move in a Plasma release
        function openFor(item, model, row) {
            clearMenuItems()
            const roles = item.model ?? {}
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
            openRelative()
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
                root.expanded = false
            }
        }
    }

    // ------------------------------------------------------------------ panel: the emblem
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        // a pill, not a square: the bar's one wide, accent-filled island (panel/build.py launcher_style)
        Layout.minimumWidth: Math.round(emblem.implicitWidth * 1.8 * root.s)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
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
            open: root.expanded
            scale: root.s * 1.12       // vector, stays crisp
            // light on the accent fill: a white core and orbits with a breath of the tertiary,
            // candy satellites
            c1: "#ffffff"
            c2: C.mix(pal.tertiary, "#ffffff", 0.55)
            c3: C.mix(pal.red, "#ffffff", 0.15)
            c4: C.mix(pal.teal, "#ffffff", 0.15)
            glow: "#ffffff"
        }
    }

    // ------------------------------------------------------------------ popup
    fullRepresentation: FocusScope {
        id: pop
        // fixed: Plasma would otherwise restore a different remembered size per screen
        readonly property int w: root.px(880)
        readonly property int h: root.px(580)
        Layout.preferredWidth: w
        Layout.preferredHeight: h
        Layout.minimumWidth: w
        Layout.minimumHeight: h
        Layout.maximumWidth: w
        Layout.maximumHeight: h
        focus: true

        property date now: new Date()
        Timer { running: root.expanded; repeat: true; interval: 5000; triggeredOnStart: true; onTriggered: pop.now = new Date() }

        // fresh every time it opens: empty query, All, first app, the grid fades in
        signal entered()
        Connections {
            target: root
            function onExpandedChanged() {
                if (!root.expanded) return
                search.text = ""
                root.category = 0
                browse.gridView.currentIndex = -1
                browse.gridView.positionViewAtBeginning()
                browse.pinnedView.positionViewAtBeginning()
                Qt.callLater(() => search.forceActiveFocus())
                pop.entered()
            }
        }
        Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())

        PopupIn {
            anchors.fill: parent
            active: root.expanded
            ricePalette: pal

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.space.lg

                // ------------------------------------------------------ hero card
                // It sits the dialog's margin (space.sm) in from the edge, so its corners are
                // concentric with the popup's: lg - sm.
                HeroCard {
                    id: hero
                    Layout.preferredWidth: root.px(248)
                    Layout.fillHeight: true
                    launcher: root
                    rice: pal
                    account: me
                    now: pop.now
                    onBrowseImage: browseDialog.open()
                }

                // ------------------------------------------------------ search + content, or wallpapers
                Item {
                    id: rightSide
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: Tokens.space.lg
                    Layout.rightMargin: Tokens.space.lg
                    Layout.bottomMargin: Tokens.space.lg

                ColumnLayout {
                    id: appsPane
                    anchors.fill: parent
                    spacing: Tokens.space.md
                    // the two views trade places with a fade and a short slide
                    opacity: root.view === "apps" ? 1 : 0
                    visible: opacity > 0
                    enabled: root.view === "apps"
                    Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                    transform: Translate { x: root.view === "apps" ? 0 : -root.px(16); Behavior on x { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.move } } }

                    // search, and the way to the wallpapers
                    RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    Rectangle {
                        id: searchBox
                        Layout.fillWidth: true
                        implicitHeight: root.px(46)
                        radius: Tokens.radius.md
                        color: C.alpha(pal.fg, search.activeFocus ? 0.09 : 0.06)
                        border.width: search.activeFocus ? 1.5 : 1
                        border.color: search.activeFocus ? C.alpha(pal.primary, 0.75) : C.alpha(pal.edge, Tokens.alpha.outline)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: search.forceActiveFocus() }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space.lg
                            anchors.rightMargin: Tokens.space.md
                            spacing: Tokens.space.md
                            Text {
                                text: "search"
                                color: search.activeFocus ? pal.primary : pal.muted
                                font.family: Tokens.font.icons
                                font.pixelSize: root.px(22)
                                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                TextInput {
                                    id: search
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: pal.fg
                                    selectionColor: pal.primary
                                    selectedTextColor: pal.onPrimary
                                    font.family: Tokens.font.ui
                                    font.pixelSize: root.px(Tokens.size.title)
                                    clip: true
                                    focus: true
                                    onTextChanged: root.query = text
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Escape) {
                                            if (text) text = ""; else root.expanded = false
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && root.query)) {
                                            // with a query the arrows walk the results; without, Down enters the grid
                                            // (Tab then follows the focus chain: pinned, chips, grid, session)
                                            if (root.query) root.moveSelection(1)
                                            else { browse.gridView.forceActiveFocus(Qt.TabFocusReason); if (browse.gridView.currentIndex < 0) browse.gridView.currentIndex = 0 }
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Up) {
                                            if (root.query) root.moveSelection(-1)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            if (root.query) root.activateSelection()
                                            else if (browse.gridView.currentIndex >= 0) root.launch(root.browseModel, browse.gridView.currentIndex)
                                            event.accepted = true
                                        }
                                    }
                                }
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: !search.text && !search.preeditText
                                    text: "Search apps, settings, files… or do maths"
                                    color: pal.muted
                                    font: search.font
                                    elide: Text.ElideRight
                                }
                            }
                            // KRunner at work: stepped dots; otherwise the key hint
                            Busy {
                                visible: root.searching
                                running: visible
                                implicitWidth: root.px(16); implicitHeight: implicitWidth
                                color: pal.primary
                            }
                            Rectangle {
                                visible: !root.searching
                                implicitHeight: root.px(22)
                                implicitWidth: hint.implicitWidth + Tokens.space.md + 2
                                radius: Tokens.radius.xs
                                color: C.alpha(pal.fg, 0.07)
                                border.width: 1
                                border.color: C.alpha(pal.edge, Tokens.alpha.outline)
                                Text {
                                    id: hint
                                    anchors.centerIn: parent
                                    text: root.query ? "esc" : "meta"
                                    color: pal.muted
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: root.px(Tokens.size.caption)
                                }
                            }
                        }
                    }

                    IconButton {
                        palette: pal
                        icon: "palette"
                        tooltip: "Theme: wallpapers and colours"
                        size: root.px(46)
                        onClicked: root.openWallpapers("desktop")
                    }
                    }

                    // ---------------------------------------------- browse: pinned, chips, grid
                    AppBrowse {
                        id: browse
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.query
                        launcher: root
                        rice: pal
                        menu: ctx
                        kickerDrag: dragHelper
                        searchField: search
                    }

                    // ---------------------------------------------- results
                    SearchResults {
                        id: resultsArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !!root.query
                        launcher: root
                        rice: pal
                        menu: ctx
                        runnerModel: runner
                    }
                }

                // built the first time it's opened, then kept
                Loader {
                    id: walls
                    anchors.fill: parent
                    active: root.view === "walls" || item !== null
                    opacity: root.view === "walls" ? 1 : 0
                    visible: opacity > 0
                    enabled: root.view === "walls"
                    Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                    transform: Translate { x: root.view === "walls" ? 0 : root.px(16); Behavior on x { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.move } } }
                    onEnabledChanged: if (enabled && item) Qt.callLater(() => item.forceActiveFocus())
                    onLoaded: { root.wallsPane = item; if (root.openTab) item.tab = root.openTab; root.openTab = ""; item.forceActiveFocus() }
                    sourceComponent: WallpaperPane {
                        cfg: root.cfg
                        mode: root.wallMode
                        heroCurrent: root.cfg.heroImage || pal.wallpaper     // the choice, not the preview
                        onBack: { root.view = "apps"; hero.preview = ""; Qt.callLater(() => search.forceActiveFocus()) }
                        onHeroHovered: path => hero.preview = path
                        onHeroPicked: path => { root.setHero(path); hero.preview = ""; root.view = "apps" }
                    }
                }
                }
            }
        }
    }
}
