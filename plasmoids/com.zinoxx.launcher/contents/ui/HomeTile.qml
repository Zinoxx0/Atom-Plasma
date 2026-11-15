import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Rice

// One tile of Atom Home. A row of covers is all covers, a row of icons is all icons:
//   cover   a game with Steam's art: its cover
//   poster  an app in a row of covers: a cover of its own (its colour, its icon's light, the icon on it)
//   float   an app in a row of icons: the icon alone over a soft shadow; a glass plate comes with the focus
//   theme   a Theme page item (ThemeFace draws it)
//   slider  a Theme page size (ThemeSlider draws it): drag it, or left and right a step at a time (applied once
//           the keys pause, or at Enter); `slid(v)` says where it was let go
// The focused tile (of the active row) lifts a little, wears the ring (a white line just outside it, with a
// gap, so it never covers the art) and glows in its own colour (the palette's glow sets how much); a glint
// crosses it once as it takes the focus. Under the pointer (before the focus settles on it, or in a row
// behind) it only brightens: hovered and focused never look alike. While the pointer is the input in use it
// carries its own actions in its top corner (pin, and "..." = the right click's menu): a click launches,
// so nothing has to be reached across other tiles.
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
    property bool pointerMode: false        // the pointer is the input in use (keys or a pad hide its hover)
    property bool pinned: false
    property bool expanded: true            // a group's header: its group is open
    readonly property bool wide: !!(item && item.ctl === "group")
    readonly property bool slider: !!(item && item.slider)
    readonly property bool flat: wide || slider             // (wide tiles don't lift or glow: the ring alone)
    readonly property bool canPin: !!(item && !item.kind && !item.ctl && item.favId)
    readonly property bool hasMenu: !!(item && !item.ctl && (item.model || item.kind === "look"))
    property real unit: 1
    property int focusMs: Tokens.ms(380)
    signal activated()
    signal pointed(point at)                // the pointer is over it (where, in the window)
    signal pointerOut()
    signal menu()
    signal pinToggle()
    signal slid(real v)

    readonly property bool focused: current && rowActive
    readonly property bool pointerOn: pointerMode && (hit.containsMouse || corner.hot)
    readonly property bool hovered: pointerOn && !focused
    readonly property var roles: item ? item.roles : null      // the launcher's menu reads favoriteId and actionList
    readonly property bool hasArt: !!(item && item.art && item.art.portrait)
    readonly property bool themed: !!(item && item.kind)
    readonly property bool control: !!(item && item.ctl)      // "Show more" / "Show less" (HomeRow's)
    readonly property string look: control ? "ctl" : slider ? "slider" : themed ? "theme" : shape === "square" ? "float" : hasArt ? "cover" : "poster"
    readonly property real radius: Math.round(20 * unit)
    readonly property color ring: rice.light ? rice.fg : "#ffffff"
    readonly property real ringGap: Math.max(3, u(4))          // between the tile and its ring
    readonly property real ringW: Math.max(2, u(2.5))
    readonly property real glowK: Math.max(0.4, rice.glow)
    function u(n) { return Math.round(n * unit) }

    // its colour, read only where it shows: a poster's fill, or the glow of a tile that has had the focus
    property bool sampled: false
    onFocusedChanged: if (focused) { sampled = true; glint.restart() }
    onItemChanged: {
        sampled = focused
        if (!isNaN(sliding) && item && Math.abs(item.v - sliding) < 0.001) sliding = NaN     // (applied: the item says it now)
    }
    readonly property string colorSource: !item || item.ctl ? ""
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
    scale: flat ? 1 : focused ? 1.07 : hovered ? 1.025 : 1
    Behavior on scale { NumberAnimation { duration: tile.focusMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

    // the light it gives off when focused, in its own colour (made while it shows)
    property real glowV: focused && !flat ? 1 : 0
    Behavior on glowV { NumberAnimation { duration: tile.focusMs } }
    Loader {
        anchors.fill: parent
        active: tile.glowV > 0
        sourceComponent: RectangularShadow {
            radius: tile.radius
            blur: tile.u(52)
            spread: -tile.u(6)
            color: C.alpha(tile.glowColor, 0.65 * tile.glowK)
            opacity: tile.glowV
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: tile.look === "ctl" ? ctlLook : tile.look === "cover" ? coverLook : tile.look === "poster" ? posterLook
                       : tile.look === "float" ? floatLook : tile.look === "theme" ? themeLook : tile.look === "slider" ? sliderLook : null
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
                font.pixelSize: tile.u(14)
            }
        }
    }

    // ---- float: the icon on a faint glass plate (every one: the focus brightens it, it doesn't appear)
    Component {
        id: floatLook
        Item {
            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                color: C.alpha(tile.rice.fg, 0.045 + 0.075 * tile.glowV + (tile.hovered ? 0.035 : 0))
                border.width: 1
                border.color: C.alpha(tile.rice.edge, 0.08 + 0.08 * tile.glowV)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.62); height: width
                source: tile.item ? tile.item.icon : ""
            }
        }
    }

    // ---- "Show more" / "Show less": a glass plate with its chevron (and, unlabeled rows, its words on it)
    Component {
        id: ctlLook
        Item {
            // a group's header: the whole bar (icon, title, what's in it, the chevron)
            Row {
                visible: tile.wide
                anchors { left: parent.left; leftMargin: tile.u(22); verticalCenter: parent.verticalCenter }
                spacing: tile.u(16)
                Text { anchors.verticalCenter: parent.verticalCenter; text: tile.item ? tile.item.icon : ""; color: tile.rice.primary
                       font.family: Tokens.font.icons; font.pixelSize: tile.u(28) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: tile.item ? tile.item.name : ""; color: tile.rice.fg
                       font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: tile.u(23) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: tile.item && tile.item.meta ? tile.item.meta[0] : ""; color: tile.rice.fgDim
                       font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: tile.u(16) }
            }
            Text {
                visible: tile.wide
                anchors { right: parent.right; rightMargin: tile.u(22); verticalCenter: parent.verticalCenter }
                text: "expand_more"
                rotation: tile.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                color: tile.rice.fg
                font.family: Tokens.font.icons
                font.pixelSize: tile.u(30)
            }
            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                color: C.alpha(tile.rice.fg, (tile.wide ? 0.05 : 0.06) + 0.07 * (tile.focused ? 1 : 0) + (tile.hovered ? 0.04 : 0))
                border.width: 1
                border.color: C.alpha(tile.rice.edge, 0.12 + 0.08 * tile.glowV)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Column {
                visible: !tile.wide
                anchors.centerIn: parent
                spacing: tile.u(2)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.item ? tile.item.icon : ""
                    color: tile.rice.fg
                    font.family: Tokens.font.icons
                    font.pixelSize: tile.u(tile.labeled ? 34 : 30)
                }
                Text {
                    visible: !tile.labeled
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.item ? tile.item.name : ""
                    color: tile.rice.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: tile.u(15)
                }
                Text {
                    visible: !tile.labeled && !!tile.item && tile.item.ctl === "more"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.item && tile.item.meta ? tile.item.meta[0] : ""
                    color: tile.rice.fgDim
                    font.family: Tokens.font.ui
                    font.pixelSize: tile.u(13)
                }
            }
        }
    }

    // ---- a Theme page item
    Component {
        id: themeLook
        ThemeFace { item: tile.item; rice: tile.rice; unit: tile.unit; radius: tile.radius }
    }

    // ---- a size slider: where it is while it's moved (NaN: where the item says), its track's ends (ThemeSlider
    // draws it there; the pointer is read against them)
    property real sliding: NaN
    property bool dragging: false
    readonly property real sliderValue: !isNaN(sliding) ? sliding : item && item.slider ? item.v : 0
    readonly property real trackL: u(158)
    readonly property real trackR: width - u(44)
    function snap(v) { const it = item; return Math.round(Math.round(Math.max(it.min, Math.min(it.max, v)) / it.step) * it.step * 100) / 100 }
    function slideAt(x) { sliding = snap(item.min + (item.max - item.min) * Math.max(0, Math.min(1, (x - trackL) / Math.max(1, trackR - trackL)))) }
    function nudge(dx) { if (!slider) return; sliding = snap((isNaN(sliding) ? item.v : sliding) + dx * item.step); settle.restart() }
    function commitNow() {
        settle.stop()
        if (isNaN(sliding)) return
        if (Math.abs(sliding - item.v) < 0.001) sliding = NaN
        else slid(sliding)
    }
    function cancelSlide() { settle.stop(); dragging = false; sliding = NaN }
    Timer { id: settle; interval: 650; onTriggered: tile.commitNow() }        // (the keys paused: applied)
    Component {
        id: sliderLook
        ThemeSlider {
            item: tile.item; rice: tile.rice; unit: tile.unit; radius: tile.radius
            value: tile.sliderValue; trackL: tile.trackL; trackR: tile.trackR
            focused: tile.focused; hovered: tile.pointerMode && hit.containsMouse; dragging: tile.dragging
        }
    }

    // ---- the focus: the ring (outside, with a gap), and a glint once (made only while it crosses)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -(tile.ringGap + tile.ringW)
        radius: tile.radius + tile.ringGap + tile.ringW
        color: "transparent"
        border.width: tile.ringW
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
        y: parent.height + tile.u(17)
        width: parent.width + tile.u(16)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: tile.labeled && tile.item ? tile.item.name : ""
        color: tile.focused ? tile.rice.fg : tile.rice.fgDim
        font.family: Tokens.font.ui
        font.weight: Font.Medium
        font.pixelSize: tile.u(15)
        scale: 1 / tile.scale       // stays its size while the tile grows
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }

    // its own actions, in its corner, while the pointer is on it
    Row {
        id: corner
        readonly property bool hot: pinB.hot || moreB.hot
        // inside the corner of a big tile (a cover, a wallpaper); on a small one (an app's icon) badges on
        // its corner, half outside, so they never sit on the icon
        readonly property bool small: tile.width < tile.u(140)
        anchors { right: parent.right; top: parent.top
                  rightMargin: small ? -Math.round(pinB.width * 0.4) : tile.u(8); topMargin: small ? -Math.round(pinB.width * 0.4) : tile.u(8) }
        spacing: tile.u(small ? 4 : 6)
        z: 5
        opacity: tile.pointerOn ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        CornerButton { id: pinB; rice: tile.rice; unit: tile.unit; shown: tile.canPin; icon: "push_pin"; on: tile.pinned
                       tip: tile.pinned ? "Unpin" : "Pin"; onClicked: tile.pinToggle() }
        CornerButton { id: moreB; rice: tile.rice; unit: tile.unit; shown: tile.hasMenu; icon: "more_horiz"; tip: "More"; onClicked: tile.menu() }
    }
    component CornerButton: Rectangle {
        id: cb
        property RicePalette rice: null     // (an inline component sees no ids of its file: all passed in)
        property real unit: 1
        property string icon: ""
        property string tip: ""
        property bool on: false
        property bool shown: true
        readonly property bool hot: cbm.containsMouse
        signal clicked()
        visible: shown
        width: Math.round(28 * unit); height: width; radius: width / 2
        color: hot ? Qt.rgba(0.06, 0.07, 0.1, 0.96) : Qt.rgba(0.06, 0.07, 0.1, 0.86)
        border.width: 1
        border.color: C.alpha("#ffffff", hot ? 0.4 : 0.18)
        scale: cbm.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Text {
            anchors.centerIn: parent
            text: cb.icon
            color: cb.on ? cb.rice.primary : "#ffffff"
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(17 * cb.unit)
            font.variableAxes: { "FILL": cb.on ? 1 : 0 }
        }
        MouseArea { id: cbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.clicked() }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: tile.slider        // (a slider's drag is its own: the page doesn't scroll with it)
        // the stage decides whether the pointer means it (it rests here, or is slowing down on it) or is
        // only passing over on its way somewhere else (to the hero's buttons): only the first takes the focus
        onEntered: tile.pointed(mapToItem(null, mouseX, mouseY))
        onPositionChanged: mouse => {
            if (tile.dragging) tile.slideAt(mouse.x)
            // (dragging too: the stage keeps knowing where the pointer is, so what slides under it after a size
            // is applied isn't taken for a move)
            if (tile.dragging || !tile.focused) tile.pointed(mapToItem(null, mouseX, mouseY))
        }
        onExited: tile.pointerOut()
        // a slider: pressed, it takes the focus and the value under the pointer; let go, it's applied
        onPressed: mouse => { if (tile.slider && mouse.button === Qt.LeftButton) { tile.activated(); tile.dragging = true; tile.slideAt(mouse.x) } }
        onReleased: if (tile.dragging) { tile.dragging = false; tile.commitNow() }
        onCanceled: if (tile.dragging) { tile.dragging = false; tile.commitNow() }
        onClicked: mouse => { if (tile.slider) return; mouse.button === Qt.RightButton ? tile.menu() : tile.activated() }
    }
}
