import QtQuick
import QtQuick.Effects
import Atom
import Rice

// The Theme page's Launcher (every screen): its style (a picture of each; picking the other closes this one and opens
// it), its size, and its backdrop material (4x2 gallery matching Desktop -> Island style so users can mix & match).
Column {
    id: lc
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var styles: (studio.row("lstyle") || { items: [] }).items
    readonly property var size: ((studio.row("lsize") || { items: [] }).items || [])[0] || null
    readonly property var backdrops: (studio.row("backdrop") || { items: [] }).items
    readonly property string wall: studio.targetThumb ? "file://" + studio.targetThumb : ""
    readonly property var targetVals: studio.targetPal && studio.targetPal.values ? studio.targetPal.values : ({})
    readonly property string frost: targetVals._glassFull ? "file://" + targetVals._glassFull : wall
    readonly property bool hasFrost: !!targetVals._glassFull

    // Shared compact static textures for the Liquid glass backdrop preview card (live: false)
    function refreshPvTex() {
        pvSharpSrc.scheduleUpdate()
        pvBlurSrc.scheduleUpdate()
    }
    Item {
        width: 0; height: 0
        Item {
            id: pvSharpHolder
            width: 360; height: 202
            visible: true
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: lc.wall
                sourceSize.width: 480
                smooth: true
                onStatusChanged: if (status === Image.Ready) Qt.callLater(() => pvSharpSrc.scheduleUpdate())
            }
        }
        Item {
            id: pvBlurHolder
            width: 180; height: 101
            visible: true
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: lc.frost
                sourceSize.width: lc.hasFrost ? 0 : 240
                smooth: true
                layer.enabled: !lc.hasFrost
                layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 0.9; blurMax: 32; saturation: 0.2 }
                onStatusChanged: if (status === Image.Ready) Qt.callLater(() => pvBlurSrc.scheduleUpdate())
            }
        }
        ShaderEffectSource { id: pvSharpSrc; sourceItem: pvSharpHolder; hideSource: true; live: false; smooth: true }
        ShaderEffectSource { id: pvBlurSrc; sourceItem: pvBlurHolder; hideSource: true; live: false; smooth: true }
    }
    onWallChanged: Qt.callLater(refreshPvTex)
    onFrostChanged: Qt.callLater(refreshPvTex)
    Component.onCompleted: Qt.callLater(refreshPvTex)

    StudioCap { studio: lc.studio; text: "Style"; note: "picking the other opens it at once" }
    Item { width: 1; height: lc.d(12) }
    Row {
        spacing: lc.d(18)
        Repeater {
            model: lc.styles
            StudioCard {
                id: sc
                required property var modelData
                readonly property bool atom: modelData.style === "atom"
                studio: lc.studio
                picW: lc.d(330); picH: lc.d(178)
                fkey: "ls:" + modelData.style
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: modelData.current ? "In use" : "Switch to it"
                onActivated: lc.studio.model.apply(modelData)
                RoundPic {
                    studio: lc.studio
                    anchors.fill: parent
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: C.mix(lc.lk.surfaceHigh, lc.lk.primary, 0.10) }
                            GradientStop { position: 1; color: lc.lk.surfaceLowest }
                        }
                    }
                    Item {      // Simplified: a hero over rows of tiles
                        visible: !sc.atom
                        anchors.fill: parent
                        Rectangle { x: lc.d(20); y: lc.d(24); width: lc.d(52); height: lc.d(6); radius: lc.d(3); color: lc.lk.fg; opacity: 0.4 }
                        Rectangle { x: lc.d(20); y: lc.d(38); width: lc.d(94); height: lc.d(14); radius: lc.d(4); color: lc.lk.fg; opacity: 0.8 }
                        Repeater {
                            model: 12
                            Rectangle {
                                required property int index
                                x: lc.d(20) + (index % 6) * lc.d(50); y: lc.d(80) + Math.floor(index / 6) * lc.d(42)
                                width: lc.d(42); height: lc.d(32); radius: lc.d(7)
                                color: index % 6 === 0 ? lc.lk.primary : C.alpha(lc.lk.fg, 0.18)
                            }
                        }
                    }
                    Item {      // Atom's: rings round a core
                        visible: sc.atom
                        anchors.fill: parent
                        Rectangle { x: lc.d(20); y: lc.d(76); width: lc.d(98); height: lc.d(16); radius: lc.d(4); color: lc.lk.fg; opacity: 0.8 }
                        Rectangle { x: lc.d(20); y: lc.d(100); width: lc.d(62); height: lc.d(7); radius: lc.d(3.5); color: lc.lk.fgDim; opacity: 0.5 }
                        Item {
                            x: parent.width - lc.d(176); y: lc.d(10); width: lc.d(158); height: width
                            Repeater {
                                model: [31, 49, 67]
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    anchors.centerIn: parent
                                    width: lc.d(2 * modelData); height: width; radius: width / 2
                                    color: "transparent"; border.width: lc.d(1.4); border.color: C.alpha(lc.lk.fg, 0.5 - index * 0.12)
                                }
                            }
                            Rectangle { anchors.centerIn: parent; width: lc.d(38); height: width; radius: width / 2; color: lc.lk.primary; opacity: 0.88 }
                            Repeater {
                                model: [[48, 79], [110, 79], [79, 30], [32, 59], [125, 102], [79, 146]]
                                Rectangle { required property var modelData; x: lc.d(modelData[0] - 5.5); y: lc.d(modelData[1] - 5.5); width: lc.d(11); height: width; radius: width / 2; color: lc.lk.fg; opacity: 0.72 }
                            }
                        }
                    }
                }
            }
        }
    }
    Item { width: 1; height: lc.d(28) }
    StudioCap { studio: lc.studio; text: "Size"; note: "on each screen's standard size" }
    Item { width: 1; height: lc.d(12) }
    StudioSlider {
        visible: !!lc.size
        studio: lc.studio
        fkey: "sl:lsize"
        value: lc.size ? lc.size.v : 1
        min: lc.size ? lc.size.min : 0.8; max: lc.size ? lc.size.max : 1.8; step: lc.size ? lc.size.step : 0.05
        def: lc.size ? lc.size.def : 1
        defLabel: "Standard"
        desc: "<b>Launcher size</b> This launcher and its pages on every screen. Left and right to change it."
        onCommit: v => lc.studio.slide(lc.size, v)
    }
    Item { width: 1; height: lc.d(28) }
    StudioCap { studio: lc.studio; text: "Backdrop"; note: "launcher & power page · mix and match with island styles" }
    Item { width: 1; height: lc.d(12) }
    Grid {
        columns: 4
        columnSpacing: lc.d(18)
        rowSpacing: lc.d(18)
        Repeater {
            model: lc.backdrops
            StudioCard {
                id: bc
                required property var modelData
                readonly property string st: modelData.style
                readonly property bool isSolid: st === "solid" || st === "satin"
                readonly property bool isShaderWall: st === "liquid"
                studio: lc.studio
                picW: lc.d(286); picH: lc.d(152)
                fkey: "bd:" + st
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: "Use this material"
                onActivated: lc.studio.model.apply(modelData)
                RoundPic {
                    studio: lc.studio
                    anchors.fill: parent

                    // 1. Solid & Satin: clean architectural tonal gradient (+ tactile anodized grain on Satin)
                    Item {
                        visible: bc.isSolid
                        anchors.fill: parent
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: C.mix(lc.lk.surfaceHigh, lc.lk.primary, lc.lk.light ? 0.12 : 0.18) }
                                GradientStop { position: 0.55; color: C.mix(lc.lk.surfaceLowest, lc.lk.surfaceHigh, lc.lk.light ? 0.52 : 0.36) }
                                GradientStop { position: 1; color: C.mix(lc.lk.surfaceLowest, lc.lk.tertiary, lc.lk.light ? 0.08 : 0.10) }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: C.alpha(lc.lk.primary, lc.lk.light ? 0.07 : 0.11) }
                                GradientStop { position: 1; color: C.alpha(lc.lk.tertiary, lc.lk.light ? 0.06 : 0.09) }
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: parent.height * (bc.st === "satin" ? 0.55 : 0.38)
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, bc.st === "satin" ? (lc.lk.light ? 0.30 : 0.13) : (lc.lk.light ? 0.22 : 0.07)) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                        Image {
                            visible: bc.st === "satin"
                            anchors.fill: parent
                            source: Prefs.grain
                            fillMode: Image.Tile
                            smooth: false
                            opacity: 0.13
                        }
                    }

                    // 2. Aurora: real GPU velvet palette mesh shader (0 FBOs)
                    ShaderEffect {
                        visible: bc.st === "aurora"
                        anchors.fill: parent
                        fragmentShader: Prefs.auroraBackdropShader
                        readonly property size boxSize: Qt.size(width, height)
                        readonly property real dpr: 1
                        readonly property real isLight: lc.lk.light ? 1 : 0
                        readonly property point origin: Qt.point(width / 2, height / 2)
                        readonly property real radius: -1
                        readonly property real veilAlpha: 0.06
                        readonly property color baseColor: lc.lk.surfaceLowest
                        readonly property color colA: lc.lk.primary
                        readonly property color colB: lc.lk.secondary
                        readonly property color colC: lc.lk.tertiary
                    }

                    // 3. Sanded glass (matte): smooth real frost + delicate tactile sandblasted grain
                    Item {
                        visible: bc.st === "matte"
                        anchors.fill: parent
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: visible ? lc.frost : ""
                            sourceSize.width: lc.hasFrost ? 0 : 240
                            smooth: true
                            layer.enabled: visible && !lc.hasFrost
                            layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 0.9; blurMax: 32; saturation: 0.2 }
                        }
                        Rectangle { anchors.fill: parent; color: C.alpha(lc.lk.surfaceLowest, lc.lk.light ? 0.18 : 0.30) }
                        Image { anchors.fill: parent; source: Prefs.grain; fillMode: Image.Tile; smooth: false; opacity: 0.10 }
                    }

                    // 4. Blur (clear): wallpaper + real dark app window composited & blurred smoothly together
                    Item {
                        visible: bc.st === "clear"
                        anchors.fill: parent
                        Item {
                            anchors.fill: parent
                            layer.enabled: bc.st === "clear"
                            layer.effect: MultiEffect { autoPaddingEnabled: false; blurEnabled: true; blur: 0.72; blurMax: 28; saturation: 0.15 }
                            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: bc.st === "clear" ? lc.wall : ""; sourceSize.width: 360; smooth: true }
                            // Subtle open window behind the live blur (blurred with the wallpaper, never harsh!)
                            Rectangle {
                                x: parent.width * 0.22; y: parent.height * 0.16
                                width: parent.width * 0.62; height: parent.height * 0.68
                                radius: lc.d(10)
                                color: C.alpha(lc.lk.light ? "#ffffff" : lc.lk.surfaceHigh, 0.76)
                                border.width: lc.d(1); border.color: C.alpha(lc.lk.primary, 0.5)
                                Rectangle { x: lc.d(8); y: lc.d(8); width: parent.width * 0.24; height: parent.height - lc.d(16); radius: lc.d(6); color: C.alpha(lc.lk.primary, 0.32) }
                                Rectangle { x: parent.width * 0.36; y: lc.d(18); width: parent.width * 0.48; height: lc.d(10); radius: lc.d(4); color: C.alpha(lc.lk.fg, 0.45) }
                                Rectangle { x: parent.width * 0.36; y: lc.d(36); width: parent.width * 0.36; height: lc.d(8); radius: lc.d(4); color: C.alpha(lc.lk.tertiary, 0.40) }
                            }
                        }
                        Rectangle { anchors.fill: parent; color: C.alpha(lc.lk.surfaceLowest, lc.lk.light ? 0.14 : 0.26) }
                    }

                    // 5. Liquid glass: live GPU refraction shader over shared static wall textures
                    Item {
                        visible: bc.isShaderWall
                        anchors.fill: parent
                        ShaderEffect {
                            anchors.fill: parent
                            fragmentShader: Prefs.liquidBackdropShader
                            readonly property size boxSize: Qt.size(width, height)
                            readonly property size screenSize: Qt.size(width, height)
                            readonly property real offsetY: 0
                            readonly property real dpr: 1
                            readonly property point origin: Qt.point(width / 2, height / 2)
                            readonly property real radius: -1
                            readonly property real isLight: lc.lk.light ? 1 : 0
                            readonly property point lensCenter: Qt.point(width * 0.74, height * 0.54)
                            readonly property real lensRadius: lc.d(34)
                            readonly property real veilAlpha: 0.20
                            readonly property color veilColor: lc.lk.surfaceLowest
                            readonly property color accentColor: lc.lk.primary
                            readonly property var sharpTex: pvSharpSrc
                            readonly property var blurTex: pvBlurSrc
                        }
                        // On Liquid glass card, show a clean curved optical lens pane inset so edge refraction reads unmistakably
                        ShaderEffect {
                            visible: bc.st === "liquid"
                            x: lc.d(14); y: lc.d(14); width: parent.width - lc.d(28); height: parent.height - lc.d(28)
                            fragmentShader: Prefs.opticalGlassShader
                            readonly property size boxSize: Qt.size(width, height)
                            readonly property point rectPos: Qt.point(x, y)
                            readonly property size screenSize: Qt.size(parent.width, parent.height)
                            readonly property real bevel: lc.d(13)
                            readonly property real dpr: 1
                            readonly property vector4d radii: Qt.vector4d(lc.d(14), lc.d(14), lc.d(14), lc.d(14))
                            readonly property color tintColor: Qt.rgba(lc.lk.surfaceLowest.r, lc.lk.surfaceLowest.g, lc.lk.surfaceLowest.b, lc.lk.light ? 0.24 : 0.20)
                            readonly property color rimA: lc.lk.primary
                            readonly property color rimB: lc.lk.tertiary
                            readonly property color rimC: lc.lk.secondary
                            readonly property real glassAlpha: 0.86
                            readonly property real frostMix: 0.36
                            readonly property real isLight: lc.lk.light ? 1 : 0
                            readonly property real isJewel: 0
                            readonly property real flatBottom: 0
                            readonly property real mode: 0
                            readonly property var sharpTex: pvSharpSrc
                            readonly property var blurTex: pvBlurSrc
                        }
                    }

                    // 7. Clear (none): crisp unfiltered wallpaper + light readability vignette
                    Item {
                        visible: bc.st === "none"
                        anchors.fill: parent
                        Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: bc.st === "none" ? lc.wall : ""; sourceSize.width: 480; smooth: true }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0; color: C.alpha(lc.lk.surfaceLowest, 0.36) }
                                GradientStop { position: 0.45; color: "transparent" }
                                GradientStop { position: 1; color: C.alpha(lc.lk.surfaceLowest, 0.24) }
                            }
                        }
                    }

                    // Unified miniature Atom Launcher silhouette on EVERY card so materials compare cleanly side-by-side
                    Item {
                        anchors.fill: parent
                        // Top bar pill hints
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: lc.d(12)
                            spacing: lc.d(5)
                            Repeater {
                                model: 3
                                Rectangle {
                                    required property int index
                                    width: index === 0 ? lc.d(22) : lc.d(14); height: lc.d(5); radius: height / 2
                                    color: index === 0 ? lc.lk.fg : C.alpha(lc.lk.fg, 0.34)
                                }
                            }
                        }
                        // Left hero caption silhouette
                        Column {
                            x: lc.d(22); anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: lc.d(6)
                            spacing: lc.d(6)
                            Rectangle { width: lc.d(74); height: lc.d(10); radius: lc.d(4); color: C.alpha(lc.lk.fg, 0.86) }
                            Rectangle { width: lc.d(48); height: lc.d(5.5); radius: lc.d(3); color: C.alpha(lc.lk.fgDim, 0.60) }
                            Rectangle { width: lc.d(30); height: lc.d(9); radius: height / 2; color: C.alpha(lc.lk.primary, 0.85) }
                        }
                        // Right miniature Atom orbit & core silhouette
                        Item {
                            x: parent.width - lc.d(96); anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: lc.d(6)
                            width: lc.d(68); height: width
                            Rectangle {
                                anchors.centerIn: parent; width: lc.d(62); height: width; radius: width / 2
                                color: "transparent"; border.width: lc.d(1); border.color: C.alpha(lc.lk.fg, 0.22)
                            }
                            Rectangle {
                                anchors.centerIn: parent; width: lc.d(42); height: width; radius: width / 2
                                color: "transparent"; border.width: lc.d(1); border.color: C.alpha(lc.lk.fg, 0.36)
                            }
                            Rectangle {
                                anchors.centerIn: parent; width: lc.d(20); height: width; radius: width / 2
                                color: C.alpha(lc.lk.primary, 0.80)
                                border.width: lc.d(1); border.color: Qt.rgba(1, 1, 1, 0.45)
                            }
                        }
                    }

                    // Crisp card frame hairline
                    Rectangle {
                        anchors.fill: parent; radius: lc.d(14); color: "transparent"
                        border.width: lc.d(1); border.color: Qt.rgba(1, 1, 1, lc.lk.light ? 0.30 : 0.14)
                    }
                }
            }
        }
    }
}
