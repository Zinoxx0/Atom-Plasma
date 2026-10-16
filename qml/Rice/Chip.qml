import QtQuick
import org.kde.plasma.core as PlasmaCore
import "Color.js" as C

// A small rounded label: a status ("live", "on track"), a badge ("NEW", solid) or, with
// `interactive`, a tag/filter chip with hover, press, a selected state and keyboard focus.
//
//   Chip { palette: pal; text: "live"; dot: true; tint: pal.green }
//   Chip { palette: pal; text: "modern"; interactive: true; onClicked: mouse => ... }
Item {
    id: chip
    required override property RicePalette palette
    property string text: ""
    property string icon: ""            // Material Symbols glyph before the text
    property bool dot: false            // a status dot before the text
    property bool pulse: false          // the dot breathes (popups only: it's a loop)
    property color tint: palette.fgDim
    property bool solid: false          // badge: filled with the tint, dark text
    property bool interactive: false
    property bool selected: false
    property string tooltip: ""
    property real size: 22
    property bool bold: true
    property color textColor: solid ? palette.surfaceLowest
                            : interactive ? (hot || selected ? palette.fg : palette.fgDim) : tint
    signal clicked(var mouse)

    readonly property bool hovered: mouse.containsMouse
    readonly property bool hot: interactive && (hovered || activeFocus)

    implicitHeight: size
    implicitWidth: row.implicitWidth + 2 * Math.round(size * 0.42)
    activeFocusOnTab: interactive
    Keys.onReturnPressed: clicked({ button: Qt.LeftButton })
    Keys.onEnterPressed: clicked({ button: Qt.LeftButton })
    Keys.onSpacePressed: clicked({ button: Qt.LeftButton })

    Rectangle {
        id: body
        anchors.fill: parent
        radius: height / 2
        color: chip.solid ? chip.tint
             : mouse.pressed ? C.alpha(chip.tint, 0.30)
             : chip.selected ? C.alpha(chip.tint, 0.22)
             : chip.hot ? C.alpha(chip.tint, 0.20) : C.alpha(chip.tint, chip.interactive ? 0.07 : 0.15)
        border.width: chip.interactive ? 1 : 0
        border.color: chip.selected || chip.hot ? C.alpha(chip.tint, 0.7) : C.alpha(chip.tint, 0.18)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(chip.size * 0.22)
        Rectangle {
            id: dotItem
            visible: chip.dot
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(chip.size * 0.28); height: width; radius: width / 2
            color: chip.solid ? chip.textColor : chip.tint
            SequentialAnimation on opacity {
                running: chip.pulse && chip.dot && chip.visible
                loops: Animation.Infinite
                onRunningChanged: if (!running) dotItem.opacity = 1
                NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }
        Text {
            visible: chip.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            color: label.color
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(chip.size * 0.68)
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: chip.textColor
            font.family: Tokens.font.ui
            font.weight: chip.bold ? Font.Bold : Font.Normal
            font.pixelSize: chip.size >= 20 ? Tokens.size.small : Tokens.size.caption
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
    }
    FocusRing { radius: body.radius; ink: chip.palette.edge }
    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: chip.tooltip
        active: chip.tooltip !== ""
        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: chip.interactive
            hoverEnabled: chip.interactive
            cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => chip.clicked(m)
        }
    }
}
