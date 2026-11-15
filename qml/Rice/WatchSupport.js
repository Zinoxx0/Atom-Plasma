.pragma library
// Whether Atom.Native's FileWatch can be made here: in plasmashell (its QML_IMPORT_PATH) yes; in the splash,
// the logout screen or a bare qml6, maybe not. Asked once per engine, quietly (a failed import throws, it
// doesn't log).
var native = null           // null: not asked yet

function make(parent) {
    if (native === false)
        return null
    try {
        const w = Qt.createQmlObject("import Atom.Native\nFileWatch {}", parent, "WatchSupport")
        native = true
        return w
    } catch (e) {
        native = false
        return null
    }
}
