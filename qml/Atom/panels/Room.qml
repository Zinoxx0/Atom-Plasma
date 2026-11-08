import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Atom
import "../../Rice"
import "../../Rice/Color.js" as C
import "parts"

// The room's lights (Atom RoomLight): the bedside lamp and the LED strip side by side, each with its
// switch, light level, white (warm to cool), a colour field and swatches, and its moods (the lamp also its
// animations); Match wallpaper for both under them. Opened from the status island's light button or the
// control center's Room row; shows only what answers. A strip that can't be reached says why, with a
// way to try again.
FocusScope {
    id: rp
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette
    function u(n) { return Math.round(n * ui) }
    readonly property var lights: RoomLight

    readonly property real colW: u(330)
    readonly property bool showLamp: lights.lampReachable
    readonly property bool showStrip: lights.roomReachable
    implicitWidth: (showLamp && showStrip ? 2 * colW + u(25) : colW + u(40))
    // as tall as it needs, up to what the screen has above the bar (the laptop's): then it scrolls
    readonly property real maxH: Screen.height > 0 ? Screen.height - u(150) : col.implicitHeight
    implicitHeight: Math.min(col.implicitHeight, maxH)
    function enter() { lights.refresh(); forceActiveFocus() }
    Component.onCompleted: RoomLight.watch("room/" + screenName, true)
    Component.onDestruction: RoomLight.watch("room/" + screenName, false)

    // ------------------------------------------------------------------ bits
    component Caption: Text {
        property RicePalette pal
        property real ui: 1
        color: pal ? pal.muted : "grey"
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(10.5 * ui)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }
    // candy dots: a light's quick colours
    component Swatches: RowLayout {
        id: sw
        property RicePalette pal
        property real ui: 1
        property var colours: []           // colours to show
        property int current: -1           // the one the light shows
        signal picked(int index)
        spacing: 0
        Repeater {
            model: sw.colours
            Item {
                id: dot
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: Math.round(26 * sw.ui)
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.round(22 * sw.ui); height: width; radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(dot.modelData, 1.15) }
                        GradientStop { position: 1; color: Qt.darker(dot.modelData, 1.1) }
                    }
                    border.width: dm.containsMouse || sw.current === dot.index ? Math.round(2 * sw.ui) : 1
                    border.color: dm.containsMouse || sw.current === dot.index ? sw.pal.fg : Qt.rgba(1, 1, 1, 0.3)
                    scale: dm.pressed ? 0.88 : dm.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                }
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sw.picked(dot.index) }
            }
        }
    }

    // the lamp's swatches as hue/saturation, the strip's as hex (each light's own language)
    readonly property var lampDots: [{ hue: 0, sat: 90 }, { hue: 22, sat: 100 }, { hue: 40, sat: 100 }, { hue: 140, sat: 80 },
                                     { hue: 188, sat: 90 }, { hue: 224, sat: 85 }, { hue: 268, sat: 80 }, { hue: 332, sat: 68 }]
    readonly property var stripDots: ["#ff1a1a", "#ff6a00", "#ffb000", "#d77757", "#33e07a", "#1ad1ff", "#3a6bff", "#9b4dff", "#ff4fa3"]
    readonly property color stripColour: lights.strip.color || "#ffffff"
    readonly property bool lampFree: lights.lampOn && !lights.lampFlow && !lights.lampScene          // white or colour by hand
    readonly property string syncSource: {
        if (lights.sync.screen === "theme" || !lights.sync.screen) return "the theme screen"
        const s = (lights.sync.screens || []).find(x => x.id === lights.sync.screen)
        return s ? "the " + s.label + " screen" : lights.sync.screen
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: col.implicitHeight
      interactive: contentHeight > height + 1
      clip: interactive
      boundsBehavior: Flickable.StopAtBounds
    ColumnLayout {
        id: col
        width: rp.width
        spacing: rp.u(14)

        // ------------------------------------------------------------------ the room
        RowLayout {
            Layout.fillWidth: true
            spacing: rp.u(10)
            Column {
                Layout.fillWidth: true
                spacing: rp.u(1)
                Text {
                    text: "Room"
                    color: rp.pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.DemiBold
                    font.pixelSize: rp.u(18)
                }
                Text {
                    text: !lights.present ? "Away from home" : lights.anyOn
                        ? [lights.lampOn ? "Lamp on" : "", lights.stripOn ? "Strip on" : ""].filter(x => x).join("  ·  ")
                        : "All off"
                    color: rp.pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: rp.u(12)
                }
            }
            Chip {
                pal: rp.pal; ui: rp.ui
                glyph: "power_settings_new"
                text: lights.anyOn ? "All off" : "All on"
                selected: lights.anyOn
                onClicked: lights.setAll(!lights.anyOn)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: rp.u(12)

            // ------------------------------------------------------------------ the lamp
            ColumnLayout {
                visible: rp.showLamp
                Layout.preferredWidth: rp.colW
                Layout.maximumWidth: rp.colW
                Layout.alignment: Qt.AlignTop
                spacing: rp.u(10)
                Tile {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    icon: lights.lampOn ? "light" : "light_off"
                    label: "Bedside lamp"
                    sub: lights.lampSummary
                    on: lights.lampOn
                    onToggled: lights.setLamp(!lights.lampOn)
                }
                Level {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    icon: "brightness_6"
                    label: "Light level"
                    value: lights.lampBright / 100
                    dim: !lights.lampOn
                    onMoved: v => lights.setLampBright(v * 100)
                    onIconClicked: lights.setLamp(!lights.lampOn)
                }
                Spectrum {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    label: "White"
                    valueText: lights.lampCt + " K"
                    from: 1700; to: 6500; step: 100
                    value: lights.lampCt
                    engaged: rp.lampFree && lights.lampMode === "white"
                    onMoved: v => lights.setLampCt(v)
                }
                HueField {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    hue: lights.lampHue; sat: lights.lampSat
                    engaged: rp.lampFree && lights.lampMode === "colour"
                    onPicked: (h, s) => lights.setLampHsv(h, s)
                }
                Swatches {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    colours: rp.lampDots.map(d => Qt.hsva(d.hue / 360, d.sat / 100, 1, 1))
                    current: lights.lampMode === "colour" && rp.lampFree ? rp.lampDots.findIndex(d => d.hue === lights.lampHue && d.sat === lights.lampSat) : -1
                    onPicked: i => lights.setLampHsv(rp.lampDots[i].hue, rp.lampDots[i].sat)
                }
                Caption { pal: rp.pal; ui: rp.ui; text: "Moods"; Layout.topMargin: rp.u(2) }
                Flow {
                    Layout.fillWidth: true
                    spacing: rp.u(6)
                    Chip {
                        pal: rp.pal; ui: rp.ui; small: true
                        glyph: "local_fire_department"; text: "Candle"
                        selected: lights.lampFlow === "candle"
                        onClicked: selected ? lights.stopLampFlow() : lights.startLampFlow("candle")
                    }
                    Repeater {
                        model: [{ id: "night", glyph: "bedtime", text: "Ultra night" }, { id: "cozy", glyph: "chair", text: "Cozy" },
                                { id: "reading", glyph: "menu_book", text: "Reading" }, { id: "focus", glyph: "center_focus_strong", text: "Focus" }]
                        Chip {
                            required property var modelData
                            pal: rp.pal; ui: rp.ui; small: true
                            glyph: modelData.glyph; text: modelData.text
                            selected: lights.lampOn && (lights.lampScene === modelData.id || (modelData.id === "night" && lights.lampMode === "night"))
                            onClicked: lights.setLampScene(modelData.id)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: rp.u(2)
                    Caption { pal: rp.pal; ui: rp.ui; text: "Animation"; Layout.fillWidth: true }
                    Repeater {
                        model: [{ id: "calm", text: "Calm" }, { id: "normal", text: "Normal" }, { id: "lively", text: "Lively" }]
                        Text {
                            required property var modelData
                            text: modelData.text
                            color: lights.lampSpeed === modelData.id ? rp.pal.primary : spm.containsMouse ? rp.pal.fg : rp.pal.muted
                            font.family: Tokens.font.ui
                            font.weight: lights.lampSpeed === modelData.id ? Font.DemiBold : Font.Medium
                            font.pixelSize: rp.u(11)
                            MouseArea { id: spm; anchors.fill: parent; anchors.margins: -rp.u(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lights.setLampSpeed(parent.modelData.id) }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: rp.u(6)
                    Repeater {
                        model: [{ id: "breathe", text: "Breathe" }, { id: "drift", text: "Drift" }, { id: "sunset", text: "Sunset" },
                                { id: "ocean", text: "Ocean" }, { id: "aurora", text: "Aurora" }]
                        Chip {
                            required property var modelData
                            pal: rp.pal; ui: rp.ui; small: true
                            text: modelData.text
                            selected: lights.lampFlow === modelData.id
                            onClicked: selected ? lights.stopLampFlow() : lights.startLampFlow(modelData.id)
                        }
                    }
                }
            }

            Rectangle {     // between the lights
                visible: rp.showLamp && rp.showStrip
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: C.alpha(rp.pal.edge, Tokens.alpha.outline)
            }

            // ------------------------------------------------------------------ the strip
            ColumnLayout {
                visible: rp.showStrip
                Layout.preferredWidth: rp.colW
                Layout.maximumWidth: rp.colW
                Layout.alignment: Qt.AlignTop
                spacing: rp.u(10)
                Tile {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    icon: lights.stripTrouble ? "bluetooth_disabled" : "wb_iridescent"
                    label: "LED strip"
                    sub: lights.stripSummary
                    on: lights.stripOn && !lights.stripTrouble
                    busy: lights.stripBusy
                    onToggled: lights.setStrip(!lights.stripOn)
                }
                // can't reach it: why, and a way to try again
                Rectangle {
                    visible: lights.stripTrouble
                    Layout.fillWidth: true
                    implicitHeight: troubleCol.implicitHeight + rp.u(20)
                    radius: rp.u(14)
                    color: C.alpha(rp.pal.warn, 0.1)
                    border.width: 1
                    border.color: C.alpha(rp.pal.warn, 0.35)
                    ColumnLayout {
                        id: troubleCol
                        x: rp.u(12); y: rp.u(10)
                        width: parent.width - rp.u(24)
                        spacing: rp.u(8)
                        Text {
                            Layout.fillWidth: true
                            text: "The strip didn't answer. It only takes one Bluetooth client: close its phone app, "
                                + "or switch it off at the plug for a few seconds."
                            wrapMode: Text.WordWrap
                            color: rp.pal.fgDim
                            font.family: Tokens.font.ui
                            font.pixelSize: rp.u(11)
                        }
                        Chip {
                            pal: rp.pal; ui: rp.ui; small: true
                            glyph: "refresh"; text: "Try again"
                            onClicked: lights.setStrip(lights.stripOn)
                        }
                    }
                }
                Level {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    icon: "brightness_6"
                    label: "Light level"
                    value: lights.stripBright / 100
                    dim: !lights.stripOn
                    onMoved: v => lights.setStripBright(v * 100)
                    onIconClicked: lights.setStrip(!lights.stripOn)
                }
                Spectrum {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    label: "White"
                    valueText: (lights.strip.kelvin || 4000) + " K"
                    from: 2000; to: 6500; step: 100
                    value: lights.strip.kelvin || 4000
                    engaged: lights.stripOn && lights.strip.mode === "white" && !lights.sync.on
                    c0: "#ff9a3c"
                    onMoved: v => lights.setStripKelvin(v)
                }
                HueField {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    hue: Math.max(0, Math.round(rp.stripColour.hsvHue * 359))
                    sat: Math.round(rp.stripColour.hsvSaturation * 100)
                    engaged: lights.stripOn && lights.strip.mode === "colour" && !lights.sync.on
                    onPicked: (h, s) => lights.setStripColour(String(Qt.hsva(h / 360, s / 100, 1, 1)))
                }
                Swatches {
                    Layout.fillWidth: true
                    pal: rp.pal; ui: rp.ui
                    colours: rp.stripDots
                    current: lights.strip.mode === "colour" && !lights.sync.on ? rp.stripDots.indexOf(String(lights.strip.color).toLowerCase()) : -1
                    onPicked: i => lights.setStripColour(rp.stripDots[i])
                }
                Caption { pal: rp.pal; ui: rp.ui; text: "Moods"; Layout.topMargin: rp.u(2) }
                Flow {
                    Layout.fillWidth: true
                    spacing: rp.u(6)
                    Repeater {
                        model: [{ glyph: "bedtime", text: "Night", look: { color: "#ff7a1a", bright: 8 } },
                                { glyph: "chair", text: "Cozy", look: { kelvin: 2700, bright: 35 } },
                                { glyph: "menu_book", text: "Reading", look: { kelvin: 4000, bright: 80 } },
                                { glyph: "center_focus_strong", text: "Focus", look: { kelvin: 5500, bright: 100 } },
                                { glyph: "pets", text: "Clawd", look: { color: "#d77757", bright: 70 } }]
                        Chip {
                            required property var modelData
                            pal: rp.pal; ui: rp.ui; small: true
                            glyph: modelData.glyph; text: modelData.text
                            onClicked: lights.setStripLook(modelData.look)
                        }
                    }
                }
                Chip {
                    pal: rp.pal; ui: rp.ui; small: true
                    Layout.topMargin: rp.u(2)
                    glyph: "palette"; text: "Calibrate colours"
                    onClicked: { Shell.close(); Qt.openUrlExternally("http://127.0.0.1:48724/calibrate") }
                }
            }
        }

        // ------------------------------------------------------------------ both: match the wallpaper
        Rectangle {
            visible: rp.showStrip
            Layout.fillWidth: true
            implicitHeight: syncCol.implicitHeight + rp.u(20)
            radius: rp.u(18)
            color: C.alpha(rp.pal.fg, 0.04)
            border.width: 1
            border.color: C.alpha(rp.pal.edge, Tokens.alpha.outline)
            ColumnLayout {
                id: syncCol
                x: rp.u(10); y: rp.u(10)
                width: parent.width - rp.u(20)
                spacing: rp.u(10)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: rp.u(10)
                    Tile {
                        Layout.fillWidth: true
                        pal: rp.pal; ui: rp.ui
                        icon: "wallpaper"
                        label: "Match wallpaper"
                        sub: lights.sync.problem ? lights.sync.problem
                           : lights.sync.on ? "Strip: its primary, lamp: its tertiary, from " + rp.syncSource
                           : "Both lights take your wallpaper's colours"
                        on: lights.sync.on
                        onToggled: lights.setSync({ on: !lights.sync.on })
                    }
                    Repeater {      // what they got
                        model: lights.sync.on && lights.sync.colours ? [{ g: "wb_iridescent", c: lights.sync.colours.strip }, { g: "light", c: lights.sync.colours.lamp }] : []
                        Rectangle {
                            required property var modelData
                            implicitWidth: rp.u(30); implicitHeight: implicitWidth; radius: implicitWidth / 2
                            color: modelData.c || "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.3)
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.g
                                // dark ink on light colours, light ink on dark ones
                                color: Qt.color(parent.modelData.c || "#000000").hslLightness > 0.6 ? "#1a1b26" : "#ffffff"
                                font.family: Tokens.font.icons
                                font.pixelSize: rp.u(15)
                            }
                        }
                    }
                }
                Flow {
                    visible: lights.sync.on
                    Layout.fillWidth: true
                    spacing: rp.u(6)
                    Repeater {
                        model: [{ id: "theme", label: "Theme screen" }].concat(lights.sync.screens || [])
                        Chip {
                            required property var modelData
                            pal: rp.pal; ui: rp.ui; small: true
                            glyph: modelData.id === "theme" ? "auto_awesome" : "desktop_windows"
                            text: modelData.label
                            selected: lights.sync.screen === modelData.id
                            onClicked: lights.setSync({ screen: modelData.id })
                        }
                    }
                    Item { width: rp.u(10); height: 1 }
                    Repeater {
                        model: [{ vivid: false, label: "Soft" }, { vivid: true, label: "Vivid" }]
                        Chip {
                            required property var modelData
                            pal: rp.pal; ui: rp.ui; small: true
                            text: modelData.label
                            selected: lights.sync.vivid === modelData.vivid
                            onClicked: lights.setSync({ vivid: modelData.vivid })
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------------ neither answers
        Text {
            visible: !rp.showLamp && !rp.showStrip
            Layout.fillWidth: true
            text: lights.roomProblem || lights.lampProblem || "Looking for the lights…"
            wrapMode: Text.WordWrap
            color: rp.pal.muted
            font.family: Tokens.font.ui
            font.pixelSize: rp.u(13)
        }
    }
    }
}
