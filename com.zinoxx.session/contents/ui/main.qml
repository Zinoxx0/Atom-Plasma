import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// wlogout-style session menu. Log out / restart / shut down open the rice logout screen
// (org.kde.LogoutPrompt), the one confirmation every launcher uses, so a stray click can't
// end the session.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    readonly property real uiScale: pal.uiScale
    property real uptime: 0

    readonly property var actions: [
        // tone: the colour a tile lights up in (calm ones the screen's accent, the ones that end the session warm)
        { id: "lock",     icon: "lock",               label: "Lock",      tone: "primary",   cmd: "loginctl lock-session" },
        { id: "sleep",    icon: "bedtime",            label: "Sleep",     tone: "tertiary",  cmd: "systemctl suspend" },
        { id: "logout",   icon: "logout",             label: "Log out",   tone: "secondary", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptLogout" },
        { id: "reboot",   icon: "restart_alt",        label: "Restart",   tone: "warn",      cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptReboot" },
        { id: "shutdown", icon: "power_settings_new", label: "Shut down", tone: "bad",       cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptShutDown" },
    ]

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) root.uptime = parseFloat(data["stdout"] ?? "0") || 0;
            disconnectSource(source);
        }
    }
    function refresh() { sh.connectSource('cut -d" " -f1 /proc/uptime #up') }
    Component.onCompleted: refresh()
    onExpandedChanged: if (root.expanded) refresh()

    function trigger(a) {
        root.expanded = false;
        sh.connectSource(a.cmd + " #run " + Date.now());
    }

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
            color: compact.containsMouse || root.expanded ? pal.bad : pal.fg
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
            ricePalette: pal

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                spacing: Tokens.space.lg

                // you, on a strip of this screen's wallpaper
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 84
                    implicitWidth: tiles.implicitWidth
                    Kirigami.ShadowedImage {
                        id: strip
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: C.alpha(pal.fg, 0.06)
                        source: pal.wallpaper ? "file://" + pal.wallpaper : ""
                        sourceSize.width: 1000
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.base } }
                    }
                    Rectangle {     // a dark wash, deepest on the left where the text sits
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: C.alpha(pal.surfaceLowest, 0.82) }
                            GradientStop { position: 0.65; color: C.alpha(pal.surfaceLowest, 0.45) }
                            GradientStop { position: 1; color: C.alpha(pal.surfaceLowest, 0.18) }
                        }
                        border.width: 1
                        border.color: C.alpha(pal.edge, Tokens.alpha.outline)
                    }
                    PopupHeader {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.md }
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
                            border.width: 1.5
                            border.color: C.alpha(pal.edge, Tokens.alpha.outlineStrong)
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
                            readonly property color tint: pal[modelData.tone]
                            readonly property bool hot: m.containsMouse || activeFocus
                            width: 92; height: 104
                            radius: Tokens.radius.md
                            // calm until you point at one: then it takes its colour
                            color: hot ? C.alpha(tint, m.pressed ? 0.26 : 0.16) : C.alpha(pal.fg, 0.04)
                            border.width: 1
                            border.color: hot ? C.alpha(tint, 0.7) : C.alpha(pal.edge, Tokens.alpha.outline)
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
                                    color: tile.hot ? tile.tint : pal.fgDim
                                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                    font.family: Tokens.font.icons
                                    font.pixelSize: 32
                                    layer.enabled: tile.hot
                                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tile.tint; shadowBlur: 0.7; shadowOpacity: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                                    // grow by scale, not font size, so the layout stays put
                                    scale: tile.hot ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.label
                                    color: pal.fg
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Tokens.size.label
                                }
                            }
                            FocusRing { ink: pal.edge; radius: tile.radius }
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
