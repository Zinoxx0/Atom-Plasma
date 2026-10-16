import QtQuick
import "Color.js" as C

// Keyboard focus ring, the same as the Plasma Style's: a neutral 1.5 px hairline 2 px outside
// its item, faded in while the item has active focus. MouseAreas don't take focus on click, so
// in practice it shows for Tab and the arrow keys only.
//
//   Rectangle { id: card; radius: 10; activeFocusOnTab: true; FocusRing { radius: card.radius } }
Item {
    id: ring
    property Item target: parent
    property real radius: 0          // the item's own corner radius; the ring stays concentric
    property real gap: 2
    property bool shown: target !== null && target.activeFocus
    property color ink: "#ffffff"   // pass the palette's edge (black on a light screen)

    anchors.fill: target
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

    Rectangle {
        readonly property real reach: ring.gap + border.width
        anchors.fill: parent
        anchors.margins: -reach
        radius: ring.radius > 0 ? ring.radius + reach : 0
        color: "transparent"
        border.width: 1.5
        border.color: C.alpha(ring.ink, 0.55)
    }
}
