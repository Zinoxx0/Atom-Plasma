import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// The Theme page's Lighting tab: the keyboards' RGB, through ~/.config/plasma-rice/rgb.py (asusd for the
// laptop's, hidraw for the Razer; no vendor apps). Each keyboard is Automatic (a style in a screen's
// accents, re-applied on every re-theme) or Manual (an effect and its colours). A card per keyboard
// draws what it shows. Edits are live like the Colours tab: rgb.py set, one run at a time, the latest
// values winning. A keyboard Linux won't let the user reach yet shows the one root command it needs.
Item {
    id: lt
    required property RicePalette pal
    property var screens: []                // the page's screens: [{name, label, lead}]
    property real rail: 76                  // width of the page's label column
    readonly property bool shown: visible

    property var status: null               // rgb.py status
    property string device: ""              // the keyboard being edited
    property var draft: ({})                // {device: {key: value}} shown while on their way
    property var queued: ({})               // {device: {key: value}} not sent yet
    property bool busy: false
    property string error: ""
    property int slot: 0                    // the manual colour being edited (0 or 1)
    property bool copied: false

    readonly property var devices: status ? status.devices : []
    readonly property var dev: devices.find(d => d.id === device) ?? devices[0] ?? null
    readonly property bool anyOn: devices.some(d => d.ready && sv(d, "on"))
    readonly property var styleEffect: ({ solid: "static", gradient: "gradient", breathe: "breathe", starlight: "starlight" })
    // LED-friendly picks for Manual, after the screen's own accents
    readonly property var picks: ["#ff3355", "#ff8a1f", "#ffd21f", "#3dff6e", "#1fffd2", "#2e8bff", "#8a3dff", "#ff3dc8", "#ffffff"]

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function hex(c) { return String(Qt.lighter(c, 1)).slice(0, 7) }
    // a setting as shown: the draft first, then what rgb.py has
    function sv(d, k) {
        const dr = d ? draft[d.id] : null
        return dr && dr[k] !== undefined ? dr[k] : d ? d.settings[k] : undefined
    }
    function screenLabel(name) {
        const s = screens.find(x => x.name === name)
        return s ? s.label : name
    }
    // what a keyboard shows: {effect, colours}, from its draft settings (rgb.py plan(), for the preview)
    function lookOf(d) {
        if (!d || !status) return { effect: "static", colours: ["#808080"] }
        if (sv(d, "mode") === "auto") {
            const st = d.styles.some(x => x.id === sv(d, "style")) ? sv(d, "style") : d.styles[0].id
            const f = sv(d, "follow")
            const p = status.palettes[f === "lead" ? status.lead : f] ?? status.palettes[status.lead] ?? d.colours
            return { effect: styleEffect[st], colours: st === "solid" ? [p[0]] : [p[0], p[p.length - 1]] }
        }
        const e = d.effects.find(x => x.id === sv(d, "effect")) ?? d.effects[0]
        return { effect: e.id, colours: [sv(d, "colour"), sv(d, "colour2")].slice(0, Math.max(1, e.colours)) }
    }
    function summary(d) {
        if (!d.connected) return d.id === "razer" ? "Not connected · its settings wait for it" : d.why
        if (!d.ready) return "Needs a one-time setup"
        if (!sv(d, "on")) return "Off"
        if (sv(d, "mode") === "auto") {
            const st = d.styles.find(x => x.id === sv(d, "style")) ?? d.styles[0]
            const f = sv(d, "follow")
            return "Automatic · " + st.name + " · " + (f === "lead" ? "theme screen" : screenLabel(f))
        }
        return "Manual · " + (d.effects.find(x => x.id === sv(d, "effect")) ?? d.effects[0]).name
    }

    function load() {
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rgb.py" status #lstatus ' + Date.now())
    }
    function edit(k, v, d) {
        const id = (d ?? dev).id
        const dr = Object.assign({}, draft); dr[id] = Object.assign({}, dr[id] ?? {}); dr[id][k] = v; draft = dr
        const qd = Object.assign({}, queued); qd[id] = Object.assign({}, qd[id] ?? {}); qd[id][k] = v; queued = qd
    }
    function send() { sendTimer.restart() }
    Timer { id: sendTimer; interval: 150; onTriggered: lt.flush() }
    function flush() {
        if (busy) return
        const id = Object.keys(queued)[0]
        if (id === undefined) return
        const values = queued[id]
        const qd = Object.assign({}, queued); delete qd[id]; queued = qd
        let a = ""
        for (const k in values) a += " --" + k + " " + q(String(values[k]))
        busy = true; error = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rgb.py" set ' + q(id) + a + ' #lset ' + Date.now())
    }
    function allPower(on) {
        for (const d of devices) if (d.ready) edit("on", on, d)
        send()
    }
    function copy(text) {
        clip.text = text; clip.selectAll(); clip.copy(); clip.text = ""
        copied = true; copiedTimer.restart()
    }
    Timer { id: copiedTimer; interval: 2500; onTriggered: lt.copied = false }
    TextEdit { id: clip; visible: false }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            if (source.indexOf("#lstatus") >= 0) {
                try { lt.status = JSON.parse(out) } catch (e) {}      // keep the last good one
                if (!lt.device && lt.status) {      // start on a keyboard that can be lit
                    const first = lt.status.devices.find(d => d.ready) ?? lt.status.devices[0]
                    if (first) lt.device = first.id
                }
                if (!lt.busy && Object.keys(lt.queued).length === 0) lt.draft = ({})
            } else if (source.indexOf("#lset") >= 0) {
                lt.busy = false
                if ((data["exit code"] ?? 0) !== 0) lt.error = String(data["stderr"] ?? "").trim().split("\n").pop()
                if (Object.keys(lt.queued).length) lt.flush()      // edits made meanwhile
                else lt.load()
            }
            disconnectSource(source)
        }
    }
    onShownChanged: if (shown) load()
    Component.onCompleted: if (shown) load()
    onDeviceChanged: slot = 0
    // waiting for the udev rule: notice it going in
    Timer {
        interval: 3000
        repeat: true
        running: lt.shown && lt.devices.some(d => d.connected && !d.ready && d.setup)
        onTriggered: lt.load()
    }

    component RailLabel: Text {
        Layout.preferredWidth: lt.rail
        Layout.alignment: Qt.AlignVCenter
        color: lt.pal.muted
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Tokens.size.small
    }
    component Value: Text {
        Layout.preferredWidth: 52
        horizontalAlignment: Text.AlignRight
        color: lt.pal.fgDim
        font.family: Tokens.font.mono
        font.pixelSize: Tokens.size.small
    }

    // a keyboard as a grid of keys in the colours it shows; effects that move, move (it's a popup)
    component KeyMap: Item {
        id: km
        property var look: ({ effect: "static", colours: ["#808080"] })
        property bool lit: true
        property real level: 1              // brightness 0..1
        property int rows: 6
        property int cols: 22
        readonly property var cs: look.colours.length ? look.colours : ["#808080"]
        readonly property real gap: Math.max(1, Math.round(width / cols * 0.16))
        readonly property real key: (width - gap * (cols - 1)) / cols
        readonly property bool moving: lit && ["breathe", "pulse", "spectrum", "wave", "starlight", "reactive"].indexOf(look.effect) >= 0
        property real t: 0
        NumberAnimation on t {
            from: 0; to: 1
            loops: Animation.Infinite
            running: km.moving && km.visible && lt.shown
            duration: ({ breathe: 4000, pulse: 2400, spectrum: 9000, wave: 3200, starlight: 5000, reactive: 3000 })[km.look.effect] ?? 4000
        }
        implicitHeight: rows * key + (rows - 1) * gap
        function hash(r, c) { const x = Math.sin(r * 12.9898 + c * 78.233) * 43758.5453; return x - Math.floor(x) }
        function at(r, c) {
            if (!lit) return C.alpha(lt.pal.fg, 0.06)
            const a = cs[0], b = cs[cs.length - 1]
            const wave = 0.5 - 0.5 * Math.cos(t * 2 * Math.PI)
            switch (look.effect) {
            case "gradient": return C.mix(a, b, (c * 0.85 + r * 0.15) / ((cols - 1) * 0.85 + (rows - 1) * 0.15))
            case "breathe": return C.mix(a, b, wave)
            case "pulse": return C.alpha(a, 0.3 + 0.7 * wave)
            case "spectrum": return Qt.hsla(t, 0.85, 0.6, 1)
            case "wave": return Qt.hsla(((c / cols) - t + 1) % 1, 0.85, 0.6, 1)
            case "starlight": {
                const tw = Math.pow(Math.max(0, Math.sin((t + hash(r, c)) * 2 * Math.PI)), 6)
                return C.mix(C.alpha(lt.pal.fg, 0.06), (r + c) % 2 ? b : a, tw)
            }
            case "reactive": {     // a key pressed now and then, fading
                const beat = Math.floor(t * 6), f = t * 6 - beat
                return hash(r + beat, c) > 0.9 ? C.mix(a, C.alpha(a, 0.12), f) : C.alpha(a, 0.12)
            }
            default: return a
            }
        }
        Column {
            spacing: km.gap
            opacity: km.lit ? 0.35 + 0.65 * km.level : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
            Repeater {
                model: km.rows
                Row {
                    id: kr
                    required property int index
                    spacing: km.gap
                    Repeater {
                        model: km.cols
                        Rectangle {
                            required property int index
                            width: km.key; height: km.key
                            radius: Math.max(1, km.key * 0.22)
                            color: km.at(kr.index, index)
                        }
                    }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: body.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: flick.width
            spacing: Tokens.space.sm + 2

            // ---- the keyboards: pick one; each draws what it shows
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                RailLabel { text: "Keyboards"; Layout.alignment: Qt.AlignTop; Layout.topMargin: Tokens.space.sm }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    Repeater {
                        model: lt.devices
                        Rectangle {
                            id: card
                            required property var modelData
                            readonly property var look: lt.lookOf(modelData)
                            readonly property color c: look.colours[0] ?? lt.pal.primary
                            readonly property bool selected: lt.dev && lt.dev.id === modelData.id
                            readonly property bool hot: cardMouse.containsMouse
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: cardCol.implicitHeight + 2 * Tokens.space.sm
                            radius: Tokens.radius.md
                            color: selected ? C.alpha(c, 0.12) : C.alpha(lt.pal.fg, hot ? 0.07 : 0.04)
                            border.width: selected ? 1.5 : 1
                            border.color: selected ? C.alpha(c, 0.8) : C.alpha(lt.pal.edge, Tokens.alpha.outline)
                            opacity: modelData.connected ? 1 : 0.6
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            ColumnLayout {
                                id: cardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.sm }
                                spacing: Tokens.space.sm
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space.sm
                                    Text {
                                        text: card.modelData.id === "laptop" ? "laptop_chromebook" : "keyboard"
                                        color: card.selected ? lt.pal.fg : lt.pal.fgDim
                                        font.family: Tokens.font.icons
                                        font.pixelSize: 20
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.modelData.name
                                            elide: Text.ElideRight
                                            color: card.selected ? lt.pal.fg : lt.pal.fgDim
                                            font.family: Tokens.font.ui
                                            font.weight: Font.DemiBold
                                            font.pixelSize: Tokens.size.label
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: lt.summary(card.modelData)
                                            elide: Text.ElideRight
                                            color: card.modelData.connected && !card.modelData.ready ? lt.pal.warn : lt.pal.muted
                                            font.family: Tokens.font.ui
                                            font.pixelSize: Tokens.size.caption
                                        }
                                    }
                                }
                                KeyMap {
                                    Layout.fillWidth: true
                                    look: card.look
                                    lit: card.modelData.ready && !!lt.sv(card.modelData, "on") && lt.sv(card.modelData, "brightness") > 0
                                    level: lt.sv(card.modelData, "brightness") / 100
                                    cols: card.modelData.id === "laptop" ? 18 : 22
                                }
                            }
                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: lt.device = card.modelData.id
                            }
                        }
                    }
                }
            }

            // ---- a keyboard Linux won't hand over yet: the one root step, to copy into Konsole
            RowLayout {
                Layout.fillWidth: true
                visible: lt.dev !== null && lt.dev.connected && !lt.dev.ready && !!lt.dev.setup
                spacing: 0
                RailLabel { text: "Setup"; Layout.alignment: Qt.AlignTop; Layout.topMargin: Tokens.space.sm }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: setupCol.implicitHeight + 2 * Tokens.space.md
                    radius: Tokens.radius.md
                    color: C.alpha(lt.pal.fg, 0.04)
                    border.width: 1
                    border.color: C.alpha(lt.pal.warn, 0.45)
                    ColumnLayout {
                        id: setupCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.md }
                        spacing: Tokens.space.sm
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Only root can talk to the keyboard until a udev rule hands it to you. Run this once in Konsole (sudo asks for your password); this page notices when it's done."
                            color: lt.pal.fgDim
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.small
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: cmdText.implicitHeight + 2 * Tokens.space.sm
                            radius: Tokens.radius.sm
                            color: C.alpha(lt.pal.surfaceLowest, 0.7)
                            Text {
                                id: cmdText
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.sm }
                                text: lt.dev ? lt.dev.setup ?? "" : ""
                                wrapMode: Text.Wrap
                                color: lt.pal.fg
                                font.family: Tokens.font.mono
                                font.pixelSize: Tokens.size.caption
                            }
                        }
                        RowLayout {
                            spacing: Tokens.space.sm
                            Pill {
                                palette: lt.pal
                                size: 28
                                icon: lt.copied ? "check" : "content_copy"
                                text: lt.copied ? "Copied" : "Copy command"
                                accent: lt.pal.primary
                                onAccent: lt.pal.onPrimary
                                onClicked: lt.copy(lt.dev.setup)
                            }
                            IconButton { palette: lt.pal; size: 28; icon: "refresh"; tooltip: "Check again"; onClicked: lt.load() }
                        }
                    }
                }
            }

            // ---- the chosen keyboard's settings
            ColumnLayout {
                Layout.fillWidth: true
                visible: lt.dev !== null && (lt.dev.ready || (lt.dev.id === "razer" && !lt.dev.connected))
                spacing: Tokens.space.sm + 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    RailLabel { text: "Mode" }
                    Row {
                        spacing: Tokens.space.xs + 2
                        Repeater {
                            model: [{ id: "auto", text: "Automatic", icon: "auto_awesome", tip: "In a screen's accents, re-applied whenever the theme changes" },
                                    { id: "manual", text: "Manual", icon: "tune", tip: "An effect and colours of your own" }]
                            Chip {
                                required property var modelData
                                palette: lt.pal
                                interactive: true
                                size: 26
                                icon: modelData.icon
                                text: modelData.text
                                tooltip: modelData.tip
                                selected: lt.sv(lt.dev, "mode") === modelData.id
                                tint: lt.pal.primary
                                onClicked: if (!selected) { lt.edit("mode", modelData.id); lt.send() }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Chip {
                        readonly property bool on: !!lt.sv(lt.dev, "on")
                        palette: lt.pal
                        interactive: true
                        size: 26
                        icon: "power_settings_new"
                        text: on ? "On" : "Off"
                        selected: on
                        tint: on ? lt.pal.primary : lt.pal.fgDim
                        tooltip: on ? "Turn this keyboard's lights off" : "Turn them back on"
                        onClicked: { lt.edit("on", !on); lt.send() }
                    }
                }

                // Automatic: a style, in which screen's accents
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "auto"
                    spacing: 0
                    RailLabel { text: "Style" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space.xs + 2
                        Repeater {
                            model: lt.dev ? lt.dev.styles : []
                            Chip {
                                required property var modelData
                                palette: lt.pal
                                interactive: true
                                size: 26
                                text: modelData.name
                                tooltip: ({ solid: "The primary accent on every key", gradient: "Primary to tertiary across the keys, like the bar's outline",
                                            breathe: "Breathing between primary and tertiary", starlight: "Keys twinkling in primary and tertiary" })[modelData.id]
                                selected: lt.sv(lt.dev, "style") === modelData.id
                                tint: lt.pal.primary
                                onClicked: if (!selected) { lt.edit("style", modelData.id); lt.send() }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "auto"
                    spacing: 0
                    RailLabel { text: "Follows" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space.xs + 2
                        Repeater {
                            model: [{ name: "lead", label: "Theme screen" }].concat(lt.screens.map(s => ({ name: s.name, label: s.label })))
                            Chip {
                                required property var modelData
                                palette: lt.pal
                                interactive: true
                                size: 26
                                icon: modelData.name === "lead" ? "star" : ""
                                text: modelData.label
                                tooltip: modelData.name === "lead" ? "Whichever screen drives apps and terminals (now " + lt.screenLabel(lt.status ? lt.status.lead : "") + ")"
                                                                   : "This screen's accents"
                                selected: lt.sv(lt.dev, "follow") === modelData.name
                                tint: lt.pal.secondary
                                onClicked: if (!selected) { lt.edit("follow", modelData.name); lt.send() }
                            }
                        }
                    }
                }

                // Manual: an effect, and the colours it takes
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "manual"
                    spacing: 0
                    RailLabel { text: "Effect" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space.xs + 2
                        Repeater {
                            model: lt.dev ? lt.dev.effects : []
                            Chip {
                                required property var modelData
                                palette: lt.pal
                                interactive: true
                                size: 26
                                text: modelData.name
                                selected: lt.sv(lt.dev, "effect") === modelData.id
                                tint: lt.pal.primary
                                onClicked: if (!selected) { lt.edit("effect", modelData.id); lt.send() }
                            }
                        }
                    }
                }
                Item {      // the manual colours: which one is edited, then quick picks
                    id: manual
                    readonly property var eff: lt.dev ? lt.dev.effects.find(x => x.id === lt.sv(lt.dev, "effect")) ?? lt.dev.effects[0] : null
                    readonly property int n: eff ? eff.colours : 0
                    readonly property string key: lt.slot > 0 && n > 1 ? "colour2" : "colour"
                    readonly property color cur: lt.sv(lt.dev, key) ?? "#ffffff"
                    property real hueMemo: 0
                    readonly property real hh: cur.hslHue >= 0 ? cur.hslHue : hueMemo
                    onCurChanged: if (cur.hslHue >= 0) hueMemo = cur.hslHue
                    function set(c) { lt.edit(key, lt.hex(c)) }
                    // an LED colour is a hue and how far it is from white: saturation s sits at lightness 1 - s/2
                    function hs(h, s) { set(Qt.hsla(h, s, 1 - s / 2, 1)) }
                    visible: false
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "manual" && manual.n > 0
                    spacing: 0
                    RailLabel { text: manual.n > 1 ? "Colours" : "Colour" }
                    Row {
                        spacing: Tokens.space.xs + 2
                        Repeater {
                            model: manual.n
                            Rectangle {
                                id: slotDot
                                required property int index
                                readonly property bool on: lt.slot === index || manual.n === 1
                                width: 26; height: 26; radius: 13
                                color: lt.sv(lt.dev, index ? "colour2" : "colour") ?? "#ffffff"
                                border.width: on ? 2 : 1
                                border.color: on ? lt.pal.fg : C.alpha(lt.pal.edge, 0.2)
                                Text {
                                    anchors.centerIn: parent
                                    text: slotDot.index + 1
                                    visible: manual.n > 1
                                    color: slotDot.color.hslLightness > 0.6 ? "#14151b" : "#ffffff"
                                    font.family: Tokens.font.ui
                                    font.weight: Font.Bold
                                    font.pixelSize: Tokens.size.caption
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: lt.slot = slotDot.index
                                }
                            }
                        }
                        Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: C.alpha(lt.pal.edge, 0.14) }
                        Repeater {
                            model: [String(lt.pal.primary), String(lt.pal.secondary), String(lt.pal.tertiary)].concat(lt.picks)
                            Rectangle {
                                id: pick
                                required property string modelData
                                required property int index
                                readonly property bool on: lt.hex(manual.cur) === lt.hex(modelData)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 10
                                color: modelData
                                border.width: on ? 2 : 1
                                border.color: on ? lt.pal.fg : C.alpha(lt.pal.edge, 0.2)
                                scale: pickMouse.containsMouse ? 1.15 : 1
                                Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                                PlasmaCore.ToolTipArea {
                                    anchors.fill: parent
                                    mainText: pick.index < 3 ? ["Primary", "Secondary", "Tertiary"][pick.index] + " accent" : lt.hex(pick.modelData)
                                    MouseArea {
                                        id: pickMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { manual.set(pick.modelData); lt.send() }
                                    }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "manual" && manual.n > 0
                    spacing: 0
                    RailLabel { text: "Hue" }
                    ColourSlider {
                        Layout.fillWidth: true
                        palette: lt.pal
                        channel: "h"; h: manual.hh; s: manual.cur.hslSaturation; l: 0.55
                        value: manual.hh
                        onMoved: v => manual.hs(v, manual.cur.hslSaturation < 0.05 ? 1 : manual.cur.hslSaturation)
                        onReleased: lt.send()
                    }
                    Value { text: Math.round(manual.hh * 360) + "°" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: lt.sv(lt.dev, "mode") === "manual" && manual.n > 0
                    spacing: 0
                    RailLabel { text: "Saturation" }
                    ColourSlider {
                        Layout.fillWidth: true
                        palette: lt.pal
                        channel: "x"
                        from: "#ffffff"
                        to: Qt.hsla(manual.hh, 1, 0.5, 1)
                        value: manual.cur.hslSaturation
                        onMoved: v => manual.hs(manual.hh, v)
                        onReleased: lt.send()
                    }
                    Value { text: Math.round(manual.cur.hslSaturation * 100) + "%" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    RailLabel { text: "Brightness" }
                    ColourSlider {
                        Layout.fillWidth: true
                        palette: lt.pal
                        channel: "x"
                        from: C.alpha(lt.pal.fg, 0.08)
                        to: lt.lookOf(lt.dev).colours[0] ?? lt.pal.primary
                        value: (lt.sv(lt.dev, "brightness") ?? 0) / 100
                        onMoved: v => lt.edit("brightness", Math.round(v * 100))
                        onReleased: lt.send()
                    }
                    Value {
                        readonly property int b: lt.sv(lt.dev, "brightness") ?? 0
                        // asusd has four steps; the Razer takes any level
                        text: lt.dev && lt.dev.id === "laptop" ? ["Off", "Low", "Med", "High"][b <= 0 ? 0 : Math.min(3, 1 + Math.floor((b - 1) * 3 / 100))]
                                                              : b + "%"
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: lt.rail
                visible: lt.error !== ""
                text: "Couldn't light it: " + lt.error
                wrapMode: Text.WordWrap
                color: lt.pal.bad
                font.family: Tokens.font.ui
                font.pixelSize: Tokens.size.small
            }
        }
    }
}
