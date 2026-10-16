import QtQuick
import org.kde.plasma.private.mpris as Mpris

// What's playing (MPRIS): the current player, its track and art, and a position counted locally
// (MPRIS only reports it on seeks), stepped every 2 s while playing.
Item {
    id: m
    Mpris.Mpris2Model { id: mpris }
    readonly property var player: mpris.currentPlayer
    readonly property int status: player ? player.playbackStatus : Mpris.PlaybackStatus.Unknown
    readonly property bool playing: status === Mpris.PlaybackStatus.Playing
    readonly property bool present: !!player && status > Mpris.PlaybackStatus.Stopped && track !== ""
    readonly property string track: player ? player.track : ""
    readonly property string artist: player ? player.artist : ""
    readonly property string artUrl: player ? player.artUrl : ""
    readonly property real length: player ? player.length : 0          // µs
    readonly property bool canPrev: player ? player.canGoPrevious : false
    readonly property bool canNext: player ? player.canGoNext : false
    readonly property bool canToggle: player ? (playing ? player.canPause : player.canPlay) : false
    function prev() { if (player) player.Previous() }
    function next() { if (player) player.Next() }
    function toggle() { if (player) { if (playing) player.Pause(); else player.Play() } }

    property real position: 0
    function sync() { position = player ? player.position : 0 }
    onPlayerChanged: sync()
    onTrackChanged: sync()
    Connections {
        target: m.player
        ignoreUnknownSignals: true
        function onPositionChanged() { m.position = m.player.position }
    }
    Timer {
        interval: 2000
        repeat: true
        running: m.playing && m.length > 0
        onTriggered: m.position = Math.min(m.length, m.position + 2e6 * (m.player ? m.player.rate || 1 : 1))
    }
}
