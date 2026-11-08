import QtQuick
import "../../../Rice"
import "../../../Rice/Color.js" as C

// A level of the control center (volume, a screen's brightness, the lamp): an icon that can be a button
// (mute), a name, and a smooth slider; with `more`, a chevron to its page (outputs). `value` is 0..1;
// dragging reports `moved(v)` continuously.
Item {
    id: lvl
    required property RicePalette pal
    property real ui: 1
    property string icon: ""
    property string label: ""
    property real value: 0
    property bool dim: false            // muted: the fill goes grey
    property bool more: false
    property color tint: pal.primary
    signal moved(real v)
    signal iconClicked()
    signal opened()
    function u(n) { return Math.round(n * ui) }
    implicitHeight: u(44)

    Rectangle {     // the icon (a button)
        id: btn
        anchors.verticalCenter: parent.verticalCenter
        width: lvl.u(36); height: width; radius: width / 2
        color: im.containsMouse ? C.alpha(lvl.pal.fg, 0.12) : C.alpha(lvl.pal.fg, 0.06)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Text {
            anchors.centerIn: parent
            text: lvl.icon
            color: lvl.dim ? lvl.pal.muted : lvl.pal.fg
            font.family: Tokens.font.icons
            font.pixelSize: lvl.u(19)
        }
        MouseArea { id: im; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lvl.iconClicked() }
    }
    Text {
        id: name
        anchors { left: btn.right; leftMargin: lvl.u(12); top: parent.top; topMargin: lvl.u(2) }
        width: track.width - pct.width - lvl.u(8)
        text: lvl.label
        elide: Text.ElideRight
        color: lvl.pal.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.Medium
        font.pixelSize: lvl.u(11)
    }
    Text {
        id: pct
        anchors { right: track.right; top: parent.top; topMargin: lvl.u(2) }
        text: Math.round(lvl.value * 100) + "%"
        color: lvl.pal.muted
        font.family: Tokens.font.ui
        font.pixelSize: lvl.u(11)
    }
    Rectangle {
        id: track
        anchors { left: btn.right; leftMargin: lvl.u(12); right: chev.left; rightMargin: lvl.more ? lvl.u(6) : 0; bottom: parent.bottom; bottomMargin: lvl.u(8) }
        height: lvl.u(8)
        radius: height / 2
        color: C.alpha(lvl.pal.fg, 0.1)
        Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, lvl.value)))
            height: parent.height
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: lvl.dim ? C.alpha(lvl.pal.fg, 0.25) : lvl.pal.primary }
                GradientStop { position: 1; color: lvl.dim ? C.alpha(lvl.pal.fg, 0.35) : lvl.pal.tertiary }
            }
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Tokens.fast } }
        }
        Rectangle {     // the knob
            x: Math.max(0, Math.min(parent.width - width, parent.width * lvl.value - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: lvl.u(drag.pressed || drag.containsMouse ? 18 : 14); height: width; radius: width / 2
            color: "white"
            border.width: 1
            border.color: C.alpha(lvl.pal.edge, 0.3)
            Behavior on width { NumberAnimation { duration: Tokens.fast } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -lvl.u(10)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function at(mx) { return Math.max(0, Math.min(1, (mx - lvl.u(10)) / track.width)) }
            onPressed: mouse => lvl.moved(at(mouse.x))
            onPositionChanged: mouse => { if (pressed) lvl.moved(at(mouse.x)) }
            onWheel: wheel => lvl.moved(Math.max(0, Math.min(1, lvl.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }
    Item {
        id: chev
        anchors { right: parent.right; verticalCenter: track.verticalCenter }
        width: lvl.more ? lvl.u(26) : 0
        visible: lvl.more
        Text {
            anchors.centerIn: parent
            text: "chevron_right"
            color: cm.containsMouse ? lvl.pal.fg : lvl.pal.fgDim
            font.family: Tokens.font.icons
            font.pixelSize: lvl.u(18)
        }
        MouseArea { id: cm; anchors.fill: parent; anchors.margins: -lvl.u(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lvl.opened() }
    }
}
