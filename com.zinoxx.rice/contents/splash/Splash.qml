import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import "Rice"
import "palette.js" as P

// Plasma rice splash, one per screen. It starts as the boot screen ended (Plymouth "rice", built by
// ~/.config/plasma-rice/boot.py): the same neutral surface, Clawd, the comet ring and a label, at the
// same offsets (boot.py LAYOUT). Then this screen's own wallpaper fades in under it as the session
// loads, and the ring's track fills with progress, so the desktop arrives instead of popping in.
Rectangle {
    id: root
    color: "#0c0d12"                            // boot.py BOOT.base

    property int stage
    property string output: Screen.name         // which screen's wallpaper (a render can set it)
    readonly property real progress: Math.min(1, Math.max(0, stage) / 6)
    // boot.py's unit (device height / 1080) in logical px, so Clawd and the ring keep their device size
    readonly property real unit: height / 1080

    onStageChanged: if (stage == 5) outro.start()

    RicePalette { id: pal; output: root.output }
    Account { id: me }

    Image {                                     // the boot surface, exactly as Plymouth drew it
        anchors.fill: parent
        source: "images/backdrop.png"
        fillMode: Image.Stretch
        smooth: true
    }

    Item {                                      // this screen's wallpaper, blurred, fading in with progress
        anchors.fill: parent
        opacity: wall.status === Image.Ready ? 0.15 + 0.85 * root.progress : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.slow * 2; easing.type: Tokens.move } }
        Image {
            id: wall
            anchors.fill: parent
            source: pal.wallpaper ? "file://" + pal.wallpaper : (P.wallpaper ? "file://" + P.wallpaper : "")
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1280                // it's blurred anyway: decode small, start fast
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: wall
            blurEnabled: true; blur: 1.0; blurMax: 64
            saturation: 0.15
        }
        Rectangle { anchors.fill: parent; color: Qt.alpha("#0c0d12", 0.55) }   // keeps the content legible
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        transform: Translate { id: rise; y: 8 * root.unit }
        Component.onCompleted: intro.start()

        Clawd {
            id: clawd
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + (-70 * root.unit) - height / 2
            px: 9 * root.unit
            interactive: false
            mood: "happy"
            daypart: "day"
            Timer { interval: 1600; running: content.opacity > 0; repeat: true; onTriggered: clawd.hop() }
        }

        Item {                                  // comet ring: the boot spinner, plus a track that fills
            id: ring
            width: 40 * root.unit; height: width
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 36 * root.unit - height / 2
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.alpha("#e6e8f0", 0.32)
                    strokeWidth: 3 * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - 3 * root.unit; radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 360 * fill.value
                    }
                }
            }
            QtObject {
                id: fill
                property real value: root.progress
                Behavior on value { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.enter } }
            }
            Image {
                anchors.fill: parent
                source: "images/comet.png"
                smooth: true
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 1600; loops: Animation.Infinite
                    running: content.opacity > 0
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 76 * root.unit
            text: "Welcome back, " + me.displayName
            color: "#e6e8f0"
            opacity: 0.9
            font.family: Tokens.font.display
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(Tokens.size.heading * root.unit)
        }
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
        NumberAnimation { target: rise; property: "y"; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
    }
    ParallelAnimation {
        id: outro
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: Tokens.base; easing.type: Tokens.exit }
        NumberAnimation { target: rise; property: "y"; to: -6 * root.unit; duration: Tokens.base; easing.type: Tokens.exit }
    }
}
