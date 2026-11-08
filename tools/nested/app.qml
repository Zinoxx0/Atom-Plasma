import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 600; height: 300; title: "user app"; color: "#203040"
    onActiveChanged: console.warn("ATOM-TEST app active", active)
    TextInput { anchors.fill: parent; anchors.margins: 20; focus: true; color: "white"; font.pixelSize: 30
        onTextChanged: console.warn("ATOM-TEST app typed", JSON.stringify(text)) }
}
