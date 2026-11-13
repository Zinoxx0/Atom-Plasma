import QtQuick
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// A button of Atom Home's top bar: a round glyph, lit under the pointer (in `hotColor` when it has one).
Rectangle {
    id: tb
    required property RicePalette rice
    property real unit: 1
    property string icon: ""
    property string tip: ""
    property color hotColor: rice.fg
    signal clicked()
    readonly property bool hot: ma.containsMouse
    width: height
    height: Math.round(42 * unit)
    radius: height / 2
    color: C.alpha(rice.fg, hot ? 0.1 : 0)
    Behavior on color { ColorAnimation { duration: Tokens.fast } }
    Text {
        anchors.centerIn: parent
        text: tb.icon
        color: tb.hot ? tb.hotColor : tb.rice.fgDim
        font.family: Tokens.font.icons
        font.pixelSize: Math.round(23 * tb.unit)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }
    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: tb.tip
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }
}
