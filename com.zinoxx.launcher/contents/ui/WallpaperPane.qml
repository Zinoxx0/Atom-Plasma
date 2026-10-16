import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// The wallpaper picker, inside the launcher: a grid of ~/Pictures/Wallpapers. Clicking one runs
// ~/.config/plasma-rice/rice.py, which sets it on the chosen screen(s) and re-themes the desktop
// from it. Screen chips pick the target, presets keep every screen's wallpaper under a short name,
// "Get more" asks wallhaven for new ones. In "hero" mode it only picks the launcher's hero image.
Item {
    id: wp
    property var cfg                        // the launcher's Plasmoid.configuration
    property string mode: "desktop"         // "desktop" | "hero"
    property string screenName: ""          // the screen this launcher is on
    property string heroCurrent: ""         // in hero mode: the image the hero shows now
    readonly property bool shown: visible
    signal heroPicked(string path)
    signal heroHovered(string path)         // "" when the pointer leaves the grid
    signal back()
    RicePalette { id: pal; output: Screen.name }   // its own: ready before anything below is built

    property string home: ""
    property var walls: []          // file names in ~/Pictures/Wallpapers
    property string current: ""     // last wallpaper picked (drives the global theme)
    property var screens: []        // [{name, label, main, image, thumb}] left to right, from rice.py screens
    property var presets: []        // [{name, screens: {output: image}, theme, thumbs: {output: thumb}}]
    property string busy: ""        // "" | "apply" | "fetch"
    property string pending: ""     // path (or "preset:<name>") being applied
    property string status: ""
    property bool loaded: false
    property var fresh: []          // file names brought by the last "Get more" (badged in the grid)
    property bool naming: false     // the preset name field is out

    readonly property string target: screens.some(s => s.name === cfg.wallTarget) ? cfg.wallTarget : "all"
    readonly property var targetScreen: screens.find(s => s.name === target) ?? null
    readonly property bool heroMode: mode === "hero"

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function pathOf(name) { return home + "/Pictures/Wallpapers/" + name }
    function fileName(p) { return p ? p.split("/").pop() : "" }
    function thumb(name) { return "file://" + home + "/.cache/rice/thumbs-plasma/" + name.replace(/\.[^.]+$/, "") + ".jpg" }
    // already showing on every screen the view targets (then a click does nothing)
    function isCurrent(path) {
        if (heroMode) return path === heroCurrent
        return targetScreen ? targetScreen.image === path
             : screens.length ? screens.every(s => s.image === path) : path === current
    }
    function pick(name) {
        const p = pathOf(name)
        if (heroMode) { heroPicked(p); return }
        if (!isCurrent(p)) apply(p)
    }

    // the grid's model, kept in step with `walls` in place, so a reload keeps the loaded thumbnails
    ListModel { id: wallModel }
    function syncModel(names) {
        const want = new Set(names)
        for (let i = wallModel.count - 1; i >= 0; i--)
            if (!want.has(wallModel.get(i).name)) wallModel.remove(i)
        for (let i = 0; i < names.length; i++)
            if (i >= wallModel.count || wallModel.get(i).name !== names[i]) wallModel.insert(i, { name: names[i] })
    }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            const kind = (source.match(/#(\w+) \d+$/) || [])[1]     // the tags in a fetch could contain anything
            if (kind === "list") {
                const parts = out.split("\n@@\n")
                wp.home = (parts[0] ?? "").trim()
                const names = (parts[1] ?? "").split("\n").filter(s => s.length)
                wp.current = (parts[2] ?? "").trim()
                try { wp.screens = JSON.parse(parts[3]) } catch (e) {}
                try { wp.presets = JSON.parse(parts[4]) } catch (e) {}
                wp.syncModel(names)
                wp.walls = names
                wp.loaded = true
            } else if (kind === "apply") {
                wp.busy = ""; wp.pending = ""
                wp.reload()
            } else if (kind === "psave") {
                const name = out.trim()
                wp.status = name ? "Saved preset “" + name + "”" : "Couldn't save the preset"
                wp.reload()
            } else if (kind === "pdelete") {
                wp.reload()
            } else if (kind === "fetch") {
                wp.busy = ""
                try {
                    const r = JSON.parse(out)
                    const what = "“" + r.tags.join(", ") + "”"
                    wp.fresh = r.saved.map(p => wp.fileName(p))
                    wp.status = r.saved.length ? "Added " + r.saved.length + " for " + what : "Nothing new for " + what
                    if (r.thin && r.thin.length) wp.status += " · no luck with " + r.thin.join(", ")
                } catch (e) { wp.status = "Couldn't reach wallhaven" }
                wp.reload()
            }
            disconnectSource(source)
        }
    }
    function reload() {
        sh.connectSource('echo "$HOME"; printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" thumbs; '
            + 'find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -printf "%f\\n" | sort; '
            + 'printf "\\n@@\\n"; readlink -f "$HOME/.local/state/rice/wallpaper"; '
            + 'printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" screens; '
            + 'printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" presets #list ' + Date.now())
    }
    // scr: "all", "focused" or an output name; defaults to the view's target
    function apply(arg, scr) {
        if (busy) return
        busy = "apply"; pending = arg; status = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" ' + q(arg) + ' --screen ' + q(scr || target) + ' #apply ' + Date.now())
    }
    // tags: "modern, clean, aesthetic"; each click brings the next best matches (wallhaven.py)
    function fetch(tags) {
        if (busy) return
        const t = String(tags ?? "").trim()
        busy = "fetch"; status = t ? "Looking for “" + t + "”…" : "Fetching from wallhaven…"
        if (t) {
            cfg.tags = t
            cfg.tagHistory = [t].concat(cfg.tagHistory.filter(h => h.toLowerCase() !== t.toLowerCase())).slice(0, 6)
        }
        sh.connectSource('python3 "$HOME/.config/plasma-rice/wallhaven.py" 6 ' + q(t) + ' #fetch ' + Date.now())
    }
    function forgetTags(t) { cfg.tagHistory = cfg.tagHistory.filter(h => h !== t) }
    function openFolder() { Qt.openUrlExternally("file://" + home + "/Pictures/Wallpapers") }

    // presets: names up to 10 characters (rice.py trims them the same way)
    function savePreset(name) {
        const n = String(name ?? "").trim().slice(0, 10)
        naming = false
        if (!n) return
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset save ' + q(n) + ' #psave ' + Date.now())
    }
    function loadPreset(name) {
        if (busy) return
        busy = "apply"; pending = "preset:" + name; status = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset load ' + q(name) + ' #apply ' + Date.now())
    }
    function deletePreset(name) {
        status = "Deleted preset “" + name + "”"
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset delete ' + q(name) + ' #pdelete ' + Date.now())
    }
    // on screen right now: every connected screen it knows shows its wallpaper, and the theme is its
    function presetIsOn(pr) {
        const known = screens.filter(s => pr.screens[s.name] !== undefined)
        return known.length > 0 && known.every(s => s.image === pr.screens[s.name]) && current === pr.theme
    }
    function presetThumbs(pr) {     // left to right like the screens
        const order = screens.map(s => s.name)
        return Object.keys(pr.thumbs || {}).sort((a, b) => order.indexOf(a) - order.indexOf(b)).map(o => pr.thumbs[o])
    }

    onShownChanged: if (shown) { reload(); naming = false; Qt.callLater(grid.showCurrent) }
    Component.onCompleted: reload()

    Keys.onEscapePressed: wp.back()

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.space.md

        // header: back, what this view does, this screen's palette as candy dots
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            IconButton {
                palette: pal
                icon: "arrow_back"
                tooltip: "Back to apps"
                size: 34
                onClicked: wp.back()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: wp.heroMode ? "Hero image" : "Wallpapers"
                    color: pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.Bold
                    font.pixelSize: Tokens.size.heading
                }
                Text {
                    Layout.fillWidth: true
                    text: wp.heroMode ? "Pick the picture behind the clock · hover to preview"
                        : !wp.loaded ? "" : wp.status || (wp.walls.length + " wallpapers · "
                          + (wp.targetScreen ? "for " + wp.targetScreen.label : "for every screen"))
                    elide: Text.ElideRight
                    color: pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: Tokens.size.label
                }
            }
            Row {
                visible: !wp.heroMode
                spacing: -6
                Repeater {
                    model: ["primary", "secondary", "tertiary", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
                    Rectangle {
                        id: dot
                        required property string modelData
                        required property int index
                        width: 20; height: 20; radius: 10
                        color: pal.col(modelData)
                        border.width: 2
                        border.color: pal.surface
                        z: dotTip.containsMouse ? 30 : 20 - index
                        scale: dotTip.containsMouse ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                        PlasmaCore.ToolTipArea {
                            id: dotTip
                            anchors.fill: parent
                            mainText: dot.modelData
                            subText: String(pal.col(dot.modelData))
                        }
                    }
                }
            }
        }

        // target screens: All, then one chip per screen (left to right) showing what's on it
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            visible: !wp.heroMode && wp.screens.length > 1
            Repeater {
                id: screenChips
                model: wp.screens.length > 1 ? [{ name: "all", label: "All", thumb: "", main: false }].concat(wp.screens) : []
                Rectangle {
                    id: scr
                    required property var modelData
                    required property int index
                    readonly property bool selected: wp.target === modelData.name
                    readonly property bool hot: scrHover.containsMouse || activeFocus
                    Layout.fillWidth: true
                    implicitHeight: 40
                    implicitWidth: scrRow.implicitWidth + 2 * Tokens.space.sm + 2
                    radius: Tokens.radius.sm
                    color: selected ? C.alpha(pal.primary, scrHover.pressed ? 0.26 : 0.18)
                         : C.alpha(pal.fg, scrHover.pressed ? 0.14 : hot ? 0.09 : 0.05)
                    border.width: 1
                    border.color: selected ? pal.primary : hot ? C.alpha(pal.primary, 0.6) : C.alpha(pal.fg, Tokens.alpha.outline)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }

                    function choose() { wp.cfg.wallTarget = modelData.name; Qt.callLater(grid.showCurrent) }
                    activeFocusOnTab: true
                    Keys.onReturnPressed: choose()
                    Keys.onEnterPressed: choose()
                    Keys.onSpacePressed: choose()
                    Keys.onLeftPressed: if (index > 0) screenChips.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                    Keys.onRightPressed: if (index < screenChips.count - 1) screenChips.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)

                    RowLayout {
                        id: scrRow
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Item {
                            implicitWidth: 36; implicitHeight: 22
                            Kirigami.ShadowedImage {
                                anchors.fill: parent
                                visible: scr.modelData.thumb !== ""
                                radius: Tokens.radius.xs
                                color: C.alpha(pal.fg, 0.08)
                                source: scr.modelData.thumb ? "file://" + scr.modelData.thumb : ""
                                sourceSize.width: 96
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: scr.modelData.name === "all"
                                text: "view_column"
                                color: scr.selected ? pal.primary : pal.fgDim
                                font.family: Tokens.font.icons
                                font.pixelSize: 20
                            }
                        }
                        Text {
                            text: scr.modelData.label
                            color: pal.fg
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: Tokens.size.label
                        }
                    }
                    FocusRing { ink: pal.edge; radius: scr.radius }
                    MouseArea {
                        id: scrHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scr.choose()
                    }
                }
            }
        }

        // actions, and presets (every screen's wallpaper under a name: click to bring the look back,
        // right-click to delete; saving asks for a name, 10 characters at most)
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            visible: !wp.heroMode
            Pill { palette: pal; icon: "shuffle"; tooltip: "Shuffle"; busy: wp.busy === "apply" && wp.pending === "random"; onClicked: wp.apply("random") }
            Pill { palette: pal; icon: "skip_previous"; tooltip: "Previous"; onClicked: wp.apply("prev") }
            Pill { palette: pal; icon: "skip_next"; tooltip: "Next"; onClicked: wp.apply("next") }
            Pill { palette: pal; icon: "folder_open"; tooltip: "Open the wallpaper folder"; accent: pal.secondary; onAccent: pal.col("on_secondary"); onClicked: wp.openFolder() }
            Rectangle { implicitWidth: 1; implicitHeight: 22; color: C.alpha(pal.fg, 0.12) }
            ListView {
                id: presetList
                Layout.fillWidth: true
                implicitHeight: 32
                orientation: ListView.Horizontal
                spacing: Tokens.space.xs + 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: wp.presets.length > 0 && !wp.naming
                model: wp.presets
                layer.enabled: contentWidth > width
                layer.effect: EdgeFade { view: presetList }
                WheelHandler {
                    enabled: presetList.contentWidth > presetList.width
                    onWheel: event => presetList.flick((event.angleDelta.y || event.angleDelta.x) * 8, 0)
                }
                delegate: Rectangle {
                    id: pc
                    required property var modelData
                    readonly property bool isOn: wp.presetIsOn(modelData)
                    readonly property bool applying: wp.busy === "apply" && wp.pending === "preset:" + modelData.name
                    readonly property bool hot: pcMouse.containsMouse || activeFocus
                    height: presetList.height
                    width: pcRow.implicitWidth + 2 * Tokens.space.sm
                    radius: Tokens.radius.sm
                    color: isOn ? C.alpha(pal.primary, pcMouse.pressed ? 0.26 : 0.18)
                         : C.alpha(pal.fg, pcMouse.pressed ? 0.14 : hot ? 0.09 : 0.05)
                    border.width: 1
                    border.color: isOn ? pal.primary : hot ? C.alpha(pal.primary, 0.6) : C.alpha(pal.fg, Tokens.alpha.outline)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                    activeFocusOnTab: true
                    Keys.onReturnPressed: wp.loadPreset(modelData.name)
                    Keys.onSpacePressed: wp.loadPreset(modelData.name)
                    Keys.onDeletePressed: wp.deletePreset(modelData.name)
                    Row {
                        id: pcRow
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Row {           // its screens' wallpapers, fanned like a small deck
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: -10
                            Repeater {
                                model: wp.presetThumbs(pc.modelData)
                                Kirigami.ShadowedImage {
                                    required property string modelData
                                    required property int index
                                    z: 10 - index
                                    width: 28; height: 18
                                    radius: 4
                                    color: C.alpha(pal.fg, 0.08)
                                    border.width: 1.5
                                    border.color: pal.surface
                                    source: "file://" + modelData
                                    sourceSize.width: 96
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pc.modelData.name
                            color: pc.isOn || pc.hot ? pal.fg : pal.fgDim
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: Tokens.size.label
                        }
                        Busy {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pc.applying
                            width: 14; height: 14
                            running: pc.applying
                            color: pal.primary
                        }
                    }
                    FocusRing { ink: pal.edge; radius: pc.radius }
                    PlasmaCore.ToolTipArea {
                        anchors.fill: parent
                        mainText: pc.modelData.name
                        subText: (pc.isOn ? "On screen now" : "Click to bring this look back") + " · right-click to delete"
                        MouseArea {
                            id: pcMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) wp.deletePreset(pc.modelData.name)
                                else if (!pc.isOn) wp.loadPreset(pc.modelData.name)
                            }
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true; visible: wp.presets.length === 0 && !wp.naming }
            TagField {
                id: presetField
                Layout.fillWidth: true
                visible: wp.naming
                palette: pal
                glyph: "bookmark"
                maximumLength: 10
                placeholder: "Preset name, 10 letters max"
                accent: pal.primary
                onAccent: pal.onPrimary
                onAccepted: wp.savePreset(text)
                onEscaped: wp.naming = false
            }
            Pill {
                palette: pal
                icon: wp.naming ? "check" : "bookmark_add"
                text: wp.naming ? "Save" : (wp.presets.length ? "" : "Save preset")
                tooltip: wp.naming ? "" : "Keep the wallpaper of every screen under a name"
                onClicked: {
                    if (wp.naming) { wp.savePreset(presetField.text); return }
                    presetField.text = ""
                    wp.naming = true
                    Qt.callLater(presetField.focusText)
                }
            }
        }

        // get more: describe what you want, wallhaven.py finds the best matches you don't have yet
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            visible: !wp.heroMode
            TagField {
                id: tagField
                Layout.fillWidth: true
                palette: pal
                text: wp.cfg.tags
                placeholder: "Describe what you want: modern, clean, aesthetic…"
                accent: pal.tertiary
                onAccent: pal.col("on_tertiary")
                busy: wp.busy === "fetch"
                onAccepted: wp.fetch(text)
                onEscaped: wp.back()
            }
            Pill {
                palette: pal
                size: tagField.implicitHeight
                icon: "cloud_download"
                text: "Get more"
                accent: pal.tertiary
                onAccent: pal.col("on_tertiary")
                busy: wp.busy === "fetch"
                onClicked: wp.fetch(tagField.text)
            }
        }
        // recent searches: click to get more of the same, right-click to forget
        ListView {
            id: recentTags
            Layout.fillWidth: true
            implicitHeight: 26
            orientation: ListView.Horizontal
            spacing: Tokens.space.xs + 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: !wp.heroMode && wp.cfg.tagHistory.length > 0
            model: wp.cfg.tagHistory
            layer.enabled: contentWidth > width
            layer.effect: EdgeFade { view: recentTags }
            delegate: Chip {
                id: recent
                required property string modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                palette: pal
                interactive: true
                bold: false
                size: 24
                text: modelData
                tint: pal.tertiary
                tooltip: "Get more like this · right-click to forget"
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) { wp.forgetTags(recent.modelData); return }
                    tagField.text = recent.modelData
                    wp.fetch(recent.modelData)
                }
            }
        }

        // the grid (with its loading and empty states)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid
                anchors.fill: parent
                visible: wp.loaded && wallModel.count > 0
                clip: true
                readonly property int columns: 3
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.round(cellWidth * 9 / 16)
                model: wallModel
                // see the app grid: lay out again once the pane has its real width
                onWidthChanged: Qt.callLater(forceLayout)
                onCellWidthChanged: Qt.callLater(forceLayout)
                cacheBuffer: Math.max(0, Math.ceil(wallModel.count / columns) * cellHeight)
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
                }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit } }
                displaced: Transition { NumberAnimation { properties: "x,y"; duration: Tokens.base; easing.type: Tokens.move } }

                activeFocusOnTab: true
                keyNavigationEnabled: true
                currentIndex: -1
                onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
                Keys.onReturnPressed: if (currentIndex >= 0) wp.pick(wallModel.get(currentIndex).name)
                Keys.onEnterPressed: if (currentIndex >= 0) wp.pick(wallModel.get(currentIndex).name)
                Keys.onSpacePressed: if (currentIndex >= 0) wp.pick(wallModel.get(currentIndex).name)
                Keys.onEscapePressed: wp.back()
                // in hero mode the hero previews the wallpaper under the pointer (or the keyboard)
                onCurrentIndexChanged: if (wp.heroMode && activeFocus && currentIndex >= 0) wp.heroHovered(wp.pathOf(wallModel.get(currentIndex).name))

                delegate: Item {
                    id: cell
                    required property string name
                    required property int index
                    readonly property string path: wp.pathOf(name)
                    readonly property var usedOn: wp.screens.filter(s => s.image === path)
                    readonly property bool isCurrent: wp.isCurrent(path)
                    readonly property bool applying: wp.busy === "apply" && wp.pending === path
                    readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
                    readonly property bool hot: hover.containsMouse || focused
                    width: grid.cellWidth
                    height: grid.cellHeight
                    z: hot ? 2 : 0

                    Item {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: Tokens.space.xs + 1
                        scale: hover.pressed ? 0.97 : cell.hot ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                        Rectangle {     // soft glow behind the hovered / current tile
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: Tokens.radius.md + 4
                            color: "transparent"
                            border.width: 4
                            border.color: C.alpha(pal.primary, cell.isCurrent ? 0.35 : cell.hot ? 0.2 : 0)
                            Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                        }
                        Rectangle {     // while the thumbnail loads
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: C.alpha(pal.fg, 0.06)
                            visible: img.status !== Image.Ready
                        }
                        Kirigami.ShadowedImage {
                            id: img
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: "transparent"
                            source: wp.home ? wp.thumb(cell.name) : ""
                            sourceSize.width: 480
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                        }
                        Rectangle {     // hover brighten
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: "white"
                            opacity: cell.hot ? 0.06 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                        }
                        Chip {          // which screens show it (only with more than one screen)
                            visible: !wp.heroMode && wp.screens.length > 1 && cell.usedOn.length > 0
                            anchors { left: parent.left; bottom: parent.bottom; margins: Tokens.space.sm }
                            palette: pal
                            size: 20
                            solid: true
                            tint: C.alpha(pal.col("background"), 0.8)
                            textColor: pal.fg
                            text: cell.usedOn.length === wp.screens.length ? "All" : cell.usedOn.map(s => s.label).join(" · ")
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            color: "transparent"
                            border.width: cell.isCurrent ? 2.5 : 1
                            border.color: cell.isCurrent ? pal.primary
                                        : cell.hot ? C.alpha(pal.primary, 0.8)
                                        : C.alpha(pal.fg, Tokens.alpha.outline)
                            Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                        }
                        Chip {          // just fetched
                            visible: wp.fresh.indexOf(cell.name) >= 0
                            anchors { left: parent.left; top: parent.top; margins: Tokens.space.sm }
                            palette: pal
                            size: 20
                            solid: true
                            tint: pal.tertiary
                            text: "NEW"
                        }
                        Rectangle {     // "current" badge
                            visible: cell.isCurrent
                            anchors { right: parent.right; top: parent.top; margins: Tokens.space.sm }
                            width: 22; height: 22; radius: 11
                            color: pal.primary
                            Text {
                                anchors.centerIn: parent
                                text: "check"
                                color: pal.onPrimary
                                font.family: Tokens.font.icons
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }
                        }
                        Rectangle {     // applying
                            anchors.fill: parent
                            radius: Tokens.radius.md
                            visible: cell.applying
                            color: C.alpha(pal.col("background"), 0.55)
                            Busy {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                running: cell.applying
                                color: pal.primary
                            }
                        }
                        FocusRing { ink: pal.edge; radius: Tokens.radius.md; shown: cell.focused }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: cell.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onContainsMouseChanged: if (wp.heroMode) wp.heroHovered(containsMouse ? cell.path : "")
                            onClicked: wp.pick(cell.name)
                        }
                    }
                }

                function showCurrent() {
                    const want = wp.heroMode ? wp.heroCurrent : wp.targetScreen ? wp.targetScreen.image : wp.current
                    const i = wp.walls.findIndex(n => wp.home + "/Pictures/Wallpapers/" + n === want)
                    if (i >= 0) positionViewAtIndex(i, GridView.Contain)
                }
                Connections {
                    target: wp
                    // after a "Get more", bring the first new one into view
                    function onWallsChanged() {
                        const i = wp.walls.findIndex(n => wp.fresh.indexOf(n) >= 0)
                        if (i >= 0) Qt.callLater(() => grid.positionViewAtIndex(i, GridView.Contain))
                    }
                }
            }

            // loading: placeholder tiles breathing while the list comes in (only while shown)
            Grid {
                id: skeleton
                anchors.fill: parent
                visible: !wp.loaded
                columns: 3
                readonly property real cw: Math.floor(width / 3)
                Repeater {
                    model: 6
                    Item {
                        width: skeleton.cw; height: Math.round(skeleton.cw * 9 / 16)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Tokens.space.xs + 1
                            radius: Tokens.radius.md
                            color: C.alpha(pal.fg, 0.06)
                            SequentialAnimation on opacity {
                                running: skeleton.visible && wp.shown
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
            }

            // empty: nothing in ~/Pictures/Wallpapers yet
            ColumnLayout {
                anchors.centerIn: parent
                visible: wp.loaded && wallModel.count === 0
                spacing: Tokens.space.sm
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "wallpaper"
                    color: pal.muted
                    font.family: Tokens.font.icons
                    font.pixelSize: 44
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No wallpapers yet"
                    color: pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.Bold
                    font.pixelSize: Tokens.size.title
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Drop images in ~/Pictures/Wallpapers, or get some from wallhaven."
                    color: pal.fgDim
                    font.family: Tokens.font.ui
                    font.pixelSize: Tokens.size.label
                }
            }
        }
    }
}
