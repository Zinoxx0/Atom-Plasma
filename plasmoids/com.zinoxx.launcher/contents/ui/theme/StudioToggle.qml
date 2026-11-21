import QtQuick
import Atom
import Rice

// A switch on the Theme page (the taskbar's Automatic size, a keyboard on or off): a pill with its knob.
Focusable {
    id: tg
    property string text: ""
    property bool chosen: false
    readonly property var lk: studio.look
    width: row.width + studio.d(30)
    height: studio.d(46)
    lensRadius: height / 2
    act: chosen ? "Turn off" : "Turn on"
    Rectangle { anchors.fill: parent; radius: height / 2; color: C.alpha(tg.lk.surfaceHigh, tg.hovered ? 0.75 : 0.52) }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: tg.studio.d(12)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: tg.studio.d(42); height: tg.studio.d(26); radius: height / 2
            color: tg.chosen ? tg.lk.primary : C.alpha(tg.lk.fg, 0.24)
            Behavior on color { ColorAnimation { duration: Tokens.ms(250) } }
            Rectangle {
                width: tg.studio.d(18); height: width; radius: width / 2
                y: tg.studio.d(4)
                x: tg.chosen ? parent.width - width - tg.studio.d(4) : tg.studio.d(4)
                color: tg.chosen ? tg.lk.surfaceLowest : tg.lk.fg
                Behavior on x { NumberAnimation { duration: Tokens.ms(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tg.text
            color: tg.lk.fg
            font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: tg.studio.d(16)
        }
    }
}
