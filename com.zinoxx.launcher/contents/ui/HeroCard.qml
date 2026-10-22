import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import "Rice"
import "Rice/Color.js" as C

// The launcher's left side: a card of this screen's wallpaper (or a picture chosen with its pencil, placed
// by hand) with the time, the date, a greeting and the session shortcuts.
Item {
    id: hero
    required property var launcher          // the launcher (its config, actions, sizes)
    required property RicePalette rice
    required property Account account
    property date now: new Date()
    signal browseImage()                     // the pencil menu's Browse image…

    readonly property real radius: Tokens.radius.lg - Tokens.space.sm

    // What it shows: a picture picked with the pencil, or this screen's wallpaper; while
    // picking, the one under the pointer. Where it sits (focus point and zoom, set with
    // "Adjust manually") only applies to the image it was set for.
    property string preview: ""
    readonly property string source: preview || launcher.cfg.heroImage || rice.wallpaper
    readonly property bool placed: !preview && launcher.cfg.heroFor === source
    property bool adjusting: false
    property real editX: 0.5
    property real editY: 0.5
    property real editZoom: 1
    readonly property real fx: adjusting ? editX : placed ? launcher.cfg.heroX : 0.5
    readonly property real fy: adjusting ? editY : placed ? launcher.cfg.heroY : 0.5
    readonly property real zoom: adjusting ? editZoom : placed ? launcher.cfg.heroZoom : 1
    function startAdjust() { editX = fx; editY = fy; editZoom = zoom; adjusting = true }
    function finishAdjust(keep) {
        if (keep) {
            launcher.cfg.heroFor = source
            launcher.cfg.heroX = editX
            launcher.cfg.heroY = editY
            launcher.cfg.heroZoom = editZoom
        }
        adjusting = false
    }
    Connections { target: launcher; function onExpandedChanged() { if (!launcher.expanded) { hero.finishAdjust(false); hero.preview = "" } } }

    Item {
        id: art
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Rectangle { anchors.fill: parent; color: C.alpha(rice.primary, 0.12) }
        Image {
            id: wall
            source: hero.source ? "file://" + hero.source : ""
            asynchronous: true
            smooth: true
            mipmap: true
            // decoded at about the size it shows (the card is tall: the height decides)
            sourceSize.height: Math.ceil(hero.height * Screen.devicePixelRatio * Math.min(3, Math.max(1, hero.zoom)))
            // cover the card, then zoom; the focus point picks which part shows
            readonly property real cover: implicitWidth > 0 && implicitHeight > 0
                ? Math.max(hero.width / implicitWidth, hero.height / implicitHeight) * hero.zoom : 1
            width: implicitWidth * cover
            height: implicitHeight * cover
            x: (hero.width - width) * hero.fx
            y: (hero.height - height) * hero.fy
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.enter } }
        }
    }
    Rectangle { id: artMask; anchors.fill: parent; radius: hero.radius; visible: false; layer.enabled: true }
    Rectangle {      // dusk falls over the lower half, where the text sits
        anchors.fill: parent
        opacity: hero.adjusting ? 0.35 : 1
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        radius: hero.radius
        border.width: 1
        border.color: C.alpha(rice.edge, Tokens.alpha.outline)
        gradient: Gradient {
            GradientStop { position: 0.0; color: C.alpha(rice.surfaceLowest, 0.0) }
            GradientStop { position: 0.38; color: C.alpha(rice.surfaceLowest, 0.15) }
            GradientStop { position: 0.72; color: C.alpha(rice.surfaceLowest, 0.78) }
            GradientStop { position: 1.0; color: C.alpha(rice.surfaceLowest, 0.92) }
        }
    }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: launcher.px(Tokens.space.lg + 4) }
        spacing: 0
        // out of the way while the picture is being placed
        opacity: hero.adjusting ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        Text {
            text: Qt.formatTime(now, "HH:mm")
            color: rice.fg
            font.family: Tokens.font.display
            font.weight: Font.Black
            font.pixelSize: launcher.px(54)
            font.features: { "tnum": 1 }
            style: Text.Raised
            styleColor: C.alpha(rice.surfaceLowest, 0.35)
        }
        Text {
            Layout.topMargin: -Tokens.space.xs
            text: Qt.formatDate(now, "dddd, d MMMM")
            color: rice.fgDim
            font.family: Tokens.font.ui
            font.weight: Font.Medium
            font.pixelSize: launcher.px(Tokens.size.body)
        }
        RowLayout {
            Layout.topMargin: launcher.px(Tokens.space.xl)
            spacing: Tokens.space.md
            Rectangle {               // avatar, as in the session menu
                implicitWidth: launcher.px(40); implicitHeight: implicitWidth; radius: implicitWidth / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: rice.primary }
                    GradientStop { position: 1; color: rice.tertiary }
                }
                border.width: 1
                border.color: C.alpha(rice.edge, Tokens.alpha.outlineStrong)
                Text {
                    anchors.centerIn: parent
                    text: account.initial
                    color: rice.onPrimary
                    font.family: Tokens.font.display
                    font.weight: Font.Black
                    font.pixelSize: launcher.px(Tokens.size.heading)
                }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: launcher.greeting(now.getHours())
                    color: rice.fgDim
                    font.family: Tokens.font.ui
                    font.pixelSize: launcher.px(Tokens.size.label)
                }
                Text {
                    text: account.displayName
                    color: rice.fg
                    font.family: Tokens.font.display
                    font.weight: Font.ExtraBold
                    font.pixelSize: launcher.px(Tokens.size.heading)
                }
            }
        }
        RowLayout {
            id: sessionRow
            Layout.topMargin: launcher.px(Tokens.space.lg + 2)
            spacing: Tokens.space.sm
            Repeater {
                id: sessionButtons
                model: launcher.sessionActions
                Pill {
                    required property var modelData
                    required property int index
                    palette: rice
                    icon: modelData.icon
                    tooltip: modelData.tip
                    size: launcher.px(40)
                    accent: rice[modelData.tone]
                    onAccent: rice.surfaceLowest
                    Keys.onLeftPressed: if (index > 0) sessionButtons.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                    Keys.onRightPressed: if (index < sessionButtons.count - 1) sessionButtons.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)
                    onClicked: { launcher.expanded = false; launcher.run(modelData.cmd) }
                }
            }
        }
    }

    // placing the picture: drag to move it, scroll to zoom; Done keeps it, Esc doesn't
    MouseArea {
        id: placer
        anchors.fill: parent
        enabled: hero.adjusting
        visible: enabled
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point last
        onPressed: m => last = Qt.point(m.x, m.y)
        onPositionChanged: m => {
            const dx = m.x - last.x, dy = m.y - last.y
            last = Qt.point(m.x, m.y)
            const sx = hero.width - wall.width, sy = hero.height - wall.height    // 0 or less
            if (sx < -0.5) hero.editX = Math.max(0, Math.min(1, hero.editX + dx / sx))
            if (sy < -0.5) hero.editY = Math.max(0, Math.min(1, hero.editY + dy / sy))
        }
        onWheel: w => hero.editZoom = Math.max(1, Math.min(3, hero.editZoom * (w.angleDelta.y > 0 ? 1.08 : 1 / 1.08)))
    }
    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: launcher.px(Tokens.space.lg) }
        spacing: Tokens.space.sm
        opacity: hero.adjusting ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        Chip {
            anchors.horizontalCenter: parent.horizontalCenter
            palette: rice
            solid: true
            tint: C.alpha(rice.surfaceLowest, 0.78)
            textColor: rice.fg
            icon: "pan_tool"
            size: 26
            text: "Drag to move · scroll to zoom"
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.space.sm
            Pill { palette: rice; icon: "restart_alt"; text: "Reset"; accent: rice.secondary; onAccent: rice.col("on_secondary")
                   onClicked: { hero.editX = 0.5; hero.editY = 0.5; hero.editZoom = 1 } }
            Pill { palette: rice; icon: "check"; text: "Done"; onClicked: hero.finishAdjust(true) }
        }
    }
    Keys.onEscapePressed: event => { if (hero.adjusting) { hero.finishAdjust(false); event.accepted = true } else event.accepted = false }

    // the pencil: what the hero shows
    Rectangle {
        id: pencil
        anchors { right: parent.right; top: parent.top; margins: Tokens.space.sm + 2 }
        width: launcher.px(32); height: width; radius: width / 2
        visible: !hero.adjusting
        color: C.alpha(rice.surfaceLowest, pencilMouse.containsMouse || heroMenu.opened ? 0.78 : 0.5)
        border.width: 1
        border.color: C.alpha(rice.edge, pencilMouse.containsMouse ? Tokens.alpha.outlineStrong : Tokens.alpha.outline)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Text {
            anchors.centerIn: parent
            text: "edit"
            color: pencilMouse.containsMouse ? rice.primary : rice.fg
            font.family: Tokens.font.icons
            font.pixelSize: launcher.px(17)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
        }
        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: "Hero image"
            subText: launcher.cfg.heroImage ? "A picture of your choice" : "Follows this screen's wallpaper"
            MouseArea {
                id: pencilMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: heroMenu.openRelative()
            }
        }
    }
    PlasmaExtras.Menu {
        id: heroMenu
        visualParent: pencil
        readonly property bool opened: status === PlasmaExtras.Menu.Open
        PlasmaExtras.MenuItem {
            text: "Pick from wallpapers"
            icon: "preferences-desktop-wallpaper"
            onClicked: launcher.openWallpapers("hero")
        }
        PlasmaExtras.MenuItem {
            text: "Adjust manually"
            icon: "transform-move"
            onClicked: { hero.startAdjust(); hero.forceActiveFocus() }
        }
        PlasmaExtras.MenuItem {
            text: "Browse image…"
            icon: "document-open"
            onClicked: hero.browseImage()
        }
        PlasmaExtras.MenuItem { separator: true; visible: !!launcher.cfg.heroImage }
        PlasmaExtras.MenuItem {
            visible: !!launcher.cfg.heroImage
            text: "Follow the wallpaper"
            icon: "view-refresh"
            onClicked: launcher.setHero("")
        }
    }
}
