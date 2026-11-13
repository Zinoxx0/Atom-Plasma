import QtQuick
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// The focused item, large (Atom Home's hero): a game's own logo or the app's name, what it is and when it
// was last used, its description, and its actions: Play or Open (the one bright pill), Pin, More.
// The stage keeps two and cross-fades between them as the focus moves.
Item {
    id: hero
    property var item: null
    required property RicePalette rice
    property real unit: 1
    property bool pinned: false
    property string eyebrow: ""             // a line above the title (the Theme page uses it)
    property var swatches: []               // colours shown above the title (the Theme page's)
    property string primaryText: ""         // overrides "Open" / "Play"
    property string primaryIcon: ""
    property var extraActions: null         // [{ icon, tip, on }] in place of Pin and More
    signal primary()
    signal pin()
    signal more(Item from)
    signal extra(int i, Item from)
    function u(n) { return Math.round(n * unit) }

    readonly property bool game: !!(item && item.game)
    readonly property string logo: item && item.art && item.art.logo ? item.art.logo : ""
    function ago(ts) {
        const s = Date.now() / 1000 - ts
        if (s < 90) return "just now"
        if (s < 3600) return Math.round(s / 60) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        if (s < 172800) return "yesterday"
        if (s < 86400 * 30) return Math.round(s / 86400) + " days ago"
        return new Date(ts * 1000).toLocaleDateString(Qt.locale(), "d MMM")
    }
    readonly property var meta: {
        if (!item) return []
        if (item.meta) return item.meta
        const out = [game ? "Game" : (item.category || "App")]
        out.push(item.last ? (game ? "Played " : "Used ") + ago(item.last) : game ? "Installed" : "")
        return out.filter(Boolean)
    }
    readonly property string desc: {
        if (!item) return ""
        const d = item.desc || ""
        return /on steam/i.test(d) ? "" : d
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 0
        Text {
            visible: !!hero.eyebrow
            text: hero.eyebrow.toUpperCase()
            color: hero.rice.primary
            font.family: Tokens.font.ui
            font.weight: Font.Bold
            font.pixelSize: hero.u(13)
            font.letterSpacing: hero.u(1.6)
            bottomPadding: hero.u(8)
        }
        Row {
            visible: hero.swatches.length > 0
            spacing: hero.u(10)
            bottomPadding: hero.u(14)
            Repeater {
                model: hero.swatches
                Rectangle {
                    required property var modelData
                    width: hero.u(30); height: width; radius: width / 2
                    color: modelData
                    border.width: 1
                    border.color: C.alpha("#ffffff", 0.3)
                }
            }
        }
        Image {
            visible: !!hero.logo
            source: hero.logo
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            width: hero.u(470)
            height: hero.u(150)
            sourceSize.width: 940
        }
        Item { visible: !!hero.logo; width: 1; height: hero.u(18) }
        Text {
            visible: !hero.logo
            width: parent.width
            text: hero.item ? hero.item.name : ""
            elide: Text.ElideRight
            color: hero.rice.fg
            font.family: Tokens.font.display
            font.weight: Font.Bold
            font.pixelSize: hero.u(62)
            font.letterSpacing: -hero.u(1.3)
            bottomPadding: hero.u(12)
            style: Text.Raised
            styleColor: C.alpha(hero.rice.surfaceLowest, 0.35)
        }
        Row {       // what it is · when · pinned
            spacing: hero.u(10)
            Repeater {
                model: hero.meta
                Row {
                    required property var modelData
                    required property int index
                    spacing: hero.u(10)
                    Rectangle {
                        visible: index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: hero.u(4); height: width; radius: width / 2
                        color: hero.rice.fgDim
                        opacity: 0.6
                    }
                    Text {
                        text: modelData
                        color: hero.rice.fgDim
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: hero.u(14)
                    }
                }
            }
            Rectangle {
                visible: hero.pinned
                anchors.verticalCenter: parent.verticalCenter
                width: pinText.implicitWidth + hero.u(20)
                height: pinText.implicitHeight + hero.u(6)
                radius: height / 2
                color: C.alpha(hero.rice.fg, 0.12)
                Text {
                    id: pinText
                    anchors.centerIn: parent
                    text: "Pinned"
                    color: hero.rice.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: hero.u(13)
                }
            }
        }
        Text {
            visible: !!hero.desc
            width: Math.min(parent.width, hero.u(600))
            topPadding: hero.u(10)
            text: hero.desc
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: hero.rice.fgDim
            font.family: Tokens.font.ui
            font.pixelSize: hero.u(16.5)
            lineHeight: 1.12
        }
        Item { width: 1; height: hero.u(24) }
        Row {
            spacing: hero.u(12)
            Pill {      // the one bright pill
                rice: hero.rice; unit: hero.unit
                icon: hero.primaryIcon || (hero.game ? "play_arrow" : "open_in_new")
                text: hero.primaryText || (hero.game ? "Play" : "Open")
                bright: true
                onClicked: hero.primary()
            }
            Pill {
                rice: hero.rice; unit: hero.unit
                visible: !hero.extraActions
                icon: "push_pin"
                filled: hero.pinned
                tip: hero.pinned ? "Unpin" : "Pin"
                onClicked: hero.pin()
            }
            Pill {
                id: moreButton
                rice: hero.rice; unit: hero.unit
                visible: !hero.extraActions
                icon: "more_horiz"
                tip: "More"
                onClicked: hero.more(moreButton)
            }
            Repeater {
                model: hero.extraActions || []
                Pill {
                    id: ex
                    rice: hero.rice; unit: hero.unit
                    required property var modelData
                    required property int index
                    icon: modelData.icon
                    tip: modelData.tip || ""
                    filled: !!modelData.on
                    onClicked: hero.extra(index, ex)
                }
            }
        }
    }

    // a hero button: the bright pill (white in the dark, ink in the light) or a round glass one
    component Pill: Rectangle {
        id: pill
        property string icon: ""
        property string text: ""
        property string tip: ""
        property bool bright: false
        property bool filled: false
        property RicePalette rice: null
        property real unit: 1
        function u(n) { return Math.round(n * unit) }
        signal clicked()
        readonly property bool hot: pm.containsMouse
        height: pill.u(52)
        width: bright ? row.implicitWidth + pill.u(54) : height
        radius: height / 2
        color: bright ? (pill.rice.light ? pill.rice.fg : "#f3f6fb") : C.alpha(pill.rice.fg, hot ? 0.2 : 0.12)
        border.width: bright ? 0 : 1
        border.color: C.alpha(pill.rice.edge, 0.14)
        scale: pm.pressed ? 0.96 : hot ? (bright ? 1.04 : 1.05) : 1
        Behavior on scale { NumberAnimation { duration: Tokens.ms(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: pill.u(10)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                color: pill.bright ? (pill.rice.light ? pill.rice.surfaceLowest : "#0a0d13") : pill.filled ? pill.rice.primary : pill.rice.fg
                font.family: Tokens.font.icons
                font.pixelSize: pill.u(pill.bright ? 26 : 24)
                font.variableAxes: { "FILL": pill.bright || pill.filled ? 1 : 0 }
            }
            Text {
                visible: !!pill.text
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.rice.light ? pill.rice.surfaceLowest : "#0a0d13"
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: pill.u(16.5)
            }
        }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
    }
}
