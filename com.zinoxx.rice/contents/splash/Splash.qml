import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "palette.js" as P

// Plasma rice splash: Clawd bouncing over the blurred current wallpaper, with a
// gradient progress pill. palette.js is rewritten by ~/.config/plasma-rice/rice.py.
Rectangle {
    id: root
    color: P.colors.surface_lowest

    property int stage
    readonly property real progress: Math.min(1, Math.max(0, stage) / 6)

    onStageChanged: if (stage == 5) outro.running = true

    Image {
        id: wall
        anchors.fill: parent
        source: P.wallpaper ? "file://" + P.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.25
        opacity: wall.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
    Rectangle { anchors.fill: parent; color: Qt.alpha(P.colors.background, 0.62) }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 34
        opacity: 0
        scale: 0.9
        Component.onCompleted: intro.start()

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: clawd.implicitWidth
            height: clawd.implicitHeight + 24
            Clawd {
                id: clawd
                anchors.bottom: parent.bottom
                px: 9
                interactive: false
                mood: "happy"
            }
            Timer { interval: 1600; running: true; repeat: true; onTriggered: clawd.hop() }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Welcome back"
                color: P.colors.on_surface
                font.family: "Inter Display"; font.weight: Font.ExtraBold; font.pixelSize: 34
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Thorfinn"
                color: P.colors.primary
                font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 15
                font.letterSpacing: 3
                font.capitalization: Font.AllUppercase
            }
        }

        Rectangle {   // progress pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260; height: 8; radius: 4
            color: Qt.alpha(P.colors.on_surface, 0.12)
            Rectangle {
                height: parent.height; radius: 4
                width: Math.max(height, parent.width * root.progress)
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: P.colors.primary }
                    GradientStop { position: 1; color: P.colors.tertiary }
                }
            }
        }
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "scale"; to: 1; duration: 700; easing.type: Easing.OutBack }
    }
    NumberAnimation { id: outro; target: content; property: "opacity"; to: 0; duration: 400 }
}
