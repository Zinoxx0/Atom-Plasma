import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import "Rice"
import "Rice/Color.js" as C

// The bar part of Glimpse: pinned launchers (PinTile), lit when their app runs anywhere.
// On a bar too wide for its screen (Rice/BarFit.qml, step 3) the pins give way: as many as fit stay,
// the rest fold into a folder tile (a 2x2 peek at its apps) that opens them in a popup. The panel
// hands this widget whatever room is left, so it folds exactly as far as it has to, live.
// A panel representation: nothing in here may loop smoothly.
Item {
    id: bar
    property var g                          // the Glimpse root
    readonly property int iconSize: Math.max(16, Math.min(Math.round(Kirigami.Units.iconSizes.medium * g.uiScale), height - 12))
    readonly property int pinW: iconSize + 12
    readonly property int count: g.launchers.count
    // every pin, 1 px apart; folded as far as it goes: one pin and the folder
    readonly property real natural: count > 0 ? count * (pinW + 1) - 1 : 0
    readonly property real tightest: count > 2 ? 2 * pinW + 1 : natural
    // what this widget takes at each fit step (g.riceFit, for BarFit)
    readonly property var fitWidths: [natural, natural, natural, tightest]
    // pins fold only from step 3: until then the numbers on the right go first
    readonly property bool folding: g.fit.step >= 3
    Layout.fillHeight: true
    Layout.minimumWidth: folding ? tightest : natural
    Layout.preferredWidth: natural
    Layout.maximumWidth: natural

    // how many pins the room holds: all, or as many as fit beside the folder (which takes 2 at least)
    readonly property int shown: {
        if (!folding || count <= 2 || width >= natural - 0.5) return count
        const slots = Math.floor((width + 1) / (pinW + 1))
        return Math.max(1, Math.min(count - 2, slots - 1))
    }
    readonly property int foldedCount: count - shown
    onFoldedCountChanged: if (foldedCount === 0) folderOpen = false

    // anything running (or asking for attention) in the folder, for its dot
    readonly property var foldedState: {
        const R = TaskManager.AbstractTasksModel
        let running = false, attention = false
        for (let i = shown; i < count; i++) {
            const idx = g.launchers.index(i, 0)
            const info = g.infoFor(g.launchers.data(idx, R.AppId), g.launchers.data(idx, R.LauncherUrlWithoutIcon), g.running)
            if (info && info.count > 0) running = true
            if (info && info.attention) attention = true
        }
        return { running: running, attention: attention }
    }
    function foldedNames() {
        const R = TaskManager.AbstractTasksModel
        const out = []
        for (let i = shown; i < count; i++) {
            const idx = g.launchers.index(i, 0)
            out.push(g.launchers.data(idx, R.AppName) || g.launchers.data(idx, Qt.DisplayRole) || "")
        }
        return out.filter(n => n).join(" · ")
    }

    DropArea {
        anchors.fill: parent
        onEntered: drag => { drag.accepted = drag.hasUrls && drag.urls.some(u => String(u).endsWith(".desktop")) }
        onDropped: drop => {
            for (const u of drop.urls)
                if (String(u).endsWith(".desktop")) bar.g.addLauncher(bar.g.launcherUrlFor(u))
            drop.acceptProposedAction()
        }
    }
    Row {
        id: launcherRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Repeater {
            model: bar.g.launchers
            delegate: PinTile {
                g: bar.g
                iconSize: bar.iconSize
                height: bar.height
                visible: index < bar.shown
            }
        }

        // the folder: the pins that don't fit, as a 2x2 peek; a click opens them all
        Item {
            id: folder
            visible: bar.foldedCount > 0
            width: bar.pinW
            height: bar.height

            Rectangle {     // hover, as on a pin
                anchors.centerIn: parent
                width: bar.iconSize + 8
                height: width
                radius: Tokens.radius.sm
                color: C.alpha(bar.g.cFg, fma.pressed ? Tokens.alpha.press : fma.containsMouse || bar.folderOpen ? Tokens.alpha.hover : 0)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Rectangle {     // the folder itself: a pane of the bar's glass
                id: pane
                anchors.centerIn: parent
                width: bar.iconSize
                height: width
                radius: Tokens.radius.sm
                color: C.alpha(bar.g.cFg, 0.08)
                border.width: 1
                border.color: C.alpha(bar.g.cFg, fma.containsMouse || bar.folderOpen ? 0.30 : 0.16)
                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                scale: fma.pressed ? 0.92 : fma.containsMouse ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

                Grid {
                    id: peek
                    anchors.centerIn: parent
                    columns: 2
                    readonly property real gap: Math.max(2, Math.round(bar.iconSize / 14))
                    spacing: gap
                    readonly property real cell: Math.floor((pane.width - 3 * gap) / 2)
                    Repeater {
                        model: bar.g.launchers
                        delegate: Kirigami.Icon {
                            required property int index
                            required property var model
                            visible: index >= bar.shown && index < bar.shown + 4
                            width: peek.cell
                            height: width
                            source: model.decoration
                        }
                    }
                }
            }
            Rectangle {     // something in the folder runs: one dot (red: it wants attention)
                visible: bar.foldedState.running || bar.foldedState.attention
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: 4; height: 4; radius: 2
                color: bar.foldedState.attention ? bar.g.cRed : C.alpha(bar.g.cFg, 0.75)
            }

            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                active: !bar.folderOpen
                mainText: i18np("1 more pinned app", "%1 more pinned apps", bar.foldedCount)
                subText: bar.foldedCount > 0 ? bar.foldedNames() : ""
                MouseArea {
                    id: fma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        // a click on the folder while it's open closes it (the popup loses focus first,
                        // then this click would open it again)
                        if (!bar.folderOpen && Date.now() - bar.closedAt < 300) return
                        bar.folderOpen = !bar.folderOpen
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ the open folder
    property bool folderOpen: false
    property real closedAt: 0
    property int menusOpen: 0               // a pin's context menu open in the folder
    onFolderOpenChanged: if (!folderOpen) { closedAt = Date.now(); menusOpen = 0 }
    Loader {
        active: bar.folderOpen
        sourceComponent: PlasmaCore.PopupPlasmaWindow {
            id: win
            visualParent: folder
            popupDirection: Plasmoid.location === PlasmaCore.Types.TopEdge ? Qt.BottomEdge : Qt.TopEdge
            animated: true
            removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
                ? PlasmaCore.AppletPopup.AtScreenEdges
                : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges
            margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets) ? Kirigami.Units.largeSpacing : 0
            width: pins.implicitWidth + leftPadding + rightPadding
            height: pins.implicitHeight + topPadding + bottomPadding

            mainItem: Row {
                id: pins
                spacing: 1
                focus: true
                Keys.onEscapePressed: bar.folderOpen = false
                Repeater {
                    model: bar.g.launchers
                    delegate: PinTile {
                        g: bar.g
                        iconSize: bar.iconSize
                        height: bar.iconSize + 16
                        visible: index >= bar.shown
                        onActed: bar.folderOpen = false
                        onMenuOpenChanged: bar.menusOpen = Math.max(0, bar.menusOpen + (menuOpen ? 1 : -1))
                    }
                }
            }

            // it closes when it loses focus, except to a pin's own menu (then when that menu closes)
            onActiveChanged: if (!active) closer.restart()
            onVisibleChanged: if (!visible) bar.folderOpen = false
            Timer { id: closer; interval: 100; onTriggered: if (!win.active && bar.menusOpen === 0) bar.folderOpen = false }
            Connections {
                target: bar
                function onMenusOpenChanged() { if (bar.menusOpen === 0) closer.restart() }
            }
            // shown once placed: a window visible from the start flickers in the screen's middle first
            Component.onCompleted: { visible = true; requestActivate() }
        }
    }
}
