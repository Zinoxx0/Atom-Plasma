import QtQuick
import QtQuick.Layouts
import "../../Rice"

// A stand-in panel for testing the sheet (two sizes: "demo" and "demo2"). Not shown to the user.
FocusScope {
    id: demo
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property bool wide: kind === "demo2"
    implicitWidth: wide ? 520 : 340
    implicitHeight: col.implicitHeight
    ColumnLayout {
    id: col
    anchors.fill: parent
    spacing: Tokens.space.md
    Text {
        text: demo.wide ? "Wide demo panel" : "Demo panel"
        color: demo.ricePalette ? demo.ricePalette.fg : "white"
        font.family: Tokens.font.display
        font.pixelSize: Tokens.size.heading
        font.weight: Font.DemiBold
    }
    Repeater {
        model: demo.wide ? 3 : 5
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Tokens.radius.md
            color: Qt.rgba(1, 1, 1, 0.05)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            Text { anchors.centerIn: parent; text: "row " + index; color: "white"; opacity: 0.7 }
        }
    }
    TextInput {
        Layout.fillWidth: true
        color: "white"
        font.pixelSize: 18
        focus: true
        onTextChanged: console.warn("ATOM-TEST demo typed", JSON.stringify(text))
    }
}
}
