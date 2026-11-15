import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The launcher's top bar (Stage): the jewel (home), the page tabs (or the Theme page's crumb), then
// search, theme, power, the time and you. One control height (stage.barH), a third bigger than a window's;
// the keys reach it too (up from the first row: keyOn names the part with the ring).
Item {
    id: topBar
    required property var stage             // the Stage (Window)
    readonly property Item tabStrip: tabs
    readonly property Item searchButton: searchBtn
    readonly property Item themeButton: themeBtn
    readonly property Item powerButton: powerBtn
    x: topBar.stage.side
    y: topBar.stage.u(26)
    width: topBar.stage.width - 2 * topBar.stage.side
    height: topBar.stage.barH
    opacity: topBar.stage.topO
    transform: Translate { y: (1 - topBar.stage.topO) * -topBar.stage.u(18) }
    readonly property string keyOn: (topBar.stage.focusRev, topBar.stage.pageState().line === "top") ? topBar.stage.topItems[topBar.stage.pageState().top] || "" : ""
    Row {
        spacing: topBar.stage.u(26)
        anchors.verticalCenter: parent.verticalCenter
        JewelChip {         // a round jewel, apart from the tabs: the logo, and the way Home
            id: homeJewel
            width: topBar.stage.barH; height: topBar.stage.barH
            rice: topBar.stage.rice
            onClicked: topBar.stage.tab !== 0 ? topBar.stage.setTab(0) : topBar.stage.launcher.close()
        }
        Row {
            id: crumb
            visible: opacity > 0.01
            opacity: topBar.stage.theming ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
            width: topBar.stage.theming ? implicitWidth : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: topBar.stage.u(12)
            TopButton { height: topBar.stage.barH; rice: topBar.stage.rice; unit: topBar.stage.unit; icon: "arrow_back"; tip: "Back (Esc)"; focused: topBar.keyOn === "back"; onClicked: topBar.stage.setTab(topBar.stage.tabBefore) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Theme"; color: topBar.stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: topBar.stage.u(30)
                   layer.enabled: true
                   layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.7; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 } }
        }
        Rectangle {         // the pages' track: the one you're on is a solid pill
            id: tabs
            width: topBar.stage.theming ? 0 : tabRow.width + 2 * topBar.stage.u(5)
            visible: opacity > 0.01
            opacity: topBar.stage.theming ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
            height: topBar.stage.barH
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: C.alpha(topBar.stage.rice.surfaceLowest, 0.55)
            border.width: 1
            border.color: C.alpha(topBar.stage.rice.edge, 0.12)
            Rectangle {
                id: tabPill
                readonly property Item at: (tabRep.count, tabRep.itemAt(topBar.stage.tab))     // (count: itemAt doesn't notify)
                x: (at ? at.x : 0) + topBar.stage.u(5)
                y: topBar.stage.u(5)
                width: at ? at.width : 0
                height: parent.height - 2 * topBar.stage.u(5)
                radius: height / 2
                color: topBar.stage.rice.light ? topBar.stage.rice.fg : "#f3f6fb"
                Behavior on x { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
                Behavior on width { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            }
            Row {
                id: tabRow
                x: topBar.stage.u(5)
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: tabRep
                    model: ["Home", "Games", "Apps"]
                    delegate: Item {
                        id: tabItem
                        required property string modelData
                        required property int index
                        readonly property bool on: topBar.stage.tab === index
                        width: tabText.implicitWidth + topBar.stage.u(48)
                        height: topBar.stage.barH - 2 * topBar.stage.u(5)
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData
                            color: tabItem.on ? (topBar.stage.rice.light ? topBar.stage.rice.surfaceLowest : "#0a0d13")
                                 : tabMouse.containsMouse ? topBar.stage.rice.fg : topBar.stage.rice.fgDim
                            font.family: Tokens.font.ui
                            font.weight: Font.Bold
                            font.pixelSize: topBar.stage.u(23)
                            Behavior on color { ColorAnimation { duration: Tokens.ms(240) } }
                        }
                        Rectangle {     // the keys' ring
                            anchors.fill: parent
                            anchors.margins: -topBar.stage.u(4)
                            radius: height / 2
                            color: "transparent"
                            border.width: Math.max(2, topBar.stage.u(2.5))
                            border.color: topBar.stage.rice.light ? topBar.stage.rice.fg : "#ffffff"
                            opacity: topBar.keyOn === "tab" + tabItem.index ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: topBar.stage.setTab(index) }
                    }
                }
            }
        }
    }
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: topBar.stage.u(14)
        TopButton { id: searchBtn; height: topBar.stage.barH; rice: topBar.stage.rice; unit: topBar.stage.unit; icon: "search"; tip: "Search (just type)"; focused: topBar.keyOn === "search"; onClicked: topBar.stage.openSearch("") }
        TopButton { id: themeBtn; height: topBar.stage.barH; rice: topBar.stage.rice; unit: topBar.stage.unit; icon: "palette"; tip: "Theme"; focused: topBar.keyOn === "theme"; lit: topBar.stage.theming; onClicked: topBar.stage.toggleTheme() }
        TopButton {
            id: powerBtn
            height: topBar.stage.barH
            rice: topBar.stage.rice; unit: topBar.stage.unit
            icon: "power_settings_new"; tip: "Power"; hotColor: topBar.stage.rice.bad
            focused: topBar.keyOn === "power"
            onClicked: topBar.stage.openPowerHere()
        }
        Rectangle { width: 1; height: topBar.stage.u(38); anchors.verticalCenter: parent.verticalCenter; color: C.alpha(topBar.stage.rice.fg, 0.16) }
        // the battery saver, while the laptop runs on battery
        Rectangle {
            visible: topBar.stage.launcher.unplugged || topBar.stage.launcher.saverOn
            anchors.verticalCenter: parent.verticalCenter
            height: topBar.stage.u(56)
            width: saverRow.implicitWidth + topBar.stage.u(36)
            radius: height / 2
            color: topBar.stage.launcher.saverShown ? C.alpha(topBar.stage.rice.green, 0.22) : C.alpha(topBar.stage.rice.fg, sm.containsMouse ? 0.14 : 0.08)
            opacity: topBar.stage.launcher.saverBusy ? 0.6 : 1
            Row {
                id: saverRow
                anchors.centerIn: parent
                spacing: topBar.stage.u(7)
                readonly property real charge: Number(topBar.stage.launcher.batt["Percent"]) || 0
                Text { anchors.verticalCenter: parent.verticalCenter; text: topBar.stage.launcher.saverShown ? "eco" : "battery_" + Math.min(6, Math.round(saverRow.charge / 100 * 6)) + "_bar"
                       color: topBar.stage.launcher.saverShown ? topBar.stage.rice.green : topBar.stage.rice.fg; font.family: Tokens.font.icons; font.pixelSize: topBar.stage.u(28) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(saverRow.charge) + "%"; color: topBar.stage.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: topBar.stage.u(20) }
            }
            MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!topBar.stage.launcher.saverBusy) topBar.stage.launcher.setSaver(!topBar.stage.launcher.saverShown) }
        }
        Text {      // (a soft shadow of its own: nothing darkens the top of the page)
            anchors.verticalCenter: parent.verticalCenter
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.7; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 }
            text: Qt.formatTime(topBar.stage.now, "HH:mm")
            color: topBar.stage.rice.fg
            font.family: Tokens.font.ui
            font.weight: Font.Bold
            font.pixelSize: topBar.stage.u(38)
            font.features: { "tnum": 1 }
            leftPadding: topBar.stage.u(8)
            rightPadding: topBar.stage.u(8)
        }
        Rectangle {     // you
            width: topBar.stage.u(60); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: topBar.stage.rice.primary }
                GradientStop { position: 1; color: topBar.stage.rice.tertiary }
            }
            border.width: 2
            border.color: C.alpha("#ffffff", 0.18)
            Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: topBar.stage.account.initial; color: topBar.stage.rice.onPrimary
                   font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: topBar.stage.u(26) }
            Kirigami.ShadowedImage { id: face; anchors.fill: parent; radius: width / 2; source: topBar.stage.account.face; visible: status === Image.Ready; fillMode: Image.PreserveAspectCrop; color: "transparent" }
        }
    }
}
