import QtQuick
import Atom.Native
import Rice

// Atom's hints, bottom left: what the controls do on this page, for the input in use only (stage.input: the pad's
// letters, the keys, NOTHING for the pointer: the user, 2026-11-23). stage.hints = { pad: [["LB RB", "Pages"], ...],
// keys: [["Tab", "Pages"], ...] } (the page sets it); on the top bar its own; every page adds the way up to it.
Row {
    id: hints
    required property var stage
    readonly property var rice: hints.stage.look
    function d(px) { return hints.stage.d(px) }
    x: hints.stage.side
    y: hints.stage.height - height - hints.d(34)
    spacing: hints.d(24)
    opacity: hints.stage.topO * (hints.stage.keysShown ? 1 : 0)
    Behavior on opacity { enabled: hints.stage.phase === "open"; NumberAnimation { duration: Tokens.ms(260) } }
    visible: opacity > 0.01
    readonly property bool pad: hints.stage.input === "pad"
    readonly property var shown: hints.stage.zone === "top"
        ? (pad ? [["✥", "Move"], ["A", "Select"], ["B", "Back"]] : [["← →", "Move"], ["Enter", "Select"], ["Esc", "Back"]])
        : pad ? (hints.stage.hints.pad || []).concat([["≡", "Top bar"]])
              : (hints.stage.hints.keys || []).concat(hints.stage.searching ? [] : [["F10", "Top bar"]])
    // (kept while the pointer's in use, so they don't change as they fade)
    property var model: []
    onShownChanged: if (hints.stage.keysShown) model = shown
    Connections { target: hints.stage; function onKeysShownChanged() { if (hints.stage.keysShown) hints.model = hints.shown } }
    Component.onCompleted: model = shown
    Repeater {
        model: hints.model
        Row {
            required property var modelData
            spacing: hints.d(8)
            Repeater {
                model: String(modelData[0]).split(" ")
                Rectangle { required property string modelData
                            width: Math.max(height, kt.implicitWidth + hints.d(12)); height: hints.d(26); radius: hints.d(8)
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            color: "transparent"; border.width: Math.max(1, hints.d(1.5)); border.color: C.alpha(hints.rice.fg, 0.34)
                            Text { id: kt; anchors.centerIn: parent; text: modelData; color: hints.rice.fgDim; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: hints.d(12.5) } }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: String(modelData[1]); color: hints.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: hints.d(14.5) }
        }
    }
}
