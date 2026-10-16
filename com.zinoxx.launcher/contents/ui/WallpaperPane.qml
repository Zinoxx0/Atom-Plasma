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

// The Theme page, inside the launcher, laid out from the widest scope down: Themes (whole looks:
// every screen's wallpaper and hand-picked colours under a short name), Screens (the desk map: which
// screen is edited, or all of them), then that screen's look in two tabs. Wallpaper: a grid of
// ~/Pictures/Wallpapers; clicking one runs ~/.config/plasma-rice/rice.py, which sets it and
// re-themes from it; Discover asks wallhaven for more. Colours (ColoursTab): the mood and accents,
// changed live. Everything applies at once; "Save look" keeps it (it stands out while the look on
// screen isn't saved). Labels sit in one left rail. In "hero" mode it only picks the launcher's
// hero image.
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
    property bool naming: false     // the theme name field is out
    property string tab: "walls"    // "walls" | "colours"

    // which screen the page edits, and whether edits go to every screen (the desk map's chain)
    readonly property bool linked: cfg.wallTarget === "all" || !screens.some(s => s.name === cfg.wallTarget)
    readonly property string focusName: {
        const has = n => screens.some(s => s.name === n)
        if (!linked) return cfg.wallTarget
        if (has(cfg.wallFocus)) return cfg.wallFocus
        return has(Screen.name) ? Screen.name : (screens.length ? screens[0].name : "")
    }
    readonly property string target: linked ? "all" : focusName
    readonly property var focusScreen: screens.find(s => s.name === focusName) ?? null
    readonly property var targetScreen: linked ? null : focusScreen
    function pickScreen(name) { cfg.wallFocus = name; cfg.wallTarget = name; Qt.callLater(grid.showCurrent) }
    function toggleLink() {
        if (linked) cfg.wallTarget = focusName
        else { cfg.wallFocus = focusName; cfg.wallTarget = "all" }
    }
    // the look on screen matches no saved theme: Save look stands out
    readonly property bool unsaved: loaded && !presets.some(pr => presetIsOn(pr))
    property bool discover: false   // the wallhaven search is open
    readonly property real rail: 76 // the label column every row hangs off
    readonly property string context: !loaded ? "" : linked ? "Editing every screen together"
        : focusScreen ? "Editing the " + focusScreen.label + " screen" + (focusScreen.lead ? " · its look drives apps and terminals" : "") : ""
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
                wp.status = name ? "Saved theme “" + name + "”" : "Couldn't save the theme"
                wp.reload()
            } else if (kind === "pdelete") {
                wp.reload()
            } else if (kind === "state") {
                const parts = out.split("\n@@\n")
                try { wp.screens = JSON.parse(parts[0]) } catch (e) {}
                try { wp.presets = JSON.parse(parts[1]) } catch (e) {}
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
        status = "Deleted theme “" + name + "”"
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset delete ' + q(name) + ' #pdelete ' + Date.now())
    }
    // on screen right now: every connected screen it knows shows its wallpaper with the same
    // hand-picked colours, and the theme is its
    function ovKey(m) {
        return JSON.stringify(Object.keys(m).sort().map(o => [o, Object.keys(m[o]).sort().map(k => [k, m[o][k]])]))
    }
    function presetIsOn(pr) {
        const known = screens.filter(s => pr.screens[s.name] !== undefined)
        if (!(known.length > 0 && known.every(s => s.image === pr.screens[s.name]) && current === pr.theme)) return false
        const now = {}, kept = {}
        for (const s of known) {
            if (s.overrides && Object.keys(s.overrides).length) now[s.name] = s.overrides
            if (pr.overrides && pr.overrides[s.name] && Object.keys(pr.overrides[s.name]).length) kept[s.name] = pr.overrides[s.name]
        }
        return ovKey(now) === ovKey(kept)
    }
    // screens and themes again (after a colour change: accents, custom marks, Save look)
    function refreshState() {
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" screens; printf "\\n@@\\n"; '
            + 'python3 "$HOME/.config/plasma-rice/rice.py" presets #state ' + Date.now())
    }
    Timer { id: statusTimer; interval: 5000; onTriggered: wp.status = "" }
    onStatusChanged: if (status) statusTimer.restart()
    onDiscoverChanged: if (discover) Qt.callLater(() => tagField.focusText())
    function presetThumbs(pr) {     // left to right like the screens
        const order = screens.map(s => s.name)
        return Object.keys(pr.thumbs || {}).sort((a, b) => order.indexOf(a) - order.indexOf(b)).map(o => pr.thumbs[o])
    }

    onShownChanged: if (shown) { reload(); naming = false; Qt.callLater(grid.showCurrent) }
    Component.onCompleted: reload()

    Keys.onEscapePressed: wp.back()

    component RailLabel: Text {
        Layout.preferredWidth: wp.rail
        Layout.alignment: Qt.AlignVCenter
        color: pal.muted
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Tokens.size.small
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.space.md

        // header: back, the page, and what it's editing right now (or what just happened)
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
                    text: wp.heroMode ? "Hero image" : "Theme"
                    color: pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.Bold
                    font.pixelSize: Tokens.size.heading
                }
                Text {
                    Layout.fillWidth: true
                    text: wp.heroMode ? "Pick the picture behind the clock · hover to preview" : wp.status || wp.context
                    elide: Text.ElideRight
                    color: wp.status ? pal.fg : pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: Tokens.size.label
                }
            }
            Busy {
                visible: wp.busy !== "" || colours.busy
                running: visible
                width: 18; height: 18
                color: pal.primary
            }
        }

        // themes: whole looks (every screen's wallpaper and hand-picked colours). Click to bring one
        // back, right-click to delete; Save look names the look on screen (10 characters at most)
        RowLayout {
            Layout.fillWidth: true
            visible: !wp.heroMode
            spacing: 0
            RailLabel { text: "Themes" }
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
                         : C.alpha(pal.fg, pcMouse.pressed ? 0.12 : hot ? 0.08 : 0.04)
                    border.width: 1
                    border.color: isOn ? pal.primary : hot ? C.alpha(pal.primary, 0.5) : "transparent"
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
                        Text {          // keeps hand-picked colours too
                            visible: !!pc.modelData.overrides
                            anchors.verticalCenter: parent.verticalCenter
                            text: "palette"
                            color: pal.muted
                            font.family: Tokens.font.icons
                            font.pixelSize: 14
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
                        subText: (pc.modelData.overrides ? "Wallpapers and hand-picked colours · " : "Wallpapers · ")
                               + (pc.isOn ? "on screen now" : "click to bring it back") + " · right-click to delete"
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
            Text {
                Layout.fillWidth: true
                visible: wp.presets.length === 0 && !wp.naming
                text: "Keep the look on your screens to come back to it"
                elide: Text.ElideRight
                color: pal.muted
                font.family: Tokens.font.ui
                font.pixelSize: Tokens.size.label
            }
            TagField {
                id: presetField
                Layout.fillWidth: true
                visible: wp.naming
                palette: pal
                glyph: "bookmark"
                maximumLength: 10
                placeholder: "Name this look, 10 letters max"
                accent: pal.primary
                onAccent: pal.onPrimary
                onAccepted: wp.savePreset(text)
                onEscaped: wp.naming = false
            }
            Item { implicitWidth: Tokens.space.sm }
            Pill {
                palette: pal
                icon: wp.naming ? "check" : "bookmark_add"
                text: wp.naming ? "Save" : "Save look"
                accent: wp.unsaved || wp.naming ? pal.primary : pal.fgDim
                onAccent: wp.unsaved || wp.naming ? pal.onPrimary : pal.surfaceLowest
                tooltip: wp.naming ? "" : wp.unsaved ? "This look isn't saved yet: keep every screen's wallpaper and colours as a theme"
                                                     : "This look is saved · save it again under another name"
                onClicked: {
                    if (wp.naming) { wp.savePreset(presetField.text); return }
                    presetField.text = ""
                    wp.naming = true
                    Qt.callLater(presetField.focusText)
                }
                Rectangle {     // unsaved
                    visible: wp.unsaved && !wp.naming
                    anchors { right: parent.right; top: parent.top; margins: -1 }
                    width: 8; height: 8; radius: 4
                    color: pal.primary
                    border.width: 1.5
                    border.color: pal.surfaceLowest
                }
            }
        }

        // screens: the desk map picks the screen to edit; the chain edits all of them together
        RowLayout {
            Layout.fillWidth: true
            visible: !wp.heroMode && wp.screens.length > 1
            spacing: 0
            RailLabel { text: "Screens" }
            DeskMap {
                Layout.preferredHeight: 56
                Layout.preferredWidth: implicitWidth
                Layout.maximumWidth: 360
                pal: pal
                screens: wp.screens
                focusName: wp.focusName
                linked: wp.linked
                onPicked: name => wp.pickScreen(name)
            }
            Item { implicitWidth: Tokens.space.md }
            Chip {
                palette: pal
                interactive: true
                size: 28
                icon: wp.linked ? "link" : "link_off"
                text: "All screens"
                selected: wp.linked
                tint: pal.primary
                tooltip: wp.linked ? "Wallpapers and colours go to every screen · click a screen to edit it alone"
                                   : "Edit every screen together"
                onClicked: wp.toggleLink()
            }
            Item { Layout.fillWidth: true }
            Row {           // the star's meaning
                spacing: 3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "star"
                    color: pal.muted
                    font.family: Tokens.font.icons
                    font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "drives apps"
                    color: pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: Tokens.size.caption
                }
            }
        }

        // the look of the chosen screen: tabs, and each tab's own tools on the right
        Item {
            Layout.fillWidth: true
            implicitHeight: 34
            visible: !wp.heroMode
            Rectangle {     // the tabs' baseline
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: C.alpha(pal.edge, 0.08)
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom }
                spacing: Tokens.space.lg
                Repeater {
                    model: [{ id: "walls", text: "Wallpaper" }, { id: "colours", text: "Colours" }]
                    Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: wp.tab === modelData.id
                        width: tbText.implicitWidth
                        height: 34
                        Text {
                            id: tbText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -1
                            text: tb.modelData.text
                            color: tb.on || tbMouse.containsMouse ? pal.fg : pal.fgDim
                            font.family: Tokens.font.ui
                            font.weight: tb.on ? Font.Bold : Font.DemiBold
                            font.pixelSize: Tokens.size.body
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 2
                            radius: 1
                            color: pal.primary
                            opacity: tb.on ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                        }
                        MouseArea {
                            id: tbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wp.tab = tb.modelData.id
                        }
                    }
                }
            }
            Row {           // Wallpaper: step through the library, the folder, Discover
                visible: wp.tab === "walls"
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
                spacing: 2
                IconButton { palette: pal; size: 30; icon: "shuffle"; tooltip: "Shuffle"; onClicked: wp.apply("random") }
                IconButton { palette: pal; size: 30; icon: "skip_previous"; tooltip: "Previous"; onClicked: wp.apply("prev") }
                IconButton { palette: pal; size: 30; icon: "skip_next"; tooltip: "Next"; onClicked: wp.apply("next") }
                IconButton { palette: pal; size: 30; icon: "folder_open"; tooltip: "Open the wallpaper folder"; onClicked: wp.openFolder() }
                Item { width: Tokens.space.xs; height: 1 }
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    palette: pal
                    interactive: true
                    size: 28
                    icon: "travel_explore"
                    text: "Discover"
                    selected: wp.discover
                    tint: pal.tertiary
                    tooltip: "Find new wallpapers on wallhaven"
                    onClicked: wp.discover = !wp.discover
                }
            }
            Row {           // Colours: undo, back to the wallpaper's own
                visible: wp.tab === "colours"
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
                spacing: Tokens.space.xs + 2
                Chip {
                    palette: pal
                    interactive: true
                    size: 28
                    icon: "undo"
                    text: "Undo"
                    enabled: colours.canUndo
                    opacity: enabled ? 1 : 0.4
                    tint: pal.fgDim
                    onClicked: colours.undo()
                }
                Chip {
                    palette: pal
                    interactive: true
                    size: 28
                    icon: "auto_awesome"
                    text: "Automatic"
                    enabled: colours.custom && !colours.busy
                    opacity: enabled ? 1 : 0.4
                    tint: pal.secondary
                    tooltip: "Back to the wallpaper's own colours"
                    onClicked: colours.automatic()
                }
            }
        }

        // Discover: describe what you want, wallhaven.py finds the best matches you don't have yet;
        // recent searches below (click to get more of the same, right-click to forget)
        ColumnLayout {
            Layout.fillWidth: true
            visible: !wp.heroMode && wp.tab === "walls" && wp.discover
            spacing: Tokens.space.sm
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.sm
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
                    onEscaped: wp.discover = false
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
            ListView {
                id: recentTags
                Layout.fillWidth: true
                implicitHeight: 26
                orientation: ListView.Horizontal
                spacing: Tokens.space.xs + 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: wp.cfg.tagHistory.length > 0
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
        }

        // Colours: the chosen screen's mood and accents, live
        ColoursTab {
            id: colours
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !wp.heroMode && wp.tab === "colours"
            pal: pal
            rail: wp.rail
            screen: wp.focusName
            target: wp.target
            onChanged: wp.refreshState()
        }

        // the grid (with its loading and empty states)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: wp.heroMode || wp.tab === "walls"

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
