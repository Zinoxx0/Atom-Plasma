import QtQuick
import org.kde.plasma.private.mpris as Mpris

// What's playing (MPRIS): the current player, its track and art, the controls, and a position counted
// locally (MPRIS only reports it on seeks), stepped every `step` ms while playing and `ticking`.
//
//   NowPlaying { id: music; ticking: band.open; step: 1000 }     music.track, music.position / music.length
Item {
    id: m
    visible: false

    property bool ticking: true             // count the position (e.g. only while it's on screen)
    property int step: 2000

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
    readonly property bool canPrev: player ? player.canGoPrevious : false
    readonly property bool canNext: player ? player.canGoNext : false
    readonly property bool canToggle: player ? (playing ? player.canPause : player.canPlay) : false
    function prev() { if (player) player.Previous() }
    function next() { if (player) player.Next() }
    function toggle() { if (player) { if (playing) player.Pause(); else player.Play() } }

    property real position: 0
    function sync() {
        if (!player) { position = 0; return }
        player.updatePosition()
        position = player.position
    }
    onPlayerChanged: sync()
    onTrackChanged: sync()
    onTickingChanged: if (ticking) sync()
    Connections {
        target: m.player
        ignoreUnknownSignals: true
        function onPositionChanged() { m.position = m.player.position }
    }
    Timer {
        interval: m.step
        repeat: true
        running: m.ticking && m.playing && m.length > 0
        onTriggered: m.position = Math.min(m.length, m.position + m.step * 1000 * (m.player ? m.player.rate || 1 : 1))
    }
}
