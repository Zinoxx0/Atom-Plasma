import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// The bar part of Glimpse: pinned launchers, lit when their app runs anywhere (dots, a glow or an
// underline, in the app's own colour). A panel representation: nothing in here may loop smoothly,
// so the "launching" wait is a stepped blink.
Item {
    id: bar
    property var g                          // the Glimpse root
    readonly property int iconSize: Math.max(16, Math.min(Math.round(Kirigami.Units.iconSizes.medium * g.uiScale), height - 12))
    Layout.fillHeight: true
    Layout.minimumWidth: launcherRow.implicitWidth
    Layout.preferredWidth: launcherRow.implicitWidth
    Layout.maximumWidth: launcherRow.implicitWidth

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
            delegate: Item {
                id: lb
                required property int index
                required property var model
                readonly property var g: bar.g
                readonly property var info: g.infoFor(model.AppId, model.LauncherUrlWithoutIcon, g.running)
                readonly property int count: info ? info.count : 0
                readonly property bool focused: info ? info.active : false
                readonly property bool attention: info ? info.attention : false
                readonly property color tint: C.appTint(colors, g.cFg)     // the app's own colour, as in the top band
                Kirigami.ImageColors { id: colors; source: lb.model.decoration }
                property bool launching: false
                width: bar.iconSize + 12
                height: bar.height
                onCountChanged: {
                    if (count > 0 && launching) { launching = false; arrive.restart() }
                }

                function launch(newInstance) {
                    const idx = g.launchers.mapToSource(g.launchers.index(lb.index, 0))
                    if (newInstance) g.launcherTasks.requestNewInstance(idx)
                    else g.launcherTasks.requestActivate(idx)
                    launching = lb.count === 0     // single-window apps never show a second one
                    launchTimeout.restart()
                }
                Timer { id: launchTimeout; interval: 6000; onTriggered: lb.launching = false }

                Rectangle {
                    anchors.centerIn: parent
                    width: bar.iconSize + 8
                    height: width
                    radius: Tokens.radius.sm
                    color: C.alpha(lb.g.cFg, ma.pressed ? Tokens.alpha.press : ma.containsMouse ? Tokens.alpha.hover : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                }
                Shape {          // "glow" mark
                    id: glow
                    anchors.centerIn: icon
                    width: bar.iconSize * 1.7
                    height: width
                    visible: lb.g.cfg.launcherMark === "glow" && lb.count > 0
                    opacity: lb.focused ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: Tokens.base } }
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: glow.width / 2; centerY: glow.height / 2; centerRadius: glow.width / 2
                            focalX: centerX; focalY: centerY
                            GradientStop { position: 0; color: C.alpha(lb.attention ? lb.g.cRed : lb.tint, 0.6) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height }
                    }
                }
                Kirigami.Icon {
                    id: icon
                    anchors.centerIn: parent
                    width: bar.iconSize
                    height: width
                    source: lb.model.decoration
                    // waiting for the app to show up: a stepped blink, two repaints a second
                    opacity: lb.launching && blink.on ? 0.4 : 1
                    property real mag: ma.pressed ? 0.88 : ma.containsMouse ? 1.1 : 1
                    Behavior on mag { SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.002 } }
                    scale: mag
                    transform: [
                        Translate {
                            y: ma.containsMouse && !ma.pressed ? -2 : 0
                            Behavior on y { SpringAnimation { spring: 4; damping: 0.5; epsilon: 0.05 } }
                        },
                        Scale { id: arriveScale; origin.x: icon.width / 2; origin.y: icon.height }
                    ]
                }
                Timer {
                    id: blink
                    property bool on: false
                    interval: 500
                    repeat: true
                    running: lb.launching && Tokens.speed > 0
                    onTriggered: on = !on
                    onRunningChanged: on = false
                }
                SequentialAnimation {         // ...and a small hop when it does
                    id: arrive
                    ParallelAnimation {
                        NumberAnimation { target: arriveScale; property: "yScale"; to: 1.12; duration: Tokens.fast; easing.type: Tokens.enter }
                        NumberAnimation { target: arriveScale; property: "xScale"; to: 0.94; duration: Tokens.fast; easing.type: Tokens.enter }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: arriveScale; property: "yScale"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
                        NumberAnimation { target: arriveScale; property: "xScale"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
                    }
                }
                Row {            // "dots" mark: one per window (max 3); dash = focused
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    spacing: 2
                    visible: lb.g.cfg.launcherMark === "dots"
                    Repeater {
                        model: Math.min(lb.count, 3)
                        delegate: Rectangle {
                            required property int index
                            readonly property bool lead: index === 0 && lb.focused
                            width: lead ? 10 : 4
                            height: 4
                            radius: 2
                            color: lb.attention ? lb.g.cRed : lead ? Qt.lighter(lb.tint, 1.1) : C.alpha(lb.tint, 0.75)
                            Behavior on width { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                            Behavior on color { ColorAnimation { duration: Tokens.base } }
                            scale: 0
                            Component.onCompleted: popIn.start()
                            NumberAnimation on scale { id: popIn; running: false; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                        }
                    }
                }
                Rectangle {      // "underline" mark
                    visible: lb.g.cfg.launcherMark === "underline" && lb.count > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: lb.focused ? bar.iconSize * 0.9 : bar.iconSize * 0.45
                    height: 2
                    radius: 1
                    color: lb.attention ? lb.g.cRed : lb.focused ? lb.tint : C.alpha(lb.tint, 0.6)
                    Behavior on width { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
                }

                PlasmaCore.ToolTipArea {
                    anchors.fill: parent
                    mainText: lb.model.AppName || lb.model.display || ""
                    subText: lb.count ? i18np("1 window · middle-click for a new one", "%1 windows · middle-click for a new one", lb.count)
                                      : i18n("Not running")
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) { menu.openRelative(); return }
                            if (mouse.button === Qt.MiddleButton || lb.count === 0) { lb.launch(mouse.button === Qt.MiddleButton); return }
                            lb.g.actOnApp(lb.model.AppId, lb.model.LauncherUrlWithoutIcon)
                        }
                    }
                }
                PlasmaExtras.Menu {
                    id: menu
                    visualParent: lb
                    PlasmaExtras.MenuItem {
                        text: i18n("New window")
                        icon: "window-new"
                        onClicked: lb.launch(true)
                    }
                    PlasmaExtras.MenuItem {
                        text: i18n("Unpin from bar")
                        icon: "window-unpin"
                        onClicked: lb.g.removeLauncherAt(lb.index)
                    }
                }
            }
        }
    }
}
