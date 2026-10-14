import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// HyDE-style wallpaper selector: a grid of ~/Pictures/Wallpapers; clicking one
// runs ~/.config/plasma-rice/rice.py, which sets it on the chosen screen(s) and
// re-themes the desktop from it. Scroll on the panel icon to step through this
// screen's wallpapers.
PlasmoidItem {
    id: root

    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    property string home: ""
    property var walls: []          // file names in ~/Pictures/Wallpapers
    property string current: ""     // last wallpaper picked (drives the global theme)
    property var screens: []        // [{name, label, main, image, thumb}] left to right, from rice.py screens
    property string busy: ""        // "" | "apply" | "fetch"
    property string pending: ""     // path being applied
    property string status: ""
    property bool loaded: false
    property var fresh: []          // file names brought by the last "Get more" (badged in the grid)

    readonly property string screenName: Screen.name   // output this bar is on
    onScreenNameChanged: reload()
    // screens the popup applies to: "all" or an output name (remembered; falls back if unplugged)
    readonly property string target: screens.some(s => s.name === Plasmoid.configuration.target) ? Plasmoid.configuration.target : "all"
    readonly property var targetScreen: screens.find(s => s.name === target) ?? null
    readonly property var here: screens.find(s => s.name === screenName) ?? null

    function col(n, f) { return pal[n] ?? f }
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function thumb(name) { return "file://" + home + "/.cache/rice/thumbs-plasma/" + name.replace(/\.[^.]+$/, "") + ".jpg" }
    function fileName(p) { return p ? p.split("/").pop() : "" }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const out = data["stdout"] ?? "";
            const kind = (source.match(/#(\w+) \d+$/) || [])[1];     // the tags in a fetch could contain anything
            if (kind === "list") {
                const parts = out.split("\n@@\n");
                root.home = (parts[0] ?? "").trim();
                root.walls = (parts[1] ?? "").split("\n").filter(s => s.length);
                root.current = (parts[2] ?? "").trim();
                try { root.pal = JSON.parse(parts[3]) } catch (e) {}
                try { root.screens = JSON.parse(parts[4]) } catch (e) {}
                root.loaded = true;
            } else if (kind === "apply") {
                root.busy = ""; root.pending = "";
                root.reload();
            } else if (kind === "fetch") {
                root.busy = "";
                try {
                    const r = JSON.parse(out);
                    const what = "“" + r.tags.join(", ") + "”";
                    root.fresh = r.saved.map(p => root.fileName(p));
                    root.status = r.saved.length ? "Added " + r.saved.length + " for " + what : "Nothing new for " + what;
                    if (r.thin && r.thin.length) root.status += " · no luck with " + r.thin.join(", ");
                } catch (e) { root.status = "Couldn't reach wallhaven" }
                root.reload();
            }
            disconnectSource(source);
        }
    }
    function reload() {
        sh.connectSource('echo "$HOME"; printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" thumbs; '
            + 'find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -printf "%f\\n" | sort; '
            + 'printf "\\n@@\\n"; readlink -f "$HOME/.local/state/rice/wallpaper"; printf "\\n@@\\n"; '
            + 'cat "$HOME/.local/state/rice/palette-' + screenName + '.json" 2>/dev/null || cat "$HOME/.local/state/rice/palette.json"; '
            + 'printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" screens #list ' + Date.now());
    }
    // scr: "all", "focused" or an output name; defaults to the popup's target
    function apply(arg, scr) {
        if (busy) return;
        busy = "apply"; pending = arg; status = "";
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" ' + q(arg) + ' --screen ' + q(scr || target) + ' #apply ' + Date.now());
    }
    function stepHere(arg) { apply(arg, screenName || "focused") }
    // tags: "modern, clean, aesthetic"; each click brings the next best matches (wallhaven.py).
    // Empty: one of the default themes.
    function fetch(tags) {
        if (busy) return;
        const t = String(tags ?? "").trim();
        busy = "fetch"; status = t ? "Looking for “" + t + "”…" : "Fetching from wallhaven…";
        if (t) {
            Plasmoid.configuration.tags = t;
            Plasmoid.configuration.tagHistory = [t].concat(Plasmoid.configuration.tagHistory
                .filter(h => h.toLowerCase() !== t.toLowerCase())).slice(0, 6);
        }
        sh.connectSource('python3 "$HOME/.config/plasma-rice/wallhaven.py" 6 ' + q(t) + ' #fetch ' + Date.now());
    }
    function forgetTags(t) { Plasmoid.configuration.tagHistory = Plasmoid.configuration.tagHistory.filter(h => h !== t) }
    function openFolder() { Qt.openUrlExternally("file://" + home + "/Pictures/Wallpapers") }

    Component.onCompleted: reload()
    onExpandedChanged: if (root.expanded) reload()
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: reload()

    Plasmoid.contextualActions: [
        PlasmaCore.Action { text: "Next wallpaper (this screen)"; icon.name: "go-next"; onTriggered: root.stepHere("next") },
        PlasmaCore.Action { text: "Previous wallpaper (this screen)"; icon.name: "go-previous"; onTriggered: root.stepHere("prev") },
        PlasmaCore.Action { text: "Random wallpaper (this screen)"; icon.name: "media-playlist-shuffle"; onTriggered: root.stepHere("random") },
        PlasmaCore.Action { text: "Get more from wallhaven"; icon.name: "download"; onTriggered: root.fetch(Plasmoid.configuration.tags) },
        PlasmaCore.Action { text: "Open wallpaper folder"; icon.name: "folder-pictures"; onTriggered: root.openFolder() }
    ]

    toolTipMainText: "Wallpaper"
    toolTipSubText: (here ? fileName(here.image) : fileName(current)) + "\nScroll to switch this screen · click for all"
    preferredRepresentation: compactRepresentation

    // ---------- panel: tiny rounded preview of this screen's wallpaper ----------
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        Layout.minimumWidth: 46 * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
        property real acc: 0
        onWheel: wheel => {
            acc += wheel.angleDelta.y;
            if (Math.abs(acc) >= 120 && !root.busy) { root.stepHere(acc < 0 ? "next" : "prev"); acc = 0 }
        }

        Item {
            id: chip
            anchors.centerIn: parent
            width: 34 * root.uiScale; height: 22 * root.uiScale
            scale: compact.containsMouse ? 1.1 : 1
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Kirigami.ShadowedImage {
                anchors.fill: parent
                radius: 7
                color: "transparent"
                source: root.here && root.here.thumb ? "file://" + root.here.thumb
                      : root.current && root.home ? root.thumb(root.fileName(root.current)) : ""
                sourceSize.width: 96
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                radius: 7
                color: "transparent"
                border.width: 1.5
                border.color: compact.containsMouse || root.expanded ? root.col("primary", "#7aa2f7") : Qt.alpha(root.col("on_surface", "#c0caf5"), 0.35)
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }
            Rectangle {   // spinner while re-theming
                anchors.fill: parent
                radius: 7
                visible: root.busy === "apply"
                color: Qt.alpha(root.col("background", "#1a1b26"), 0.6)
                Text {
                    anchors.centerIn: parent
                    text: "progress_activity"
                    color: root.col("primary", "#7aa2f7")
                    font.family: "Material Symbols Rounded"; font.pixelSize: 16
                    RotationAnimation on rotation { running: root.busy === "apply"; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                }
            }
        }
    }

    // ---------- popup ----------
    fullRepresentation: Item {
        Layout.preferredWidth: 780
        Layout.preferredHeight: 600
        Layout.minimumWidth: 560
        Layout.minimumHeight: 420

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // header: title, current name, palette swatches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Wallpaper"
                        color: root.col("on_surface", "#c0caf5")
                        font.family: "Inter Display"; font.weight: Font.ExtraBold; font.pixelSize: 24
                    }
                    Text {
                        text: root.targetScreen ? root.fileName(root.targetScreen.image) || "–"
                            : root.screens.some(s => s.image !== root.screens[0].image) ? root.screens.length + " screens, different wallpapers"
                            : root.fileName(root.current) || "–"
                        color: root.col("on_surface_variant", "#a9b1d6")
                        font.family: "Inter"; font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: -6   // overlapping candy dots
                    Repeater {
                        model: ["primary", "secondary", "tertiary", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
                        Rectangle {
                            required property string modelData
                            required property int index
                            width: 24; height: 24; radius: 12
                            color: root.col(modelData, "#888")
                            border.width: 2
                            border.color: root.col("surface", "#1a1b26")
                            z: 20 - index
                            scale: dotHover.containsMouse ? 1.25 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            MouseArea { id: dotHover; anchors.fill: parent; hoverEnabled: true }
                            QQC2.ToolTip.visible: dotHover.containsMouse
                            QQC2.ToolTip.text: modelData + "  " + root.col(modelData, "")
                        }
                    }
                }
            }

            // target screens: All, then one chip per screen (left to right) showing what's on it
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.screens.length > 1
                Repeater {
                    model: root.screens.length > 1 ? [{ name: "all", label: "All screens", thumb: "", main: false }].concat(root.screens) : []
                    Rectangle {
                        id: scr
                        required property var modelData
                        readonly property bool selected: root.target === modelData.name
                        implicitHeight: 44
                        implicitWidth: scrRow.implicitWidth + 18
                        radius: 12
                        color: selected ? Qt.alpha(root.col("primary", "#7aa2f7"), 0.18)
                                        : Qt.alpha(root.col("on_surface", "#c0caf5"), scrHover.containsMouse ? 0.10 : 0.05)
                        border.width: selected ? 1.5 : 1
                        border.color: selected ? root.col("primary", "#7aa2f7")
                                    : scrHover.containsMouse ? Qt.alpha(root.col("primary", "#7aa2f7"), 0.6)
                                    : Qt.alpha(root.col("on_surface", "#c0caf5"), 0.10)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            id: scrRow
                            anchors.centerIn: parent
                            spacing: 8
                            Item {
                                implicitWidth: 44; implicitHeight: 26
                                Kirigami.ShadowedImage {
                                    anchors.fill: parent
                                    visible: scr.modelData.thumb !== ""
                                    radius: 6
                                    color: "transparent"
                                    source: scr.modelData.thumb ? "file://" + scr.modelData.thumb : ""
                                    sourceSize.width: 96
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: scr.modelData.name === "all"
                                    text: "view_column"
                                    color: scr.selected ? root.col("primary", "#7aa2f7") : root.col("on_surface_variant", "#a9b1d6")
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 22
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: scr.modelData.label
                                    color: root.col("on_surface", "#c0caf5")
                                    font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 12
                                }
                                Text {
                                    text: scr.modelData.name === "all" ? root.screens.length + " screens"
                                        : scr.modelData.name + (scr.modelData.main ? " · main" : "")
                                    color: root.col("muted", "#565f89")
                                    font.family: "Inter"; font.pixelSize: 10
                                }
                            }
                        }
                        MouseArea {
                            id: scrHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Plasmoid.configuration.target = scr.modelData.name; Qt.callLater(grid.showCurrent) }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                readonly property color acc: root.col("primary", "#7aa2f7")
                PillButton { icon: "shuffle"; label: "Shuffle"; accent: parent.acc; fg: root.col("on_surface", "#c0caf5"); accentText: root.col("on_primary", "#1a1b26"); busy: root.busy === "apply" && root.pending === "random"; onClicked: root.apply("random") }
                PillButton { icon: "skip_previous"; accent: parent.acc; accentText: root.col("on_primary", "#1a1b26"); onClicked: root.apply("prev") }
                PillButton { icon: "skip_next"; accent: parent.acc; accentText: root.col("on_primary", "#1a1b26"); onClicked: root.apply("next") }
                PillButton { icon: "folder_open"; accent: root.col("secondary", "#9aa5ce"); accentText: root.col("on_secondary", "#1a1b26"); onClicked: root.openFolder() }
                Item { Layout.fillWidth: true }
                Text {
                    Layout.maximumWidth: 420
                    text: root.status || (root.walls.length + " wallpapers")
                    elide: Text.ElideRight
                    color: root.col("muted", "#565f89")
                    font.family: "Inter"; font.pixelSize: 12
                }
            }

            // get more: describe what you want, wallhaven.py finds the best matches you don't have yet
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TagField {
                    id: tagField
                    Layout.fillWidth: true
                    text: Plasmoid.configuration.tags
                    placeholder: "Describe what you want: modern, clean, aesthetic…"
                    accent: root.col("tertiary", "#bb9af7")
                    fg: root.col("on_surface", "#c0caf5")
                    muted: root.col("muted", "#565f89")
                    busy: root.busy === "fetch"
                    onAccepted: root.fetch(text)
                }
                PillButton {
                    implicitHeight: 34
                    icon: root.busy === "fetch" ? "progress_activity" : "cloud_download"
                    label: "Get more"
                    accent: root.col("tertiary", "#bb9af7")
                    fg: root.col("on_surface", "#c0caf5")
                    accentText: root.col("on_tertiary", "#1a1b26")
                    busy: root.busy === "fetch"
                    onClicked: root.fetch(tagField.text)
                }
            }
            // recent searches: click to get more of the same, right-click to forget
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: Plasmoid.configuration.tagHistory.length > 0
                Repeater {
                    model: Plasmoid.configuration.tagHistory
                    Rectangle {
                        id: recent
                        required property string modelData
                        height: 24
                        width: chipText.implicitWidth + 20
                        radius: 12
                        readonly property color acc: root.col("tertiary", "#bb9af7")
                        color: chipHover.containsMouse ? Qt.alpha(acc, 0.22) : Qt.alpha(root.col("on_surface", "#c0caf5"), 0.05)
                        border.width: 1
                        border.color: chipHover.containsMouse ? acc : Qt.alpha(acc, 0.18)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: recent.modelData
                            color: chipHover.containsMouse ? root.col("on_surface", "#c0caf5") : root.col("on_surface_variant", "#a9b1d6")
                            font.family: "Inter"; font.pixelSize: 11
                        }
                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { root.forgetTags(recent.modelData); return }
                                tagField.text = recent.modelData
                                root.fetch(recent.modelData)
                            }
                        }
                        QQC2.ToolTip.visible: chipHover.containsMouse
                        QQC2.ToolTip.delay: 600
                        QQC2.ToolTip.text: "Get more like this · right-click to forget"
                    }
                }
            }

            // grid
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.floor(width / 4)
                cellHeight: Math.round(cellWidth * 9 / 16)
                model: root.walls
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

                add: Transition { NumberAnimation { properties: "opacity,scale"; from: 0; duration: 260; easing.type: Easing.OutCubic } }

                delegate: Item {
                    id: cell
                    required property string modelData
                    required property int index
                    readonly property string path: root.home + "/Pictures/Wallpapers/" + modelData
                    // screens showing it; "current" = already on every targeted screen
                    readonly property var usedOn: root.screens.filter(s => s.image === path)
                    readonly property bool isCurrent: root.targetScreen ? root.targetScreen.image === path
                                                    : root.screens.length ? usedOn.length === root.screens.length
                                                    : path === root.current
                    readonly property bool applying: root.busy === "apply" && root.pending === path
                    width: grid.cellWidth
                    height: grid.cellHeight
                    z: hover.containsMouse ? 2 : 0

                    Item {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 6
                        scale: hover.pressed ? 0.97 : hover.containsMouse ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                        // soft glow behind the hovered/current tile
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 16
                            color: "transparent"
                            border.width: 4
                            border.color: Qt.alpha(root.col("primary", "#7aa2f7"), cell.isCurrent ? 0.35 : hover.containsMouse ? 0.2 : 0)
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                        }
                        Kirigami.ShadowedImage {
                            id: img
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            source: root.home ? root.thumb(cell.modelData) : ""
                            sourceSize.width: 480
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                        }
                        Rectangle {   // hover brighten
                            anchors.fill: parent
                            radius: 12
                            color: "white"
                            opacity: hover.containsMouse ? 0.06 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        Rectangle {   // which screens show it (only with more than one screen)
                            visible: root.screens.length > 1 && cell.usedOn.length > 0
                            anchors { left: parent.left; bottom: parent.bottom; margins: 7 }
                            width: usedText.implicitWidth + 14; height: 20; radius: 10
                            color: Qt.alpha(root.col("background", "#1a1b26"), 0.78)
                            Text {
                                id: usedText
                                anchors.centerIn: parent
                                text: cell.usedOn.length === root.screens.length ? "All screens" : cell.usedOn.map(s => s.label).join(" · ")
                                color: root.col("on_surface", "#c0caf5")
                                font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 10
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.width: cell.isCurrent ? 2.5 : 1
                            border.color: cell.isCurrent ? root.col("primary", "#7aa2f7")
                                        : hover.containsMouse ? Qt.alpha(root.col("primary", "#7aa2f7"), 0.8)
                                        : Qt.alpha(root.col("on_surface", "#c0caf5"), 0.10)
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        Rectangle {   // just fetched
                            visible: root.fresh.indexOf(cell.modelData) >= 0
                            anchors { left: parent.left; top: parent.top; margins: 7 }
                            width: newText.implicitWidth + 14; height: 20; radius: 10
                            color: root.col("tertiary", "#bb9af7")
                            Text {
                                id: newText
                                anchors.centerIn: parent
                                text: "NEW"
                                color: root.col("on_tertiary", "#1a1b26")
                                font.family: "Inter"; font.weight: Font.Black; font.pixelSize: 10
                            }
                        }
                        Rectangle {   // "current" badge
                            visible: cell.isCurrent
                            anchors { right: parent.right; top: parent.top; margins: 7 }
                            width: 24; height: 24; radius: 12
                            color: root.col("primary", "#7aa2f7")
                            Text {
                                anchors.centerIn: parent
                                text: "check"
                                color: root.col("on_primary", "#1a1b26")
                                font.family: "Material Symbols Rounded"; font.pixelSize: 17; font.weight: Font.Bold
                            }
                        }
                        Rectangle {   // applying overlay
                            anchors.fill: parent
                            radius: 12
                            visible: cell.applying
                            color: Qt.alpha(root.col("background", "#1a1b26"), 0.55)
                            Text {
                                anchors.centerIn: parent
                                text: "progress_activity"
                                color: root.col("primary", "#7aa2f7")
                                font.family: "Material Symbols Rounded"; font.pixelSize: 30
                                RotationAnimation on rotation { running: cell.applying; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!cell.isCurrent) root.apply(cell.path)
                        }
                    }
                }

                function showCurrent() {
                    const want = root.targetScreen ? root.targetScreen.image : root.current;
                    const i = root.walls.findIndex(n => root.home + "/Pictures/Wallpapers/" + n === want);
                    if (i >= 0) positionViewAtIndex(i, GridView.Contain);
                }
                Connections {
                    target: root
                    function onExpandedChanged() { if (root.expanded) Qt.callLater(grid.showCurrent) }
                    // after a "Get more", bring the first new one into view
                    function onWallsChanged() {
                        const i = root.walls.findIndex(n => root.fresh.indexOf(n) >= 0);
                        if (i >= 0) Qt.callLater(() => grid.positionViewAtIndex(i, GridView.Contain));
                    }
                }
            }
        }
    }
}
