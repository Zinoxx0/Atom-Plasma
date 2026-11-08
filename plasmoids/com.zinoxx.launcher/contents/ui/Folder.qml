import QtQuick
import org.kde.kirigami as Kirigami
import Atom
import "Rice"
import "Rice/Color.js" as C

// A category opened as a folder: a frosted panel (it grows out of its stack: the stage moves and sizes
// it) with the category's name and its apps, six to a row. Esc, the close mark or a click outside fold it
// back into its stack. Lives in the stage's full-window layer (Frost: x/y are window coordinates).
Frost {
    id: folder
    required property var launcher
    required property RicePalette rice
    property var cat: null
    property real unit: 1
    property real reveal: 0                     // the content's opacity (after the panel has grown)
    signal done()
    readonly property alias grid: grid
    function u(n) { return Math.round(n * unit) }

    radius: u(30)
    tintAlpha: 0.6
    rimAlpha: 0.4
    rimA: rice.primary
    rimB: rice.tertiary

    MouseArea { anchors.fill: parent }          // clicks on the panel don't reach the backdrop

    Item {
        anchors.fill: parent
        anchors.margins: folder.u(22)
        opacity: folder.reveal
        visible: opacity > 0.01

        Row {
            id: header
            spacing: folder.u(12)
            height: folder.u(40)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: folder.cat ? folder.cat.icon : ""
                color: folder.rice.primary
                font.family: Tokens.font.icons
                font.pixelSize: folder.u(26)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: folder.cat ? folder.cat.label : ""
                color: folder.rice.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: folder.u(22)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: grid.count + (grid.count === 1 ? " app" : " apps")
                color: folder.rice.muted
                font.family: Tokens.font.ui
                font.pixelSize: folder.u(13)
            }
        }
        Rectangle {     // close
            anchors { right: parent.right; verticalCenter: header.verticalCenter }
            width: folder.u(34); height: width; radius: width / 2
            color: C.alpha(folder.rice.fg, closeMouse.containsMouse ? 0.14 : 0.06)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Text {
                anchors.centerIn: parent
                text: "close"
                color: folder.rice.fg
                font.family: Tokens.font.icons
                font.pixelSize: folder.u(18)
            }
            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: folder.done() }
        }

        GridView {
            id: grid
            readonly property int columns: 6
            anchors { top: header.bottom; topMargin: folder.u(14); bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            width: columns * cellWidth
            cellWidth: Math.floor(parent.width / columns)
            cellHeight: folder.u(122)
            clip: true
            model: folder.cat ? folder.cat.model : null
            currentIndex: -1
            keyNavigationEnabled: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false
            onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && currentIndex >= 0) {
                    folder.launcher.launch(model, currentIndex); event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    folder.done(); event.accepted = true
                }
            }
            Rectangle {     // a slim scroll pip, quiet until the grid moves
                parent: grid
                anchors.right: parent.right
                y: grid.visibleArea.yPosition * grid.height
                width: 4
                height: Math.max(24, grid.visibleArea.heightRatio * grid.height)
                radius: 2
                color: C.alpha(folder.rice.fg, 0.3)
                visible: grid.contentHeight > grid.height + 1
                opacity: grid.moving ? 1 : 0.35
                Behavior on opacity { NumberAnimation { duration: Tokens.base } }
            }
            delegate: AppTile {
                id: app
                required property int index
                required property var model
                width: grid.cellWidth
                height: grid.cellHeight
                launcher: folder.launcher
                rice: folder.rice
                sourceModel: grid.model
                row: index
                roles: app.model
                decoration: app.model.decoration
                label: app.model.display
                url: app.model.url || ""
                iconSize: folder.u(52)
                current: GridView.isCurrentItem && grid.activeFocus
            }
        }
    }
}
