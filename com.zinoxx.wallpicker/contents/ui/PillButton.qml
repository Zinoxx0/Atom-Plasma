import QtQuick
import QtQuick.Layouts

// Rounded pill with a Material Symbols icon and optional label.
Rectangle {
    id: btn
    property string icon: ""
    property string label: ""
    property color accent: "#7aa2f7"
    property color fg: "#c0caf5"
    property color accentText: "#1a1b26"
    property bool busy: false
    signal clicked()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + (label ? 26 : 16)
    radius: height / 2
    color: mouse.containsMouse ? btn.accent : Qt.alpha(btn.accent, 0.13)
    border.width: 1
    border.color: Qt.alpha(btn.accent, mouse.containsMouse ? 0 : 0.25)
    scale: mouse.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            text: btn.icon
            visible: text.length > 0
            color: mouse.containsMouse ? btn.accentText : btn.accent
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            RotationAnimation on rotation {
                running: btn.busy
                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                onRunningChanged: if (!running) parent.rotation = 0
            }
        }
        Text {
            text: btn.label
            visible: text.length > 0
            color: mouse.containsMouse ? btn.accentText : btn.fg
            font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 12
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !btn.busy
        onClicked: btn.clicked()
    }
}
