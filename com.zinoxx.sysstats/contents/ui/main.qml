import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors
import "Rice"
import "Rice/Color.js" as C

// CPU / RAM / GPU as gradient rings, in the same style as the Claude widget. The popup adds a
// three-minute history of each (tabs) and what uses the most of it right now.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }
    readonly property real uiScale: pal.uiScale

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) root.uptime = parseFloat(data["stdout"] ?? "0") || 0;
            else if (source.indexOf("#top") >= 0) root.topProcs = root.parseTop(data["stdout"] ?? "");
            disconnectSource(source);
        }
    }
    property real uptime: 0
    onExpandedChanged: if (expanded) sh.connectSource('cut -d" " -f1 /proc/uptime #up')

    readonly property int rate: expanded ? 1000 : 2500
    Sensors.Sensor { id: cpu;     sensorId: "cpu/all/usage";               updateRateLimit: root.rate }
    Sensors.Sensor { id: cpuTemp; sensorId: "cpu/all/averageTemperature";  updateRateLimit: root.rate }
    Sensors.Sensor { id: mem;     sensorId: "memory/physical/usedPercent"; updateRateLimit: root.rate }
    Sensors.Sensor { id: memUsed; sensorId: "memory/physical/used";        updateRateLimit: root.rate }
    Sensors.Sensor { id: memTot;  sensorId: "memory/physical/total";       updateRateLimit: 60000 }
    // which GPU is which, by name: ksystemstats numbers them in the order they're found, which a kernel or
    // driver change can swap. The NVIDIA gets the clock weighting below, the other one the median.
    Sensors.Sensor { id: name0; sensorId: "gpu/gpu0/name"; updateRateLimit: 60000 }
    Sensors.Sensor { id: name1; sensorId: "gpu/gpu1/name"; updateRateLimit: 60000 }
    function isNvidia(s) { return /nvidia|geforce|quadro/i.test(String(s.value ?? "")) }
    readonly property bool swapped: isNvidia(name1) && !isNvidia(name0)
    readonly property string dgpu: "gpu/" + (swapped ? "gpu1" : "gpu0")
    readonly property string other: "gpu/" + (swapped ? "gpu0" : "gpu1")
    Sensors.Sensor { id: gpu;     sensorId: root.dgpu + "/usage";          updateRateLimit: root.rate }
    Sensors.Sensor { id: gpuTemp; sensorId: root.dgpu + "/temperature";    updateRateLimit: root.rate }
    Sensors.Sensor { id: igpu;    sensorId: root.other + "/usage";         updateRateLimit: root.rate
                     onValueChanged: root.igpuRecent = root.igpuRecent.concat([root.num(igpu)]).slice(-3) }
    Sensors.Sensor { id: gpuClock; sensorId: root.dgpu + "/coreFrequency"; updateRateLimit: root.rate
                     onValueChanged: root.gpuTopClock = Math.max(root.gpuTopClock, root.num(gpuClock)) }

    function num(s) { const v = Number(s.value); return isFinite(v) ? v : 0 }

    // GPU load as work done, not the raw "busy" %: idling at 210 MHz (a tenth of its boost) the NVIDIA
    // reads 100 % busy from a few compositor frames, so its usage is weighted by its clock against the
    // highest clock seen (from 1800 MHz: it boosts past that within a minute). The iGPU's sensor throws
    // single 100 % readings as it wakes from GFXOFF, so it shows the median of its last three.
    property real gpuTopClock: 1800
    readonly property real gpuLoad: num(gpuClock) > 0 ? num(gpu) * Math.min(1, num(gpuClock) / gpuTopClock) : num(gpu)
    property var igpuRecent: []
    readonly property real igpuLoad: igpuRecent.length ? igpuRecent.slice().sort((a, b) => a - b)[(igpuRecent.length - 1) >> 1] : 0
    readonly property var stats: [
        { key: "cpu", label: "CPU", icon: "memory", value: num(cpu), from: "primary", to: "secondary",
          sub: cpuTemp.value ? Math.round(num(cpuTemp)) + "°C" : "" },
        { key: "mem", label: "RAM", icon: "memory_alt", value: num(mem), from: "secondary", to: "tertiary",
          sub: (num(memUsed) / 1073741824).toFixed(1) + " / " + Math.round(num(memTot) / 1073741824) + " GB" },
        { key: "gpu", label: "GPU", icon: "stadia_controller", value: Math.max(gpuLoad, igpuLoad), from: "tertiary", to: "primary",
          sub: (gpuTemp.value ? Math.round(num(gpuTemp)) + "°C · " : "") + "iGPU " + Math.round(igpuLoad) + "%" },
    ]
    // the screen's own colour family; past 70 / 90 % the (harmonized) warning colours take over
    function heat(v, base) { return v >= 90 ? pal.bad : v >= 70 ? pal.warn : pal[base] }

    // three minutes of each, sampled every 2 s all the time (data only: nothing is drawn while the
    // popup is closed), so the graph is full the moment it opens
    readonly property int samples: 90
    property var history: [[], [], []]
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.history = root.stats.map((s, i) => root.history[i].concat([s.value]).slice(-root.samples))
    }
    property int tab: 0                 // which history the popup shows: cpu / mem / gpu

    // the top three for the shown tab, refreshed every 2 s while open
    property var topProcs: []
    function topCommand() {
        return tab === 2
            ? "nvidia-smi pmon -c 1 -s u 2>/dev/null | awk 'NR > 2 && $4 ~ /^[0-9]+$/ { print $4, $NF }' | sort -rn | head -3"
            : "ps -eo " + (tab === 1 ? "rss" : "pcpu") + ",comm --no-headers --sort=-" + (tab === 1 ? "rss" : "pcpu") + " | head -3"
    }
    function readTop() { sh.connectSource(topCommand() + " #top") }
    function parseTop(out) {
        return out.split("\n").map(l => l.trim()).filter(l => l).map(l => {
            const i = l.indexOf(" ");
            const v = Number(l.slice(0, i));
            // rss is in KiB; a process's GPU share is weighted by the clock like the ring
            return { name: l.slice(i + 1).trim(),
                     value: tab === 1 ? v / 1048576 : tab === 2 && num(gpuClock) > 0 ? v * Math.min(1, num(gpuClock) / gpuTopClock) : v }
        });
    }
    Timer { interval: 2000; running: root.expanded; repeat: true; triggeredOnStart: true; onTriggered: root.readTop() }
    onTabChanged: { topProcs = []; readTop() }
    function openMonitor() {
        sh.connectSource("setsid -f plasma-systemmonitor >/dev/null 2>&1 #run");
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
            spacing: Tokens.space.sm * root.uiScale
            Repeater {
                // fixed count: `stats` is a new array on every sensor update, and using it as the
                // model destroyed and rebuilt (blank, then sweeping from 0) every ring each time
                model: 3
                RowLayout {
                    id: cell
                    required property int index
                    readonly property var stat: root.stats[index]
                    spacing: Tokens.space.xs * root.uiScale
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
                        // a full 100 drops its sign: "100" fits in the room kept for "00%", so the
                        // panel islands never shift, and 1% doesn't trail two empty digits
                        text: Math.round(cell.stat.value) >= 100 ? "100" : Math.round(cell.stat.value) + "%"
                        color: pal.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.round(Tokens.size.label * root.uiScale)
                        font.features: { "tnum": 1 }
                        Layout.minimumWidth: Math.ceil(widest.advanceWidth)
                        TextMetrics { id: widest; font: pct.font; text: "00%" }
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
            ricePalette: pal

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

                // history: one tab per meter, its line in that meter's colours
                GlassCard {
                    id: hist
                    Layout.fillWidth: true
                    implicitHeight: histCol.implicitHeight + 2 * Tokens.space.md
                    palette: pal
                    readonly property var stat: root.stats[root.tab]
                    readonly property var points: root.history[root.tab]
                    readonly property color lineA: root.heat(stat.value, stat.from)
                    readonly property color lineB: root.heat(stat.value, stat.to)
                    function stat3() {
                        const d = points;
                        if (!d.length) return "";
                        const lo = Math.min(...d), hi = Math.max(...d), avg = d.reduce((a, b) => a + b, 0) / d.length;
                        return "min " + Math.round(lo) + "  ·  avg " + Math.round(avg) + "  ·  peak " + Math.round(hi);
                    }

                    ColumnLayout {
                        id: histCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.md }
                        spacing: Tokens.space.sm
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space.xs + 2
                            Repeater {
                                model: 3
                                Chip {
                                    required property int index
                                    palette: pal
                                    interactive: true
                                    selected: root.tab === index
                                    size: 24
                                    icon: root.stats[index].icon
                                    text: root.stats[index].label
                                    tint: pal[root.stats[index].from]
                                    onClicked: root.tab = index
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(hist.stat.value) + "%"
                                color: hist.lineA
                                font.family: Tokens.font.ui
                                font.weight: Font.Bold
                                font.pixelSize: Tokens.size.body
                                font.features: { "tnum": 1 }
                            }
                        }
                        Canvas {
                            id: graph
                            Layout.fillWidth: true
                            implicitHeight: 84
                            readonly property var points: hist.points
                            readonly property color a: hist.lineA
                            readonly property color b: hist.lineB
                            onPointsChanged: requestPaint()
                            onAChanged: requestPaint()
                            onBChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const d = points, n = root.samples;
                                // faint quarter lines, so the height reads as a percentage
                                ctx.strokeStyle = C.alpha(pal.fg, 0.06);
                                ctx.lineWidth = 1;
                                for (const q of [0.25, 0.5, 0.75]) {
                                    ctx.beginPath(); ctx.moveTo(0, Math.round(height * q) + 0.5); ctx.lineTo(width, Math.round(height * q) + 0.5); ctx.stroke();
                                }
                                if (d.length < 2) return;
                                const x = i => width * (i + n - d.length) / (n - 1);
                                const y = v => 2 + (height - 4) * (1 - Math.max(0, Math.min(100, v)) / 100);
                                const along = ctx.createLinearGradient(0, 0, width, 0);
                                along.addColorStop(0, C.alpha(a, 0.9));
                                along.addColorStop(1, b);
                                const fall = ctx.createLinearGradient(0, 0, 0, height);
                                fall.addColorStop(0, C.alpha(C.mix(a, b, 0.5), 0.34));
                                fall.addColorStop(1, C.alpha(C.mix(a, b, 0.5), 0));
                                ctx.beginPath();
                                ctx.moveTo(x(0), height);
                                for (let i = 0; i < d.length; i++) ctx.lineTo(x(i), y(d[i]));
                                ctx.lineTo(x(d.length - 1), height);
                                ctx.closePath();
                                ctx.fillStyle = fall;
                                ctx.fill();
                                ctx.beginPath();
                                for (let i = 0; i < d.length; i++) i ? ctx.lineTo(x(i), y(d[i])) : ctx.moveTo(x(i), y(d[i]));
                                ctx.lineWidth = 2;
                                ctx.lineJoin = "round";
                                ctx.strokeStyle = along;
                                ctx.stroke();
                                // now: a dot at the end of the line
                                ctx.beginPath();
                                ctx.arc(x(d.length - 1), y(d[d.length - 1]), 3, 0, 2 * Math.PI);
                                ctx.fillStyle = b;
                                ctx.fill();
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "last 3 minutes"
                                color: pal.muted
                                font.family: Tokens.font.ui
                                font.pixelSize: Tokens.size.caption
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: hist.stat3()
                                color: pal.muted
                                font.family: Tokens.font.ui
                                font.pixelSize: Tokens.size.caption
                                font.features: { "tnum": 1 }
                            }
                        }

                        // what uses the most of it now
                        SectionHeader {
                            Layout.topMargin: Tokens.space.xs
                            palette: pal
                            text: root.tab === 1 ? "Most memory" : root.tab === 2 ? "Most GPU" : "Most CPU"
                        }
                        Repeater {
                            model: 3
                            RowLayout {
                                id: proc
                                required property int index
                                readonly property var item: root.topProcs[index] ?? null
                                Layout.fillWidth: true
                                spacing: Tokens.space.sm
                                opacity: item ? 1 : 0.35
                                Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                                Text {
                                    Layout.preferredWidth: 150
                                    text: proc.item ? proc.item.name : "–"
                                    elide: Text.ElideRight
                                    color: pal.fg
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.label
                                    font.weight: Font.Medium
                                }
                                Rectangle {     // its share, in the meter's colours
                                    Layout.fillWidth: true
                                    implicitHeight: 4
                                    radius: 2
                                    color: C.alpha(pal.fg, 0.08)
                                    Rectangle {
                                        height: parent.height
                                        radius: 2
                                        readonly property real share: !proc.item ? 0
                                            : root.tab === 1 ? Math.min(1, proc.item.value / Math.max(1, root.num(memTot) / 1073741824))
                                            : Math.min(1, proc.item.value / 100)
                                        width: Math.max(height, parent.width * share)
                                        Behavior on width { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: hist.lineA }
                                            GradientStop { position: 1; color: hist.lineB }
                                        }
                                    }
                                }
                                Text {
                                    Layout.preferredWidth: 64
                                    horizontalAlignment: Text.AlignRight
                                    text: !proc.item ? "" : root.tab === 1 ? proc.item.value.toFixed(1) + " GB" : Math.round(proc.item.value) + "%"
                                    color: pal.fgDim
                                    font.family: Tokens.font.ui
                                    font.pixelSize: Tokens.size.label
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
