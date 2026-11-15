import QtQuick
import QtQuick.Effects
import Rice

// "Save this look", named where it sits: a card at the tile with a short name already in the field (the
// day's date: a controller can save it as it is), selected so typing replaces it. Enter saves, Esc doesn't.
// Names stay short (10 characters, rice.py's rule).
FocusScope {
    id: nc
    required property RicePalette rice
    required property var model             // ThemeModel
    property real unit: 1
    function u(n) { return Math.round(n * unit) }
    property Item anchorItem: null
    property bool open: false
    signal closed()

    function openAt(tile, suggestion) {
        field.text = suggestion || ""
        anchorItem = tile
        open = true
        place()
        field.forceActiveFocus()
        field.selectAll()
    }
    function save() { if (!open) return; const n = field.text.trim(); open = false; if (n) model.savePreset(n); closed() }
    function cancel() { if (!open) return; open = false; closed() }
    function place() {
        if (!anchorItem) return
        const p = anchorItem.mapToItem(nc, 0, 0)
        card.x = Math.max(u(24), Math.min(nc.width - card.width - u(24), p.x + anchorItem.width / 2 - card.width / 2))
        const above = p.y - card.height - u(26)
        card.y = above >= u(70) ? above : p.y + anchorItem.height + u(26)
    }

    Rectangle {     // a quiet scrim: the page steps back while the card is out
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.32)
        opacity: nc.open ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(220) } }
    }
    MouseArea { anchors.fill: parent; enabled: nc.open; hoverEnabled: true; onClicked: nc.cancel() }
    Item {
        id: card
        width: nc.u(420)
        height: col.implicitHeight + 2 * nc.u(22)
        visible: opacity > 0.01
        opacity: nc.open ? 1 : 0
        scale: nc.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Tokens.ms(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on scale { NumberAnimation { duration: Tokens.ms(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        RectangularShadow { anchors.fill: parent; radius: nc.u(26); blur: nc.u(44); offset.y: nc.u(16); spread: -nc.u(10); color: Qt.rgba(0, 0, 0, 0.5) }
        Rectangle { anchors.fill: parent; radius: nc.u(26); color: C.alpha(nc.rice.surfaceLowest, 0.94); border.width: 1; border.color: C.alpha(nc.rice.edge, 0.16) }
        MouseArea { anchors.fill: parent; hoverEnabled: true }
        Column {
            id: col
            x: nc.u(22); y: nc.u(22)
            width: card.width - 2 * nc.u(22)
            spacing: nc.u(14)
            Text { text: "Save this look"; color: nc.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: nc.u(18) }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Every screen's wallpaper and colours, under a short name."
                color: nc.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: nc.u(14)
            }
            Rectangle {
                width: parent.width
                height: nc.u(48)
                radius: height / 2
                color: C.alpha(nc.rice.fg, 0.08)
                border.width: Math.max(1.5, nc.u(1.5))
                border.color: C.alpha(nc.rice.primary, field.activeFocus ? 0.9 : 0.3)
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: nc.u(20); rightMargin: nc.u(20) }
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 10
                    color: nc.rice.fg
                    selectionColor: nc.rice.primary
                    selectedTextColor: nc.rice.onPrimary
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: nc.u(18)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { nc.save(); e.accepted = true }
                        else if (e.key === Qt.Key_Escape) { nc.cancel(); e.accepted = true }
                        else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab || e.key === Qt.Key_Up || e.key === Qt.Key_Down || e.key === Qt.Key_Menu) e.accepted = true
                    }
                }
                Text { anchors { right: parent.right; rightMargin: nc.u(18); verticalCenter: parent.verticalCenter }
                       text: field.text.length + "/10"; color: nc.rice.muted; font.family: Tokens.font.ui; font.pixelSize: nc.u(13) }
            }
            Row {
                anchors.right: parent.right
                spacing: nc.u(10)
                Rectangle {
                    height: nc.u(40); width: cr.implicitWidth + nc.u(32); radius: height / 2
                    color: C.alpha(nc.rice.fg, cm.containsMouse ? 0.16 : 0.09)
                    border.width: 1; border.color: C.alpha(nc.rice.edge, 0.14)
                    Text { id: cr; anchors.centerIn: parent; text: "Cancel"; color: nc.rice.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: nc.u(15) }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.cancel() }
                }
                Rectangle {
                    height: nc.u(40); width: sr.implicitWidth + nc.u(32); radius: height / 2
                    color: nc.rice.light ? nc.rice.fg : "#f3f6fb"
                    opacity: field.text.trim() ? 1 : 0.5
                    Row {
                        id: sr
                        anchors.centerIn: parent
                        spacing: nc.u(8)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "bookmark_add"; color: "#0a0d13"; font.family: Tokens.font.icons; font.pixelSize: nc.u(19) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Save"; color: "#0a0d13"; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: nc.u(15) }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nc.save() }
                }
            }
        }
    }
}
