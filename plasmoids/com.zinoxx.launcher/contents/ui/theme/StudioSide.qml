import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The Theme page's side column: two panels of one kind (the same edge, heading and rows, so the column reads as one
// list in two scopes; the lab showed that a special box for the screen broke the flow).
//   Editing [screen]  accent glass: the desk as it stands (each screen to scale with its wallpaper; the one being
//                     edited framed in the accent with its label a filled chip, the others dimmed; a light in the
//                     panel sits under it and glides when it changes; "All screens" in the heading), then what
//                     belongs to that screen: Wallpapers and Colours, their icons its wallpaper and its accents
//   Everywhere        neutral glass: saved looks, the launcher, the desktop, the keyboards
// Every section shows its value now; walking them with the keys shows them.
Item {
    id: side
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    width: d(460)
    implicitHeight: here.height + d(18) + every.height

    // ---------------------------------------------------------------- the screen you're editing
    Item {
        id: here
        x: -side.d(16)
        width: side.width + side.d(32)
        height: hereCol.height + side.d(16)
        RectangularShadow { anchors.fill: parent; radius: side.d(26); blur: side.d(40); offset.y: side.d(16); spread: -side.d(6); color: Qt.rgba(0, 0, 0, 0.22) }
        Rectangle {
            anchors.fill: parent
            radius: side.d(26)
            color: C.alpha(C.mix(side.lk.surfaceLowest, side.lk.primary, 0.16), 0.66)
            border.width: side.d(1.5)
            border.color: C.alpha(side.lk.primary, 0.45)
        }
        Item {      // the light under the screen being edited (across the desk for all of them)
            anchors.fill: parent
            anchors.margins: side.d(2)
            clip: true
            RectangularShadow {
                readonly property var at: desk.lightAt
                width: at.w; height: side.d(110)
                x: at.x - width / 2 + side.d(14); y: desk.y + side.d(40) - height / 2
                radius: height / 2
                blur: side.d(70)
                color: C.alpha(side.lk.primary, 0.34)
                Behavior on x { NumberAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                Behavior on width { NumberAnimation { duration: Tokens.ms(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            }
        }
        Column {
            id: hereCol
            x: side.d(16); y: side.d(6)
            width: side.width
            Item {      // the heading: Editing [screen] ... All screens
                width: parent.width; height: side.d(46)
                Row {
                    x: side.d(18)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: side.d(10)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "edit"; color: side.lk.primary; font.family: Tokens.font.icons; font.pixelSize: side.d(19) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "EDITING"; color: side.lk.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: side.d(13); font.letterSpacing: side.d(1.2) }
                    ScreenTag { anchors.verticalCenter: parent.verticalCenter; studio: side.studio; small: true }
                }
                StudioChip {
                    studio: side.studio
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: side.d(32)
                    inSide: true
                    fkey: "scr:all"
                    text: "All screens"
                    chosen: side.studio.model.target === "all"
                    desc: "<b>All screens</b> Wallpapers and colours go to every screen at once."
                    act: chosen ? "Just this one" : "All of them"
                    onActivated: side.studio.setTarget(chosen ? side.studio.screenName : "all")
                }
            }
            // the desk: the screens as they sit, to scale
            Item {
                id: desk
                readonly property var scrs: (side.studio.model.screens || []).slice().sort((a, b) => a.x - b.x)
                readonly property real gap: side.d(12)
                readonly property real x0: scrs.length ? Math.min(...scrs.map(s => s.x)) : 0
                readonly property real y0: scrs.length ? Math.min(...scrs.map(s => s.y)) : 0
                readonly property real spanW: scrs.length ? Math.max(...scrs.map(s => s.x + s.w)) - x0 : 1
                readonly property real spanH: scrs.length ? Math.max(...scrs.map(s => s.y + s.h)) - y0 : 1
                // to the panel's width, but never taller than a strip (one screen alone would fill the panel)
                readonly property real k: Math.min((width - gap * Math.max(0, scrs.length - 1)) / Math.max(1, spanW), side.d(104) / Math.max(1, spanH))
                readonly property real ox: (width - (spanW * k + gap * Math.max(0, scrs.length - 1))) / 2
                readonly property real mapH: scrs.length ? Math.max(...scrs.map(s => (s.y - y0 + s.h) * k)) : side.d(90)
                function sx(i) { return ox + (scrs[i].x - x0) * k + i * gap }
                // where the light sits: under the target, or across the desk
                readonly property var lightAt: {
                    const t = side.studio.model.target, i = scrs.findIndex(s => s.name === t)
                    return i < 0 ? { x: width / 2, w: width * 0.9 } : { x: sx(i) + scrs[i].w * k / 2, w: Math.max(side.d(150), scrs[i].w * k * 1.1) }
                }
                width: parent.width
                height: mapH + side.d(44)
                Repeater {
                    model: desk.scrs.length
                    Focusable {
                        id: sc
                        required property int index
                        readonly property var s: desk.scrs[index] || ({})
                        readonly property bool tgt: side.studio.model.target === "all" || side.studio.model.target === s.name
                        readonly property string pv: side.studio.deskPv ? side.studio.deskPv[s.name] || "" : ""
                        studio: side.studio
                        inSide: true
                        fkey: "scr:" + s.name
                        x: desk.sx(index); y: side.d(6) + (s.y - desk.y0) * desk.k
                        width: s.w * desk.k; height: s.h * desk.k
                        lensRadius: side.d(7)
                        lensGap: side.d(11)
                        desc: "<b>" + s.label + "</b> Edit this screen: wallpapers and colours go to it."
                        act: "Edit it"
                        onActivated: side.studio.setTarget(s.name)
                        RectangularShadow {     // its glow when it's the one
                            anchors.fill: parent; anchors.margins: -side.d(4)
                            radius: side.d(11); blur: side.d(26); spread: side.d(2)
                            color: C.alpha(side.lk.primary, 0.5)
                            opacity: sc.tgt ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.ms(350) } }
                        }
                        RoundImage {
                            anchors.fill: parent
                            radius: side.d(7)
                            fill: C.alpha(side.lk.surfaceHigh, 0.6)
                            shadowBlur: side.d(12)
                            asynchronous: false
                            sourceWidth: 320
                            source: (sc.pv || sc.s.thumb) ? "file://" + (sc.pv || sc.s.thumb) : ""
                        }
                        Rectangle {     // the others, dimmed (the pointer on one lifts it)
                            anchors.fill: parent; radius: side.d(7)
                            color: Qt.rgba(0, 0, 0, 1)
                            opacity: sc.tgt || sc.hovered || sc.focused ? 0 : 0.42
                            Behavior on opacity { NumberAnimation { duration: Tokens.ms(400) } }
                        }
                        Rectangle {     // the frame: the accent, a gap away
                            anchors.fill: parent; anchors.margins: -side.d(7)
                            radius: side.d(13)
                            color: "transparent"
                            border.width: side.d(3); border.color: side.lk.primary
                            opacity: sc.tgt ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.ms(350) } }
                        }
                        Rectangle {     // "Preview": what A would put there
                            visible: sc.pv !== "" && sc.pv !== sc.s.thumb
                            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: side.d(5)
                            width: pvT.width + side.d(12); height: side.d(18); radius: side.d(5)
                            color: side.lk.primary
                            Text { id: pvT; anchors.centerIn: parent; text: "Preview"; color: side.lk.surfaceLowest; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: side.d(10.5) }
                        }
                        Rectangle {     // its label: a filled chip when it's the one
                            x: -side.d(4); y: parent.height + side.d(10)
                            width: lab.width + side.d(16); height: side.d(24); radius: side.d(8)
                            color: sc.tgt ? side.lk.primary : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.ms(350) } }
                            Text {
                                id: lab
                                anchors.centerIn: parent
                                text: sc.s.label + (sc.s.name === side.studio.screenName ? "  ●" : "")
                                color: sc.tgt ? side.lk.surfaceLowest : side.lk.fgDim
                                font.family: Tokens.font.ui; font.weight: sc.tgt ? Font.Bold : Font.Medium; font.pixelSize: side.d(13.5)
                            }
                        }
                    }
                }
            }
            Repeater {
                model: side.studio.sections.filter(x => x.scope === "here")
                StudioRailItem { required property var modelData; studio: side.studio; sec: modelData; panel: "here" }
            }
        }
    }

    // ---------------------------------------------------------------- everywhere
    Item {
        id: every
        x: -side.d(16)
        y: here.height + side.d(18)
        width: side.width + side.d(32)
        height: everyCol.height + side.d(16)
        RectangularShadow { anchors.fill: parent; radius: side.d(26); blur: side.d(40); offset.y: side.d(16); spread: -side.d(6); color: Qt.rgba(0, 0, 0, 0.22) }
        Rectangle {
            anchors.fill: parent
            radius: side.d(26)
            color: C.alpha(side.lk.surfaceLowest, 0.6)
            border.width: side.d(1.5)
            border.color: C.alpha(side.lk.fg, 0.13)
        }
        Column {
            id: everyCol
            x: side.d(16); y: side.d(6)
            width: side.width
            Item {
                width: parent.width; height: side.d(46)
                Row {
                    x: side.d(18)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: side.d(10)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "public"; color: side.lk.fgDim; font.family: Tokens.font.icons; font.pixelSize: side.d(19) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "EVERYWHERE"; color: side.lk.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: side.d(13); font.letterSpacing: side.d(1.2) }
                }
            }
            Repeater {
                model: side.studio.sections.filter(x => x.scope === "every")
                StudioRailItem { required property var modelData; studio: side.studio; sec: modelData; panel: "every" }
            }
        }
    }
}
