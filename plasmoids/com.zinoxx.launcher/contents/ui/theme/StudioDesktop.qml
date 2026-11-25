import QtQuick
import QtQuick.Effects
import Atom
import Rice

// The Theme page's Desktop (every screen): the top bar's size, the taskbar's (Automatic: each screen at its standard
// size times this; off: this size on every screen) and its islands' material gallery (4x2, matching Launcher Backdrop).
Column {
    id: dc
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var topSize: ((studio.row("top") || { items: [] }).items || [])[0] || null
    readonly property var tsizeRow: studio.row("tsize")
    readonly property var tsize: tsizeRow ? tsizeRow.items[0] : null
    readonly property var auto: tsizeRow && tsizeRow.tools ? tsizeRow.tools.find(t => t.id === "ui:auto") : null
    readonly property var islands: (studio.row("bar") || { items: [] }).items
    readonly property string wall: studio.targetThumb ? "file://" + studio.targetThumb : ""
    readonly property var targetVals: studio.targetPal && studio.targetPal.values ? studio.targetPal.values : ({})
    readonly property string frost: targetVals._glassFull ? "file://" + targetVals._glassFull : wall
    readonly property bool hasFrost: !!targetVals._glassFull

    // Shared compact bottom-cropped wallpaper textures for the Liquid / Aurora island preview cards (live: false)
    function refreshBarTex() {
        barSharpSrc.scheduleUpdate()
        barBlurSrc.scheduleUpdate()
    }
    Item {
        width: 0; height: 0
        Item {
            id: barSharpHolder
            width: 360; height: 192
            visible: true
            clip: true
            Image {
                width: parent.width * 1.4; height: parent.height * 1.4
                x: (parent.width - width) / 2; y: parent.height - height
                fillMode: Image.PreserveAspectCrop
                source: dc.wall
                sourceSize.width: 540
                smooth: true
                onStatusChanged: if (status === Image.Ready) Qt.callLater(() => barSharpSrc.scheduleUpdate())
            }
        }
        Item {
            id: barBlurHolder
            width: 180; height: 96
            visible: true
            clip: true
            Image {
                width: parent.width * 1.4; height: parent.height * 1.4
                x: (parent.width - width) / 2; y: parent.height - height
                fillMode: Image.PreserveAspectCrop
                source: dc.frost
                sourceSize.width: dc.hasFrost ? 0 : 240
                smooth: true
                layer.enabled: !dc.hasFrost
                layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 0.9; blurMax: 32; saturation: 0.2 }
                onStatusChanged: if (status === Image.Ready) Qt.callLater(() => barBlurSrc.scheduleUpdate())
            }
        }
        ShaderEffectSource { id: barSharpSrc; sourceItem: barSharpHolder; hideSource: true; live: false; smooth: true }
        ShaderEffectSource { id: barBlurSrc; sourceItem: barBlurHolder; hideSource: true; live: false; smooth: true }
    }
    onWallChanged: Qt.callLater(refreshBarTex)
    onFrostChanged: Qt.callLater(refreshBarTex)
    Component.onCompleted: Qt.callLater(refreshBarTex)

    StudioCap { studio: dc.studio; text: "Top bar size"; note: "the band at the top of every screen" }
    Item { width: 1; height: dc.d(12) }
    StudioSlider {
        visible: !!dc.topSize
        studio: dc.studio
        fkey: "sl:top"
        value: dc.topSize ? dc.topSize.v : 1
        min: dc.topSize ? dc.topSize.min : 0.8; max: dc.topSize ? dc.topSize.max : 1.8; step: dc.topSize ? dc.topSize.step : 0.05
        def: dc.topSize ? dc.topSize.def : 1.05
        defLabel: "Default"
        desc: "<b>Top bar size</b> Its strip and the window shelf it opens. Left and right to change it."
        onCommit: v => dc.studio.slide(dc.topSize, v)
    }
    Item { width: 1; height: dc.d(30) }
    StudioCap { studio: dc.studio; text: "Taskbar size"; note: "its popups and the desk's clocks follow it" }
    Item { width: 1; height: dc.d(12) }
    Row {
        spacing: dc.d(18)
        StudioSlider {
            visible: !!dc.tsize
            studio: dc.studio
            fkey: "sl:tsize"
            value: dc.tsize ? dc.tsize.v : 1
            min: dc.tsize ? dc.tsize.min : 0.8; max: dc.tsize ? dc.tsize.max : 1.8; step: dc.tsize ? dc.tsize.step : 0.05
            def: dc.tsize ? dc.tsize.def : 1
            defLabel: dc.tsize ? dc.tsize.defLabel : "Standard"
            desc: "<b>Taskbar size</b> " + (dc.tsize ? dc.tsize.desc : "") + " Left and right to change it."
            onCommit: v => dc.studio.slide(dc.tsize, v)
        }
        StudioToggle {
            visible: !!dc.auto
            anchors.verticalCenter: parent.verticalCenter
            studio: dc.studio
            fkey: "tg:uiauto"
            text: "Automatic"
            chosen: !!(dc.auto && dc.auto.on)
            desc: "<b>Automatic</b> " + (chosen ? "On: each screen at its standard size × this." : "Off: this size on every screen.")
            onActivated: dc.studio.model.tool("ui:auto")
        }
    }
    Item { width: 1; height: dc.d(30) }
    StudioCap { studio: dc.studio; text: "Island style"; note: "every bar & popup sheet · mix and match with backdrop" }
    Item { width: 1; height: dc.d(12) }
    Grid {
        columns: 4
        columnSpacing: dc.d(18)
        rowSpacing: dc.d(18)
        Repeater {
            model: dc.islands
            StudioCard {
                id: ic
                required property var modelData
                readonly property string st: modelData.style
                readonly property bool isShader: st === "liquid" || st === "aurora"
                readonly property real shaderMode: st === "aurora" ? 1 : 0
                studio: dc.studio
                picW: dc.d(286); picH: dc.d(152)
                fkey: "isl:" + st
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: "Use this material"
                onActivated: dc.studio.model.apply(modelData)
                RoundPic {
                    studio: dc.studio
                    anchors.fill: parent

                    // Desktop background: zoomed bottom edge of this screen's real wallpaper
                    Image {
                        width: parent.width * 1.4; height: parent.height * 1.4
                        x: (parent.width - width) / 2; y: parent.height - height
                        fillMode: Image.PreserveAspectCrop
                        source: dc.wall
                        sourceSize.width: 540
                        smooth: true
                    }
                    // On Blur card, show a subtle bright-rimmed app window peeking behind the floating bar
                    Rectangle {
                        visible: ic.st === "clear"
                        x: dc.d(22); y: dc.d(16)
                        width: dc.d(138); height: dc.d(136)
                        radius: dc.d(10)
                        color: C.alpha(dc.lk.light ? "#ffffff" : dc.lk.surfaceHigh, 0.82)
                        border.width: dc.d(1); border.color: C.alpha(dc.lk.primary, 0.55)
                        Rectangle { x: dc.d(8); y: dc.d(8); width: dc.d(30); height: parent.height - lcGap; readonly property real lcGap: dc.d(16); radius: dc.d(5); color: C.alpha(dc.lk.primary, 0.28) }
                        Rectangle { x: dc.d(46); y: dc.d(16); width: dc.d(72); height: dc.d(7); radius: dc.d(3.5); color: C.alpha(dc.lk.fg, 0.45) }
                        Rectangle { x: dc.d(46); y: dc.d(30); width: dc.d(54); height: dc.d(6); radius: dc.d(3); color: C.alpha(dc.lk.tertiary, 0.45) }
                    }

                    // Authentic bottom-flush Atom Plasma notch bar: [Launcher jewel] [Tasks] ... [Status + Clock]
                    Item {
                        id: barRow
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: dc.d(38)
                        readonly property real nr: dc.d(11)
                        // [x, width, rTL, rTR, isJewel, kind]
                        readonly property var specs: [
                            { x: 0, w: dc.d(38), tl: 0, tr: nr, jewel: true, kind: "launcher", t: 0 },
                            { x: dc.d(46), w: dc.d(116), tl: nr, tr: nr, jewel: false, kind: "tasks", t: 0.35 },
                            { x: width - dc.d(94), w: dc.d(94), tl: nr, tr: 0, jewel: false, kind: "clock", t: 1.0 },
                        ]

                        Repeater {
                            model: barRow.specs
                            Item {
                                id: isl
                                required property var modelData
                                x: modelData.x
                                y: 0
                                width: modelData.w
                                height: barRow.height
                                readonly property color acc: C.mix(dc.lk.primary, dc.lk.tertiary, modelData.t)

                                // Soft grounding shadow
                                RectangularShadow {
                                    anchors.fill: parent
                                    radius: Math.max(isl.modelData.tl, isl.modelData.tr)
                                    blur: dc.d(12); offset.y: -dc.d(1); spread: -dc.d(2)
                                    color: Qt.rgba(0, 0, 0, dc.lk.light ? 0.16 : 0.40)
                                }

                                // GPU shader islands (Liquid glass, Aurora): real optical shader!
                                ShaderEffect {
                                    visible: ic.isShader
                                    anchors.fill: parent
                                    fragmentShader: Prefs.opticalGlassShader
                                    readonly property size boxSize: Qt.size(width, height)
                                    readonly property point rectPos: Qt.point(isl.x, ic.picH - barRow.height)
                                    readonly property size screenSize: Qt.size(ic.picW, ic.picH)
                                    readonly property real bevel: dc.d(10)
                                    readonly property real dpr: 1
                                    readonly property vector4d radii: Qt.vector4d(isl.modelData.tl, isl.modelData.tr, 0, 0)
                                    readonly property color baseTint: dc.lk.light ? Tokens.neutral.light : dc.lk.surfaceLowest
                                    readonly property color tintColor: Qt.rgba(baseTint.r, baseTint.g, baseTint.b,
                                        ic.shaderMode > 0.5 ? 1.0 : (dc.lk.light ? 0.34 : 0.24))
                                    readonly property color rimA: (isl.modelData.jewel || ic.shaderMode > 0.5) ? dc.lk.primary : isl.acc
                                    readonly property color rimB: (isl.modelData.jewel || ic.shaderMode > 0.5) ? dc.lk.tertiary : isl.acc
                                    readonly property color rimC: dc.lk.secondary
                                    readonly property real glassAlpha: isl.modelData.jewel ? 0.92 : (ic.shaderMode > 0.5 ? 0.90 : 0.84)
                                    readonly property real frostMix: isl.modelData.jewel ? 0.32 : 0.30
                                    readonly property real isLight: dc.lk.light ? 1 : 0
                                    readonly property real isJewel: isl.modelData.jewel ? 1 : 0
                                    readonly property real flatBottom: 1
                                    readonly property real mode: ic.shaderMode
                                    readonly property var sharpTex: barSharpSrc
                                    readonly property var blurTex: barBlurSrc
                                }

                                // Non-shader islands (Solid, Satin, Sanded glass, Blur, Clear)
                                Item {
                                    visible: !ic.isShader
                                    anchors.fill: parent
                                    // Clipped interior showing frosted wallpaper for Sanded glass / Blur
                                    Item {
                                        anchors.fill: parent
                                        visible: !isl.modelData.jewel && (ic.st === "matte" || ic.st === "clear")
                                        layer.enabled: visible
                                        layer.effect: MultiEffect { maskEnabled: true; maskSource: notchMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                        Image {
                                            x: -isl.x
                                            y: -(ic.picH - barRow.height)
                                            width: ic.picW * 1.4; height: ic.picH * 1.4
                                            fillMode: Image.PreserveAspectCrop
                                            source: (ic.st === "matte" || ic.st === "clear") ? dc.frost : ""
                                            sourceSize.width: dc.hasFrost ? 0 : 240
                                            smooth: true
                                            layer.enabled: !dc.hasFrost && (ic.st === "matte" || ic.st === "clear")
                                            layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 0.85; blurMax: 24 }
                                        }
                                        // Blurred window tint hint inside Blur's tasks notch
                                        Rectangle {
                                            visible: ic.st === "clear" && isl.modelData.kind === "tasks"
                                            x: -dc.d(8); y: 0; width: dc.d(100); height: parent.height
                                            color: C.alpha(dc.lk.light ? "#ffffff" : dc.lk.primary, 0.24)
                                        }
                                    }
                                    Rectangle {
                                        id: notchMask
                                        anchors.fill: parent
                                        visible: false
                                        layer.enabled: !ic.isShader && !isl.modelData.jewel && (ic.st === "matte" || ic.st === "clear" || ic.st === "satin")
                                        topLeftRadius: isl.modelData.tl; topRightRadius: isl.modelData.tr
                                        bottomLeftRadius: 0; bottomRightRadius: 0
                                        color: "white"
                                    }
                                    // Body fill (or accent gradient for launcher jewel)
                                    Rectangle {
                                        anchors.fill: parent
                                        topLeftRadius: isl.modelData.tl; topRightRadius: isl.modelData.tr
                                        bottomLeftRadius: 0; bottomRightRadius: 0
                                        color: isl.modelData.jewel ? "transparent"
                                             : ic.st === "solid" ? C.alpha(dc.lk.surfaceHigh, 0.94)
                                             : ic.st === "satin" ? C.alpha(C.mix(dc.lk.surfaceHigh, isl.acc, 0.08), 0.97)
                                             : ic.st === "matte" ? C.alpha(dc.lk.surfaceHigh, 0.62)
                                             : ic.st === "clear" ? C.alpha(dc.lk.surfaceHigh, 0.34)
                                             : C.alpha(dc.lk.surfaceLowest, 0.48)
                                        gradient: isl.modelData.jewel ? jewelGrad : null
                                        Gradient {
                                            id: jewelGrad
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: dc.lk.primary }
                                            GradientStop { position: 1; color: dc.lk.tertiary }
                                        }
                                        border.width: dc.d(1)
                                        border.color: isl.modelData.jewel ? C.alpha("#ffffff", 0.45)
                                                    : C.alpha(isl.acc, ic.st === "clear" ? 0.45 : 0.38)
                                    }
                                    // Sanded glass & Satin tactile micro-grain clipped cleanly to the notch
                                    Image {
                                        visible: !isl.modelData.jewel && (ic.st === "matte" || ic.st === "satin")
                                        anchors.fill: parent
                                        source: visible ? Prefs.grain : ""
                                        fillMode: Image.Tile
                                        smooth: false
                                        opacity: ic.st === "satin" ? 0.15 : 0.11
                                        layer.enabled: visible
                                        layer.effect: MultiEffect { maskEnabled: true; maskSource: notchMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                    }
                                    // Crisp top edge specular highlight
                                    Rectangle {
                                        x: isl.modelData.tl; y: dc.d(1)
                                        width: Math.max(0, parent.width - isl.modelData.tl - isl.modelData.tr)
                                        height: dc.d(ic.st === "satin" ? 1.5 : 1)
                                        color: Qt.rgba(1, 1, 1, ic.st === "satin" ? 0.42 : ic.st === "clear" ? 0.48 : 0.26)
                                    }
                                }

                                // Authentic miniature glyphs inside each notch (Launcher A, Tasks pins, Status + Clock)
                                Text {
                                    visible: isl.modelData.kind === "launcher"
                                    anchors.centerIn: parent
                                    text: "A"
                                    color: "#ffffff"
                                    font.family: Tokens.font.display
                                    font.weight: Font.Bold
                                    font.pixelSize: dc.d(15)
                                }
                                Row {
                                    visible: isl.modelData.kind === "tasks"
                                    anchors.centerIn: parent
                                    spacing: dc.d(9)
                                    Repeater {
                                        model: [dc.lk.primary, dc.lk.tertiary, dc.lk.secondary, dc.lk.fg]
                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            width: dc.d(16); height: width; radius: dc.d(5)
                                            color: C.alpha(modelData, index === 3 ? 0.72 : 0.90)
                                        }
                                    }
                                }
                                Row {
                                    visible: isl.modelData.kind === "clock"
                                    anchors.centerIn: parent
                                    spacing: dc.d(6)
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: dc.d(6); height: width; radius: width / 2; color: dc.lk.primary }
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: dc.d(6); height: width; radius: width / 2; color: dc.lk.tertiary; opacity: 0.85 }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "12:00"
                                        color: dc.lk.fg
                                        font.family: Tokens.font.ui
                                        font.weight: Font.DemiBold
                                        font.pixelSize: dc.d(11.5)
                                    }
                                }
                            }
                        }
                    }

                    // Crisp card frame hairline
                    Rectangle {
                        anchors.fill: parent; radius: dc.d(14); color: "transparent"
                        border.width: dc.d(1); border.color: Qt.rgba(1, 1, 1, dc.lk.light ? 0.30 : 0.14)
                    }
                }
            }
        }
    }
}
