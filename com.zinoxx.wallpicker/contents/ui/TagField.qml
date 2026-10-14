import QtQuick
import QtQuick.Layouts

// Rounded text field for wallhaven tags, in the same style as PillButton.
Rectangle {
    id: field
    property alias text: input.text
    property string placeholder: ""
    property color accent: "#7aa2f7"
    property color fg: "#c0caf5"
    property color muted: "#565f89"
    property bool busy: false
    signal accepted()

    implicitHeight: 34
    radius: height / 2
    color: Qt.alpha(fg, input.activeFocus ? 0.09 : hover.containsMouse ? 0.07 : 0.05)
    border.width: input.activeFocus ? 1.5 : 1
    border.color: input.activeFocus ? accent : Qt.alpha(accent, hover.containsMouse ? 0.45 : 0.2)
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    MouseArea {     // clicks on the padding focus the text too
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: input.forceActiveFocus()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 8
        Text {
            text: "sell"
            color: input.activeFocus ? field.accent : field.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 17
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: field.fg
                selectionColor: field.accent
                selectedTextColor: "#11111b"
                font.family: "Inter"
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                readOnly: field.busy
                onAccepted: field.accepted()
            }
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !input.text && !input.preeditText
                text: field.placeholder
                color: field.muted
                font: input.font
                elide: Text.ElideRight
            }
        }
        Text {          // clear
            visible: input.text.length > 0 && !field.busy
            text: "close"
            color: clear.containsMouse ? field.fg : field.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 16
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
}
