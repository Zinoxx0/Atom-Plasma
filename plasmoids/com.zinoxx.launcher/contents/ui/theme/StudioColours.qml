import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The Theme page's Colours, for the screen being edited: where they come from (the wallpaper's own, or a mood: each
// card a small picture of the surfaces and accents it makes from this screen's hue), the three accents (a swatch
// opens the colour editor at it; "Back to the wallpaper's" drops the hand-picked ones), and how strong they are.
Column {
    id: cs
    required property Item studio
    readonly property var lk: studio.look
    readonly property var tp: studio.targetPal
    function d(px) { return studio.d(px) }
    readonly property var row: studio.row("colours")
    readonly property var items: row ? row.items : []
    readonly property var moodWords: ({ neon: "Saturated accents that glow.", soft: "Pastel accents, gentle on the eyes.", light: "Light surfaces with deep accents.",
                                        void: "Near black, one quiet accent.", graphite: "Neutral greys; colour only where it matters." })
    // a mood's look, from this screen's hue
    function moodLook(m) {
        const b = Qt.color(cs.tp.primary), h = b.hslHue < 0 ? 0.75 : b.hslHue, H = dh => (h + dh / 360 + 2) % 1, c = (dh, s, l) => Qt.hsla(H(dh), s, l, 1)
        if (m === "neon") return { bg: c(0, 0.45, 0.09), ink: Qt.rgba(1, 1, 1, 0.8), dots: [c(0, 0.9, 0.62), c(40, 0.9, 0.62), c(-50, 0.85, 0.55)] }
        if (m === "soft") return { bg: c(0, 0.18, 0.13), ink: Qt.rgba(1, 1, 1, 0.8), dots: [c(0, 0.6, 0.82), c(40, 0.6, 0.85), c(-50, 0.5, 0.78)] }
        if (m === "light") return { bg: c(0, 0.25, 0.95), ink: Qt.rgba(0.07, 0.07, 0.09, 0.55), dots: [c(0, 0.6, 0.38), c(40, 0.6, 0.4), c(-50, 0.6, 0.35)] }
        if (m === "void") return { bg: "#0a0a0c", ink: Qt.rgba(1, 1, 1, 0.8), dots: [c(0, 0.5, 0.7)] }
        return { bg: "#2a2b2e", ink: Qt.rgba(1, 1, 1, 0.8), dots: ["#8e9096", "#6c6e74", c(0, 0.15, 0.62)] }
    }

    StudioCap { studio: cs.studio; text: "Mood"; note: "where the colours come from" }
    Item { width: 1; height: cs.d(14) }
    Row {
        spacing: cs.d(18)
        Repeater {
            model: cs.items.filter(x => x.kind === "colours-auto" || x.kind === "mood")
            StudioCard {
                id: mc
                required property var modelData
                readonly property bool auto: modelData.kind === "colours-auto"
                readonly property var ml: auto ? null : cs.moodLook(modelData.mood)
                studio: cs.studio
                fkey: "src:" + (modelData.mood || "auto")
                name: modelData.name
                note: auto ? "from the wallpaper" : ""
                current: !!modelData.current
                desc: "<b>" + modelData.name + "</b> " + (auto ? "The wallpaper's own mood and accents, read when it's set." : cs.moodWords[modelData.mood] || "")
                act: "Use"
                onActivated: cs.studio.model.apply(modelData)
                Loader {
                    active: mc.auto
                    anchors.fill: parent
                    sourceComponent: RoundImage {
                        radius: cs.d(14)
                        fill: C.alpha(cs.lk.surfaceHigh, 0.6)
                        shadowBlur: cs.d(14)
                        source: cs.studio.targetThumb ? "file://" + cs.studio.targetThumb : ""
                    }
                }
                Kirigami.ShadowedRectangle {
                    visible: !mc.auto
                    anchors.fill: parent; radius: cs.d(14)
                    color: mc.ml ? mc.ml.bg : "transparent"
                    shadow.size: cs.d(14); shadow.yOffset: cs.d(6); shadow.color: Qt.rgba(0, 0, 0, 0.28)
                    Rectangle { x: cs.d(18); y: cs.d(18); width: parent.width * 0.56; height: cs.d(9); radius: height / 2; color: mc.ml ? mc.ml.ink : "transparent" }
                    Rectangle { x: cs.d(18); y: cs.d(36); width: parent.width * 0.36; height: cs.d(9); radius: height / 2; color: mc.ml ? mc.ml.ink : "transparent"; opacity: 0.5 }
                }
                Row {
                    x: cs.d(18); y: parent.height - height - cs.d(18)
                    spacing: cs.d(8)
                    Repeater {
                        model: mc.auto ? [cs.tp.primary, cs.tp.secondary, cs.tp.tertiary] : mc.ml ? mc.ml.dots : []
                        Rectangle { required property var modelData; width: cs.d(24); height: width; radius: width / 2; color: modelData; border.width: mc.auto ? cs.d(2) : 0; border.color: Qt.rgba(0, 0, 0, 0.4) }
                    }
                }
            }
        }
    }
    Item { width: 1; height: cs.d(40) }
    StudioCap { studio: cs.studio; text: "Accents"; note: cs.items.some(x => x.kind === "accent" && x.current) ? "hand-picked" : "from the wallpaper" }
    Item { width: 1; height: cs.d(14) }
    Row {
        spacing: cs.d(34)
        Repeater {
            model: cs.items.filter(x => x.kind === "accent")
            Focusable {
                id: sw
                required property var modelData
                readonly property color c: cs.tp[modelData.role] || cs.lk.primary
                studio: cs.studio
                fkey: "acc:" + modelData.role
                width: cs.d(150); height: col.height
                lensItem: disc
                lensRadius: disc.width / 2
                desc: "<b>" + modelData.name + "</b> Pick your own to mismatch on purpose; a new wallpaper on that screen brings the automatic one back."
                act: "Edit colour"
                onActivated: cs.studio.editAccent(Object.assign({}, modelData, { hex: C.hex(sw.c) }), disc)
                onMenu: activated()
                Column {
                    id: col
                    width: parent.width
                    spacing: cs.d(12)
                    Item {
                        width: parent.width; height: cs.d(96)
                        Rectangle {
                            id: disc
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: cs.d(96); height: width; radius: width / 2
                            color: sw.c
                            border.width: cs.d(1.5); border.color: Qt.rgba(1, 1, 1, 0.2)
                            scale: sw.hovered && !sw.focused ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: Tokens.ms(200) } }
                        }
                        Rectangle {
                            visible: !!sw.modelData.current
                            x: disc.x + disc.width - width * 0.8; y: 0
                            width: cs.d(28); height: width; radius: width / 2; color: cs.lk.primary
                            Text { anchors.centerIn: parent; text: "check"; color: cs.lk.surfaceLowest; font.family: Tokens.font.icons; font.weight: Font.Bold; font.pixelSize: cs.d(18) }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: sw.modelData.name; color: cs.lk.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: cs.d(16) }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: C.hex(sw.c); color: cs.lk.fgDim; font.family: Tokens.font.mono; font.pixelSize: cs.d(14) }
                }
            }
        }
        StudioChip {
            studio: cs.studio
            y: cs.d(25)
            fkey: "acc:reset"
            icon: "restart_alt"
            text: "Back to the wallpaper's"
            desc: "<b>Back to the wallpaper's</b> Drops the hand-picked accents."
            act: "Reset"
            onActivated: cs.studio.model.resetAccents()
        }
    }
    Item { width: 1; height: cs.d(40) }
    StudioCap { studio: cs.studio; text: "Intensity"; note: "how strongly the accents show" }
    Item { width: 1; height: cs.d(14) }
    StudioSlider {
        studio: cs.studio
        fkey: "sl:int"
        value: cs.studio.model.intensity
        min: 0.3; max: 1.5; step: 0.1; def: 1
        defLabel: "Standard"
        fmt: function (v) { return Math.round(v * 100) + "%" }
        desc: "<b>Intensity</b> Calmer or stronger accents. Left and right to change it."
        onCommit: v => cs.studio.model.setIntensity(v)
    }
}
