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

// The launcher with no query: pinned apps, the category chips and the app grid (whole columns, centred).
ColumnLayout {
    id: browse
    required property var launcher
    required property RicePalette rice
    required property var menu               // the right-click menu (pin, the app's actions)
    required property var kickerDrag         // Kicker's DragHelper: apps dragged onto the bar
    required property Item searchField        // typing on the grid goes there
    readonly property alias gridView: grid
    readonly property alias pinnedView: pinned

    spacing: Tokens.space.sm

    SectionHeader {
        visible: pinned.count > 0
        palette: rice
        text: "Pinned"
        Layout.leftMargin: Tokens.space.xxs
    }
    ListView {
        id: pinned
        Layout.fillWidth: true
        implicitHeight: count ? launcher.px(92) : 0
        orientation: ListView.Horizontal
        spacing: Tokens.space.sm
        clip: true
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        model: launcher.favorites
        // overflowing: soft edges where there's more, scroll with the wheel too
        layer.enabled: contentWidth > width
        layer.effect: EdgeFade { view: pinned }
        WheelHandler {
            enabled: pinned.interactive
            onWheel: event => pinned.flick((event.angleDelta.y || event.angleDelta.x) * 8, 0)
        }
        // keyboard: Tab in, arrows along the row, Enter to open
        activeFocusOnTab: count > 0
        keyNavigationEnabled: true
        currentIndex: -1
        highlightFollowsCurrentItem: false
        onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
        Keys.onReturnPressed: if (currentIndex >= 0) launcher.launch(launcher.favorites, currentIndex)
        Keys.onEnterPressed: if (currentIndex >= 0) launcher.launch(launcher.favorites, currentIndex)
        Keys.onEscapePressed: launcher.expanded = false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
            id: pin
            required property int index
            required property var model
            readonly property color tint: C.appTint(pinColors, rice.primary)
            readonly property bool focused: ListView.isCurrentItem && pinned.activeFocus
            readonly property bool hot: pm.containsMouse || focused
            Kirigami.ImageColors { id: pinColors; source: pin.model.decoration }
            width: launcher.px(88)
            height: pinned.height

            Rectangle {
                id: pinCard
                anchors.fill: parent
                radius: Tokens.radius.md
                color: C.alpha(pin.tint, pm.pressed ? 0.22 : pin.hot ? 0.14 : 0.06)
                border.width: 1
                border.color: C.alpha(pin.tint, pin.hot ? 0.65 : 0.22)
                // the app's colour, lighting the card from under its icon (as in the top band)
                AppGlow {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: launcher.px(30) - height / 2
                    width: parent.width * 1.05
                    flat: 0.72
                    tint: pin.tint
                    strength: (pin.hot ? 0.5 : 0.28) * Math.max(0.3, rice.glow)
                    Behavior on strength { NumberAnimation { duration: Tokens.base } }
                }
                // pressed dips; hover grows the icon, not the card (the row clips)
                scale: pm.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                Column {
                    anchors.centerIn: parent
                    spacing: Tokens.space.xs + 2
                    Kirigami.Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: launcher.px(40); height: width
                        source: pin.model.decoration
                        scale: pin.hot ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: pin.width - Tokens.space.sm
                        horizontalAlignment: Text.AlignHCenter
                        text: pin.model.display
                        elide: Text.ElideRight
                        color: rice.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: launcher.px(Tokens.size.small)
                    }
                }
            }
            FocusRing { ink: rice.edge; radius: pinCard.radius; shown: pin.focused; gap: 1 }
            MouseArea {
                id: pm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) menu.openFor(pin, launcher.favorites, pin.index)
                    else launcher.launch(launcher.favorites, pin.index)
                }
            }
        }
    }

    // category chips
    ListView {
        id: chips
        objectName: "categoryChips"
        Layout.fillWidth: true
        Layout.topMargin: Tokens.space.xs
        implicitHeight: launcher.px(30) + 6       // room for the focus ring
        orientation: ListView.Horizontal
        spacing: Tokens.space.xs + 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: launcher.categories
        layer.enabled: contentWidth > width
        layer.effect: EdgeFade { view: chips }
        WheelHandler {
            enabled: chips.contentWidth > chips.width
            onWheel: event => chips.flick((event.angleDelta.y || event.angleDelta.x) * 8, 0)
        }
        delegate: Item {
            id: chipCell
            required property int index
            required property var modelData
            readonly property alias chipItem: chip
            function step(d) {
                const next = chips.itemAtIndex(index + d)
                if (next) next.chipItem.forceActiveFocus(Qt.TabFocusReason)
            }
            width: chip.width
            height: chips.height
            Chip {
                id: chip
                anchors.verticalCenter: parent.verticalCenter
                palette: rice
                interactive: true
                size: launcher.px(30)
                icon: chipCell.modelData.icon
                text: chipCell.modelData.label
                tint: rice.primary
                selected: launcher.category === chipCell.index
                bold: selected
                onActiveFocusChanged: if (activeFocus) chips.positionViewAtIndex(chipCell.index, ListView.Contain)
                Keys.onLeftPressed: chipCell.step(-1)
                Keys.onRightPressed: chipCell.step(1)
                onClicked: { launcher.category = chipCell.index; grid.currentIndex = -1; grid.positionViewAtBeginning() }
            }
        }
    }

    // app grid: whole columns, centred. The view is exactly its columns wide inside a box
    // that fills the room: a cell width that follows the view's own width, plus a centring
    // margin, left GridView counting too few columns (3 of 6) and never counting again.
    Item {
    id: gridBox
    Layout.fillWidth: true
    Layout.fillHeight: true
    GridView {
        id: grid
        objectName: "appGrid"
        readonly property int columns: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: columns * cellWidth
        height: parent.height
        clip: true
        cellWidth: Math.floor(gridBox.width / columns)
        cellHeight: launcher.px(100)
        model: launcher.browseModel
        currentIndex: -1
        keyNavigationEnabled: true
        activeFocusOnTab: true
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        // a slim scroll pip, quiet until the grid moves or is hovered
        Rectangle {
            parent: grid
            anchors.right: parent.right
            y: grid.visibleArea.yPosition * grid.height
            width: 4
            height: Math.max(24, grid.visibleArea.heightRatio * grid.height)
            radius: 2
            color: C.alpha(rice.fg, 0.3)
            visible: grid.contentHeight > grid.height + 1
            opacity: grid.moving || gridHover.hovered ? 1 : 0.35
            Behavior on opacity { NumberAnimation { duration: Tokens.base } }
        }
        HoverHandler { id: gridHover }
        onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
        // swap categories with a soft fade
        onModelChanged: { opacity = 0; fadeIn.restart() }
        NumberAnimation { id: fadeIn; target: grid; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (currentIndex >= 0) launcher.launch(launcher.browseModel, currentIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                launcher.expanded = false
                event.accepted = true
            } else if (event.key === Qt.Key_Up && currentIndex < columns) {
                searchField.forceActiveFocus()
                event.accepted = true
            } else if (event.text && event.text.trim() && !(event.modifiers & Qt.ControlModifier)) {
                searchField.text += event.text          // typing on the grid searches
                searchField.cursorPosition = searchField.text.length
                searchField.forceActiveFocus()
                event.accepted = true
            }
        }

        delegate: Item {
            id: app
            required property int index
            required property var model
            readonly property bool current: GridView.isCurrentItem && grid.activeFocus
            readonly property bool hot: am.containsMouse || current
            readonly property color tint: C.appTint(appColors, rice.primary)
            Kirigami.ImageColors { id: appColors; source: app.model.decoration }
            width: grid.cellWidth
            height: grid.cellHeight

            // on open, the first rows fade up in a quick ripple
            transform: Translate { id: appRise }
            SequentialAnimation {
                id: appIn
                PropertyAction { target: app; property: "opacity"; value: 0 }
                PropertyAction { target: appRise; property: "y"; value: 8 }
                PauseAnimation { duration: Tokens.ms(80 + app.index * 12) }
                ParallelAnimation {
                    NumberAnimation { target: app; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                    NumberAnimation { target: appRise; property: "y"; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
                }
            }
            Connections {
                target: pop
                function onEntered() { if (app.index < 24 && Tokens.speed > 0) appIn.restart() }
            }

            Rectangle {
                id: appCard
                anchors.fill: parent
                anchors.margins: Tokens.space.xs
                radius: Tokens.radius.md
                color: C.alpha(app.tint, am.pressed ? 0.24 : app.hot ? 0.16 : 0)
                border.width: 1
                border.color: C.alpha(app.tint, app.hot ? 0.40 : 0)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
            }
            FocusRing { ink: rice.edge; radius: appCard.radius; target: appCard; shown: app.current; gap: 1 }
            Column {
                anchors.centerIn: parent
                spacing: Tokens.space.sm
                scale: am.pressed ? 0.95 : app.hot ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                Kirigami.Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: launcher.px(42); height: width
                    source: app.model.decoration
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: grid.cellWidth - Tokens.space.md - 2
                    horizontalAlignment: Text.AlignHCenter
                    text: app.model.display
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 0.92
                    color: rice.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.Medium
                    font.pixelSize: launcher.px(Tokens.size.small)
                }
            }
            MouseArea {
                id: am
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property point pressAt
                onPressed: mouse => pressAt = Qt.point(mouse.x, mouse.y)
                onPositionChanged: mouse => {      // drag an app onto the bar to pin it there
                    if (pressed && app.model.url && kickerDrag.isDrag(pressAt.x, pressAt.y, mouse.x, mouse.y))
                        kickerDrag.startDrag(launcher, app.model.url)
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) menu.openFor(app, launcher.browseModel, app.index)
                    else launcher.launch(launcher.browseModel, app.index)
                }
            }
        }
    }
}
}
