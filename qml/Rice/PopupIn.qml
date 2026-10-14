import QtQuick

// Wraps a popup's content and brings it in when the popup opens: a fade and a 6 px rise,
// no overshoot. Anchor it like the content it holds.
//
//   PopupIn { anchors.fill: parent; active: root.expanded; ColumnLayout { ... } }
Item {
    id: pin
    property bool active: false             // bind to the applet's `expanded`
    property real rise: 6
    default property alias content: body.data

    Item {
        id: body
        anchors.fill: parent
        transform: Translate { id: lift }
    }
    function play() {
        if (Tokens.speed <= 0) { body.opacity = 1; lift.y = 0; return }
        anim.restart();
    }
    ParallelAnimation {
        id: anim
        NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
        NumberAnimation { target: lift; property: "y"; from: pin.rise; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
    }
    onActiveChanged: if (active) play()
    Component.onCompleted: if (active) play()
}
