import QtQuick
import "Rice"
import "Rice/Color.js" as C

// One big action on the logout screen: a glyph and a label on a tinted glass tile. The action
// the prompt was opened for carries a ring that drains with the countdown.
Item {
    id: tile
    required override property RicePalette palette
    property string icon: ""
    property string text: ""
    property string hint: ""               // a small second line ("with updates")
    property color tint: palette.primary
    property real progress: -1             // countdown left, 1 -> 0; < 0 = no ring
    signal activated()

    readonly property bool hot: mouse.containsMouse || activeFocus
    implicitWidth: 136
    implicitHeight: 156
    activeFocusOnTab: true
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: C.alpha(tile.tint, mouse.pressed ? 0.30 : tile.hot ? 0.22 : 0.10)
        border.width: 1
        border.color: C.alpha(tile.tint, tile.hot ? 0.70 : 0.24)
        scale: mouse.pressed ? 0.97 : tile.hot ? 1.03 : 1
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }

        // a faint sheen along the top, like the bar islands
        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: card.radius - 1
            gradient: Gradient {
                GradientStop { position: 0; color: C.alpha("#ffffff", 0.06) }
                GradientStop { position: 0.45; color: "transparent" }
            }
        }

        Item {
            id: glyphBox
            width: 64; height: 64
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.18)
            // countdown ring: the track, then what's left of the wait
            Ring {
                anchors.fill: parent
                visible: tile.progress >= 0
                instant: true
                showText: false
                thickness: 3
                value: Math.max(0, tile.progress) * 100
                from: tile.tint
                to: tile.tint
                track: C.alpha(tile.tint, 0.18)
            }
            Text {
                anchors.centerIn: parent
                text: tile.icon
                color: tile.tint
                font.family: Tokens.font.icons
                font.pixelSize: 40
                scale: tile.hot ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
            }
        }
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: glyphBox.bottom; topMargin: Tokens.space.md }
            spacing: Tokens.space.xxs
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.text
                color: tile.palette.fg
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: Tokens.size.title
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: tile.hint
                color: tile.palette.fgDim
                font.family: Tokens.font.ui
                font.pixelSize: Tokens.size.small
            }
        }
    }
    FocusRing { radius: card.radius; target: card; shown: tile.activeFocus }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
