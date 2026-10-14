import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.kirigami as Kirigami

// CPU / RAM / GPU as gradient rings, in the same style as the Claude widget.
PlasmoidItem {
    id: root

    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    function col(n, f) { return pal[n] ?? f }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            try { root.pal = JSON.parse(data["stdout"]) } catch (e) {}
            disconnectSource(source);
        }
    }
    function refresh() { sh.connectSource('cat "$HOME/.local/state/rice/palette-' + screenName + '.json" 2>/dev/null || cat "$HOME/.local/state/rice/palette.json" #pal ' + Date.now()) }
    Component.onCompleted: refresh()
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()
    // each bar follows its own screen's wallpaper (palette-<output>.json, see rice.py)
    readonly property string screenName: Screen.name
    onScreenNameChanged: refresh()

    readonly property int rate: expanded ? 1000 : 2500
    Sensors.Sensor { id: cpu;     sensorId: "cpu/all/usage";               updateRateLimit: root.rate }
    Sensors.Sensor { id: cpuTemp; sensorId: "cpu/all/averageTemperature";  updateRateLimit: root.rate }
    Sensors.Sensor { id: mem;     sensorId: "memory/physical/usedPercent"; updateRateLimit: root.rate }
    Sensors.Sensor { id: memUsed; sensorId: "memory/physical/used";        updateRateLimit: root.rate }
    Sensors.Sensor { id: memTot;  sensorId: "memory/physical/total";       updateRateLimit: 60000 }
    Sensors.Sensor { id: gpu;     sensorId: "gpu/gpu0/usage";              updateRateLimit: root.rate }
    Sensors.Sensor { id: gpuTemp; sensorId: "gpu/gpu0/temperature";        updateRateLimit: root.rate }
    Sensors.Sensor { id: igpu;    sensorId: "gpu/gpu1/usage";              updateRateLimit: root.rate }

    function num(s) { const v = Number(s.value); return isFinite(v) ? v : 0 }
    readonly property var stats: [
        { key: "cpu", label: "CPU", icon: "memory", value: num(cpu), from: "primary", to: "cyan",
          sub: cpuTemp.value ? Math.round(num(cpuTemp)) + "°C" : "" },
        { key: "mem", label: "RAM", icon: "memory_alt", value: num(mem), from: "tertiary", to: "magenta",
          sub: (num(memUsed) / 1073741824).toFixed(1) + " / " + Math.round(num(memTot) / 1073741824) + " GB" },
        { key: "gpu", label: "GPU", icon: "stadia_controller", value: Math.max(num(gpu), num(igpu)), from: "green", to: "teal",
          sub: (gpuTemp.value ? Math.round(num(gpuTemp)) + "°C · " : "") + "iGPU " + Math.round(num(igpu)) + "%" },
    ]
    function heat(v, base) { return v >= 90 ? col("red", "#f7768e") : v >= 70 ? col("yellow", "#e0af68") : col(base, "#7aa2f7") }

    // CPU history for the sparkline
    property var history: []
    Timer {
        interval: 1000; running: root.expanded; repeat: true; triggeredOnStart: true
        onTriggered: { const h = root.history.concat([root.num(cpu)]); root.history = h.slice(-60) }
    }

    toolTipMainText: "System"
    toolTipSubText: stats.map(s => s.label + " " + Math.round(s.value) + "%").join("  ·  ")
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        Layout.minimumWidth: row.implicitWidth + 16 * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10 * root.uiScale
            Repeater {
                // fixed count: `stats` is a new array on every sensor update, and using it as the
                // model destroyed and rebuilt (blank, then sweeping from 0) every ring each time
                model: 3
                RowLayout {
                    id: cell
                    required property int index
                    readonly property var stat: root.stats[index]
                    spacing: 4 * root.uiScale
                    Item {
                        implicitWidth: 22 * root.uiScale; implicitHeight: implicitWidth
                        Ring {
                            anchors.fill: parent
                            thickness: 2.5 * root.uiScale
                            instant: true    // a 1.1 s sweep per update kept the panel redrawing
                            value: cell.stat.value
                            from: root.heat(cell.stat.value, cell.stat.from)
                            to: root.heat(cell.stat.value, cell.stat.to)
                            track: Qt.alpha(root.col("on_surface", "#c0caf5"), 0.14)
                            showText: false
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.stat.icon
                            color: root.heat(cell.stat.value, cell.stat.from)
                            font.family: "Material Symbols Rounded"; font.pixelSize: Math.round(12 * root.uiScale)
                        }
                    }
                    PlasmaComponents.Label {
                        id: pct
                        text: Math.round(cell.stat.value) + "%"
                        color: root.col("on_surface", Kirigami.Theme.textColor)
                        font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: Math.round(12 * root.uiScale)
                        font.features: { "tnum": 1 }
                        // room for "100%" so the panel islands don't shift
                        Layout.minimumWidth: Math.max(30 * root.uiScale, Math.ceil(widest.advanceWidth))
                        TextMetrics { id: widest; font: pct.font; text: "100%" }
                    }
                }
            }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: 440
        Layout.preferredHeight: content.implicitHeight + 24
        Layout.minimumWidth: 440
        Layout.minimumHeight: content.implicitHeight + 24

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 16

            Text {
                text: "System"
                color: root.col("on_surface", "#c0caf5")
                font.family: "Inter Display"; font.weight: Font.ExtraBold; font.pixelSize: 24
            }

            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: 3    // fixed count, see the compact Repeater
                    ColumnLayout {
                        id: big
                        required property int index
                        readonly property var stat: root.stats[index]
                        Layout.fillWidth: true
                        spacing: 6
                        Ring {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 118; implicitHeight: 118
                            thickness: 10
                            value: big.stat.value
                            label: big.stat.label
                            from: root.heat(big.stat.value, big.stat.from)
                            to: root.heat(big.stat.value, big.stat.to)
                            track: Qt.alpha(root.col("on_surface", "#c0caf5"), 0.08)
                            textColor: root.col("on_surface", "#c0caf5")
                            subColor: root.col("on_surface_variant", "#a9b1d6")
                            active: root.expanded
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: big.stat.sub
                            color: root.col("on_surface_variant", "#a9b1d6")
                            font.family: "Inter"; font.pixelSize: 12
                        }
                    }
                }
            }

            // CPU sparkline
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 70
                radius: 14
                color: Qt.alpha(root.col("surface_highest", "#292e42"), 0.5)
                Text {
                    anchors { left: parent.left; top: parent.top; margins: 10 }
                    text: "CPU · last minute"
                    color: root.col("muted", "#565f89")
                    font.family: "Inter"; font.pixelSize: 11
                }
                Canvas {
                    id: spark
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.topMargin: 24
                    property var points: root.history
                    onPointsChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const d = points, n = 60;
                        if (d.length < 2) return;
                        const x = i => width * (i + n - d.length) / (n - 1);
                        const y = v => height - Math.max(0, Math.min(100, v)) / 100 * height;
                        const grad = ctx.createLinearGradient(0, 0, 0, height);
                        grad.addColorStop(0, Qt.alpha(root.col("primary", "#7aa2f7"), 0.45));
                        grad.addColorStop(1, Qt.alpha(root.col("primary", "#7aa2f7"), 0));
                        ctx.beginPath();
                        ctx.moveTo(x(0), height);
                        for (let i = 0; i < d.length; i++) ctx.lineTo(x(i), y(d[i]));
                        ctx.lineTo(x(d.length - 1), height);
                        ctx.closePath();
                        ctx.fillStyle = grad;
                        ctx.fill();
                        ctx.beginPath();
                        for (let i = 0; i < d.length; i++) i ? ctx.lineTo(x(i), y(d[i])) : ctx.moveTo(x(i), y(d[i]));
                        ctx.lineWidth = 2;
                        ctx.lineJoin = "round";
                        ctx.strokeStyle = root.col("primary", "#7aa2f7");
                        ctx.stroke();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    text: "System Monitor"
                    icon.name: "utilities-system-monitor"
                    onClicked: { sh.connectSource("setsid -f plasma-systemmonitor >/dev/null 2>&1 #run " + Date.now()); root.expanded = false }
                }
            }
        }
    }
}
