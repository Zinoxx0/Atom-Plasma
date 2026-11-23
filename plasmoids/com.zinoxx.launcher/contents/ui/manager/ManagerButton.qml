import QtQuick
import QtCore
import Atom
import Rice

// The launcher's way into Atom Manager, at the bottom right (both styles): a round glass gear, an accent dot on it
// while an update waits, and a "Critical update!" banner beside it while a security fix waits (rice.py manager
// leaves that state in ~/.cache/rice/manager-status.json; the updater will keep it fresh). The keys' and the pad's
// way to it (F1, View) shows beside it only while that input is the one in use (glyph: "F1" or "⧉", "" for none).
Item {
    id: mb
    required property RicePalette look
    required property real unit
    property string glyph: ""
    signal open(string section)
    function d(px) { return px * unit / 0.836 }
    readonly property string home: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    WatchedJson { id: st; path: mb.home + "/.cache/rice/manager-status.json" }
    readonly property bool available: !!(st.value && st.value.available)
    readonly property bool critical: !!(st.value && st.value.critical)
    width: row.width
    height: mb.d(52)

    Row {
        id: row
        anchors.right: parent.right
        height: parent.height
        spacing: mb.d(12)
        Rectangle {         // the banner: a security fix is waiting
            visible: mb.critical
            anchors.verticalCenter: parent.verticalCenter
            height: mb.d(40); width: bRow.width + mb.d(30); radius: height / 2
            color: C.alpha(mb.look.bad, bm.containsMouse ? 0.34 : 0.24)
            border.width: Math.max(1, mb.d(1.5)); border.color: C.alpha(mb.look.bad, 0.7)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Row {
                id: bRow
                anchors.centerIn: parent
                spacing: mb.d(8)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "gpp_maybe"; color: mb.look.bad; font.family: Tokens.font.icons; font.pixelSize: mb.d(21) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Critical update!"; color: mb.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: mb.d(15.5) }
            }
            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.open("updates") }
        }
        Rectangle {         // the key or the pad's button that opens it too
            visible: mb.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, gt.implicitWidth + mb.d(12)); height: mb.d(26); radius: mb.glyph.length === 1 ? height / 2 : mb.d(8)
            color: "transparent"; border.width: Math.max(1, mb.d(1.5)); border.color: C.alpha(mb.look.fg, 0.34)
            Text { id: gt; anchors.centerIn: parent; text: mb.glyph; color: mb.look.fgDim; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: mb.d(12.5) }
        }
        Item {
            width: mb.d(52); height: width
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: C.alpha(gm.containsMouse ? mb.look.fg : mb.look.surfaceLowest, gm.containsMouse ? 0.14 : 0.38)
                border.width: 1; border.color: C.alpha(mb.look.fg, 0.10)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Text {
                anchors.centerIn: parent
                text: "settings"; color: mb.look.fg
                font.family: Tokens.font.icons; font.pixelSize: mb.d(25)
                rotation: gm.containsMouse ? 60 : 0
                Behavior on rotation { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            }
            Rectangle {     // an update waits
                visible: mb.available
                x: parent.width - width - mb.d(3); y: mb.d(3)
                width: mb.d(13); height: width; radius: width / 2
                color: mb.critical ? mb.look.bad : mb.look.primary
                border.width: Math.max(1, mb.d(2)); border.color: mb.look.surfaceLowest
            }
            MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.open(mb.critical ? "updates" : "") }
        }
    }
}
