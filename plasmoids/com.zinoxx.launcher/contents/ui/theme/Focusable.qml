import QtQuick

// A part of the Theme page the focus can rest on: it registers with the page (ThemeStudio walks every registered
// part spatially with the keys and a pad's D-pad) and the page's one lens goes round it, or round lensItem. The
// pointer takes the focus where it rests (only when it really moved: ThemeStudio.pointed) and a click activates.
//   region   a part that walks itself (the wallpaper grid): step(dx, dy), enterFrom(rect), lensRect(), current()
//   slider   left and right nudge it instead of moving the focus
Item {
    id: f
    required property Item studio
    property string fkey: ""
    property string desc: ""            // the footer's line (styled text: "<b>Name</b> what it does")
    property string act: "Choose"       // what A does, for the hints
    property Item lensItem: f
    property real lensRadius: studio.d(12)
    property real lensGap: studio.d(6)
    property bool slider: false
    property bool rail: false           // a section in the side column (left from the content lands there)
    property bool inSide: false         // in the side column
    property bool region: false
    property bool mouse: true           // its own hover and click (a region's parts have theirs)
    property string tag: ""             // a name the lens shows (a wallpaper's)
    readonly property bool focused: studio.focused === f && studio.active
    readonly property bool hovered: hover.containsMouse
    signal activated()
    signal nudged(int dx)
    signal menu()
    Component.onCompleted: studio.reg(f)
    Component.onDestruction: studio.unreg(f)
    MouseArea {
        id: hover
        anchors.fill: parent
        enabled: f.mouse
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: f.studio.pointed(f)
        onPositionChanged: f.studio.pointed(f)
        onClicked: m => { if (m.button === Qt.RightButton) f.menu(); else f.studio.clicked(f) }
    }
}
