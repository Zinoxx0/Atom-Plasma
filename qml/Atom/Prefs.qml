pragma Singleton
import QtQuick
import QtCore
import Rice

// The shell's own settings, read live from the rice's settings.json (~/.config/atom-plasma, written by rice.py:
// a replaced file is one change): one object for every widget in plasmashell (Atom is one module, one engine).
//   backdropStyle  "solid" (Solid) | "satin" (Satin) | "aurora" (Aurora) | "matte" (Sanded glass) | "clear" (Blur)
//                  | "liquid" (Liquid glass) | "none" (Clear) [+ legacy "noise"]:
//                  the launcher's and the power page's backdrop (rice.py backdrop ..., Theme page's "Backdrop";
//                  settings backdrop.style, blur.style before 1.1)
//   launcherSize   the launcher's own size on each screen's standard size (rice.py launcher size F)
//   launcherStyle  which launcher opens: "simplified" (Stage.qml) or a folder of the launcher's styles/ with a
//                  Stage.qml ("atom"); rice.py launcher style NAME
Item {
    id: prefs
    visible: false
    WatchedJson {
        id: file
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.config/atom-plasma/settings.json"
    }
    readonly property var value: file.value || ({})
    readonly property url grain: Qt.resolvedUrl("grain.png")       // the matte finish's grain (Backdrop, previews)
    readonly property url liquidBackdropShader: Qt.resolvedUrl("liquid_backdrop.frag.qsb")
    readonly property url auroraBackdropShader: Qt.resolvedUrl("aurora_backdrop.frag.qsb")
    readonly property url opticalGlassShader: Qt.resolvedUrl("liquid_glass.frag.qsb")
    // The two styles, the same on every surface that wears them (measured on screenshots: the launcher and the
    // power page must match): the grain is always the TOP layer of a backdrop (over its veil and any scrim:
    // under a veil it faded to half), at this strength; the glass's veil is the power page's.
    readonly property real grainAlpha: 0.05
    readonly property real glassVeil: 0.52
    readonly property string backdropStyle: {
        const st = (value.backdrop || value.blur || {}).style
        return ["solid", "satin", "aurora", "clear", "liquid", "noise", "none"].indexOf(st) >= 0 ? st : "matte"
    }
    // the bar's islands (rice.py bar style ...): solid | satin | aurora | matte | clear | liquid | none
    readonly property string barStyle: value.bar && ["satin", "aurora", "matte", "clear", "liquid", "none"].indexOf(value.bar.style) >= 0 ? value.bar.style : "solid"
    // true for bar styles rendered by Atom.LiquidBar & Glass GPU shaders (liquid, aurora)
    readonly property bool barShadered: barStyle === "liquid" || barStyle === "aurora"
    readonly property string launcherStyle: {
        const v = value.launcher ? String(value.launcher.style || "") : ""
        return /^[a-z0-9-]+$/.test(v) ? v : "simplified"
    }
    readonly property real launcherSize: {
        const v = value.launcher ? Number(value.launcher.size) : 1
        return v > 0 ? Math.max(0.6, Math.min(2, v)) : 1
    }
    // Misc Modules (settings.json `modules.<id>.{enabled, config}`): live-watched across every plasmoid
    readonly property var modules: value.modules || ({})
    function moduleEnabled(id, fallback) {
        const m = modules[id]
        if (m && typeof m.enabled === "boolean") return m.enabled
        return fallback === undefined ? true : !!fallback
    }
    function moduleOpt(id, key, fallback) {
        const m = modules[id]
        const c = m && m.config ? m.config : null
        if (c && c[key] !== undefined && c[key] !== null) return c[key]
        return fallback
    }
}
