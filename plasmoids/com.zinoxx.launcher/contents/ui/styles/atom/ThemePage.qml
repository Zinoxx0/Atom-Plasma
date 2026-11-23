import QtQuick
import Atom
import Rice
import "../.."          // ThemeModel: what the Theme page shows and the commands that apply it
import "../../theme"    // ThemeStudio: the Theme page itself, the same in every launcher style

// Atom's Theme page: the shared one (ThemeStudio, the user's pick for both launchers, 2026-11-21) under Atom's top
// bar. The scene behind wears what's in focus: a previewed wallpaper sharp, with the palette it would make
// (stage.previewValues, stage.focusItem). The caption and the hints are the page's own (Stage hides Atom's).
Item {
    id: page
    required property var stage
    anchors.fill: parent

    ThemeModel { id: tm; launcher: page.stage.launcher; rice: page.stage.rice; screenName: page.stage.screenName }
    ThemeStudio {
        id: studio
        anchors.fill: parent
        launcher: page.stage.launcher
        model: tm
        rice: page.stage.rice
        look: page.stage.look
        screenName: page.stage.screenName
        unit: page.stage.unit
        topInset: page.stage.d(140)
        wideFamily: page.stage.wideFamily
        veil: 0.42
        opacity: page.stage.capO
        origin: Qt.point(page.stage.screenObj ? page.stage.screenObj.virtualX : 0, (page.stage.screenObj ? page.stage.screenObj.virtualY : 0) + page.stage.topGap)
        onPreview: (values, image, thumb) => {
            page.stage.previewValues = values
            page.stage.focusItem = image ? { hero: "file://" + image, sharp: true } : null
        }
        onGiveKeys: page.stage.takeKeys()
        onLeave: page.stage.enterTop("theme")           // (up past its top: the top bar)
    }
    Component.onCompleted: {
        page.stage.pageApi = { key: e => studio.key(e), wheel: dy => studio.wheel(dy), north: () => studio.north(), openSection: r => studio.openSection(r),
                                save: () => ({ section: studio.section }), restore: f => { if (f.section) studio.setSection(f.section, true) },
                                enter: () => studio.setSection(studio.section, true) }
        page.stage.hints = { pad: [], keys: [] }
        page.stage.caption = { where: [], name: "" }
        if (page.stage.launcher.themeRow) Qt.callLater(() => studio.openSection(page.stage.launcher.themeRow))
    }
    Component.onDestruction: if (page.stage) { page.stage.previewValues = null; page.stage.focusItem = null }
}
