import QtQuick
import Atom
import Rice

// The Theme page's Launcher (every screen): its style (a picture of each; picking the other closes this one and opens
// it), its size, and its backdrop, the power page's too (each over this screen's wallpaper as that style shows it).
Column {
    id: lc
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var styles: (studio.row("lstyle") || { items: [] }).items
    readonly property var size: ((studio.row("lsize") || { items: [] }).items || [])[0] || null
    readonly property var backdrops: (studio.row("backdrop") || { items: [] }).items
    readonly property string wall: studio.targetThumb ? "file://" + studio.targetThumb : ""

    StudioCap { studio: lc.studio; text: "Style"; note: "picking the other opens it at once" }
    Item { width: 1; height: lc.d(14) }
    Row {
        spacing: lc.d(18)
        Repeater {
            model: lc.styles
            StudioCard {
                id: sc
                required property var modelData
                readonly property bool atom: modelData.style === "atom"
                studio: lc.studio
                picW: lc.d(400); picH: lc.d(225)
                fkey: "ls:" + modelData.style
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: modelData.current ? "In use" : "Switch to it"
                onActivated: lc.studio.model.apply(modelData)
                RoundPic {
                    studio: lc.studio
                    anchors.fill: parent
                    Rectangle { anchors.fill: parent; color: C.mix(lc.lk.surfaceLowest, lc.lk.surfaceHigh, 0.35) }
                    Item {      // Simplified: a hero over rows of tiles
                        visible: !sc.atom
                        anchors.fill: parent
                        Rectangle { x: lc.d(24); y: lc.d(30); width: lc.d(60); height: lc.d(8); radius: lc.d(4); color: lc.lk.fg; opacity: 0.4 }
                        Rectangle { x: lc.d(24); y: lc.d(50); width: lc.d(110); height: lc.d(18); radius: lc.d(4); color: lc.lk.fg; opacity: 0.75 }
                        Repeater {
                            model: 12
                            Rectangle {
                                required property int index
                                x: lc.d(24) + (index % 6) * lc.d(64); y: lc.d(104) + Math.floor(index / 6) * lc.d(52)
                                width: lc.d(54); height: lc.d(40); radius: lc.d(8)
                                color: index % 6 === 0 ? lc.lk.primary : C.alpha(lc.lk.fg, 0.2)
                            }
                        }
                    }
                    Item {      // Atom's: rings round a core
                        visible: sc.atom
                        anchors.fill: parent
                        Rectangle { x: lc.d(24); y: lc.d(96); width: lc.d(120); height: lc.d(20); radius: lc.d(4); color: lc.lk.fg; opacity: 0.75 }
                        Item {
                            x: parent.width - lc.d(220); y: lc.d(12); width: lc.d(200); height: width
                            Repeater {
                                model: [40, 62, 84]
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    anchors.centerIn: parent
                                    width: lc.d(2 * modelData); height: width; radius: width / 2
                                    color: "transparent"; border.width: lc.d(1.5); border.color: C.alpha(lc.lk.fg, 0.5 - index * 0.12)
                                }
                            }
                            Rectangle { anchors.centerIn: parent; width: lc.d(48); height: width; radius: width / 2; color: lc.lk.primary; opacity: 0.85 }
                            Repeater {
                                model: [[60, 100], [140, 100], [100, 38], [41, 75], [158, 128], [100, 184]]
                                Rectangle { required property var modelData; x: lc.d(modelData[0] - 7); y: lc.d(modelData[1] - 7); width: lc.d(14); height: width; radius: width / 2; color: lc.lk.fg; opacity: 0.7 }
                            }
                        }
                    }
                }
            }
        }
    }
    Item { width: 1; height: lc.d(40) }
    StudioCap { studio: lc.studio; text: "Size"; note: "on each screen's standard size" }
    Item { width: 1; height: lc.d(14) }
    StudioSlider {
        visible: !!lc.size
        studio: lc.studio
        fkey: "sl:lsize"
        value: lc.size ? lc.size.v : 1
        min: lc.size ? lc.size.min : 0.8; max: lc.size ? lc.size.max : 1.8; step: lc.size ? lc.size.step : 0.05
        def: lc.size ? lc.size.def : 1
        defLabel: "Standard"
        desc: "<b>Launcher size</b> This launcher and its pages on every screen. Left and right to change it."
        onCommit: v => lc.studio.slide(lc.size, v)
    }
    Item { width: 1; height: lc.d(40) }
    StudioCap { studio: lc.studio; text: "Backdrop"; note: "the launcher and the power page" }
    Item { width: 1; height: lc.d(14) }
    Row {
        spacing: lc.d(18)
        Repeater {
            model: lc.backdrops
            StudioCard {
                id: bc
                required property var modelData
                readonly property string st: modelData.style
                studio: lc.studio
                picW: lc.d(300); picH: lc.d(169)
                fkey: "bd:" + st
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: "Use this style"
                onActivated: lc.studio.model.apply(modelData)
                RoundPic {
                    studio: lc.studio
                    anchors.fill: parent
                    Image {     // (blurred by decoding it tiny: the matte and the clear one)
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: lc.wall
                        sourceSize.width: bc.st === "matte" ? 28 : bc.st === "clear" ? 56 : 360
                        smooth: true
                    }
                    Rectangle { visible: bc.st === "matte"; anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28) }
                    Item {      // clear: the windows behind show through the glass
                        visible: bc.st === "clear"
                        anchors.fill: parent
                        Rectangle { x: parent.width * 0.14; y: parent.height * 0.16; width: parent.width * 0.46; height: parent.height * 0.56; radius: lc.d(10); color: Qt.rgba(0.92, 0.92, 0.95, 0.75)
                                    Rectangle { width: parent.width; height: lc.d(14); radius: lc.d(10); color: Qt.rgba(0.2, 0.2, 0.26, 0.85) } }
                        Rectangle { x: parent.width * 0.5; y: parent.height * 0.36; width: parent.width * 0.38; height: parent.height * 0.48; radius: lc.d(10); color: Qt.rgba(0.8, 0.8, 0.86, 0.65) }
                    }
                    Rectangle {
                        visible: bc.st === "none"
                        anchors.fill: parent
                        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.45) } GradientStop { position: 0.7; color: "transparent" } }
                    }
                    Image { visible: bc.st === "matte" || bc.st === "noise"; anchors.fill: parent; source: Prefs.grain; fillMode: Image.Tile; opacity: 0.16 }
                }
            }
        }
    }
}
