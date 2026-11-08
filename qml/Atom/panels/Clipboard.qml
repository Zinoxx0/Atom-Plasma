import QtQuick
import QtQuick.Layouts
import Atom
import "../../Rice"
import "../../Rice/Color.js" as C

// The clipboard's history (Meta+V; Klipper, kept alive by Atom Notify): a search field and what you
// copied lately. A click (or Enter on the first match) makes an entry the clipboard again; the cross
// forgets it. Esc closes.
FocusScope {
    id: cb
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette
    function u(n) { return Math.round(n * ui) }
    readonly property var history: Notify.clipboard

    implicitWidth: u(420)
    implicitHeight: col.implicitHeight
    function enter() { search.text = ""; search.forceActiveFocus() }
    function matches(t) { return !search.text || String(t).toLowerCase().indexOf(search.text.toLowerCase()) >= 0 }
    function take(uuid) { history.moveToTop(uuid); Shell.close() }

    ColumnLayout {
        id: col
        width: cb.width
        spacing: cb.u(10)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cb.u(44)
            radius: height / 2
            color: C.alpha(cb.pal.fg, 0.06)
            border.width: 1
            border.color: search.activeFocus ? C.alpha(cb.pal.primary, 0.7) : C.alpha(cb.pal.edge, Tokens.alpha.outline)
            Text {
                id: lens
                x: cb.u(16)
                anchors.verticalCenter: parent.verticalCenter
                text: "content_paste_search"
                color: cb.pal.primary
                font.family: Tokens.font.icons
                font.pixelSize: cb.u(20)
            }
            TextInput {
                id: search
                anchors { left: lens.right; leftMargin: cb.u(10); right: parent.right; rightMargin: cb.u(16); top: parent.top; bottom: parent.bottom }
                verticalAlignment: TextInput.AlignVCenter
                color: cb.pal.fg
                font.family: Tokens.font.ui
                font.pixelSize: cb.u(14)
                focus: true
                Keys.onReturnPressed: {
                    for (let i = 0; i < list.count; i++) { const it = list.itemAtIndex(i); if (it && it.shown) { cb.take(it.uuid); return } }
                }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !search.text
                    text: "Search what you copied"
                    color: cb.pal.muted
                    font: search.font
                }
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, cb.u(440))
            clip: true
            spacing: cb.u(4)
            model: cb.history
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: entry
                required property var model
                required property int index
                readonly property string uuid: model.uuid || ""
                readonly property string text: String(model.display || "").trim()
                readonly property bool shown: cb.matches(text)
                width: list.width
                height: shown ? Math.max(cb.u(44), body.implicitHeight + cb.u(16)) : 0
                visible: shown
                radius: cb.u(12)
                color: em.containsMouse ? C.alpha(cb.pal.primary, 0.14) : index === 0 ? C.alpha(cb.pal.fg, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                Text {
                    id: kindGlyph
                    x: cb.u(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: /^(https?|file):\/\//.test(entry.text) ? "link" : entry.text === "" ? "image" : index === 0 ? "content_paste" : "notes"
                    color: index === 0 ? cb.pal.primary : cb.pal.fgDim
                    font.family: Tokens.font.icons
                    font.pixelSize: cb.u(18)
                }
                Text {
                    id: body
                    anchors { left: kindGlyph.right; leftMargin: cb.u(10); right: x.left; rightMargin: cb.u(6); verticalCenter: parent.verticalCenter }
                    text: entry.text || "(image)"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: cb.pal.fg
                    font.family: Tokens.font.ui
                    font.pixelSize: cb.u(13)
                }
                MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.take(entry.uuid) }
                Text {
                    id: x
                    anchors { right: parent.right; rightMargin: cb.u(10); verticalCenter: parent.verticalCenter }
                    text: "close"
                    opacity: em.containsMouse || xm.containsMouse ? 1 : 0
                    color: xm.containsMouse ? cb.pal.fg : cb.pal.muted
                    font.family: Tokens.font.icons
                    font.pixelSize: cb.u(16)
                    MouseArea { id: xm; anchors.fill: parent; anchors.margins: -cb.u(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.history.remove(entry.uuid) }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "Nothing copied yet"
                color: cb.pal.muted
                font.family: Tokens.font.ui
                font.pixelSize: cb.u(13)
            }
        }
        Text {
            Layout.alignment: Qt.AlignRight
            visible: list.count > 0
            text: "Clear history"
            color: clearM.containsMouse ? cb.pal.fg : cb.pal.primary
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: cb.u(11)
            MouseArea { id: clearM; anchors.fill: parent; anchors.margins: -cb.u(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.history.clearHistory() }
        }
    }
}
