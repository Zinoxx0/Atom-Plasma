import QtQuick
import Atom

// A bar widget whose popup is its own content drawn on the shell's sheet (Atom panels/Portal.qml, made there
// in the widget's context), grown out of its island: the island's place, opening / toggling / hovering /
// closing the panel, and the portal's registration. One for every such widget (sysstats, claudeusage).
//
//   PortalHost { id: portal; widget: root; kind: "stats"; screenName: root.myScreenName; popup: root.popup }
//   then portal.open, portal.toggle(), portal.rect(); onPlaced: once the bar's layout has settled
QtObject {
    id: ph
    required property Item widget           // its PlasmoidItem (the island is its compact representation)
    required property string kind           // the Atom Shell panel kind
    property string screenName: ""
    property Component popup: null

    readonly property bool open: Shell.kind === kind && Shell.screen === screenName
    function rect() {                       // the island, global logical px
        const it = widget.compactRepresentationItem
        return it ? Shell.rectOf(it, 0, 0, it.width, it.height) : null
    }
    function toggle() { Shell.toggle(kind, screenName, rect()) }
    function show() { Shell.open(kind, screenName, rect()) }
    function close() { Shell.close(kind) }
    function hover() { Shell.hover(kind, screenName, rect()) }

    onScreenNameChanged: Shell.portal(screenName, kind, popup)
    Component.onCompleted: Shell.portal(screenName, kind, popup)
    // where its island is (for things that grow out of it unasked), once the bar's layout has settled
    signal placed()
    property Timer settle: Timer {
        interval: 1500
        running: ph.screenName !== ""
        onTriggered: { const r = ph.rect(); if (r) Shell.place(ph.kind, ph.screenName, r); ph.placed() }
    }
}
