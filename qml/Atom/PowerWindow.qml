import QtQuick
import QtQuick.Effects
import QtQuick.Window
import org.kde.layershell as LayerShell
import Atom.Native
import "../Rice"
import "../Rice/Color.js" as C
import "../Rice/SessionActions.js" as Session

// The power overlay on one screen (Shell kind "power"): a ripple of KWin's blur and a dim spreads out from
// the power button that was pressed (or the screen's centre) until it covers the screen, on every screen;
// on the screen it was opened from, you and the session's actions come up big: lock, sleep, log out,
// restart, shut down. Esc, a click on the blur or a second press fold it back into where it came from.
// Log out, restart and shut down still go through the rice logout screen (SessionActions.js).
// Mapped only while open (it grows once the surface is up).
Window {
    id: pw
    required property var screenObj
    readonly property string screenName: screenObj ? screenObj.name : ""

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0
    y: screenObj ? screenObj.virtualY : 0
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height : 0
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: phase !== "closed"

    LayerShell.Window.scope: "atom-power"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                             | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: lead ? LayerShell.Window.KeyboardInteractivityExclusive
                                                  : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: lead
    LayerShell.Window.wantsToBeOnActiveScreen: false

    RicePalette { id: pal; output: pw.screenName }
    readonly property real ui: Math.max(1, pal.uiScale)
    function u(n) { return Math.round(n * ui) }

    // ------------------------------------------------------------------ open / close
    readonly property bool wanted: Shell.kind === "power"
    readonly property bool lead: wanted && Shell.screen === screenName
    property bool wasLead: false                // keeps the actions while it folds away
    property string phase: "closed"
    property real p: 0                          // the ripple: 0 = a point, 1 = the whole screen
    property point origin: Qt.point(width / 2, height / 2)
    onWantedChanged: wanted ? begin() : end()
    function begin() {
        // read Shell directly: `lead` may not have caught up with the change that called this
        const here = Shell.screen === screenName, a = Shell.anchor
        origin = here && a && screenObj ? Qt.point(a.x - screenObj.virtualX + a.width / 2, a.y - screenObj.virtualY + a.height / 2)
                                        : Qt.point(width / 2, height / 2)
        wasLead = here
        shrink.stop()
        if (phase === "closed") { p = 0; phase = "opening"; waitFrame = true }
        else { phase = "opening"; grow.restart() }
    }
    function end() {
        if (phase === "closed" || phase === "closing") return
        phase = "closing"
        grow.stop()
        waitFrame = false
        shrink.restart()
    }
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) { waitFrame = false; grow.restart() }
    NumberAnimation { id: grow; target: pw; property: "p"; to: 1; duration: Tokens.ms(560); easing.type: Easing.InOutCubic
                      onFinished: if (pw.phase === "opening") pw.phase = "open" }
    NumberAnimation { id: shrink; target: pw; property: "p"; to: 0; duration: Tokens.ms(340); easing.type: Easing.InOutCubic
                      onFinished: pw.phase = "closed" }
    readonly property bool shown: phase === "open" || (phase === "opening" && p > 0.35)

    // the ripple: a circle from the origin that reaches the farthest corner
    readonly property real reach: Math.max(Math.hypot(origin.x, origin.y), Math.hypot(width - origin.x, origin.y),
                                           Math.hypot(origin.x, height - origin.y), Math.hypot(width - origin.x, height - origin.y))
    readonly property real r: reach * p
    BlurBehind {
        window: pw
        shapes: pw.phase === "closed" || pw.r < 1 ? []
              : pw.p >= 1 ? [{ x: 0, y: 0, width: pw.width, height: pw.height, radius: 0 }]
              : [{ x: pw.origin.x - pw.r, y: pw.origin.y - pw.r, width: 2 * pw.r, height: 2 * pw.r, radius: pw.r }]
    }
    Rectangle {     // the dim, riding the same ripple
        x: pw.origin.x - pw.r
        y: pw.origin.y - pw.r
        width: 2 * pw.r
        height: 2 * pw.r
        radius: pw.r
        visible: pw.r > 0.5
        color: Qt.rgba(0.02, 0.025, 0.05, pw.wasLead ? 0.42 : 0.3)
    }
    // a click anywhere on the blur folds it away
    MouseArea {
        anchors.fill: parent
        enabled: pw.phase === "open"
        onClicked: Shell.close("power")
    }

    // ------------------------------------------------------------------ you, and the actions (the lead screen)
    Account { id: me }
    property real uptime: 0
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) pw.uptime = parseFloat(data["stdout"] ?? "0") || 0
            disconnectSource(source)
        }
    }
    function upText(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return "up " + (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m"
    }
    function trigger(a) {
        Shell.close("power")
        sh.connectSource(a.cmd + " #run")      // a fixed set of commands: fixed names (RiceShell)
    }
    readonly property var actions: Session.pick()
    property int hot: -1

    Item {
        id: stage
        anchors.fill: parent
        visible: pw.wasLead && pw.phase !== "closed"
        focus: true
        Keys.onEscapePressed: Shell.close("power")
        Keys.onLeftPressed: pw.hot = pw.hot < 0 ? pw.actions.length - 1 : Math.max(0, pw.hot - 1)
        Keys.onRightPressed: pw.hot = pw.hot < 0 ? 0 : Math.min(pw.actions.length - 1, pw.hot + 1)
        Keys.onReturnPressed: if (pw.hot >= 0) pw.trigger(pw.actions[pw.hot])
        Keys.onEnterPressed: if (pw.hot >= 0) pw.trigger(pw.actions[pw.hot])

        Column {
            id: who
            anchors.horizontalCenter: parent.horizontalCenter
            y: row.y - height - pw.u(56) + (pw.shown ? 0 : pw.u(18))
            spacing: pw.u(10)
            opacity: pw.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: pw.shown ? Tokens.slow : Tokens.fast } }
            Behavior on y { NumberAnimation { duration: Tokens.ms(560); easing.type: Tokens.grow } }
            Rectangle {     // the initial on a primary -> tertiary gradient
                anchors.horizontalCenter: parent.horizontalCenter
                width: pw.u(84); height: width; radius: width / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: pal.primary }
                    GradientStop { position: 1; color: pal.tertiary }
                }
                border.width: 2
                border.color: C.alpha(pal.edge, Tokens.alpha.outlineStrong)
                Text {
                    anchors.centerIn: parent
                    text: me.initial
                    color: pal.onPrimary
                    font.family: Tokens.font.display
                    font.weight: Font.Black
                    font.pixelSize: pw.u(38)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: me.displayName
                color: "white"
                font.family: Tokens.font.display
                font.weight: Font.Light
                font.pixelSize: pw.u(34)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: me.loginName + "@" + me.host + "   ·   " + pw.upText(pw.uptime)
                color: Qt.rgba(1, 1, 1, 0.7)
                font.family: Tokens.font.ui
                font.pixelSize: pw.u(14)
            }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.5); shadowBlur: 0.8; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 }
        }

        Row {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(pw.height * 0.52)
            spacing: pw.u(30)
            Repeater {
                model: pw.actions
                delegate: Item {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property color tint: pal[modelData.tone]
                    readonly property bool lit: pw.hot === index
                    readonly property real size: pw.u(118)
                    width: size
                    height: size + pw.u(44)
                    // out one after another from the middle
                    readonly property int delay: Tokens.ms(120 + Math.abs(index - (pw.actions.length - 1) / 2) * 70)
                    opacity: pw.shown ? 1 : 0
                    scale: pw.shown ? 1 : 0.7
                    Behavior on opacity { SequentialAnimation {
                        PauseAnimation { duration: pw.shown ? btn.delay : 0 }
                        NumberAnimation { duration: pw.shown ? Tokens.slow : Tokens.fast } } }
                    Behavior on scale { SequentialAnimation {
                        PauseAnimation { duration: pw.shown ? btn.delay : 0 }
                        NumberAnimation { duration: pw.shown ? Tokens.ms(520) : Tokens.fast; easing.type: Tokens.grow } } }

                    Rectangle {
                        id: disc
                        width: btn.size; height: width; radius: width / 2
                        color: btn.lit ? C.alpha(btn.tint, m.pressed ? 0.36 : 0.26) : Qt.rgba(1, 1, 1, 0.07)
                        border.width: btn.lit ? 2 : 1
                        border.color: btn.lit ? C.alpha(btn.tint, 0.85) : Qt.rgba(1, 1, 1, 0.16)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                        scale: m.pressed ? 0.95 : btn.lit ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                        Text {
                            anchors.centerIn: parent
                            text: btn.modelData.icon
                            color: btn.lit ? btn.tint : "white"
                            font.family: Tokens.font.icons
                            font.pixelSize: Math.round(btn.size * 0.4)
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            layer.enabled: btn.lit
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: btn.tint; shadowBlur: 0.8; shadowOpacity: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: disc.horizontalCenter
                        y: btn.size + pw.u(14)
                        text: btn.modelData.tip
                        color: btn.lit ? "white" : Qt.rgba(1, 1, 1, 0.75)
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: pw.u(15)
                    }
                    MouseArea {
                        id: m
                        anchors.fill: disc
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) pw.hot = btn.index; else if (pw.hot === btn.index) pw.hot = -1
                        onClicked: pw.trigger(btn.modelData)
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: row.y + row.height + pw.u(40)
            text: "Esc to stay"
            color: Qt.rgba(1, 1, 1, 0.45)
            opacity: pw.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.slow } }
            font.family: Tokens.font.ui
            font.pixelSize: pw.u(13)
        }
    }
    onPhaseChanged: {
        if (phase === "opening" && wasLead) { hot = -1; sh.connectSource('cut -d" " -f1 /proc/uptime #up'); Qt.callLater(() => stage.forceActiveFocus()) }
        if (Shell.debug) console.warn("ATOM power", screenName, "phase", phase, "lead", wasLead)
    }
}
