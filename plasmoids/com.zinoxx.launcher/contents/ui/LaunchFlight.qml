import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// Launching from the launcher (Stage): the tile grows into the whole screen (a game's cover becomes its
// banner, an app's icon sits on its own colour) and the launcher closes once it's there.
// fly(item, from): from = the tile's rect in the window. The stage fades it with the rest as it closes.
Item {
    id: launchFly
    required property var stage             // the Stage (Window)
    function fly(it, rect) {
        launchFly.item = it
        launchFly.from = rect
        launchFly.p = 0
        launchFly.opacity = 1
        launchFly.visible = true
        launchGrow.restart()
    }
    visible: false
    property rect from: Qt.rect(0, 0, 0, 0)
    property var item: null
    property real p: 0
    readonly property bool art: !!(item && item.art && item.art.hero)
    x: M.lerp(from.x, 0, p)
    y: M.lerp(from.y, 0, p)
    width: M.lerp(from.width, launchFly.stage.width, p)
    height: M.lerp(from.height, launchFly.stage.height, p)
    layer.enabled: visible
    layer.effect: MultiEffect { maskEnabled: true; maskSource: flyMask }
    Rectangle {
        anchors.fill: parent
        color: launchFly.art ? "#000000" : C.mix(flyColors.c, "#0b0f16", 0.5)
        QtObject { id: flyColors; readonly property color c: C.appTint(flyIc, launchFly.stage.rice.primary) }
        Kirigami.ImageColors { id: flyIc; source: launchFly.item ? launchFly.item.icon : "" }
    }
    Image {
        anchors.fill: parent
        visible: launchFly.art
        source: launchFly.art ? launchFly.item.art.hero : ""
        fillMode: Image.PreserveAspectCrop
    }
    Image {
        anchors.fill: parent
        visible: !!(launchFly.item && launchFly.item.art && launchFly.item.art.portrait)
        source: visible ? launchFly.item.art.portrait : ""
        fillMode: Image.PreserveAspectCrop
        opacity: 1 - Math.min(1, launchFly.p * 1.8)
    }
    Kirigami.Icon {
        visible: !launchFly.art
        anchors.centerIn: parent
        width: M.lerp(Math.min(launchFly.from.width, launchFly.from.height) * 0.56, Math.min(launchFly.stage.width, launchFly.stage.height) * 0.22, launchFly.p)
        height: width
        source: launchFly.item ? launchFly.item.icon : ""
    }
    NumberAnimation on p { id: launchGrow; running: false; from: 0; to: 1; duration: Tokens.ms(620); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmMove; onFinished: launchFly.stage.launcher.close() }
    Rectangle { id: flyMask; width: launchFly.width; height: launchFly.height; radius: M.lerp(launchFly.stage.u(22), 0, launchFly.p); visible: false; layer.enabled: true }
}
