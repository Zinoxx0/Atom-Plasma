import QtQuick
import Atom
import Rice

// A size on the Theme page: a row of ticks lit up to the value (the accent's colours along it), the default a
// taller tick, the value big at the end. Left and right step it (keys, a pad), a click or a drag on the ticks sets
// it; it's applied (commit) once the hands rest (650 ms) or on release. It shows its own value while it moves.
Focusable {
    id: sl
    property real value: 1
    property real min: 0.8
    property real max: 1.8
    property real step: 0.05
    property real def: 1
    property string defLabel: "Standard"
    property var fmt: function (v) { return v.toFixed(2) + "×" }
    signal commit(real v)
    slider: true
    act: "Done"
    readonly property var lk: studio.look
    property real shown: value
    property bool moving: false
    onValueChanged: if (!moving) shown = value
    readonly property int n: Math.round((max - min) / step)
    readonly property int at: Math.round((shown - min) / step)
    readonly property int defAt: Math.round((def - min) / step)
    width: studio.d(960)
    readonly property bool narrow: width < studio.d(700)
    height: studio.d(70)
    lensRadius: studio.d(18)
    function setStep(k) {
        k = Math.max(0, Math.min(n, k))
        if (k === at) return
        moving = true
        shown = Math.round((min + k * step) * 100) / 100
        rest.restart()
    }
    onNudged: dx => setStep(at + dx)
    onActivated: if (rest.running) { rest.stop(); done() }
    // (applied only when it changed: a click on the tick it's at, or a release where it started, does nothing)
    function done() { moving = false; if (Math.abs(shown - value) > step / 4) commit(shown) }
    Timer { id: rest; interval: 650; onTriggered: sl.done() }
    Rectangle { anchors.fill: parent; radius: sl.studio.d(18); color: C.alpha(sl.lk.surfaceHigh, sl.hovered ? 0.62 : 0.4) }
    Row {
        id: ticks
        x: sl.studio.d(24)
        width: sl.width - x - valueBox.width - sl.studio.d(24 + 26)
        height: parent.height
        spacing: (width - (sl.n + 1) * sl.studio.d(3)) / Math.max(1, sl.n)
        Repeater {
            model: sl.n + 1
            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool now: index === sl.at
                width: now ? sl.studio.d(5) : sl.studio.d(3)
                height: now ? sl.studio.d(38) : index === sl.defAt ? sl.studio.d(24) : sl.studio.d(14)
                radius: sl.studio.d(2)
                color: now ? sl.lk.fg : index <= sl.at ? C.mix(sl.lk.primary, sl.lk.secondary, index / Math.max(1, sl.n)) : C.alpha(sl.lk.fg, 0.26)
                Behavior on height { NumberAnimation { duration: Tokens.ms(200) } }
            }
        }
    }
    MouseArea {         // the ticks: a click or a drag sets it, applied on release
        x: ticks.x - sl.studio.d(8); width: ticks.width + sl.studio.d(16); height: parent.height
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function pick(mx) { sl.setStep(Math.round((mx - sl.studio.d(8)) / Math.max(1, ticks.width) * sl.n)) }
        onPressed: m => { sl.studio.clicked(sl, true); pick(m.x) }
        onPositionChanged: m => { if (pressed) pick(m.x) }
        onReleased: { rest.stop(); sl.done() }
    }
    Row {
        id: valueBox
        anchors.right: parent.right; anchors.rightMargin: sl.studio.d(24)
        anchors.verticalCenter: parent.verticalCenter
        spacing: sl.studio.d(sl.narrow ? 16 : 26)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: sl.studio.d(sl.narrow ? 92 : 124)
            horizontalAlignment: Text.AlignRight
            text: sl.fmt(sl.shown)
            color: sl.lk.fg
            font.family: Tokens.font.display; font.weight: Font.DemiBold; font.pixelSize: sl.studio.d(sl.narrow ? 26 : 30); font.features: { "tnum": 1 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: sl.studio.d(sl.narrow ? 64 : 150)
            text: sl.defLabel + "\n" + sl.fmt(sl.def)
            color: sl.lk.fgDim
            lineHeight: 1.15
            font.family: Tokens.font.ui; font.pixelSize: sl.studio.d(14)
        }
    }
}
