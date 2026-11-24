import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import Atom

// The shell's host: one per bar, takes no space on it. It draws its screen's panels (calendar, control
// center...) on one morphing sheet (Atom.SheetWindow), its part of the power overlay (Atom.PowerWindow) and
// the docked bar's floor while the islands are elsewhere (Atom.FloorWindow); the bar's widgets are islands that ask
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

    // Pause Panel Colorizer's preset auto-loading while the launcher or power overlay covers this screen,
    // preventing synchronous 67 KB JSON reads & writeConfig() GUI stalls when windows minimize/restore.
    readonly property GridLayout panelLayout: {
        let p = root.parent
        while (p) {
            if (p instanceof GridLayout) return p
            p = p.parent
        }
        return null
    }
    property QtObject colorizer: null
    function findColorizer() {
        const lay = panelLayout
        if (!lay) return
        const kids = lay.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            const a = c && c.applet ? c.applet : null
            if (a && a.plasmoid && a.plasmoid.pluginName === "luisbocanegra.panel.colorizer" && "presetAutoloading" in a) {
                colorizer = a
                return
            }
        }
    }
    Component.onCompleted: Qt.callLater(findColorizer)
    Connections {
        target: root.panelLayout
        function onChildrenChanged() { root.findColorizer() }
    }
    readonly property bool barCovered: !!myScreen && (
        Shell.kind === "power"
        || (Shell.kind === "launcher" && Shell.screen === myScreen.name && !(Shell.args && Shell.args.searchOnly))
        || (!!Shell.under && Shell.under.kind === "launcher" && Shell.under.screen === myScreen.name)
    )
    property bool freezeColorizer: false
    Timer { id: unfreezeColorizer; interval: 320; onTriggered: root.freezeColorizer = false }
    onBarCoveredChanged: {
        if (barCovered) {
            if (!colorizer) findColorizer()
            unfreezeColorizer.stop()
            freezeColorizer = true
        } else {
            unfreezeColorizer.restart()
        }
    }
    Binding {
        target: root.colorizer
        property: "presetAutoloading"
        value: ({ enabled: false, filterByScreen: true, filterByActive: false, trackLastActive: false })
        when: root.freezeColorizer && !!root.colorizer
        restoreMode: Binding.RestoreBindingOrValue
    }

    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: SheetWindow {
            required property var modelData
            screenObj: modelData
            panels: Shell.panels
        }
    }
    // a docked bar's floor, kept while the islands are on another screen (no bare strip under a maximized
    // window); the bar's thickness is this panel window's
    Instantiator {
        model: root.myScreen ? [root.myScreen] : []
        delegate: FloorWindow {
            required property var modelData
            screenObj: modelData
            barH: root.Window.window ? root.Window.window.height : 0
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
