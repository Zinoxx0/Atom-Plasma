import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import Rice

// A desk in miniature (the Theme page's saved looks): every screen as it sits, to scale, with a wallpaper each.
Kirigami.ShadowedRectangle {
    id: md
    required property Item studio
    property var thumbs: ({})           // {connector: thumb}
    property bool dim: false
    readonly property var lk: studio.look
    readonly property var scrs: (studio.model.screens || []).slice().sort((a, b) => a.x - b.x)
    function d(px) { return studio.d(px) }
    radius: d(14)
    color: C.mix(lk.surfaceLowest, lk.surfaceHigh, 0.45)
    shadow.size: d(14); shadow.yOffset: d(6); shadow.color: Qt.rgba(0, 0, 0, 0.28)
    readonly property real gap: d(12)
    readonly property real x0: scrs.length ? Math.min(...scrs.map(s => s.x)) : 0
    readonly property real y0: scrs.length ? Math.min(...scrs.map(s => s.y)) : 0
    readonly property real spanW: scrs.length ? Math.max(...scrs.map(s => s.x + s.w)) - x0 : 1
    readonly property real spanH: scrs.length ? Math.max(...scrs.map(s => s.y + s.h)) - y0 : 1
    readonly property real k: Math.max(0.0001, Math.min((width - d(48) - gap * Math.max(0, scrs.length - 1)) / spanW, (height - d(40)) / spanH))
    readonly property real ox: (width - (spanW * k + gap * Math.max(0, scrs.length - 1))) / 2
    readonly property real oy: (height - spanH * k) / 2
    Repeater {
        model: md.scrs.length
        RoundImage {
            required property int index
            readonly property var s: md.scrs[index]
            x: md.ox + (s.x - md.x0) * md.k + index * md.gap; y: md.oy + (s.y - md.y0) * md.k
            width: s.w * md.k; height: s.h * md.k
            radius: md.d(5)
            fill: C.alpha(md.lk.surfaceHigh, 0.6)
            shadowBlur: md.d(8)
            sourceWidth: 240
            opacity: md.dim ? 0.55 : 1
            source: md.thumbs[s.name] ? "file://" + md.thumbs[s.name] : ""
        }
    }
}
