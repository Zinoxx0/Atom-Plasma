import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import Atom
import Rice

// The Theme page's desk map (Stage): the screens as they sit on the desk (the rice's DeskMap), the one
// being edited ringed, the one that themes the system starred, and what the focused item would put on each.
Rectangle {
    id: screensCard
    required property var stage             // the Stage (Window)
    required property var themeModel        // the Theme page's (ThemeModel)
    anchors.right: parent.right
    anchors.rightMargin: screensCard.stage.side
    y: screensCard.stage.heroTop + (screensCard.stage.theming ? 0 : -screensCard.stage.u(10))
    width: screensCard.stage.u(470)
    height: screensCard.stage.u(206)
    radius: screensCard.stage.u(26)
    visible: opacity > 0.01
    opacity: screensCard.stage.theming ? screensCard.stage.heroO : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.ms(380) } }
    Behavior on y { NumberAnimation { duration: Tokens.ms(480); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
    color: C.alpha(screensCard.stage.rice.surfaceLowest, 0.5)
    border.width: 1
    border.color: C.alpha(screensCard.stage.rice.edge, 0.1)
    DeskMap {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: capRow.top; margins: screensCard.stage.u(18) }
        pal: screensCard.stage.rice
        screens: screensCard.themeModel.screens
        focusName: screensCard.themeModel.target === "all" ? screensCard.stage.screenName : screensCard.themeModel.target
        linked: screensCard.themeModel.target === "all"
        preview: screensCard.stage.previewMap
        keyName: (screensCard.stage.focusRev, screensCard.stage.theming && screensCard.stage.pageState().line === "desk") ? screensCard.stage.deskTargets[screensCard.stage.pageState().desk] || "" : ""
        onPicked: name => { screensCard.themeModel.target = name }
    }
    Row {
        id: capRow
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: screensCard.stage.u(16) }
        height: screensCard.stage.u(32)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - allChip.width
            text: screensCard.themeModel.status || ("Editing " + screensCard.themeModel.targetLabel)
            elide: Text.ElideRight
            color: screensCard.themeModel.status ? screensCard.stage.rice.bad : screensCard.stage.rice.fgDim
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: screensCard.stage.u(14.5)
        }
        Rectangle {
            id: allChip
            anchors.verticalCenter: parent.verticalCenter
            width: allText.implicitWidth + screensCard.stage.u(28)
            height: screensCard.stage.u(32)
            radius: height / 2
            color: screensCard.themeModel.target === "all" ? screensCard.stage.rice.primary : C.alpha(screensCard.stage.rice.fg, 0.08)
            Text { id: allText; anchors.centerIn: parent; text: "All screens"; color: screensCard.themeModel.target === "all" ? screensCard.stage.rice.onPrimary : screensCard.stage.rice.fg
                   font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: screensCard.stage.u(14.5) }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screensCard.themeModel.target = screensCard.themeModel.target === "all" ? screensCard.stage.screenName : "all" }
            Rectangle {     // the keys' ring
                anchors.fill: parent
                anchors.margins: -Math.max(4, screensCard.stage.u(4))
                radius: height / 2
                color: "transparent"
                border.width: Math.max(2, screensCard.stage.u(2))
                border.color: screensCard.stage.rice.light ? screensCard.stage.rice.fg : "#ffffff"
                opacity: (screensCard.stage.focusRev, screensCard.stage.theming && screensCard.stage.pageState().line === "desk" && screensCard.stage.deskTargets[screensCard.stage.pageState().desk] === "all") ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
            }
        }
    }
}
