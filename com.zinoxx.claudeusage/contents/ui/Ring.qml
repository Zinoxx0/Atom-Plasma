import QtQuick

// Circular gauge: sweeps to `value` (0-100), with a small dot marking where
// usage would be if spread evenly over the window (`pace`, 0-100).
Item {
    id: root

    property real value: 0
    property real pace: -1
    property real shown: 0
    property color from: "#d0bcff"
    property color to: "#efb8c8"
    property color track: "#33ffffff"
    property color paceColor: "#ffffff"
    property real thickness: 12
    property string label: ""
    property string sub: ""
    property color textColor: "white"
    property color subColor: "#bbbbbb"
    property bool showText: true

    implicitWidth: 140
    implicitHeight: 140

    property bool instant: false
    Behavior on shown { enabled: !root.instant; NumberAnimation { duration: 1100; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()
    onFromChanged: canvas.requestPaint()
    onToChanged: canvas.requestPaint()
    onPaceChanged: canvas.requestPaint()

    property bool active: true
    onActiveChanged: if (active) sweep()
    function sweep() { instant = true; shown = 0; instant = false; sweepTimer.restart() }
    Timer { id: sweepTimer; interval: 60; onTriggered: root.shown = root.value }
    onValueChanged: shown = value

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const r = Math.min(width, height) / 2 - root.thickness / 2 - 2;
            const start = -Math.PI / 2;

            ctx.lineCap = "round";
            ctx.lineWidth = root.thickness;
            ctx.strokeStyle = root.track;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            // progress: short segments blending from -> to (Canvas conical gradients run the wrong way)
            const frac = Math.max(0, Math.min(1, root.shown / 100));
            if (frac > 0.002) {
                const mix = (t) => Qt.rgba(root.from.r + (root.to.r - root.from.r) * t,
                                           root.from.g + (root.to.g - root.from.g) * t,
                                           root.from.b + (root.to.b - root.from.b) * t, 1);
                const n = Math.max(2, Math.ceil(frac * 90));
                ctx.lineCap = "butt";
                for (let i = 0; i < n; i++) {
                    const a0 = start + frac * Math.PI * 2 * i / n;
                    const a1 = start + frac * Math.PI * 2 * (i + 1) / n + 0.01;
                    ctx.strokeStyle = mix(i / Math.max(1, n - 1));
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, a0, a1);
                    ctx.stroke();
                }
                // round caps
                const end = start + frac * Math.PI * 2;
                ctx.fillStyle = root.from;
                ctx.beginPath(); ctx.arc(cx + r * Math.cos(start), cy + r * Math.sin(start), root.thickness / 2, 0, Math.PI * 2); ctx.fill();
                ctx.fillStyle = root.to;
                ctx.beginPath(); ctx.arc(cx + r * Math.cos(end), cy + r * Math.sin(end), root.thickness / 2, 0, Math.PI * 2); ctx.fill();
            }

            if (root.pace >= 0) {
                const a = start + Math.min(1, root.pace / 100) * Math.PI * 2;
                ctx.fillStyle = root.paceColor;
                ctx.beginPath();
                ctx.arc(cx + r * Math.cos(a), cy + r * Math.sin(a), root.thickness * 0.22, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: root.showText
        spacing: -2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.shown) + "%"
            color: root.textColor
            font.family: "Inter Display"
            font.weight: Font.ExtraBold
            font.pixelSize: Math.round(root.height * 0.22)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.subColor
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(root.height * 0.085)
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
        }
    }
}
