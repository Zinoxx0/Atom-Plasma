import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The room behind the launcher's content (Stage): what the focus is about fills it, two slots cross-faded
// as the focus moves. A game: its own art, drifting in, fading into the room at the bottom. An app: the
// wallpaper coloured with the app's own colour and its icon large and blurred on the right. The Theme
// page: the wallpaper being looked at. Then the text's scrims (as strong as the stage measured the text
// needs: stage.scrimHero, stage.rowsCurve) and, in noisy matte, the grain over it all.
//   show(it)   the focused item (a "Show more" control keeps the room as it is); shown = the last one
Item {
    id: room
    required property var stage             // the Stage (Window): rice, bgO, phase, launcher, focusMs, scrims, paperOf()
    required property Backdrop style        // the blur style's backdrop (Atom Backdrop)

    Item {
        id: pictures
        anchors.fill: parent
        opacity: room.stage.bgO
        visible: room.stage.phase !== "closed" && opacity > 0.001
        Item {
            id: backdrop
            anchors.fill: parent

            // an app with no art of its own: the wallpaper, coloured with the app's own colour (its icon's
            // dominant one), and the icon large on the right (two slots, cross-faded)
            Repeater {
                model: 2
                Item {
                    id: glow
                    required property int index
                    anchors.fill: parent
                    opacity: room.slot === index ? room.glowLevel[index] : 0
                    visible: opacity > 0.001
                    property var item: room.items[index]
                    Kirigami.ImageColors { id: glowColors; source: glow.item ? glow.item.icon : "" }
                    readonly property color c: C.appTint(glowColors, room.stage.rice.primary)
                    Image {     // noisy matte: the frosted wallpaper itself, coloured
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        visible: room.style.matte
                        source: visible ? room.style.frostSource : ""
                        layer.enabled: glow.visible && visible
                        layer.effect: MultiEffect { colorization: 0.55; colorizationColor: glow.c; brightness: 0.04 }
                    }
                    Rectangle {     // clear blur: a breath of its colour on the glass
                        anchors.fill: parent
                        visible: room.style.glass
                        color: C.alpha(glow.c, 0.08)
                    }
                    Kirigami.Icon {     // (a blurred filter: not in no blur)
                        x: parent.width * 0.94 - width; y: parent.height * 0.04
                        width: parent.height * 0.46; height: width
                        visible: !room.style.sharp
                        source: glow.item && visible ? glow.item.icon : ""
                        opacity: 0.5
                        layer.enabled: glow.visible && visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.4 }
                    }
                }
            }
            // a game fills it with its own art, drifting a little as it arrives
            Repeater {
                model: 2
                Image {
                    id: art
                    required property int index
                    x: 0; y: 0
                    width: parent.width
                    height: parent.height * 0.78
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                    source: room.items[index] && room.items[index].art ? room.items[index].art.hero : ""
                    opacity: room.slot === index ? room.artLevel[index] : 0
                    visible: opacity > 0.001
                    transformOrigin: Item.Top
                    layer.enabled: visible
                    layer.effect: MultiEffect {     // fades into the room at the bottom
                        maskEnabled: true
                        maskSource: artMask
                        maskThresholdMin: 0.5       // with the spread: smoothstep over the mask's whole 0..1 alpha
                        maskSpreadAtMin: 1.0        // (the defaults let every pixel through: a hard cut where the art ends)
                    }
                    NumberAnimation on scale { id: drift; running: false; from: 1.07; to: 1; duration: Tokens.ms(9000); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.22, 0.6, 0.3, 1, 1, 1] }
                    onSourceChanged: if (source != "" && !room.stage.launcher.unplugged && !room.stage.launcher.saverOn) drift.restart(); else { drift.stop(); scale = 1 }
                }
            }
            Repeater {
                model: 2
                Item {
                    id: paper
                    required property int index
                    anchors.fill: parent
                    readonly property var it: room.papers[index]
                    opacity: room.slot === index ? room.paperLevel[index] : 0
                    visible: opacity > 0.001
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: paper.it && paper.it.thumb ? "file://" + paper.it.thumb : ""
                        smooth: true
                    }
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(room.stage.width, room.stage.height)
                        source: paper.it && paper.it.image ? "file://" + paper.it.image : ""
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.ms(300) } }
                    }
                }
            }
            // Text over a picture reads by measure, not by luck: the theme engine says how bright the backdrop
            // gets under the hero and under the rows (the palette's _backdrop for this screen's frosted
            // wallpaper; a game's banner its own, launcher-data's light), and a scrim of the palette's darkest
            // surface comes in exactly as strong as the dimmest text there needs for 4.5:1, and no stronger
            // (a blanket shade turned every wallpaper into the same dark mud)
            Rectangle {     // under the hero: from the left
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.scrimHero) }
                    GradientStop { position: 0.4; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.scrimHero) }
                    GradientStop { position: 0.62; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.scrimHero * 0.45) }
                    GradientStop { position: 0.85; color: C.alpha(room.stage.rice.surfaceLowest, 0) }
                }
            }
            Rectangle {     // under the rows: one smooth curve from 0% at the top to the bottom of the screen (rowsCurve)
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: room.stage.rowsCurve[0].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[0].a) }
                    GradientStop { position: room.stage.rowsCurve[1].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[1].a) }
                    GradientStop { position: room.stage.rowsCurve[2].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[2].a) }
                    GradientStop { position: room.stage.rowsCurve[3].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[3].a) }
                    GradientStop { position: room.stage.rowsCurve[4].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[4].a) }
                    GradientStop { position: room.stage.rowsCurve[5].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[5].a) }
                    GradientStop { position: room.stage.rowsCurve[6].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[6].a) }
                    GradientStop { position: room.stage.rowsCurve[7].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[7].a) }
                    GradientStop { position: room.stage.rowsCurve[8].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[8].a) }
                    GradientStop { position: room.stage.rowsCurve[9].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[9].a) }
                    GradientStop { position: room.stage.rowsCurve[10].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[10].a) }
                    GradientStop { position: room.stage.rowsCurve[11].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[11].a) }
                    GradientStop { position: room.stage.rowsCurve[12].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[12].a) }
                    GradientStop { position: room.stage.rowsCurve[13].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[13].a) }
                    GradientStop { position: room.stage.rowsCurve[14].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[14].a) }
                    GradientStop { position: room.stage.rowsCurve[15].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[15].a) }
                    GradientStop { position: room.stage.rowsCurve[16].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[16].a) }
                    GradientStop { position: room.stage.rowsCurve[17].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[17].a) }
                    GradientStop { position: room.stage.rowsCurve[18].p; color: C.alpha(room.stage.rice.surfaceLowest, room.stage.rowsCurve[18].a) }
                }
            }
            // a fine grain over it all: the dark, smooth gradients of a blurred picture band in 8 bits; noise
            // breaks the bands up (dithering)
            Image {
                anchors.fill: parent
                visible: room.style.matte        // (clear blur is clear: no grain)
                source: visible ? room.style.grain : ""
                fillMode: Image.Tile
                smooth: false
                opacity: room.style.grainAlpha
            }
        }
    }
    Rectangle {     // the game art's fade into the room
        id: artMask
        width: room.stage.width
        height: room.stage.height * 0.78
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0; color: "black" }
            GradientStop { position: 0.45; color: "black" }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    property var items: [null, null]
    property var papers: [null, null]       // the Theme page: { thumb, image } of the wallpaper shown
    property var paperLevel: [0, 0]
    property var artLevel: [0, 0]
    property var glowLevel: [0, 0]
    property int slot: 0
    property var shown: null
    function show(it) {
        if (!it || it === room.shown || it.ctl) return          // (a row's "Show more" keeps the room as it is)
        room.shown = it
        const next = room.slot ^ 1
        const nextItems = room.items.slice(); nextItems[next] = it.kind ? null : it; room.items = nextItems
        const nextPapers = room.papers.slice(); nextPapers[next] = it.kind ? room.stage.paperOf(it) : null; room.papers = nextPapers
        bgFade.paper = !!it.kind
        const hasArt = !!(it.art && it.art.hero)
        bgFade.slotFrom = room.slot
        bgFade.slotTo = next
        bgFade.art = hasArt
        room.slot = next
        bgFade.restart()
    }
    NumberAnimation {
        id: bgFade
        property int slotFrom: 0
        property int slotTo: 1
        property bool art: false
        property bool paper: false
        target: bgFade; property: "v"; from: 0; to: 1
        duration: Math.max(Tokens.ms(420), Math.round(room.stage.focusMs * 1.8))
        easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove
        property real v: 0
        onVChanged: {
            const a = room.artLevel.slice(), g = room.glowLevel.slice(), w = room.paperLevel.slice()
            a[slotTo] = art && !paper ? v * 0.9 : 0
            g[slotTo] = art || paper ? 0 : v
            w[slotTo] = paper ? v : 0
            a[slotFrom] = a[slotFrom] * (1 - v)
            g[slotFrom] = g[slotFrom] * (1 - v)
            w[slotFrom] = w[slotFrom] * (1 - v)
            room.artLevel = a
            room.glowLevel = g
            room.paperLevel = w
        }
    }
}
