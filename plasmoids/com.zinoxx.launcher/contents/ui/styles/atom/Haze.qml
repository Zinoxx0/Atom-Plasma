import QtQuick
import Rice

// The atom's haze (the Atom lab's round 7, the user's pick): no hard ring lines, a soft band of light per ring that
// breaks round every item and round the lens, brighter on the lens's side; the active ring wider, in the accent, with a
// hot core at the lens (white light on light themes: dark haze read as smoke). ONE ShaderEffect draws every ring
// (haze.frag: each band an exact blurred annulus, coloured by the angle to the lens). It replaced three Shape bands and
// three MultiEffect blurs per ring, re-blurred on every frame anything moved (2026-11-23: most of the launcher's
// dropped frames). The gaps: every Node puts a plain disc in `gaps` (its shown radius + `gap`), the lens one more; the
// shader blurs that mask by `soft`, so the haze fades out the same distance before every item, on every screen.
Item {
    id: haze
    required property var view
    readonly property real k: view.k
    function d(px) { return view.d(px) * view.k }
    // the box: the outermost ring at its widest, plus the blur
    readonly property real reach: d(Math.max(300, ...view.shells.map(s => s.radius || 300)) + view.dockLift + 44)
    x: view.cx - reach
    y: view.cy - reach
    width: 2 * reach
    height: width
    readonly property real gap: d(8)                // past an item's shown edge, the haze is gone ...
    readonly property real soft: d(5)               // ... and back over this much more
    property real blurK: 0.42
    property alias gaps: gaps

    function ringOf(i) { const o = haze.view.ringAt(i); return o && !o.gauge ? o : null }
    readonly property var rings: { haze.view.ringCount; return [ringOf(0), ringOf(1), ringOf(2), ringOf(3)] }
    function rad(o) { return o && o.r > 1 ? o.r : 0 }

    // the gaps: hard discs, drawn at half the resolution (the shader softens them)
    Item {
        id: gaps
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width / 2)), Math.max(1, Math.ceil(height / 2)))
        Rectangle {         // round the lens
            readonly property real r: haze.view.lensHole
            visible: r > 0
            x: haze.view.lensX - haze.x - r; y: haze.view.lensY - haze.y - r
            width: 2 * r; height: width; radius: r
            color: "black"
        }
    }

    readonly property color fg: view.rice.fg
    readonly property color pri: view.rice.primary
    readonly property bool light: !!view.rice.light
    readonly property color band: light ? "#ffffff" : pri          // light themes: white light, not smoke
    readonly property color far: light ? "#ffffff" : fg
    readonly property color hot: light ? pri : C.mix(pri, "#ffffff", 0.45)

    ShaderEffect {
        anchors.fill: parent
        visible: radii.x + radii.y + radii.z + radii.w > 0
        fragmentShader: "haze.frag.qsb"
        readonly property size boxSize: Qt.size(width, height)
        readonly property point centre: Qt.point(haze.reach, haze.reach)
        readonly property vector4d radii: Qt.vector4d(haze.rad(haze.rings[0]), haze.rad(haze.rings[1]), haze.rad(haze.rings[2]), haze.rad(haze.rings[3]))
        readonly property vector4d lits: Qt.vector4d(...haze.rings.map(o => o ? o.lit : 0))
        readonly property vector4d shows: Qt.vector4d(...haze.rings.map(o => o ? o.reveal : 0))
        readonly property vector4d widths: Qt.vector4d(haze.d(7), haze.d(16), haze.d(3), 0)
        // (the lab's CSS sigmas through MultiEffect, which blurred much less than its blurMax says: matched by eye)
        readonly property vector4d sigmas: Qt.vector4d(haze.d(4 * haze.blurK), haze.d(7 * haze.blurK), haze.d(1.6 * haze.blurK), 0)
        readonly property vector4d stops: Qt.vector4d(Math.PI / 2, Math.PI * 0.75, Math.PI * 35 / 180, Math.PI / 2)
        readonly property real lens: haze.view.lensAngle * Math.PI / 180
        readonly property real soft: haze.soft
        readonly property var holes: gaps
        // a quiet ring: the fg, faint
        readonly property color q0: C.alpha(haze.fg, 0.30)
        readonly property color q1: C.alpha(haze.fg, 0.13)
        readonly property color q2: C.alpha(haze.fg, 0.11)
        readonly property color q3: C.alpha(haze.fg, 0.09)
        // the active one: wide, in the accent
        readonly property color w0: C.alpha(haze.band, 1)
        readonly property color w1: C.alpha(C.mix(haze.band, haze.far, 0.5), haze.light ? 0.7 : 0.5)
        readonly property color w2: C.alpha(C.mix(haze.band, haze.far, 0.75), haze.light ? 0.58 : 0.37)
        readonly property color w3: C.alpha(haze.far, haze.light ? 0.45 : 0.24)
        // ... and its hot core at the lens
        readonly property color h0: C.alpha(haze.hot, 1)
        readonly property color h1: C.alpha(haze.pri, 0.8)
        readonly property color h2: C.alpha(haze.pri, 0.15)
        readonly property color h3: C.alpha(haze.pri, 0)
    }
}
