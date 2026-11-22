import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Rice

// One ring of the atom: its items on a circle round the core, the slot at 9 o'clock holding the current item (the next
// one below it). The pointer picks an item where it is (`picked`; the ring doesn't turn under it).
// Its line is a HAZE (the Atom lab's round 7, 2026-11-22, the user's pick): no hard line, a soft band of light that
// breaks round every item and round the lens (so it never runs behind an icon), brighter on the lens's side. The
// active ring's band is wider, in the accent and hottest at the lens, with a soft hot core; on light themes it is white
// light (dark haze read as smoke). The light hands over between rings gently (`lit`). Each band is a hidden annulus
// (HazeBand) drawn through a MultiEffect: blurred, the gaps (HazeHole discs in `holes`: one from every Node, one round
// the lens) masked out.
// Items are laid out one of three ways:
//  - a PathView (Apps, Search): even steps; a long ring shows `window` items at a time, the rest come round through a
//    gap on the far side (they fade there);
//  - docked (the view's `dock`: Home; the lab's round 6): the ring places them itself (angleAt), so the active ring is a
//    dock: the focus biggest, its neighbours less (a gaussian over their distance in items) and they make room (the
//    steps grow with the sizes, still a whole turn); the other rings rest a little smaller, the active one lifts out.
//    The dock centres on the focus where it is (a pointer's pick grows in place, its neighbours step aside);
//  - placed: the items at their own angles (it.ang: degrees clockwise from 3 o'clock; the colour wheel, gauges) and the
//    focus moves between them, nothing turns. A gauge is a placed ring of values drawn as an arc filled to the focus.
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
    readonly property int count: items.length
    property real reveal: 1                 // the opening's spiral: 0 in the core, 1 out on the ring
    property bool placed: false
    property bool gauge: false
    readonly property bool docked: view.dock && !placed && !gauge
    // handed over between rings: the light, and on a docked ring the dock and the lift
    property real lit: active ? 1 : 0
    Behavior on lit { NumberAnimation { duration: Tokens.ms(480); easing.type: Easing.OutCubic } }
    property real docking: docked && active ? 1 : 0
    Behavior on docking { NumberAnimation { duration: Tokens.ms(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    readonly property real r: view.d(radius + (docked ? view.dockLift * docking : 0)) * view.k * reveal
    readonly property real spin: -150 * (1 - reveal)
    property int placedCur: 0
    property alias turned: pv.currentIndex
    property int current: 0                 // the focus at rest (the slot, or a placed ring's)
    onCurrentChanged: {
        if (placed) placedCur = current
        else if (docked) { if (count && mod(turnTo, count) !== current) turnTo += wrapC(current - mod(turnTo, count), count) }
        else if (pv.currentIndex !== current) pv.currentIndex = current
    }
    Connections { target: pv; function onCurrentIndexChanged() { if (!ring.placed && !ring.docked) ring.current = pv.currentIndex } }
    property int picked: -1
    readonly property int slotIndex: placed ? placedCur : docked ? (count ? mod(turnTo, count) : 0) : pv.currentIndex
    readonly property int focusIndex: picked >= 0 ? picked : slotIndex
    readonly property var focusItem: items[focusIndex] || null
    readonly property Item focusDelegate: placed ? (placedRep.count, placedRep.itemAt(focusIndex))
                                        : docked ? (dockRep.count, dockRep.itemAt(focusIndex)) : (pv.count, pv.itemAtIndex(focusIndex))
    // a placed ring's items in order round it (for stepping)
    readonly property var order: items.map((it, i) => i).sort((a, b) => (items[a].ang || 0) - (items[b].ang || 0))
    function angleOf(i) { const it = items[i]; return it && it.ang !== undefined ? it.ang : 180 }
    function d(px) { return view.d(px) * view.k }
    function mod(a, n) { return ((a % n) + n) % n }
    function wrapC(x, n) { return ((x % n) + n + n / 2) % n - n / 2 }     // -n/2 .. n/2 (works for fractions)
    signal hovered(int i)
    signal unhovered(int i)
    signal clicked(int i)
    signal rightClicked(int i, Item tile)
    anchors.fill: parent

    // ------------------------------------------------------------------ docked: the ring lays its items out itself
    property int turnTo: 0                  // unbounded: the slot's item is turnTo mod count
    property real turnPos: turnTo
    Behavior on turnPos { enabled: ring.docked; NumberAnimation { duration: Tokens.ms(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    onTurnToChanged: if (docked && count) current = mod(turnTo, count)
    // the dock's centre: the focus (the slot's item, or the pointer's pick where it is), counted near the turn
    readonly property real dockTarget: picked >= 0 && count ? turnTo + wrapC(picked - mod(turnTo, count), count) : turnTo
    property real dockAt: dockTarget
    Behavior on dockAt { enabled: ring.docked; NumberAnimation { duration: Tokens.ms(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    readonly property int span: lengthy ? window : count        // the items a whole turn holds
    function erf(x) {       // Abramowitz-Stegun 7.1.26 (|error| < 1.5e-7)
        const s = x < 0 ? -1 : 1, a = Math.abs(x), t = 1 / (1 + 0.3275911 * a)
        return s * (1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-a * a))
    }
    // degrees round the ring from the dock's centre to `o` items away: the integral of the items' relative sizes (1 +
    // f * a gaussian), scaled so a whole turn is 360 (so the bigger ones near the focus get more room)
    function along(o) {
        const s = view.dockSigma, f = (view.dockFocus - 1) * docking * (span > 2 ? 1 : 0), A = f * s * Math.sqrt(Math.PI) / 2
        return 360 * (o + A * erf(o / s)) / (span + 2 * A * erf(span / 2 / s))
    }
    function angleAt(i) {   // where item i is this frame (deg, clockwise from 3 o'clock)
        return 180 - (dockAt - turnPos) * 360 / span - along(wrapC(i - dockAt, count)) + spin
    }
    function scaleAt(i) {   // its shown size over its own (the dock's: the focus most; at rest a little smaller)
        const o = wrapC(i - dockAt, count), it = items[i] || {}
        const g = 1 + (view.dockFocus - 1) * Math.exp(-Math.pow(o / view.dockSigma, 2))
        const m = Math.min(g, Math.max(1, view.dockMax / (it.big || size)))
        return view.dockRest + (m - view.dockRest) * docking
    }
    function focusScale(i) { const it = items[i] || {}; return Math.min(view.dockFocus, Math.max(1, view.dockMax / (it.big || size))) }
    function fadeAt(i) { return lengthy ? M.clamp(span / 2 - Math.abs(wrapC(i - turnPos, count))) : 1 }
    // the slot item's shown size (design px * k): the ring's name sits over it
    readonly property real slotShown: { const it = items[slotIndex] || {}; return d(it.big || size) * (docked ? scaleAt(slotIndex) : 1) }

    // ------------------------------------------------------------------ the haze
    readonly property real boxR: view.d(radius + view.dockLift + 44) * view.k   // its box: the ring at its widest + the blur
    readonly property real hazeX: view.cx - boxR
    readonly property real hazeY: view.cy - boxR
    property alias holes: holes
    function blurPx(sigma) { return Math.max(2, Math.round(d(sigma * 2.5))) }  // a blur's reach for the lab's CSS sigma
    Item {
        id: haze
        x: ring.hazeX; y: ring.hazeY
        width: 2 * ring.boxR; height: width
        visible: !ring.gauge && ring.r > 1
        opacity: ring.reveal
        readonly property color fg: ring.view.rice.fg
        readonly property color pri: ring.view.rice.primary
        readonly property bool light: !!ring.view.rice.light
        readonly property color band: light ? "#ffffff" : pri           // light themes: white light, not smoke
        readonly property color far: light ? "#ffffff" : fg
        readonly property color hot: light ? pri : C.mix(pri, "#ffffff", 0.45)
        HazeBand {          // a quiet ring
            id: quietBand
            anchors.fill: parent
            r: ring.r; w: ring.d(7); lens: ring.view.lensAngle
            c0: C.alpha(haze.fg, 0.30); a1: 90; c1: C.alpha(haze.fg, 0.13); a2: 135; c2: C.alpha(haze.fg, 0.11); c3: C.alpha(haze.fg, 0.09)
        }
        HazeBand {          // the active one: wide, in the accent
            id: wideBand
            anchors.fill: parent
            r: ring.r; w: ring.d(16); lens: ring.view.lensAngle
            c0: C.alpha(haze.band, 1)
            a1: 90; c1: C.alpha(C.mix(haze.band, haze.far, 0.5), haze.light ? 0.7 : 0.5)
            a2: 135; c2: C.alpha(C.mix(haze.band, haze.far, 0.75), haze.light ? 0.58 : 0.37)
            c3: C.alpha(haze.far, haze.light ? 0.45 : 0.24)
        }
        HazeBand {          // ... and its hot core at the lens
            id: hotBand
            anchors.fill: parent
            r: ring.r; w: ring.d(3); lens: ring.view.lensAngle
            c0: C.alpha(haze.hot, 1); a1: 35; c1: C.alpha(haze.pri, 0.8); a2: 90; c2: C.alpha(haze.pri, 0.15); c3: C.alpha(haze.pri, 0)
        }
        MultiEffect {
            anchors.fill: parent; source: quietBand; autoPaddingEnabled: false
            opacity: 1 - ring.lit; visible: opacity > 0.01
            blurEnabled: true; blur: 1; blurMax: ring.blurPx(4)
            maskEnabled: true; maskSource: holes; maskInverted: true
        }
        MultiEffect {
            anchors.fill: parent; source: wideBand; autoPaddingEnabled: false
            opacity: ring.lit; visible: opacity > 0.01
            blurEnabled: true; blur: 1; blurMax: ring.blurPx(7)
            maskEnabled: true; maskSource: holes; maskInverted: true
        }
        MultiEffect {
            anchors.fill: parent; source: hotBand; autoPaddingEnabled: false
            opacity: ring.lit; visible: opacity > 0.01
            blurEnabled: true; blur: 1; blurMax: ring.blurPx(1.6)
            maskEnabled: true; maskSource: holes; maskInverted: true
        }
        Item {              // the gaps: a soft disc round every item (Node puts its own here) and round the lens
            id: holes
            anchors.fill: parent
            visible: false; layer.enabled: true
            HazeHole {
                cx: ring.view.lensX - ring.hazeX; cy: ring.view.lensY - ring.hazeY
                rad: ring.view.lensHole; soft: ring.d(4)
            }
        }
    }

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

    PathView {
        id: pv
        anchors.fill: parent
        model: ring.placed || ring.docked ? 0 : ring.items.length
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
    Repeater {              // a docked ring: every item where the dock puts it
        id: dockRep
        model: ring.docked ? ring.items.length : 0
        delegate: Node {
            orbit: ring
            readonly property real a: ring.angleAt(index) * Math.PI / 180
            x: ring.view.cx + ring.r * Math.cos(a) - width / 2
            y: ring.view.cy + ring.r * Math.sin(a) - height / 2
        }
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
        } else if (docked) turnTo += dd
        else if (dd > 0) pv.incrementCurrentIndex(); else pv.decrementCurrentIndex()
    }
    function bring() {      // the pointer's pick to the slot (the short way); on a placed ring it just stays the focus
        if (picked < 0) return
        if (placed) placedCur = picked
        else if (docked) turnTo += wrapC(picked - mod(turnTo, count), count)
        else pv.currentIndex = picked
        current = picked
        picked = -1
    }
    // the item that will sit nearest angle `pa` (deg) once the ring has finished turning (-1: none shows there)
    function landingAt(pa) {
        if (!count || placed) return -1
        const step = 360 / span, o = Math.round(wrapC(180 - pa, 360) / step)
        if (lengthy && Math.abs(o) > (span - 1) / 2) return -1
        return mod((docked ? turnTo : pv.currentIndex) + o, count)
    }
    readonly property bool moving: docked ? Math.abs(turnPos - turnTo) > 0.002 : pv.moving
    // where an item is, in the view (its centre)
    function centreOf(i) {
        if (placed) { const a = angleOf(i) * Math.PI / 180; return Qt.point(view.cx + r * Math.cos(a), view.cy + r * Math.sin(a)) }
        const it = docked ? dockRep.itemAt(i) : pv.itemAtIndex(i)
        return it ? Qt.point(it.x + it.width / 2, it.y + it.height / 2) : Qt.point(view.cx - r, view.cy)
    }
}
