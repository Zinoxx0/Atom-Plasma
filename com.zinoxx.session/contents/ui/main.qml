import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import "Rice"
import "Rice/Color.js" as C

// wlogout-style session menu. Log out / restart / shut down need a second
// click within 4 s, so a stray click can't end the session.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    readonly property real uiScale: pal.uiScale
    property real uptime: 0
    property string armed: ""

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
            if (source.indexOf("#up") >= 0) root.uptime = parseFloat(data["stdout"] ?? "0") || 0;
            disconnectSource(source);
        }
    }
    function refresh() { sh.connectSource('cut -d" " -f1 /proc/uptime #up ' + Date.now()) }
    Component.onCompleted: refresh()
    onExpandedChanged: { armed = ""; if (root.expanded) refresh() }

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
        // a single-widget island: the same side padding as every rice bar widget
        Layout.minimumWidth: power.implicitWidth + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
        Text {      // the island around it lights up on hover (Panel Colorizer); the icon turns and warms
            id: power
            anchors.centerIn: parent
            text: "power_settings_new"
            color: compact.containsMouse || root.expanded ? pal.red : pal.fg
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(20 * root.uiScale)
            rotation: compact.containsMouse ? 90 : 0
            // one turn per hover, barely past the mark: not a loop, and no bouncy overshoot
            Behavior on rotation { NumberAnimation { duration: Tokens.slow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: content.implicitWidth + 2 * Tokens.space.lg
        Layout.preferredHeight: content.implicitHeight + 2 * Tokens.space.lg
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight
        // never bigger than the content: Plasma restores a remembered popup size otherwise
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        PopupIn {
            anchors.fill: parent
            active: root.expanded

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                spacing: Tokens.space.lg

                PopupHeader {
                    Layout.fillWidth: true
                    palette: pal
                    title: me.displayName
                    subtitle: me.loginName + "@" + me.host + "  ·  " + root.upText(root.uptime)
                    leading: Rectangle {   // avatar: the initial on a primary -> tertiary gradient
                        implicitWidth: 52; implicitHeight: 52; radius: 26
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: pal.primary }
                            GradientStop { position: 1; color: pal.tertiary }
                        }
                        border.width: 1
                        border.color: C.alpha("#ffffff", Tokens.alpha.outlineStrong)
                        Text {
                            anchors.centerIn: parent
                            text: me.initial
                            color: pal.onPrimary
                            font.family: Tokens.font.display
                            font.weight: Font.Black
                            font.pixelSize: Tokens.size.display
                        }
                    }
                }

                Row {
                    id: tiles
                    spacing: Tokens.space.sm
                    Repeater {
                        id: tileRepeater
                        model: root.actions
                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property color tint: pal.col(modelData.color)
                            readonly property bool isArmed: root.armed === modelData.id
                            readonly property bool hot: m.containsMouse || activeFocus || isArmed
                            width: 92; height: 104
                            radius: Tokens.radius.md
                            color: isArmed ? tint : C.alpha(tint, m.pressed ? 0.30 : hot ? 0.22 : 0.10)
                            border.width: 1
                            border.color: C.alpha(tint, hot ? 0.65 : 0.22)
                            scale: m.pressed ? 0.96 : hot ? 1.03 : 1
                            Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            Behavior on border.color { ColorAnimation { duration: Tokens.fast } }

                            // keyboard: Tab in, arrows along the row, Enter/Space like a click
                            activeFocusOnTab: true
                            Keys.onReturnPressed: root.trigger(tile.modelData)
                            Keys.onEnterPressed: root.trigger(tile.modelData)
                            Keys.onSpacePressed: root.trigger(tile.modelData)
                            Keys.onLeftPressed: if (tile.index > 0) tileRepeater.itemAt(tile.index - 1).forceActiveFocus(Qt.TabFocusReason)
                            Keys.onRightPressed: if (tile.index < root.actions.length - 1) tileRepeater.itemAt(tile.index + 1).forceActiveFocus(Qt.TabFocusReason)

                            Column {
                                anchors.centerIn: parent
                                spacing: Tokens.space.sm
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.icon
                                    color: tile.isArmed ? pal.col("background") : tile.tint
                                    font.family: Tokens.font.icons
                                    font.pixelSize: 32
                                    // grow by scale, not font size, so the layout stays put
                                    scale: tile.hot && !tile.isArmed ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.isArmed ? "Again?" : tile.modelData.label
                                    color: tile.isArmed ? pal.col("background") : pal.fg
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Tokens.size.label
                                }
                            }
                            // countdown while armed
                            Rectangle {
                                anchors { left: parent.left; bottom: parent.bottom; leftMargin: Tokens.space.lg; bottomMargin: Tokens.space.sm + 2 }
                                height: 3; radius: 1.5
                                color: pal.col("background")
                                opacity: 0.6
                                width: 0
                                visible: tile.isArmed
                                NumberAnimation on width {
                                    running: tile.isArmed
                                    from: tile.width - 2 * Tokens.space.lg; to: 0; duration: 4000
                                }
                            }
                            FocusRing { radius: tile.radius }
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
}
