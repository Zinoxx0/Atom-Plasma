import QtQuick
import Atom
import Rice

// A block's caption on the Theme page: its name in small capitals, then a note in plain words.
Row {
    id: cap
    required property Item studio
    property string text: ""
    property string note: ""
    spacing: studio.d(14)
    height: studio.d(34)
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: cap.text.toUpperCase()
        color: cap.studio.look.fgDim
        font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: cap.studio.d(13); font.letterSpacing: cap.studio.d(1.2)
    }
    Text {
        visible: cap.note !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: cap.note
        color: cap.studio.look.fgDim
        font.family: Tokens.font.ui; font.pixelSize: cap.studio.d(14.5)
    }
}
