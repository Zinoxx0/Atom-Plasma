import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import Atom.Native
import "../Rice"
import "../Rice/Color.js" as C
import "../Rice/Motion.js" as M
import "../Rice/SessionActions.js" as Session

// The power overlay on one screen (Shell kind "power"), in Atom Home's language: a ripple of KWin's blur and
// a veil of the palette's darkest surface spreads from the power button that was pressed (or the screen's
// centre) until it covers the screen, on every screen. On the screen it was opened from you come up big
// (your face, a greeting, how long the machine has been up) over the session's actions as five tiles in
// their tones: lock, sleep, log out, restart, shut down. The focused tile grows, wears the white ring and
// glows in its tone. The ones that end the session confirm themselves: a ring runs round the tile for three
// seconds (Enter again does it now, Esc cancels), then ksmserver ends the session as usual (no second
// prompt). Esc, a click on the blur or a second press fold it back into where it came from.
// One clock per move with Motion.js tracks (the launcher lab's timings). Mapped only while open.
// Under the nested tests (Shell.debug) nothing is run: "ATOM power run <id>" says what would have been.
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

    LayerShell.Window.scope: "utility"      // a known scope: an unknown one makes KWin call it a normal window (outlined, rounded)
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
    readonly property color ring: pal.light ? pal.fg : "#ffffff"
    readonly property real glowK: Math.max(0.4, pal.glow)

    // ------------------------------------------------------------------ open / close: one clock each
    readonly property bool wanted: Shell.kind === "power"
    readonly property bool lead: wanted && Shell.screen === screenName
    property bool wasLead: false                // keeps the actions while it folds away
    property string phase: "closed"
    property real p: 0                          // the ripple: 0 = a point, 1 = the whole screen
    property real innerV: 0                     // you and the actions: 0 = gone, 1 = here
    property var actV: [0, 0, 0, 0, 0]          // each action's own entrance
    property point origin: Qt.point(width / 2, height / 2)
    readonly property int rippleMs: Tokens.ms(700)
    readonly property int staggerMs: Tokens.ms(36)
    readonly property int focusMs: Tokens.ms(380)
    readonly property int openTotal: Math.round(rippleMs * 1.2 + 4 * staggerMs)
    readonly property int closeTotal: Math.round(rippleMs * 0.7)
    property real openT: 0
    property real closeT: 0
    property real p0: 0                         // where the close started from
    property real i0: 0
    property real openFrom: 0                   // > 0: it was folding away and opens again from where it is
    NumberAnimation { id: openClock; target: pw; property: "openT"; from: pw.openFrom; to: pw.openTotal; duration: pw.openTotal - pw.openFrom
                      onFinished: if (pw.phase === "opening") pw.phase = "open" }
    NumberAnimation { id: closeClock; target: pw; property: "closeT"; from: 0; to: pw.closeTotal; duration: pw.closeTotal
                      onFinished: { if (pw.phase === "closing") pw.phase = "closed" } }
    onOpenTChanged: if (phase === "opening") applyOpen(openT)
    onCloseTChanged: if (phase === "closing") applyClose(closeT)
    function applyOpen(t) {
        const d = rippleMs
        p = M.track(t, 0, d, M.move)
        innerV = M.track(t, d * 0.3, d * 0.9, M.enter)
        actV = actV.map((_, i) => M.track(t, d * 0.4 + i * staggerMs, d * 0.8, M.enter))
    }
    function applyClose(t) {
        const d = closeTotal
        innerV = i0 * (1 - M.track(t, 0, d * 0.45, M.exit))
        p = p0 * (1 - M.track(t, d * 0.1, d * 0.9, M.move))
    }
    onWantedChanged: wanted ? begin() : end()
    function begin() {
        // read Shell directly: `lead` may not have caught up with the change that called this
        const here = Shell.screen === screenName, a = Shell.anchor
        origin = here && a && screenObj ? Qt.point(a.x - screenObj.virtualX + a.width / 2, a.y - screenObj.virtualY + a.height / 2)
                                        : Qt.point(width / 2, height / 2)
        wasLead = here
        closeClock.stop()
        cancelCount()
        sel = 0
        greet = greeting(new Date().getHours())
        if (here) sh.connectSource('cut -d" " -f1 /proc/uptime #up')
        if (phase === "closed") { p = 0; innerV = 0; actV = [0, 0, 0, 0, 0]; openFrom = 0; phase = "opening"; waitFrame = true }
        else {      // it was folding away: carry on from where the ripple is
            let lo = 0, hi = rippleMs
            for (let k = 0; k < 20; k++) { const mid = (lo + hi) / 2; if (M.move(mid / rippleMs) < p) lo = mid; else hi = mid }
            openFrom = lo
            phase = "opening"
            openClock.restart()
        }
        if (here) Qt.callLater(() => content.forceActiveFocus())
    }
    function end() {
        if (phase === "closed" || phase === "closing") return
        cancelCount()
        openClock.stop()
        waitFrame = false
        p0 = p; i0 = innerV
        phase = "closing"
        closeClock.restart()
    }
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) { waitFrame = false; openClock.restart() }

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
    Rectangle {     // the veil, riding the same ripple: the palette's darkest surface (light moods: a light one)
        x: pw.origin.x - pw.r
        y: pw.origin.y - pw.r
        width: 2 * pw.r
        height: 2 * pw.r
        radius: pw.r
        visible: pw.r > 0.5
        color: C.alpha(pal.surfaceLowest, pw.wasLead ? 0.52 : 0.36)
    }
    // a click anywhere on the blur folds it away
    MouseArea {
        anchors.fill: parent
        enabled: pw.phase === "open" || pw.phase === "opening"
        onClicked: Shell.close("power")
    }

    // ------------------------------------------------------------------ you, and the actions (the lead screen)
    Account { id: me }
    property real uptime: 0
    property string greet: ""
    function greeting(h) { return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening" }
    function dur(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return d ? d + " d " + h + " h" : h ? h + " h " + m + " min" : m + " min"
    }
    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#up") >= 0) pw.uptime = parseFloat(data["stdout"] ?? "0") || 0
            disconnectSource(source)
        }
    }
    readonly property var actions: Session.pick()
    property int sel: 0

    // what a tile does: at once, or (ending the session) after its ring has gone round; again = now
    property int counting: -1
    property real countP: 0
    readonly property int confirmMs: 3000       // a time to read, not an animation: not scaled by Tokens.ms
    NumberAnimation { id: countdown; target: pw; property: "countP"; from: 0; to: 1; duration: pw.confirmMs
                      onFinished: if (pw.counting >= 0 && pw.countP >= 1) pw.run(pw.actions[pw.counting]) }
    function act(i) {
        const a = actions[i]
        if (!a) return
        sel = i
        if (!a.confirms || counting === i) { run(a); return }
        counting = i
        countP = 0
        countdown.restart()
        if (Shell.debug) console.warn("ATOM power confirm", a.id)
    }
    function cancelCount() {
        if (counting < 0) return
        counting = -1
        countdown.stop()
        countP = 0
        if (Shell.debug) console.warn("ATOM power cancel")
    }
    function run(a) {
        const cmd = a.confirms ? a.now : a.cmd
        cancelCount()
        Shell.close("power")
        if (Shell.debug) { console.warn("ATOM power run", a.id); return }      // the nested tests: never for real
        sh.connectSource(cmd + " #run")         // a fixed set of commands: fixed names (RiceShell)
    }

    Item {
        id: content
        anchors.fill: parent
        visible: pw.wasLead && pw.phase !== "closed"
        focus: true
        opacity: pw.innerV
        scale: M.lerp(0.94, 1, pw.innerV)
        Keys.onPressed: event => {
            const k = event.key
            if (k === Qt.Key_Escape) { if (pw.counting >= 0) pw.cancelCount(); else Shell.close("power") }
            else if (k === Qt.Key_Left || k === Qt.Key_Right) { if (pw.counting < 0) pw.sel = Math.max(0, Math.min(pw.actions.length - 1, pw.sel + (k === Qt.Key_Left ? -1 : 1))) }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) pw.act(pw.sel)
            else return
            event.accepted = true
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -pw.u(20)
            spacing: 0

            // you
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: pw.u(112); height: width
                RectangularShadow {     // a glow of the accent under it
                    anchors.fill: parent
                    radius: width / 2
                    offset.y: pw.u(24)
                    blur: pw.u(60)
                    spread: -pw.u(20)
                    color: C.alpha(pal.primary, 0.9 * pw.glowK)
                }
                Rectangle {     // the halo
                    anchors.fill: parent
                    anchors.margins: -pw.u(4)
                    radius: width / 2
                    color: C.alpha(pw.ring, 0.16)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: pal.primary }
                        GradientStop { position: 1; color: pal.tertiary }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        text: me.initial
                        color: pal.onPrimary
                        font.family: Tokens.font.display
                        font.weight: Font.Bold
                        font.pixelSize: pw.u(46)
                    }
                }
                Kirigami.ShadowedImage {
                    id: face
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: pw.wasLead ? me.face : ""
                    fillMode: Image.PreserveAspectCrop
                    radius: width / 2
                    color: "transparent"
                }
            }
            Item { width: 1; height: pw.u(26) }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pw.greet + (me.displayName ? ", " + me.displayName : "")
                color: pal.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: pw.u(42)
                font.letterSpacing: -0.6 * pw.ui
            }
            Item { width: 1; height: pw.u(8) }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pw.uptime ? "Up " + pw.dur(pw.uptime) + " · " + Qt.application.screens.length + (Qt.application.screens.length === 1 ? " screen" : " screens") : " "
                color: pal.fgDim
                font.family: Tokens.font.ui
                font.pixelSize: pw.u(16)
            }
            Item { width: 1; height: pw.u(64) }

            // the actions
            Row {
                id: acts
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: pw.u(30)
                Repeater {
                    id: actsRep
                    model: pw.actions
                    delegate: Item {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property color tone: pal[modelData.tone] ?? pal.primary
                        readonly property bool lit: pw.sel === index
                        readonly property bool counting: pw.counting === index
                        readonly property real size: pw.u(132)
                        readonly property real rad: pw.u(36)
                        width: size
                        height: size + pw.u(16) + lbl.implicitHeight
                        opacity: pw.actV[index]
                        transform: Translate { y: (1 - pw.actV[btn.index]) * pw.u(30) }

                        Item {
                            id: orb
                            width: btn.size
                            height: btn.size
                            scale: m.pressed ? 1.05 : btn.lit ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: pw.focusMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                            RectangularShadow {     // its light, in its tone, when focused
                                anchors.fill: parent
                                radius: btn.rad
                                blur: pw.u(70)
                                spread: -pw.u(6)
                                color: C.alpha(btn.tone, 0.8 * pw.glowK)
                                opacity: btn.lit ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: pw.focusMs } }
                            }
                            RectangularShadow {     // on the ground
                                anchors.fill: parent
                                radius: btn.rad
                                offset.y: pw.u(20)
                                blur: pw.u(40)
                                spread: -pw.u(20)
                                color: Qt.rgba(0, 0, 0, 0.6)
                            }
                            Rectangle {     // a deep tile of its tone, lit from the top
                                anchors.fill: parent
                                radius: btn.rad
                                gradient: Gradient {
                                    GradientStop { position: 0; color: C.mix(btn.tone, pal.surfaceLowest, 0.78) }
                                    GradientStop { position: 1; color: pal.surfaceLowest }
                                }
                                border.width: 1
                                border.color: C.alpha("#ffffff", 0.12)
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: btn.rad
                                gradient: Gradient {
                                    GradientStop { position: 0; color: C.alpha("#ffffff", 0.12) }
                                    GradientStop { position: 0.5; color: C.alpha("#ffffff", 0) }
                                }
                            }
                            Rectangle {     // the focus ring
                                anchors.fill: parent
                                radius: btn.rad
                                color: "transparent"
                                border.width: Math.max(2, pw.u(2.5))
                                border.color: C.alpha(pw.ring, 0.95)
                                opacity: btn.lit && !btn.counting ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Math.round(pw.focusMs * 0.6) } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: btn.modelData.icon
                                color: btn.lit ? btn.tone : pal.fg
                                font.family: Tokens.font.icons
                                font.pixelSize: pw.u(50)
                                rotation: btn.lit && btn.modelData.id === "shutdown" ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                                Behavior on color { ColorAnimation { duration: Tokens.ms(240) } }
                            }
                            Shape {         // the countdown: a ring of its tone runs round it
                                id: ringShape
                                anchors.fill: parent
                                anchors.margins: -pw.u(9)
                                visible: btn.counting
                                preferredRendererType: Shape.CurveRenderer
                                layer.enabled: visible
                                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: btn.tone; shadowBlur: 0.5; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                                ShapePath {
                                    strokeColor: btn.tone
                                    strokeWidth: Math.max(3, pw.u(3.5))
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    trim.start: 0
                                    trim.end: btn.counting ? pw.countP : 0
                                    PathRectangle {
                                        x: pw.u(1.75); y: pw.u(1.75)
                                        width: ringShape.width - 2 * pw.u(1.75)
                                        height: ringShape.height - 2 * pw.u(1.75)
                                        radius: btn.rad + pw.u(9)
                                    }
                                }
                            }
                        }
                        Text {
                            id: lbl
                            anchors.horizontalCenter: orb.horizontalCenter
                            y: btn.size + pw.u(16)
                            text: btn.modelData.label
                            color: btn.lit ? pal.fg : pal.fgDim
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: pw.u(16)
                            Behavior on color { ColorAnimation { duration: Tokens.ms(200) } }
                        }
                        MouseArea {
                            id: m
                            anchors.fill: orb
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: if (pw.counting < 0) pw.sel = btn.index
                            onClicked: pw.act(btn.index)
                        }
                        readonly property Item orbItem: orb
                    }
                }
            }
            Item { width: 1; height: pw.u(54) }

            // the keys; while a ring runs, what's about to happen
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: pw.u(22)
                Text {
                    visible: pw.counting >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: pw.counting >= 0 ? pw.actions[pw.counting].doing + " in " + Math.max(1, Math.ceil(pw.confirmMs / 1000 * (1 - pw.countP))) + "…" : ""
                    color: pal.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: pw.u(15)
                }
                Repeater {
                    model: pw.counting >= 0 ? [["Enter", "Now"], ["Esc", "Cancel"]] : [["←→", "Choose"], ["Enter", "Go"], ["Esc", "Back"]]
                    Row {
                        required property var modelData
                        spacing: pw.u(7)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(pw.u(22), kt.implicitWidth + pw.u(12))
                            height: pw.u(22)
                            radius: pw.u(6)
                            color: "transparent"
                            border.width: 1
                            border.color: C.alpha(pal.fg, 0.2)
                            Text { id: kt; anchors.centerIn: parent; text: modelData[0]; color: pal.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: pw.u(11.5) }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: pw.counting >= 0 ? pal.fg : pal.muted
                            font.family: Tokens.font.ui
                            font.weight: pw.counting >= 0 ? Font.DemiBold : Font.Medium
                            font.pixelSize: pw.u(pw.counting >= 0 ? 14 : 13)
                        }
                    }
                }
            }
        }
    }
    onPhaseChanged: {
        if (!Shell.debug) return
        console.warn("ATOM power", screenName, "phase", phase, "lead", wasLead)
        if (phase === "open" && wasLead) for (let i = 0; i < actsRep.count; i++) {     // where the tiles sit (the tests click them)
            const o = actsRep.itemAt(i).orbItem, q = o.mapToItem(null, o.width / 2, o.height / 2)
            console.warn("ATOM power action", actions[i].id, "at", Math.round(pw.x + q.x), Math.round(pw.y + q.y))
        }
    }
}
