import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atom
import Atom.Native
import "../../Rice"
import "../../Rice/Color.js" as C

// An app's tray menu (right click on its icon in the status island), drawn on the shell's sheet in the
// rice's own look instead of a stock menu: the app's name, then its entries (checks, separators,
// submenus that open in place with a way back). A click runs the entry and closes it.
// args: { key } (the icon's Tray key, so a shifted row still finds it)
FocusScope {
    id: tm
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette
    function u(n) { return Math.round(n * ui) }

    readonly property int row: {
        for (let r = 0; r < Tray.count; r++) if (Tray.data(Tray.index(r, 0), Qt.UserRole + 1) === args.key) return r
        return -1
    }
    readonly property string title: row >= 0 ? Tray.data(Tray.index(row, 0), Qt.UserRole + 3) : ""
    property var stack: []                      // the menus opened so far (root first)
    readonly property var menu: stack.length ? stack[stack.length - 1] : null
    Component.onCompleted: { const m = row >= 0 ? Tray.menu(row) : null; if (m) stack = [m] }
    function enter() { forceActiveFocus() }
    Keys.onEscapePressed: event => { if (stack.length > 1) { stack = stack.slice(0, -1); event.accepted = true } else event.accepted = false }

    implicitWidth: u(280)
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: tm.width
        spacing: tm.u(2)
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: tm.u(6)
            spacing: tm.u(8)
            Rectangle {
                visible: tm.stack.length > 1
                implicitWidth: tm.u(28); implicitHeight: implicitWidth; radius: implicitWidth / 2
                color: C.alpha(tm.pal.fg, backM.containsMouse ? 0.13 : 0.06)
                Text { anchors.centerIn: parent; text: "arrow_back"; color: tm.pal.fg; font.family: Tokens.font.icons; font.pixelSize: tm.u(16) }
                MouseArea { id: backM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tm.stack = tm.stack.slice(0, -1) }
            }
            Text {
                Layout.fillWidth: true
                text: tm.title
                elide: Text.ElideRight
                color: tm.pal.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: tm.u(15)
            }
        }
        Text {
            visible: !tm.menu || (!tm.menu.ready && tm.menu.count === 0)
            text: tm.menu ? "…" : "No menu"
            color: tm.pal.muted
            font.family: Tokens.font.ui
            font.pixelSize: tm.u(12)
        }
        Repeater {
            model: tm.menu
            delegate: Item {
                id: entry
                required property int index
                required property var model             // (not one property per role: `enabled` is every Item's own)
                readonly property string text: model.text || ""
                readonly property string iconName: model.iconName || ""
                readonly property string iconSource: model.iconSource || ""
                readonly property bool on: model.enabled !== false
                readonly property bool checkable: !!model.checkable
                readonly property bool checked: !!model.checked
                readonly property bool separator: !!model.separator
                readonly property bool hasSubmenu: !!model.hasSubmenu
                Layout.fillWidth: true
                implicitHeight: separator ? tm.u(11) : tm.u(36)
                Rectangle {
                    visible: entry.separator
                    anchors.centerIn: parent
                    width: parent.width - tm.u(16); height: 1
                    color: C.alpha(tm.pal.edge, Tokens.alpha.outline)
                }
                Rectangle {
                    visible: !entry.separator
                    anchors.fill: parent
                    radius: tm.u(10)
                    color: em.containsMouse && entry.on ? C.alpha(tm.pal.primary, em.pressed ? 0.26 : 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                }
                RowLayout {
                    visible: !entry.separator
                    anchors { fill: parent; leftMargin: tm.u(10); rightMargin: tm.u(8) }
                    spacing: tm.u(10)
                    opacity: entry.on ? 1 : 0.45
                    Item {
                        implicitWidth: tm.u(18); implicitHeight: implicitWidth
                        Text {
                            anchors.centerIn: parent
                            visible: entry.checkable
                            text: entry.checked ? "check" : ""
                            color: tm.pal.primary
                            font.family: Tokens.font.icons
                            font.pixelSize: tm.u(18)
                        }
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !entry.checkable && (entry.iconName !== "" || entry.iconSource !== "")
                            source: entry.iconName || entry.iconSource
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: entry.text
                        elide: Text.ElideRight
                        color: tm.pal.fg
                        font.family: Tokens.font.ui
                        font.pixelSize: tm.u(13)
                    }
                    Text {
                        visible: entry.hasSubmenu
                        text: "chevron_right"
                        color: tm.pal.fgDim
                        font.family: Tokens.font.icons
                        font.pixelSize: tm.u(18)
                    }
                }
                MouseArea {
                    id: em
                    anchors.fill: parent
                    enabled: !entry.separator && entry.on
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (entry.hasSubmenu) {
                            const sub = tm.menu.submenu(entry.index)
                            if (sub) tm.stack = tm.stack.concat([sub])
                        } else {
                            tm.menu.trigger(entry.index)
                            Shell.close()
                        }
                    }
                }
            }
        }
    }
}
