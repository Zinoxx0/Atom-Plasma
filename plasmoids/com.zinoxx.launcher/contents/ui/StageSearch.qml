import QtQuick
import QtQuick.Effects
import Rice

// The launcher's search (Stage): the magnifier in the top bar opens into a field, the results come down
// under it; in the finder (search only, over whatever is on the screen) the field is all there is.
// query: the field (the stage opens, fills and clears it); finderCard: the finder's plate (KWin blurs it).
Item {
    id: searchLayer
    required property var stage             // the Stage (Window)
    readonly property Item query: queryField
    readonly property Item finderCard: finderPlate
    anchors.fill: parent
    visible: searchLayer.stage.searchP > 0.001
    readonly property rect from: {
        searchLayer.stage.planeO
        if (searchLayer.stage.finder) { const t = to; return Qt.rect(t.x + t.width * 0.08, t.y - searchLayer.stage.u(10), t.width * 0.84, t.height) }
        const p = searchLayer.stage.searchButton.mapToItem(searchLayer, 0, 0)
        return Qt.rect(p.x, p.y, searchLayer.stage.searchButton.width, searchLayer.stage.searchButton.height)
    }
    readonly property rect to: {
        const w = Math.min(searchLayer.stage.u(760), searchLayer.stage.width * 0.62), h = searchLayer.stage.u(60)
        return Qt.rect((searchLayer.stage.width - w) / 2, searchLayer.stage.u(30) + searchLayer.stage.u(23) - h / 2, w, h)
    }
    MouseArea { anchors.fill: parent; enabled: searchLayer.stage.searchOpen; onClicked: searchLayer.stage.closeSearch() }
    // the finder's card: the field and the results on one glass plate, blurred behind (only the
    // plate: the screen around it stays as it is). It's the field's size until results come, then
    // grows with them.
    RectangularShadow {
        anchors.fill: finderPlate
        visible: finderPlate.visible
        opacity: finderPlate.opacity
        radius: finderPlate.radius; blur: searchLayer.stage.u(44); offset.y: searchLayer.stage.u(16); spread: -searchLayer.stage.u(10)
        color: Qt.rgba(0, 0, 0, 0.5)
    }
    Rectangle {
        id: finderPlate
        visible: searchLayer.stage.finder && searchLayer.stage.searchP > 0.001
        opacity: Math.min(1, searchLayer.stage.searchP * 1.6)
        readonly property real pad: searchLayer.stage.u(18)
        readonly property real k: results.contentH > 0 ? results.opacity : 0      // the results' share
        property real resB: results.y + results.height      // (results coming in stretch it smoothly)
        Behavior on resB { NumberAnimation { duration: Tokens.ms(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove } }
        x: Math.min(field.x, M.lerp(field.x, results.x, k)) - pad
        y: field.y - pad
        width: Math.max(field.x + field.width, M.lerp(field.x + field.width, results.x + results.width, k)) + pad - x
        height: Math.max(field.y + field.height, M.lerp(field.y + field.height, resB, k)) + pad - y
        radius: Math.min(searchLayer.stage.u(34), height / 2)
        color: C.alpha(searchLayer.stage.rice.surfaceLowest, 0.82)
        border.width: 1
        border.color: C.alpha(searchLayer.stage.rice.edge, 0.14)
        MouseArea { anchors.fill: parent }     // a click on the plate isn't a click outside
    }

    Rectangle {
        id: field
        x: M.lerp(searchLayer.from.x, searchLayer.to.x, searchLayer.stage.searchP)
        y: M.lerp(searchLayer.from.y, searchLayer.to.y, searchLayer.stage.searchP)
        width: M.lerp(searchLayer.from.width, searchLayer.to.width, searchLayer.stage.searchP)
        height: M.lerp(searchLayer.from.height, searchLayer.to.height, searchLayer.stage.searchP)
        radius: height / 2
        opacity: Math.min(1, searchLayer.stage.searchP * 3)
        color: C.alpha(searchLayer.stage.rice.surfaceLowest, 0.74)
        border.width: 1
        border.color: C.alpha(searchLayer.stage.rice.edge, 0.14)
        MouseArea { anchors.fill: parent; onClicked: queryField.forceActiveFocus() }
        Text {
            id: lens
            x: searchLayer.stage.u(22)
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            color: searchLayer.stage.rice.primary
            font.family: Tokens.font.icons
            font.pixelSize: searchLayer.stage.u(26)
        }
        TextInput {
            id: queryField
            anchors { left: lens.right; leftMargin: searchLayer.stage.u(14); right: busy.left; rightMargin: searchLayer.stage.u(12); top: parent.top; bottom: parent.bottom }
            verticalAlignment: TextInput.AlignVCenter
            opacity: M.clamp((searchLayer.stage.searchP - 0.45) / 0.55)
            color: searchLayer.stage.rice.fg
            selectionColor: searchLayer.stage.rice.primary
            selectedTextColor: searchLayer.stage.rice.onPrimary
            font.family: Tokens.font.ui
            font.pixelSize: searchLayer.stage.u(21)
            clip: true
            onTextChanged: searchLayer.stage.launcher.query = text
            Keys.onPressed: event => searchLayer.stage.onSearchKey(event)
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !queryField.text && !queryField.preeditText
                text: "Search apps, games, settings, files… or do maths"
                color: searchLayer.stage.rice.muted
                font: queryField.font
                elide: Text.ElideRight
            }
        }
        Busy {
            id: busy
            anchors { right: parent.right; rightMargin: searchLayer.stage.u(20); verticalCenter: parent.verticalCenter }
            visible: searchLayer.stage.launcher.searching
            running: visible
            implicitWidth: searchLayer.stage.u(18); implicitHeight: implicitWidth
            color: searchLayer.stage.rice.primary
        }
    }
    HomeSearch {
        id: results
        x: (searchLayer.stage.width - width) / 2
        y: searchLayer.stage.u(132) + (1 - opacity) * -searchLayer.stage.u(14)
        width: Math.min(searchLayer.stage.u(1120), searchLayer.stage.width * 0.9)
        // the finder's results take what they need (at most the rest of the screen)
        height: searchLayer.stage.finder ? Math.min(searchLayer.stage.height - y - searchLayer.stage.u(50), Math.max(searchLayer.stage.u(120), contentH))
                             : searchLayer.stage.height - y - searchLayer.stage.u(50)
        launcher: searchLayer.stage.launcher
        rice: searchLayer.stage.rice
        unit: searchLayer.stage.unit
        opacity: searchLayer.stage.launcher.query !== "" ? M.clamp((searchLayer.stage.searchP - 0.3) / 0.7) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    }
}
