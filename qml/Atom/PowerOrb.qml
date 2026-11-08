import QtQuick
import "../Rice"
import "../Rice/SessionActions.js" as Session

// One power button that blooms into the session's actions: the orb stretches into a pill toward
// `side` and lock, sleep, restart and shut down bead out of it one after another, the nearest first.
// A second click, Esc or leaving it for a moment folds them back. Restart and shut down go through the
// rice logout screen (SessionActions.js), so a stray click can't end the session.
// Plain colours in (Atom knows no palettes): `tones` maps a tone name (primary, tertiary, secondary,
// warn, bad) to a colour.
//
//   PowerOrb { tones: ({ primary: pal.primary, ... }); onTriggered: a => run(a.cmd) }
FocusScope {
    id: orb
    property var actions: Session.pick(["lock", "sleep", "reboot", "shutdown"])
    property var tones: ({})
    property color fg: "white"
    property color fill: Qt.rgba(1, 1, 1, 0.07)
    property color edge: Qt.rgba(1, 1, 1, 0.14)
    property real size: 48
    property int side: Qt.LeftEdge              // where the actions bloom: Qt.LeftEdge or Qt.RightEdge
    property bool open: false
    property bool foldOnLeave: true
    signal triggered(var action)

    readonly property real gap: Math.round(size * 0.16)
    readonly property real step: size + gap
    readonly property real bloom: actions.length * step       // how far the pill reaches past the orb
    readonly property int dir: side === Qt.RightEdge ? 1 : -1
    implicitWidth: size
    implicitHeight: size
    property int hovered: -1                   // the action under the pointer or the keyboard
    readonly property var hot: hovered >= 0 ? actions[hovered] : null
    function tone(a) { return tones[a.tone] ?? fg }
    function toggle() { open = !open; if (!open) hovered = -1 }

    // the pill the actions sit in: grows out of the orb toward `side`
    Rectangle {
        id: pill
        y: 0
        height: orb.size
        radius: height / 2
        width: orb.size + (orb.open ? orb.bloom : 0)
        x: orb.dir < 0 ? orb.size - width : 0
        color: orb.fill
        border.width: 1
        border.color: orb.edge
        Behavior on width { NumberAnimation { duration: orb.open ? Tokens.morph : Tokens.collapse; easing.type: orb.open ? Tokens.grow : Tokens.exit } }
        HoverHandler { id: around; enabled: orb.open }     // leaving the bloomed pill for a moment folds it
    }

    Repeater {
        id: beads
        model: orb.actions
        delegate: Item {
            id: bead
            required property var modelData
            required property int index
            // nearest the orb first: shut down sits next to it, lock at the far end
            readonly property int fromOrb: orb.actions.length - index
            readonly property real home: orb.dir < 0 ? -fromOrb * orb.step : orb.size + orb.gap + (index) * orb.step
            readonly property bool lit: orb.hovered === index
            readonly property color tint: orb.tone(modelData)
            width: orb.size
            height: orb.size
            x: orb.open ? home : 0
            opacity: orb.open ? 1 : 0
            scale: orb.open ? 1 : 0.6
            visible: opacity > 0.01
            readonly property int delay: (orb.dir < 0 ? fromOrb - 1 : index) * Tokens.ms(40)
            Behavior on x { SequentialAnimation {
                PauseAnimation { duration: orb.open ? bead.delay : 0 }
                NumberAnimation { duration: orb.open ? Tokens.morph : Tokens.collapse; easing.type: orb.open ? Tokens.grow : Tokens.exit } } }
            Behavior on opacity { SequentialAnimation {
                PauseAnimation { duration: orb.open ? bead.delay : 0 }
                NumberAnimation { duration: orb.open ? Tokens.base : Tokens.fast } } }
            Behavior on scale { SequentialAnimation {
                PauseAnimation { duration: orb.open ? bead.delay : 0 }
                NumberAnimation { duration: orb.open ? Tokens.morph : Tokens.collapse; easing.type: orb.open ? Tokens.grow : Tokens.exit } } }

            Rectangle {
                anchors.centerIn: parent
                width: orb.size - orb.gap
                height: width
                radius: width / 2
                color: bead.lit ? Qt.rgba(bead.tint.r, bead.tint.g, bead.tint.b, m.pressed ? 0.3 : 0.2) : "transparent"
                border.width: bead.lit ? 1 : 0
                border.color: Qt.rgba(bead.tint.r, bead.tint.g, bead.tint.b, 0.7)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                scale: m.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
            }
            Text {
                anchors.centerIn: parent
                text: bead.modelData.icon
                color: bead.lit ? bead.tint : orb.fg
                opacity: bead.lit ? 1 : 0.82
                font.family: Tokens.font.icons
                font.pixelSize: Math.round(orb.size * 0.46)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            MouseArea {
                id: m
                anchors.fill: parent
                enabled: orb.open
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) orb.hovered = bead.index; else if (orb.hovered === bead.index) orb.hovered = -1
                onClicked: { orb.open = false; orb.triggered(bead.modelData) }
            }
        }
    }

    // what the lit action does, under the pill
    Text {
        id: caption
        readonly property real pillCentre: orb.dir < 0 ? orb.size - (orb.size + orb.bloom) / 2 : (orb.size + orb.bloom) / 2
        x: Math.round(pillCentre - width / 2)
        y: orb.size + Math.round(orb.gap * 0.8)
        text: orb.hot ? orb.hot.tip : ""
        color: orb.hot ? orb.tone(orb.hot) : orb.fg
        opacity: orb.open && orb.hot ? 0.95 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(orb.size * 0.27)
    }

    // the orb itself: the power glyph, which turns into a close mark while the actions are out
    Rectangle {
        id: core
        width: orb.size
        height: orb.size
        radius: width / 2
        color: coreMouse.containsMouse || orb.activeFocus ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Text {
            anchors.centerIn: parent
            text: orb.open ? "close" : "power_settings_new"
            readonly property color warm: orb.tones.bad ?? orb.fg
            color: coreMouse.containsMouse && !orb.open ? warm : orb.fg
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(orb.size * 0.5)
            rotation: orb.open ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Tokens.morph; easing.type: Tokens.grow } }
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        MouseArea {
            id: coreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { orb.toggle(); orb.forceActiveFocus() }
        }
    }

    Timer {
        interval: 1400
        running: orb.open && orb.foldOnLeave && !around.hovered && !coreMouse.containsMouse && orb.hovered < 0 && !orb.activeFocus
        onTriggered: orb.open = false
    }

    // keyboard: Enter/Space open it, arrows walk the actions, Enter picks, Esc folds (and stops there)
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (!orb.open) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                orb.open = true; orb.hovered = orb.dir < 0 ? orb.actions.length - 1 : 0; event.accepted = true
            }
            return
        }
        const n = orb.actions.length
        if (event.key === Qt.Key_Escape) { orb.open = false; orb.hovered = -1; event.accepted = true }
        else if (event.key === Qt.Key_Left) { orb.hovered = orb.hovered < 0 ? n - 1 : Math.max(0, orb.hovered - 1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { orb.hovered = orb.hovered < 0 ? 0 : Math.min(n - 1, orb.hovered + 1); event.accepted = true }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && orb.hot) {
            const a = orb.hot; orb.open = false; orb.hovered = -1; orb.triggered(a); event.accepted = true
        }
    }
    onActiveFocusChanged: if (!activeFocus && open && !around.hovered) open = false
}
