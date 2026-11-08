import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import "Rice"
import "Rice/Color.js" as C

// A category of the app library, drawn as a little deck: a frosted card holding its first four apps'
// icons, two thin glass sheets peeking out behind it (they fan out a little when it's pointed at), its name
// under it and how many apps it holds in the corner. Clicking it opens the category as a folder
// (Folder.qml grows out of it). Lives directly in the stage's full-window layer: x/y are window
// coordinates (the frost lines up with the wallpaper by them).
Item {
    id: stack
    required property var launcher
    required property RicePalette rice
    required property var cat                   // { label, icon, model }
    property Item backdrop: null
    property real unit: 1
    readonly property bool hot: m.containsMouse || activeFocus
    readonly property real radius: Math.round(26 * unit)
    signal opened()
    function u(n) { return Math.round(n * unit) }

    // the first four apps (re-read when the category fills)
    readonly property int count: cat && cat.model ? cat.model.count : 0
    readonly property var icons: {
        const out = [], m = cat ? cat.model : null
        for (let i = 0; m && i < Math.min(4, count); i++) out.push(m.data(m.index(i, 0), Qt.DecorationRole))
        return out
    }

    // the deck: two sheets behind the card
    Repeater {
        model: stack.count > 1 ? 2 : 0
        Rectangle {
            required property int index
            readonly property int side: index === 0 ? -1 : 1
            anchors.fill: parent
            radius: stack.radius
            scale: 0.92 - index * 0.03
            transformOrigin: Item.Bottom
            rotation: side * (stack.hot ? 7 + index * 2 : 3.5 + index * 1.5)
            transform: Translate {
                y: -stack.u(stack.hot ? 12 : 7) - index * stack.u(3)
                Behavior on y { NumberAnimation { duration: Tokens.ms(420); easing.type: Tokens.grow } }
            }
            color: Qt.rgba(1, 1, 1, 0.05 + index * 0.015)
            border.width: 1
            border.color: C.alpha(index === 0 ? stack.rice.primary : stack.rice.tertiary, stack.hot ? 0.45 : 0.22)
            Behavior on rotation { NumberAnimation { duration: Tokens.ms(420); easing.type: Tokens.grow } }
            Behavior on border.color { ColorAnimation { duration: Tokens.base } }
        }
    }

    Frost {
        id: card
        anchors.fill: parent
        backdrop: stack.backdrop
        originX: stack.x
        originY: stack.y
        radius: stack.radius
        tintAlpha: stack.hot ? 0.42 : 0.52
        rimAlpha: stack.hot ? 0.6 : 0.3
        rimA: stack.rice.primary
        rimB: stack.rice.tertiary
        Behavior on tintAlpha { NumberAnimation { duration: Tokens.fast } }
        Behavior on rimAlpha { NumberAnimation { duration: Tokens.fast } }
        scale: m.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: stack.u(12)
            scale: stack.hot ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
            Repeater {
                model: stack.icons
                Kirigami.Icon {
                    required property var modelData
                    width: stack.u(38); height: width
                    source: modelData
                }
            }
        }
        // how many apps, a small pip in the corner
        Rectangle {
            visible: stack.count > 4
            anchors { right: parent.right; top: parent.top; margins: stack.u(9) }
            height: stack.u(20)
            width: Math.max(height, countText.implicitWidth + stack.u(12))
            radius: height / 2
            color: C.alpha(stack.rice.fg, 0.12)
            Text {
                id: countText
                anchors.centerIn: parent
                text: stack.count
                color: stack.rice.fgDim
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: stack.u(11)
            }
        }
    }
    // the name, under the card, on the wallpaper (a soft shadow keeps it readable)
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + stack.u(10)
        width: parent.width + stack.u(24)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: stack.cat ? stack.cat.label : ""
        color: stack.rice.fg
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.35)
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: stack.u(13)
    }
    FocusRing { ink: stack.rice.edge; radius: stack.radius; shown: stack.activeFocus; gap: 2 }
    activeFocusOnTab: true
    Keys.onReturnPressed: stack.opened()
    Keys.onEnterPressed: stack.opened()
    Keys.onSpacePressed: stack.opened()
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: stack.opened()
    }
}
