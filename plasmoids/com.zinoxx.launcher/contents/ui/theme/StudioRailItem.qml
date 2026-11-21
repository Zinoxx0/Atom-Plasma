import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import Rice

// A section in the Theme page's side column: its icon (Wallpapers: the edited screen's wallpaper; Colours: its three
// accents), its name and its value now. The open one sits on a lighter glass with its icon in the accent.
Focusable {
    id: ri
    required property var sec              // { id, icon, name, scope }
    property string panel: "every"
    readonly property var lk: studio.look
    readonly property bool open: studio.section === sec.id
    width: studio.d(460)
    height: studio.d(74)
    rail: true
    inSide: true
    fkey: "sec:" + sec.id
    lensRadius: studio.d(18)
    desc: "<b>" + sec.name + "</b> " + studio.summary(sec.id)
    act: "Open"
    onActivated: studio.setSection(sec.id, true)
    Rectangle {
        anchors.fill: parent
        radius: ri.studio.d(18)
        color: ri.open ? C.alpha(ri.lk.fg, 0.11) : ri.hovered ? C.alpha(ri.lk.fg, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: Tokens.ms(300) } }
    }
    Item {
        id: ico
        x: ri.studio.d(18)
        width: ri.studio.d(36); height: parent.height
        Loader {        // Wallpapers: the screen's own
            active: ri.sec.id === "walls"
            anchors.centerIn: parent
            sourceComponent: RoundImage {
                width: ri.studio.d(36); height: ri.studio.d(27); radius: ri.studio.d(7)
                shadow: false
                fill: C.alpha(ri.lk.surfaceHigh, 0.6)
                border: ri.studio.d(1.5); borderColor: C.alpha(ri.lk.fg, 0.3)
                sourceWidth: 96
                source: ri.studio.targetThumb ? "file://" + ri.studio.targetThumb : ""
            }
        }
        Item {      // Colours: its three accents
            visible: ri.sec.id === "colours"
            anchors.centerIn: parent
            width: ri.studio.d(30); height: ri.studio.d(28)
            Repeater {
                model: [ri.studio.targetPal.primary, ri.studio.targetPal.secondary, ri.studio.targetPal.tertiary]
                Rectangle {
                    required property var modelData
                    required property int index
                    width: ri.studio.d(16); height: width; radius: width / 2
                    x: [ri.studio.d(7), 0, ri.studio.d(14)][index]; y: [0, ri.studio.d(12), ri.studio.d(12)][index]
                    color: modelData
                    border.width: 1; border.color: C.alpha(ri.lk.surfaceLowest, 0.5)
                }
            }
        }
        Text {
            visible: ri.sec.id !== "walls" && ri.sec.id !== "colours"
            anchors.centerIn: parent
            text: ri.sec.icon
            color: ri.open ? ri.lk.primary : ri.lk.fgDim
            font.family: Tokens.font.icons; font.pixelSize: ri.studio.d(27)
        }
    }
    Column {
        x: ico.x + ico.width + ri.studio.d(18)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - ri.studio.d(14)
        spacing: ri.studio.d(6)
        Text { text: ri.sec.name; color: ri.lk.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: ri.studio.d(19) }
        Text { width: parent.width; text: ri.studio.summary(ri.sec.id); elide: Text.ElideRight; color: ri.lk.fgDim; font.family: Tokens.font.ui; font.pixelSize: ri.studio.d(14.5) }
    }
}
