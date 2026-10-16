import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import "Rice"
import "Rice/Color.js" as C

// The opened band of one screen: the resting band grows down into it (its lower lip turning to
// glass), the apps fade and rise into place, media floats on the right. Hovering an icon slides a
// lens under it and drips a tab with the app's name from the lip; resting there brings the app's
// window thumbnails down under the tab. Leaving the band (and the tab and thumbnails) closes it at once.
Window {
    id: shelfWin
    required property var modelData
    property var g                          // the Glimpse root

    screen: modelData
    x: modelData.virtualX                   // keep Qt's idea of the position on this screen,
    y: modelData.virtualY                   // or it re-homes the window to another one
    transientParent: null
    visible: false
    color: "transparent"
    // below the lip it is see-through (fillets, tab, around the thumbnails): click-through the moment it closes
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | (g.shelfOpen ? 0 : Qt.WindowTransparentForInput)
    width: modelData.width
    height: g.barH + g.tabH + dropGap + thumbs.fullHeight + g.px(24)
    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: g.fsMode ? LayerShell.Window.LayerOverlay : LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: false

    property real morph: 0                  // 0 = the resting band, 1 = open
    readonly property real lip: Math.max(0, Math.min(1, morph))
    readonly property real bandH: g.stripHeight + (g.barH - g.stripHeight) * morph
    readonly property int dropGap: g.px(6)
    // rebuilt mid-animation (screen change): don't leave the resting band hidden
    Component.onDestruction: {
        g.shelfShown = false; g.shelfMapped = false; g.shelfOpen = false; g.menuOpen = false
        g.hoverTile = null; g.bandHovered = false; g.dropHovered = false
    }

    // Stays mapped (above the strip, which maps first), so opening never waits for the window to come
    // up (~70 ms the first time). While closed it draws nothing: the band's material has no height and
    // everything else has faded out. Over a fullscreen window it only maps while open, so nothing sits
    // on top of a game.
    readonly property bool drawn: morph > 0 || g.shelfOpen
    function ensureMapped() {
        unmap.stop()
        if (!visible) {
            visible = true
            g.shelfMapped = true
        }
    }
    Timer {
        id: unmap
        interval: 1000
        onTriggered: {
            if (!shelfWin.g.fsMode || shelfWin.g.shelfOpen || shelfWin.morph > 0) return
            shelfWin.visible = false
            shelfWin.g.shelfMapped = false
        }
    }
    // after a fullscreen window: map again once the strip is back, so this one lands above it
    Timer { id: remap; interval: 150; onTriggered: if (!shelfWin.g.fsMode) shelfWin.ensureMapped() }
    Component.onCompleted: remap.start()

    Connections {
        target: shelfWin.g
        function onFsModeChanged() {
            if (!shelfWin.g.fsMode) remap.restart()
            else if (!shelfWin.g.shelfOpen) unmap.restart()
        }
        function onShelfOpenChanged() {
            const g = shelfWin.g
            if (g.shelfOpen) {
                closeMorph.stop()
                // back before it had folded away: carry on from where it is, no second light
                if (shelfWin.morph < 0.3) glintRun.restart()
                shelfWin.ensureMapped()
                openMorph.restart()
                g.shelfRevealed()
            } else {
                openMorph.stop()
                g.shelfShown = false        // the resting band is back underneath while this one folds away
                g.shelfClosing()
                closeMorph.restart()
            }
        }
    }
    // opens with a quick, soft grow (from wherever a closing left it); closes at once, the icons
    // fading back into the lip
    SequentialAnimation {
        id: openMorph
        NumberAnimation { target: shelfWin; property: "morph"; to: 1; duration: Tokens.ms(170); easing.type: Easing.OutQuart }
        // drawn for a good few frames by now: the resting band can step aside without a flicker
        ScriptAction { script: if (shelfWin.g.shelfOpen) shelfWin.g.shelfShown = true }
    }
    // the light that runs out along the rim from where the pointer met the edge
    property real glint: 1
    NumberAnimation { id: glintRun; target: shelfWin; property: "glint"; from: 0; to: 1; duration: Tokens.ms(650); easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: closeMorph
        NumberAnimation { target: shelfWin; property: "morph"; to: 0; duration: Tokens.fast; easing.type: Easing.OutCubic }
        ScriptAction { script: if (!shelfWin.g.shelfOpen && shelfWin.g.fsMode) unmap.restart() }
    }

    // ------------------------------------------------------------------ the label tab
    // it drips from the lip under the lens; the lens and the tab follow the hovered icon
    property string tabText: ""
    readonly property IconTile lensTile: g.lensTile
    onLensTileChanged: if (lensTile) tabText = lensTile.appName      // keeps its text while it retracts
    readonly property bool tabWanted: lensTile !== null && morph > 0.85
    property real tabDrop: tabWanted ? g.tabH : 0
    Behavior on tabDrop { NumberAnimation { duration: shelfWin.tabWanted ? Tokens.base : Tokens.fast; easing.type: shelfWin.tabWanted ? Tokens.enter : Tokens.exit } }
    property real tabWidth: Math.min(width - 2 * g.fillet - 40, tabLabel.implicitWidth + 2 * g.px(14))
    Behavior on tabWidth { enabled: shelfWin.tabDrop > 1; NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
    readonly property real tabGrown: Math.max(0, Math.min(1, tabDrop / g.tabH))

    Notch {
        id: notch
        width: parent.width
        height: shelfWin.drawn ? g.barH + g.tabH + 20 : 0
        bandH: shelfWin.bandH
        bezelH: g.stripHeight * (1 - shelfWin.lip)     // the resting strip melts into the glass as it opens
        fillet: g.fillet
        glass: shelfWin.lip
        glint: shelfWin.glint
        glintX: g.edgeX
        tabX: lens.x + lens.width / 2
        tabW: shelfWin.tabWidth * (0.6 + 0.4 * shelfWin.tabGrown)     // a droplet that widens as it drops
        tabH: Math.max(0, shelfWin.tabDrop) * shelfWin.lip
        tabRadius: Tokens.radius.sm
        backdrop: g.glassUrl
        backdropSize: Qt.size(shelfWin.width, g.glassBand)
        bezel: g.cBezel
        tintA: g.washA
        tintB: g.washB
        tintC: g.washC
        rimA: g.cPrimary
        rimB: g.cTertiary
        rimStops: g.pal.values._rim || []
        shimmer: g.shelfOpen
        glow: g.cPrimary
    }
    Text {
        id: tabLabel
        x: notch.tL + g.px(14)
        y: shelfWin.bandH
        width: Math.max(0, notch.tabW - 2 * g.px(14))
        height: notch.tabH
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: shelfWin.tabText
        elide: Text.ElideRight
        opacity: Math.max(0, Math.min(1, (notch.tabH - g.tabH * 0.5) / (g.tabH * 0.4)))
        color: g.cFg
        font.family: Tokens.font.ui
        font.pixelSize: g.px(Tokens.size.label)
        font.weight: Font.DemiBold
    }

    // ------------------------------------------------------------------ the band itself
    Item {
        id: band
        width: parent.width
        height: shelfWin.bandH
        HoverHandler { onHoveredChanged: shelfWin.g.bandHovered = hovered }

        // the lens under the hovered icon: its leading edge moves first, so it stretches toward
        // the target and settles, without overshoot
        Rectangle {
            id: lens
            property real edgeL: 0
            property real edgeR: 0
            property bool toRight: true
            readonly property IconTile target: shelfWin.lensTile
            property color tint: target ? target.tint : g.cPrimary       // glows in the hovered app's colour
            Behavior on tint { ColorAnimation { duration: Tokens.base } }
            // while invisible it jumps straight to the first target instead of sliding in from the last one
            Behavior on edgeL { enabled: lens.opacity > 0.05; NumberAnimation { duration: lens.toRight ? Tokens.base : Tokens.fast; easing.type: Tokens.enter } }
            Behavior on edgeR { enabled: lens.opacity > 0.05; NumberAnimation { duration: lens.toRight ? Tokens.fast : Tokens.base; easing.type: Tokens.enter } }
            x: edgeL
            width: Math.max(0, edgeR - edgeL)
            y: 2
            height: g.barH - 5
            radius: Math.round(Tokens.radius.sm * g.topScale)
            opacity: target && shelfWin.morph > 0.6 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
            gradient: Gradient {
                GradientStop { position: 0; color: C.alpha("#ffffff", 0.10) }
                GradientStop { position: 1; color: C.alpha(lens.tint, 0.26) }
            }
            border.width: 1
            border.color: C.alpha("#ffffff", Tokens.alpha.outlineStrong * 0.8)
            function aim(t) {
                const p = t.mapToItem(band, 0, 0)
                const l = p.x + 2, r = p.x + g.fitSlot - 2      // the icon's slot, not its name
                toRight = l >= edgeL
                edgeL = l
                edgeR = r
            }
            onTargetChanged: if (target) aim(target)
            Connections {
                target: lens.target
                function onXChanged() { lens.aim(lens.target) }
            }
        }

        Row {
            id: icons
            x: g.leftPad
            height: g.barH
            spacing: 0
            Repeater {
                model: shelfWin.g.groups
                delegate: Row {
                    id: group
                    required property var modelData
                    required property int index
                    visible: list.count > 0
                    spacing: 0
                    Item {          // hairline between screens
                        visible: group.index > shelfWin.g.firstGroup
                        width: 11
                        height: shelfWin.g.barH
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1
                            height: parent.height * 0.42 * shelfWin.lip
                            color: C.alpha(shelfWin.g.cFg, 0.22)
                        }
                    }
                    ListView {
                        id: list
                        height: shelfWin.g.barH
                        width: contentWidth
                        orientation: ListView.Horizontal
                        interactive: false
                        spacing: 0
                        model: group.modelData.apps
                        delegate: IconTile { g: shelfWin.g }
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                                NumberAnimation { property: "scale"; from: 0.85; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit }
                                NumberAnimation { property: "scale"; to: 0.85; duration: Tokens.fast; easing.type: Tokens.exit }
                            }
                        }
                        displaced: Transition { NumberAnimation { property: "x"; duration: Tokens.base; easing.type: Tokens.move } }
                    }
                }
            }
            Text {          // nothing open yet
                visible: shelfWin.g.firstGroup < 0
                height: shelfWin.g.barH
                leftPadding: 4
                verticalAlignment: Text.AlignVCenter
                opacity: shelfWin.lip
                text: i18n("No open windows")
                color: shelfWin.g.cFgDim
                font.family: Tokens.font.ui
                font.pixelSize: shelfWin.g.px(Tokens.size.label)
                font.weight: Font.Medium
            }
        }

        MediaModule {
            id: media
            g: shelfWin.g
            visible: g.cfg.showMedia && opacity > 0
            open: g.shelfOpen
            pop: Math.max(0, Math.min(1, (shelfWin.morph - 0.5) * 2))
            width: implicitWidth
            x: band.width - g.fillet - g.px(10) - width
            y: Math.round((g.barH - height) / 2) - 1
        }
    }
    // icons get the band up to the media module; their slots shrink when there are too many
    Binding {
        target: shelfWin.g
        property: "iconRoom"
        value: (media.present && shelfWin.g.cfg.showMedia ? media.x - shelfWin.g.px(16) : shelfWin.width - shelfWin.g.fillet - 8) - shelfWin.g.leftPad
    }

    Connections {       // centred under the app's icon (kept while it fades out)
        target: shelfWin.g
        function onThumbTileChanged() {
            const t = shelfWin.g.thumbTile
            if (t) thumbs.centerX = t.mapToItem(drop, shelfWin.g.fitSlot / 2, 0).x
        }
    }

    // ------------------------------------------------------------------ under the band: tab and thumbnails
    // One hover area for both, so moving from an icon down onto its thumbnails keeps the band open.
    // It is their parent, not an overlay: an overlay's HoverHandler would take the hover from the cards.
    Item {
        id: drop
        y: shelfWin.bandH
        width: parent.width
        height: Math.max(0, parent.height - y)
        HoverHandler { id: dropHover }
        readonly property point p: dropHover.point.position
        readonly property bool inside: dropHover.hovered && (
            (p.x >= notch.tL && p.x <= notch.tR && p.y <= notch.tabH)
            || (thumbs.visible && p.x >= thumbs.x && p.x <= thumbs.x + thumbs.width
                && p.y >= thumbs.y - shelfWin.dropGap && p.y <= thumbs.y + thumbs.height))
        onInsideChanged: shelfWin.g.dropHovered = inside

        ThumbStrip {
            id: thumbs
            g: shelfWin.g
            tile: shelfWin.g.thumbTile
            y: shelfWin.g.tabH + shelfWin.dropGap
            minX: shelfWin.g.fillet + shelfWin.g.px(8)
            maxX: drop.width - shelfWin.g.fillet - shelfWin.g.px(8)
        }
    }
}
