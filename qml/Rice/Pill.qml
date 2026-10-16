import QtQuick
import org.kde.plasma.core as PlasmaCore
import "Color.js" as C

// A pill button in the popups: a Material Symbols glyph and/or a label on a faint accent tint
// that fills in on hover, dips on press, and takes keyboard focus (Tab, then Enter or Space).
// Icon only, it's round. `busy` swaps the icon for the stepped Busy dots and disables it.
//
//   Pill { palette: pal; icon: "shuffle"; text: "Shuffle"; onClicked: ... }
Item {
    id: pill
    required override property RicePalette palette
    property string icon: ""
    property string text: ""
    property string tooltip: ""
    property color accent: palette.primary
    property color onAccent: palette.onPrimary
    property bool busy: false
    property bool iconLast: false       // the glyph after the label (external links: open_in_new)
    property real size: 30
    signal clicked()

    readonly property bool hovered: mouse.containsMouse
    readonly property bool hot: (hovered || activeFocus) && !busy

    implicitHeight: size
    implicitWidth: text ? row.implicitWidth + 2 * Tokens.space.md : size
    activeFocusOnTab: true
    Keys.onReturnPressed: if (!busy) clicked()
    Keys.onEnterPressed: if (!busy) clicked()
    Keys.onSpacePressed: if (!busy) clicked()

    Rectangle {
        id: body
        anchors.fill: parent
        radius: height / 2
        color: mouse.pressed ? Qt.darker(pill.accent, 1.12)
             : pill.hot ? pill.accent : C.alpha(pill.accent, 0.13)
        border.width: 1
        border.color: C.alpha(pill.accent, pill.hot || mouse.pressed ? 0 : 0.26)
        scale: mouse.pressed ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Tokens.space.xs + 2
            layoutDirection: pill.iconLast ? Qt.RightToLeft : Qt.LeftToRight
            Item {
                visible: pill.icon !== "" || pill.busy
                width: glyph.implicitWidth
                height: glyph.implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: glyph
                    visible: !pill.busy
                    text: pill.icon || "progress_activity"
                    color: pill.hot || mouse.pressed ? pill.onAccent : pill.accent
                    font.family: Tokens.font.icons
                    font.pixelSize: Math.round(pill.size * 0.58)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                }
                Busy {
                    anchors.centerIn: parent
                    width: Math.round(pill.size * 0.46); height: width
                    running: pill.busy
                    visible: pill.busy
                    color: pill.accent
                }
            }
            Text {
                visible: pill.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.hot || mouse.pressed ? pill.onAccent : pill.palette.fg
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: Tokens.size.label
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
        }
    }
    FocusRing { radius: body.radius }
    // the tooltip area wraps the mouse area: hover reaches both (as a sibling on top it would
    // take the hover for itself)
    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: pill.tooltip
        active: pill.tooltip !== ""
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !pill.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
