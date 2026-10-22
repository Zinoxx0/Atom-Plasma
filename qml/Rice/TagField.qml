import QtQuick
import QtQuick.Layouts

import "Color.js" as C

// Rounded text field (wallhaven tags, preset names), in the same style as the Rice pills.
Rectangle {
    id: field
    required override property RicePalette palette
    property alias text: input.text
    property alias maximumLength: input.maximumLength
    property string glyph: "sell"           // Material Symbols icon at the start
    property string placeholder: ""
    property color accent: palette.tertiary
    property color onAccent: palette.col("on_tertiary")    // text on the accent (selection)
    property bool busy: false
    signal accepted()
    signal escaped()
    function focusText() { input.forceActiveFocus() }

    readonly property bool hovered: hover.containsMouse || clear.containsMouse
    implicitHeight: 34
    radius: height / 2
    color: C.alpha(palette.fg, input.activeFocus ? 0.09 : hovered ? 0.07 : 0.05)
    border.width: 1
    border.color: input.activeFocus ? accent : C.alpha(accent, hovered ? 0.45 : 0.2)
    Behavior on color { ColorAnimation { duration: Tokens.fast } }
    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }

    MouseArea {     // clicks on the padding focus the text too
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: input.forceActiveFocus()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.space.md
        anchors.rightMargin: Tokens.space.sm + 2
        spacing: Tokens.space.sm
        Text {
            text: field.glyph
            color: input.activeFocus ? field.accent : field.palette.muted
            font.family: Tokens.font.icons
            font.pixelSize: 17
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: field.palette.fg
                selectionColor: field.accent
                selectedTextColor: field.onAccent
                font.family: Tokens.font.ui
                font.pixelSize: Tokens.size.body
                clip: true
                selectByMouse: true
                readOnly: field.busy
                activeFocusOnTab: true
                onAccepted: field.accepted()
                Keys.onEscapePressed: event => { field.escaped(); event.accepted = true }
            }
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !input.text && !input.preeditText
                text: field.placeholder
                color: field.palette.muted
                font: input.font
                elide: Text.ElideRight
            }
        }
        Text {          // clear
            visible: input.text.length > 0 && !field.busy
            text: "close"
            color: clear.pressed ? field.accent : clear.containsMouse ? field.palette.fg : field.palette.muted
            font.family: Tokens.font.icons
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            MouseArea {
                id: clear
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { input.clear(); input.forceActiveFocus() }
            }
        }
    }
    // focus (clicked or tabbed into) is the accent edge above, like the Plasma Style's text fields
}
