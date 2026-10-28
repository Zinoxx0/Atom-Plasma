import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// The Theme page's Size tab: how big the rice's UI is on each screen (bars, the top band, popups, clocks).
// Automatic gives every screen its standard size: the same apparent size whatever its resolution, physical
// size and how far away it's seen (a 1080p laptop panel smaller, an 8K bigger; rice.py displays explains
// it), times Overall. Off, Overall is the size on every screen. A screen can also have its own size
// (This screen), until set back to automatic. Changes apply when a slider is let go (rice.py ui set).
Item {
    id: st
    required property RicePalette pal
    property string screen: ""              // the screen chosen on the page's map
    property real rail: 76
    readonly property bool shown: visible
    signal changed()

    property var info: null                 // rice.py ui show
    property bool busy: false
    property string error: ""
    property var draft: ({})                // {size, own} shown while on their way

    readonly property bool auto: info ? info.auto : true
    readonly property real overall: draft.size ?? (info ? info.size : 1)
    readonly property var cur: info ? (info.screens.find(s => s.name === screen) ?? info.screens[0]) : null
    readonly property real ownSize: draft.own ?? (cur ? (cur.own ?? cur.size) : 1)

    // overall: 0.6..1.8; a screen's own size: 0.6..3 (an 8K at scale 1 may want ~3)
    readonly property real oLo: 0.6
    readonly property real oHi: 1.8
    readonly property real sLo: 0.6
    readonly property real sHi: 3.0

    function rice(args) { return ["python3", sh.home + "/.config/plasma-rice/rice.py"].concat(args) }
    function load() { sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" ui show #ushow') }
    function set(args) {
        busy = true; error = ""
        sh.exec("uset", rice(["ui", "set"].concat(args)))       // changing arguments: RiceShell.exec
    }
    function pct(v) { return Math.round(v * 100) + "%" }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            if (source.indexOf("#ushow") >= 0) {
                try { st.info = JSON.parse(data["stdout"] ?? "") } catch (e) {}
                st.draft = ({})
            } else if (source.indexOf("#uset") >= 0) {
                st.busy = false
                if ((data["exit code"] ?? 0) !== 0) st.error = String(data["stderr"] ?? "").trim().split("\n").pop()
                st.load(); st.changed()
            }
            disconnectSource(source)
        }
    }
    onShownChanged: if (shown) load()
    Component.onCompleted: if (shown) load()

    component RailLabel: Text {
        Layout.preferredWidth: st.rail
        Layout.alignment: Qt.AlignVCenter
        color: st.pal.muted
        font.family: Tokens.font.ui
        font.weight: Font.DemiBold
        font.pixelSize: Tokens.size.small
    }
    component Value: Text {
        Layout.preferredWidth: 44
        horizontalAlignment: Text.AlignRight
        color: st.pal.fgDim
        font.family: Tokens.font.mono
        font.pixelSize: Tokens.size.small
    }
    component Note: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: st.pal.muted
        font.family: Tokens.font.ui
        font.pixelSize: Tokens.size.small
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.space.md

        // ---- automatic or one size everywhere
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            RailLabel { text: "Size" }
            Chip {
                palette: st.pal
                interactive: true
                selected: st.auto
                icon: "auto_awesome"
                text: "Automatic"
                tooltip: "Every screen gets the same apparent size, whatever its resolution and how big it is"
                onClicked: if (!st.busy && !st.auto) st.set(["--auto", "true"])
            }
            Item { implicitWidth: Tokens.space.xs + 2 }
            Chip {
                palette: st.pal
                interactive: true
                selected: !st.auto
                icon: "straighten"
                text: "Same everywhere"
                tooltip: "One size on every screen (small on a laptop panel up close, tiny on an 8K)"
                onClicked: if (!st.busy && st.auto) st.set(["--auto", "false"])
            }
            Item { Layout.fillWidth: true }
            Busy { visible: st.busy; running: st.busy; width: 16; height: 16; color: st.pal.primary }
        }

        // ---- overall size
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            RailLabel { text: "Overall" }
            ColourSlider {
                Layout.fillWidth: true
                palette: st.pal
                channel: "x"
                from: C.alpha(st.pal.primary, 0.25)
                to: st.pal.primary
                value: (st.overall - st.oLo) / (st.oHi - st.oLo)
                onMoved: v => st.draft = Object.assign({}, st.draft, { size: Math.round((st.oLo + v * (st.oHi - st.oLo)) * 20) / 20 })
                onReleased: if (st.draft.size !== undefined) st.set(["--size", String(st.draft.size)])
            }
            Value { text: st.pct(st.overall) }
        }

        // ---- every screen's size now (the chosen one's own size below)
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            RailLabel { text: "Screens" }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space.xs + 2
                Repeater {
                    model: st.info ? st.info.screens : []
                    Chip {
                        required property var modelData
                        palette: st.pal
                        selected: modelData.name === (st.cur ? st.cur.name : "")
                        icon: modelData.own ? "push_pin" : ""
                        text: modelData.label + "  " + st.pct(modelData.size)
                        tooltip: modelData.title + " · standard " + st.pct(modelData.standard)
                                 + (modelData.own ? " · its own size" : st.auto ? " · automatic" : "")
                    }
                }
            }
        }

        // ---- the chosen screen's own size
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space.sm
            visible: !!st.cur
            RailLabel { text: st.cur ? st.cur.label : "" }
            ColourSlider {
                Layout.fillWidth: true
                palette: st.pal
                channel: "x"
                from: C.alpha(st.pal.tertiary, 0.25)
                to: st.pal.tertiary
                opacity: st.cur && st.cur.own ? 1 : 0.6
                value: (st.ownSize - st.sLo) / (st.sHi - st.sLo)
                onMoved: v => st.draft = Object.assign({}, st.draft, { own: Math.round((st.sLo + v * (st.sHi - st.sLo)) * 20) / 20 })
                onReleased: if (st.draft.own !== undefined && st.cur)
                    st.set(["--screen", st.cur.name, "--own", String(st.draft.own)])
            }
            Value { text: st.pct(st.ownSize) }
            Pill {
                palette: st.pal
                visible: !!(st.cur && st.cur.own)
                icon: "restart_alt"
                text: "Automatic"
                size: 26
                accent: C.alpha(st.pal.fg, 0.10)
                onAccent: st.pal.fg
                tooltip: "Back to the size every other screen follows"
                onClicked: if (!st.busy) st.set(["--screen", st.cur.name, "--own", "auto"])
            }
        }
        Note {
            visible: !!st.cur
            text: !st.cur ? "" : (st.cur.own ? "This screen keeps its own size. " : "Drag to give this screen its own size. ")
                  + (st.cur.scaleAdvice ? "Plasma's own scale looks off for it (apps too would be tiny or huge): "
                                          + st.cur.scaleAdvice + " in System Settings > Display would suit it." : "")
        }
        Note {
            visible: st.error !== ""
            text: st.error
            color: st.pal.bad
        }
        Item { Layout.fillHeight: true }
    }
}
