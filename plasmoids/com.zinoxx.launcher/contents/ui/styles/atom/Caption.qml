import QtQuick
import QtQuick.Effects
import Atom.Native
import Rice

// Atom's caption, left of the atom, centred on it: where you are ("Pinned  3 of 10"), the name in Hubot Sans (at
// most two lines) or a game's own logo, what it is, its facts (a value over a word), what A and X do (clickable),
// and a page's tools under them (the Games page's library buttons). It slides in a little whenever its content
// changes. content: { where: [strong, ...], name, logo, desc, facts: [[value, label, swatch?]], acts: [[pad, label]],
// tools: [[icon, label]] }; a click on an act or a tool calls stage.act(i) / stage.tool(i).
Item {
    id: cap
    required property var stage
    property var content: ({})
    readonly property var rice: cap.stage.look
    function d(px) { return cap.stage.d(px) }
    x: cap.stage.side
    y: cap.stage.atomAt.y - col.height / 2
    width: cap.stage.capWidth
    height: col.height
    function chip(padKey) {
        const i = cap.stage.input
        return i === "pad" ? padKey : i === "keys" ? ({ A: "Enter", X: "Menu", Y: "Y" }[padKey] || padKey) : ""
    }
    property int swaps: 0
    onContentChanged: { swaps++; slide.restart() }
    property real slideT: 1
    NumberAnimation { id: slide; target: cap; property: "slideT"; from: 0; to: 1; duration: Tokens.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn }

    Column {
        id: col
        width: parent.width
        spacing: 0
        opacity: cap.slideT
        transform: Translate { x: (1 - cap.slideT) * -cap.d(22) }
        Row {               // where you are
            spacing: cap.d(10)
            bottomPadding: cap.d(18)
            Repeater {
                model: cap.content.where || []
                Text { required property var modelData; required property int index
                       text: String(modelData); color: index === 0 ? cap.rice.fg : cap.rice.fgDim
                       style: cap.rice.light ? Text.Raised : Text.Normal
                       styleColor: C.alpha(cap.rice.surfaceLowest, 0.85)
                       font.family: Tokens.font.ui; font.weight: index === 0 ? Font.DemiBold : Font.Medium; font.pixelSize: cap.d(16) }
            }
        }
        Image {             // a game's own logo (soft dark shadow on light themes so white Steam logos stay legible)
            visible: !!cap.content.logo && status === Image.Ready
            source: cap.content.logo || ""
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: cap.d(520)
            width: Math.min(cap.d(520), implicitWidth); height: Math.min(cap.d(170), implicitHeight * width / Math.max(1, implicitWidth))
            layer.enabled: visible && cap.rice.light
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
                shadowBlur: 0.65
                shadowHorizontalOffset: 0
                shadowVerticalOffset: cap.d(2)
                shadowScale: 1.02
            }
        }
        Item { width: 1; height: cap.content.logo ? cap.d(18) : 0 }
        Text {              // the name: Hubot Sans, as big as two lines allow
            id: name
            visible: !cap.content.logo
            width: parent.width
            text: cap.content.name || ""
            color: cap.rice.fg
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 1.02
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: cap.d(44)
            font.pixelSize: cap.d(88)
            font.family: cap.stage.wideFamily
            font.variableAxes: cap.stage.wide(125, 680)
            font.letterSpacing: -cap.d(0.8)
            bottomPadding: cap.d(14)
        }
        Text {
            visible: !!cap.content.desc
            width: Math.min(parent.width, cap.d(680))
            text: cap.content.desc || ""
            color: cap.rice.fgDim
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Tokens.font.ui
            font.pixelSize: cap.d(20)
            lineHeight: 1.15
            bottomPadding: cap.d(34)
        }
        Row {               // facts: a value over a word
            visible: (cap.content.facts || []).length > 0
            spacing: cap.d(52)
            bottomPadding: cap.d(40)
            Repeater {
                model: cap.content.facts || []
                Column {
                    required property var modelData
                    spacing: cap.d(4)
                    Row { spacing: cap.d(10)
                        Rectangle { visible: !!modelData[2]; width: cap.d(22); height: width; radius: width / 2; color: modelData[2] || "transparent"
                                    anchors.verticalCenter: parent.verticalCenter; border.width: 1; border.color: C.alpha("#ffffff", 0.25) }
                        Text { text: String(modelData[0] ?? ""); color: cap.rice.fg; font.family: cap.stage.wideFamily; font.pixelSize: cap.d(30)
                               font.variableAxes: cap.stage.wide(112, 600); font.features: { "tnum": 1 } } }
                    Text { text: String(modelData[1] ?? ""); color: cap.rice.fgDim; font.family: Tokens.font.ui; font.pixelSize: cap.d(14.5) }
                }
            }
        }
        Row {               // what A and X do (the pad's letters; clickable)
            spacing: cap.d(8)
            Repeater {
                model: cap.content.acts || []
                Rectangle {
                    id: act
                    required property var modelData
                    required property int index
                    readonly property bool lit: index === 0
                    readonly property bool keyed: cap.stage.capFocus === index
                    width: actRow.implicitWidth + cap.d(26); height: cap.d(46); radius: height / 2
                    color: C.alpha(cap.rice.fg, am.containsMouse ? 0.12 : 0)
                    border.width: act.keyed ? Math.max(1.5, cap.d(1.6)) : 0; border.color: cap.rice.fg
                    Row { id: actRow; anchors.centerIn: parent; spacing: cap.d(10)
                        Rectangle { visible: pg.text !== ""; width: Math.max(height, pg.implicitWidth + cap.d(12)); height: cap.d(26); radius: height / 2; anchors.verticalCenter: parent.verticalCenter
                                    color: "transparent"; border.width: Math.max(1, cap.d(1.5)); border.color: act.lit ? cap.rice.primary : C.alpha(cap.rice.fg, 0.34)
                                    // the pad's letter, the key that does it, or nothing for the pointer
                                    Text { id: pg; anchors.centerIn: parent; text: cap.chip(String(act.modelData[0])); color: act.lit ? cap.rice.fg : cap.rice.fgDim
                                           font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: cap.d(12.5) } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(act.modelData[1]); color: cap.rice.fg
                               font.family: Tokens.font.ui; font.weight: act.lit ? Font.DemiBold : Font.Medium; font.pixelSize: cap.d(17) } }
                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cap.stage.act(act.index) }
                }
            }
        }
        Item { width: 1; height: (cap.content.tools || []).length ? cap.d(30) : 0 }
        Flow {              // a page's tools (the library's buttons)
            width: parent.width
            spacing: cap.d(10)
            Repeater {
                model: cap.content.tools || []
                Rectangle {
                    id: tool
                    required property var modelData
                    required property int index
                    readonly property bool keyed: cap.stage.capFocus === (cap.content.acts || []).length + index
                    width: toolRow.implicitWidth + cap.d(32); height: cap.d(44); radius: height / 2
                    color: C.alpha(tm2.containsMouse || tool.keyed ? cap.rice.fg : cap.rice.surfaceLowest, tm2.containsMouse || tool.keyed ? 0.12 : 0.45)
                    border.width: tool.keyed ? Math.max(1.5, cap.d(1.6)) : 1
                    border.color: tool.keyed ? cap.rice.fg : C.alpha(cap.rice.fg, 0.14)
                    Row { id: toolRow; anchors.centerIn: parent; spacing: cap.d(9)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(tool.modelData[0]); color: cap.rice.fgDim; font.family: Tokens.font.icons; font.pixelSize: cap.d(20) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String(tool.modelData[1]); color: tm2.containsMouse || tool.keyed ? cap.rice.fg : cap.rice.fgDim
                               font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: cap.d(15) } }
                    MouseArea { id: tm2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cap.stage.tool(tool.index) }
                }
            }
        }
    }
}
