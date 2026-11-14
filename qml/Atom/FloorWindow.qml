import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import Atom.Native
import "../Rice"
import "../Rice/Color.js" as C

// A docked bar's floor, kept on its screen while the islands are on another one. A window maximized on a
// screen (or touching its bar) sits on the docked bar's glass floor; when the pointer takes the islands to
// another screen, KWin fades that whole bar out (kwin/rice_islands), floor included, and the strip the bar
// keeps for itself (so windows never resize) would show bare wallpaper under the window. This surface is the
// same floor (the palette's `_floor`, the very values Colorizer draws the docked bar's with: atom/panel.py
// floor()) on the layer below the bar and above the wallpaper, so the islands lift off a floor that stays.
//   - the islands leave a docked screen: it shows at once, under the bar fading out on top of it
//   - they come back: it waits under the arriving bar until that's opaque, then goes
//   - a window docks or lets go while the islands are elsewhere: it eases in or out like the bar's own morph
// The frost is the theme engine's pre-blurred wallpaper (`_glassFull`), not KWin's blur: it fades with it.
Window {
    id: fw
    required property var screenObj
    property real barH: 0                       // the bar's thickness: the strip it keeps
    readonly property string screenName: screenObj ? screenObj.name : ""

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0           // keep Qt's idea of the position on this screen,
    y: screenObj ? screenObj.virtualY : 0           // or it re-homes the window to another one
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    width: screenObj ? screenObj.width : 1
    height: Math.max(1, Math.ceil(barH))
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    visible: level > 0.001

    // a known scope (an unknown one makes KWin call it a normal window: outlined, rounded), and not "dock":
    // kwin/rice_islands takes any plasmashell dock along a screen's bottom edge for a bar, and hid this one too
    LayerShell.Window.scope: "utility"
    LayerShell.Window.layer: LayerShell.Window.LayerBottom  // over the wallpaper, under the bar and the windows
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1     // in the bar's own strip
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false
    InputMask { window: fw; shapes: [] }    // nothing to click: the pointer goes through

    RicePalette { id: pal; output: fw.screenName }
    readonly property var fl: pal.values._floor ?? null

    // docked, as Plasma decides a window touches a panel: a window (not minimized) over the bar's strip or
    // the pixel row above it (a maximized window ends right there)
    readonly property var strip: screenObj && barH > 0
        ? { x: screenObj.virtualX, y: screenObj.virtualY + screenObj.height - barH - 1, width: screenObj.width, height: barH + 1 }
        : null
    readonly property bool docked: !!strip && Windows.occupied(strip)
    readonly property bool here: Shell.barShown(screenName)         // the islands are on this screen
    readonly property bool covered: Windows.isFullscreen(screenName)
    readonly property bool want: docked && !here && !covered && !!fl

    property real level: 0
    property bool seenHere: true
    onWantChanged: Qt.callLater(sync)
    onHereChanged: Qt.callLater(sync)
    function sync() {
        const left = seenHere && !here, came = !seenHere && here
        seenHere = here
        const to = want ? 1 : 0
        if (Shell.debug) console.warn("ATOM floor", screenName, "docked", docked, "islands here", here, "->", to)
        if (Math.abs(level - to) < 0.001 && !fade.running) return
        fade.stop()
        if (to === 1 && left) { level = 1; return }      // the bar fades out on top of an identical floor
        // under the arriving bar until it's opaque (rice_islands: fadeIn 180 ms)
        fade.wait = to === 0 && came ? 220 : 0
        fade.length = left || came ? 150 : 260          // (260: the bar's own docking morph, panel.DOCK_MS)
        fade.to = to
        fade.start()
    }
    SequentialAnimation {
        id: fade
        property int wait: 0
        property int length: 260
        property real to: 0
        PauseAnimation { duration: fade.wait }
        NumberAnimation { target: fw; property: "level"; to: fade.to; duration: fade.length; easing.type: Easing.OutCubic }
    }

    Item {
        anchors.fill: parent
        opacity: fw.level
        clip: true
        Image {     // the screen's wallpaper, frosted, lined up with the real one (the strip is its bottom)
            y: fw.height - height
            width: fw.width
            height: fw.screenObj ? fw.screenObj.height : 0
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: pal.values._glassFull ? "file://" + pal.values._glassFull : ""
        }
        Rectangle {
            anchors.fill: parent
            color: fw.fl ? C.alpha(fw.fl.color, fw.fl.alpha) : "transparent"
        }
        Rectangle {     // the hairline the window sits on
            width: parent.width; height: 1
            color: fw.fl ? C.alpha(fw.fl.edge, fw.fl.edgeAlpha) : "transparent"
        }
        Rectangle {     // and the sheen under it
            y: 1; width: parent.width; height: 1
            color: fw.fl ? C.alpha("#ffffff", fw.fl.sheen) : "transparent"
        }
    }
}
