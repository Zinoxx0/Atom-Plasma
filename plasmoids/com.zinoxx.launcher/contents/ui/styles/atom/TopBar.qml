import QtQuick
import Atom
import Atom.Native
import Rice

// Atom's top bar (its own: the simplified style has another): the jewel, the pages as words with a beam of accent
// light under the one you're on (it follows the pointer over them), LB/RB while a pad is in use; the search field
// (the query while searching), theme, power, the battery saver while on battery, the time with the date.
Item {
    id: bar
    required property var stage
    readonly property Item powerButton: powerBtn
    readonly property Item themeButton: themeBtn
    readonly property Item searchButton: field
    readonly property var rice: bar.stage.look
    function d(px) { return bar.stage.d(px) }
    x: bar.stage.side
    y: bar.d(30)
    width: bar.stage.width - 2 * bar.stage.side
    height: bar.d(64)
    opacity: bar.stage.topO
    transform: Translate { y: (1 - bar.stage.topO) * -bar.d(14) }

    component Glyph: Rectangle {
        property alias text: g.text
        width: Math.max(height, g.implicitWidth + bar.d(12)); height: bar.d(26); radius: height / 2
        color: "transparent"; border.width: Math.max(1, bar.d(1.5)); border.color: C.alpha(bar.rice.fg, 0.34)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Text { id: g; anchors.centerIn: parent; color: bar.rice.fgDim; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: bar.d(12.5) }
    }
    component Plain: Item {
        id: pb
        property string icon
        property bool lit
        property color hot: bar.rice.fg
        signal clicked()
        width: bar.d(52); height: width
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle { anchors.fill: parent; radius: width / 2; color: C.alpha(bar.rice.fg, pbm.containsMouse || pb.lit ? 0.12 : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } } }
        Text { anchors.centerIn: parent; text: pb.icon; color: pbm.containsMouse ? pb.hot : bar.rice.fg; font.family: Tokens.font.icons; font.pixelSize: bar.d(26) }
        MouseArea { id: pbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.d(14)
        Rectangle {         // the jewel: the rice's emblem on the accent
            width: bar.d(52); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: bar.rice.primary } GradientStop { position: 1; color: bar.rice.tertiary } }
            Emblem { anchors.centerIn: parent; scale: parent.width * 0.62 / 34; hovered: jm.containsMouse; pressed: jm.pressed
                     c1: "#ffffff"; c2: C.mix(bar.rice.tertiary, "#ffffff", 0.55); c3: C.mix(bar.rice.red, "#ffffff", 0.15); c4: C.mix(bar.rice.teal, "#ffffff", 0.15); glow: "#ffffff" }
            MouseArea { id: jm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.stage.page !== "home" ? bar.stage.setPage("home") : bar.stage.launcher.close() }
        }
        Glyph { text: "LB"; visible: Gamepad.inUse }
        Item {
            id: tabs
            width: tabRow.width; height: bar.height
            anchors.verticalCenter: parent.verticalCenter
            property int hovered: -1
            readonly property int on: bar.stage.tabs.indexOf(bar.stage.page)
            readonly property Item at: (rep.count, rep.itemAt(hovered >= 0 ? hovered : on))
            Row {
                id: tabRow
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: rep
                    model: ["Home", "Games", "Apps"]
                    delegate: Item {
                        id: tab
                        required property string modelData
                        required property int index
                        width: tt.implicitWidth + bar.d(32); height: bar.height
                        Text { id: tt; anchors.centerIn: parent; text: tab.modelData
                               color: tabs.on === tab.index || tm.containsMouse ? bar.rice.fg : bar.rice.fgDim
                               font.family: bar.stage.wideFamily; font.pixelSize: bar.d(21); font.variableAxes: bar.stage.wide(112, 600)
                               Behavior on color { ColorAnimation { duration: Tokens.ms(220) } } }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: tabs.hovered = containsMouse ? tab.index : (tabs.hovered === tab.index ? -1 : tabs.hovered)
                                    onClicked: bar.stage.setPage(bar.stage.tabs[tab.index]) }
                    }
                }
            }
            Rectangle {     // the beam
                readonly property real w: tabs.at ? tabs.at.width * 0.62 : 0
                visible: !!tabs.at
                x: tabs.at ? tabs.at.x + (tabs.at.width - w) / 2 : 0
                width: w; y: parent.height / 2 + bar.d(22)
                height: Math.max(2, bar.d(2.4)); radius: height / 2
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(bar.rice.primary, 0) }
                    GradientStop { position: 0.5; color: bar.rice.light ? bar.rice.primary : C.mix(bar.rice.primary, "#ffffff", 0.35) }
                    GradientStop { position: 1; color: C.alpha(bar.rice.primary, 0) } }
                Behavior on x { NumberAnimation { duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Behavior on width { NumberAnimation { duration: Tokens.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Rectangle { anchors.centerIn: parent; width: parent.width; height: bar.d(14); radius: height / 2; z: -1
                            color: C.alpha(bar.rice.primary, bar.rice.light ? 0.12 : 0.28) }
            }
        }
        Glyph { text: "RB"; visible: Gamepad.inUse }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: bar.d(8)
        Rectangle {         // the search field: the query while searching
            id: field
            readonly property bool on: bar.stage.searching
            width: Math.max(fieldRow.implicitWidth + bar.d(40), on ? bar.d(300) : 0); height: bar.d(50); radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: C.alpha(fm.containsMouse && !on ? bar.rice.fg : bar.rice.surfaceLowest, fm.containsMouse && !on ? 0.12 : on ? 0.6 : 0.38)
            border.width: on ? Math.max(1.5, bar.d(1.5)) : 1
            border.color: on ? C.alpha(bar.rice.primary, 0.7) : C.alpha(bar.rice.fg, 0.10)
            Behavior on width { NumberAnimation { duration: Tokens.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            Row {
                id: fieldRow
                anchors.verticalCenter: parent.verticalCenter
                x: bar.d(18)
                spacing: bar.d(10)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "search"; visible: !field.on; color: bar.rice.fgDim; font.family: Tokens.font.icons; font.pixelSize: bar.d(22) }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: field.on ? bar.stage.launcher.query : "Type to search"
                       color: field.on ? bar.rice.fg : bar.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: bar.d(17); font.weight: field.on ? Font.DemiBold : Font.Normal }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: field.on; width: Math.max(2, bar.d(2)); height: bar.d(22); color: bar.rice.primary
                            SequentialAnimation on opacity { running: field.on && bar.stage.phase === "open"; loops: Animation.Infinite
                                PropertyAction { value: 1 } PauseAnimation { duration: 530 } PropertyAction { value: 0 } PauseAnimation { duration: 530 } } }
            }
            MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onClicked: if (!field.on) bar.stage.openSearch("") }
        }
        Plain { id: themeBtn; icon: "palette"; lit: bar.stage.page === "theme"; onClicked: bar.stage.toggleTheme() }
        Plain { id: powerBtn; icon: "power_settings_new"; hot: bar.rice.bad; onClicked: bar.stage.openPowerHere() }
        Rectangle {         // the battery saver, while the laptop runs on battery
            visible: bar.stage.launcher.unplugged || bar.stage.launcher.saverOn
            anchors.verticalCenter: parent.verticalCenter
            height: bar.d(46); width: sr.implicitWidth + bar.d(32); radius: height / 2
            color: bar.stage.launcher.saverShown ? C.alpha(bar.rice.green, 0.22) : C.alpha(bar.rice.fg, sm.containsMouse ? 0.14 : 0.08)
            Row { id: sr; anchors.centerIn: parent; spacing: bar.d(6)
                readonly property real charge: Number(bar.stage.launcher.batt["Percent"]) || 0
                Text { anchors.verticalCenter: parent.verticalCenter; text: bar.stage.launcher.saverShown ? "eco" : "battery_" + Math.min(6, Math.round(sr.charge / 100 * 6)) + "_bar"
                       color: bar.stage.launcher.saverShown ? bar.rice.green : bar.rice.fg; font.family: Tokens.font.icons; font.pixelSize: bar.d(22) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(sr.charge) + "%"; color: bar.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: bar.d(16) } }
            MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!bar.stage.launcher.saverBusy) bar.stage.launcher.setSaver(!bar.stage.launcher.saverShown) }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: bar.d(14)
            spacing: bar.d(5)
            Text { anchors.right: parent.right; text: Qt.formatTime(bar.stage.now, "HH:mm"); color: bar.rice.fg
                   font.family: bar.stage.wideFamily; font.pixelSize: bar.d(34); font.variableAxes: bar.stage.wide(118, 500); font.features: { "tnum": 1 } }
            Text { anchors.right: parent.right; text: Qt.formatDate(bar.stage.now, "dddd d MMMM"); color: bar.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: bar.d(13.5) }
        }
    }
}
