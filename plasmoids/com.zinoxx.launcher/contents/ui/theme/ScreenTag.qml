import QtQuick
import Atom
import Rice

// The screen being edited, as one filled chip (the same mark on the desk map's label, the panel's heading and the
// section's header ties them together): a monitor and its name, or "Every screen".
Rectangle {
    id: tag
    required property Item studio
    property bool small: false
    readonly property bool all: studio.model.target === "all"
    width: row.width + studio.d(small ? 16 : 20)
    height: studio.d(small ? 26 : 30)
    radius: studio.d(small ? 8 : 9)
    color: studio.look.primary
    Row {
        id: row
        anchors.centerIn: parent
        spacing: tag.studio.d(6)
        Text { anchors.verticalCenter: parent.verticalCenter; text: tag.all ? "select_all" : "monitor"; color: tag.studio.look.surfaceLowest; font.family: Tokens.font.icons; font.pixelSize: tag.studio.d(tag.small ? 16 : 18) }
        Text { anchors.verticalCenter: parent.verticalCenter; text: tag.studio.targetName; color: tag.studio.look.surfaceLowest; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: tag.studio.d(tag.small ? 13 : 15) }
    }
}
