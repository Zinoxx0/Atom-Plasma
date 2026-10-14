import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import Qt5Compat.GraphicalEffects as GE

// A calm, wallpaper-lit app launcher in the style of the session menu. Left: a hero card of
// this screen's wallpaper with the time, a greeting and session shortcuts. Right: a search
// field over pinned apps, category chips and the app grid. Typing searches apps, settings,
// files and maths (KRunner), grouped by kind. Favourites are Plasma's shared ones (Kickoff's).
// Meta opens it (X-Plasma-Provides: org.kde.plasma.launchermenu).
PlasmoidItem {
    id: root

    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    property string user: ""
    property string realName: ""
    readonly property string firstName: realName.split(/[ ,]/)[0] || user
    readonly property string screenName: Screen.name
    function col(n, f) { return pal[n] ?? f }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property color cFg: col("on_surface", "#c0caf5")
    readonly property color cFgDim: col("on_surface_variant", "#a9b1d6")
    readonly property color cMuted: col("muted", "#565f89")
    readonly property color cBg: col("background", "#1a1b26")
    readonly property color cPrimary: col("primary", "#7aa2f7")
    readonly property color cOnPrimary: col("on_primary", "#1a1b26")
    readonly property color cTertiary: col("tertiary", "#bb9af7")

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.indexOf("#info") >= 0) {
                const p = (data["stdout"] ?? "").split("\n@@\n");
                root.user = (p[0] ?? "").trim();
                root.realName = (p[1] ?? "").trim();
                try { root.pal = JSON.parse(p[2]) } catch (e) {}
            }
            disconnectSource(source);
        }
    }
    function refresh() {
        sh.connectSource('id -un; printf "\\n@@\\n"; getent passwd "$(id -un)" | cut -d: -f5; printf "\\n@@\\n"; '
            + 'cat "$HOME/.local/state/rice/palette-' + screenName + '.json" 2>/dev/null || cat "$HOME/.local/state/rice/palette.json" #info ' + Date.now());
    }
    function run(cmd) { sh.connectSource(cmd + " #run " + Date.now()) }
    Component.onCompleted: refresh()
    onScreenNameChanged: refresh()
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()

    // an app's own colour, from its icon: the most vivid sizeable swatch as a candy pastel
    function appTint(ic) {
        const p = ic ? ic.palette : null
        let best = null, score = 0
        for (let i = 0; p && i < p.length; i++) {
            const c = p[i].color, r = p[i].ratio
            if (r < 0.04 || c.hslSaturation < 0.28 || c.hslLightness < 0.12 || c.hslLightness > 0.92) continue
            const s = c.hslSaturation * Math.sqrt(r)
            if (s > score) { best = c; score = s }
        }
        return best ? Qt.hsla(best.hslHue, Math.min(1, best.hslSaturation * 1.1), Math.max(0.62, Math.min(0.76, best.hslLightness)), 1) : cPrimary
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
    onQueryChanged: { runner.query = query; selGroup = 0; selRow = 0; Qt.callLater(fixSelection) }

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
        function onQueryFinished() { Qt.callLater(root.fixSelection) }
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

    // session shortcuts in the hero card (restart and power go through Plasma's confirm screen)
    readonly property var sessionActions: [
        { icon: "lock", tip: "Lock", color: "primary", cmd: "loginctl lock-session" },
        { icon: "bedtime", tip: "Sleep", color: "tertiary", cmd: "systemctl suspend" },
        { icon: "restart_alt", tip: "Restart…", color: "orange", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptReboot" },
        { icon: "power_settings_new", tip: "Shut down…", color: "red", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptShutDown" }
    ]

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
        Layout.minimumWidth: (emblem.implicitWidth + 6) * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
        Emblem {
            id: emblem
            anchors.centerIn: parent
            hovered: compact.containsMouse
            pressed: compact.pressed
            open: root.expanded
            scale: root.uiScale        // vector, stays crisp
            c1: root.col("primary", "#7aa2f7")
            c2: root.col("tertiary", "#bb9af7")
            c3: root.col("red", "#f7768e")
            c4: root.col("teal", "#73daca")
            glow: root.col("primary", "#7aa2f7")
        }
    }

    // ------------------------------------------------------------------ popup
    fullRepresentation: FocusScope {
        id: pop
        Layout.preferredWidth: 880
        Layout.preferredHeight: 580
        Layout.minimumWidth: 720
        Layout.minimumHeight: 480
        focus: true

        property date now: new Date()
        Timer { running: root.expanded; repeat: true; interval: 5000; triggeredOnStart: true; onTriggered: pop.now = new Date() }

        // fresh every time it opens: empty query, All, first app, staggered entrance
        signal entered()
        Connections {
            target: root
            function onExpandedChanged() {
                if (!root.expanded) return
                search.text = ""
                root.category = 0
                grid.currentIndex = -1
                grid.positionViewAtBeginning()
                Qt.callLater(() => search.forceActiveFocus())
                pop.entered()
            }
        }
        Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 16

            // ---------------------------------------------------------- hero card
            Item {
                id: hero
                Layout.preferredWidth: 248
                Layout.fillHeight: true
                opacity: 0
                transform: Translate { id: heroShift; x: -18 }
                Connections {
                    target: pop
                    function onEntered() { heroIn.restart() }
                }
                ParallelAnimation {
                    id: heroIn
                    NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: 260 }
                    NumberAnimation { target: heroShift; property: "x"; from: -18; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }
                Component.onCompleted: heroIn.restart()

                Kirigami.ShadowedImage {
                    id: wall
                    anchors.fill: parent
                    radius: 22
                    color: root.alpha(root.cPrimary, 0.12)
                    // the full wallpaper, decoded at about the card's real size (the thumbnail is too small for a tall crop)
                    source: root.pal._wallpaper ? "file://" + root.pal._wallpaper : root.pal._thumb ? "file://" + root.pal._thumb : ""
                    sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {      // dusk falls over the lower half, where the text sits
                    anchors.fill: parent
                    radius: 22
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.alpha(root.cBg, 0.0) }
                        GradientStop { position: 0.38; color: root.alpha(root.cBg, 0.15) }
                        GradientStop { position: 0.72; color: root.alpha(root.cBg, 0.78) }
                        GradientStop { position: 1.0; color: root.alpha(root.cBg, 0.92) }
                    }
                }

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
                    spacing: 0
                    Text {
                        text: Qt.formatTime(pop.now, "HH:mm")
                        color: root.cFg
                        font.family: "Inter Display"; font.weight: Font.Black; font.pixelSize: 54
                        font.features: { "tnum": 1 }
                        style: Text.Raised; styleColor: root.alpha(root.cBg, 0.35)
                    }
                    Text {
                        Layout.topMargin: -4
                        text: Qt.formatDate(pop.now, "dddd, d MMMM")
                        color: root.cFgDim
                        font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: 13
                    }
                    RowLayout {
                        Layout.topMargin: 22
                        spacing: 12
                        Rectangle {               // avatar, as in the session menu
                            implicitWidth: 40; implicitHeight: 40; radius: 20
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: root.cPrimary }
                                GradientStop { position: 1; color: root.cTertiary }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.firstName ? root.firstName[0].toUpperCase() : "?"
                                color: root.cOnPrimary
                                font.family: "Inter Display"; font.weight: Font.Black; font.pixelSize: 18
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: {
                                    const h = pop.now.getHours()
                                    return h < 5 ? "Up late," : h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening,"
                                }
                                color: root.cFgDim
                                font.family: "Inter"; font.pixelSize: 12
                            }
                            Text {
                                text: root.firstName
                                color: root.cFg
                                font.family: "Inter Display"; font.weight: Font.ExtraBold; font.pixelSize: 18
                            }
                        }
                    }
                    RowLayout {
                        Layout.topMargin: 18
                        spacing: 8
                        Repeater {
                            model: root.sessionActions
                            Rectangle {
                                id: sbtn
                                required property var modelData
                                readonly property color tint: root.col(modelData.color, "#7aa2f7")
                                implicitWidth: 44; implicitHeight: 40
                                radius: 14
                                color: Qt.alpha(tint, sm.containsMouse ? 0.26 : 0.12)
                                border.width: 1
                                border.color: Qt.alpha(tint, sm.containsMouse ? 0.7 : 0.25)
                                scale: sm.pressed ? 0.92 : sm.containsMouse ? 1.06 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: sbtn.modelData.icon
                                    color: sbtn.tint
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                                }
                                MouseArea {
                                    id: sm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.expanded = false; root.run(sbtn.modelData.cmd) }
                                }
                                QQC2.ToolTip.visible: sm.containsMouse
                                QQC2.ToolTip.delay: 500
                                QQC2.ToolTip.text: modelData.tip
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------- search + content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                // search
                Rectangle {
                    id: searchBox
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 16
                    color: Qt.alpha(root.cFg, search.activeFocus ? 0.09 : 0.06)
                    border.width: search.activeFocus ? 1.5 : 1
                    border.color: search.activeFocus ? Qt.alpha(root.cPrimary, 0.75) : Qt.alpha(root.cFg, 0.10)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: search.forceActiveFocus() }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        spacing: 12
                        Text {
                            text: "search"
                            color: search.activeFocus ? root.cPrimary : root.cMuted
                            font.family: "Material Symbols Rounded"; font.pixelSize: 22
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TextInput {
                                id: search
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.cFg
                                selectionColor: root.cPrimary
                                selectedTextColor: root.cOnPrimary
                                font.family: "Inter"; font.pixelSize: 15
                                clip: true
                                focus: true
                                onTextChanged: root.query = text
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        if (text) text = ""; else root.expanded = false
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                        if (root.query) root.moveSelection(1)
                                        else { grid.forceActiveFocus(); if (grid.currentIndex < 0) grid.currentIndex = 0 }
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
                                color: root.cMuted
                                font: search.font
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {           // key hint
                            implicitHeight: 22
                            implicitWidth: hint.implicitWidth + 14
                            radius: 7
                            color: Qt.alpha(root.cFg, 0.07)
                            border.width: 1
                            border.color: Qt.alpha(root.cFg, 0.10)
                            Text {
                                id: hint
                                anchors.centerIn: parent
                                text: root.query ? "esc" : "meta"
                                color: root.cMuted
                                font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 10
                            }
                        }
                    }
                }

                // ---------------------------------------------- browse: pinned, chips, grid
                ColumnLayout {
                    id: browse
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12
                    visible: !root.query

                    Text {
                        visible: pinned.count > 0
                        text: "Pinned"
                        color: root.cFgDim
                        font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 12
                        font.letterSpacing: 0.6
                    }
                    ListView {
                        id: pinned
                        Layout.fillWidth: true
                        implicitHeight: count ? 96 : 0
                        orientation: ListView.Horizontal
                        spacing: 10
                        clip: false
                        interactive: contentWidth > width
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.favorites
                        delegate: Item {
                            id: pin
                            required property int index
                            required property var model
                            readonly property color tint: root.appTint(pinColors)
                            Kirigami.ImageColors { id: pinColors; source: pin.model.decoration }
                            width: 92
                            height: 96
                            opacity: 0
                            transform: Translate { id: pinRise; y: 14 }
                            SequentialAnimation {
                                id: pinIn
                                PauseAnimation { duration: 60 + pin.index * 40 }
                                ParallelAnimation {
                                    NumberAnimation { target: pin; property: "opacity"; to: 1; duration: 220 }
                                    NumberAnimation { target: pinRise; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack }
                                }
                            }
                            Connections {
                                target: pop
                                function onEntered() { pin.opacity = 0; pinRise.y = 14; pinIn.restart() }
                            }
                            Component.onCompleted: pinIn.restart()

                            Rectangle {
                                anchors.fill: parent
                                radius: 22
                                color: Qt.alpha(pin.tint, pm.containsMouse ? 0.24 : 0.10)
                                border.width: 1
                                border.color: Qt.alpha(pin.tint, pm.containsMouse ? 0.7 : 0.22)
                                scale: pm.pressed ? 0.94 : pm.containsMouse ? 1.05 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Kirigami.Icon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 40; height: 40
                                        source: pin.model.decoration
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 80
                                        horizontalAlignment: Text.AlignHCenter
                                        text: pin.model.display
                                        elide: Text.ElideRight
                                        color: root.cFg
                                        font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 11
                                    }
                                }
                            }
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
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: 32
                        orientation: ListView.Horizontal
                        spacing: 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.categories
                        // soft edges where there is more to scroll to
                        readonly property bool moreLeft: contentX > 2
                        readonly property bool moreRight: contentX + width < contentWidth - 2
                        layer.enabled: moreLeft || moreRight
                        layer.effect: GE.OpacityMask {
                            maskSource: Rectangle {
                                width: chips.width
                                height: chips.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: chips.moreLeft ? "transparent" : "black" }
                                    GradientStop { position: 0.06; color: "black" }
                                    GradientStop { position: 0.9; color: "black" }
                                    GradientStop { position: 1; color: chips.moreRight ? "transparent" : "black" }
                                }
                            }
                        }
                        delegate: Rectangle {
                            id: chip
                            required property int index
                            required property var modelData
                            readonly property bool on: root.category === index
                            height: 32
                            width: chipRow.implicitWidth + 24
                            radius: 16
                            color: on ? root.cPrimary : Qt.alpha(root.cFg, cm.containsMouse ? 0.11 : 0.06)
                            border.width: on ? 0 : 1
                            border.color: Qt.alpha(root.cFg, 0.08)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData.icon
                                    color: chip.on ? root.cOnPrimary : root.cFgDim
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 16
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData.label
                                    color: chip.on ? root.cOnPrimary : root.cFg
                                    font.family: "Inter"; font.weight: chip.on ? Font.Bold : Font.Medium; font.pixelSize: 12
                                }
                            }
                            MouseArea {
                                id: cm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.category = chip.index; grid.currentIndex = -1; grid.positionViewAtBeginning() }
                            }
                        }
                    }

                    // app grid
                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: Math.floor(width / 6)
                        cellHeight: 100
                        model: root.browseModel
                        currentIndex: -1
                        keyNavigationEnabled: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false
                        QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}
                        // swap categories with a soft fade
                        opacity: 1
                        onModelChanged: { opacity = 0; fadeIn.restart() }
                        NumberAnimation { id: fadeIn; target: grid; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (currentIndex >= 0) root.launch(root.browseModel, currentIndex)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                root.expanded = false
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up && currentIndex < Math.floor(width / cellWidth)) {
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
                            readonly property color tint: root.appTint(appColors)
                            Kirigami.ImageColors { id: appColors; source: app.model.decoration }
                            width: grid.cellWidth
                            height: grid.cellHeight
                            transform: Translate { id: appRise }
                            SequentialAnimation {
                                id: appIn
                                PropertyAction { target: app; property: "opacity"; value: 0 }
                                PropertyAction { target: appRise; property: "y"; value: 12 }
                                PauseAnimation { duration: 140 + app.index * 14 }
                                ParallelAnimation {
                                    NumberAnimation { target: app; property: "opacity"; to: 1; duration: 200 }
                                    NumberAnimation { target: appRise; property: "y"; to: 0; duration: 340; easing.type: Easing.OutCubic }
                                }
                            }
                            Connections {
                                target: pop
                                function onEntered() { if (app.index < 24) appIn.restart() }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 18
                                color: Qt.alpha(app.tint, am.containsMouse || app.current ? 0.16 : 0)
                                border.width: app.current ? 1.5 : 1
                                border.color: Qt.alpha(app.tint, app.current ? 0.75 : am.containsMouse ? 0.35 : 0)
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                scale: am.pressed ? 0.92 : am.containsMouse ? 1.06 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Kirigami.Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 42; height: 42
                                    source: app.model.decoration
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: grid.cellWidth - 14
                                    horizontalAlignment: Text.AlignHCenter
                                    text: app.model.display
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    lineHeight: 0.92
                                    color: root.cFg
                                    font.family: "Inter"; font.weight: Font.Medium; font.pixelSize: 11
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

                // ---------------------------------------------- results
                ListView {
                    id: results
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !!root.query
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: runner
                    QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}
                    delegate: Column {
                        id: group
                        required property int index
                        required property var model
                        readonly property var matches: runner.modelForRow(index)
                        width: results.width - 6
                        height: visible ? implicitHeight : 0
                        spacing: 4
                        visible: list.count > 0
                        topPadding: 6
                        bottomPadding: 6
                        Text {
                            leftPadding: 6
                            text: String(group.matches ? group.matches.name : "").toUpperCase()
                            color: root.cMuted
                            font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 10
                            font.letterSpacing: 1.2
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
                                height: 54
                                radius: 16
                                color: selected ? Qt.alpha(root.cPrimary, 0.16) : Qt.alpha(root.cFg, rm.containsMouse ? 0.06 : 0)
                                border.width: selected ? 1 : 0
                                border.color: Qt.alpha(root.cPrimary, 0.4)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                onSelectedChanged: if (selected) results.positionViewAtIndex(group.index, ListView.Contain)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Kirigami.Icon {
                                        implicitWidth: 32; implicitHeight: 32
                                        source: row.model.decoration
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.model.display
                                            elide: Text.ElideRight
                                            color: root.cFg
                                            font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 13
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: row.model.description || ""
                                            elide: Text.ElideRight
                                            color: root.cMuted
                                            font.family: "Inter"; font.pixelSize: 11
                                        }
                                    }
                                    Rectangle {
                                        visible: row.selected
                                        implicitHeight: 22
                                        implicitWidth: enterText.implicitWidth + 14
                                        radius: 7
                                        color: Qt.alpha(root.cPrimary, 0.22)
                                        Text {
                                            id: enterText
                                            anchors.centerIn: parent
                                            text: "↵ open"
                                            color: root.cPrimary
                                            font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 10
                                        }
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
                    // nothing found
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: !runner.querying && results.contentHeight < 20
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "search_off"
                            color: root.cMuted
                            font.family: "Material Symbols Rounded"; font.pixelSize: 40
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Nothing for “" + root.query + "”"
                            color: root.cFgDim
                            font.family: "Inter"; font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
