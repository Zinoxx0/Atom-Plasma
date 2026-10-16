import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// Live thumbnails of one app's windows, hanging under its icon below the label tab: one card per
// window, with its title and whether it is minimized; a window on another screen sits a little smaller
// and darker, like its app's icon. A card takes the same clicks as a window in the band (minimized ->
// restore here, elsewhere -> slide here, focused -> minimize, else focus); middle-click or the x
// closes it. The streams only run while it shows.
Item {
    id: strip
    property var g                          // the Glimpse root
    property Item tile                      // the app whose windows show; null hides the strip
    property Item shown: null               // what is on display (kept while fading out)
    property real centerX: 0                // under the icon
    property real minX: 0                   // the strip stays within [minX, maxX]
    property real maxX: 0

    readonly property int pad: g.px(8)
    readonly property int gap: g.px(8)
    readonly property int cpad: g.px(6)     // inside a card
    readonly property int titleH: g.px(18)
    readonly property int baseTh: g.px(104) // a thumbnail's height, unless many have to fit
    readonly property int radius: Tokens.radius.lg
    readonly property int cardRadius: Math.max(Tokens.radius.xs, radius - pad)
    // the tallest it gets, for sizing the window it lives in
    readonly property int fullHeight: baseTh + titleH + 3 * cpad + 2 * pad

    readonly property var tasks: shown ? shown.tasks : null
    readonly property var wins: shown ? g.windowsOf(shown.tasks, shown.srcIndex, g.tick) : []
    readonly property var infos: wins.map(w => g.windowInfo(tasks, w))
    readonly property var aspects: infos.map(i => {
        const r = i ? i.geometry : null
        return r && r.height > 0 ? Math.max(0.6, Math.min(2.4, r.width / r.height)) : 1.6
    })
    readonly property real aspectSum: aspects.reduce((a, b) => a + b, 0)
    readonly property int th: Math.floor(Math.max(g.px(40), Math.min(baseTh,
        (maxX - minX - 2 * pad - (wins.length - 1) * gap - wins.length * 2 * cpad) / Math.max(0.1, aspectSum))))
    readonly property int cardH: th + titleH + 3 * cpad

    // drops in under the tab; fades out quicker than it came
    property real reveal: tile ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: strip.tile ? Tokens.base : Tokens.fast; easing.type: strip.tile ? Tokens.enter : Tokens.exit } }
    onTileChanged: if (tile) shown = tile
    onRevealChanged: if (reveal <= 0) shown = null
    readonly property bool streaming: shown !== null && reveal > 0

    visible: reveal > 0 && wins.length > 0
    opacity: reveal
    width: row.width + 2 * pad
    height: cardH + 2 * pad
    x: Math.round(Math.max(minX, Math.min(maxX - width, centerX - width / 2)))
    Behavior on x { enabled: strip.reveal > 0.9; NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
    transform: Translate { y: (1 - strip.reveal) * -strip.g.px(6) }

    Rectangle {
        anchors.fill: parent
        radius: strip.radius
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(C.mix(strip.g.cBezel, strip.g.cPrimary, 0.10), 0.96) }
            GradientStop { position: 1; color: C.alpha(strip.g.cBezel, 0.96) }
        }
        border.width: 1
        border.color: C.alpha("#ffffff", Tokens.alpha.outline)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: Tokens.alpha.shadow
            shadowBlur: 0.8
            shadowVerticalOffset: strip.g.px(4)
            shadowHorizontalOffset: 0
        }
    }

    Row {
        id: row
        x: strip.pad
        y: strip.pad
        spacing: strip.gap
        Repeater {
            model: strip.wins.length
            delegate: Thumb {}
        }
    }

    component Chip: Rectangle {
        property alias text: label.text
        property bool accent: false
        height: strip.g.px(16)
        width: label.implicitWidth + strip.g.px(10)
        radius: height / 2
        color: accent ? strip.g.cPrimary : C.alpha(strip.g.cBezel, 0.88)
        gradient: accent ? accentFill : null
        Gradient {
            id: accentFill
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: strip.g.cPrimary }
            GradientStop { position: 1; color: strip.g.cTertiary }
        }
        Text {
            id: label
            anchors.centerIn: parent
            color: parent.accent ? strip.g.cOnPrimary : strip.g.cFg
            font.family: Tokens.font.ui
            font.pixelSize: strip.g.px(Tokens.size.caption)
            font.weight: parent.accent ? Font.Bold : Font.DemiBold
        }
    }

    component Thumb: Item {
        id: card
        required property int index
        readonly property var g: strip.g
        readonly property var idx: strip.wins[index] ?? null
        readonly property var info: strip.infos[index] ?? null
        readonly property string uuid: info ? info.uuid : ""
        readonly property string title: info ? info.title : ""
        readonly property bool minimized: info ? info.minimized : false
        readonly property bool active: info ? info.active : false
        readonly property bool here: info ? info.here : true
        readonly property bool away: !here         // on another screen: a little smaller and darker
        readonly property real aspect: strip.aspects[index] ?? 1.6
        readonly property bool hovered: hover.hovered
        width: Math.round(strip.th * aspect) + 2 * strip.cpad
        height: strip.cardH
        scale: away ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }

        HoverHandler { id: hover }

        Rectangle {
            anchors.fill: parent
            radius: strip.cardRadius
            color: C.alpha("#ffffff", card.hovered ? Tokens.alpha.hover : 0.03)
            border.width: 1
            border.color: card.active ? C.alpha(card.g.cPrimary, 0.8)
                        : C.alpha("#ffffff", card.hovered ? Tokens.alpha.outlineStrong : Tokens.alpha.outline)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
        }

        Item {
            id: preview
            x: strip.cpad
            y: strip.cpad
            width: card.width - 2 * strip.cpad
            height: strip.th
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: previewMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                brightness: card.away ? -0.42 : 0
                saturation: card.away ? -0.3 : 0
            }
            Rectangle { anchors.fill: parent; color: C.alpha("#000000", 0.3) }
            Kirigami.Icon {         // until the first frame arrives (and for windows KWin can't show)
                anchors.centerIn: parent
                width: Math.round(strip.th * 0.4)
                height: width
                source: strip.shown ? strip.shown.icon : ""
                animated: false
                opacity: stream.item && stream.item.ready ? 0 : 0.7
            }
            Loader {
                id: stream
                anchors.fill: parent
                active: strip.streaming && card.uuid !== ""
                source: "PipeWireThumb.qml"
            }
            Binding { target: stream.item; property: "uuid"; value: card.uuid; when: stream.status === Loader.Ready }
        }
        Rectangle {
            id: previewMask
            visible: false
            layer.enabled: true
            width: preview.width
            height: preview.height
            radius: Math.max(4, strip.cardRadius - strip.cpad)
        }

        Chip {
            x: preview.x + strip.cpad
            y: preview.y + strip.cpad
            visible: card.minimized
            text: i18n("Minimized")
        }

        Row {
            x: strip.cpad
            y: strip.cpad * 2 + strip.th
            width: card.width - 2 * strip.cpad
            height: strip.titleH
            spacing: strip.g.px(6)
            Kirigami.Icon {
                id: appIcon
                anchors.verticalCenter: parent.verticalCenter
                width: strip.g.px(14)
                height: width
                source: strip.shown ? strip.shown.icon : ""
                animated: false
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - appIcon.width - parent.spacing
                text: card.title
                elide: Text.ElideRight
                color: card.away ? card.g.cFgDim : card.g.cFg
                font.family: Tokens.font.ui
                font.pixelSize: strip.g.px(Tokens.size.small)
                font.weight: card.active ? Font.DemiBold : Font.Medium
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) strip.tasks.requestClose(card.idx)
                else card.g.actOn(strip.tasks, card.idx)
            }
        }

        // close: only on hover, in the preview's corner
        Rectangle {
            x: preview.x + preview.width - width - strip.g.px(4)
            y: preview.y + strip.g.px(4)
            width: strip.g.px(20)
            height: width
            radius: width / 2
            opacity: card.hovered ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
            color: closeArea.containsMouse ? card.g.cRed : C.alpha(card.g.cBezel, 0.88)
            border.width: 1
            border.color: C.alpha("#ffffff", Tokens.alpha.outline)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            Text {
                anchors.centerIn: parent
                text: "close"
                color: closeArea.containsMouse ? card.g.cBezel : card.g.cFg
                font.family: Tokens.font.icons
                font.pixelSize: strip.g.px(14)
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.tasks.requestClose(card.idx)
            }
        }
    }
}
