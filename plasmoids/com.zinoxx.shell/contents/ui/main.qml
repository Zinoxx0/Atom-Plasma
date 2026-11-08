import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import Atom

// The shell's host: one per bar, takes no space on it. It draws its screen's panels (calendar, control
// center...) on one morphing sheet (Atom.SheetWindow) and its part of the power overlay (Atom.PowerWindow); the bar's widgets are islands that ask
// for them through Atom.Shell. One host per screen: a second one on the same screen stays idle.
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    fullRepresentation: Item {
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        Layout.maximumWidth: 0
        Layout.minimumHeight: 0
        Layout.preferredHeight: 0
    }
    toolTipMainText: "Atom shell"

    readonly property var screens: Array.prototype.slice.call(Qt.application.screens)
    // until the item sits in its panel window, Screen.name reports the primary screen
    readonly property var myScreen: root.Window.window ? (screens.find(s => s.name === Screen.name) ?? null) : null

    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: SheetWindow {
            required property var modelData
            screenObj: modelData
            panels: Shell.panels
        }
    }
    // the power overlay: every screen blurs, the actions come up on the one it was opened from
    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: PowerWindow {
            required property var modelData
            screenObj: modelData
        }
    }
}
