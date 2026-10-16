import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import "Rice"
import "Rice/Color.js" as C

// The Theme page's Colours tab: what rice.py made of a screen's wallpaper (its mood and three
// accents) and hand-picked replacements, to mismatch on purpose. Edits preview here; Apply re-themes
// live (rice.py theme set), Back to automatic drops them (theme reset). They last until a new
// wallpaper is picked on that screen, unless kept in a theme (the bookmark button above).
Item {
    id: ct
    required property RicePalette pal
    property string screen: ""              // the screen whose colours are shown
    property string target: "all"           // what Apply / Back to automatic touch: an output or "all"
    readonly property bool shown: visible

    property var theme: null                // rice.py theme show
    property var edits: ({})                // pending: {mood, primary, secondary, tertiary, intensity}
    property string role: "primary"         // the accent being edited
    property bool busy: false
    property string status: ""

    readonly property var roles: ["primary", "secondary", "tertiary"]
    readonly property var names: ({ primary: "Primary", secondary: "Secondary", tertiary: "Tertiary" })
    readonly property var moodNames: ({ neon: "Neon", soft: "Soft", light: "Light", void: "Void", graphite: "Graphite" })
    readonly property var saved: theme ? theme.overrides : ({})
    function val(k) { return edits[k] !== undefined ? edits[k] : saved[k] }
    function accent(r) {
        const e = edits[r]
        return e === "auto" && theme ? theme.auto[r] : e ? e : theme ? theme.current[r] : pal.col(r)
    }
    function isCustom(r) { const v = val(r); return v !== undefined && v !== "" && v !== "auto" }
    readonly property string mood: { const m = val("mood"); return m && m !== "auto" ? m : "auto" }
    readonly property real intensity: val("intensity") !== undefined ? Number(val("intensity")) : 1
    readonly property bool dirty: Object.keys(edits).length > 0
    readonly property bool custom: Object.keys(saved).length > 0

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function set(k, v) { const e = Object.assign({}, edits); e[k] = v; edits = e }
    function hex(c) { return String(Qt.lighter(c, 1)).slice(0, 7) }
    function load() {
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" theme show --screen ' + q(screen || "focused") + ' #tshow ' + Date.now())
    }
    function apply() {
        if (!dirty || busy) return
        let a = ""
        for (const k of ["mood", "primary", "secondary", "tertiary", "intensity"])
            if (edits[k] !== undefined) a += " --" + k + " " + q(String(edits[k]))
        busy = true; status = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" theme set --screen ' + q(target) + a + ' #tset ' + Date.now())
    }
    function reset() {
        if (busy) return
        if (dirty) { edits = ({}); return }     // first, just the pending edits
        busy = true; status = ""
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" theme reset --screen ' + q(target) + ' #tset ' + Date.now())
    }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const out = data["stdout"] ?? ""
            if (source.indexOf("#tshow") >= 0) {
                try { ct.theme = JSON.parse(out) } catch (e) { ct.theme = null }
            } else if (source.indexOf("#tset") >= 0) {
                ct.busy = false
                ct.edits = ({})
                ct.status = (data["exit code"] ?? 0) === 0 ? "" : "rice.py: " + String(data["stderr"] ?? "").trim().split("\n").pop()
                ct.load()
            }
            disconnectSource(source)
        }
    }
    onShownChanged: if (shown) load()
    Component.onCompleted: if (shown) load()
    onScreenChanged: { edits = ({}); if (shown) load() }

    // the colour being edited, as HSL; the hue is remembered while the colour is grey
    readonly property color cur: accent(role)
    property real hueMemo: 0
    readonly property real hh: cur.hslHue >= 0 ? cur.hslHue : hueMemo
    onCurChanged: if (cur.hslHue >= 0) hueMemo = cur.hslHue
    function setHsl(h, s, l) { set(role, hex(Qt.hsla(h, s, l, 1))) }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.space.md

        // mood: the wallpaper's character as read, or forced
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.xs + 2
            Text {
                text: "Mood"
                color: ct.pal.muted
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: Tokens.size.label
                Layout.rightMargin: Tokens.space.xs
            }
            Repeater {
                model: ["auto"].concat(ct.theme ? ct.theme.moods : [])
                Chip {
                    required property string modelData
                    palette: ct.pal
                    interactive: true
                    size: 26
                    selected: ct.mood === modelData
                    tint: ct.pal.primary
                    text: modelData === "auto" ? "Auto · " + (ct.theme ? ct.moodNames[ct.theme.detected] ?? ct.theme.detected : "…")
                                               : ct.moodNames[modelData]
                    tooltip: ({ auto: "What the wallpaper reads as", neon: "Vivid accents at the edge of the gamut",
                                soft: "Calm, pastel accents", light: "Light frosted desktop, silver accents",
                                void: "True black, cold starlight", graphite: "Neutral greys, silver accents" })[modelData]
                    onClicked: ct.set("mood", modelData)
                }
            }
            Item { Layout.fillWidth: true }
        }

        // the three accents: click one to edit it
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            Repeater {
                model: ct.roles
                Rectangle {
                    id: card
                    required property string modelData
                    readonly property color c: ct.accent(modelData)
                    readonly property bool selected: ct.role === modelData
                    readonly property bool onLight: c.hslLightness > 0.6
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: Tokens.radius.md
                    color: c
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    border.width: selected ? 2 : 1
                    border.color: selected ? ct.pal.fg : C.alpha(ct.pal.edge, 0.16)
                    Rectangle {     // a soft sheen, like glass
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.22) }
                            GradientStop { position: 0.55; color: "transparent" }
                        }
                    }
                    Column {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.space.md }
                        spacing: 1
                        Text {
                            text: ct.names[card.modelData]
                            color: card.onLight ? "#14151b" : "#ffffff"
                            font.family: Tokens.font.ui
                            font.weight: Font.Bold
                            font.pixelSize: Tokens.size.label
                        }
                        Text {
                            text: ct.hex(card.c) + (ct.isCustom(card.modelData) ? "  ·  custom" : "")
                            color: card.onLight ? Qt.rgba(0.08, 0.08, 0.1, 0.7) : Qt.rgba(1, 1, 1, 0.75)
                            font.family: Tokens.font.mono
                            font.pixelSize: Tokens.size.small
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ct.role = card.modelData
                    }
                }
            }
        }

        // the editor for the chosen accent: the wallpaper's own colours, then hue/saturation/lightness and hex
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Tokens.space.md
            rowSpacing: Tokens.space.xs + 2

            Text { text: "Wallpaper"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
            Row {
                Layout.columnSpan: 2
                spacing: Tokens.space.xs + 2
                Repeater {
                    model: ct.theme ? [ct.theme.auto[ct.role]].concat(ct.theme.swatches) : []
                    Rectangle {
                        id: sw
                        required property string modelData
                        required property int index
                        width: 26; height: 26; radius: 13
                        color: modelData
                        border.width: ct.hex(ct.cur) === modelData.toLowerCase() ? 2 : 1
                        border.color: ct.hex(ct.cur) === modelData.toLowerCase() ? ct.pal.fg : C.alpha(ct.pal.edge, 0.2)
                        scale: swMouse.containsMouse ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                        Text {      // the first one is what rice.py picked for this accent
                            anchors.centerIn: parent
                            visible: sw.index === 0
                            text: "auto_awesome"
                            color: C.rgb(sw.modelData).hslLightness > 0.6 ? "#14151b" : "#ffffff"
                            font.family: Tokens.font.icons
                            font.pixelSize: 14
                        }
                        PlasmaCore.ToolTipArea {
                            anchors.fill: parent
                            mainText: sw.index === 0 ? "Automatic" : "From the wallpaper"
                            subText: sw.modelData
                            MouseArea {
                                id: swMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ct.set(ct.role, sw.index === 0 ? "auto" : sw.modelData)
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
            }
            Text { text: Math.round(ct.hh * 360) + "°"; color: ct.pal.fgDim; font.family: Tokens.font.mono; font.pixelSize: Tokens.size.small; Layout.preferredWidth: 72 }

            Text { text: "Saturation"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
            ColourSlider {
                Layout.fillWidth: true
                palette: ct.pal
                channel: "s"; h: ct.hh; s: ct.cur.hslSaturation; l: ct.cur.hslLightness
                value: ct.cur.hslSaturation
                onMoved: v => ct.setHsl(ct.hh, v, ct.cur.hslLightness)
            }
            Text { text: Math.round(ct.cur.hslSaturation * 100) + "%"; color: ct.pal.fgDim; font.family: Tokens.font.mono; font.pixelSize: Tokens.size.small }

            Text { text: "Lightness"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
            ColourSlider {
                Layout.fillWidth: true
                palette: ct.pal
                channel: "l"; h: ct.hh; s: ct.cur.hslSaturation; l: ct.cur.hslLightness
                value: ct.cur.hslLightness
                onMoved: v => ct.setHsl(ct.hh, ct.cur.hslSaturation, v)
            }
            // hex, typed
            Rectangle {
                Layout.preferredWidth: 72
                implicitHeight: 24
                radius: height / 2
                color: C.alpha(ct.pal.fg, hexIn.activeFocus ? 0.09 : 0.05)
                border.width: 1
                border.color: hexIn.activeFocus ? ct.pal.primary : C.alpha(ct.pal.edge, Tokens.alpha.outline)
                TextInput {
                    id: hexIn
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space.sm
                    verticalAlignment: TextInput.AlignVCenter
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
                        if (t.length === 6) ct.set(ct.role, "#" + t.toLowerCase())
                        else text = ct.hex(ct.cur)
                    }
                    onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => ct.hex(ct.cur))
                }
            }

            Text { text: "Intensity"; color: ct.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
            ColourSlider {
                Layout.fillWidth: true
                palette: ct.pal
                channel: "x"
                from: Qt.hsla(ct.hh, 0.08, 0.5, 1)
                to: ct.accent("primary")
                value: (ct.intensity - 0.3) / 1.2
                onMoved: v => ct.set("intensity", Math.round((0.3 + v * 1.2) * 100) / 100)
            }
            Text { text: Math.round(ct.intensity * 100) + "%"; color: ct.pal.fgDim; font.family: Tokens.font.mono; font.pixelSize: Tokens.size.small }
        }

        Item { Layout.fillHeight: true }

        // a preview of the edits on a bar island and the band's glow line, then the actions
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            Rectangle {
                id: preview
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Tokens.radius.md
                color: ct.theme ? ct.theme.surface : ct.pal.surface
                border.width: 1
                border.color: C.alpha(ct.accent("primary"), 0.5)
                readonly property color fg: ct.theme ? ct.theme.fg : ct.pal.fg
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Tokens.space.md
                    spacing: Tokens.space.sm
                    Ring {
                        width: 24; height: 24
                        value: 62; shown: 62; instant: true
                        thickness: 4
                        from: ct.accent("primary")
                        to: ct.accent("tertiary")
                        track: C.alpha(preview.fg, 0.14)
                        showText: false
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "62%"
                        color: preview.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: Tokens.size.body
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: chipText.implicitWidth + 16; height: 22; radius: 11
                        color: C.alpha(ct.accent("secondary"), 0.22)
                        border.width: 1
                        border.color: C.alpha(ct.accent("secondary"), 0.6)
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: ct.mood === "auto" ? (ct.theme ? ct.moodNames[ct.theme.mood] ?? "" : "") : ct.moodNames[ct.mood]
                            color: preview.fg
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.small
                        }
                    }
                }
                Rectangle {     // the top band's glow line
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: Tokens.radius.md; rightMargin: Tokens.radius.md }
                    height: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.2; color: ct.accent("primary") }
                        GradientStop { position: 0.8; color: ct.accent("tertiary") }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }
            Pill {
                palette: ct.pal
                icon: ct.dirty ? "undo" : "auto_awesome"
                text: ct.dirty ? "Discard" : "Automatic"
                tooltip: ct.dirty ? "Forget these edits" : "Back to the wallpaper's own colours"
                accent: ct.pal.secondary
                onAccent: ct.pal.col("on_secondary")
                enabled: ct.dirty || ct.custom
                opacity: enabled ? 1 : 0.4
                busy: ct.busy && !ct.dirty
                onClicked: ct.reset()
            }
            Pill {
                palette: ct.pal
                icon: "check"
                text: "Apply"
                tooltip: ct.target === "all" ? "Re-theme every screen with these colours" : "Re-theme this screen with these colours"
                enabled: ct.dirty
                opacity: enabled ? 1 : 0.4
                busy: ct.busy && ct.dirty
                onClicked: ct.apply()
            }
        }
        Text {
            Layout.fillWidth: true
            text: ct.status || (ct.dirty && ct.edits.mood !== undefined ? "A new mood re-picks the accents you haven't set by hand."
                  : "Hand-picked colours last until a new wallpaper; keep them with “Save theme”.")
            elide: Text.ElideRight
            color: ct.status ? ct.pal.bad : ct.pal.muted
            font.family: Tokens.font.ui
            font.pixelSize: Tokens.size.small
        }
    }
}
