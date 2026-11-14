import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// One tile of Atom Home. A row of covers is all covers, a row of icons is all icons:
//   cover   a game with Steam's art: its cover
//   poster  an app in a row of covers: a cover of its own (its colour, its icon's light, the icon on it)
//   float   an app in a row of icons: the icon alone over a soft shadow; a glass plate comes with the focus
//   theme   a Theme page item (ThemeFace draws it)
// The focused tile (of the active row) grows, wears the ring and glows in its own colour (the palette's
// glow sets how much), and a glint crosses it once as it takes the focus.
// Cheap by design (a row can hold hundreds, and the strip makes and reuses them as it moves): each look is
// built only for the tiles that wear it, the glow and the glint only around the focus, and the colour is
// read off the image only where it's shown (a poster's fill, a focused tile's glow).
Item {
    id: tile
    required property var item
    required property string shape          // the row's: "square" | "portrait" | "poster" | "wall" | "look" | ...
    required property RicePalette rice
    property bool labeled: false
    property bool current: false            // the row's focus
    property bool rowActive: false          // the row has the keyboard's focus
    property real unit: 1
    property int focusMs: Tokens.ms(380)
    signal activated()
    signal pointed()
    signal menu()

    readonly property bool focused: current && rowActive
    readonly property var roles: item ? item.roles : null      // the launcher's menu reads favoriteId and actionList
    readonly property bool hasArt: !!(item && item.art && item.art.portrait)
    readonly property bool themed: !!(item && item.kind)
    readonly property string look: themed ? "theme" : shape === "square" ? "float" : hasArt ? "cover" : "poster"
    readonly property real radius: Math.round(22 * unit)
    readonly property color ring: rice.light ? rice.fg : "#ffffff"
    readonly property real glowK: Math.max(0.4, rice.glow)
    function u(n) { return Math.round(n * unit) }

    // its colour, read only where it shows: a poster's fill, or the glow of a tile that has had the focus
    property bool sampled: false
    onFocusedChanged: if (focused) { sampled = true; glint.restart() }
    onItemChanged: sampled = focused
    readonly property string colorSource: !item ? ""
                                        : themed ? (item.thumb ? "file://" + item.thumb : "")
                                        : hasArt ? item.art.portrait : item.icon
    Kirigami.ImageColors {
        id: colors
        source: tile.look === "poster" || tile.sampled ? tile.colorSource : ""
    }
    readonly property color tint: C.appTint(colors, rice.primary)
    readonly property color glowColor: themed && item.kind === "accent" ? item.hex : themed && !item.thumb ? rice.primary : tint

    property real enter: 0                  // the stage's entrance: how far right it still is
    transform: Translate { x: tile.enter }
    z: focused ? 2 : 0
    scale: focused ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: tile.focusMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

    // the light it gives off when focused, in its own colour (made while it shows)
    property real glowV: focused ? 1 : 0
    Behavior on glowV { NumberAnimation { duration: tile.focusMs } }
    Loader {
        anchors.fill: parent
        active: tile.glowV > 0
        sourceComponent: RectangularShadow {
            radius: tile.radius
            blur: tile.u(52)
            spread: -tile.u(6)
            color: C.alpha(tile.glowColor, 0.8 * tile.glowK)
            opacity: tile.glowV
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: tile.look === "cover" ? coverLook : tile.look === "poster" ? posterLook
                       : tile.look === "float" ? floatLook : tile.look === "theme" ? themeLook : null
    }

    // ---- cover: the game's own art
    Component {
        id: coverLook
        Kirigami.ShadowedImage {
            source: tile.hasArt ? tile.item.art.portrait : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(tile.width * 2, tile.height * 2)
            radius: tile.radius
            color: "#0b0f16"
            shadow.size: tile.u(22)
            shadow.yOffset: tile.u(8)
            shadow.color: Qt.rgba(0, 0, 0, 0.5)
        }
    }

    // ---- poster: an app's cover of its own, in deep jewel tones of its colour
    Component {
        id: posterLook
        Item {
            RectangularShadow { anchors.fill: parent; radius: tile.radius; blur: tile.u(24); offset.y: tile.u(8); spread: -tile.u(8); color: Qt.rgba(0, 0, 0, 0.45) }
            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: C.mix(tile.tint, "#0b0f16", 0.42) }
                    GradientStop { position: 1; color: C.mix(tile.tint, "#05070c", 0.8) }
                }
                border.width: 1
                border.color: C.alpha(tile.rice.edge, 0.14)
            }
            Item {      // the icon's own light, a huge soft copy of it
                anchors.fill: parent
                clip: true
                Kirigami.Icon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -parent.height * 0.1
                    width: parent.width * 1.15; height: width
                    source: tile.item ? tile.item.icon : ""
                    opacity: 0.45
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 48; saturation: 0.5 }
                }
            }
            Rectangle {     // light at the top
                anchors.fill: parent
                radius: tile.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: C.alpha("#ffffff", 0.12) }
                    GradientStop { position: 0.4; color: C.alpha("#ffffff", 0) }
                }
            }
            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.4 - height / 2
                width: Math.round(parent.width * 0.5); height: width
                source: tile.item ? tile.item.icon : ""
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.7; shadowVerticalOffset: tile.u(6) }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: tile.u(12) }
                horizontalAlignment: Text.AlignHCenter
                text: tile.item ? tile.item.name : ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: "#ffffff"
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: tile.u(13)
            }
        }
    }

    // ---- float: the icon alone; a glass plate only with the focus
    Component {
        id: floatLook
        Item {
            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                color: C.alpha(tile.rice.fg, 0.1)
                border.width: 1
                border.color: C.alpha(tile.rice.edge, 0.16)
                opacity: tile.glowV
                visible: opacity > 0
            }
            RectangularShadow {         // its shadow on the ground
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.82
                width: parent.width * 0.5
                height: Math.max(2, parent.height * 0.07)
                radius: height / 2
                blur: tile.u(10)
                color: Qt.rgba(0, 0, 0, 0.5)
                opacity: tile.focused ? 0.4 : 0.85
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -parent.height * 0.03
                width: Math.round(parent.width * (tile.focused ? 0.72 : 0.68)); height: width
                Behavior on width { NumberAnimation { duration: tile.focusMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                source: tile.item ? tile.item.icon : ""
            }
        }
    }

    // ---- a Theme page item
    Component {
        id: themeLook
        ThemeFace { item: tile.item; rice: tile.rice; unit: tile.unit; radius: tile.radius }
    }

    // ---- the focus: the ring, and a glint once (made only while it crosses)
    Rectangle {
        anchors.fill: parent
        radius: tile.radius
        color: "transparent"
        border.width: Math.max(2, tile.u(2.5))
        border.color: tile.ring
        opacity: tile.focused ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Math.round(tile.focusMs * 0.6) } }
    }
    property real glintX: -1
    NumberAnimation {
        id: glint
        target: tile; property: "glintX"
        from: 0; to: 1
        duration: Tokens.ms(900)
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0.6, 0.3, 1, 1, 1]
        onStopped: tile.glintX = -1
    }
    Loader {
        anchors.fill: parent
        active: glint.running
        sourceComponent: Item {
            clip: true
            Rectangle {
                width: parent.width * 0.55
                height: parent.height * 2
                y: -parent.height / 2
                x: -width + tile.glintX * (parent.width + width)
                rotation: 18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: C.alpha("#ffffff", 0.22) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }

    Text {      // its name, under it (rows of many apps)
        visible: tile.labeled
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + tile.u(11)
        width: parent.width + tile.u(16)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tile.labeled && tile.item ? tile.item.name : ""
        color: tile.focused ? tile.rice.fg : tile.rice.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.Medium
        font.pixelSize: tile.u(13)
        scale: 1 / tile.scale       // stays its size while the tile grows
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tile.pointed()
        onPositionChanged: if (!tile.focused) tile.pointed()      // moved on it after the rows came to rest
        onClicked: mouse => mouse.button === Qt.RightButton ? tile.menu() : tile.activated()
    }
}
