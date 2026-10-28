import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// The Theme page's Colours tab: what rice.py made of a screen's wallpaper (its mood and three
// accents) and hand-picked replacements, to mismatch on purpose. Edits are live, like picking a
// wallpaper: a click, a slider let go or a typed hex re-themes the target right away (rice.py theme
// set, one run at a time, the latest values winning); undo() steps back, automatic() returns to
// the wallpaper's own colours. They last until a new wallpaper is picked there, unless saved in a
// theme (Save look). Rows hang off the page's label rail (`rail`).
Item {
    id: ct
    required property RicePalette pal
    property string screen: ""              // the screen whose colours are shown
    property string target: "all"           // where edits go: an output or "all"
    property real rail: 76                  // width of the page's label column
    readonly property bool shown: visible
    signal changed()                        // a run finished: the page refreshes its screens and themes

    property var theme: null                // rice.py theme show
    property var draft: ({})                // values shown while they're on their way
    property var queued: ({})               // values not sent yet
    property var history: []                // earlier hand-picked states of this screen, for undo
    property bool busy: false
    property string error: ""
    property string role: "primary"         // the accent being edited

    readonly property var roles: ["primary", "secondary", "tertiary"]
    readonly property var names: ({ primary: "Primary", secondary: "Secondary", tertiary: "Tertiary" })
    // a mood's name as shown (the moods themselves come from rice.py: theme.moods)
    function moodName(m) { return m ? m[0].toUpperCase() + m.slice(1) : "" }
    readonly property var keys: ["mood", "primary", "secondary", "tertiary", "intensity"]
    readonly property var saved: theme ? theme.overrides : ({})
    function val(k) { return draft[k] !== undefined ? draft[k] : saved[k] }
    function accent(r) {
        const d = draft[r]
        return d === "auto" && theme ? theme.auto[r] : d ? d : theme ? theme.current[r] : pal.col(r)
    }
    function isCustom(r) { const v = val(r); return v !== undefined && v !== "" && v !== "auto" }
    readonly property string mood: { const m = val("mood"); return m && m !== "auto" ? m : "auto" }
    readonly property real intensity: { const v = val("intensity"); return v !== undefined && v !== "auto" ? Number(v) : 1 }
    readonly property bool custom: Object.keys(saved).length > 0 || Object.keys(draft).some(k => draft[k] !== "auto")
    readonly property bool canUndo: history.length > 0 && !busy

    function rice(args) { return ["python3", sh.home + "/.config/plasma-rice/rice.py"].concat(args) }
    function hex(c) { return String(Qt.lighter(c, 1)).slice(0, 7) }
    function load() {
        if (!busy) error = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" theme show --screen ' + sh.q(screen || "focused") + ' #tshow')
    }
    // show it now; send() (or a drag let go) sends it
    function edit(k, v) {
        const d = Object.assign({}, draft); d[k] = v; draft = d
        const qd = Object.assign({}, queued); qd[k] = v; queued = qd
    }
    function send() { sendTimer.restart() }
    Timer { id: sendTimer; interval: 150; onTriggered: ct.flush() }
    function flush() {
        if (busy || Object.keys(queued).length === 0) return
        history = history.concat([Object.assign({}, saved)]).slice(-20)
        run(queued)
    }
    function run(values) {
        const a = []
        for (const k of keys) if (values[k] !== undefined) a.push("--" + k, String(values[k]))
        queued = ({}); busy = true; error = ""
        sh.exec("tset", rice(["theme", "set", "--screen", target].concat(a)))      // (changing arguments: RiceShell.exec)
    }
    function undo() {
        if (!canUndo) return
        const prev = history[history.length - 1]
        history = history.slice(0, -1)
        const v = {}
        for (const k of keys) v[k] = prev[k] !== undefined ? prev[k] : "auto"
        draft = Object.assign({}, v); run(v)
    }
    function automatic() {
        if (busy || !custom) return
        history = history.concat([Object.assign({}, saved)]).slice(-20)
        draft = ({}); queued = ({}); busy = true; error = ""
        sh.exec("tset", rice(["theme", "reset", "--screen", target]))
    }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            if (source.indexOf("#tshow") >= 0) {
                try { ct.theme = JSON.parse(out) } catch (e) {}      // keep the last good one
                if (!ct.busy && Object.keys(ct.queued).length === 0) ct.draft = ({})
            } else if (source.indexOf("#tset") >= 0) {
                ct.busy = false
                if ((data["exit code"] ?? 0) !== 0) ct.error = String(data["stderr"] ?? "").trim().split("\n").pop()
                if (Object.keys(ct.queued).length) ct.run(ct.queued)    // edits made meanwhile
                else { ct.load(); ct.changed() }
            }
            disconnectSource(source)
        }
    }
    onShownChanged: if (shown) load()
    Component.onCompleted: if (shown) load()
    onScreenChanged: { draft = ({}); queued = ({}); history = []; if (shown) load() }

    // the colour being edited, as HSL; the hue is remembered while the colour is grey
    readonly property color cur: accent(role)
    property real hueMemo: 0
    readonly property real hh: cur.hslHue >= 0 ? cur.hslHue : hueMemo
    onCurChanged: if (cur.hslHue >= 0) hueMemo = cur.hslHue
    function setHsl(h, s, l) { edit(role, hex(Qt.hsla(h, s, l, 1))) }

    component RailLabel: Text {
        Layout.preferredWidth: ct.rail
        Layout.alignment: Qt.AlignVCenter
        color: ct.pal.muted
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Tokens.size.small
    }
    component Value: Text {
        Layout.preferredWidth: 44
        horizontalAlignment: Text.AlignRight
        color: ct.pal.fgDim
        font.family: Tokens.font.mono
        font.pixelSize: Tokens.size.small
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.space.md

        // ---- the look as a whole: mood and intensity
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            RailLabel { text: "Mood" }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space.xs + 2
                Repeater {
                    model: ["auto"].concat(ct.theme ? ct.theme.moods : [])
                    Chip {
                        required property string modelData
                        palette: ct.pal
                        interactive: true
                        size: 26
                        selected: ct.mood === modelData
                        tint: ct.pal.primary
                        text: modelData === "auto" ? "Auto · " + (ct.theme ? ct.moodName(ct.theme.detected) : "…")
                                                   : ct.moodName(modelData)
                        tooltip: ({ auto: "What the wallpaper reads as", neon: "Vivid accents at the edge of the gamut",
                                    soft: "Calm, pastel accents", light: "Light frosted desktop, silver accents",
                                    void: "True black, cold starlight", graphite: "Neutral greys, silver accents" })[modelData]
                        onClicked: if (ct.mood !== modelData) { ct.edit("mood", modelData); ct.send() }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            RailLabel { text: "Intensity" }
            ColourSlider {
                Layout.fillWidth: true
                palette: ct.pal
                channel: "x"
                from: Qt.hsla(ct.hh, 0.08, 0.5, 1)
                to: ct.accent("primary")
                value: (ct.intensity - 0.3) / 1.2
                onMoved: v => ct.edit("intensity", Math.round((0.3 + v * 1.2) * 100) / 100)
                onReleased: ct.send()
            }
            Value { text: Math.round(ct.intensity * 100) + "%" }
        }

        // ---- the three accents: pick one, edit it in the card under them
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            RailLabel { text: "Accents" }
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space.sm
                Repeater {
                    model: ct.roles
                    Rectangle {
                        id: acc
                        required property string modelData
                        readonly property color c: ct.accent(modelData)
                        readonly property bool selected: ct.role === modelData
                        readonly property bool hot: accMouse.containsMouse
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Tokens.radius.md
                        color: selected ? C.alpha(c, 0.16) : C.alpha(ct.pal.fg, hot ? 0.07 : 0.04)
                        border.width: selected ? 1.5 : 1
                        border.color: selected ? c : C.alpha(ct.pal.edge, Tokens.alpha.outline)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.space.sm }
                            spacing: Tokens.space.sm
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: acc.c
                                border.width: ct.isCustom(acc.modelData) ? 2 : 0
                                border.color: ct.pal.fg
                                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: ct.names[acc.modelData]
                                    color: acc.selected ? ct.pal.fg : ct.pal.fgDim
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Tokens.size.label
                                }
                                Text {
                                    text: ct.hex(acc.c)
                                    color: ct.pal.muted
                                    font.family: Tokens.font.mono
                                    font.pixelSize: Tokens.size.caption
                                }
                            }
                        }
                        MouseArea {
                            id: accMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ct.role = acc.modelData
                        }
                    }
                }
            }
        }

        // ---- the editor for the chosen accent
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: ct.rail
            implicitHeight: editor.implicitHeight + 2 * Tokens.space.md
            radius: Tokens.radius.md
            color: C.alpha(ct.pal.fg, 0.04)
            border.width: 1
            border.color: C.alpha(ct.cur, 0.45)
            Rectangle {     // the accent's own wash at the top
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0; color: C.alpha(ct.cur, 0.14) }
                    GradientStop { position: 0.6; color: "transparent" }
                }
            }
            GridLayout {
                id: editor
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.md }
                columns: 3
                columnSpacing: Tokens.space.md
                rowSpacing: Tokens.space.sm

                // which accent, where it comes from, and its hex (type one in)
                Text {
                    text: ct.names[ct.role]
                    color: ct.pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.Bold
                    font.pixelSize: Tokens.size.title
                }
                Text {
                    Layout.fillWidth: true
                    text: ct.isCustom(ct.role) ? "Hand-picked" : "From the wallpaper"
                    color: ct.pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: Tokens.size.small
                }
                Rectangle {
                    Layout.preferredWidth: 84
                    implicitHeight: 26
                    radius: height / 2
                    color: C.alpha(ct.pal.fg, hexIn.activeFocus ? 0.09 : 0.05)
                    border.width: 1
                    border.color: hexIn.activeFocus ? ct.cur : C.alpha(ct.pal.edge, Tokens.alpha.outline)
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
                        spacing: 6
                        Rectangle { width: 14; height: 14; radius: 7; color: ct.cur; anchors.verticalCenter: parent.verticalCenter }
                        TextInput {
                            id: hexIn
                            width: 56
                            anchors.verticalCenter: parent.verticalCenter
                            text: ct.hex(ct.cur)
                            color: ct.pal.fg
                            selectionColor: ct.pal.primary
                            selectedTextColor: ct.pal.onPrimary
                            font.family: Tokens.font.mono
                            font.pixelSize: Tokens.size.small
                            maximumLength: 7
                            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                            onAccepted: {
                                const t = text.replace("#", "")
                                if (t.length === 6) { ct.edit(ct.role, "#" + t.toLowerCase()); ct.send() }
                                text = Qt.binding(() => ct.hex(ct.cur))
                            }
                            onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => ct.hex(ct.cur))
                        }
                    }
                }

                Text { text: "Wallpaper"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                Row {
                    Layout.columnSpan: 2
                    spacing: Tokens.space.xs + 2
                    Repeater {
                        // first: back to what rice.py picks for this accent; then the wallpaper's own colours
                        model: ct.theme ? ["auto"].concat(ct.theme.swatches) : []
                        Rectangle {
                            id: sw
                            required property string modelData
                            readonly property bool isAuto: modelData === "auto"
                            readonly property color c: isAuto ? (ct.theme ? ct.theme.auto[ct.role] : "#808080") : modelData
                            readonly property bool on: isAuto ? !ct.isCustom(ct.role) : ct.isCustom(ct.role) && ct.hex(ct.cur) === modelData.toLowerCase()
                            width: 24; height: 24; radius: 12
                            color: c
                            border.width: on ? 2 : 1
                            border.color: on ? ct.pal.fg : C.alpha(ct.pal.edge, 0.2)
                            scale: swMouse.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                            Text {
                                anchors.centerIn: parent
                                visible: sw.isAuto
                                text: "auto_awesome"
                                color: sw.c.hslLightness > 0.6 ? "#14151b" : "#ffffff"
                                font.family: Tokens.font.icons
                                font.pixelSize: 13
                            }
                            PlasmaCore.ToolTipArea {
                                anchors.fill: parent
                                mainText: sw.isAuto ? "Automatic" : "From the wallpaper"
                                subText: sw.isAuto ? "What the wallpaper gives this accent: " + ct.hex(sw.c) : sw.modelData
                                MouseArea {
                                    id: swMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { ct.edit(ct.role, sw.isAuto ? "auto" : sw.modelData); ct.send() }
                                }
                            }
                        }
                    }
                }

                Text { text: "Hue"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                ColourSlider {
                    Layout.fillWidth: true
                    palette: ct.pal
                    channel: "h"; h: ct.hh; s: ct.cur.hslSaturation; l: ct.cur.hslLightness
                    value: ct.hh
                    onMoved: v => ct.setHsl(v, Math.max(ct.cur.hslSaturation, 0.05), ct.cur.hslLightness)
                    onReleased: ct.send()
                }
                Value { text: Math.round(ct.hh * 360) + "°" }

                Text { text: "Saturation"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                ColourSlider {
                    Layout.fillWidth: true
                    palette: ct.pal
                    channel: "s"; h: ct.hh; s: ct.cur.hslSaturation; l: ct.cur.hslLightness
                    value: ct.cur.hslSaturation
                    onMoved: v => ct.setHsl(ct.hh, v, ct.cur.hslLightness)
                    onReleased: ct.send()
                }
                Value { text: Math.round(ct.cur.hslSaturation * 100) + "%" }

                Text { text: "Lightness"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                ColourSlider {
                    Layout.fillWidth: true
                    palette: ct.pal
                    channel: "l"; h: ct.hh; s: ct.cur.hslSaturation; l: ct.cur.hslLightness
                    value: ct.cur.hslLightness
                    onMoved: v => ct.setHsl(ct.hh, ct.cur.hslSaturation, v)
                    onReleased: ct.send()
                }
                Value { text: Math.round(ct.cur.hslLightness * 100) + "%" }
            }
        }

        Item { Layout.fillHeight: true }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: ct.rail
            visible: ct.error !== ""
            text: "Couldn't apply: " + ct.error
            elide: Text.ElideRight
            color: ct.pal.bad
            font.family: Tokens.font.ui
            font.pixelSize: Tokens.size.small
        }
    }
}
