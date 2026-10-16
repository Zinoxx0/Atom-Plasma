import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "Color.js" as C

// This screen's wallpaper palette (~/.local/state/rice/palette-<output>.json, written by rice.py),
// for every rice widget. Until it has loaded, and for keys a palette lacks, it answers with one
// shared set of dark Tokyo Night colours (Tokens.fallback), so all widgets agree at login.
//
//   RicePalette { id: pal; output: Screen.name }   then pal.primary, pal.col("teal"), pal.uiScale
Item {
    id: rp
    visible: false

    property string output: ""                  // the widget's Screen.name
    property var values: ({})                   // the raw palette JSON
    readonly property bool loaded: values.primary !== undefined
    readonly property real uiScale: values._scale || 1          // rice settings bar_scale
    readonly property real topScale: values._topScale || 1      // rice settings top_scale
    readonly property string wallpaper: values._wallpaper || ""
    readonly property string thumb: values._thumb || ""
    // the wallpaper's character (palette v2): neon / soft / light / void / graphite
    readonly property string mood: values._mood || "soft"
    readonly property bool light: values._scheme === "light"
    readonly property real glow: values._glow ?? 0.7       // how much things glow: 1 neon .. 0.35 void
    readonly property color edge: values._edge || "#ffffff" // hairlines and sheens

    function col(name) { return values[name] ?? Tokens.fallback[name] ?? "#ff00ff" }

    // The usual roles, as colours. They glide to a new wallpaper's colours instead of snapping (not at
    // the first load: widgets start in their screen's colours). onPrimary doesn't: QML reads a name
    // starting with "on" as a signal handler, and `Behavior on onPrimary` crashes the engine.
    property bool glide: false
    onLoadedChanged: if (loaded) Qt.callLater(() => rp.glide = true)
    property color surfaceLowest: col("surface_lowest")
    property color surface: col("surface")
    property color surfaceLow: col("surface_low")
    property color surfaceContainer: col("surface_container")
    property color surfaceHigh: col("surface_high")
    property color surfaceHighest: col("surface_highest")
    property color outline: col("outline")
    property color outlineVariant: col("outline_variant")
    property color muted: col("muted")
    property color fg: col("on_surface")
    property color fgDim: col("on_surface_variant")
    property color primary: col("primary")
    property color onPrimary: col("on_primary")
    property color secondary: col("secondary")
    property color tertiary: col("tertiary")
    property color claude: col("claude")
    // Status hues (and the candy accents) are pulled a little toward this screen's primary, so a
    // green "on track" or a red warning still reads as itself but belongs to the wallpaper. col()
    // still answers with the raw palette.
    readonly property real harmony: 0.10
    // on a light screen the hues (made for dark backgrounds and terminals) are deepened so they read on frost
    function tuned(name) {
        const c = C.rgb(C.mix(col(name), col("primary"), harmony))
        return light ? Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.15), Math.min(c.hslLightness, 0.40), 1) : c
    }
    property color red: tuned("red")
    property color orange: tuned("orange")
    property color yellow: tuned("yellow")
    property color green: tuned("green")
    property color teal: tuned("teal")
    property color cyan: tuned("cyan")
    property color blue: tuned("blue")
    property color magenta: tuned("magenta")
    // what a state means, for chips, meters and alerts
    readonly property color ok: values.ok ? col("ok") : green
    readonly property color warn: values.warn ? col("warn") : yellow
    readonly property color bad: values.bad ? col("bad") : red
    Behavior on surfaceLowest { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on surface { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on surfaceLow { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on surfaceContainer { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on surfaceHigh { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on surfaceHighest { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on outline { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on outlineVariant { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on muted { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on fg { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on fgDim { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on primary { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on secondary { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on tertiary { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on claude { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on red { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on orange { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on yellow { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on green { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on teal { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on cyan { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on blue { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }
    Behavior on magenta { enabled: rp.glide; ColorAnimation { duration: Tokens.ms(700); easing.type: Tokens.move } }

    function refresh() {
        if (output)
            sh.connectSource('cat "$HOME/.local/state/rice/palette-' + output + '.json" 2>/dev/null'
                             + ' || cat "$HOME/.local/state/rice/palette.json" #pal ' + output + ' ' + Date.now());
    }
    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            try {
                const j = JSON.parse(data["stdout"] ?? "");
                if (j && j.primary) rp.values = j;
            } catch (e) {}
            disconnectSource(source);
        }
    }
    // rice.py writes the file (to a temp name, then a rename) on every wallpaper change: a watch on
    // its folder (inotify, no polling) sees each replace, so every widget follows its screen at once.
    // The colour scheme switch used to be the cue, but plasmashell 6.8 no longer passes it on live.
    FolderListModel {
        folder: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/state/rice"
        nameFilters: rp.output ? ["palette-" + rp.output + ".json"] : []
        showDirs: false
        onDataChanged: reread.restart()
        onRowsInserted: reread.restart()
    }
    Timer { id: reread; interval: 120; onTriggered: rp.refresh() }     // one read per burst of writes
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()
    onOutputChanged: refresh()
    Component.onCompleted: refresh()
}
