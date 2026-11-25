import QtQuick
import Rice

// Minimalistic crystalline horizon bar meter (used stacked on the taskbar and wider in the popup).
// No rings, no slider thumb: smooth luminous Gemini spectrum bar + vertical even-pace tick.
Item {
    id: meter
    property real value: 0                  // 0..100
    property real pace: -1                  // 0..100, or < 0 to hide
    property bool hot: false
    property bool shimmer: false
    property bool animate: true
    property string starStyle: "iridescent"
    property color trackColor: Qt.rgba(1, 1, 1, 0.13)
    property color paceColor: Qt.rgba(1, 1, 1, 0.65)
    property color warnColor: "#ff9e64"
    property color hotColor: "#f7768e"
    property real paceExtra: 1.5

    readonly property real clamped: Math.max(0, Math.min(100, isFinite(value) ? value : 0))
    readonly property real fillW: clamped <= 0 ? 0 : Math.max(height, Math.round(width * clamped / 100))

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: meter.trackColor
    }

    Item {
        id: fillClip
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: meter.fillW
        clip: true
        Behavior on width { enabled: meter.animate; NumberAnimation { duration: Tokens.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: meter.hot ? meter.warnColor : "#4285f4" }
                GradientStop { position: 0.52; color: meter.hot ? meter.hotColor : (meter.starStyle === "google4" ? "#34a853" : "#7c6cf6") }
                GradientStop { position: 1.0; color: meter.hot ? meter.hotColor : (meter.starStyle === "google4" ? "#fbbc04" : "#d96570") }
            }
        }

        // Soft luminous leading edge (not a circle/knob)
        Rectangle {
            visible: fillClip.width > meter.height
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(fillClip.width, Math.max(4, meter.height * 1.4))
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.65) }
            }
        }

        // Subtle traveling light shimmer while Gemini is active
        Rectangle {
            id: wave
            visible: meter.shimmer && meter.animate && fillClip.width > 4
            width: Math.max(12, meter.width * 0.45)
            height: parent.height
            y: 0
            x: -width
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.48) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            NumberAnimation on x {
                running: wave.visible
                from: -wave.width
                to: meter.width + wave.width
                duration: 2100
                loops: Animation.Infinite
            }
        }
    }

    // Even-pace vertical notch
    Rectangle {
        visible: meter.pace >= 0 && meter.pace <= 100
        x: Math.round((meter.width - width) * Math.max(0, Math.min(100, meter.pace)) / 100)
        y: -meter.paceExtra
        width: Math.max(1.5, Math.round(meter.height * 0.28))
        height: meter.height + 2 * meter.paceExtra
        radius: width / 2
        color: meter.paceColor
    }
}
