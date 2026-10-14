import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// wlogout-style session menu. Log out / restart / shut down need a second
// click within 4 s, so a stray click can't end the session.
PlasmoidItem {
    id: root

    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    property string user: ""
    property string host: ""
    property real uptime: 0
    property string armed: ""

    function col(n, f) { return pal[n] ?? f }

    readonly property var actions: [
        { id: "lock",     icon: "lock",               label: "Lock",      color: "primary",  confirm: false, cmd: "loginctl lock-session" },
        { id: "sleep",    icon: "bedtime",            label: "Sleep",     color: "tertiary", confirm: false, cmd: "systemctl suspend" },
        { id: "logout",   icon: "logout",             label: "Log out",   color: "yellow",   confirm: true,  cmd: "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout" },
        { id: "reboot",   icon: "restart_alt",        label: "Restart",   color: "orange",   confirm: true,  cmd: "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot" },
        { id: "shutdown", icon: "power_settings_new", label: "Shut down", color: "red",      confirm: true,  cmd: "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown" },
    ]

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.indexOf("#info") >= 0) {
                const p = (data["stdout"] ?? "").split("\n@@\n");
                root.user = (p[0] ?? "").trim();
                root.host = (p[1] ?? "").trim();
                root.uptime = parseFloat(p[2] ?? "0");
                try { root.pal = JSON.parse(p[3]) } catch (e) {}
            }
            disconnectSource(source);
        }
    }
    function refresh() {
        sh.connectSource('id -un; printf "\\n@@\\n"; cat /proc/sys/kernel/hostname; printf "\\n@@\\n"; cut -d" " -f1 /proc/uptime; printf "\\n@@\\n"; cat "$HOME/.local/state/rice/palette-' + screenName + '.json" 2>/dev/null || cat "$HOME/.local/state/rice/palette.json" #info ' + Date.now());
    }
    Component.onCompleted: refresh()
    onExpandedChanged: { armed = ""; if (root.expanded) refresh() }
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()
    // each bar follows its own screen's wallpaper (palette-<output>.json, see rice.py)
    readonly property string screenName: Screen.name
    onScreenNameChanged: refresh()

    function trigger(a) {
        if (a.confirm && armed !== a.id) { armed = a.id; disarm.restart(); return }
        armed = "";
        root.expanded = false;
        sh.connectSource(a.cmd + " #run " + Date.now());
    }
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }

    function upText(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return "up " + (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m";
    }

    toolTipMainText: "Session"
    toolTipSubText: "Lock, sleep, log out, restart, shut down"
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        Layout.minimumWidth: 36 * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
        Text {      // the island around it lights up on hover (Panel Colorizer); the icon turns and warms
            anchors.centerIn: parent
            text: "power_settings_new"
            color: compact.containsMouse || root.expanded ? root.col("red", "#f7768e") : root.col("on_surface", Kirigami.Theme.textColor)
            font.family: "Material Symbols Rounded"
            font.pixelSize: Math.round(20 * root.uiScale)
            rotation: compact.containsMouse ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: tiles.implicitWidth + 24
        Layout.preferredHeight: content.implicitHeight + 24
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 16

            RowLayout {
                spacing: 14
                Rectangle {   // avatar: initial on a primary -> tertiary gradient
                    implicitWidth: 52; implicitHeight: 52; radius: 26
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.col("primary", "#7aa2f7") }
                        GradientStop { position: 1; color: root.col("tertiary", "#bb9af7") }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.user ? root.user[0].toUpperCase() : "?"
                        color: root.col("on_primary", "#1a1b26")
                        font.family: "Inter Display"; font.weight: Font.Black; font.pixelSize: 24
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Text {
                        text: root.user
                        color: root.col("on_surface", "#c0caf5")
                        font.family: "Inter Display"; font.weight: Font.ExtraBold; font.pixelSize: 20
                    }
                    Text {
                        text: root.host + "  ·  " + root.upText(root.uptime)
                        color: root.col("on_surface_variant", "#a9b1d6")
                        font.family: "Inter"; font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Row {
                id: tiles
                spacing: 10
                Repeater {
                    model: root.actions
                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property color tint: root.col(modelData.color, "#7aa2f7")
                        readonly property bool isArmed: root.armed === modelData.id
                        readonly property bool hot: m.containsMouse || isArmed
                        width: 92; height: 104
                        radius: 22
                        color: isArmed ? tint : Qt.alpha(tint, hot ? 0.24 : 0.10)
                        border.width: 1
                        border.color: Qt.alpha(tint, hot ? 0.7 : 0.25)
                        scale: m.pressed ? 0.94 : hot ? 1.05 : 1
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 160 } }

                        // entrance: tiles rise in one after another
                        opacity: 0
                        transform: Translate { id: rise; y: 14 }
                        SequentialAnimation {
                            id: enter
                            PauseAnimation { duration: tile.index * 45 }
                            ParallelAnimation {
                                NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 220 }
                                NumberAnimation { target: rise; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack }
                            }
                        }
                        Connections {
                            target: root
                            function onExpandedChanged() {
                                if (root.expanded) { tile.opacity = 0; rise.y = 14; enter.restart() }
                            }
                        }
                        Component.onCompleted: if (root.expanded) enter.restart()

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.icon
                                color: tile.isArmed ? root.col("background", "#1a1b26") : tile.tint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: tile.hot ? 36 : 32
                                Behavior on font.pixelSize { NumberAnimation { duration: 160 } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.isArmed ? "Again?" : tile.modelData.label
                                color: tile.isArmed ? root.col("background", "#1a1b26") : root.col("on_surface", "#c0caf5")
                                font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 12
                            }
                        }
                        // countdown bar while armed
                        Rectangle {
                            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 18; bottomMargin: 10 }
                            height: 3; radius: 1.5
                            color: root.col("background", "#1a1b26")
                            opacity: 0.6
                            width: 0
                            visible: tile.isArmed
                            NumberAnimation on width {
                                running: tile.isArmed
                                from: tile.width - 36; to: 0; duration: 4000
                            }
                        }
                        MouseArea {
                            id: m
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.trigger(tile.modelData)
                        }
                    }
                }
            }
        }
    }
}
