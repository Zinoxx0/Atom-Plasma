import QtQuick
import Atom
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import Rice

// One item on a ring (Orbit), by what it carries: art (a round picture: a game, a theme, a backdrop's preview), a glyph
// (a node: a category, an action, a section), sw / swc (a colour swatch: one colour, or colours round a disc), dot (a
// wallpaper on the colour wheel: its accent), mark (a gauge's value), else an icon. A label under it if it has one; a
// ring round it when it's the one in use (`now`). Items rest directly on the ring's haze.
// On a docked ring (Home) the ring places it and sizes it (the dock); elsewhere the focus grows a little.
Item {
    id: node
    required property var orbit             // the Orbit (not `ring`: a binding `ring: ring` would bind to itself)
    required property int index
    readonly property var it: orbit.items[index] || null
    readonly property real fade: orbit.docked ? orbit.fadeAt(index) : PathView.fade === undefined ? 1 : PathView.fade
    readonly property bool focused: orbit.active && orbit.focusIndex === index
    readonly property string kind: !it ? "" : it.art ? "art" : it.glyph ? "glyph" : (it.sw || it.swc) ? "swatch" : it.dot ? "dot" : it.mark ? "mark" : "icon"
    readonly property var roles: it ? it.roles : null      // (the launcher's menu reads the item's roles off it)
    readonly property var pal: orbit.view.rice
    readonly property real lookScale: orbit.docked ? orbit.scaleAt(index) : focused && kind !== "mark" ? 1.16 : 1
    // the lens round it when it has the focus: its shown size at rest (a docked focus: the dock's), x 1.16 (+ the view's margin)
    readonly property real lensSize: width * (orbit.docked ? orbit.focusScale(index) : 1) * 1.16
    width: orbit.d(it && it.big ? it.big : orbit.size)
    height: width
    z: focused ? 2 : 1
    opacity: node.fade * orbit.reveal
    visible: opacity > 0.01

    // its look: only the one it needs is made (an item used to make every kind and hide all but one: a ring of 19
    // apps was ~130 items, and every category change remade them)
    Loader {
        id: look
        anchors.fill: parent
        scale: node.lookScale
        Behavior on scale { enabled: !node.orbit.docked; NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        sourceComponent: node.kind === "icon" ? iconLook : node.kind === "art" ? artLook : node.kind === "glyph" ? glyphLook
                       : node.kind === "swatch" ? (node.it.swc ? wheelLook : swatchLook) : node.kind === "dot" ? dotLook
                       : node.kind === "mark" ? markLook : null
    }
    Component { id: iconLook; Kirigami.Icon { source: node.it ? node.it.icon : "" } }
    Component {
        id: artLook
        Kirigami.ShadowedImage {
            radius: width / 2
            source: node.it ? node.it.art : ""
            asynchronous: true
            sourceSize.width: 256
            fillMode: Image.PreserveAspectCrop
            color: "transparent"
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: C.alpha(node.pal.fg, 0.42)
            shadow.size: node.orbit.d(26); shadow.yOffset: node.orbit.d(10); shadow.color: Qt.rgba(0, 0, 0, 0.4)
        }
    }
    Component {             // a node: a glyph on a disc of glass
        id: glyphLook
        Rectangle {
            radius: width / 2
            color: C.alpha(node.pal.surfaceLowest, 0.55)
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: C.alpha(node.pal.fg, node.focused ? 0.6 : 0.26)
            Text { anchors.centerIn: parent; text: node.it ? node.it.glyph || "" : ""; color: node.pal.fg
                   font.family: Tokens.font.icons; font.pixelSize: parent.width * 0.46 }
        }
    }
    Component {             // a swatch: one colour
        id: swatchLook
        Rectangle {
            radius: width / 2
            color: node.it && node.it.sw ? node.it.sw : "transparent"
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: Qt.rgba(1, 1, 1, 0.22)
        }
    }
    Component {             // ... or colours round a disc
        id: wheelLook
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.22); strokeWidth: Math.max(1.5, node.orbit.d(1.5))
                fillGradient: ConicalGradient {
                    centerX: node.width / 2; centerY: node.height / 2; angle: 90
                    GradientStop { position: 0; color: node.it && node.it.swc ? node.it.swc[0] : "red" }
                    GradientStop { position: 0.33; color: node.it && node.it.swc ? node.it.swc[1] : "green" }
                    GradientStop { position: 0.66; color: node.it && node.it.swc ? node.it.swc[2] : "blue" }
                    GradientStop { position: 1; color: node.it && node.it.swc ? node.it.swc[0] : "red" }
                }
                PathAngleArc { centerX: node.width / 2; centerY: node.height / 2; radiusX: node.width / 2 - 1; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Component {             // a wallpaper on the wheel: its accent, glowing a little
        id: dotLook
        Rectangle {
            radius: width / 2
            color: node.it && node.it.dot ? node.it.dot : "transparent"
            border.width: Math.max(1, node.orbit.d(1.2)); border.color: C.alpha(node.pal.fg, 0.3)
            Rectangle { anchors.centerIn: parent; width: parent.width * 2; height: width; radius: width / 2; z: -1
                        color: C.alpha(parent.color, 0.22) }
        }
    }
    Component {             // a gauge's value: a small mark, bigger on the quarters
        id: markLook
        Item {
            Rectangle {
                anchors.centerIn: parent
                width: node.orbit.d(node.it && node.it.major ? 6 : 4); height: width; radius: width / 2
                color: C.alpha(node.pal.fg, node.it && node.it.major ? 0.75 : 0.45)
            }
        }
    }
    Rectangle {             // the one in use
        visible: !!(node.it && node.it.now) && node.kind !== "mark"
        anchors.centerIn: parent
        width: parent.width + node.orbit.d(node.kind === "dot" ? 9 : 12); height: width; radius: width / 2
        color: "transparent"; border.width: Math.max(1.5, node.orbit.d(1.8)); border.color: C.alpha(node.pal.fg, 0.8)
    }
    Text {                  // its name, under it
        visible: !!(node.it && node.it.label)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom; anchors.topMargin: node.orbit.d(node.kind === "mark" ? 4 : 10)
        text: node.it ? node.it.label || "" : ""
        color: node.focused ? node.pal.fg : node.pal.fgDim
        font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: node.orbit.d(node.kind === "mark" ? 13 : 14)
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -node.orbit.d(node.kind === "dot" || node.kind === "mark" ? 9 : 16)   // (a bigger target than it looks: the lab's round 5)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: containsMouse ? node.orbit.hovered(node.index) : node.orbit.unhovered(node.index)
        onPressed: if (Shell.debug) console.warn("ATOM atom node press", node.orbit.index, node.index)
        onClicked: mouse => mouse.button === Qt.RightButton ? node.orbit.rightClicked(node.index, node) : node.orbit.clicked(node.index)
    }
}
