import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import "Rice"
import "Rice/Color.js" as C

// The face of a Theme page tile (HomeTile keeps the focus, the ring, the glow and the clicks):
//   wall    the wallpaper, badged with the screens it's on
//   look    a saved theme: its screens as they sat (LayoutGlyph), and its name
//   save    a place for a new one
//   mood / colours-auto / accent / size / light   a swatch of what it does
// What's in use now wears a tick. Each kind builds only its own parts (a row holds 159 wallpapers).
Item {
    id: face
    required property var item
    required property RicePalette rice
    property real unit: 1
    property real radius: 22
    function u(n) { return Math.round(n * unit) }
    readonly property string kind: item ? item.kind : ""

    Loader {
        anchors.fill: parent
        sourceComponent: face.kind === "wall" ? wallFace : face.kind === "blur" ? blurFace : face.kind ? cardFace : null
    }

    // ---- a wallpaper: its thumbnail, decoded at the tile's size
    Component {
        id: wallFace
        Kirigami.ShadowedImage {
            source: face.item && face.item.thumb ? "file://" + face.item.thumb : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(face.width * 2, face.height * 2)
            radius: face.radius
            color: "#0b0f16"
            shadow.size: face.u(18)
            shadow.yOffset: face.u(6)
            shadow.color: Qt.rgba(0, 0, 0, 0.45)
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: face.u(8) }
                spacing: face.u(5)
                Repeater {
                    model: face.item ? face.item.onScreens : []
                    Rectangle {
                        required property string modelData
                        width: bt.implicitWidth + face.u(14)
                        height: face.u(20)
                        radius: height / 2
                        color: Qt.rgba(0, 0, 0, 0.6)
                        Text { id: bt; anchors.centerIn: parent; text: modelData; color: "#ffffff"; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: face.u(11) }
                    }
                }
            }
        }
    }

    // ---- a blur style: what it looks like over this screen's wallpaper (matte: the frost and its grain; clear:
    // the wallpaper blurred live, a window's edge showing through), its name on it
    Component {
        id: blurFace
        Item {
            readonly property bool matte: face.item && face.item.style === "matte"
            readonly property bool sharp: face.item && face.item.style === "none"
            readonly property var v: face.rice.values || ({})
            Kirigami.ShadowedRectangle {
                anchors.fill: parent
                radius: face.radius
                color: "#0b0f16"
                shadow.size: face.u(18)
                shadow.yOffset: face.u(6)
                shadow.color: Qt.rgba(0, 0, 0, 0.45)
            }
            Item {
                id: pic
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: blurMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                Image {         // what's behind: the frost (matte), or the wallpaper, softly blurred (clear)
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: parent.parent.matte ? (parent.parent.v._glassFull ? "file://" + parent.parent.v._glassFull : "")
                                                : (face.rice.wallpaper ? "file://" + face.rice.wallpaper : "")
                    sourceSize.width: 480
                    layer.enabled: !parent.parent.matte && !parent.parent.sharp
                    layer.effect: MultiEffect { blurEnabled: true; blur: 0.55; blurMax: 32; saturation: 0.15 }
                }
                Rectangle {     // a window's edge under the clear blur: it shows things through
                    visible: !parent.parent.matte && !parent.parent.sharp
                    x: parent.width * 0.52; y: parent.height * 0.16
                    width: parent.width * 0.4; height: parent.height * 0.5
                    radius: face.u(8)
                    color: C.alpha("#ffffff", 0.16)
                    border.width: 1
                    border.color: C.alpha("#ffffff", 0.22)
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 0.5; blurMax: 16 }
                }
                Image {         // the grain (matte)
                    anchors.fill: parent
                    visible: parent.parent.matte
                    source: visible ? Prefs.grain : ""
                    fillMode: Image.Tile
                    smooth: false
                    opacity: 0.09
                }
                Rectangle {     // the veil (no blur: only the dark shade, from the bottom)
                    anchors.fill: parent
                    color: parent.parent.sharp ? "transparent" : C.alpha(face.rice.surfaceLowest, parent.parent.matte ? 0.18 : 0.34)
                    gradient: parent.parent.sharp ? shade : null
                    Gradient {
                        id: shade
                        GradientStop { position: 0; color: C.alpha(face.rice.surfaceLowest, 0) }
                        GradientStop { position: 0.45; color: C.alpha(face.rice.surfaceLowest, 0.18) }
                        GradientStop { position: 1; color: C.alpha(face.rice.surfaceLowest, 0.6) }
                    }
                }
            }
            Rectangle { id: blurMask; anchors.fill: parent; radius: face.radius; visible: false; layer.enabled: true }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: face.u(14) }
                horizontalAlignment: Text.AlignHCenter
                text: face.item ? face.item.name : ""
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.4)
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: face.u(17)
            }
        }
    }

    // ---- a card: a theme, a new one, a swatch
    Component {
        id: cardFace
        Item {
            Rectangle {
                anchors.fill: parent
                radius: face.radius
                color: face.kind === "save" ? C.alpha(face.rice.fg, 0.04) : C.mix(face.rice.surface, "#000000", 0.2)
                border.width: face.kind === "save" ? Math.max(1.5, face.u(1.5)) : 1
                border.color: C.alpha(face.rice.edge, face.kind === "save" ? 0.2 : 0.1)
                gradient: face.kind === "mood" ? moodGradient : null
                RectangularShadow { z: -1; anchors.fill: parent; radius: face.radius; blur: face.u(20); offset.y: face.u(6); spread: -face.u(8); color: Qt.rgba(0, 0, 0, 0.4); visible: face.kind !== "save" }
            }
            Gradient {
                id: moodGradient
                readonly property var palettes: ({
                    neon: ["#ff3d8b", "#7a5cff", "#00e5ff"], soft: ["#9fb8e8", "#c7a8e0", "#f0c3c7"], light: ["#f4f6fb", "#dfe6f2", "#c9d6ea"],
                    void: ["#05070c", "#10131c", "#3a4a7a"], graphite: ["#2a2e36", "#4a505c", "#8a93a3"] })
                readonly property var s: face.item && palettes[face.item.mood] ? palettes[face.item.mood] : ["#333", "#555", "#777"]
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: moodGradient.s[0] }
                GradientStop { position: 0.55; color: moodGradient.s[1] }
                GradientStop { position: 1; color: moodGradient.s[2] }
            }
            Loader {        // a theme: its screens as they sat
                active: face.kind === "look"
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.14
                width: parent.width * 0.8
                height: parent.height * 0.5
                sourceComponent: LayoutGlyph { pal: face.rice; layout: face.item.layout || [] }
            }
            Text {
                visible: face.kind === "look" || face.kind === "save"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: face.u(14) }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: visible && face.item ? face.item.name : ""
                color: face.kind === "save" ? face.rice.fgDim : face.rice.fg
                font.family: face.kind === "look" ? Tokens.font.display : Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: face.u(face.kind === "look" ? 17 : 14)
            }
            Text {
                visible: face.kind === "save" || face.kind === "colours-auto" || (face.kind === "size" && face.item.v === "auto")
                anchors.centerIn: parent
                anchors.verticalCenterOffset: face.kind === "save" ? -face.u(10) : 0
                text: face.kind === "save" ? "add" : face.kind === "colours-auto" ? "auto_awesome" : "fit_screen"
                color: face.kind === "save" ? face.rice.fgDim : face.rice.fg
                font.family: Tokens.font.icons
                font.pixelSize: face.u(40)
            }
            Rectangle {     // an accent
                visible: face.kind === "accent"
                anchors.centerIn: parent
                width: parent.width * 0.52; height: width; radius: width / 2
                color: face.item && face.item.hex ? face.item.hex : "transparent"
                border.width: 1
                border.color: C.alpha("#ffffff", 0.3)
            }
            Text {          // a size
                visible: (face.kind === "size" || face.kind === "lsize") && face.item.v !== "auto"
                anchors.centerIn: parent
                text: "Aa"
                color: face.rice.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: face.u(26 * (0.62 + (((face.kind === "size" || face.kind === "lsize") && typeof face.item.v === "number" ? face.item.v : 1) - 1) * 1.1))
            }
            Loader {        // a keyboard, lit the way it would be
                active: face.kind === "light" || face.kind === "kb"
                x: parent.width * 0.12
                y: parent.height * 0.3
                width: parent.width * 0.76
                height: parent.height * 0.4
                sourceComponent: Rectangle {
                    radius: face.u(8)
                    color: "#0a0d13"
                    border.width: 1
                    border.color: C.alpha("#ffffff", 0.12)
                    Grid {
                        anchors.fill: parent
                        anchors.margins: face.u(4)
                        columns: 10
                        spacing: 2
                        Repeater {
                            model: 30
                            Rectangle {
                                required property int index
                                readonly property real x01: (index % 10) / 9
                                width: (parent.width - 18) / 10
                                height: (parent.height - 4) / 3
                                radius: 2
                                readonly property string e: face.item ? face.item.effect : ""
                                color: e === "off" ? "#1a1f2a"
                                     : e === "spectrum" ? Qt.hsva((x01 * 0.85 + Math.floor(index / 10) * 0.07) % 1, 0.8, 1, 1)
                                     : e === "gradient" ? C.mix(face.rice.primary, face.rice.tertiary, x01)
                                     : e === "breathe" ? C.mix(face.rice.primary, "#000000", 0.6 - Math.sin(x01 * Math.PI) * 0.6)
                                     : face.rice.primary
                            }
                        }
                    }
                }
            }
        }
    }

    // in use now
    Rectangle {
        visible: !!(face.item && face.item.current) && face.kind !== "save"
        anchors { right: parent.right; top: parent.top; margins: face.u(9) }
        width: face.u(20); height: width; radius: width / 2
        color: face.rice.primary
        Text { anchors.centerIn: parent; text: "check"; color: face.rice.onPrimary; font.family: Tokens.font.icons; font.pixelSize: face.u(15); font.weight: Font.Bold }
    }
}
