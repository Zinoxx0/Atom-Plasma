import QtQuick
import "../../../Rice"
import "../../../Rice/Color.js" as C

// A choice in a row of them (a preset, a screen, a speed): a pill with an optional glyph, lit in the accent
// while selected.
Rectangle {
    id: chip
    required property RicePalette pal
    property real ui: 1
    property string text: ""
    property string glyph: ""
    property bool selected: false
    property bool small: false
    signal clicked()
    function u(n) { return Math.round(n * ui) }

    implicitHeight: u(small ? 26 : 30)
    implicitWidth: row.implicitWidth + u(small ? 18 : 24)
    radius: height / 2
    color: selected ? C.alpha(pal.primary, m.pressed ? 0.34 : m.containsMouse ? 0.3 : 0.24)
                    : C.alpha(pal.fg, m.pressed ? 0.12 : m.containsMouse ? 0.09 : 0.05)
    border.width: 1
    border.color: selected ? C.alpha(pal.primary, 0.55) : C.alpha(pal.edge, Tokens.alpha.outline)
    Behavior on color { ColorAnimation { duration: Tokens.fast } }
    scale: m.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: chip.u(5)
        Text {
            visible: chip.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            color: chip.selected ? chip.pal.primary : chip.pal.fgDim
            font.family: Tokens.font.icons
            font.pixelSize: chip.u(chip.small ? 14 : 16)
        }
        Text {
            visible: chip.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: chip.selected ? chip.pal.fg : chip.pal.fgDim
            font.family: Tokens.font.ui
            font.weight: chip.selected ? Font.DemiBold : Font.Medium
            font.pixelSize: chip.u(chip.small ? 11 : 12)
        }
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
