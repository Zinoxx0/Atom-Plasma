import QtQuick
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

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

    function col(name) { return values[name] ?? Tokens.fallback[name] ?? "#ff00ff" }

    // the usual roles, as colours
    readonly property color surfaceLowest: col("surface_lowest")
    readonly property color surface: col("surface")
    readonly property color surfaceLow: col("surface_low")
    readonly property color surfaceContainer: col("surface_container")
    readonly property color surfaceHigh: col("surface_high")
    readonly property color surfaceHighest: col("surface_highest")
    readonly property color outline: col("outline")
    readonly property color outlineVariant: col("outline_variant")
    readonly property color muted: col("muted")
    readonly property color fg: col("on_surface")
    readonly property color fgDim: col("on_surface_variant")
    readonly property color primary: col("primary")
    readonly property color onPrimary: col("on_primary")
    readonly property color secondary: col("secondary")
    readonly property color tertiary: col("tertiary")
    readonly property color red: col("red")
    readonly property color orange: col("orange")
    readonly property color yellow: col("yellow")
    readonly property color green: col("green")
    readonly property color teal: col("teal")
    readonly property color cyan: col("cyan")
    readonly property color blue: col("blue")
    readonly property color magenta: col("magenta")
    readonly property color claude: col("claude")

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
    // rice.py re-themes by switching the colour scheme (RiceA/RiceB): the cue to re-read the file
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()
    onOutputChanged: refresh()
    Component.onCompleted: refresh()
}
