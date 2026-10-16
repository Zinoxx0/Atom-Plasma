import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// Now playing, under the clock on one screen, only while something plays: the album art blurred
// into the glass, the art itself, title and artist, a thin progress line, and previous / play /
// next on hover. Its colours are the screen's palette (a glass card, like the bar's islands).
DeskWindow {
    id: mw
    box: d.lay ? d.lay.media : null
    shown: d.desk.media === true && !!d.player && d.player.present

    readonly property var m: d.player
    readonly property real bh: height
    readonly property string art: m ? m.artUrl : ""
    readonly property real radius: Math.min(Tokens.radius.lg, bh / 2)

    HoverHandler { id: hover }

    // flush with the clock's text above it (the clock keeps that much padding inside its window)
    readonly property bool flushRight: d.lay ? d.lay.align === "right" : true
    readonly property real inset: d.lay ? Math.round(Math.max(d.lay.clock.h * 0.07, 30)) : 0     // = ClockWindow.pad
    Item {
        id: card
        anchors.fill: parent
        anchors.leftMargin: mw.flushRight ? 0 : mw.inset
        anchors.rightMargin: mw.flushRight ? mw.inset : 0

        // the glass: the art, blurred, under the palette's surface, clipped to the card
        Item {
            id: glass
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: shape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Rectangle { anchors.fill: parent; color: mw.d.pal.surfaceLowest }
            Image {
                anchors.fill: parent
                source: mw.art
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 192
                asynchronous: true
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: 0.25 }
            }
            Rectangle { anchors.fill: parent; color: C.alpha(mw.d.pal.surfaceLowest, mw.d.pal.light ? 0.5 : 0.6) }
            Rectangle {     // a breath of light along the top, like the islands
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: parent.height * 0.5
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, mw.d.pal.light ? 0.25 : 0.06) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Rectangle {
            id: shape
            anchors.fill: parent
            radius: mw.radius
            visible: false
            layer.enabled: true
        }
        Rectangle {
            anchors.fill: parent
            radius: mw.radius
            color: "transparent"
            border.width: 1
            border.color: C.alpha(mw.d.pal.edge, 0.14)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Math.round(mw.bh * 0.14)
            spacing: Math.round(mw.bh * 0.16)

            Kirigami.ShadowedImage {
                id: cover
                Layout.fillHeight: true
                Layout.preferredWidth: height
                radius: Tokens.radius.sm
                color: C.alpha(mw.d.pal.fg, 0.08)
                source: mw.art
                sourceSize.width: 160
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                Text {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    text: "music_note"
                    color: mw.d.pal.fgDim
                    font.family: Tokens.font.icons
                    font.pixelSize: Math.round(cover.height * 0.5)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Math.round(mw.bh * 0.04)
                Text {
                    Layout.fillWidth: true
                    text: mw.m ? mw.m.track : ""
                    elide: Text.ElideRight
                    color: mw.d.pal.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.Bold
                    font.pixelSize: Math.max(11, Math.round(mw.bh * 0.17))
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: mw.m ? mw.m.artist : ""
                    elide: Text.ElideRight
                    color: mw.d.pal.fgDim
                    font.family: Tokens.font.ui
                    font.pixelSize: Math.max(10, Math.round(mw.bh * 0.135))
                }
                Item {          // progress
                    Layout.fillWidth: true
                    Layout.topMargin: Math.round(mw.bh * 0.04)
                    implicitHeight: 3
                    visible: mw.m && mw.m.length > 0
                    Rectangle { anchors.fill: parent; radius: 1.5; color: C.alpha(mw.d.pal.fg, 0.14) }
                    Rectangle {
                        height: parent.height
                        radius: 1.5
                        width: mw.m ? parent.width * Math.max(0, Math.min(1, mw.m.position / Math.max(1, mw.m.length))) : 0
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: mw.d.pal.primary }
                            GradientStop { position: 1; color: mw.d.pal.tertiary }
                        }
                    }
                }
            }
            Row {           // controls, on hover
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                opacity: hover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                IconButton { palette: mw.d.pal; size: Math.round(mw.bh * 0.36); icon: "skip_previous"; enabled: mw.m && mw.m.canPrev; onClicked: mw.m.prev() }
                IconButton {
                    palette: mw.d.pal
                    size: Math.round(mw.bh * 0.42)
                    icon: mw.m && mw.m.playing ? "pause" : "play_arrow"
                    filled: true
                    enabled: mw.m && mw.m.canToggle
                    onClicked: mw.m.toggle()
                }
                IconButton { palette: mw.d.pal; size: Math.round(mw.bh * 0.36); icon: "skip_next"; enabled: mw.m && mw.m.canNext; onClicked: mw.m.next() }
            }
        }
    }
}
