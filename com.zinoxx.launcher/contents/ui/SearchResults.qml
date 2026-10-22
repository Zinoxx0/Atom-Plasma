import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import "Rice"
import "Rice/Color.js" as C

// The launcher with a query: KRunner's matches grouped by kind, with the keyboard selection, a breathing
// placeholder while results are on their way and a note when there are none.
Item {
    id: resultsArea
    required property var launcher
    required property RicePalette rice
    required property var menu
    required property var runnerModel        // Kicker's RunnerModel

    // empty groups collapse to nothing, so any height means something matched
    readonly property bool hasResults: results.contentHeight > 20

    ListView {
        id: results
        anchors.fill: parent
        clip: true
        spacing: 0
        boundsBehavior: Flickable.StopAtBounds
        model: runnerModel
        QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}
        // cross-fade: the old results dim while KRunner works, the new ones brighten in
        opacity: launcher.searching ? 0.55 : 1
        Behavior on opacity { NumberAnimation { duration: launcher.searching ? Tokens.fast : Tokens.base; easing.type: Tokens.enter } }
        delegate: Column {
            id: group
            required property int index
            required property var model
            readonly property var matches: runnerModel.modelForRow(index)
            width: results.width - Tokens.space.sm
            height: visible ? implicitHeight : 0
            spacing: Tokens.space.xs
            visible: list.count > 0
            topPadding: Tokens.space.xs + 2
            bottomPadding: Tokens.space.xs + 2
            SectionHeader {
                leftPadding: Tokens.space.sm
                palette: rice
                text: String(group.matches ? group.matches.name : "")
            }
            Repeater {
                id: list
                model: group.matches
                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var model
                    readonly property bool selected: launcher.selGroup === group.index && launcher.selRow === index
                    width: group.width
                    height: launcher.px(52)
                    radius: Tokens.radius.sm
                    color: selected ? C.alpha(rice.primary, rm.pressed ? 0.24 : 0.16)
                         : C.alpha(rice.fg, rm.pressed ? 0.10 : rm.containsMouse ? 0.06 : 0)
                    border.width: selected ? 1 : 0
                    border.color: C.alpha(rice.primary, 0.4)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    onSelectedChanged: if (selected) results.positionViewAtIndex(group.index, ListView.Contain)

                    // each row arrives with a short fade and rise, a few ms after the one above
                    opacity: 0
                    transform: Translate { id: rowRise; y: 6 }
                    SequentialAnimation {
                        id: rowIn
                        PauseAnimation { duration: Tokens.ms(Math.min(row.index, 6) * 20) }
                        ParallelAnimation {
                            NumberAnimation { target: row; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                            NumberAnimation { target: rowRise; property: "y"; to: 0; duration: Tokens.base; easing.type: Tokens.enter }
                        }
                    }
                    Component.onCompleted: {
                        if (Tokens.speed > 0) rowIn.start();
                        else { opacity = 1; rowRise.y = 0 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.space.md
                        anchors.rightMargin: Tokens.space.md
                        spacing: Tokens.space.md
                        Kirigami.Icon {
                            implicitWidth: launcher.px(32); implicitHeight: implicitWidth
                            source: row.model.decoration
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: row.model.display
                                elide: Text.ElideRight
                                color: rice.fg
                                font.family: Tokens.font.ui
                                font.weight: Font.DemiBold
                                font.pixelSize: launcher.px(Tokens.size.body)
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: row.model.description || ""
                                elide: Text.ElideRight
                                color: rice.muted
                                font.family: Tokens.font.ui
                                font.pixelSize: launcher.px(Tokens.size.small)
                            }
                        }
                        Chip {
                            visible: row.selected
                            palette: rice
                            text: "↵ open"
                            tint: rice.primary
                            size: 20
                        }
                    }
                    MouseArea {
                        id: rm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) menu.openFor(row, group.matches, row.index)
                            else launcher.launch(group.matches, row.index)
                        }
                    }
                }
            }
        }
    }

    // searching, nothing in yet: placeholder rows breathing (popup only, stops when done)
    Column {
        id: skeleton
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Tokens.space.sm }
        spacing: Tokens.space.sm
        visible: launcher.searching && !resultsArea.hasResults
        SectionHeader { leftPadding: Tokens.space.sm; palette: rice; text: "Searching…" }
        Repeater {
            model: 3
            Rectangle {
                id: skel
                required property int index
                width: skeleton.width - Tokens.space.sm
                height: launcher.px(52)
                radius: Tokens.radius.sm
                color: C.alpha(rice.fg, 0.05)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Tokens.space.md
                    spacing: Tokens.space.md
                    Rectangle { width: launcher.px(32); height: width; radius: Tokens.radius.xs; color: C.alpha(rice.fg, 0.07) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.space.xs + 2
                        Rectangle { width: launcher.px(180 - skel.index * 40); height: 9; radius: 4.5; color: C.alpha(rice.fg, 0.08) }
                        Rectangle { width: 110; height: 7; radius: 3.5; color: C.alpha(rice.fg, 0.05) }
                    }
                }
                SequentialAnimation on opacity {
                    running: skeleton.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: skel.index * 120 }
                    NumberAnimation { to: 0.45; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // nothing found
    ColumnLayout {
        anchors.centerIn: parent
        spacing: Tokens.space.sm
        visible: !launcher.searching && !resultsArea.hasResults
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "search_off"
            color: rice.muted
            font.family: Tokens.font.icons
            font.pixelSize: launcher.px(44)
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Nothing for “" + launcher.query + "”"
            color: rice.fg
            font.family: Tokens.font.display
            font.weight: Font.Bold
            font.pixelSize: launcher.px(Tokens.size.title)
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Try an app, a setting, a file name, or a sum like 12*7"
            color: rice.fgDim
            font.family: Tokens.font.ui
            font.pixelSize: launcher.px(Tokens.size.label)
        }
    }
                    }
