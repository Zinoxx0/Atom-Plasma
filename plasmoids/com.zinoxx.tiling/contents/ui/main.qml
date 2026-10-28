import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Rice"

// Auto-tiling for the screen this bar is on, like "Peek at Desktop": one glyph, click to flip it.
// The state is rice.py's (~/.local/state/rice/tiling.json, written by atom/tiling.py): screens float
// unless set to tile. Hidden when Krohnkite isn't installed. Meta+Alt+T does the same for the focused
// window's screen.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property real uiScale: pal.uiScale
    readonly property string screenName: Screen.name

    WatchedJson {
        id: st
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
              + "/.local/state/rice/tiling.json"
        onChanged: root.pending = false
    }
    readonly property bool available: !st.answered || (st.value?.available ?? false)
    readonly property bool tiled: (st.value?.screens ?? {})[screenName] === "tile"
    property bool pending: false        // clicked, the state file hasn't caught up yet

    Plasmoid.status: available ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if ((data["exit code"] ?? 0) !== 0) {
                root.pending = false
                console.warn("tiling:", data["stderr"])
            }
        }
    }
    function toggle() {
        if (!screenName) return
        pending = true
        // one fixed command per screen (RiceShell: repeating commands keep fixed names)
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" tiling toggle --screen ' + sh.q(screenName)
                         + " #tiling")
    }

    toolTipMainText: tiled ? "Auto-tiling is on" : "Windows float"
    toolTipSubText: (tiled ? "This screen arranges its windows in tiles" : "Windows on this screen go where you put them")
                    + " · click to " + (tiled ? "let them float" : "tile them") + " · Meta+Alt+T"
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        // a single-widget island: the same side padding as every rice bar widget
        Layout.minimumWidth: glyph.implicitWidth + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.toggle()
        Text {
            id: glyph
            anchors.centerIn: parent
            // tiles when tiling, two loose overlapping windows when floating
            text: root.tiled ? "grid_view" : "filter_none"
            color: root.tiled ? pal.primary : compact.containsMouse ? pal.fg : pal.fgDim
            opacity: root.pending ? 0.5 : 1
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(19 * root.uiScale)
            scale: compact.pressed ? 0.88 : 1
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        }
    }
}
