import QtQuick
import QtQuick.Effects
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// One app in the opened band. Several windows of it stack up behind the icon (fainter copies,
// fanned to the right) with a count. Where its windows are shows in the icon itself: out on this
// screen it looks as it always does and lights the glass under it; only minimized here it stays
// solid but casts no light; with nothing on this screen it sits a little smaller and darker.
// The lip under it: a glowing bar when the app has the focus, a dot when a window is out here,
// a ring when this screen's windows of it are all minimized.
Item {
    id: tile
    required property int index
    required property var model
    property var g                          // the Glimpse root

    readonly property var proxy: ListView.view ? ListView.view.model : null
    readonly property var tasks: proxy ? proxy.sourceModel : null
    // the app's row in the task model: a group parent when it has several windows
    readonly property var srcIndex: proxy && index >= 0 && g.tick >= 0 ? proxy.mapToSource(proxy.index(index, 0)) : null
    readonly property var st: g.appState(tasks, srcIndex, g.tick)
    readonly property int count: st.count
    readonly property bool active: st.active
    readonly property bool here: st.here
    readonly property bool minimizedHere: st.minimizedHere
    readonly property bool away: st.away
    readonly property string appName: model.AppName || model.display || ""
    readonly property var icon: model.decoration
    readonly property bool hovered: ma.containsMouse
    readonly property color tint: C.appTint(colors, g.cFg)
    Kirigami.ImageColors { id: colors; source: tile.model.decoration }

    property real pop: 0                    // 0 = hidden, 1 = in place
    property int delay: 0
    readonly property int iconY: Math.round((g.barH - g.iconSize) / 2) - 1
    width: g.fitSlot + (name.visible ? name.width + 4 : 0)
    height: g.barH

    // the app's light on the glass under it, only while a window of it is out on this screen: kept to
    // the band, so it never spills past the lip. Brightest for the focused app.
    Item {
        x: Math.round((g.fitSlot - width) / 2)
        width: g.px(84)
        height: g.barH
        clip: true
        opacity: tile.pop * (tile.here ? 1 : 0)
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.base } }
        AppGlow {
            anchors.horizontalCenter: parent.horizontalCenter
            y: g.barH - 6 - height / 2
            width: parent.width
            tint: tile.tint
            strength: (tile.active ? 0.65 : 0.4) * Math.max(0.3, g.pal.glow)
            Behavior on strength { NumberAnimation { duration: Tokens.base } }
        }
    }

    Item {
        id: art
        x: Math.round((g.fitSlot - g.iconSize) / 2)
        y: tile.iconY
        width: g.iconSize
        height: g.iconSize
        opacity: tile.pop
        // hover: a small, well-damped lift; press: a small dip
        property real mag: ma.pressed ? 0.94 : tile.hovered ? 1.07 : 1
        Behavior on mag { SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.002 } }
        // nothing on this screen: a little smaller and darker
        property real far: tile.away ? 1 : 0
        Behavior on far { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        scale: (0.92 + 0.08 * tile.pop) * mag * (1 - 0.14 * far)
        transform: Translate { y: (1 - tile.pop) * g.px(6) }
        layer.enabled: far > 0
        layer.sourceRect: Qt.rect(0, 0, width + 2 * g.px(6) + 2, height)    // room for the stacked copies
        layer.effect: MultiEffect { brightness: -0.42 * art.far; saturation: -0.3 * art.far }

        // the other windows: fainter copies of the icon, fanned out behind it
        Repeater {
            model: Math.min(2, Math.max(0, tile.count - 1))
            delegate: Kirigami.Icon {
                required property int index
                z: -1 - index
                width: g.iconSize
                height: g.iconSize
                x: (index + 1) * g.px(6)
                scale: 1 - (index + 1) * 0.12
                opacity: index ? 0.28 : 0.55
                source: tile.icon
                animated: false
            }
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: tile.icon
            animated: false
        }
    }

    // how many windows, when more than one
    Rectangle {
        visible: tile.count > 1
        x: art.x + g.iconSize - width * 0.55
        y: art.y + g.iconSize - height * 0.7
        height: g.px(14)
        width: Math.max(height, countText.implicitWidth + g.px(8))
        radius: height / 2
        opacity: tile.pop
        color: C.alpha(g.cBezel, 0.92)
        border.width: 1
        border.color: C.alpha(tile.tint, 0.7)
        Text {
            id: countText
            anchors.centerIn: parent
            text: tile.count
            color: g.cFg
            font.family: Tokens.font.ui
            font.pixelSize: g.px(Tokens.size.caption)
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }
    }

    // app name, when enabled in the settings
    Text {
        id: name
        visible: g.cfg.showNames
        x: g.fitSlot - 4
        anchors.verticalCenter: art.verticalCenter
        width: Math.min(implicitWidth, g.px(120))
        text: tile.appName
        elide: Text.ElideRight
        opacity: tile.pop
        color: tile.away ? g.cFgDim : g.cFg
        font.family: Tokens.font.ui
        font.pixelSize: g.px(Tokens.size.label)
        font.weight: tile.active ? Font.DemiBold : Font.Medium
    }

    // focused: a lit stretch of the lip under the icon
    Rectangle {
        x: art.x + (g.iconSize - width) / 2
        y: g.barH - height - 1
        width: tile.active ? g.px(16) : 0
        height: 3
        radius: 1.5
        opacity: tile.pop
        visible: width > 0.5
        Behavior on width { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: g.cPrimary }
            GradientStop { position: 1; color: g.cTertiary }
        }
        layer.enabled: tile.active
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: g.cPrimary; shadowBlur: 0.6; shadowOpacity: 0.9; shadowVerticalOffset: 0; shadowHorizontalOffset: 0 }
    }
    // a window out here: dot; this screen's windows of it all minimized: ring
    Rectangle {
        x: art.x + (g.iconSize - width) / 2
        y: g.barH - height - 1
        visible: !tile.active && (tile.here || tile.minimizedHere)
        width: 4
        height: 4
        radius: 2
        opacity: tile.pop
        color: tile.minimizedHere ? "transparent" : C.alpha(g.cFg, 0.85)
        border.width: tile.minimizedHere ? 1 : 0
        border.color: C.alpha(g.cFg, 0.6)
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onContainsMouseChanged: {
            if (containsMouse) g.hoverTile = tile
            else if (g.hoverTile === tile) g.hoverTile = null
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) menu.openRelative()
            else if (mouse.button === Qt.MiddleButton) tile.tasks.requestNewInstance(tile.srcIndex)
            else g.actOnTile(tile.tasks, tile.srcIndex)
        }
    }
    PlasmaExtras.Menu {
        id: menu
        visualParent: tile
        readonly property string url: String(tile.model.LauncherUrlWithoutIcon || "")
        onStatusChanged: {
            g.menuOpen = status === PlasmaExtras.Menu.Open || status === PlasmaExtras.Menu.Opening
            if (!g.menuOpen && !g.shelfHovered) g.closeIn(g.handOff)
        }
        PlasmaExtras.MenuItem {
            visible: menu.url !== ""
            text: g.hasLauncher(menu.url) ? i18n("Unpin from bar") : i18n("Pin to bar")
            icon: g.hasLauncher(menu.url) ? "window-unpin" : "window-pin"
            onClicked: g.hasLauncher(menu.url) ? g.removeLauncher(menu.url) : g.addLauncher(menu.url)
        }
        PlasmaExtras.MenuItem {
            text: i18n("New window")
            icon: "window-new"
            onClicked: tile.tasks.requestNewInstance(tile.srcIndex)
        }
        PlasmaExtras.MenuItem {
            text: tile.count > 1 ? i18n("Close all %1 windows", tile.count) : i18n("Close window")
            icon: "window-close"
            onClicked: g.closeApp(tile.tasks, tile.srcIndex)
        }
    }

    // fade and rise into place, a quick ripple from the left, when the band opens; fade out when it
    // closes. Caught while still folding away, it comes straight back from where it is.
    Connections {
        target: g
        function onShelfRevealed() {
            tile.delay = tile.pop > 0.05 ? 0 : Math.min(8, Math.round(tile.mapToItem(null, 0, 0).x / g.fitSlot)) * Tokens.ms(12)
            foldAnim.stop()
            popAnim.restart()
        }
        function onShelfClosing() {
            popAnim.stop()
            foldAnim.restart()
        }
    }
    SequentialAnimation {
        id: popAnim
        PauseAnimation { duration: tile.delay }
        NumberAnimation { target: tile; property: "pop"; to: 1; duration: Tokens.base; easing.type: Easing.OutQuart }
    }
    NumberAnimation { id: foldAnim; target: tile; property: "pop"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit }
    // a window that shows up while the band is open comes straight in
    Component.onCompleted: if (g.shelfOpen && g.shelfMapped) { tile.delay = 0; popAnim.restart() }
}
