import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// The screens as they sit on the desk: each monitor drawn small, at its real position and shape,
// showing its wallpaper and a dot of its accent (ringed when its colours are hand-picked). The one
// whose wallpaper drives the system theme (window colours, terminals, apps) wears a star. Click a
// monitor to edit it; `linked` draws them all as one selection (edits go to every screen).
Item {
    id: dm
    required property RicePalette pal
    property var screens: []                // rice.py screens: name, label, x, y, w, h, thumb, lead, accent, overrides
    property string focusName: ""
    property bool linked: false
    signal picked(string name)

    readonly property real gap: 4
    readonly property real minX: screens.length ? Math.min(...screens.map(s => s.x)) : 0
    readonly property real minY: screens.length ? Math.min(...screens.map(s => s.y ?? 0)) : 0
    readonly property real spanW: screens.length ? Math.max(...screens.map(s => s.x + s.w)) - minX : 1
    readonly property real spanH: screens.length ? Math.max(...screens.map(s => (s.y ?? 0) + s.h)) - minY : 1
    readonly property real k: Math.min(width / Math.max(1, spanW), height / Math.max(1, spanH))
    implicitWidth: spanW * height / Math.max(1, spanH)      // as wide as the height allows

    Repeater {
        model: dm.screens
        Item {
            id: mon
            required property var modelData
            readonly property bool selected: dm.linked || modelData.name === dm.focusName
            readonly property bool focused: modelData.name === dm.focusName
            readonly property bool custom: Object.keys(modelData.overrides ?? {}).length > 0
            readonly property bool hot: monMouse.containsMouse
            x: (modelData.x - dm.minX) * dm.k + dm.gap / 2
            y: ((modelData.y ?? 0) - dm.minY) * dm.k + dm.gap / 2
            width: modelData.w * dm.k - dm.gap
            height: modelData.h * dm.k - dm.gap
            scale: monMouse.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }

            Kirigami.ShadowedImage {
                anchors.fill: parent
                radius: Tokens.radius.xs
                color: C.alpha(dm.pal.fg, 0.08)
                source: mon.modelData.thumb ? "file://" + mon.modelData.thumb : ""
                sourceSize.width: 160
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: mon.selected || mon.hot ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
            }
            Rectangle {     // its name on a soft scrim along the bottom
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.min(parent.height, 18)
                radius: Tokens.radius.xs
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                }
            }
            Text {
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: 5; bottomMargin: 2 }
                text: mon.modelData.label
                color: "#ffffff"
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: Tokens.size.caption
            }
            Rectangle {     // its accent; ringed when hand-picked
                anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                width: 9; height: 9; radius: 4.5
                color: mon.modelData.accent || dm.pal.primary
                border.width: mon.custom ? 1.5 : 0
                border.color: "#ffffff"
            }
            Text {          // drives the system theme
                visible: mon.modelData.lead
                anchors { right: parent.right; top: parent.top; margins: 2 }
                text: "star"
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.5)
                font.family: Tokens.font.icons
                font.pixelSize: 13
                font.variableAxes: ({ "FILL": 1 })
                renderType: Text.NativeRendering
            }
            Rectangle {     // selection
                anchors.fill: parent
                anchors.margins: -2
                radius: Tokens.radius.xs + 2
                color: "transparent"
                border.width: mon.focused && !dm.linked ? 2 : mon.selected ? 1.5 : mon.hot ? 1 : 0
                border.color: mon.selected ? dm.pal.primary : C.alpha(dm.pal.fg, 0.5)
                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                mainText: mon.modelData.label + " · " + mon.modelData.name
                subText: [mon.modelData.lead ? "Its wallpaper drives window colours, terminals and apps" : "",
                          mon.custom ? "Hand-picked colours" : "Colours from its wallpaper"].filter(s => s).join(" · ")
                MouseArea {
                    id: monMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dm.picked(mon.modelData.name)
                }
            }
        }
    }
}
