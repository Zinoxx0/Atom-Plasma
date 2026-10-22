import QtQuick
import org.kde.kirigami as Kirigami
import "Color.js" as C

// Wraps a popup's content and brings it in when the popup opens: a fade and a 6 px rise,
// no overshoot. Given the screen's palette, a faint aurora of its colours glows behind the top
// (Aurora). Anchor it like the content it holds.
//
//   PopupIn { anchors.fill: parent; active: root.expanded; ricePalette: pal; ColumnLayout { ... } }
//
// The popup's frame comes from the Plasma Style, which follows the theme-driving screen (dark glass,
// or white frost when that wallpaper is light). On a screen of the other kind PopupIn paints this
// screen's own surface over it, out to the frame's hairline, so text in the screen's colours reads.
Item {
    id: pin
    property bool active: false             // bind to the applet's `expanded`
    property real rise: 6
    property RicePalette ricePalette: null
    default property alias content: body.data
    // the dialog frame's margin around the content and its corner radius (plasma-style/build.py)
    property real frameMargin: Tokens.space.sm
    property real frameRadius: Tokens.radius.lg
    readonly property bool chromeLight: Kirigami.Theme.backgroundColor.hslLightness > 0.5
    readonly property bool repaint: ricePalette !== null && ricePalette.loaded && ricePalette.light !== chromeLight

    Rectangle {
        visible: pin.repaint
        anchors.fill: parent
        anchors.margins: -(pin.frameMargin - 1)
        radius: pin.frameRadius - 1
        color: pin.ricePalette ? C.alpha(pin.ricePalette.light ? pin.ricePalette.surfaceLowest : Tokens.neutral.dark, 0.985) : "transparent"
        border.width: 1
        border.color: pin.ricePalette ? C.alpha(pin.ricePalette.edge, Tokens.alpha.outline) : "transparent"
    }

    Aurora {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Math.min(parent.height, 220)
        visible: pin.ricePalette !== null
        ricePalette: pin.ricePalette
        opacity: body.opacity
        drift: pin.drift
    }
    property real drift: 1
    Item {
        id: body
        anchors.fill: parent
        transform: Translate { id: lift }
    }
    function play() {
        if (Tokens.speed <= 0) { body.opacity = 1; lift.y = 0; drift = 1; return }
        anim.restart();
    }
    ParallelAnimation {
        id: anim
        NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
        NumberAnimation { target: lift; property: "y"; from: pin.rise; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
        NumberAnimation { target: pin; property: "drift"; from: 0; to: 1; duration: Tokens.ms(900); easing.type: Easing.OutCubic }
    }
    onActiveChanged: if (active) play()
    Component.onCompleted: if (active) play()
}
