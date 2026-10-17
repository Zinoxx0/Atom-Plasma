import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import "Rice"

// One piece of the desk: a layer-shell window on the bottom layer of the host's screen (over the
// wallpaper, under every window, never focused), at `box` in that screen's logical px. A new box
// fades the content out, moves the window and fades it back in; showing fades in.
Window {
    id: dw
    required property var d                 // the Desk root
    required property var modelData        // its QScreen (created per screen by an Instantiator, so the
                                            // screen is known before the surface exists)
    property var box: null                  // {x, y, w, h}
    property bool shown: true
    default property alias content: body.data
    property var placed: null               // the box on screen now

    visible: d.ready && placed !== null && shown
    screen: modelData
    x: modelData.virtualX                   // keep Qt's idea of the position on this screen,
    y: modelData.virtualY                   // or it re-homes the window to another one
    // KWin can report a stray enter for the neighbouring screen (fractional scales round the edge over
    // the seam) and Qt follows it; without this, the next show would put the surface on that screen
    onScreenChanged: if (modelData.name && screen?.name !== modelData.name) screen = modelData
    transientParent: null                   // not the desktop's: it would decide the output
    width: placed ? placed.w : 1
    height: placed ? placed.h : 1
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    LayerShell.Window.scope: "rice-desk"
    LayerShell.Window.layer: LayerShell.Window.LayerBottom
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft
    LayerShell.Window.margins: placed ? ({ left: placed.x, top: placed.y, right: 0, bottom: 0 })
                                      : ({ left: 0, top: 0, right: 0, bottom: 0 })
    LayerShell.Window.exclusionZone: -1     // place against the whole screen, not around the top strip
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false

    function same(a, b) { return !!a && !!b && a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h }
    onBoxChanged: {
        if (!box) { placed = null; return }
        if (!placed) { placed = box; return }
        if (!same(box, placed)) relocate.restart()
    }
    Component.onCompleted: placed = box
    onVisibleChanged: if (visible && !relocate.running) { body.opacity = 0; appear.restart() }

    Item {
        id: body
        anchors.fill: parent
    }
    SequentialAnimation {
        id: relocate
        NumberAnimation { target: body; property: "opacity"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit }
        ScriptAction { script: dw.placed = dw.box }
        PauseAnimation { duration: 80 }
        NumberAnimation { target: body; property: "opacity"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
    }
    NumberAnimation { id: appear; target: body; property: "opacity"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
}
