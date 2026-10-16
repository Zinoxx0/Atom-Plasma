import QtQuick
import QtQuick.Layouts

// The header every rice popup opens with: optional leading art (an avatar, Clawd's card), the
// title in the display face with an optional badge beside it, a dim subtitle under it, and
// trailing controls on the right.
//
//   PopupHeader {
//       palette: pal; title: "System"; subtitle: "Thorfinn · up 3h"; Layout.fillWidth: true
//       trailing: IconButton { palette: pal; icon: "monitoring" }
//   }
RowLayout {
    id: head
    required override property RicePalette palette
    property string title: ""
    property string subtitle: ""
    property int subtitleLines: 2
    property alias leading: lead.data
    property alias badge: badgeSlot.data
    property alias trailing: trail.data

    spacing: Tokens.space.md

    Item {
        id: lead
        visible: children.length > 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        Layout.alignment: Qt.AlignVCenter
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Tokens.space.xxs
        RowLayout {
            spacing: Tokens.space.sm
            Text {
                text: head.title
                color: head.palette.fg
                font.family: Tokens.font.display
                font.weight: Font.ExtraBold
                font.pixelSize: Tokens.size.display
                elide: Text.ElideRight
                Layout.fillWidth: badgeSlot.children.length === 0
            }
            Item {
                id: badgeSlot
                visible: children.length > 0
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true; visible: badgeSlot.children.length > 0 }
        }
        Text {
            visible: text !== ""
            text: head.subtitle
            color: head.palette.fgDim
            font.family: Tokens.font.ui
            font.pixelSize: Tokens.size.label
            wrapMode: Text.WordWrap
            maximumLineCount: head.subtitleLines
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
    Item {
        id: trail
        visible: children.length > 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        Layout.alignment: Qt.AlignVCenter
    }
}
