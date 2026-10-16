import QtQuick
import org.kde.plasma.core as PlasmaCore
import "Color.js" as C

// A rounded icon button for popups: a Material Symbols glyph (and optional label), a soft wash on
// hover and press, a focus ring for the keyboard, a Plasma-styled tooltip.
Item {
    id: btn
    required override property RicePalette palette
    property string icon: ""            // Material Symbols name, e.g. "lock"
    property string text: ""
    property string tooltip: ""
    property color accent: palette.primary
    property bool checked: false
    property real size: 32
    signal clicked()

    readonly property bool hovered: mouse.containsMouse
    implicitWidth: text ? row.implicitWidth + 2 * Tokens.space.md : size
    implicitHeight: size
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Math.min(height / 2, Tokens.radius.sm)
        color: btn.checked ? C.alpha(btn.accent, 0.22)
             : mouse.pressed ? C.alpha(btn.palette.fg, Tokens.alpha.press)
             : btn.hovered ? C.alpha(btn.palette.fg, Tokens.alpha.hover) : "transparent"
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.space.xs
        Text {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            color: btn.checked || btn.hovered ? btn.accent : btn.palette.fg
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(btn.size * 0.56)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.palette.fg
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: Tokens.size.label
        }
    }
    FocusRing { radius: face.radius }
    // the tooltip area wraps the mouse area: as a sibling on top it would take the hover for itself
    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: btn.tooltip
        active: btn.tooltip !== ""
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
