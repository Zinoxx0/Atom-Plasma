import QtQuick
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// A button of Atom Home's top bar: a round glyph with a big enough target, lit under the pointer (in
// `hotColor` when it has one), ringed while the keys are on it, filled while what it opens is open (`lit`).
Rectangle {
    id: tb
    required property RicePalette rice
    property real unit: 1
    property string icon: ""
    property string tip: ""
    property color hotColor: rice.fg
    property bool focused: false            // the keys are on it (the top bar's line)
    property bool lit: false                // what it opens is open
    signal clicked()
    readonly property bool hot: ma.containsMouse
    width: height
    height: Math.round(52 * unit)
    radius: height / 2
    // a dark glass of its own (as the pages' track), lit from it: it reads over any picture
    color: C.mix(C.alpha(rice.surfaceLowest, 0.55), rice.fg, lit ? 0.2 : hot || focused ? 0.14 : 0.04)
    border.width: 1
    border.color: C.alpha(rice.edge, hot || lit ? 0.18 : 0.08)
    scale: ma.pressed ? 0.94 : 1
    Behavior on scale { NumberAnimation { duration: Tokens.fast } }
    Behavior on color { ColorAnimation { duration: Tokens.fast } }
    Text {
        anchors.centerIn: parent
        text: tb.icon
        color: tb.hot ? tb.hotColor : tb.focused || tb.lit ? tb.rice.fg : C.mix(tb.rice.fg, tb.rice.fgDim, 0.4)
        font.family: Tokens.font.icons
        font.pixelSize: Math.round(26 * tb.unit)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }
    Rectangle {     // the keys' ring: the launcher's language (white, outside, with a gap)
        anchors.fill: parent
        anchors.margins: -Math.max(4, Math.round(4 * tb.unit))
        radius: height / 2
        color: "transparent"
        border.width: Math.max(2, Math.round(2.5 * tb.unit))
        border.color: tb.rice.light ? tb.rice.fg : "#ffffff"
        opacity: tb.focused ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
    }
    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: tb.tip
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }
}
