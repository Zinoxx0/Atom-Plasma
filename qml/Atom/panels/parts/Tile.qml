import QtQuick
import "../../../Rice"
import "../../../Rice/Color.js" as C

// A quick toggle of the control center: an icon in a disc, a name and a word about its state; lit in the
// accent while on. With `more`, a chevron on its right opens its page (networks, devices...).
Rectangle {
    id: tile
    required property RicePalette pal
    property real ui: 1
    property string icon: ""
    property string label: ""
    property string sub: ""
    property bool on: false
    property bool more: false
    property bool busy: false
    signal toggled()
    signal opened()
    function u(n) { return Math.round(n * ui) }

    implicitHeight: u(58)
    radius: u(18)
    color: on ? C.alpha(pal.primary, m.pressed ? 0.34 : m.containsMouse ? 0.3 : 0.24)
              : C.alpha(pal.fg, m.pressed ? 0.11 : m.containsMouse ? 0.09 : 0.055)
    border.width: 1
    border.color: on ? C.alpha(pal.primary, 0.55) : C.alpha(pal.edge, Tokens.alpha.outline)
    Behavior on color { ColorAnimation { duration: Tokens.base } }
    Behavior on border.color { ColorAnimation { duration: Tokens.base } }
    scale: m.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

    Rectangle {
        id: disc
        x: tile.u(11)
        anchors.verticalCenter: parent.verticalCenter
        width: tile.u(38); height: width; radius: width / 2
        color: tile.on ? tile.pal.primary : C.alpha(tile.pal.fg, 0.08)
        Behavior on color { ColorAnimation { duration: Tokens.base } }
        Text {
            anchors.centerIn: parent
            text: tile.icon
            color: tile.on ? tile.pal.onPrimary : tile.pal.fg
            opacity: tile.busy ? 0.5 : 1
            font.family: Tokens.font.icons
            font.pixelSize: tile.u(20)
            Behavior on color { ColorAnimation { duration: Tokens.base } }
        }
    }
    Column {
        anchors { left: disc.right; leftMargin: tile.u(10); right: chev.left; rightMargin: tile.u(4); verticalCenter: parent.verticalCenter }
        spacing: tile.u(1)
        Text {
            width: parent.width
            text: tile.label
            elide: Text.ElideRight
            color: tile.pal.fg
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: tile.u(13)
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: tile.sub
            elide: Text.ElideRight
            color: tile.on ? C.mix(tile.pal.fg, tile.pal.primary, 0.35) : tile.pal.muted
            font.family: Tokens.font.ui
            font.pixelSize: tile.u(11)
        }
    }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }
    Item {      // its page (a separate target, so the toggle stays one click)
        id: chev
        visible: tile.more
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: tile.more ? tile.u(30) : 0
        Rectangle {
            anchors.centerIn: parent
            width: tile.u(24); height: width; radius: width / 2
            color: cm.containsMouse ? C.alpha(tile.pal.fg, 0.12) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "chevron_right"
                color: tile.pal.fgDim
                font.family: Tokens.font.icons
                font.pixelSize: tile.u(18)
            }
        }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.opened() }
    }
}
