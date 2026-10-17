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
    function run(cmd) { sh.connectSource(cmd + " #run " + Date.now()) }

    // what the right side shows: the apps, or the wallpapers (to set them, or to pick the hero)
    property string view: "apps"
    property string wallMode: "desktop"
    function openWallpapers(mode, tab) {
        wallMode = mode; view = "walls"
        if (tab && walls.item) walls.item.tab = tab
        else openTab = tab || ""
    }
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

    // session shortcuts in the hero card. Restart and shut down go through the rice logout
    // screen (org.kde.LogoutPrompt), the same confirmation the session widget uses.
    readonly property var sessionActions: [
        { icon: "lock", tip: "Lock", tone: "primary", cmd: "loginctl lock-session" },
        { icon: "bedtime", tip: "Sleep", tone: "tertiary", cmd: "systemctl suspend" },
        { icon: "restart_alt", tip: "Restart…", tone: "warn", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptReboot" },
        { icon: "power_settings_new", tip: "Shut down…", tone: "bad", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptShutDown" }
    ]
    function greeting(h) { return h < 5 ? "Up late," : h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening," }

    // ------------------------------------------------------------------ right-click menu
    PlasmaExtras.Menu {
        id: ctx
        property var target: null          // { model, row, favoriteId }
        function openFor(item, model, row) {
            clearMenuItems()
            const fav = model.data(model.index(row, 0), Qt.UserRole + 3)
            target = { model: model, row: row, favoriteId: fav }
            visualParent = item
            if (fav) addMenuItem(menuItem.createObject(ctx, {
                text: root.isFavorite(fav) ? "Unpin from launcher" : "Pin to launcher",
                icon: root.isFavorite(fav) ? "window-unpin" : "window-pin", act: { fav: true } }))
            const acts = model.data(model.index(row, 0), Qt.UserRole + 9) || []
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
                grid.currentIndex = -1
                grid.positionViewAtBeginning()
                pinned.positionViewAtBeginning()
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
                Item {
                    id: hero
                    readonly property real radius: Tokens.radius.lg - Tokens.space.sm
                    Layout.preferredWidth: root.px(248)
                    Layout.fillHeight: true

                    // What it shows: a picture picked with the pencil, or this screen's wallpaper; while
                    // picking, the one under the pointer. Where it sits (focus point and zoom, set with
                    // "Adjust manually") only applies to the image it was set for.
                    property string preview: ""
                    readonly property string source: preview || root.cfg.heroImage || pal.wallpaper
                    readonly property bool placed: !preview && root.cfg.heroFor === source
                    property bool adjusting: false
                    property real editX: 0.5
                    property real editY: 0.5
                    property real editZoom: 1
                    readonly property real fx: adjusting ? editX : placed ? root.cfg.heroX : 0.5
                    readonly property real fy: adjusting ? editY : placed ? root.cfg.heroY : 0.5
                    readonly property real zoom: adjusting ? editZoom : placed ? root.cfg.heroZoom : 1
                    function startAdjust() { editX = fx; editY = fy; editZoom = zoom; adjusting = true }
                    function finishAdjust(keep) {
                        if (keep) {
                            root.cfg.heroFor = source
                            root.cfg.heroX = editX
                            root.cfg.heroY = editY
                            root.cfg.heroZoom = editZoom
                        }
                        adjusting = false
                    }
                    Connections { target: root; function onExpandedChanged() { if (!root.expanded) { hero.finishAdjust(false); hero.preview = "" } } }

                    Item {
                        id: art
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        Rectangle { anchors.fill: parent; color: C.alpha(pal.primary, 0.12) }
                        Image {
                            id: wall
                            source: hero.source ? "file://" + hero.source : ""
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            // decoded at about the size it shows (the card is tall: the height decides)
                            sourceSize.height: Math.ceil(hero.height * Screen.devicePixelRatio * Math.min(3, Math.max(1, hero.zoom)))
                            // cover the card, then zoom; the focus point picks which part shows
                            readonly property real cover: implicitWidth > 0 && implicitHeight > 0
                                ? Math.max(hero.width / implicitWidth, hero.height / implicitHeight) * hero.zoom : 1
                            width: implicitWidth * cover
                            height: implicitHeight * cover
                            x: (hero.width - width) * hero.fx
                            y: (hero.height - height) * hero.fy
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.enter } }
                        }
                    }
                    Rectangle { id: artMask; anchors.fill: parent; radius: hero.radius; visible: false; layer.enabled: true }
                    Rectangle {      // dusk falls over the lower half, where the text sits
                        anchors.fill: parent
                        opacity: hero.adjusting ? 0.35 : 1
                        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                        radius: hero.radius
                        border.width: 1
                        border.color: C.alpha(pal.edge, Tokens.alpha.outline)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: C.alpha(pal.surfaceLowest, 0.0) }
                            GradientStop { position: 0.38; color: C.alpha(pal.surfaceLowest, 0.15) }
                            GradientStop { position: 0.72; color: C.alpha(pal.surfaceLowest, 0.78) }
                            GradientStop { position: 1.0; color: C.alpha(pal.surfaceLowest, 0.92) }
                        }
                    }

                    ColumnLayout {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: root.px(Tokens.space.lg + 4) }
                        spacing: 0
                        // out of the way while the picture is being placed
                        opacity: hero.adjusting ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                        Text {
                            text: Qt.formatTime(pop.now, "HH:mm")
                            color: pal.fg
                            font.family: Tokens.font.display
                            font.weight: Font.Black
                            font.pixelSize: root.px(54)
                            font.features: { "tnum": 1 }
                            style: Text.Raised
                            styleColor: C.alpha(pal.surfaceLowest, 0.35)
                        }
                        Text {
                            Layout.topMargin: -Tokens.space.xs
                            text: Qt.formatDate(pop.now, "dddd, d MMMM")
                            color: pal.fgDim
                            font.family: Tokens.font.ui
                            font.weight: Font.Medium
                            font.pixelSize: root.px(Tokens.size.body)
                        }
                        RowLayout {
                            Layout.topMargin: root.px(Tokens.space.xl)
                            spacing: Tokens.space.md
                            Rectangle {               // avatar, as in the session menu
                                implicitWidth: root.px(40); implicitHeight: implicitWidth; radius: implicitWidth / 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: pal.primary }
                                    GradientStop { position: 1; color: pal.tertiary }
                                }
                                border.width: 1
                                border.color: C.alpha(pal.edge, Tokens.alpha.outlineStrong)
                                Text {
                                    anchors.centerIn: parent
                                    text: me.initial
                                    color: pal.onPrimary
                                    font.family: Tokens.font.display
                                    font.weight: Font.Black
                                    font.pixelSize: root.px(Tokens.size.heading)
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: root.greeting(pop.now.getHours())
                                    color: pal.fgDim
                                    font.family: Tokens.font.ui
                                    font.pixelSize: root.px(Tokens.size.label)
                                }
                                Text {
                                    text: me.displayName
                                    color: pal.fg
                                    font.family: Tokens.font.display
                                    font.weight: Font.ExtraBold
                                    font.pixelSize: root.px(Tokens.size.heading)
                                }
                            }
                        }
                        RowLayout {
                            id: sessionRow
                            Layout.topMargin: root.px(Tokens.space.lg + 2)
                            spacing: Tokens.space.sm
                            Repeater {
                                id: sessionButtons
                                model: root.sessionActions
                                Pill {
                                    required property var modelData
                                    required property int index
                                    palette: pal
                                    icon: modelData.icon
                                    tooltip: modelData.tip
                                    size: root.px(40)
                                    accent: pal[modelData.tone]
                                    onAccent: pal.surfaceLowest
                                    Keys.onLeftPressed: if (index > 0) sessionButtons.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                                    Keys.onRightPressed: if (index < sessionButtons.count - 1) sessionButtons.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)
                                    onClicked: { root.expanded = false; root.run(modelData.cmd) }
                                }
                            }
                        }
                    }

                    // placing the picture: drag to move it, scroll to zoom; Done keeps it, Esc doesn't
                    MouseArea {
                        id: placer
                        anchors.fill: parent
                        enabled: hero.adjusting
                        visible: enabled
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point last
                        onPressed: m => last = Qt.point(m.x, m.y)
                        onPositionChanged: m => {
                            const dx = m.x - last.x, dy = m.y - last.y
                            last = Qt.point(m.x, m.y)
                            const sx = hero.width - wall.width, sy = hero.height - wall.height    // 0 or less
                            if (sx < -0.5) hero.editX = Math.max(0, Math.min(1, hero.editX + dx / sx))
                            if (sy < -0.5) hero.editY = Math.max(0, Math.min(1, hero.editY + dy / sy))
                        }
                        onWheel: w => hero.editZoom = Math.max(1, Math.min(3, hero.editZoom * (w.angleDelta.y > 0 ? 1.08 : 1 / 1.08)))
                    }
                    Column {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.px(Tokens.space.lg) }
                        spacing: Tokens.space.sm
                        opacity: hero.adjusting ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                        Chip {
                            anchors.horizontalCenter: parent.horizontalCenter
                            palette: pal
                            solid: true
                            tint: C.alpha(pal.surfaceLowest, 0.78)
                            textColor: pal.fg
                            icon: "pan_tool"
                            size: 26
                            text: "Drag to move · scroll to zoom"
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Tokens.space.sm
                            Pill { palette: pal; icon: "restart_alt"; text: "Reset"; accent: pal.secondary; onAccent: pal.col("on_secondary")
                                   onClicked: { hero.editX = 0.5; hero.editY = 0.5; hero.editZoom = 1 } }
                            Pill { palette: pal; icon: "check"; text: "Done"; onClicked: hero.finishAdjust(true) }
                        }
                    }
                    Keys.onEscapePressed: event => { if (hero.adjusting) { hero.finishAdjust(false); event.accepted = true } else event.accepted = false }

                    // the pencil: what the hero shows
                    Rectangle {
                        id: pencil
                        anchors { right: parent.right; top: parent.top; margins: Tokens.space.sm + 2 }
                        width: root.px(32); height: width; radius: width / 2
                        visible: !hero.adjusting
                        color: C.alpha(pal.surfaceLowest, pencilMouse.containsMouse || heroMenu.opened ? 0.78 : 0.5)
                        border.width: 1
                        border.color: C.alpha(pal.edge, pencilMouse.containsMouse ? Tokens.alpha.outlineStrong : Tokens.alpha.outline)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        Text {
                            anchors.centerIn: parent
                            text: "edit"
                            color: pencilMouse.containsMouse ? pal.primary : pal.fg
                            font.family: Tokens.font.icons
                            font.pixelSize: root.px(17)
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        }
                        PlasmaCore.ToolTipArea {
                            anchors.fill: parent
                            mainText: "Hero image"
                            subText: root.cfg.heroImage ? "A picture of your choice" : "Follows this screen's wallpaper"
                            MouseArea {
                                id: pencilMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: heroMenu.openRelative()
                            }
                        }
                    }
                    PlasmaExtras.Menu {
                        id: heroMenu
                        visualParent: pencil
                        readonly property bool opened: status === PlasmaExtras.Menu.Open
                        PlasmaExtras.MenuItem {
                            text: "Pick from wallpapers"
                            icon: "preferences-desktop-wallpaper"
                            onClicked: root.openWallpapers("hero")
                        }
                        PlasmaExtras.MenuItem {
                            text: "Adjust manually"
                            icon: "transform-move"
                            onClicked: { hero.startAdjust(); hero.forceActiveFocus() }
                        }
                        PlasmaExtras.MenuItem {
                            text: "Browse image…"
                            icon: "document-open"
                            onClicked: browseDialog.open()
                        }
                        PlasmaExtras.MenuItem { separator: true; visible: !!root.cfg.heroImage }
                        PlasmaExtras.MenuItem {
                            visible: !!root.cfg.heroImage
                            text: "Follow the wallpaper"
                            icon: "view-refresh"
                            onClicked: root.setHero("")
                        }
                    }
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
                                            else { grid.forceActiveFocus(Qt.TabFocusReason); if (grid.currentIndex < 0) grid.currentIndex = 0 }
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Up) {
                                            if (root.query) root.moveSelection(-1)
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            if (root.query) root.activateSelection()
                                            else if (grid.currentIndex >= 0) root.launch(root.browseModel, grid.currentIndex)
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
                    ColumnLayout {
                        id: browse
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Tokens.space.sm
                        visible: !root.query

                        SectionHeader {
                            visible: pinned.count > 0
                            palette: pal
                            text: "Pinned"
                            Layout.leftMargin: Tokens.space.xxs
                        }
                        ListView {
                            id: pinned
                            Layout.fillWidth: true
                            implicitHeight: count ? root.px(92) : 0
                            orientation: ListView.Horizontal
                            spacing: Tokens.space.sm
                            clip: true
                            interactive: contentWidth > width
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.favorites
                            // overflowing: soft edges where there's more, scroll with the wheel too
                            layer.enabled: contentWidth > width
                            layer.effect: EdgeFade { view: pinned }
                            WheelHandler {
                                enabled: pinned.interactive
                                onWheel: event => pinned.flick((event.angleDelta.y || event.angleDelta.x) * 8, 0)
                            }
                            // keyboard: Tab in, arrows along the row, Enter to open
                            activeFocusOnTab: count > 0
                            keyNavigationEnabled: true
                            currentIndex: -1
                            highlightFollowsCurrentItem: false
                            onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
                            Keys.onReturnPressed: if (currentIndex >= 0) root.launch(root.favorites, currentIndex)
                            Keys.onEnterPressed: if (currentIndex >= 0) root.launch(root.favorites, currentIndex)
                            Keys.onEscapePressed: root.expanded = false
                            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                            delegate: Item {
                                id: pin
                                required property int index
                                required property var model
                                readonly property color tint: C.appTint(pinColors, pal.primary)
                                readonly property bool focused: ListView.isCurrentItem && pinned.activeFocus
                                readonly property bool hot: pm.containsMouse || focused
                                Kirigami.ImageColors { id: pinColors; source: pin.model.decoration }
                                width: root.px(88)
                                height: pinned.height

                                Rectangle {
                                    id: pinCard
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    color: C.alpha(pin.tint, pm.pressed ? 0.22 : pin.hot ? 0.14 : 0.06)
                                    border.width: 1
                                    border.color: C.alpha(pin.tint, pin.hot ? 0.65 : 0.22)
                                    // the app's colour, lighting the card from under its icon (as in the top band)
                                    AppGlow {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: root.px(30) - height / 2
                                        width: parent.width * 1.05
                                        flat: 0.72
                                        tint: pin.tint
                                        strength: (pin.hot ? 0.5 : 0.28) * Math.max(0.3, pal.glow)
                                        Behavior on strength { NumberAnimation { duration: Tokens.base } }
                                    }
                                    // pressed dips; hover grows the icon, not the card (the row clips)
                                    scale: pm.pressed ? 0.96 : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Tokens.space.xs + 2
                                        Kirigami.Icon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: root.px(40); height: width
                                            source: pin.model.decoration
                                            scale: pin.hot ? 1.08 : 1
                                            Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: pin.width - Tokens.space.sm
                                            horizontalAlignment: Text.AlignHCenter
                                            text: pin.model.display
                                            elide: Text.ElideRight
                                            color: pal.fg
                                            font.family: Tokens.font.ui
                                            font.weight: Font.DemiBold
                                            font.pixelSize: root.px(Tokens.size.small)
                                        }
                                    }
                                }
                                FocusRing { ink: pal.edge; radius: pinCard.radius; shown: pin.focused; gap: 1 }
                                MouseArea {
                                    id: pm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) ctx.openFor(pin, root.favorites, pin.index)
                                        else root.launch(root.favorites, pin.index)
                                    }
                                }
                            }
                        }

                        // category chips
                        ListView {
                            id: chips
                            objectName: "categoryChips"
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space.xs
                            implicitHeight: root.px(30) + 6       // room for the focus ring
                            orientation: ListView.Horizontal
                            spacing: Tokens.space.xs + 2
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.categories
                            layer.enabled: contentWidth > width
                            layer.effect: EdgeFade { view: chips }
                            WheelHandler {
                                enabled: chips.contentWidth > chips.width
                                onWheel: event => chips.flick((event.angleDelta.y || event.angleDelta.x) * 8, 0)
                            }
                            delegate: Item {
                                id: chipCell
                                required property int index
                                required property var modelData
                                readonly property alias chipItem: chip
                                function step(d) {
                                    const next = chips.itemAtIndex(index + d)
                                    if (next) next.chipItem.forceActiveFocus(Qt.TabFocusReason)
                                }
                                width: chip.width
                                height: chips.height
                                Chip {
                                    id: chip
                                    anchors.verticalCenter: parent.verticalCenter
                                    palette: pal
                                    interactive: true
                                    size: root.px(30)
                                    icon: chipCell.modelData.icon
                                    text: chipCell.modelData.label
                                    tint: pal.primary
                                    selected: root.category === chipCell.index
                                    bold: selected
                                    onActiveFocusChanged: if (activeFocus) chips.positionViewAtIndex(chipCell.index, ListView.Contain)
                                    Keys.onLeftPressed: chipCell.step(-1)
                                    Keys.onRightPressed: chipCell.step(1)
                                    onClicked: { root.category = chipCell.index; grid.currentIndex = -1; grid.positionViewAtBeginning() }
                                }
                            }
                        }

                        // app grid: whole columns, centred. The view is exactly its columns wide inside a box
                        // that fills the room: a cell width that follows the view's own width, plus a centring
                        // margin, left GridView counting too few columns (3 of 6) and never counting again.
                        Item {
                        id: gridBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        GridView {
                            id: grid
                            objectName: "appGrid"
                            readonly property int columns: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: columns * cellWidth
                            height: parent.height
                            clip: true
                            cellWidth: Math.floor(gridBox.width / columns)
                            cellHeight: root.px(100)
                            model: root.browseModel
                            currentIndex: -1
                            keyNavigationEnabled: true
                            activeFocusOnTab: true
                            boundsBehavior: Flickable.StopAtBounds
                            highlightFollowsCurrentItem: false
                            // a slim scroll pip, quiet until the grid moves or is hovered
                            Rectangle {
                                parent: grid
                                anchors.right: parent.right
                                y: grid.visibleArea.yPosition * grid.height
                                width: 4
                                height: Math.max(24, grid.visibleArea.heightRatio * grid.height)
                                radius: 2
                                color: C.alpha(pal.fg, 0.3)
                                visible: grid.contentHeight > grid.height + 1
                                opacity: grid.moving || gridHover.hovered ? 1 : 0.35
                                Behavior on opacity { NumberAnimation { duration: Tokens.base } }
                            }
                            HoverHandler { id: gridHover }
                            onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
                            // swap categories with a soft fade
                            onModelChanged: { opacity = 0; fadeIn.restart() }
                            NumberAnimation { id: fadeIn; target: grid; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (currentIndex >= 0) root.launch(root.browseModel, currentIndex)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    root.expanded = false
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up && currentIndex < columns) {
                                    search.forceActiveFocus()
                                    event.accepted = true
                                } else if (event.text && event.text.trim() && !(event.modifiers & Qt.ControlModifier)) {
                                    search.text += event.text          // typing on the grid searches
                                    search.cursorPosition = search.text.length
                                    search.forceActiveFocus()
                                    event.accepted = true
                                }
                            }

                            delegate: Item {
                                id: app
                                required property int index
                                required property var model
                                readonly property bool current: GridView.isCurrentItem && grid.activeFocus
                                readonly property bool hot: am.containsMouse || current
                                readonly property color tint: C.appTint(appColors, pal.primary)
                                Kirigami.ImageColors { id: appColors; source: app.model.decoration }
                                width: grid.cellWidth
                                height: grid.cellHeight

                                // on open, the first rows fade up in a quick ripple
                                transform: Translate { id: appRise }
                                SequentialAnimation {
                                    id: appIn
                                    PropertyAction { target: app; property: "opacity"; value: 0 }
                                    PropertyAction { target: appRise; property: "y"; value: 8 }
                                    PauseAnimation { duration: Tokens.ms(80 + app.index * 12) }
                                    ParallelAnimation {
                                        NumberAnimation { target: app; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                                        NumberAnimation { target: appRise; property: "y"; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
                                    }
                                }
                                Connections {
                                    target: pop
                                    function onEntered() { if (app.index < 24 && Tokens.speed > 0) appIn.restart() }
                                }

                                Rectangle {
                                    id: appCard
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space.xs
                                    radius: Tokens.radius.md
                                    color: C.alpha(app.tint, am.pressed ? 0.24 : app.hot ? 0.16 : 0)
                                    border.width: 1
                                    border.color: C.alpha(app.tint, app.hot ? 0.40 : 0)
                                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                                }
                                FocusRing { ink: pal.edge; radius: appCard.radius; target: appCard; shown: app.current; gap: 1 }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: Tokens.space.sm
                                    scale: am.pressed ? 0.95 : app.hot ? 1.04 : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                                    Kirigami.Icon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: root.px(42); height: width
                                        source: app.model.decoration
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: grid.cellWidth - Tokens.space.md - 2
                                        horizontalAlignment: Text.AlignHCenter
                                        text: app.model.display
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        lineHeight: 0.92
                                        color: pal.fg
                                        font.family: Tokens.font.ui
                                        font.weight: Font.Medium
                                        font.pixelSize: root.px(Tokens.size.small)
                                    }
                                }
                                MouseArea {
                                    id: am
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    property point pressAt
                                    onPressed: mouse => pressAt = Qt.point(mouse.x, mouse.y)
                                    onPositionChanged: mouse => {      // drag an app onto the bar to pin it there
                                        if (pressed && app.model.url && dragHelper.isDrag(pressAt.x, pressAt.y, mouse.x, mouse.y))
                                            dragHelper.startDrag(root, app.model.url)
                                    }
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) ctx.openFor(app, root.browseModel, app.index)
                                        else root.launch(root.browseModel, app.index)
                                    }
                                }
                            }
                        }
                    }
                    }

                    // ---------------------------------------------- results
                    Item {
                        id: resultsArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !!root.query
                        // empty groups collapse to nothing, so any height means something matched
                        readonly property bool hasResults: results.contentHeight > 20

                        ListView {
                            id: results
                            anchors.fill: parent
                            clip: true
                            spacing: 0
                            boundsBehavior: Flickable.StopAtBounds
                            model: runner
                            QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}
                            // cross-fade: the old results dim while KRunner works, the new ones brighten in
                            opacity: root.searching ? 0.55 : 1
                            Behavior on opacity { NumberAnimation { duration: root.searching ? Tokens.fast : Tokens.base; easing.type: Tokens.enter } }
                            delegate: Column {
                                id: group
                                required property int index
                                required property var model
                                readonly property var matches: runner.modelForRow(index)
                                width: results.width - Tokens.space.sm
                                height: visible ? implicitHeight : 0
                                spacing: Tokens.space.xs
                                visible: list.count > 0
                                topPadding: Tokens.space.xs + 2
                                bottomPadding: Tokens.space.xs + 2
                                SectionHeader {
                                    leftPadding: Tokens.space.sm
                                    palette: pal
                                    text: String(group.matches ? group.matches.name : "")
                                }
                                Repeater {
                                    id: list
                                    model: group.matches
                                    delegate: Rectangle {
                                        id: row
                                        required property int index
                                        required property var model
                                        readonly property bool selected: root.selGroup === group.index && root.selRow === index
                                        width: group.width
                                        height: root.px(52)
                                        radius: Tokens.radius.sm
                                        color: selected ? C.alpha(pal.primary, rm.pressed ? 0.24 : 0.16)
                                             : C.alpha(pal.fg, rm.pressed ? 0.10 : rm.containsMouse ? 0.06 : 0)
                                        border.width: selected ? 1 : 0
                                        border.color: C.alpha(pal.primary, 0.4)
                                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                        onSelectedChanged: if (selected) results.positionViewAtIndex(group.index, ListView.Contain)

                                        // each row arrives with a short fade and rise, a few ms after the one above
                                        opacity: 0
                                        transform: Translate { id: rowRise; y: 6 }
                                        SequentialAnimation {
                                            id: rowIn
                                            PauseAnimation { duration: Tokens.ms(Math.min(row.index, 6) * 20) }
                                            ParallelAnimation {
                                                NumberAnimation { target: row; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                                                NumberAnimation { target: rowRise; property: "y"; to: 0; duration: Tokens.base; easing.type: Tokens.enter }
                                            }
                                        }
                                        Component.onCompleted: {
                                            if (Tokens.speed > 0) rowIn.start();
                                            else { opacity = 1; rowRise.y = 0 }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Tokens.space.md
                                            anchors.rightMargin: Tokens.space.md
                                            spacing: Tokens.space.md
                                            Kirigami.Icon {
                                                implicitWidth: root.px(32); implicitHeight: implicitWidth
                                                source: row.model.decoration
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: row.model.display
                                                    elide: Text.ElideRight
                                                    color: pal.fg
                                                    font.family: Tokens.font.ui
                                                    font.weight: Font.DemiBold
                                                    font.pixelSize: root.px(Tokens.size.body)
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: text.length > 0
                                                    text: row.model.description || ""
                                                    elide: Text.ElideRight
                                                    color: pal.muted
                                                    font.family: Tokens.font.ui
                                                    font.pixelSize: root.px(Tokens.size.small)
                                                }
                                            }
                                            Chip {
                                                visible: row.selected
                                                palette: pal
                                                text: "↵ open"
                                                tint: pal.primary
                                                size: 20
                                            }
                                        }
                                        MouseArea {
                                            id: rm
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) ctx.openFor(row, group.matches, row.index)
                                                else root.launch(group.matches, row.index)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // searching, nothing in yet: placeholder rows breathing (popup only, stops when done)
                        Column {
                            id: skeleton
                            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Tokens.space.sm }
                            spacing: Tokens.space.sm
                            visible: root.searching && !resultsArea.hasResults
                            SectionHeader { leftPadding: Tokens.space.sm; palette: pal; text: "Searching…" }
                            Repeater {
                                model: 3
                                Rectangle {
                                    id: skel
                                    required property int index
                                    width: skeleton.width - Tokens.space.sm
                                    height: root.px(52)
                                    radius: Tokens.radius.sm
                                    color: C.alpha(pal.fg, 0.05)
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Tokens.space.md
                                        spacing: Tokens.space.md
                                        Rectangle { width: root.px(32); height: width; radius: Tokens.radius.xs; color: C.alpha(pal.fg, 0.07) }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Tokens.space.xs + 2
                                            Rectangle { width: root.px(180 - skel.index * 40); height: 9; radius: 4.5; color: C.alpha(pal.fg, 0.08) }
                                            Rectangle { width: 110; height: 7; radius: 3.5; color: C.alpha(pal.fg, 0.05) }
                                        }
                                    }
                                    SequentialAnimation on opacity {
                                        running: skeleton.visible
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: skel.index * 120 }
                                        NumberAnimation { to: 0.45; duration: 650; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }

                        // nothing found
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Tokens.space.sm
                            visible: !root.searching && !resultsArea.hasResults
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "search_off"
                                color: pal.muted
                                font.family: Tokens.font.icons
                                font.pixelSize: root.px(44)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Nothing for “" + root.query + "”"
                                color: pal.fg
                                font.family: Tokens.font.display
                                font.weight: Font.Bold
                                font.pixelSize: root.px(Tokens.size.title)
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Try an app, a setting, a file name, or a sum like 12*7"
                                color: pal.fgDim
                                font.family: Tokens.font.ui
                                font.pixelSize: root.px(Tokens.size.label)
                            }
                        }
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
                    onLoaded: { if (root.openTab) item.tab = root.openTab; root.openTab = ""; item.forceActiveFocus() }
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
