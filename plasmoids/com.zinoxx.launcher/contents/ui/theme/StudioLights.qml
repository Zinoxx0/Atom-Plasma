import QtQuick
import Atom
import Rice

// The Theme page's Lighting: every keyboard side by side, each on its own: a picture of its keys as they shine now,
// the screen whose colours it wears, its effect (the screen-following styles, its own effects, "Your colour" opens
// the colour editor at it, Off), its brightness, and a switch.
Item {
    id: lt
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var devs: studio.model.lights && studio.model.lights.devices ? studio.model.lights.devices : []
    width: studio.mainWidth
    implicitHeight: devs.length ? cols.height : none.height
    Text {
        id: none
        visible: !lt.devs.length
        text: "No keyboards with lights here."
        color: lt.lk.fgDim
        font.family: Tokens.font.ui; font.pixelSize: lt.d(17)
    }
    Row {
        id: cols
        spacing: lt.d(40)
        Repeater {
            model: lt.devs
            Column {
                id: kc
                required property var modelData
                readonly property var dev: modelData
                readonly property var ds: { lt.studio.model.draft; return Object.assign({}, dev.settings || {}, lt.studio.model.kbDraft(dev.id)) }
                readonly property var row: lt.studio.row("kb-" + dev.id)
                readonly property var items: row ? row.items : []
                readonly property bool lit: ds.on !== false
                readonly property string fx: !lit ? "off" : ds.mode === "auto" ? (ds.style || "solid") : (ds.effect || "static")
                readonly property color c0: (dev.colours && dev.colours[0]) || lt.lk.primary
                readonly property color c1: (dev.colours && dev.colours[1]) || c0
                readonly property color own: ds.colour || "#ff3355"
                readonly property string shortName: dev.id === "laptop" ? "Laptop" : String(dev.name || dev.id).split(" ").slice(1, 2).join(" ") || String(dev.name || dev.id)
                width: (lt.width - lt.d(40) * Math.max(0, lt.devs.length - 1)) / Math.max(1, lt.devs.length)
                spacing: 0
                function hash(i) { return (i * 2654435761) % 97 }
                function keyColour(i) {
                    const x = (i % 17) / 16
                    if (fx === "off") return C.alpha(lt.lk.fg, 0.06)
                    if (fx === "gradient") return C.mix(c0, c1, x)
                    if (fx === "starlight") return hash(i) % 5 === 0 ? (i % 2 ? c0 : c1) : C.alpha(lt.lk.fg, 0.08)
                    if (fx === "spectrum" || fx === "wave") return Qt.hsla(x * 0.85, 0.8, 0.6, 1)
                    if (fx === "reactive") return hash(i) % 7 === 0 ? own : C.alpha(lt.lk.fg, 0.08)
                    if (ds.mode !== "auto") return own
                    return c0
                }
                function dotsOf(it) {
                    const k = String(it.key)
                    if (it.kind === "accent") return [it.hex]
                    if (k.endsWith(":off")) return []
                    if (k.indexOf(":style:") >= 0) return k.endsWith("gradient") || k.endsWith("starlight") || k.endsWith("breathe") ? [c0, c1] : [c0]
                    if (k.endsWith("spectrum") || k.endsWith("wave")) return ["#ff4d6d", "#ffd24d", "#4dc3ff"]
                    return [own]
                }
                Item {      // its name, and its switch
                    width: parent.width; height: lt.d(64)
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: lt.d(8)
                        Text { text: kc.shortName; color: lt.lk.fg; font.family: lt.studio.wideFamily; font.variableAxes: lt.studio.wideAxes(110, 600); font.pixelSize: lt.d(24) }
                        Text { text: kc.dev.name + (kc.dev.zones ? " · " + kc.dev.zones : ""); color: lt.lk.fgDim; font.family: Tokens.font.ui; font.pixelSize: lt.d(14.5) }
                    }
                    StudioToggle {
                        visible: !!kc.dev.ready
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        studio: lt.studio
                        fkey: "kon:" + kc.dev.id
                        text: kc.lit ? "On" : "Off"
                        chosen: kc.lit
                        desc: "<b>" + kc.shortName + "</b> Its lighting, on or off."
                        onActivated: lt.studio.model.kbPower(kc.dev.id, !kc.lit)
                    }
                }
                Item { width: 1; height: lt.d(16) }
                Rectangle {     // its keys, as they shine now
                    width: parent.width; height: lt.d(120); radius: lt.d(16)
                    color: C.alpha(lt.lk.fg, 0.08)
                    Grid {
                        id: keysGrid
                        anchors.centerIn: parent
                        columns: 17
                        rowSpacing: lt.d(5); columnSpacing: lt.d(5)
                        opacity: 0.35 + (kc.ds.brightness ?? 60) / 154
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(300) } }
                        Repeater {
                            model: 68
                            Rectangle {
                                required property int index
                                width: (kc.width - lt.d(32) - 16 * lt.d(5)) / 17; height: lt.d(18); radius: lt.d(3)
                                color: kc.keyColour(index)
                                Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
                            }
                        }
                    }
                }
                Text {
                    visible: !kc.dev.ready
                    topPadding: lt.d(14)
                    text: kc.dev.connected ? "It needs a one-time setup first." : "Not connected."
                    color: lt.lk.fgDim; font.family: Tokens.font.ui; font.pixelSize: lt.d(15)
                }
                Column {
                    visible: !!kc.dev.ready
                    width: parent.width
                    Item { width: 1; height: lt.d(22) }
                    StudioCap { studio: lt.studio; text: "Follows"; note: "its colours come from that screen" }
                    Item { width: 1; height: lt.d(10) }
                    Flow {
                        width: parent.width
                        spacing: lt.d(10)
                        Repeater {
                            model: [["lead", "Theme screen"]].concat((lt.studio.model.screens || []).map(s => [s.name, s.label]))
                            StudioChip {
                                required property var modelData
                                studio: lt.studio
                                fkey: "kf:" + kc.dev.id + ":" + modelData[0]
                                text: modelData[1]
                                chosen: (kc.ds.follow || "lead") === modelData[0]
                                desc: "<b>" + modelData[1] + "</b> The " + kc.shortName.toLowerCase() + " keyboard wears " + (modelData[0] === "lead" ? "the theme's screen's" : "the " + modelData[1] + "'s") + " colours."
                                act: "Follow it"
                                onActivated: lt.studio.model.setFollow(kc.dev.id, modelData[0])
                            }
                        }
                    }
                    Item { width: 1; height: lt.d(22) }
                    StudioCap { studio: lt.studio; text: "Effect" }
                    Item { width: 1; height: lt.d(10) }
                    Flow {
                        width: parent.width
                        spacing: lt.d(10)
                        Repeater {
                            model: kc.items
                            StudioChip {
                                id: ec
                                required property var modelData
                                studio: lt.studio
                                fkey: "kx:" + modelData.key
                                text: modelData.name
                                dots: kc.dotsOf(modelData)
                                chosen: !!modelData.current
                                desc: "<b>" + modelData.name + "</b> " + (modelData.desc || "")
                                act: modelData.kind === "accent" ? "Pick its colour" : "Use"
                                onActivated: modelData.kind === "accent" ? lt.studio.editAccent(modelData, ec) : lt.studio.model.apply(modelData)
                            }
                        }
                    }
                    Item { width: 1; height: lt.d(22) }
                    StudioCap { studio: lt.studio; text: "Brightness" }
                    Item { width: 1; height: lt.d(10) }
                    StudioSlider {
                        studio: lt.studio
                        width: parent.width
                        fkey: "sl:kb:" + kc.dev.id
                        value: kc.ds.brightness ?? 0
                        min: 0; max: 100; step: 5; def: 60
                        defLabel: "Usual"
                        fmt: function (v) { return Math.round(v) + "%" }
                        desc: "<b>Brightness</b> How bright the " + kc.shortName.toLowerCase() + " keyboard shines. Left and right to change it."
                        onCommit: v => lt.studio.model.setKbBright(kc.dev.id, v)
                    }
                }
            }
        }
    }
}
