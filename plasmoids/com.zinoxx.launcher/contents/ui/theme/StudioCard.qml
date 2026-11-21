import QtQuick
import Atom
import Rice

// A choice on the Theme page shown as a picture of what it does (a mood, a backdrop, an island style, a launcher, a
// saved look), its name under it, a tick on the one in use. The lens goes round the picture. Its children are the
// picture (they fill `pic`; they draw their own rounded corners).
Focusable {
    id: card
    property string name: ""
    property string note: ""
    property bool current: false
    property real picW: studio.d(236)
    property real picH: studio.d(132)
    default property alias picture: pic.data
    readonly property var lk: studio.look
    width: picW
    height: picH + studio.d(12) + label.height
    lensItem: pic
    lensRadius: studio.d(14)
    Item {
        id: pic
        width: card.picW
        height: card.picH
        scale: card.hovered && !card.focused ? 1.015 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.ms(220) } }
    }
    Rectangle {         // the one in use
        visible: card.current
        anchors.right: pic.right; anchors.top: pic.top; anchors.margins: card.studio.d(8)
        width: card.studio.d(28); height: width; radius: width / 2
        color: card.lk.primary
        Text { anchors.centerIn: parent; text: "check"; color: card.lk.surfaceLowest; font.family: Tokens.font.icons; font.weight: Font.Bold; font.pixelSize: card.studio.d(18) }
    }
    Row {
        id: label
        y: card.picH + card.studio.d(12)
        spacing: card.studio.d(8)
        Text { text: card.name; color: card.lk.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: card.studio.d(16.5) }
        Text { visible: card.note !== ""; anchors.baseline: parent.children[0].baseline; text: card.note; color: card.lk.fgDim; font.family: Tokens.font.ui; font.pixelSize: card.studio.d(14) }
    }
}
