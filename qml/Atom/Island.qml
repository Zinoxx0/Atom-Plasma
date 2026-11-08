import QtQuick
import QtQuick.Window

// The clickable part of a bar widget whose panel is drawn by the shell. Fill the compact representation
// with it: a click opens (or closes) panel `kind` on this screen, grown out of this island; while another
// panel is open on the screen, pointing at this one moves the sheet here. It also keeps the switchboard's
// map of islands current, so the shell can grow things out of it unasked (notifications from the status
// island).
//
//   Island { anchors.fill: parent; kind: "calendar" }       island.open: its panel is showing
MouseArea {
    id: isl
    property string kind: ""
    property var args: ({})
    // how far the island's glass reaches past this item (Panel Colorizer's island padding)
    property real reach: 0
    readonly property string screenName: Window.window ? Screen.name : ""
    readonly property bool open: Shell.kind === kind && Shell.screen === screenName

    hoverEnabled: true
    function globalRect() {
        const p = mapToGlobal(-reach, -reach)
        return { x: p.x, y: p.y, width: width + 2 * reach, height: height + 2 * reach }
    }
    onClicked: Shell.toggle(kind, screenName, globalRect(), args)
    onContainsMouseChanged: if (containsMouse) { place(); Shell.hover(kind, screenName, globalRect(), args) }

    function place() { if (kind && screenName && width > 0) Shell.place(kind, screenName, globalRect()) }
    onWidthChanged: Qt.callLater(place)
    onHeightChanged: Qt.callLater(place)
    onScreenNameChanged: Qt.callLater(place)
    Component.onCompleted: Qt.callLater(place)
    Component.onDestruction: if (kind && screenName) Shell.forget(kind, screenName)
}
