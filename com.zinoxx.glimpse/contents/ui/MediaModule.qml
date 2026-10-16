import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris
import "Rice"
import "Rice/Color.js" as C

// Now playing, floating on the right of the opened band: art, title and artist, previous /
// play-pause / next and a thin progress line. Not there while nothing plays (no player, or stopped).
// The progress only ticks, and the little level meter on the art only moves, while the band is open.
Item {
    id: media
    property var g                          // the Glimpse root
    property bool open: false               // the band is open
    property real pop: 0                    // the band's icons fade in; this follows along

    Mpris.Mpris2Model { id: mpris }
    readonly property var player: mpris.currentPlayer
    readonly property int status: player ? player.playbackStatus : Mpris.PlaybackStatus.Unknown
    readonly property bool playing: status === Mpris.PlaybackStatus.Playing
    readonly property string track: player ? player.track : ""
    readonly property string artist: player ? player.artist : ""
    readonly property string artUrl: player ? player.artUrl : ""
    readonly property string appIcon: player ? (player.iconName || player.desktopEntry || "") : ""
    readonly property real length: player ? player.length : 0          // µs
    readonly property bool present: !!player && status > Mpris.PlaybackStatus.Stopped && track !== ""

    // position: MPRIS only reports it on seeks, so count the seconds ourselves while open
    property real position: 0
    function syncPosition() {
        if (!player) return
        player.updatePosition()
        position = player.position
    }
    Connections {
        target: media.player
        function onPositionChanged() { media.position = media.player.position }
    }
    onOpenChanged: if (open) syncPosition()
    onPlayerChanged: syncPosition()
    onTrackChanged: syncPosition()
    Timer {
        interval: 1000
        repeat: true
        running: media.open && media.playing && media.length > 0
        onTriggered: media.position = Math.min(media.length, media.position + 1e6 * (media.player ? media.player.rate || 1 : 1))
    }

    function esc(t) { return String(t ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    readonly property int h: g.barH - 8
    readonly property int pad: 4
    implicitWidth: row.implicitWidth + 2 * pad + g.px(4)
    height: h
    property real presence: present ? 1 : 0
    Behavior on presence { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
    opacity: presence * pop
    visible: opacity > 0

    // the album art lights the glass under the module, like the apps do under their icons
    Kirigami.ImageColors { id: artColors; source: media.artUrl }
    Item {
        x: -g.px(24)
        y: -media.y
        width: media.width + 2 * g.px(24)
        height: g.barH
        clip: true
        AppGlow {
            anchors.horizontalCenter: parent.horizontalCenter
            y: g.barH - 6 - height / 2
            width: parent.width
            flat: Math.min(0.62, 70 / Math.max(1, width))
            tint: C.appTint(artColors, g.cPrimary)
            strength: media.playing ? 0.32 : 0.16
            Behavior on strength { NumberAnimation { duration: Tokens.base } }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.round(Tokens.radius.sm * g.topScale)
        color: C.alpha(g.pal.edge, 0.05)
        border.width: 1
        border.color: C.alpha(g.pal.edge, Tokens.alpha.outline)
    }

    Row {
        id: row
        x: media.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: g.px(8)

        // album art (or the player's icon), with a tiny level meter while playing
        Item {
            id: art
            width: media.h - 2 * media.pad
            height: width
            anchors.verticalCenter: parent.verticalCenter
            Kirigami.ShadowedImage {
                id: cover
                anchors.fill: parent
                source: media.artUrl
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                radius: Math.max(4, Math.round(Tokens.radius.sm * g.topScale) - media.pad)
                sourceSize: Qt.size(width * 2, height * 2)
            }
            Rectangle {
                anchors.fill: parent
                visible: !cover.visible
                radius: cover.radius
                color: C.alpha(g.pal.edge, 0.06)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.7)
                    height: width
                    source: media.appIcon || "media-default-album"
                    animated: false
                }
            }
            Row {           // a little meter: just MPRIS state, stepped, only while open and playing
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 3
                spacing: 1
                visible: media.playing && media.open
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        property real level: 0.5
                        anchors.bottom: parent.bottom
                        width: 2
                        height: Math.max(2, Math.round(level * art.height * 0.36))
                        radius: 1
                        color: "white"
                        opacity: 0.9
                        Behavior on height { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                        Timer {
                            interval: 150 + parent.index * 37
                            repeat: true
                            running: media.playing && media.open
                            onTriggered: parent.level = 0.25 + Math.random() * 0.75
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (media.player && media.player.canRaise) media.player.Raise()
            }
        }

        // title · artist on one line, the progress under it
        Item {
            id: info
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(g.px(190), titleText.implicitWidth)
            height: titleText.height + g.px(5) + 2
            Text {
                id: titleText
                width: parent.width
                text: "<b>" + media.esc(media.track) + "</b>"
                      + (media.artist ? "<font color='" + g.cFgDim + "'>  ·  " + media.esc(media.artist) + "</font>" : "")
                textFormat: Text.StyledText
                elide: Text.ElideRight
                color: g.cFg
                font.family: Tokens.font.ui
                font.pixelSize: g.px(Tokens.size.small)
            }
            Rectangle {         // progress
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                radius: 1
                visible: media.length > 0
                color: C.alpha(g.pal.edge, 0.12)
                Rectangle {
                    height: parent.height
                    radius: 1
                    width: parent.width * Math.max(0, Math.min(1, media.position / Math.max(1, media.length)))
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: g.cPrimary }
                        GradientStop { position: 1; color: g.cTertiary }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (media.player && media.player.canRaise) media.player.Raise()
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            MediaButton {
                glyph: "skip_previous"
                enabled: media.player ? media.player.canGoPrevious : false
                onClicked: media.player.Previous()
            }
            MediaButton {
                glyph: media.playing ? "pause" : "play_arrow"
                big: true
                enabled: media.player ? (media.playing ? media.player.canPause : media.player.canPlay) : false
                onClicked: media.playing ? media.player.Pause() : media.player.Play()
            }
            MediaButton {
                glyph: "skip_next"
                enabled: media.player ? media.player.canGoNext : false
                onClicked: media.player.Next()
            }
        }
    }

    // like Rice's IconButton, with filled glyphs (the outlined play/pause read too thin this small)
    component MediaButton: Item {
        id: btn
        property string glyph
        property bool big: false
        signal clicked()
        width: media.g.px(big ? 28 : 24)
        height: media.h - 2 * media.pad
        opacity: enabled ? 1 : 0.35
        Rectangle {
            anchors.centerIn: parent
            width: btn.width
            height: width
            radius: Math.min(height / 2, Tokens.radius.sm)
            color: area.pressed ? C.alpha(media.g.cFg, Tokens.alpha.press)
                 : area.containsMouse ? C.alpha(media.g.cFg, Tokens.alpha.hover) : "transparent"
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: area.containsMouse ? media.g.cPrimary : media.g.cFg
            font.family: Tokens.font.icons
            font.pixelSize: media.g.px(btn.big ? 22 : 18)
            font.variableAxes: ({ "FILL": 1 })
            renderType: Text.NativeRendering     // the distance-field renderer ignores variable axes
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            enabled: btn.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
