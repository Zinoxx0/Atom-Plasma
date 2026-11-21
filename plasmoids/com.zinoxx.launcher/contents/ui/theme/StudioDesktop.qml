import QtQuick
import Atom
import Rice

// The Theme page's Desktop (every screen): the top bar's size, the taskbar's (Automatic: each screen at its standard
// size times this; off: this size on every screen) and its islands' glass, each over this screen's wallpaper.
Column {
    id: dc
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property var topSize: ((studio.row("top") || { items: [] }).items || [])[0] || null
    readonly property var tsizeRow: studio.row("tsize")
    readonly property var tsize: tsizeRow ? tsizeRow.items[0] : null
    readonly property var auto: tsizeRow && tsizeRow.tools ? tsizeRow.tools.find(t => t.id === "ui:auto") : null
    readonly property var islands: (studio.row("bar") || { items: [] }).items
    readonly property string wall: studio.targetThumb ? "file://" + studio.targetThumb : ""

    StudioCap { studio: dc.studio; text: "Top bar size"; note: "the band at the top of every screen" }
    Item { width: 1; height: dc.d(14) }
    StudioSlider {
        visible: !!dc.topSize
        studio: dc.studio
        fkey: "sl:top"
        value: dc.topSize ? dc.topSize.v : 1
        min: dc.topSize ? dc.topSize.min : 0.8; max: dc.topSize ? dc.topSize.max : 1.8; step: dc.topSize ? dc.topSize.step : 0.05
        def: dc.topSize ? dc.topSize.def : 1.05
        defLabel: "Default"
        desc: "<b>Top bar size</b> Its strip and the window shelf it opens. Left and right to change it."
        onCommit: v => dc.studio.slide(dc.topSize, v)
    }
    Item { width: 1; height: dc.d(40) }
    StudioCap { studio: dc.studio; text: "Taskbar size"; note: "its popups and the desk's clocks follow it" }
    Item { width: 1; height: dc.d(14) }
    Row {
        spacing: dc.d(18)
        StudioSlider {
            visible: !!dc.tsize
            studio: dc.studio
            fkey: "sl:tsize"
            value: dc.tsize ? dc.tsize.v : 1
            min: dc.tsize ? dc.tsize.min : 0.8; max: dc.tsize ? dc.tsize.max : 1.8; step: dc.tsize ? dc.tsize.step : 0.05
            def: dc.tsize ? dc.tsize.def : 1
            defLabel: dc.tsize ? dc.tsize.defLabel : "Standard"
            desc: "<b>Taskbar size</b> " + (dc.tsize ? dc.tsize.desc : "") + " Left and right to change it."
            onCommit: v => dc.studio.slide(dc.tsize, v)
        }
        StudioToggle {
            visible: !!dc.auto
            anchors.verticalCenter: parent.verticalCenter
            studio: dc.studio
            fkey: "tg:uiauto"
            text: "Automatic"
            chosen: !!(dc.auto && dc.auto.on)
            desc: "<b>Automatic</b> " + (chosen ? "On: each screen at its standard size × this." : "Off: this size on every screen.")
            onActivated: dc.studio.model.tool("ui:auto")
        }
    }
    Item { width: 1; height: dc.d(40) }
    StudioCap { studio: dc.studio; text: "Island style"; note: "every bar" }
    Item { width: 1; height: dc.d(14) }
    Row {
        spacing: dc.d(18)
        Repeater {
            model: dc.islands
            StudioCard {
                id: ic
                required property var modelData
                readonly property string st: modelData.style
                studio: dc.studio
                picW: dc.d(300); picH: dc.d(169)
                fkey: "isl:" + st
                name: modelData.name
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + modelData.desc
                act: "Use this style"
                onActivated: dc.studio.model.apply(modelData)
                RoundPic {
                    studio: dc.studio
                    anchors.fill: parent
                    Image {     // the bottom of the wallpaper, close up (where the bar sits)
                        width: parent.width * 1.6; height: parent.height * 1.6
                        x: (parent.width - width) / 2; y: parent.height - height
                        fillMode: Image.PreserveAspectCrop
                        source: dc.wall
                        sourceSize.width: 480
                    }
                    Item {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.margins: dc.d(12)
                        height: dc.d(40)
                        Repeater {
                            model: [[0, 40], [0.5, 140], [1, 70]]
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: dc.d(modelData[1]); height: parent.height; radius: height / 2
                                x: (parent.width - width) * modelData[0]
                                color: ic.st === "solid" ? dc.lk.surfaceHigh : ic.st === "matte" ? C.alpha(dc.lk.surfaceHigh, 0.78)
                                     : ic.st === "clear" ? Qt.rgba(1, 1, 1, 0.16) : C.alpha(dc.lk.surfaceLowest, 0.4)
                                border.width: ic.st === "clear" ? dc.d(1) : 0
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                Rectangle {     // the solid islands' sheen
                                    visible: ic.st === "solid" || ic.st === "clear"
                                    x: parent.radius; width: parent.width - 2 * parent.radius; height: dc.d(1); color: Qt.rgba(1, 1, 1, ic.st === "solid" ? 0.3 : 0.5)
                                }
                                Image { visible: ic.st === "matte"; anchors.fill: parent; anchors.margins: dc.d(3); source: Prefs.grain; fillMode: Image.Tile; opacity: 0.22 }
                                Rectangle { visible: index === 0; anchors.centerIn: parent; width: dc.d(18); height: width; radius: width / 2; color: dc.lk.primary }
                            }
                        }
                    }
                }
            }
        }
    }
}
