import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import Atom
import "Rice"

// The session island: the power glyph on the bar. A click opens the session panel (Atom
// panels/Session.qml: you, the uptime; lock, sleep, log out, restart, shut down) on the shell's sheet,
// grown out of this island.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property real uiScale: pal.uiScale

    toolTipMainText: "Session"
    toolTipSubText: "Lock, sleep, log out, restart, shut down"
    preferredRepresentation: compactRepresentation

    compactRepresentation: Island {
        id: compact
        kind: "session"
        // a single-widget island: the same side padding as every rice bar widget
        Layout.minimumWidth: power.implicitWidth + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Text {      // the island around it lights up on hover (Panel Colorizer); the icon turns and warms
            id: power
            anchors.centerIn: parent
            text: "power_settings_new"
            color: compact.containsMouse || compact.open ? pal.bad : pal.fg
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(20 * root.uiScale)
            rotation: compact.containsMouse || compact.open ? 90 : 0
            // one turn per hover, barely past the mark: not a loop, and no bouncy overshoot
            Behavior on rotation { NumberAnimation { duration: Tokens.slow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
    }
    // never shown (the panel is the shell's), but a panel applet draws nothing without one
    fullRepresentation: Item {}
}
