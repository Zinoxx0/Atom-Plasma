import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import "Rice"
import "palette.js" as P

// Atom Plasma splash, one per screen. It starts as the boot screen ended (Plymouth "rice", built by
// ~/.config/plasma-rice/bin/boot.py): the same neutral surface, the white Orbit mark, the comet ring and a
// label, at the same offsets (the design tokens' bootLayout, which boot.py reads too). Then this screen's own wallpaper fades in under it as the
// session loads, and the ring's track fills with progress, so the desktop arrives instead of popping in;
// as it does, the mark opens into its halo, as the launcher does.
Rectangle {
    id: root
    color: Tokens.boot.base                     // the boot surface (design tokens, as boot.py draws it)
    readonly property var lay: Tokens.bootLayout    // Plymouth's layout at 1080p (boot.py draws the same)

    property int stage
    property string output: Screen.name         // which screen's wallpaper (a render can set it)
    readonly property real progress: Math.min(1, Math.max(0, stage) / 6)
    // boot.py's unit (device height / 1080) in logical px, so Clawd and the ring keep their device size
    readonly property real unit: height / 1080

    onStageChanged: if (stage == 5) { mark.open = true; outro.start() }

    RicePalette { id: pal; output: root.output }
    Account { id: me }

    Image {                                     // the boot surface, exactly as Plymouth drew it
        anchors.fill: parent
        source: "images/backdrop.png"
        fillMode: Image.Stretch
        smooth: true
    }

    Item {                                      // this screen's pre-blurred wallpaper (_glassFull), fading in with progress
        anchors.fill: parent
        readonly property string frost: pal.values && pal.values._glassFull ? "file://" + pal.values._glassFull : ""
        opacity: (frost ? frostImg.status : wall.status) === Image.Ready ? 0.25 + 0.75 * root.progress : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.slow * 2; easing.type: Tokens.move } }
        Image {                                 // fast path: already blurred & sized by atom/screens.py (~20 KB JPEG)
            id: frostImg
            anchors.fill: parent
            visible: parent.frost !== ""
            source: parent.frost
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Image {                                 // fallback only when _glassFull doesn't exist yet
            id: wall
            anchors.fill: parent
            source: parent.frost === "" ? (pal.wallpaper ? "file://" + pal.wallpaper : (P.wallpaper ? "file://" + P.wallpaper : "")) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 640
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            visible: parent.frost === "" && wall.status === Image.Ready
            source: parent.frost === "" ? wall : null
            blurEnabled: true; blur: 1.0; blurMax: 64
            saturation: 0.15
        }
        Rectangle { anchors.fill: parent; color: Qt.alpha(Tokens.boot.base, 0.55) }   // keeps the content legible
    }

    Item {
        id: content
        anchors.fill: parent
        // Visible on frame 1 (no dark-screen fade-in delay from Plymouth's handoff)
        opacity: 1
        transform: Translate { id: rise; y: 0 }

        // the launcher's Orbit mark, all white (boot.py renders the same one for Plymouth): its
        // satellites swing round now and then while the session loads
        Emblem {
            id: mark
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + (root.lay.mark_y * root.unit) - height / 2
            scale: root.lay.mark_scale * root.unit
            c1: "#ffffff"; c2: "#ffffff"; c3: "#ffffff"; c4: "#ffffff"; glow: "#ffffff"
            Timer {
                interval: 1300; running: content.opacity > 0 && !mark.open; repeat: true
                onTriggered: mark.hovered = !mark.hovered
            }
        }

        Item {                                  // comet ring: the boot spinner, plus a track that fills
            id: ring
            width: root.lay.ring * root.unit; height: width
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + root.lay.ring_y * root.unit - height / 2
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.alpha("#e6e8f0", 0.32)
                    strokeWidth: root.lay.ring_w * root.unit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: ring.width / 2 - root.lay.ring_w * root.unit; radiusY: radiusX
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
            id: welcome
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + root.lay.label_y * root.unit
            text: "Welcome back, " + me.displayName
            color: "#e6e8f0"
            opacity: 0
            font.family: Tokens.font.display
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(Tokens.size.heading * root.unit)
            Component.onCompleted: welcomeFade.start()
        }
        NumberAnimation { id: welcomeFade; target: welcome; property: "opacity"; from: 0; to: 0.9; duration: Tokens.base; easing.type: Tokens.enter }
    }

    ParallelAnimation {
        id: outro
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: Tokens.base; easing.type: Tokens.exit }
        NumberAnimation { target: rise; property: "y"; to: -6 * root.unit; duration: Tokens.base; easing.type: Tokens.exit }
    }
}
