import QtQuick
import QtQuick.Effects
import Rice

// A size on the Theme page, as a big slider (HomeTile holds its value and reads the pointer against
// trackL/trackR; this only draws it): the value large on the left, then the track from min to max with a notch
// at every step (0.05), filled in the accents up to the knob, the ends and the standard size named under it.
//   item     the ThemeModel item: { v, min, max, step, def }
//   value    where it is now (while it's dragged or stepped: not yet applied)
Item {
    id: sl
    required property var item
    required property RicePalette rice
    property real unit: 1
    property real radius: 20
    property real value: 1
    property real trackL: 150
    property real trackR: 600
    property bool focused: false
    property bool hovered: false
    property bool dragging: false
    function u(n) { return Math.round(n * unit) }

    readonly property real lo: item ? item.min : 0.8
    readonly property real hi: item ? item.max : 1.8
    function xOf(v) { return trackL + (trackR - trackL) * Math.max(0, Math.min(1, (v - lo) / Math.max(0.001, hi - lo))) }
    readonly property int steps: item ? Math.round((hi - lo) / item.step) : 20
    readonly property real trackY: Math.round(height * 0.42)
    readonly property bool moved: !!item && Math.abs(value - item.v) > 0.001       // (not applied yet)

    Rectangle {     // the plate (the group headers' glass)
        anchors.fill: parent
        radius: sl.radius
        color: C.alpha(sl.rice.fg, 0.05 + (sl.focused ? 0.05 : 0) + (sl.hovered ? 0.03 : 0))
        border.width: 1
        border.color: C.alpha(sl.rice.edge, sl.focused ? 0.2 : 0.12)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }

    Text {          // the value, large
        x: sl.u(26)
        width: sl.trackL - x - sl.u(22)
        anchors.verticalCenter: parent.verticalCenter
        text: Number(sl.value).toFixed(2) + "×"
        color: sl.moved ? sl.rice.primary : sl.rice.fg
        font.family: Tokens.font.display
        font.weight: Font.DemiBold
        font.pixelSize: sl.u(32)
        font.features: { "tnum": 1 }
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: sl.u(18)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
    }

    Item {
        id: track
        x: sl.trackL
        y: sl.trackY - height / 2
        width: sl.trackR - sl.trackL
        height: sl.u(8)
        Rectangle {     // the rail
            anchors.fill: parent
            radius: height / 2
            color: C.alpha(sl.rice.fg, 0.12)
        }
        Repeater {      // a notch at every step (the fill covers the ones behind the knob)
            model: sl.steps + 1
            Rectangle {
                required property int index
                readonly property real v: sl.lo + index * (sl.item ? sl.item.step : 0.05)
                readonly property bool major: sl.item && Math.abs(v - sl.item.def) < 0.001
                width: major ? sl.u(4) : sl.u(2)
                height: major ? sl.u(16) : sl.u(10)
                radius: width / 2
                x: sl.xOf(v) - sl.trackL - width / 2
                y: (track.height - height) / 2
                color: C.alpha(sl.rice.fg, major ? 0.55 : 0.26)
            }
        }
        Rectangle {     // the fill, in the accents, up to the knob
            width: Math.max(height, knob.x + knob.width / 2)
            height: parent.height
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: sl.rice.primary }
                GradientStop { position: 1; color: sl.rice.tertiary }
            }
        }
        Rectangle {     // the knob
            id: knob
            property real d: sl.u(sl.dragging ? 32 : 28)
            width: d; height: d; radius: d / 2
            x: sl.xOf(sl.value) - sl.trackL - width / 2
            y: (track.height - height) / 2
            color: sl.rice.light ? sl.rice.surfaceLowest : "#ffffff"
            border.width: Math.max(2, sl.u(3))
            border.color: sl.rice.primary
            Behavior on x { enabled: !sl.dragging; NumberAnimation { duration: Tokens.ms(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
            Behavior on d { NumberAnimation { duration: Tokens.fast } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.5); shadowBlur: 0.6; shadowVerticalOffset: sl.u(2) }
        }
    }

    // under the track: its ends and its default (the standard size)
    Text {
        x: sl.trackL
        y: sl.trackY + sl.u(17)
        text: Number(sl.lo).toFixed(2) + "×"
        color: sl.rice.muted
        font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: sl.u(12.5); font.features: { "tnum": 1 }
    }
    Text {
        x: sl.trackR - implicitWidth
        y: sl.trackY + sl.u(17)
        text: Number(sl.hi).toFixed(2) + "×"
        color: sl.rice.muted
        font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: sl.u(12.5); font.features: { "tnum": 1 }
    }
    Text {
        x: (sl.item ? sl.xOf(sl.item.def) : 0) - implicitWidth / 2
        y: sl.trackY + sl.u(17)
        text: sl.item ? sl.item.defLabel || "Standard" : ""
        color: sl.rice.fgDim
        font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: sl.u(12.5)
    }
}
