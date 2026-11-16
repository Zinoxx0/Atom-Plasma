import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import Rice

// One ring of the atom: its items on a circle round the core (a PathView: the slot at 9 o'clock holds the current item,
// the next one below it), a hairline lit from the lens' side, and on the active ring an arc of light at the lens. A long
// ring shows `window` items at a time: the rest wait behind and come round through a gap on the far side (they fade
// there). The pointer picks an item where it is (`picked`; the ring doesn't turn under it).
Item {
    id: ring
    required property var view              // the AtomView
    required property int index             // 0 = the innermost
    property var items: []                  // [{ name, icon, art, ... }]
    property real radius: 300               // design px (view.d)
    property real size: 66                  // an item's diameter (design px); an item's own `big` wins
    property int window: 16
    property string name: ""
    readonly property bool active: view.at === index
    readonly property bool lengthy: items.length > window
    property real reveal: 1                 // the opening's spiral: 0 in the core, 1 out on the ring
    readonly property real r: view.d(radius) * view.k * reveal
    readonly property real spin: -150 * (1 - reveal)
    property alias current: pv.currentIndex
    property int picked: -1
    readonly property int focusIndex: picked >= 0 ? picked : pv.currentIndex
    readonly property var focusItem: items[focusIndex] || null
    readonly property Item focusDelegate: (pv.count, pv.itemAtIndex(focusIndex))
    function d(px) { return view.d(px) * view.k }
    signal hovered(int i)
    signal clicked(int i)
    signal rightClicked(int i, Item tile)
    anchors.fill: parent

    // the hairline: brightest on the lens' side, fading to the far side
    Shape {
        anchors.fill: parent
        visible: ring.r > 1
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: ring.view.cx; centerY: ring.view.cy
                angle: -ring.view.lensAngle            // (its angle runs counter-clockwise, the screen's clockwise)
                GradientStop { position: 0; color: C.alpha(ring.view.rice.fg, ring.active ? 0.52 : 0.30) }
                GradientStop { position: 0.32; color: C.alpha(ring.view.rice.fg, ring.active ? 0.11 : 0.06) }
                GradientStop { position: 0.68; color: C.alpha(ring.view.rice.fg, ring.active ? 0.11 : 0.06) }
                GradientStop { position: 1; color: C.alpha(ring.view.rice.fg, ring.active ? 0.52 : 0.30) }
            }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r + 0.9; radiusY: ring.r + 0.9; startAngle: 0; sweepAngle: 360 }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r - 0.9; radiusY: ring.r - 0.9; startAngle: 0; sweepAngle: 360 }
        }
    }
    // the active ring's light at the lens
    Shape {
        anchors.fill: parent
        visible: ring.active && ring.r > 1
        opacity: ring.active ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(400) } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: ring.view.cx; centerY: ring.view.cy
                angle: -ring.view.lensAngle
                GradientStop { position: 0; color: ring.view.rice.primary }
                GradientStop { position: 0.22; color: C.alpha(ring.view.rice.primary, 0) }
                GradientStop { position: 0.78; color: C.alpha(ring.view.rice.primary, 0) }
                GradientStop { position: 1; color: ring.view.rice.primary }
            }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r + 1.8; radiusY: ring.r + 1.8; startAngle: 0; sweepAngle: 360 }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r - 1.8; radiusY: ring.r - 1.8; startAngle: 0; sweepAngle: 360 }
        }
    }

    PathView {
        id: pv
        anchors.fill: parent
        model: ring.items.length
        interactive: false                  // the keys, the wheel and the pointer turn it, never a flick
        pathItemCount: ring.lengthy ? ring.window : ring.items.length
        preferredHighlightBegin: 0.5
        preferredHighlightEnd: 0.5
        highlightRangeMode: PathView.StrictlyEnforceRange
        highlightMoveDuration: Tokens.ms(560)
        // from the far side (3 o'clock) round the top to the slot (9 o'clock, halfway) and on below it: the next item is
        // under the slot. A long ring fades its items out over the first and last step: its gap
        readonly property real e: ring.lengthy ? 360 / ring.window : 0.001
        path: Path {
            startX: ring.view.cx + ring.r * Math.cos(ring.spin * Math.PI / 180)
            startY: ring.view.cy + ring.r * Math.sin(ring.spin * Math.PI / 180)
            PathAttribute { name: "fade"; value: ring.lengthy ? 0 : 1 }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r; radiusY: ring.r; startAngle: ring.spin; sweepAngle: -pv.e; moveToStart: false }
            PathAttribute { name: "fade"; value: 1 }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r; radiusY: ring.r; startAngle: ring.spin - pv.e; sweepAngle: -(360 - 2 * pv.e); moveToStart: false }
            PathAttribute { name: "fade"; value: 1 }
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r; radiusY: ring.r; startAngle: ring.spin - 360 + pv.e; sweepAngle: -pv.e; moveToStart: false }
            PathAttribute { name: "fade"; value: ring.lengthy ? 0 : 1 }
        }
        delegate: Item {
            id: dl
            required property int index
            readonly property var it: ring.items[index] || null
            readonly property real fade: PathView.fade === undefined ? 1 : PathView.fade
            readonly property bool focused: ring.active && ring.focusIndex === index
            readonly property bool planet: !!(dl.it && dl.it.art)
            readonly property var roles: dl.it ? dl.it.roles : null      // (the launcher's menu reads the item's roles off it)
            width: ring.d(dl.it && dl.it.big ? dl.it.big : ring.size)
            height: width
            z: focused ? 2 : 1
            opacity: dl.fade * ring.reveal
            visible: opacity > 0.01
            Item {
                anchors.fill: parent
                scale: dl.focused ? 1.16 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Kirigami.ShadowedImage {
                    visible: dl.planet
                    anchors.fill: parent
                    radius: width / 2
                    source: visible ? dl.it.art : ""
                    fillMode: Image.PreserveAspectCrop
                    color: "transparent"
                    border.width: Math.max(1.5, ring.d(1.5)); border.color: C.alpha(ring.view.rice.fg, 0.42)
                    shadow.size: ring.d(26); shadow.yOffset: ring.d(10); shadow.color: Qt.rgba(0, 0, 0, 0.4)
                }
                Kirigami.Icon {
                    visible: !dl.planet
                    anchors.fill: parent
                    source: dl.it ? dl.it.icon : ""
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -ring.d(6)
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) ring.hovered(dl.index)
                onClicked: mouse => mouse.button === Qt.RightButton ? ring.rightClicked(dl.index, dl) : ring.clicked(dl.index)
            }
        }
    }
    function turn(dd) { if (dd > 0) pv.incrementCurrentIndex(); else pv.decrementCurrentIndex() }
    function bring() { if (picked >= 0) { pv.currentIndex = picked; picked = -1 } }      // the pointer's pick to the slot (the short way)
    readonly property bool moving: pv.moving
    // where an item is, in the view (its centre)
    function centreOf(i) { const it = pv.itemAtIndex(i); return it ? Qt.point(it.x + it.width / 2, it.y + it.height / 2) : Qt.point(view.cx - r, view.cy) }
}
