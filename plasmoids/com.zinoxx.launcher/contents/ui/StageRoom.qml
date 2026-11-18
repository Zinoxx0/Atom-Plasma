import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The room behind the launcher's content (Stage): what the focus is about fills it. A game: its own art,
// drifting in, fading into the room at the bottom. An app: the wallpaper coloured with the app's own colour
// and its icon large and blurred on the right (two slots, cross-faded as the focus moves). The Theme page:
// the wallpaper being looked at (a stack: each new one fades in OVER the one before, which stays until it's
// covered, so nothing between them shows through; an item with the same picture changes nothing). Then the
// text's scrims (as strong as the stage measured the text needs: stage.scrimHero, stage.rowsCurve) and, in
// the grainy styles, the grain over it all.
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
                    ImagePalette { id: glowColors; source: glow.item ? glow.item.icon : "" }
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
            // the Theme page's wallpapers: three layers, the newest on top (z), each fading in once its picture
            // has loaded (or after a moment, its thumbnail first), the ones under it let go once it's in
            Item {
                anchors.fill: parent
                opacity: room.paperO
                visible: opacity > 0.001
                Repeater {
                    id: paperRep
                    model: 3
                    Item {
                        id: paper
                        required property int index
                        anchors.fill: parent
                        readonly property var it: room.papers[index]
                        z: room.paperZ[index]
                        property real level: 0
                        opacity: level
                        visible: level > 0.001
                        // its full picture is there (or never will be): it can come in
                        readonly property bool ready: !it || !it.image || full.status === Image.Ready || full.status === Image.Error
                        function arrive(now) {
                            fadeIn.stop()
                            wait.stop()
                            if (now) { level = 1; room.paperIn(index); return }
                            level = 0
                            if (ready) fadeIn.restart(); else wait.restart()
                        }
                        function drop() { fadeIn.stop(); wait.stop(); level = 0 }
                        onReadyChanged: if (ready && wait.running) { wait.stop(); fadeIn.restart() }
                        Timer { id: wait; interval: 260; onTriggered: fadeIn.restart() }      // (a slow one: its thumbnail first)
                        NumberAnimation {
                            id: fadeIn
                            target: paper; property: "level"; to: 1
                            duration: Math.max(Tokens.ms(420), Math.round(room.stage.focusMs * 1.4))
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove
                            onFinished: room.paperIn(paper.index)
                        }
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: paper.it && paper.it.thumb ? "file://" + paper.it.thumb : ""
                            smooth: true
                        }
                        Image {
                            id: full
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(room.stage.width, room.stage.height)
                            source: paper.it && paper.it.image ? "file://" + paper.it.image : ""
                            opacity: status === Image.Ready ? 1 : 0
                            // (only over its own thumbnail, on a layer already showing: one that waited comes in sharp)
                            Behavior on opacity { enabled: paper.level > 0.001; NumberAnimation { duration: Tokens.ms(300) } }
                        }
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
                visible: room.style.grainy       // (noisy matte, noisy only; clear blur is clear: no grain)
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
    property var artLevel: [0, 0]
    property var glowLevel: [0, 0]
    property int slot: 0
    property var shown: null
    // the Theme page's wallpapers (paperRep): { thumb, image } per layer, their order (z), the one on top
    property var papers: [null, null, null]
    property var paperZ: [0, 0, 0]
    property int paperTop: -1
    property int paperSeq: 0
    property real paperO: 0                 // the stack as a whole (in on the Theme page, out on the others)
    function show(it) {
        if (!it || it === room.shown || (it.ctl && it.ctl !== "group")) return     // (a row's "Show more" keeps the room)
        const was = room.shown
        room.shown = it
        if (it.kind) {          // the Theme page: the wallpaper it's about (the screen's own for any other item)
            showPaper(room.stage.paperOf(it))
            if (!(was && was.kind)) fadeTo(null, true)      // (from the home's rooms: they go, the stack comes)
            return
        }
        fadeTo(it, false)
    }
    function fadeTo(it, paper) {
        const next = room.slot ^ 1
        const nextItems = room.items.slice(); nextItems[next] = paper ? null : it; room.items = nextItems
        bgFade.slotFrom = room.slot
        bgFade.slotTo = next
        bgFade.art = !!(it && it.art && it.art.hero)
        bgFade.paper = paper
        bgFade.p0 = room.paperO
        room.slot = next
        bgFade.restart()
    }
    function samePaper(a, b) { return !!a && !!b && (a.image || a.thumb || "") === (b.image || b.thumb || "") }
    function showPaper(p) {
        if (paperTop >= 0 && samePaper(papers[paperTop], p)) return        // (already shown, or on its way)
        // a free layer (not showing), else the lowest one (under the two above it: it shows least)
        let s = -1, low = Infinity
        for (let i = 0; i < 3 && s < 0; i++) { const l = paperRep.itemAt(i); if (i !== paperTop && (!l || l.level <= 0.001)) s = i }
        for (let i = 0; i < 3 && s < 0; i++) if (i !== paperTop && paperZ[i] < low) low = paperZ[i]
        if (s < 0) s = paperZ.indexOf(low)
        const ps = papers.slice(); ps[s] = p; papers = ps
        const zs = paperZ.slice(); zs[s] = ++paperSeq; paperZ = zs
        paperTop = s
        const l = paperRep.itemAt(s)
        if (l) l.arrive(paperO < 0.01)      // (the stack hidden: in at once, the room's fade brings it in)
        if (Shell.debug) console.warn("ATOM room paper", s, p ? p.image || p.thumb : "")
    }
    function paperIn(i) {       // a layer is all in: the ones under it can go
        if (i !== paperTop) return
        for (let k = 0; k < 3; k++) if (k !== i) { const l = paperRep.itemAt(k); if (l) l.drop() }
    }
    function clearPapers() {
        for (let k = 0; k < 3; k++) { const l = paperRep.itemAt(k); if (l) l.drop() }
        papers = [null, null, null]
        paperTop = -1
    }
    NumberAnimation {
        id: bgFade
        property int slotFrom: 0
        property int slotTo: 1
        property bool art: false
        property bool paper: false
        property real p0: 0
        target: bgFade; property: "v"; from: 0; to: 1
        duration: Math.max(Tokens.ms(420), Math.round(room.stage.focusMs * 1.8))
        easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove
        property real v: 0
        onVChanged: {
            const a = room.artLevel.slice(), g = room.glowLevel.slice()
            a[slotTo] = art && !paper ? v * 0.9 : 0
            g[slotTo] = art || paper ? 0 : v
            a[slotFrom] = a[slotFrom] * (1 - v)
            g[slotFrom] = g[slotFrom] * (1 - v)
            room.artLevel = a
            room.glowLevel = g
            room.paperO = paper ? p0 + (1 - p0) * v : p0 * (1 - v)
        }
        onFinished: if (!paper) room.clearPapers()      // (off the Theme page: its pictures let go)
    }
}
