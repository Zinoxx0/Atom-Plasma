import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import "Rice"
import "Rice/Color.js" as C

// CPU / RAM / GPU as gradient rings, in the same style as the Claude widget.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    readonly property real uiScale: pal.uiScale

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) root.uptime = parseFloat(data["stdout"] ?? "0") || 0;
            disconnectSource(source);
        }
    }
    property real uptime: 0
    onExpandedChanged: if (expanded) sh.connectSource('cut -d" " -f1 /proc/uptime #up ' + Date.now())

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
    function heat(v, base) { return v >= 90 ? pal.red : v >= 70 ? pal.yellow : pal.col(base) }

    // CPU history for the sparkline
    property var history: []
    Timer {
        interval: 1000; running: root.expanded; repeat: true; triggeredOnStart: true
        onTriggered: { const h = root.history.concat([root.num(cpu)]); root.history = h.slice(-60) }
    }
    function openMonitor() {
        sh.connectSource("setsid -f plasma-systemmonitor >/dev/null 2>&1 #run " + Date.now());
        root.expanded = false;
    }

    function upText(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return "up " + (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m";
    }

    toolTipMainText: "System"
    toolTipSubText: stats.map(s => s.label + " " + Math.round(s.value) + "%").join("  ·  ")
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        // the same side padding as every rice bar widget
        Layout.minimumWidth: row.implicitWidth + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Tokens.space.md * root.uiScale
            Repeater {
                // fixed count: `stats` is a new array on every sensor update, and using it as the
                // model destroyed and rebuilt (blank, then sweeping from 0) every ring each time
                model: 3
                RowLayout {
                    id: cell
                    required property int index
                    readonly property var stat: root.stats[index]
                    spacing: Tokens.space.sm * root.uiScale
                    Item {
                        implicitWidth: 22 * root.uiScale; implicitHeight: implicitWidth
                        Ring {
                            anchors.fill: parent
                            thickness: 2.5 * root.uiScale
                            instant: true    // a 1.1 s sweep per update kept the panel redrawing
                            value: cell.stat.value
                            from: root.heat(cell.stat.value, cell.stat.from)
                            to: root.heat(cell.stat.value, cell.stat.to)
                            track: C.alpha(pal.fg, 0.14)
                            showText: false
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.stat.icon
                            color: root.heat(cell.stat.value, cell.stat.from)
                            font.family: Tokens.font.icons
                            font.pixelSize: Math.round(12 * root.uiScale)
                        }
                    }
                    Text {
                        id: pct
                        text: Math.round(cell.stat.value) + "%"
                        color: pal.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.round(Tokens.size.label * root.uiScale)
                        font.features: { "tnum": 1 }
                        // room for "100%" so the panel islands don't shift
                        Layout.minimumWidth: Math.ceil(widest.advanceWidth)
                        TextMetrics { id: widest; font: pct.font; text: "100%" }
                    }
                }
            }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: 460
        Layout.preferredHeight: content.implicitHeight + 2 * Tokens.space.lg
        Layout.minimumWidth: 460
        Layout.minimumHeight: content.implicitHeight + 2 * Tokens.space.lg
        // never bigger than the content: Plasma restores a remembered popup size otherwise
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        PopupIn {
            anchors.fill: parent
            active: root.expanded

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                spacing: Tokens.space.lg

                PopupHeader {
                    Layout.fillWidth: true
                    palette: pal
                    title: "System"
                    subtitle: me.host + "  ·  " + root.upText(root.uptime)
                    trailing: IconButton {
                        palette: pal
                        icon: "monitoring"
                        tooltip: "Open System Monitor"
                        size: 34
                        onClicked: root.openMonitor()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: 3    // fixed count, see the compact Repeater
                        ColumnLayout {
                            id: big
                            required property int index
                            readonly property var stat: root.stats[index]
                            Layout.fillWidth: true
                            spacing: Tokens.space.xs + 2
                            Ring {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 118; implicitHeight: 118
                                thickness: 10
                                value: big.stat.value
                                label: big.stat.label
                                from: root.heat(big.stat.value, big.stat.from)
                                to: root.heat(big.stat.value, big.stat.to)
                                track: C.alpha(pal.fg, 0.08)
                                textColor: pal.fg
                                subColor: pal.fgDim
                                active: root.expanded
                            }
                            Text {
                                // filling the width lets the three columns share the row evenly
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: big.stat.sub
                                color: pal.fgDim
                                font.family: Tokens.font.ui
                                font.pixelSize: Tokens.size.label
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                // CPU sparkline
                GlassCard {
                    Layout.fillWidth: true
                    implicitHeight: 78
                    palette: pal
                    SectionHeader {
                        anchors { left: parent.left; top: parent.top; margins: Tokens.space.md }
                        palette: pal
                        text: "CPU · last minute"
                    }
                    Text {
                        anchors { right: parent.right; top: parent.top; margins: Tokens.space.md }
                        text: Math.round(root.stats[0].value) + "%"
                        color: pal.primary
                        font.family: Tokens.font.ui
                        font.weight: Font.Bold
                        font.pixelSize: Tokens.size.small
                        font.features: { "tnum": 1 }
                    }
                    Canvas {
                        id: spark
                        anchors.fill: parent
                        anchors.margins: Tokens.space.md
                        anchors.topMargin: Tokens.space.xl + 6
                        property var points: root.history
                        readonly property color line: pal.primary
                        onPointsChanged: requestPaint()
                        onLineChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const d = points, n = 60;
                            if (d.length < 2) return;
                            const x = i => width * (i + n - d.length) / (n - 1);
                            const y = v => height - Math.max(0, Math.min(100, v)) / 100 * height;
                            const grad = ctx.createLinearGradient(0, 0, 0, height);
                            grad.addColorStop(0, C.alpha(line, 0.45));
                            grad.addColorStop(1, C.alpha(line, 0));
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
                            ctx.strokeStyle = line;
                            ctx.stroke();
                        }
                    }
                }
            }
        }
    }
}
