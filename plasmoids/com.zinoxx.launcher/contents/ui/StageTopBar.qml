import QtQuick
import Atom.Native
import Rice

// The launcher's top bar (Stage, the "simplified" style; the atom style has its own): the jewel (home), the page
// tabs as words with a beam of accent light under the one you're on (it follows the pointer over them), LB/RB while a
// pad is in use, or the Theme page's crumb; then the search field, theme, power, the battery saver while on battery,
// and the time with the date. A gradient from the top edge (Stage) carries it, so nothing needs a shadow. One control
// height (stage.barH); the keys reach it too (up from the first row: keyOn names the part with the ring).
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
    readonly property var rice: topBar.stage.rice
    function u(n) { return topBar.stage.u(n) }
    FontLoader { id: wide; source: "../fonts/HubotSans.ttf" }      // Hubot Sans (OFL): the tabs and the time
    // (its weights go through font.variableAxes "wght": with any axis set, font.weight no longer reaches it)
    readonly property string wideFamily: wide.status === FontLoader.Ready ? wide.name : Tokens.font.display

    // a pad glyph (LB, RB) in a hairline pill
    component Glyph: Rectangle {
        property alias text: g.text
        width: Math.max(height, g.implicitWidth + topBar.u(14)); height: topBar.u(28); radius: height / 2
        color: "transparent"; border.width: Math.max(1, topBar.u(1.5)); border.color: C.alpha(topBar.rice.fg, 0.34)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Text { id: g; anchors.centerIn: parent; color: topBar.rice.fgDim; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: topBar.u(13) }
    }
    // an icon button without a plate: the hover and the keys' ring are its only frame
    component Plain: Item {
        id: pb
        property string icon
        property string tip
        property bool focused
        property bool lit
        property color hot: topBar.rice.fg
        signal clicked()
        width: topBar.u(56); height: width
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle { anchors.fill: parent; radius: width / 2; color: C.alpha(topBar.rice.fg, pbm.containsMouse || pb.lit ? 0.12 : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } } }
        Rectangle { anchors.fill: parent; anchors.margins: -topBar.u(4); radius: width / 2; color: "transparent"
                    border.width: Math.max(2, topBar.u(2.5)); border.color: topBar.rice.light ? topBar.rice.fg : "#ffffff"
                    opacity: pb.focused ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Tokens.fast } } }
        Text { anchors.centerIn: parent; text: pb.icon; color: pbm.containsMouse ? pb.hot : topBar.rice.fg; font.family: Tokens.font.icons; font.pixelSize: topBar.u(30) }
        MouseArea { id: pbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    Row {
        spacing: topBar.u(18)
        anchors.verticalCenter: parent.verticalCenter
        JewelChip {         // a round jewel, apart from the tabs: the logo, and the way Home
            id: homeJewel
            width: topBar.u(56); height: width
            anchors.verticalCenter: parent.verticalCenter
            rice: topBar.rice
            onClicked: topBar.stage.tab !== 0 ? topBar.stage.setTab(0) : topBar.stage.launcher.close()
        }
        Row {
            id: crumb
            visible: opacity > 0.01
            opacity: topBar.stage.theming ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
            width: topBar.stage.theming ? implicitWidth : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: topBar.u(10)
            Plain { icon: "arrow_back"; tip: "Back (Esc)"; focused: topBar.keyOn === "back"; onClicked: topBar.stage.setTab(topBar.stage.tabBefore) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Theme"; color: topBar.rice.fg
                   font.family: topBar.wideFamily; font.weight: Font.DemiBold; font.pixelSize: topBar.u(26); font.variableAxes: { "wdth": 112, "wght": 600 } }
        }
        Glyph { text: "LB"; visible: Gamepad.inUse && !topBar.stage.theming }
        Item {              // the pages: words, the one you're on lit by a beam under it
            id: tabs
            width: topBar.stage.theming ? 0 : tabRow.width
            height: topBar.stage.barH
            visible: opacity > 0.01
            opacity: topBar.stage.theming ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.ms(320) } }
            anchors.verticalCenter: parent.verticalCenter
            property int hovered: -1
            readonly property Item at: (tabRep.count, tabRep.itemAt(hovered >= 0 ? hovered : topBar.stage.tab))     // (count: itemAt doesn't notify)
            Row {
                id: tabRow
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: tabRep
                    model: ["Home", "Games", "Apps"]
                    delegate: Item {
                        id: tabItem
                        required property string modelData
                        required property int index
                        readonly property bool on: topBar.stage.tab === index
                        width: tabText.implicitWidth + topBar.u(34)
                        height: topBar.stage.barH
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData
                            color: tabItem.on || tabMouse.containsMouse ? topBar.rice.fg : topBar.rice.fgDim
                            font.family: topBar.wideFamily
                            font.weight: Font.DemiBold
                            font.pixelSize: topBar.u(23)
                            font.variableAxes: { "wdth": 112, "wght": 600 }
                            Behavior on color { ColorAnimation { duration: Tokens.ms(240) } }
                        }
                        Rectangle {     // the keys' ring
                            anchors.fill: parent
                            anchors.topMargin: topBar.u(8); anchors.bottomMargin: topBar.u(8)
                            radius: height / 2
                            color: "transparent"
                            border.width: Math.max(2, topBar.u(2.5))
                            border.color: topBar.rice.light ? topBar.rice.fg : "#ffffff"
                            opacity: topBar.keyOn === "tab" + tabItem.index ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: tabs.hovered = containsMouse ? tabItem.index : (tabs.hovered === tabItem.index ? -1 : tabs.hovered)
                                    onClicked: topBar.stage.setTab(index) }
                    }
                }
            }
            Rectangle {     // the beam: accent light under the page (or the one the pointer is over)
                readonly property real w: tabs.at ? tabs.at.width * 0.62 : 0
                x: tabs.at ? tabs.at.x + (tabs.at.width - w) / 2 : 0
                width: w
                y: parent.height / 2 + topBar.u(24)
                height: Math.max(2, topBar.u(2.5)); radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(topBar.rice.primary, 0) }
                    GradientStop { position: 0.5; color: topBar.rice.light ? topBar.rice.primary : C.mix(topBar.rice.primary, "#ffffff", 0.35) }
                    GradientStop { position: 1; color: C.alpha(topBar.rice.primary, 0) }
                }
                Behavior on x { NumberAnimation { duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Behavior on width { NumberAnimation { duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Rectangle {     // its glow
                    anchors.centerIn: parent; width: parent.width; height: topBar.u(14); radius: height / 2; z: -1
                    color: C.alpha(topBar.rice.primary, topBar.rice.light ? 0.12 : 0.28)
                }
            }
        }
        Glyph { text: "RB"; visible: Gamepad.inUse && !topBar.stage.theming }
    }
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: topBar.u(10)
        Rectangle {         // the search field (typing anywhere searches too)
            id: searchBtn
            readonly property bool focused: topBar.keyOn === "search"
            width: searchRow.implicitWidth + topBar.u(44); height: topBar.u(56); radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: C.alpha(sm2.containsMouse ? topBar.rice.fg : topBar.rice.surfaceLowest, sm2.containsMouse ? 0.12 : 0.38)
            border.width: 1; border.color: C.alpha(topBar.rice.fg, 0.10)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Rectangle { anchors.fill: parent; anchors.margins: -topBar.u(4); radius: height / 2; color: "transparent"
                        border.width: Math.max(2, topBar.u(2.5)); border.color: topBar.rice.light ? topBar.rice.fg : "#ffffff"
                        opacity: searchBtn.focused ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Tokens.fast } } }
            Row {
                id: searchRow
                anchors.centerIn: parent
                spacing: topBar.u(10)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "search"; color: topBar.rice.fgDim; font.family: Tokens.font.icons; font.pixelSize: topBar.u(26) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Type to search"; color: topBar.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: topBar.u(18) }
            }
            MouseArea { id: sm2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: topBar.stage.openSearch("") }
        }
        Plain { id: themeBtn; icon: "palette"; tip: "Theme"; focused: topBar.keyOn === "theme"; lit: topBar.stage.theming; onClicked: topBar.stage.toggleTheme() }
        Plain { id: powerBtn; icon: "power_settings_new"; tip: "Power"; hot: topBar.rice.bad; focused: topBar.keyOn === "power"; onClicked: topBar.stage.openPowerHere() }
        // the battery saver, while the laptop runs on battery
        Rectangle {
            visible: topBar.stage.launcher.unplugged || topBar.stage.launcher.saverOn
            anchors.verticalCenter: parent.verticalCenter
            height: topBar.u(52)
            width: saverRow.implicitWidth + topBar.u(36)
            radius: height / 2
            color: topBar.stage.launcher.saverShown ? C.alpha(topBar.rice.green, 0.22) : C.alpha(topBar.rice.fg, sm.containsMouse ? 0.14 : 0.08)
            opacity: topBar.stage.launcher.saverBusy ? 0.6 : 1
            Row {
                id: saverRow
                anchors.centerIn: parent
                spacing: topBar.u(7)
                readonly property real charge: Number(topBar.stage.launcher.batt["Percent"]) || 0
                Text { anchors.verticalCenter: parent.verticalCenter; text: topBar.stage.launcher.saverShown ? "eco" : "battery_" + Math.min(6, Math.round(saverRow.charge / 100 * 6)) + "_bar"
                       color: topBar.stage.launcher.saverShown ? topBar.rice.green : topBar.rice.fg; font.family: Tokens.font.icons; font.pixelSize: topBar.u(26) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(saverRow.charge) + "%"; color: topBar.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: topBar.u(19) }
            }
            MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!topBar.stage.launcher.saverBusy) topBar.stage.launcher.setSaver(!topBar.stage.launcher.saverShown) }
        }
        Column {            // the time, the date under it
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: topBar.u(14)
            spacing: topBar.u(6)
            Text {
                anchors.right: parent.right
                text: Qt.formatTime(topBar.stage.now, "HH:mm")
                color: topBar.rice.fg
                font.family: topBar.wideFamily
                font.weight: Font.Medium
                font.pixelSize: topBar.u(36)
                font.variableAxes: { "wdth": 118, "wght": 500 }
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.right: parent.right
                text: Qt.formatDate(topBar.stage.now, "dddd d MMMM")
                color: topBar.rice.fgDim
                font.family: Tokens.font.ui
                font.pixelSize: topBar.u(14)
            }
        }
    }
}
