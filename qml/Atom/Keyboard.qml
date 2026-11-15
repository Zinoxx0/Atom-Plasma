import QtQuick
import QtQuick.Effects
import QtCore
import Atom.Native
import Rice

// The on-screen keyboard, for a game controller (bin/pad.py; Atom Pad holds its state): the active layout's
// keys (the daemon reads them from XKB: ~/.cache/rice/pad-keyboard.json), shifted and AltGr labels as the
// layout has them, a set of accented letters, and the keys a text field needs (Tab, Backspace, Enter, the
// cursor). It lives on its screen's sheet window (that surface never takes the keyboard while no panel is
// open, so the text field being typed into keeps the focus): Glass in the screen's palette, KWin's blur
// behind it, sized by the screen's UI size (a TV across the room gets big keys). The D-pad moves the focus
// (a ring that glides from key to key), A types the focused one, the pointer clicks any; typing goes through
// the daemon as key presses. It moves out of the way: dragged by any bare part of it (its edge and grip, the
// gaps, the hints; never from a key), or flipped between the bottom and the top of the screen (the
// controller's View). The window puts `shapes` in its input mask and blur.
Item {
    id: kb
    required property RicePalette pal
    required property string screenName
    property real ui: 1
    function u(n) { return Math.round(n * ui) }

    readonly property bool wanted: Pad.oskShown && Pad.oskScreen === screenName
    property real p: wanted ? 1 : 0
    Behavior on p { NumberAnimation { duration: kb.wanted ? Tokens.ms(340) : Tokens.ms(200); easing.type: Easing.BezierSpline
                                      easing.bezierCurve: kb.wanted ? Tokens.calmIn : Tokens.calmOut } }
    readonly property bool shown: p > 0.001
    readonly property real rise: (1 - p) * u(36)
    readonly property var shapes: shown ? [{ x: plate.x, y: plate.y + rise, width: plate.width, height: plate.height, radius: plate.radius }] : []

    // ---- the layout
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    WatchedJson { id: layoutFile; path: kb.home + "/.cache/rice/pad-keyboard.json" }
    readonly property var lay: layoutFile.value || ({ rows: [[], [], [], []] })
    readonly property bool hasAltGr: (lay.rows || []).some(r => r.some(k => !!(k.l[2] || k.l[3])))
    readonly property var accents: [["à", "á", "â", "ã", "ä", "è", "é", "ê", "ë", "ì", "í", "î", "ï"],
                                    ["ò", "ó", "ô", "õ", "ö", "ù", "ú", "û", "ü", "ç", "ñ"],
                                    ["ý", "ÿ", "æ", "œ", "ß", "€", "£", "«", "»", "¿", "¡"]]
    // rows of keys, 15 units wide each: { t: "char" | "text" | name, w (units), k (a layout key) | s (text) }
    readonly property var rows: {
        const r = lay.rows || [[], [], [], []]
        const chars = i => (r[i] || []).map(k => ({ t: "char", w: 1, k: k }))
        const texts = i => accents[i - 1].map(s => ({ t: "text", w: 1, s: s }))
        const acc = Pad.layer === "accents"
        const row1 = acc ? texts(1) : chars(1), row2 = acc ? texts(2) : chars(2), row3 = acc ? texts(3) : chars(3)
        const fill = (n, used) => Math.max(1, 15 - n - used)
        const out = [
            chars(0).concat([{ t: "bksp", w: fill(chars(0).length, 0) }]),
            [{ t: "tab", w: fill(row1.length, 0) }].concat(row1),
            [{ t: "layer", w: 1.75 }].concat(row2).concat([{ t: "enter", w: fill(row2.length, 1.75) }]),
            [{ t: "shift", w: 2.25 }].concat(row3).concat([{ t: "shift", w: fill(row3.length, 2.25) }]),
            [{ t: "left", w: 1.25 }, { t: "right", w: 1.25 }].concat(hasAltGr ? [{ t: "altgr", w: 1.5 }] : [])
                .concat([{ t: "space", w: hasAltGr ? 9 : 10.5 }, { t: "hide", w: 2 }]),
        ]
        return out
    }
    // what a key shows and types now (shift, caps on letters, AltGr)
    function letter(k) { return !!k.l[0] && k.l[0] !== k.l[0].toUpperCase() && k.l[1] === k.l[0].toUpperCase() }
    function level(k) {
        const up = Pad.shift === 1 || (Pad.shift === 2 && letter(k))
        return (Pad.altgr ? 2 : 0) + (up ? 1 : 0)
    }
    function label(key) {
        if (key.t === "char") { const k = key.k, l = level(k); return k.l[l] || k.l[l & 2] || k.l[0] }
        if (key.t === "text") return Pad.shift ? key.s.toUpperCase() : key.s
        return ({ bksp: "backspace", tab: "keyboard_tab", enter: "keyboard_return", shift: Pad.shift === 2 ? "keyboard_capslock" : "shift",
                  left: "chevron_left", right: "chevron_right", hide: "keyboard_hide", space: "", layer: "", altgr: "" })[key.t] || ""
    }
    readonly property var codes: ({ bksp: 14, tab: 15, enter: 28, space: 57, left: 105, right: 106 })
    function act(key) {
        if (key.t === "char") {
            const k = key.k, l = level(k)
            Pad.key(k.code, (l & 1 ? 1 : 0) | (l & 2 ? 2 : 0))
            if (Pad.shift === 1) Pad.shift = 0
            Pad.altgr = false
        } else if (key.t === "text") {
            Pad.text(Pad.shift ? key.s.toUpperCase() : key.s)
            if (Pad.shift === 1) Pad.shift = 0
        } else if (key.t in codes) Pad.key(codes[key.t], 0)
        else if (key.t === "shift") Pad.shift = (Pad.shift + 1) % 3
        else if (key.t === "altgr") Pad.altgr = !Pad.altgr
        else if (key.t === "layer") Pad.layer = Pad.layer === "letters" ? "accents" : "letters"
        else if (key.t === "hide") Pad.hide()
    }

    // ---- the D-pad's focus: a row and a key in it; up and down land on the key nearest across
    property int fr: 2
    property int fc: 5
    function centre(ri, ci) { let x = 0; const row = rows[ri] || []; for (let i = 0; i < ci; i++) x += row[i].w; return x + (row[ci] ? row[ci].w / 2 : 0) }
    Connections {
        target: Pad
        enabled: kb.wanted
        function onMove(dx, dy) {
            if (dx) { const n = (kb.rows[kb.fr] || []).length; kb.fc = (kb.fc + dx + n) % n; return }
            const nr = Math.max(0, Math.min(kb.rows.length - 1, kb.fr + dy))
            if (nr === kb.fr) return
            const x = kb.centre(kb.fr, kb.fc), row = kb.rows[nr]
            let best = 0, bd = Infinity
            for (let i = 0, at = 0; i < row.length; at += row[i].w, i++) { const d = Math.abs(at + row[i].w / 2 - x); if (d < bd) { bd = d; best = i } }
            kb.fr = nr
            kb.fc = best
        }
        function onPress() {
            const key = (kb.rows[kb.fr] || [])[kb.fc]
            if (!key) return
            const it = keyAt(kb.fr, kb.fc)
            if (it) it.flash()
            kb.act(key)
        }
    }
    Connections {
        target: Pad
        enabled: kb.wanted
        function onFlip() { kb.flip() }
    }
    onRowsChanged: { fr = Math.min(fr, rows.length - 1); fc = Math.min(fc, (rows[fr] || [1]).length - 1) }
    onWantedChanged: if (wanted) { fr = 2; fc = Math.floor(((rows[2] || []).length) / 2); report.restart() }
    function keyAt(ri, ci) { const r = rowRep.itemAt(ri); return r ? r.keyAt(ci) : null }
    property int built: 0                   // (keys made: itemAt() doesn't notify, the ring reads this)

    // ---- where it sits: its own place, as an offset from the default one (low over the bar, centred), kept
    // whole on the screen; it stays where it was put while plasmashell runs
    property real offX: 0
    property real offY: 0
    readonly property real baseX: (width - plate.width) / 2
    readonly property real baseY: height - plate.height - u(78)       // (above the bar's islands)
    readonly property real edge: u(12)
    function clampX(o) { return Math.max(edge - baseX, Math.min(width - plate.width - edge - baseX, o)) }
    function clampY(o) { return Math.max(edge - baseY, Math.min(height - plate.height - edge - baseY, o)) }
    readonly property bool high: baseY + offY < (height - plate.height) / 2
    // the controller's View: to the top of the screen, or back down to its default place
    function flip() {
        offX = 0
        offY = high ? 0 : clampY(u(48) - baseY)
        if (Shell.debug) console.warn("ATOM pad keyboard", high ? "up" : "down")
    }
    onWidthChanged: offX = clampX(offX)
    onHeightChanged: offY = clampY(offY)
    // where it is once it has settled, for whoever asks (Bus Peek "padKeyboard": the tests), in its screen's
    // logical coordinates
    Timer {
        id: report
        interval: 150
        onTriggered: if (kb.wanted) Bus.set("padKeyboard", { screen: kb.screenName, x: Math.round(plate.x), y: Math.round(plate.y),
                                                             width: Math.round(plate.width), height: Math.round(plate.height) })
    }
    Behavior on offX { enabled: !drag.active; NumberAnimation { duration: Tokens.ms(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
    Behavior on offY { enabled: !drag.active; NumberAnimation { duration: Tokens.ms(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }

    // ---- the plate: the sheet's glass, low over the bar, as wide as the screen allows
    readonly property real gap: u(7)
    readonly property real unit: Math.floor((plate.width - 2 * plate.pad + gap) / 15)
    readonly property real keyH: Math.round(unit * 0.86)
    Item {
        id: plate
        readonly property real pad: kb.u(16)
        readonly property real head: kb.u(26)              // (room for the grip; not "top": FINAL on Item)
        readonly property real radius: Math.round(Tokens.radius.xl * kb.ui)
        width: Math.min(kb.width - 2 * kb.u(24), kb.u(1020))
        height: head + 5 * (kb.keyH + kb.gap) - kb.gap + kb.u(14) + hints.height + pad
        x: Math.round(kb.baseX + kb.offX)
        y: Math.round(kb.baseY + kb.offY)
        onXChanged: report.restart()
        onYChanged: report.restart()
        visible: kb.shown
        opacity: kb.p
        transform: Translate { y: kb.rise }

        Glass {
            anchors.fill: parent
            radius: plate.radius
            fill: kb.pal.light ? Tokens.neutral.light : Tokens.neutral.dark
            fillAlpha: kb.pal.light ? 0.86 : 0.8
            rimA: kb.pal.primary
            rimB: kb.pal.tertiary
        }
        // its bare parts move it (declared under the keys: a press on a key always types). Measured in the
        // window's coordinates, which don't move with it (in its own, the moving plate fed back into the drag)
        Item {
            anchors.fill: parent
            HoverHandler { id: bare; cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            DragHandler {
                id: drag
                target: null
                // never takes a drag over from a key (by default a DragHandler may steal it from the MouseArea
                // under the pointer: pressing a key and moving a little moved the whole keyboard)
                grabPermissions: PointerHandler.TakeOverForbidden
                property point from
                onActiveChanged: {
                    if (active) from = Qt.point(kb.offX, kb.offY)
                    if (Shell.debug && !active) console.warn("ATOM pad keyboard dragged to", Math.round(plate.x), Math.round(plate.y))
                }
                onCentroidChanged: if (active) {
                    kb.offX = kb.clampX(from.x + centroid.scenePosition.x - centroid.scenePressPosition.x)
                    kb.offY = kb.clampY(from.y + centroid.scenePosition.y - centroid.scenePressPosition.y)
                }
            }
        }
        Rectangle {     // the grip
            anchors.horizontalCenter: parent.horizontalCenter
            y: kb.u(10)
            width: kb.u(46)
            height: kb.u(5)
            radius: height / 2
            color: C.alpha(kb.pal.fg, drag.active ? 0.55 : bare.hovered ? 0.4 : 0.22)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }

        Column {
            id: grid
            x: plate.pad
            y: plate.head
            spacing: kb.gap
            Repeater {
                id: rowRep
                model: kb.rows.length
                delegate: Row {
                    id: rowItem
                    required property int index
                    readonly property var row: kb.rows[index] || []
                    spacing: kb.gap
                    function keyAt(i) { return keyRep.itemAt(i) }
                    Repeater {
                        id: keyRep
                        model: rowItem.row.length
                        onItemAdded: kb.built++
                        delegate: Key {
                            required property int index
                            board: kb
                            key: rowItem.row[index] || ({ t: "", w: 1 })
                            ri: rowItem.index
                            ci: index
                        }
                    }
                }
            }
        }

        // the D-pad's focus: a white ring outside the key with a gap (the launcher's), gliding between keys
        Rectangle {
            id: ring
            readonly property Item found: (kb.rows, kb.built, kb.fr, kb.fc, rowRep.count, kb.keyAt(kb.fr, kb.fc))
            readonly property Item target: found && found.parent ? found : null
            readonly property real g: Math.max(2, kb.u(3))
            readonly property real w: Math.max(2, kb.u(2.5))
            visible: !!target && kb.shown
            x: target ? grid.x + target.x - g - w : 0
            y: target ? grid.y + target.parent.y + target.y - g - w : 0
            width: target ? target.width + 2 * (g + w) : 0
            height: target ? target.height + 2 * (g + w) : 0
            radius: kb.u(10) + g + w
            color: "transparent"
            border.width: w
            border.color: kb.pal.light ? kb.pal.fg : "#ffffff"
            Behavior on x { NumberAnimation { duration: Tokens.ms(140); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            Behavior on y { NumberAnimation { duration: Tokens.ms(140); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            Behavior on width { NumberAnimation { duration: Tokens.ms(140); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            RectangularShadow {     // its glow, in the accent
                z: -1
                anchors.fill: parent
                radius: parent.radius
                blur: kb.u(18)
                spread: -kb.u(4)
                color: C.alpha(kb.pal.primary, 0.45 * Math.max(0.4, kb.pal.glow))
            }
        }

        // the controller's buttons, quietly (the launcher's hints)
        Row {
            id: hints
            anchors.horizontalCenter: parent.horizontalCenter
            y: grid.y + grid.height + kb.u(14)
            spacing: kb.u(18)
            Repeater {
                model: [["A", "Type"], ["X", "Delete"], ["Y", "Space"], ["LT", "Shift"], ["RT", "áé"], ["LB  RB", "Cursor"], ["☰", "Enter"],
                        ["View", "Move"], ["B", "Close"]]
                Row {
                    required property var modelData
                    spacing: kb.u(6)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(kb.u(22), ht.implicitWidth + kb.u(12))
                        height: kb.u(22)
                        radius: modelData[0].length === 1 ? height / 2 : kb.u(6)
                        color: "transparent"
                        border.width: 1
                        border.color: C.alpha(kb.pal.fg, 0.24)
                        Text { id: ht; anchors.centerIn: parent; text: modelData[0]; color: kb.pal.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: kb.u(11.5) }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: kb.pal.muted; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: kb.u(12.5) }
                }
            }
        }
    }

    // ---- one key: candy glass, its label (the shifted and AltGr ones small in its corners on a symbol key)
    component Key: Item {
        id: k
        property var board: null           // (an inline component sees no ids of its file: the keyboard, passed in)
        property var key: ({ t: "", w: 1 })
        property int ri: 0
        property int ci: 0
        readonly property bool special: key.t !== "char" && key.t !== "text"
        readonly property bool jewel: key.t === "enter"
        readonly property bool on: (key.t === "shift" && Pad.shift > 0) || (key.t === "altgr" && Pad.altgr) || (key.t === "layer" && Pad.layer === "accents")
        readonly property bool dead: key.t === "char" && !!key.k.dead && !!key.k.dead[k.board.level(key.k)]
        width: Math.round(k.board.unit * key.w - k.board.gap)
        height: k.board.keyH
        function flash() { bump.restart() }
        scale: ma.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Easing.OutBack } }
        SequentialAnimation {
            id: bump
            NumberAnimation { target: k; property: "scale"; to: 0.92; duration: Tokens.ms(60) }
            NumberAnimation { target: k; property: "scale"; to: 1; duration: Tokens.ms(180); easing.type: Easing.OutBack }
        }
        Rectangle {
            anchors.fill: parent
            radius: k.board.u(10)
            color: k.jewel ? k.board.pal.primary
                 : k.on ? C.alpha(k.board.pal.primary, 0.34)
                 : C.alpha(k.board.pal.fg, (k.special ? 0.045 : 0.085) + (ma.containsMouse ? 0.05 : 0))
            border.width: 1
            border.color: k.on ? C.alpha(k.board.pal.primary, 0.8) : C.alpha(k.board.pal.edge, k.jewel ? 0 : 0.1)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Rectangle {     // a breath of light at the top (the glass's sheen)
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: parent.height * 0.45
                radius: parent.radius - 1
                visible: !k.jewel
                gradient: Gradient {
                    GradientStop { position: 0; color: C.alpha("#ffffff", 0.06) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Text {          // the label: a character, or the key's glyph
            anchors.centerIn: parent
            readonly property string glyph: k.board.label(k.key)
            text: k.key.t === "space" ? "" : k.key.t === "layer" ? (Pad.layer === "accents" ? "abc" : "áé")
                : k.key.t === "altgr" ? "AltGr" : glyph
            color: k.jewel ? k.board.pal.onPrimary : k.dead ? k.board.pal.primary : k.special ? k.board.pal.fgDim : k.board.pal.fg
            font.family: k.special && k.key.t !== "layer" && k.key.t !== "altgr" ? Tokens.font.icons : Tokens.font.ui
            font.weight: k.special ? Font.Medium : Font.DemiBold
            font.pixelSize: k.special && k.key.t !== "layer" && k.key.t !== "altgr" ? Math.round(k.board.keyH * 0.36) : Math.round(k.board.keyH * (k.key.t === "layer" || k.key.t === "altgr" ? 0.24 : 0.34))
        }
        Text {          // a symbol key's shifted character, small at the top left (not on letters: they're their capital)
            visible: k.key.t === "char" && !k.board.letter(k.key.k) && k.board.level(k.key.k) === 0 && !!k.key.k.l[1]
            x: k.board.u(7); y: k.board.u(4)
            text: visible ? k.key.k.l[1] : ""
            color: k.board.pal.muted
            font.family: Tokens.font.ui; font.pixelSize: Math.round(k.board.keyH * 0.2)
        }
        Text {          // its AltGr character, small at the bottom right
            visible: k.key.t === "char" && !Pad.altgr && !!k.key.k.l[2]
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: k.board.u(7); bottomMargin: k.board.u(4) }
            text: visible ? k.key.k.l[2] : ""
            color: C.alpha(k.board.pal.primary, 0.9)
            font.family: Tokens.font.ui; font.pixelSize: Math.round(k.board.keyH * 0.2)
        }
        Text {          // the space bar says the layout
            visible: k.key.t === "space"
            anchors.centerIn: parent
            text: String(k.board.lay.layout || "").toUpperCase() + (k.board.lay.variant ? " · " + k.board.lay.variant : "")
            color: k.board.pal.muted
            font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: Math.round(k.board.keyH * 0.2); font.letterSpacing: k.board.u(1.5)
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true           // (a press that starts on a key types: it never moves the keyboard)
            cursorShape: Qt.PointingHandCursor
            onClicked: { k.board.fr = k.ri; k.board.fc = k.ci; k.board.act(k.key) }
        }
    }
}
