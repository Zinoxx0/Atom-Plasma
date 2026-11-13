import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.volume as Vol
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.bluezqt as BluezQt
import org.kde.notificationmanager as NM
import Atom
import Atom.Native
import "Rice"
import "Rice/Color.js" as C

// The status island (it replaces Plasma's system tray): your apps' tray icons (Atom.Native Tray: a click
// brings the app's window back, or opens the app when it has none; a right click its menu on the shell's
// sheet, the middle button its second action, the wheel scrolls it; the quiet ones stack), the room's lights when home (Atom RoomLight: a click opens the Room panel, the middle
// button switches them all, the wheel dims them), then the system's state in glyphs (network, Bluetooth,
// sound, a microphone in use, the battery, Do Not Disturb). A click on the glyphs opens the control
// center (Atom panels/Control.qml).
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property real ui: pal.uiScale
    function u(n) { return Math.round(n * ui) }

    PlasmaNM.ConnectionIcon { id: net }
    readonly property string netGlyph: {
        const n = String(net.connectionIcon || "")
        if (n.indexOf("wired") >= 0) return "lan"
        if (n.indexOf("offline") >= 0 || n.indexOf("disconnected") >= 0 || n === "") return "signal_disconnected"
        if (n.indexOf("excellent") >= 0 || n.indexOf("100") >= 0) return "wifi"
        if (n.indexOf("good") >= 0 || n.indexOf("75") >= 0) return "network_wifi_3_bar"
        if (n.indexOf("ok") >= 0 || n.indexOf("50") >= 0) return "network_wifi_2_bar"
        if (n.indexOf("weak") >= 0 || n.indexOf("25") >= 0 || n.indexOf("none") >= 0 || n.indexOf("00") >= 0) return "network_wifi_1_bar"
        if (n.indexOf("wireless") >= 0) return "wifi"
        return "lan"
    }
    readonly property var bt: BluezQt.Manager
    readonly property bool btConnected: Array.prototype.slice.call(bt.devices || []).some(d => d.connected)
    readonly property var sink: Vol.PreferredDevice.sink
    Vol.SourceOutputModel { id: recording }
    P5Support.DataSource { engine: "powermanagement"; connectedSources: ["Battery"]; onNewData: (s, d) => root.batt = d }
    property var batt: ({})
    readonly property bool hasBattery: batt["Has Battery"] === true
    readonly property int charge: Number(batt["Percent"]) || 0
    readonly property bool charging: batt["State"] === "Charging" || batt["State"] === "FullyCharged"
    NM.Settings { id: notifySettings }
    readonly property bool dnd: { const t = notifySettings.notificationsInhibitedUntil; return !!t && !isNaN(t) && t > new Date() }

    // the glyphs, left to right
    readonly property var glyphs: {
        const g = []
        if (dnd) g.push({ g: "do_not_disturb_on", c: pal.tertiary })
        if (recording.count > 0) g.push({ g: "mic", c: pal.warn })
        g.push({ g: netGlyph, c: pal.fg })
        if (bt.bluetoothOperational && btConnected) g.push({ g: "bluetooth_connected", c: pal.fg })
        g.push({ g: !sink || sink.muted ? "volume_off" : sink.volume > 65536 * 0.6 ? "volume_up" : sink.volume > 0 ? "volume_down" : "volume_mute", c: !sink || sink.muted ? pal.muted : pal.fg })
        if (hasBattery) g.push({ g: charging ? "battery_charging_full" : charge <= 10 ? "battery_alert" : "battery_" + Math.min(6, Math.round(charge / 100 * 6)) + "_bar",
                                 c: !charging && charge <= 15 ? pal.bad : pal.fg })
        return g
    }

    // its global shortcut (Meta+V, set by panel/build.py) opens the clipboard's history on the active screen;
    // Plasma also expands the applet on activation: there's no popup, so it folds straight back
    Connections {
        target: Plasmoid
        function onActivated() {
            if (Shell.kind === "clipboard") { Shell.close("clipboard"); return }
            const scr = Windows.activeScreen || Screen.name
            Shell.open("clipboard", scr, Shell.island("control", scr))
        }
    }
    onExpandedChanged: if (expanded) Qt.callLater(() => { root.expanded = false })

    toolTipMainText: "Status"
    toolTipSubText: "Network, sound, Bluetooth, battery · your apps"
    preferredRepresentation: compactRepresentation

    compactRepresentation: RowLayout {
        id: compact
        spacing: root.u(4)
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.fillHeight: true

        Item { implicitWidth: root.u(Tokens.space.sm) }

        // beads: the apps with news you haven't seen (Atom Notify), each a candy dot in the app's colour with
        // a ring that fills a fifth per message; they overlap when there are many and fan out under the pointer
        Row {
            id: beads
            visible: Notify.unseen.length > 0
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: visible ? root.u(6) : 0
            spacing: fanned ? root.u(5) : Notify.unseen.length > 3 ? -root.u(9) : root.u(3)
            Behavior on spacing { NumberAnimation { duration: Tokens.ms(380); easing.type: Tokens.grow } }
            // under the pointer: each bead's own hover (see the apps' icons below for why not a HoverHandler)
            property bool fanned: false
            function hoverCheck() {
                let any = false
                for (let i = 0; i < beadIcons.count; i++) if (beadIcons.itemAt(i)?.hovered) any = true
                if (any) { beadSettle.stop(); fanned = true } else beadSettle.restart()
            }
            Timer { id: beadSettle; interval: Tokens.ms(220); onTriggered: beads.fanned = false }
            Repeater {
                id: beadIcons
                model: Notify.unseen
                // Plasma's tooltip wraps the bead's MouseArea (Qt Quick Controls' tooltips open as popup
                // windows that take the pointer from the bar: the next click only closed the tooltip)
                delegate: PlasmaCore.ToolTipArea {
                    id: bead
                    required property var modelData
                    required property int index
                    readonly property color tint: C.appTint(beadColors, pal.primary)
                    readonly property bool hovered: beadArea.containsMouse
                    onHoveredChanged: beads.hoverCheck()
                    Kirigami.ImageColors { id: beadColors; source: bead.modelData.icon }
                    width: root.u(24); height: width
                    z: Notify.unseen.length - index
                    mainText: bead.modelData.name
                    subText: bead.modelData.unread + " new"
                    scale: hovered ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                    Rectangle {     // the candy: the app's colour, glassy
                        anchors.centerIn: parent
                        width: root.u(20); height: width; radius: width / 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(bead.tint, 1.25) }
                            GradientStop { position: 1; color: Qt.darker(bead.tint, 1.15) }
                        }
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: root.u(13); height: width
                            source: bead.modelData.icon
                        }
                    }
                    Shape {     // how many: an arc around it
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: Qt.lighter(bead.tint, 1.35)
                            strokeWidth: Math.max(1.5, root.u(2))
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: bead.width / 2; centerY: bead.height / 2
                                radiusX: bead.width / 2 - root.u(1); radiusY: radiusX
                                startAngle: -90
                                sweepAngle: Math.min(5, bead.modelData.unread) / 5 * 360
                            }
                        }
                    }
                    MouseArea {
                        id: beadArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = mapToGlobal(0, 0)
                            Shell.open("control", Screen.name, { x: p.x, y: p.y, width: width, height: height }, { group: bead.modelData.key })
                            Notify.markSeen(bead.modelData.key)
                        }
                    }
                }
            }
        }

        // the apps' icons. One with news (unseen notifications, or asking for you) stands on its own; the
        // quiet ones (open in the background, nothing new) sit in a stack of stairs that fans out under the
        // pointer. News slides an app out of the stack, and once it's been seen the app steps back in.
        Item {
            id: apps
            readonly property real slot: root.u(28)
            readonly property real step: root.u(11)     // how much of a stacked icon shows past the one in front
            readonly property real rise: root.u(2)      // each step stands this much higher
            readonly property int glide: Tokens.ms(380)
            property int quiet: 0                       // icons in the stack
            property int loud: 0                        // icons on their own
            // under the pointer: each icon's own hover. Not a HoverHandler on this item: Qt drops an ancestor's
            // hover whenever icons slide under a still pointer, and the stack flapped open and shut. It folds
            // back a moment after the pointer has really gone.
            property bool fanned: false
            function hoverCheck() {
                let any = false
                for (let i = 0; i < appIcons.count; i++) {
                    const it = appIcons.itemAt(i)
                    if (it && it.shown && it.hovered) any = true
                }
                if (any) { settle.stop(); fanned = true } else settle.restart()
            }
            Timer { id: settle; interval: Tokens.ms(220); onTriggered: apps.fanned = false }
            readonly property bool stacked: quiet > 1 && !fanned
            readonly property real stackWidth: quiet === 0 ? 0 : stacked ? slot + (quiet - 1) * step : quiet * slot
            property real shownWidth: stackWidth + loud * slot
            Behavior on shownWidth { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
            visible: quiet + loud > 0
            Layout.fillHeight: true
            Layout.preferredWidth: visible ? shownWidth : 0
            // who goes where: the stack first, in the tray's order, then the ones with news
            function relayout() {
                let q = 0, l = 0
                for (let i = 0; i < appIcons.count; i++) {
                    const it = appIcons.itemAt(i)
                    if (!it || !it.shown) continue
                    it.place = it.news ? { stack: false, i: l++ } : { stack: true, i: q++ }
                }
                quiet = q
                loud = l
                if (Shell.debug) { console.warn("ATOM tray stack", q, "alone", l); report.restart() }
            }
            Component.onCompleted: Qt.callLater(relayout)
            onStackedChanged: if (Shell.debug) { console.warn("ATOM tray stacked", stacked); report.restart() }
            Timer {     // tests (Shell.debug): where each icon ends up once it has glided there
                id: report
                interval: apps.glide + 80
                onTriggered: {
                    for (let i = 0; i < appIcons.count; i++) {
                        const it = appIcons.itemAt(i)
                        if (!it || !it.shown) continue
                        const p = it.mapToGlobal(it.width / 2, it.height / 2)
                        console.warn("ATOM tray at", it.appId, Math.round(p.x), Math.round(p.y), it.place.stack ? "stack" : "alone", apps.stacked ? "stacked" : "open")
                    }
                }
            }

            Repeater {
                id: appIcons
                model: Tray
                onItemAdded: Qt.callLater(apps.relayout)
                onItemRemoved: Qt.callLater(apps.relayout)
                // Plasma's tooltip wraps the icon's MouseArea (inside it, a hover item on top would make the
                // MouseArea an ancestor, whose hover Qt drops when icons slide under a still pointer)
                delegate: PlasmaCore.ToolTipArea {
                    id: app
                    required property int index
                    required property string key
                    required property string appId
                    required property string title
                    required property string status
                    required property string iconName
                    required property string iconSource
                    required property string tooltip
                    required property bool itemIsMenu
                    required property bool hasMenu
                    required property int pid
                    readonly property bool shown: status !== "Passive"
                    // the names it may go by: its tray id ("discord_status_icon_1" -> "discord"), its title, its window's app id
                    readonly property var names: {
                        const _ = Windows.tasks.count
                        const n = [String(appId).replace(/_status_icon(_\d+)?$/i, ""), title]
                        const w = Windows.appIdOf(pid, n)
                        if (w) n.push(w)
                        return n
                    }
                    readonly property bool news: status === "NeedsAttention" || Notify.unreadFor(names) > 0
                    onShownChanged: Qt.callLater(apps.relayout)
                    onNewsChanged: Qt.callLater(apps.relayout)
                    readonly property bool hovered: area.containsMouse
                    onHoveredChanged: apps.hoverCheck()
                    property var place: ({ stack: true, i: 0 })
                    readonly property bool squeezed: place.stack && apps.stacked
                    visible: shown
                    width: apps.slot
                    height: apps.height
                    x: !place.stack ? apps.stackWidth + place.i * apps.slot : squeezed ? place.i * apps.step : place.i * apps.slot
                    y: squeezed ? ((apps.quiet - 1) / 2 - place.i) * apps.rise : 0
                    z: place.stack ? apps.quiet - place.i : 0      // the lowest step in front
                    Behavior on x { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
                    Behavior on y { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
                    readonly property var lines: String(tooltip || title).split("\n")
                    mainText: squeezed ? "" : lines[0]
                    subText: squeezed ? "" : lines.slice(1).join("\n")
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.u(26); height: width; radius: width / 2
                        color: C.alpha(pal.fg, app.squeezed ? 0 : area.pressed ? 0.16 : area.containsMouse ? 0.1 : 0)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    }
                    Rectangle {     // in the stack: a dark glass chip, so each icon stands apart from the one behind it
                        anchors.centerIn: parent
                        width: root.u(24); height: width; radius: width / 2
                        color: C.alpha(pal.surfaceLowest, 0.92)
                        border.width: 1
                        border.color: C.alpha(pal.edge, 0.16)
                        opacity: app.squeezed ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
                    }
                    Item {
                        anchors.centerIn: parent
                        width: root.u(18); height: width
                        scale: (area.pressed ? 0.9 : 1) * (app.squeezed ? 0.84 : 1)
                        Behavior on scale { NumberAnimation { duration: Tokens.fast } }
                        // a themed name, or the app's own picture as a data: URL (Electron apps: Discord, Slack).
                        // Kirigami.Icon can't load data: URLs (it shows the "unknown" sheet), so those go to an Image.
                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: app.iconSource === ""
                            source: visible ? app.iconName : ""
                        }
                        Image {
                            anchors.fill: parent
                            visible: app.iconSource !== ""
                            source: app.iconSource
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }
                    }
                    Rectangle {     // it wants you
                        visible: app.status === "NeedsAttention"
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.u(4) }
                        width: root.u(5); height: width; radius: width / 2
                        color: pal.primary
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        function globalRect() { const p = mapToGlobal(0, 0); return { x: p.x, y: p.y, width: width, height: height } }
                        onClicked: mouse => {
                            if (Shell.debug) console.warn("ATOM tray click", app.appId, mouse.button, "window", Windows.windowOf(app.pid, app.names))
                            const p = mapToGlobal(mouse.x, mouse.y)
                            if (mouse.button === Qt.MiddleButton) Tray.secondaryActivate(app.index, p.x, p.y)
                            else if (mouse.button === Qt.RightButton || app.itemIsMenu) {
                                if (app.hasMenu) Shell.toggle("traymenu", Screen.name, globalRect(), { key: app.key })
                                else Tray.contextMenu(app.index, p.x, p.y)
                            }
                            // its window comes back (or goes down when it has the focus); with none, the app opens one
                            else if (!Windows.summon(app.pid, app.names)) Tray.activate(app.index, p.x, p.y)
                        }
                        onWheel: wheel => Tray.scroll(app.index, wheel.angleDelta.y || wheel.angleDelta.x, wheel.angleDelta.y === 0)
                    }
                }
            }
        }
        // the room's lights (the bedside lamp, the LED strip), only when home: lit while any is on
        Island {
            id: roomBtn
            kind: "room"
            visible: RoomLight.present
            Layout.preferredWidth: root.u(28)
            Layout.fillHeight: true
            cursorShape: Qt.PointingHandCursor
            property real wheelRest: 0
            onWheel: wheel => {
                wheelRest += wheel.angleDelta.y                 // a notch is 120; touchpads send many small ones
                const notches = Math.trunc(wheelRest / 120)
                if (notches === 0) return
                wheelRest -= notches * 120
                RoomLight.nudge(notches * 5)
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.u(26); height: width; radius: width / 2
                color: C.alpha(roomBtn.open ? pal.primary : pal.fg, roomBtn.open ? 0.22 : roomBtn.pressed ? 0.16 : roomBtn.containsMouse ? 0.1 : 0)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Text {
                anchors.centerIn: parent
                text: "lightbulb"
                color: roomBtn.open ? pal.primary : RoomLight.anyOn ? pal.fg : pal.muted
                font.family: Tokens.font.icons
                font.pixelSize: root.u(18)
                scale: roomBtn.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.fast } }
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            MouseArea {         // the middle button: every light on or off (left clicks fall through to the island)
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                onClicked: RoomLight.setAll(!RoomLight.anyOn)
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                active: !roomBtn.open
                mainText: "Room light"
                subText: "Lamp: " + RoomLight.lampSummary.toLowerCase() + "  ·  strip: " + RoomLight.stripSummary.toLowerCase()
                         + "\nMiddle-click: all on or off  ·  wheel: dim"
            }
        }
        Rectangle {     // between the apps and the system
            visible: Tray.count > 0 || roomBtn.visible
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.u(16)
            Layout.leftMargin: root.u(4)
            Layout.rightMargin: root.u(2)
            color: C.alpha(pal.fg, 0.18)
        }

        // the system: one island, opens the control center
        Island {
            id: sys
            kind: "control"
            Layout.fillHeight: true
            Layout.preferredWidth: glyphRow.implicitWidth + root.u(12)
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: root.u(5)
                anchors.bottomMargin: root.u(5)
                radius: height / 2
                color: C.alpha(sys.open ? pal.primary : pal.fg, sys.open ? 0.22 : sys.containsMouse ? 0.08 : 0)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Row {
                id: glyphRow
                anchors.centerIn: parent
                spacing: root.u(7)
                Repeater {
                    model: root.glyphs
                    Text {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.g
                        color: sys.open ? pal.primary : modelData.c
                        font.family: Tokens.font.icons
                        font.pixelSize: root.u(18)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    }
                }
            }
        }
        Item { implicitWidth: root.u(Tokens.space.xs) }
    }
    // never shown (the panels are the shell's), but a panel applet draws nothing without one
    fullRepresentation: Item {}
}
