import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import "../../qml/Rice"
import "../../qml/Rice/Color.js" as C

// Offscreen render of the design tokens: each screen's palette, radii, type scale, components.
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml6 TokenSheet.qml -- <out.png>
Window {
    id: win
    width: 1400; height: 980; visible: true
    color: main.surfaceLowest
    readonly property string out: Qt.application.arguments[Qt.application.arguments.length - 1]
    property var outputs: ["HDMI-A-1", "eDP-1", "DP-3"]
    RicePalette { id: main; output: "HDMI-A-1" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.space.xxl
        spacing: Tokens.space.xl

        Text { text: "Rice design tokens"; color: main.fg; font.family: Tokens.font.display; font.weight: Font.ExtraBold; font.pixelSize: Tokens.size.hero }

        // palettes per screen
        Repeater {
            model: win.outputs
            RowLayout {
                required property string modelData
                spacing: Tokens.space.sm
                RicePalette { id: p; output: modelData }
                Text { text: modelData; color: p.fg; font.family: Tokens.font.ui; font.weight: Font.Bold; font.pixelSize: Tokens.size.body; Layout.preferredWidth: 90 }
                Repeater {
                    model: ["surface_lowest", "surface_container", "surface_highest", "outline", "on_surface", "primary", "secondary", "tertiary", "red", "orange", "yellow", "green", "teal", "cyan", "blue", "magenta"]
                    Rectangle {
                        required property string modelData
                        width: 56; height: 40; radius: Tokens.radius.sm
                        color: p.col(modelData)
                        border.width: 1; border.color: C.alpha("#ffffff", Tokens.alpha.outline)
                    }
                }
            }
        }

        RowLayout {
            spacing: Tokens.space.xl
            // radii
            Repeater {
                model: ["xs", "sm", "md", "lg", "xl"]
                Column {
                    required property string modelData
                    spacing: Tokens.space.xs
                    Rectangle {
                        width: 96; height: 64; radius: Tokens.radius[modelData]
                        color: C.alpha(main.surfaceHigh, 0.9)
                        border.width: 1; border.color: C.alpha("#ffffff", Tokens.alpha.outlineStrong)
                    }
                    Text { text: modelData + " " + Tokens.radius[modelData]; color: main.fgDim; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                }
            }
            // type scale
            Column {
                spacing: 2
                Repeater {
                    model: ["hero", "display", "heading", "title", "body", "label", "small", "caption"]
                    Text {
                        required property string modelData
                        text: modelData + " " + Tokens.size[modelData] + " px"
                        color: main.fg
                        font.family: Tokens.size[modelData] >= 18 ? Tokens.font.display : Tokens.font.ui
                        font.weight: Tokens.size[modelData] >= 18 ? Font.ExtraBold : Font.Medium
                        font.pixelSize: Tokens.size[modelData]
                    }
                }
            }
        }

        // components on a popup-like glass
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 230
            radius: Tokens.radius.lg
            color: C.alpha(main.surface, Tokens.alpha.glass)
            border.width: 1; border.color: C.alpha("#ffffff", Tokens.alpha.outline)
            RowLayout {
                anchors.fill: parent; anchors.margins: Tokens.space.lg
                spacing: Tokens.space.lg
                GlassCard {
                    palette: main; accent: main.primary
                    Layout.preferredWidth: 320; Layout.fillHeight: true
                    Column {
                        anchors.fill: parent; anchors.margins: Tokens.space.md
                        spacing: Tokens.space.sm
                        SectionHeader { palette: main; text: "Section header" }
                        Text { text: "GlassCard (radius md inside a popup of lg)"; color: main.fg; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.body; width: parent.width; wrapMode: Text.Wrap }
                        Row {
                            spacing: Tokens.space.xs
                            IconButton { palette: main; icon: "lock"; tooltip: "Lock" }
                            IconButton { palette: main; icon: "bedtime"; checked: true }
                            IconButton { palette: main; icon: "power_settings_new"; accent: main.red }
                            IconButton { palette: main; icon: "open_in_new"; text: "Usage page" }
                        }
                    }
                }
                Ring { Layout.preferredWidth: 150; Layout.preferredHeight: 150; value: 64; pace: 40; label: "Session"; instant: true; from: main.primary; to: main.tertiary; track: C.alpha(main.fg, 0.08); textColor: main.fg; subColor: main.fgDim; paceColor: main.fg }
                Clawd { px: 6; animate: false; mood: "happy"; working: true; pal: main.values }
                Item { Layout.fillWidth: true }
                Column {
                    spacing: Tokens.space.xs
                    Text { text: "motion (system speed " + Tokens.speed + "x)"; color: main.fgDim; font.family: Tokens.font.ui; font.pixelSize: Tokens.size.small }
                    Text { text: "fast " + Tokens.fast + " ms · base " + Tokens.base + " ms · slow " + Tokens.slow + " ms"; color: main.fg; font.family: Tokens.font.mono; font.pixelSize: Tokens.size.label }
                    Text { text: "enter OutCubic · exit InCubic · move InOutCubic"; color: main.fg; font.family: Tokens.font.mono; font.pixelSize: Tokens.size.label }
                }
            }
        }
    }
    Timer { interval: 1500; running: true; onTriggered: win.contentItem.grabToImage(r => { r.saveToFile(win.out); Qt.quit() }) }
}
