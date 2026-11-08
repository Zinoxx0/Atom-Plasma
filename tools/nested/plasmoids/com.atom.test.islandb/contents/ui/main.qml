import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import Atom
PlasmoidItem {
    preferredRepresentation: fullRepresentation
    fullRepresentation: Rectangle {
        Layout.preferredWidth: 90; Layout.minimumWidth: 90; Layout.fillHeight: true
        radius: height / 2; color: isl.open ? "#bb9af7" : "#7aa2f7"
        Island { id: isl; anchors.fill: parent; kind: "demo2"
            onClicked: console.warn("ATOM-TEST island b clicked", JSON.stringify(globalRect()))
            Timer { interval: 3000; running: true; onTriggered: console.warn("ATOM-TEST island b at", JSON.stringify(isl.globalRect())) } }
    }
}
