import QtQuick
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// One app: its icon over its name, lit in the app's own colour when pointed at. Click launches, right-click
// opens the app's menu (pin, its actions), dragging it onto the bar pins it there. Used by the folders.
Item {
    id: tile
    required property var launcher
    required property RicePalette rice
    required property var sourceModel           // the Kicker model it comes from
    required property int row
    property var roles: null                    // the delegate's roles (favoriteId, actionList: the menu reads them)
    property var decoration
    property string label: ""
    property string url: ""
    property real iconSize: 44
    property bool current: false                 // keyboard selection
    readonly property bool hot: m.containsMouse || current
    readonly property color tint: C.appTint(colors, rice.primary)
    Kirigami.ImageColors { id: colors; source: tile.decoration }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: Tokens.space.xs
        radius: Tokens.radius.md
        color: C.alpha(tile.tint, m.pressed ? 0.26 : tile.hot ? 0.17 : 0)
        border.width: 1
        border.color: C.alpha(tile.tint, tile.hot ? 0.45 : 0)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
    }
    AppGlow {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.space.sm + tile.iconSize / 2 + Tokens.space.xs - height / 2
        width: tile.iconSize * 2.2
        tint: tile.tint
        strength: (tile.hot ? 0.42 : 0.16) * Math.max(0.3, tile.rice.glow)
        Behavior on strength { NumberAnimation { duration: Tokens.base } }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.space.sm + Tokens.space.xs
        spacing: Tokens.space.sm
        scale: m.pressed ? 0.95 : tile.hot ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
        Kirigami.Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: tile.iconSize; height: width
            source: tile.decoration
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: tile.width - Tokens.space.md
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.92
            color: tile.rice.fg
            font.family: Tokens.font.ui
            font.weight: Font.Medium
            font.pixelSize: Math.round(tile.iconSize * 0.27)
        }
    }
    FocusRing { ink: tile.rice.edge; radius: card.radius; target: card; shown: tile.current; gap: 1 }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point pressAt
        onPressed: mouse => pressAt = Qt.point(mouse.x, mouse.y)
        onPositionChanged: mouse => {      // drag an app onto the bar to pin it there
            if (pressed && tile.url && tile.launcher.kickerDrag.isDrag(pressAt.x, pressAt.y, mouse.x, mouse.y))
                tile.launcher.kickerDrag.startDrag(tile.launcher, tile.url)
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) tile.launcher.menu.openFor(tile, tile.sourceModel, tile.row)
            else tile.launcher.launch(tile.sourceModel, tile.row)
        }
    }
}
