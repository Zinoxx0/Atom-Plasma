import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// Atom Home's search results (KRunner, through the launcher's RunnerModel): the selected match large on the
// left (a card in its icon's colour: its name, what it is, and Enter), every match grouped by kind on the
// right. The launcher keeps the selection (selGroup, selRow; the arrows walk it); the pointer selects what
// it's over, a click launches, a right click opens the match's menu.
Item {
    id: hs
    required property var launcher
    required property RicePalette rice
    property real unit: 1
    function u(n) { return Math.round(n * unit) }
    readonly property var runner: launcher.runnerModel
    property var sel: null                  // the selected match: { name, desc, icon } (its delegate fills it in)
    readonly property bool hasResults: list.contentHeight > hs.u(20)

    Kirigami.ImageColors { id: colors; source: hs.sel ? hs.sel.icon : "" }
    readonly property color tint: C.appTint(colors, rice.primary)

    // ---- the selected match, large
    Item {
        id: card
        visible: hs.hasResults && !!hs.sel
        width: hs.u(340)
        height: hs.u(340)
        RectangularShadow { anchors.fill: parent; radius: hs.u(26); blur: hs.u(40); offset.y: hs.u(14); spread: -hs.u(12); color: Qt.rgba(0, 0, 0, 0.55) }
        Rectangle {
            anchors.fill: parent
            radius: hs.u(26)
            gradient: Gradient {
                GradientStop { position: 0; color: C.mix(hs.tint, "#0c1119", 0.62) }
                GradientStop { position: 1; color: C.mix(hs.tint, "#0a0e15", 0.88) }
            }
            border.width: 1
            border.color: C.alpha(hs.rice.edge, 0.12)
        }
        Kirigami.Icon {
            x: hs.u(26); y: hs.u(26)
            width: hs.u(84); height: width
            source: hs.sel ? hs.sel.icon : ""
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: hs.u(26) }
            spacing: hs.u(6)
            Text {
                width: parent.width
                text: hs.sel ? hs.sel.name : ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: "#ffffff"
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: hs.u(28)
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: hs.sel ? hs.sel.desc : ""
                elide: Text.ElideRight
                color: C.alpha("#ffffff", 0.72)
                font.family: Tokens.font.ui
                font.pixelSize: hs.u(14)
            }
            Item { width: 1; height: hs.u(10) }
            Rectangle {
                width: goRow.implicitWidth + hs.u(40)
                height: hs.u(44)
                radius: height / 2
                color: "#f3f6fb"
                Row {
                    id: goRow
                    anchors.centerIn: parent
                    spacing: hs.u(8)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "keyboard_return"; color: "#0a0d13"; font.family: Tokens.font.icons; font.pixelSize: hs.u(20) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Open"; color: "#0a0d13"; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: hs.u(15) }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: hs.launcher.activateSelection() }
            }
        }
    }

    // ---- every match, by kind
    ListView {
        id: list
        anchors { left: card.right; leftMargin: hs.u(22); right: parent.right; top: parent.top; bottom: parent.bottom }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: hs.runner
        spacing: 0
        opacity: hs.launcher.searching ? 0.6 : 1
        Behavior on opacity { NumberAnimation { duration: Tokens.base } }
        delegate: Column {
            id: group
            required property int index
            required property var model
            readonly property var matches: hs.runner.modelForRow(index)
            width: list.width
            visible: rows.count > 0
            height: visible ? implicitHeight : 0
            Text {
                text: String(group.matches ? group.matches.name : "").toUpperCase()
                leftPadding: hs.u(14)
                topPadding: hs.u(12)
                bottomPadding: hs.u(6)
                color: hs.rice.muted
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: hs.u(12)
                font.letterSpacing: hs.u(1)
            }
            Repeater {
                id: rows
                model: group.matches
                delegate: Rectangle {
                    id: match
                    required property int index
                    required property var model
                    readonly property bool selected: hs.launcher.selGroup === group.index && hs.launcher.selRow === index
                    width: group.width
                    height: hs.u(54)
                    radius: hs.u(16)
                    color: selected ? C.alpha(hs.rice.fg, 0.1) : mm.containsMouse ? C.alpha(hs.rice.fg, 0.05) : "transparent"
                    border.width: selected ? Math.max(1.5, hs.u(1.5)) : 0
                    border.color: C.alpha(hs.rice.light ? hs.rice.fg : "#ffffff", 0.6)
                    function publish() { hs.sel = { name: String(match.model.display || ""), desc: String(match.model.description || group.matches.name || ""), icon: match.model.decoration } }
                    onSelectedChanged: if (selected) publish()
                    Component.onCompleted: if (selected) publish()
                    Row {
                        anchors { left: parent.left; leftMargin: hs.u(14); verticalCenter: parent.verticalCenter }
                        spacing: hs.u(14)
                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: hs.u(34); height: width
                            source: match.model.decoration
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: match.width - hs.u(80)
                            Text {
                                width: parent.width
                                text: match.model.display
                                elide: Text.ElideRight
                                color: hs.rice.fg
                                font.family: Tokens.font.ui
                                font.weight: Font.DemiBold
                                font.pixelSize: hs.u(15.5)
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: match.model.description || ""
                                elide: Text.ElideRight
                                color: hs.rice.fgDim
                                font.family: Tokens.font.ui
                                font.pixelSize: hs.u(13)
                            }
                        }
                    }
                    MouseArea {
                        id: mm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: if (!match.selected) { hs.launcher.selGroup = group.index; hs.launcher.selRow = match.index }
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) hs.launcher.menu.openFor(match, group.matches, match.index)
                            else hs.launcher.launch(group.matches, match.index)
                        }
                    }
                }
            }
        }
    }

    // ---- nothing (once KRunner is done looking)
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: hs.u(80)
        spacing: hs.u(12)
        visible: !hs.hasResults && !hs.launcher.searching && hs.launcher.query !== ""
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "search_off"; color: C.alpha(hs.rice.fg, 0.35); font.family: Tokens.font.icons; font.pixelSize: hs.u(44) }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing for “" + hs.launcher.query + "”"; color: hs.rice.muted; font.family: Tokens.font.ui; font.pixelSize: hs.u(16) }
    }
}
