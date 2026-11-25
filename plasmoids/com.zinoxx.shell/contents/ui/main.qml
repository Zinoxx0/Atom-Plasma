import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import Atom
import Rice

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
    readonly property var panelElement: {
        let c = root.parent
        while (c) {
            if (c.hasOwnProperty("touchingWindow")) return c
            c = c.parent
        }
        return null
    }
    readonly property bool docked: !!(panelElement && panelElement.touchingWindow)
    RicePalette { id: barPal; output: root.myScreen ? root.myScreen.name : "" }

    // Mount Atom LiquidBar behind panelLayout ONLY for GPU shader bar styles (liquid, aurora)
    property Item liquidBar: null
    readonly property bool wantLiquidBar: Prefs.barShadered && !!root.panelLayout && !!root.panelLayout.parent && !!root.myScreen
    Component {
        id: liquidBarComp
        LiquidBar {
            panelLayout: root.panelLayout
            screenObj: root.myScreen
            pal: barPal
            style: Prefs.barStyle
            docked: root.docked
        }
    }
    function syncLiquidBar() {
        if (wantLiquidBar) {
            if (!liquidBar) liquidBar = liquidBarComp.createObject(root.panelLayout.parent)
            else if (liquidBar.parent !== root.panelLayout.parent) liquidBar.parent = root.panelLayout.parent
        } else if (liquidBar) {
            liquidBar.destroy()
            liquidBar = null
        }
    }
    onWantLiquidBarChanged: Qt.callLater(syncLiquidBar)
    Component.onCompleted: { Qt.callLater(findColorizer); Qt.callLater(syncLiquidBar) }
    Component.onDestruction: if (liquidBar) { liquidBar.destroy(); liquidBar = null }
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
    // Keep the Binding active once Colorizer is found: in Qt 6, Binding with RestoreBindingOrValue does
    // not restore a JS expression binding on a `property var`, leaving Colorizer's presetAutoloading stuck
    // at { enabled: false } forever after the first launcher open.
    readonly property var colorizerCfg: root.colorizer && root.colorizer.plasmoid ? root.colorizer.plasmoid.configuration : null
    property int colorizerCfgRev: 0
    Connections {
        target: root.colorizerCfg
        function onValueChanged(key) { if (key === "presetAutoloading") root.colorizerCfgRev++ }     // qmllint disable signal-handler-parameters
    }
    readonly property var liveAutoloading: {
        colorizerCfgRev
        const raw = root.colorizerCfg ? root.colorizerCfg.presetAutoloading : ""
        if (!raw) return null
        try { return JSON.parse(String(raw)) } catch (e) { return null }
    }
    Binding {
        target: root.colorizer
        property: "presetAutoloading"
        value: root.freezeColorizer
            ? Object.assign({}, root.liveAutoloading, { enabled: false })
            : root.liveAutoloading
        when: !!root.colorizer && root.liveAutoloading !== null
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
