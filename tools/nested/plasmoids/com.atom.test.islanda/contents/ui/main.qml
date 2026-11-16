import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import Atom
PlasmoidItem {
    preferredRepresentation: fullRepresentation
    fullRepresentation: Rectangle {
        Layout.preferredWidth: 90; Layout.minimumWidth: 90; Layout.fillHeight: true
        radius: height / 2; color: isl.open ? "#bb9af7" : "#7aa2f7"
        Component.onCompleted: {
            Shell.debug = true
            // the launcher style under test (look-launcher.sh ATOM_STYLE=...): the nested config's file, never the user's settings
            const x = new XMLHttpRequest()
            x.open("GET", StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/atom-test-style", false)
            try { x.send(); const v = String(x.responseText || "").trim(); if (v) Shell.styleOverride = v } catch (e) { }
        }
        Island { id: isl; anchors.fill: parent; kind: "demo"
            onClicked: console.warn("ATOM-TEST island a clicked", JSON.stringify(globalRect()))
            onPressed: console.warn("ATOM-TEST island a pressed", Date.now() % 100000)
            Timer { interval: 3000; running: true; onTriggered: console.warn("ATOM-TEST island a at", JSON.stringify(isl.globalRect())) } }
    }
}
