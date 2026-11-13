import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import Atom.Native
import "../Rice"

// One screen's shell surface: a transparent layer-shell window over the whole screen that stays mapped
// (mapping one takes ~50 ms, switching its input mask ~1 ms), drawing the morphing sheet. Only the sheet
// takes the pointer (InputMask): clicks anywhere else reach the windows below, and the sheet, which takes
// the keyboard while open, closes when it loses it. KWin blurs what's behind the sheet's exact shape.
// It steps aside while a fullscreen window covers the screen, so games keep direct scan-out.
Window {
    id: win
    required property var screenObj                 // the Qt screen it covers
    property var panels: ({})                       // kind -> url (Shell.panels)
    readonly property string screenName: screenObj ? screenObj.name : ""

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0           // keep Qt's idea of the position on this screen, or it
    y: screenObj ? screenObj.virtualY : 0           // re-homes the window to another one
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height : 0
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: !!screenObj && Windows.fullscreen[screenName] !== true && !handingBack

    LayerShell.Window.scope: "atom-shell"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                             | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    // the keyboard only while a panel is open: an always-focusable surface would take the focus when it
    // maps (plasmashell starting) and keep it after a panel closes, eating what the user types. Opening
    // switches to on-demand and asks for the focus once that change has gone out with a frame; closing
    // switches back, and KWin hands the focus back to the window that had it.
    property bool wantsKeys: false
    LayerShell.Window.keyboardInteractivity: wantsKeys ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                       : LayerShell.Window.KeyboardInteractivityNone
    property bool activatePending: false
    onFrameSwapped: if (activatePending) { activatePending = false; requestActivate() }
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false

    RicePalette { id: pal; output: win.screenName }
    readonly property real ui: pal.uiScale

    // a panel of ours is open on this screen
    readonly property bool mine: Shell.kind !== "" && Shell.screen === screenName && (Shell.kind in panels)
    // the island it grows from, in this window's coordinates (bottom centre when it has none)
    function local(r) {
        if (!r || !screenObj) return Qt.rect(width / 2 - 24, height - 56, 48, 40)
        return Qt.rect(r.x - screenObj.virtualX, r.y - screenObj.virtualY, r.width, r.height)
    }
    // follow the switchboard: open, glide to another island, switch content, close
    function sync() {
        if (mine) sheet.present(Shell.kind, local(Shell.anchor))
        else sheet.dismiss()
    }
    Connections {
        target: Shell
        function onKindChanged() { win.sync() }
        function onScreenChanged() { win.sync() }
        function onAnchorChanged() { if (win.mine) win.sync() }
    }

    Sheet {
        id: sheet
        anchors.fill: parent
        panels: win.panels
        readonly property real margin: Math.round(Tokens.space.md * win.ui)
        bounds: Qt.rect(margin, Math.round(Tokens.space.xl * win.ui), win.width - 2 * margin,
                        win.height - Math.round(Tokens.space.xl * win.ui) - margin)
        gap: Math.round(Tokens.space.md * win.ui)
        pad: Math.round(Tokens.space.lg * win.ui)
        radius: Math.round(Tokens.radius.xl * win.ui)
        fill: pal.light ? Tokens.neutral.light : Tokens.neutral.dark
        fillAlpha: pal.light ? 0.86 : 0.8
        rimA: pal.primary
        rimB: pal.tertiary
        props: ({ ricePalette: pal, screenName: win.screenName, ui: win.ui })
        onPhaseChanged: {
            if (phase === "opening") { win.wantsKeys = true; win.activatePending = true }
            else if (phase === "closing" || phase === "closed") { win.wantsKeys = false; win.activatePending = false }
            if (phase === "closed" && win.active) win.handBack()
        }
    }

    // Closed with the keyboard still here (Esc, or its island clicked again): KWin keeps a layer surface
    // focused after it stops asking for the keyboard, and only re-picks the focus when a surface goes
    // away. So it goes away for a moment (once the sheet has finished closing) and comes straight back;
    // KWin gives the focus to the window that had it before (or the desktop).
    property bool handingBack: false
    function handBack() { handingBack = true; Qt.callLater(() => { handingBack = false }) }

    // the notification cards: on the screen you're working on, out of the status island
    Toasts {
        id: toasts
        anchors.fill: parent
        screenName: win.screenName
        pal: pal
        ui: win.ui
        readonly property var statusIsland: Shell.island("control", win.screenName)
        island: statusIsland ? win.local(statusIsland) : Qt.rect(win.width - Math.round(64 * win.ui), win.height - Math.round(52 * win.ui), Math.round(48 * win.ui), Math.round(36 * win.ui))
        blocked: sheet.shown && sheet.kind === "apps"
    }
    readonly property int unread: Notify.unreadTotal      // (starts the notifications' memory with the shell)

    InputMask {
        window: win
        shapes: (sheet.shown ? [sheet.shape] : []).concat(toasts.shapes)
        onShapesChanged: if (Shell.debug && shapes.length === 0) console.warn("ATOM mask empty", Date.now() % 100000)
    }
    Item {      // tests: where a click on the surface itself lands (under the panels: on top it took their presses)
        anchors.fill: parent
        z: -1
        visible: Shell.debug
        TapHandler { onTapped: (pt) => console.warn("ATOM surface tapped at", Math.round(pt.position.x), Math.round(pt.position.y), "shown", sheet.shown) }
    }
    BlurBehind { window: win; shapes: sheet.shown && sheet.sw > 2 ? [sheet.shape] : [] }

    // a click anywhere else (another window, the bar) takes the keyboard away: the panel closes
    onActiveChanged: {
        if (Shell.debug) console.warn("ATOM sheet window", screenName, "active", active, Date.now() % 100000)
        if (!active && mine) Shell.close()
    }
}
