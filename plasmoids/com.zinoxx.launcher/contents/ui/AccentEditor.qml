import QtQuick
import QtQuick.Effects
import Rice

// An accent of the Theme page, edited where it sits: a card at its tile with the colour's hue, saturation and
// lightness (the Colours panel's sliders) and its hex. The card shows the change at once; it's applied when
// the hands rest (ThemeModel.setAccent: one rice.py run at a time, the latest waiting). "Automatic" gives
// the accent back to the wallpaper. Keys (and a pad, through Atom.Native Gamepad): up/down a line, left/right
// change it (held: it keeps going, faster), Enter keeps it, Esc puts back what it was. A click outside keeps it.
FocusScope {
    id: ed
    required property RicePalette rice
    required property var model             // ThemeModel
    property real unit: 1
    function u(n) { return Math.round(n * unit) }
    property var item: null                 // the accent: { role, name, hex, current (hand-picked) }
    property Item anchorItem: null
    readonly property bool open: item !== null
    signal closed()

    property real h: 0
    property real s: 0.6
    property real l: 0.6
    property int line: 0                    // 0 hue, 1 saturation, 2 lightness, 3 the buttons
    property int btn: 1                     // 0 Automatic, 1 Done
    property string orig: ""                // what it was, for Esc
    property bool origCustom: false
    property bool touched: false
    readonly property color colour: Qt.hsla(h, s, l, 1)
    function hex(c) { return String(Qt.lighter(c, 1)).slice(0, 7) }

    function openFor(it, tile) {
        const c = Qt.color(it.hex)
        if (c.hslHue >= 0) h = c.hslHue
        s = c.hslSaturation; l = c.hslLightness
        line = 0; btn = 1; touched = false
        orig = hex(c); origCustom = !!it.current
        item = it; anchorItem = tile
        place()
        forceActiveFocus()
    }
    function done() { if (!item) return; if (commit.running) { commit.stop(); apply() } item = null; closed() }
    function cancel() {
        if (!item) return
        commit.stop()
        if (touched) { if (origCustom) model.setAccent(item.role, orig); else model.resetAccent(item.role) }
        item = null; closed()
    }
    function automatic() { if (!item) return; commit.stop(); model.resetAccent(item.role); item = null; closed() }
    function changed() { touched = true; commit.restart() }
    function apply() { if (item) model.setAccent(item.role, hex(colour)) }
    Timer { id: commit; interval: 380; onTriggered: ed.apply() }
    function nudge(ch, d) {
        if (ch === 0) h = (h + d + 1) % 1
        else if (ch === 1) s = Math.max(0, Math.min(1, s + d))
        else l = Math.max(0.05, Math.min(0.95, l + d))
        changed()
    }

    // over its tile: above it when there's room, else under it
    function place() {
        if (!anchorItem) return
        const p = anchorItem.mapToItem(ed, 0, 0)
        card.x = Math.max(u(24), Math.min(ed.width - card.width - u(24), p.x + anchorItem.width / 2 - card.width / 2))
        const above = p.y - card.height - u(26)
        card.y = above >= u(70) ? above : p.y + anchorItem.height + u(26)
    }

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Escape) ed.cancel()
        else if (k === Qt.Key_Up) ed.line = Math.max(0, ed.line - 1)
        else if (k === Qt.Key_Down) ed.line = Math.min(3, ed.line + 1)
        else if (k === Qt.Key_Left || k === Qt.Key_Right) {
            const d = k === Qt.Key_Left ? -1 : 1
            if (ed.line === 3) ed.btn = Math.max(0, Math.min(1, ed.btn + d))
            else ed.nudge(ed.line, d * (e.isAutoRepeat ? 0.02 : 0.01))
        }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (ed.line === 3 && ed.btn === 0) ed.automatic(); else ed.done() }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Menu) {}
        else return
        e.accepted = true
    }

    // a quiet scrim: the page steps back while the card is out
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.32)
        opacity: ed.open ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(220) } }
    }
    // a click outside keeps it and closes the card (and the tiles under it don't take the pointer meanwhile)
    MouseArea {
        anchors.fill: parent
        enabled: ed.open
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ed.done()
    }

    Item {
        id: card
        width: ed.u(420)
        height: col.implicitHeight + 2 * ed.u(22)
        visible: opacity > 0.01
        opacity: ed.open ? 1 : 0
        scale: ed.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on scale { NumberAnimation { duration: Tokens.ms(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        RectangularShadow { anchors.fill: parent; radius: ed.u(26); blur: ed.u(44); offset.y: ed.u(16); spread: -ed.u(10); color: Qt.rgba(0, 0, 0, 0.5) }
        Rectangle {
            anchors.fill: parent
            radius: ed.u(26)
            color: C.alpha(ed.rice.surfaceLowest, 0.94)
            border.width: 1
            border.color: C.alpha(ed.rice.edge, 0.16)
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true }     // inside the card isn't outside

        Column {
            id: col
            x: ed.u(22); y: ed.u(22)
            width: card.width - 2 * ed.u(22)
            spacing: ed.u(6)
            Row {
                spacing: ed.u(14)
                bottomPadding: ed.u(8)
                Rectangle {
                    width: ed.u(40); height: width; radius: width / 2
                    color: ed.colour
                    border.width: 1
                    border.color: C.alpha("#ffffff", 0.3)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: ed.item ? ed.item.editTitle || ed.item.name + " accent" : ""; color: ed.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: ed.u(18) }
                    Text { text: ed.hex(ed.colour).toUpperCase(); color: ed.rice.muted; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: ed.u(14); font.features: { "tnum": 1 } }
                }
            }
            Repeater {
                model: [["Hue", "h"], ["Saturation", "s"], ["Lightness", "l"]]
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool lit: ed.line === index
                    width: col.width
                    height: ed.u(46)
                    radius: ed.u(14)
                    color: lit ? C.alpha(ed.rice.fg, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Text {
                        x: ed.u(12)
                        anchors.verticalCenter: parent.verticalCenter
                        width: ed.u(96)
                        text: modelData[0]
                        color: parent.lit ? ed.rice.fg : ed.rice.fgDim
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: ed.u(14)
                    }
                    ColourSlider {
                        x: ed.u(112)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - ed.u(14)
                        height: ed.u(26)
                        palette: ed.rice
                        channel: modelData[1]
                        h: ed.h; s: ed.s; l: ed.l
                        value: channel === "h" ? ed.h : channel === "s" ? ed.s : ed.l
                        onMoved: v => { ed.line = index; if (channel === "h") ed.h = v; else if (channel === "s") ed.s = v; else ed.l = Math.max(0.05, Math.min(0.95, v)); ed.changed() }
                    }
                }
            }
            Row {
                spacing: ed.u(10)
                topPadding: ed.u(10)
                anchors.right: parent.right
                Button { rice: ed.rice; unit: ed.unit; label: "Automatic"; icon: "auto_awesome"; focused: ed.line === 3 && ed.btn === 0; onClicked: ed.automatic() }
                Button { rice: ed.rice; unit: ed.unit; label: "Done"; icon: "check"; bright: true; focused: ed.line === 3 && ed.btn === 1; onClicked: ed.done() }
            }
        }
    }

    component Button: Rectangle {
        id: b
        property string label: ""
        property string icon: ""
        property bool bright: false
        property bool focused: false
        property RicePalette rice: null     // (an inline component sees no ids of its file: all passed in)
        property real unit: 1
        function u(n) { return Math.round(n * unit) }
        signal clicked()
        height: b.u(40)
        width: br.implicitWidth + b.u(32)
        radius: height / 2
        color: bright ? (b.rice.light ? b.rice.fg : "#f3f6fb") : C.alpha(b.rice.fg, bm.containsMouse || focused ? 0.16 : 0.09)
        border.width: bright ? 0 : 1
        border.color: C.alpha(b.rice.edge, 0.14)
        Row {
            id: br
            anchors.centerIn: parent
            spacing: b.u(8)
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.icon; color: b.bright ? "#0a0d13" : b.rice.fg; font.family: Tokens.font.icons; font.pixelSize: b.u(19) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.label; color: b.bright ? "#0a0d13" : b.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: b.u(15) }
        }
        Rectangle {     // the keys' ring
            anchors.fill: parent
            anchors.margins: -Math.max(4, b.u(5))
            radius: height / 2
            color: "transparent"
            border.width: Math.max(2, b.u(2))
            border.color: b.rice.light ? b.rice.fg : "#ffffff"
            opacity: b.focused ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
