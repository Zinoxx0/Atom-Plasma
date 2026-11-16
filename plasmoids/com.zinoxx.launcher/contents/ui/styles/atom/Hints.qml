import QtQuick
import Atom.Native
import Rice

// Atom's hints, bottom left: what the controls do on this page, the pad's letters while a pad is in use, the keys
// otherwise. stage.hints = { pad: [["LB RB", "Pages"], ...], keys: [["Tab", "Pages"], ...] } (the page sets it).
Row {
    id: hints
    required property var stage
    readonly property var rice: hints.stage.rice
    function d(px) { return hints.stage.d(px) }
    x: hints.stage.side
    y: hints.stage.height - height - hints.d(34)
    spacing: hints.d(24)
    opacity: hints.stage.topO
    Repeater {
        model: (Gamepad.inUse ? (hints.stage.hints.pad || []) : (hints.stage.hints.keys || []))
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
