import QtQuick
import Atom
import Rice

// A pill on the Theme page: a filter, a tool, a choice. Glass when it's not chosen, solid ink when it is (the
// launcher's language for "this one"); an icon, a colour dot (a lighting effect: dots), a count, a pad glyph.
Focusable {
    id: chip
    property string text: ""
    property string icon: ""
    property var dots: []               // colours for its dot (one: plain; several: in turn)
    property string count: ""
    property string pad: ""             // a pad button that does it too (Y: Shuffle)
    property bool chosen: false
    readonly property var lk: studio.look
    width: row.width + studio.d(38)
    height: studio.d(46)
    lensRadius: height / 2
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: chip.chosen ? chip.lk.fg : chip.hovered ? C.alpha(chip.lk.surfaceHigh, 0.75) : C.alpha(chip.lk.surfaceHigh, 0.52)
        Behavior on color { ColorAnimation { duration: Tokens.ms(220) } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: chip.studio.d(10)
        Text {
            visible: chip.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            color: chip.chosen ? chip.lk.surfaceLowest : chip.lk.fg
            font.family: Tokens.font.icons; font.pixelSize: chip.studio.d(21)
        }
        Row {
            visible: chip.dots.length > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: -chip.studio.d(6)
            Repeater {
                model: chip.dots.length
                Rectangle {
                    required property int index
                    width: chip.studio.d(16); height: width; radius: width / 2
                    color: chip.dots[index] || "transparent"
                    border.width: 1; border.color: C.alpha(chip.chosen ? chip.lk.surfaceLowest : chip.lk.fg, 0.3)
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: chip.chosen ? chip.lk.surfaceLowest : chip.lk.fg
            font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: chip.studio.d(16)
        }
        Text {
            visible: chip.count !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.count
            color: chip.chosen ? C.alpha(chip.lk.surfaceLowest, 0.6) : chip.lk.fgDim
            font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: chip.studio.d(14)
        }
        Rectangle {
            visible: chip.pad !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: chip.studio.d(26); height: width; radius: width / 2
            color: "transparent"
            border.width: chip.studio.d(1.5); border.color: C.alpha(chip.chosen ? chip.lk.surfaceLowest : chip.lk.fg, 0.4)
            Text { anchors.centerIn: parent; text: chip.pad; color: chip.chosen ? chip.lk.surfaceLowest : chip.lk.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: chip.studio.d(12) }
        }
    }
}
