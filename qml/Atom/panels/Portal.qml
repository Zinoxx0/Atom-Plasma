import QtQuick
import Atom
import "../../Rice"

// A bar widget's own popup on the shell's sheet: the widget registered its content (Shell.portal) and it
// is made here, in the widget's context, so it keeps reading the widget's data (system stats, Claude's
// usage). Sized by the content's implicit size; gone with the panel.
FocusScope {
    id: portal
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property Component content: Shell.portals[screenName + "/" + kind] || null
    property Item hosted: null
    implicitWidth: hosted ? hosted.implicitWidth : 0
    implicitHeight: hosted ? hosted.implicitHeight : 0
    Item { id: holder; anchors.fill: parent }
    Component.onCompleted: if (content) hosted = content.createObject(holder, { width: Qt.binding(() => holder.width) })
    Component.onDestruction: if (hosted) hosted.destroy()
    function enter() { forceActiveFocus() }
}
