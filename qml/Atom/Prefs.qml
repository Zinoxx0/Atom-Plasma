pragma Singleton
import QtQuick
import QtCore
import "../Rice"

// The shell's own settings, read live from the rice's settings.json (~/.config/atom-plasma, written by rice.py:
// a replaced file is one change): one object for every widget in plasmashell (Atom is one module, one engine).
//   blurStyle      "matte" (noisy matte) | "clear" (clear blur): the launcher's and the power page's backdrop
//                  (rice.py blur matte|clear, the Theme page's "Blur style")
//   launcherSize   the launcher's own size on each screen's standard size (rice.py launcher size F)
Item {
    id: prefs
    visible: false
    WatchedJson {
        id: file
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.config/atom-plasma/settings.json"
    }
    readonly property var value: file.value || ({})
    readonly property url grain: Qt.resolvedUrl("grain.png")       // the matte finish's grain (Backdrop, previews)
    readonly property string blurStyle: value.blur && value.blur.style === "clear" ? "clear" : "matte"
    readonly property real launcherSize: {
        const v = value.launcher ? Number(value.launcher.size) : 1
        return v > 0 ? Math.max(0.6, Math.min(2, v)) : 1
    }
}
