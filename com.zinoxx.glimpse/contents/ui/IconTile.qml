import QtQuick
import QtQuick.Effects
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// One app in the opened band. Several windows of it stack up behind the icon (fainter copies,
// fanned to the right) with a count; the lip under it lights up: a glowing bar when the app has
// the focus, a dot when a window is out on this screen, a ring when all of them are minimized.
// A tag in the corner names the screen its windows live on when none is here.
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
    readonly property bool minimized: st.minimized
    readonly property var where: st.where
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

    Item {
        id: art
        x: Math.round((g.fitSlot - g.iconSize) / 2)
        y: tile.iconY
        width: g.iconSize
        height: g.iconSize
        opacity: tile.pop * (tile.minimized ? 0.5 : tile.here || tile.count === 0 ? 1 : 0.9)
        // hover: a small, well-damped lift; press: a small dip
        property real mag: ma.pressed ? 0.94 : tile.hovered ? 1.07 : 1
        Behavior on mag { SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.002 } }
        scale: (0.92 + 0.08 * tile.pop) * mag
        transform: Translate { y: (1 - tile.pop) * g.px(6) }

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

    // lives on another screen: a tag in the corner (the laptop is a glyph, others 4K / 2K / HD)
    Rectangle {
        id: tag
        readonly property bool laptop: g.isLaptop(tile.where)
        visible: !tile.here && !tile.minimized && tile.where !== null
        x: Math.min(tile.width - width, art.x + g.iconSize - width * 0.6)
        y: Math.max(1, art.y - g.px(3))
        height: g.px(14)
        width: Math.max(height, tagText.implicitWidth + g.px(8))
        radius: height / 2
        opacity: tile.pop
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: g.cPrimary }
            GradientStop { position: 1; color: g.cTertiary }
        }
        Text {
            id: tagText
            anchors.centerIn: parent
            text: tag.laptop ? "laptop_chromebook" : g.screenShort(tile.where)
            color: g.cOnPrimary
            font.family: tag.laptop ? Tokens.font.icons : Tokens.font.ui
            font.pixelSize: tag.laptop ? g.px(12) : g.px(Tokens.size.caption)
            font.weight: Font.Black
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
        opacity: tile.pop * (tile.minimized ? 0.5 : 1)
        color: tile.here ? g.cFg : g.cFgDim
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
    // a window here: dot; all minimized: ring
    Rectangle {
        x: art.x + (g.iconSize - width) / 2
        y: g.barH - height - 1
        visible: !tile.active && (tile.here || tile.minimized)
        width: 4
        height: 4
        radius: 2
        opacity: tile.pop
        color: tile.minimized ? "transparent" : C.alpha(g.cFg, 0.85)
        border.width: tile.minimized ? 1 : 0
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

    // fade and rise into place, one after another, when the band opens; fade out when it closes
    Connections {
        target: g
        function onShelfRevealed() {
            tile.delay = Tokens.ms(40) + Math.min(12, Math.round(tile.mapToItem(null, 0, 0).x / g.fitSlot)) * Tokens.ms(16)
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
        PropertyAction { target: tile; property: "pop"; value: 0 }
        PauseAnimation { duration: tile.delay }
        NumberAnimation { target: tile; property: "pop"; to: 1; duration: Tokens.base; easing.type: Easing.OutQuart }
    }
    NumberAnimation { id: foldAnim; target: tile; property: "pop"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit }
    // a window that shows up while the band is open comes straight in
    Component.onCompleted: if (g.shelfOpen && g.shelfMapped) { tile.delay = 0; popAnim.restart() }
}
