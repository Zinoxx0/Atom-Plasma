import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atom
import "../../Rice"
import "../../Rice/Color.js" as C
import "../../Rice/SessionActions.js" as Session

// The session panel (the bar's power island): you, on a strip of this screen's wallpaper, with the uptime;
// then lock, sleep, log out, restart and shut down, which come out one after another when it opens. Log out,
// restart and shut down open the rice logout screen (org.kde.LogoutPrompt), the one confirmation every
// launcher uses, so a stray click can't end the session.
FocusScope {
    id: panel
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette

    readonly property var actions: Session.pick()
    readonly property real tile: Math.round(88 * ui)
    readonly property real gap: Math.round(Tokens.space.sm * ui)
    implicitWidth: actions.length * tile + (actions.length - 1) * gap
    implicitHeight: col.implicitHeight

    Account { id: me }
    property real uptime: 0
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) panel.uptime = parseFloat(data["stdout"] ?? "0") || 0
            disconnectSource(source)
        }
    }
    function upText(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return "up " + (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m"
    }
    function trigger(a) {
        Shell.close()
        sh.connectSource(a.cmd + " #run")      // a fixed set of commands: fixed names (RiceShell)
    }
    // the sheet calls this as the panel comes in
    property int shownAt: 0
    function enter() {
        shownAt++
        sh.connectSource('cut -d" " -f1 /proc/uptime #up')
    }

    ColumnLayout {
        id: col
        width: panel.width
        spacing: Math.round(Tokens.space.lg * panel.ui)

        // you, on a strip of this screen's wallpaper
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.round(80 * panel.ui)
            Kirigami.ShadowedImage {
                anchors.fill: parent
                radius: Tokens.radius.md
                color: C.alpha(panel.pal.fg, 0.06)
                source: panel.pal.wallpaper ? "file://" + panel.pal.wallpaper : ""
                sourceSize.width: 900
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
                    GradientStop { position: 0; color: C.alpha(panel.pal.surfaceLowest, 0.84) }
                    GradientStop { position: 0.65; color: C.alpha(panel.pal.surfaceLowest, 0.45) }
                    GradientStop { position: 1; color: C.alpha(panel.pal.surfaceLowest, 0.15) }
                }
                border.width: 1
                border.color: C.alpha(panel.pal.edge, Tokens.alpha.outline)
            }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Math.round(Tokens.space.md * panel.ui) }
                spacing: Math.round(Tokens.space.md * panel.ui)
                Rectangle {     // the initial on a primary -> tertiary gradient
                    width: Math.round(48 * panel.ui); height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: panel.pal.primary }
                        GradientStop { position: 1; color: panel.pal.tertiary }
                    }
                    border.width: 1.5
                    border.color: C.alpha(panel.pal.edge, Tokens.alpha.outlineStrong)
                    Text {
                        anchors.centerIn: parent
                        text: me.initial
                        color: panel.pal.onPrimary
                        font.family: Tokens.font.display
                        font.weight: Font.Black
                        font.pixelSize: Math.round(Tokens.size.display * panel.ui)
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: me.displayName
                        color: panel.pal.fg
                        font.family: Tokens.font.display
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.round(Tokens.size.heading * panel.ui)
                    }
                    Text {
                        text: me.loginName + "@" + me.host + "  ·  " + panel.upText(panel.uptime)
                        color: panel.pal.fgDim
                        font.family: Tokens.font.ui
                        font.pixelSize: Math.round(Tokens.size.label * panel.ui)
                    }
                }
            }
        }

        // the actions, out one after another, the last (shut down) first: it sits nearest the island
        Row {
            id: row
            spacing: panel.gap
            Repeater {
                id: tiles
                model: panel.actions
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property color tint: panel.pal[modelData.tone]
                    readonly property bool hot: m.containsMouse || activeFocus
                    width: panel.tile
                    height: Math.round(panel.tile * 1.1)

                    opacity: 0
                    scale: 0.7
                    Connections {
                        target: panel
                        function onShownAtChanged() { tileIn.restart() }
                    }
                    SequentialAnimation {
                        id: tileIn
                        PropertyAction { target: tile; property: "opacity"; value: 0 }
                        PropertyAction { target: tile; property: "scale"; value: 0.7 }
                        PauseAnimation { duration: Tokens.ms(150 + (panel.actions.length - 1 - tile.index) * 40) }
                        ParallelAnimation {
                            NumberAnimation { target: tile; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                            NumberAnimation { target: tile; property: "scale"; to: 1; duration: Tokens.morph; easing.type: Tokens.grow }
                        }
                    }

                    Rectangle {
                        id: card
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: tile.hot ? C.alpha(tile.tint, m.pressed ? 0.26 : 0.16) : C.alpha(panel.pal.fg, 0.04)
                        border.width: 1
                        border.color: tile.hot ? C.alpha(tile.tint, 0.7) : C.alpha(panel.pal.edge, Tokens.alpha.outline)
                        scale: m.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: Math.round(Tokens.space.sm * panel.ui)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.icon
                            color: tile.hot ? tile.tint : panel.pal.fgDim
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            font.family: Tokens.font.icons
                            font.pixelSize: Math.round(30 * panel.ui)
                            layer.enabled: tile.hot
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tile.tint; shadowBlur: 0.7; shadowOpacity: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                            scale: tile.hot ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.label
                            color: panel.pal.fg
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: Math.round(Tokens.size.label * panel.ui)
                        }
                    }
                    FocusRing { ink: panel.pal.edge; radius: card.radius; shown: tile.activeFocus }

                    // keyboard: arrows along the row, Enter/Space like a click
                    activeFocusOnTab: true
                    Keys.onReturnPressed: panel.trigger(tile.modelData)
                    Keys.onEnterPressed: panel.trigger(tile.modelData)
                    Keys.onSpacePressed: panel.trigger(tile.modelData)
                    Keys.onLeftPressed: if (tile.index > 0) tiles.itemAt(tile.index - 1).forceActiveFocus(Qt.TabFocusReason)
                    Keys.onRightPressed: if (tile.index < panel.actions.length - 1) tiles.itemAt(tile.index + 1).forceActiveFocus(Qt.TabFocusReason)
                    MouseArea {
                        id: m
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.trigger(tile.modelData)
                    }
                }
            }
        }
    }
}
