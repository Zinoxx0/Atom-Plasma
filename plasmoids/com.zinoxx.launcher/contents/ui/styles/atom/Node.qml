import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import Rice

// One item on a ring (Orbit), by what it carries: art (a round picture: a game, a theme, a backdrop's preview), a glyph
// (a node: a category, an action, a section), sw / swc (a colour swatch: one colour, or colours round a disc), dot (a
// wallpaper on the colour wheel: its accent), mark (a gauge's value), else an icon. A label under it if it has one; a
// ring round it when it's the one in use (`now`).
Item {
    id: node
    required property var orbit             // the Orbit (not `ring`: a binding `ring: ring` would bind to itself)
    required property int index
    readonly property var it: orbit.items[index] || null
    readonly property real fade: PathView.fade === undefined ? 1 : PathView.fade
    readonly property bool focused: orbit.active && orbit.focusIndex === index
    readonly property string kind: !it ? "" : it.art ? "art" : it.glyph ? "glyph" : (it.sw || it.swc) ? "swatch" : it.dot ? "dot" : it.mark ? "mark" : "icon"
    readonly property var roles: it ? it.roles : null      // (the launcher's menu reads the item's roles off it)
    readonly property var pal: orbit.view.rice
    width: orbit.d(it && it.big ? it.big : orbit.size)
    height: width
    z: focused ? 2 : 1
    opacity: node.fade * orbit.reveal
    visible: opacity > 0.01

    Item {
        anchors.fill: parent
        scale: node.focused && node.kind !== "mark" ? 1.16 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Kirigami.ShadowedImage {
            visible: node.kind === "art"
            anchors.fill: parent
            radius: width / 2
            source: visible ? node.it.art : ""
            asynchronous: true
            sourceSize.width: 256
            fillMode: Image.PreserveAspectCrop
            color: "transparent"
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: C.alpha(node.pal.fg, 0.42)
            shadow.size: node.orbit.d(26); shadow.yOffset: node.orbit.d(10); shadow.color: Qt.rgba(0, 0, 0, 0.4)
        }
        Kirigami.Icon {
            visible: node.kind === "icon"
            anchors.fill: parent
            source: visible ? node.it.icon : ""
        }
        Rectangle {         // a node: a glyph on a disc of glass
            visible: node.kind === "glyph"
            anchors.fill: parent; radius: width / 2
            color: C.alpha(node.pal.surfaceLowest, 0.55)
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: C.alpha(node.pal.fg, node.focused ? 0.6 : 0.26)
            Text { anchors.centerIn: parent; text: node.kind === "glyph" ? node.it.glyph : ""; color: node.pal.fg
                   font.family: Tokens.font.icons; font.pixelSize: parent.width * 0.46 }
        }
        Rectangle {         // a swatch: one colour
            visible: node.kind === "swatch" && !node.it.swc
            anchors.fill: parent; radius: width / 2
            color: node.kind === "swatch" && node.it.sw ? node.it.sw : "transparent"
            border.width: Math.max(1.5, node.orbit.d(1.5)); border.color: Qt.rgba(1, 1, 1, 0.22)
        }
        Shape {             // ... or colours round a disc
            visible: node.kind === "swatch" && !!node.it.swc
            anchors.fill: parent
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
        Rectangle {         // a wallpaper on the wheel: its accent, glowing a little
            visible: node.kind === "dot"
            anchors.fill: parent; radius: width / 2
            color: node.kind === "dot" ? node.it.dot : "transparent"
            border.width: Math.max(1, node.orbit.d(1.2)); border.color: C.alpha(node.pal.fg, 0.3)
            Rectangle { anchors.centerIn: parent; width: parent.width * 2; height: width; radius: width / 2; z: -1
                        color: C.alpha(parent.color, 0.22) }
        }
        Rectangle {         // a gauge's value: a small mark, bigger on the quarters
            visible: node.kind === "mark"
            anchors.centerIn: parent
            width: node.orbit.d(node.it && node.it.major ? 6 : 4); height: width; radius: width / 2
            color: C.alpha(node.pal.fg, node.it && node.it.major ? 0.75 : 0.45)
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
        anchors.margins: -node.orbit.d(node.kind === "dot" || node.kind === "mark" ? 9 : 6)    // (small ones: a bigger target than they look)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) node.orbit.hovered(node.index)
        onClicked: mouse => mouse.button === Qt.RightButton ? node.orbit.rightClicked(node.index, node) : node.orbit.clicked(node.index)
    }
}
