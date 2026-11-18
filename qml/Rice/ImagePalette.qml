import QtQuick
import QtQml.Models
import org.kde.kirigami as Kirigami

// Kirigami.ImageColors whose source may change: use it wherever an ImageColors' source moves (a focus, a
// reused delegate, a track). Kirigami 6.32 SEGVs plasmashell when a live ImageColors gets a new source while a
// FILE source (a path or URL, not a theme icon name) is still loading: setSource cancels the old loader without
// disconnecting it, and its finished handler then reads the nulled m_futureSourceImageData (imagecolors.cpp;
// crash in QFutureInterfaceBase, hit 2026-11-18 by Atom's launcher). So here no ImageColors ever gets a second
// source: each source gets a fresh one (dropping the old one drops its loader), made once the source has
// settled for settleMs so a fast scroll doesn't make one per step. `palette` keeps the last colours until the
// new ones are in. Reads like ImageColors for C.appTint (only .palette).
QtObject {
    id: root
    property var source: ""
    property int settleMs: 120
    property var palette: []

    property var shownSource: ""
    onSourceChanged: settle.restart()
    Component.onCompleted: shownSource = source
    onShownSourceChanged: if (!shownSource) palette = []

    readonly property Timer settle: Timer { interval: root.settleMs; onTriggered: root.shownSource = root.source }
    readonly property Instantiator maker: Instantiator {
        model: root.shownSource ? [root.shownSource] : []
        delegate: Kirigami.ImageColors {
            id: ic
            required property var modelData
            source: modelData           // set once: this object never gets another source
            onPaletteChanged: root.palette = ic.palette
        }
    }
}
