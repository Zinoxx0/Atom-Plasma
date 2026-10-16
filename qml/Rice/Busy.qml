import QtQuick

// Busy indicator that moves in steps: a ring of dots whose bright head hops one dot per tick,
// leaving a fading tail. Stepped on purpose: it also sits in the panel, where a smooth loop
// would keep plasmashell and KWin redrawing at the full refresh rate. It only ticks while
// `running` and visible.
Item {
    id: busy
    property bool running: false
    property color color: "white"
    property int dots: 8
    property int interval: 140
    property int head: 0

    implicitWidth: 16
    implicitHeight: 16

    Repeater {
        model: busy.dots
        Rectangle {
            required property int index
            readonly property real angle: index / busy.dots * 2 * Math.PI
            readonly property real d: Math.max(2, Math.round(busy.width * 0.22))
            readonly property real r: busy.width / 2 - d / 2
            readonly property int behind: (busy.head - index + busy.dots) % busy.dots
            width: d; height: d; radius: d / 2
            x: busy.width / 2 + Math.sin(angle) * r - d / 2
            y: busy.height / 2 - Math.cos(angle) * r - d / 2
            color: busy.color
            opacity: Math.max(0.2, 1 - behind * 0.22)
        }
    }
    Timer {
        interval: busy.interval
        running: busy.running && busy.visible
        repeat: true
        onTriggered: busy.head = (busy.head + 1) % busy.dots
    }
}
