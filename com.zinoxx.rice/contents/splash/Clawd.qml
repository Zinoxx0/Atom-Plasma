import QtQuick

// Clawd, the Claude Code creature, as live pixel art, with idle animations per mood.
// Ported from ~/.config/quickshell/claude/Clawd.qml (sprite data from waybar's clawd.py).
Item {
    id: root

    property string mood: "happy"   // happy | sweat | panic | limited | sleep
    property real px: 8
    property bool blinking: false
    property bool hopping: false
    property bool interactive: true   // false in the panel, so clicks reach the applet
    property bool animate: true       // pause idle animations when hidden

    readonly property int cols: 22
    readonly property int rows: 10
    readonly property color body: mood === "panic" || mood === "limited" ? "#e85d43"
                                : mood === "sleep" ? "#b98a78" : "#d97757"
    readonly property color eye: "#1f1e1d"
    readonly property color sweat: "#8ec5ff"

    implicitWidth: cols * px
    implicitHeight: rows * px

    function sprite() {
        const p = {};
        const set = (x, y, c) => p[x + "," + y] = c;
        for (const y of [0, 1, 2, 3, 6, 7]) for (let x = 4; x < 16; x++) set(x, y, body);
        for (const y of [4, 5]) for (let x = 2; x < 18; x++) set(x, y, body);
        for (const x of [5, 7, 12, 14]) { set(x, 8, body); set(x, 9, body); }

        const closed = blinking || mood === "sleep" || mood === "limited";
        for (const x of [6, 13]) {
            if (mood === "panic" && !blinking) {
                const dx = x === 6 ? 1 : -1;
                for (const y of [2, 3]) { set(x, y, eye); set(x + dx, y, eye); }
            } else if (closed) {
                set(x, 3, eye);
            } else {
                set(x, 2, eye); set(x, 3, eye);
            }
        }
        const out = [];
        for (const k in p) {
            const [x, y] = k.split(",").map(Number);
            out.push({ x: x, y: y, c: p[k] });
        }
        return out;
    }

    Item {
        id: figure
        width: root.cols * root.px
        height: root.rows * root.px

        Repeater {
            model: root.sprite()
            Rectangle {
                required property var modelData
                x: modelData.x * root.px
                y: modelData.y * root.px
                width: root.px + 0.5     // overlap a hair so no seams at fractional scales
                height: root.px + 0.5
                color: modelData.c
                antialiasing: false
            }
        }

        // Idle bob (faster and jittery when stressed, slow breathing when asleep)
        SequentialAnimation on y {
            running: root.visible && root.animate && !root.hopping
            loops: Animation.Infinite
            NumberAnimation { to: root.mood === "sleep" ? -1 : -root.px * 0.45; duration: root.mood === "panic" ? 180 : root.mood === "sleep" ? 1800 : 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: root.mood === "panic" ? 180 : root.mood === "sleep" ? 1800 : 700; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on x {
            running: root.visible && root.animate && root.mood === "panic"
            loops: Animation.Infinite
            NumberAnimation { to: 1.5; duration: 50 }
            NumberAnimation { to: -1.5; duration: 100 }
            NumberAnimation { to: 0; duration: 50 }
            PauseAnimation { duration: 400 }
        }
    }

    // Sweat drops slide down the sides
    Repeater {
        model: root.mood === "sweat" ? [18] : root.mood === "panic" || root.mood === "limited" ? [18, 1] : []
        Rectangle {
            id: dropItem
            required property var modelData
            x: modelData * root.px
            width: root.px * 1.2
            height: root.px * 1.6
            radius: width / 2
            color: root.sweat
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: -root.px; to: root.px * 3; duration: 1100; easing.type: Easing.InQuad }
                PauseAnimation { duration: 500 }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 250 }
                NumberAnimation { to: 0; duration: 850 }
                PauseAnimation { duration: 500 }
            }
        }
    }

    // Zzz when napping
    Repeater {
        model: root.mood === "sleep" ? 3 : 0
        Text {
            required property int index
            text: "z"
            color: "#e8e3d5"
            font.family: "Inter"
            font.weight: Font.Black
            font.pixelSize: Math.round(root.px * (1.6 + index * 0.5))
            x: root.cols * root.px - root.px * 3
            opacity: 0
            SequentialAnimation on y {
                loops: Animation.Infinite
                PauseAnimation { duration: index * 700 }
                NumberAnimation { from: root.px * 2; to: -root.px * 4; duration: 2100; easing.type: Easing.OutSine }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation { duration: index * 700 }
                NumberAnimation { from: 0; to: 0.9; duration: 500 }
                NumberAnimation { to: 0; duration: 1600 }
            }
        }
    }

    // Blink every few seconds
    Timer {
        interval: 3200 + Math.random() * 2500
        running: root.visible && root.animate && (root.mood === "happy" || root.mood === "sweat" || root.mood === "panic")
        repeat: true
        onTriggered: { root.blinking = true; unblink.restart(); interval = 3200 + Math.random() * 2500 }
    }
    Timer { id: unblink; interval: 140; onTriggered: root.blinking = false }

    // Hop when poked
    function hop() { if (!hopAnim.running) hopAnim.start() }
    SequentialAnimation {
        id: hopAnim
        onStarted: root.hopping = true
        onFinished: root.hopping = false
        NumberAnimation { target: figure; property: "y"; to: -root.px * 2.2; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: figure; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }
    MouseArea { anchors.fill: parent; enabled: root.interactive; onClicked: root.hop(); cursorShape: Qt.PointingHandCursor }
}
