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
    // placed: the items sit at their own angles (it.ang: degrees clockwise from 3 o'clock; the colour wheel, gauges) and
    // the focus moves between them, nothing turns. gauge: a placed ring of values drawn as an arc filled to the focus
    property bool placed: false
    property bool gauge: false
    property int placedCur: 0
    property alias turned: pv.currentIndex
    property int current: 0                 // the focus at rest (the slot, or a placed ring's)
    onCurrentChanged: { if (placed) placedCur = current; else if (pv.currentIndex !== current) pv.currentIndex = current }
    Connections { target: pv; function onCurrentIndexChanged() { if (!ring.placed) ring.current = pv.currentIndex } }
    property int picked: -1
    readonly property int focusIndex: picked >= 0 ? picked : placed ? placedCur : pv.currentIndex
    readonly property var focusItem: items[focusIndex] || null
    readonly property Item focusDelegate: placed ? (placedRep.count, placedRep.itemAt(focusIndex)) : (pv.count, pv.itemAtIndex(focusIndex))
    // a placed ring's items in order round it (for stepping)
    readonly property var order: items.map((it, i) => i).sort((a, b) => (items[a].ang || 0) - (items[b].ang || 0))
    function angleOf(i) { const it = items[i]; return it && it.ang !== undefined ? it.ang : 180 }
    function d(px) { return view.d(px) * view.k }
    signal hovered(int i)
    signal clicked(int i)
    signal rightClicked(int i, Item tile)
    anchors.fill: parent

    // a gauge: a 270 deg track from bottom-left round the top to bottom-right, lit up to the value in focus
    Shape {
        anchors.fill: parent
        visible: ring.gauge && ring.r > 1
        preferredRendererType: Shape.CurveRenderer
        readonly property real v: ring.angleOf(ring.focusIndex)
        property real vA: v
        Behavior on vA { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        ShapePath {
            fillColor: "transparent"; strokeColor: C.alpha(ring.view.rice.fg, 0.16); strokeWidth: ring.d(4.4); capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r; radiusY: ring.r; startAngle: 135; sweepAngle: 270 }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: ring.view.rice.primary; strokeWidth: ring.d(4.4); capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.view.cx; centerY: ring.view.cy; radiusX: ring.r; radiusY: ring.r; startAngle: 135; sweepAngle: Math.max(0.01, parent.vA - 135) }
        }
    }
    // the hairline: brightest on the lens' side, fading to the far side
    Shape {
        anchors.fill: parent
        visible: !ring.gauge && ring.r > 1
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
        visible: ring.active && !ring.gauge && ring.r > 1
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
        model: ring.placed ? 0 : ring.items.length
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
        delegate: Node { orbit: ring }
    }
    Repeater {              // a placed ring: every item at its own angle
        id: placedRep
        model: ring.placed ? ring.items.length : 0
        delegate: Node {
            orbit: ring
            readonly property real a: (ring.angleOf(index) + ring.spin) * Math.PI / 180
            x: ring.view.cx + ring.r * Math.cos(a) - width / 2
            y: ring.view.cy + ring.r * Math.sin(a) - height / 2
        }
    }
    function turn(dd) {
        if (placed) {       // the next item round (a gauge: up = more, no wrap)
            const o = order, p = Math.max(0, o.indexOf(placedCur))
            placedCur = o[gauge ? Math.max(0, Math.min(o.length - 1, p - dd)) : (p + dd + o.length) % o.length]
            current = placedCur
        } else if (dd > 0) pv.incrementCurrentIndex(); else pv.decrementCurrentIndex()
    }
    function bring() {      // the pointer's pick to the slot (the short way); on a placed ring it just stays the focus
        if (picked < 0) return
        if (placed) placedCur = picked; else pv.currentIndex = picked
        current = picked
        picked = -1
    }
    readonly property bool moving: pv.moving
    // where an item is, in the view (its centre)
    function centreOf(i) {
        if (placed) { const a = angleOf(i) * Math.PI / 180; return Qt.point(view.cx + r * Math.cos(a), view.cy + r * Math.sin(a)) }
        const it = pv.itemAtIndex(i); return it ? Qt.point(it.x + it.width / 2, it.y + it.height / 2) : Qt.point(view.cx - r, view.cy)
    }
}
