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
// sheet, the middle button its second action, the wheel scrolls it; the quiet ones rest in a stack that
// opens their panel), the room's lights when home (Atom RoomLight: a click opens the Room panel, the middle
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

    // an app's tray icon: a themed name, or its own picture as a data: URL (Electron apps: Discord, Slack).
    // Kirigami.Icon can't load data: URLs (it shows the "unknown" sheet), so those go to an Image.
    component AppIcon: Item {
        property string iconName: ""
        property string iconSource: ""
        Kirigami.Icon {
            anchors.fill: parent
            visible: parent.iconSource === ""
            source: visible ? parent.iconName : ""
        }
        Image {
            anchors.fill: parent
            visible: parent.iconSource !== ""
            source: parent.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    // ------------------------------------------------------------------ the apps' panel
    // On the shell's sheet (Atom panels/Portal.qml makes it there, in this widget's context), grown out of
    // the stack (or a bead: its app's group lit): the notifications by app (Atom Notify; a click runs one,
    // ✕ clears an app's, Clear all), then one row per app in the stack: a click brings the app's window back
    // (or opens the app), a right click (or ⋯) its menu, the middle button its second action.
    property Item stack: null                   // the bar's apps (the compact representation's)
    readonly property string myScreenName: root.Window.window ? Screen.name : ""
    readonly property bool appsOpen: Shell.kind === "apps" && Shell.screen === myScreenName
    onMyScreenNameChanged: Shell.portal(myScreenName, "apps", appsPopup)
    Component.onCompleted: Shell.portal(myScreenName, "apps", appsPopup)
    // a name to show: the icon's title, else its id made readable ("discord_status_icon_1" -> "Discord")
    function appName(appId, title) {
        if (title && title !== appId) return title
        const id = String(appId || "").replace(/_status_icon(_\d+)?$/i, "").replace(/[-_]+/g, " ").trim()
        return id ? id.charAt(0).toUpperCase() + id.slice(1) : "App"
    }
    function appMenu(row) {
        if (row.hasMenu) Shell.open("traymenu", myScreenName, stack ? stack.island.globalRect() : null, { key: row.key })
        else { Shell.close("apps"); const p = row.mapToGlobal(0, 0); Tray.contextMenu(row.index, p.x, p.y) }
    }
    property Component appsPopup: Component {
        Item {
            id: ap
            implicitWidth: root.u(360)
            implicitHeight: apCol.implicitHeight + 2 * root.u(Tokens.space.lg)
            readonly property string focusGroup: root.appsOpen && Shell.args ? (Shell.args.group || "") : ""
            readonly property int quiet: root.stack ? root.stack.quiet : 0

            PopupIn {
                anchors.fill: parent
                active: root.appsOpen
                ricePalette: pal

                ColumnLayout {
                    id: apCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.u(Tokens.space.lg) }
                    spacing: root.u(Tokens.space.md)

                    PopupHeader {
                        Layout.fillWidth: true
                        palette: pal
                        title: "Apps"
                        subtitle: [Notify.unreadTotal > 0 ? Notify.unreadTotal + " new" : Notify.groups.length > 0 ? "Nothing new" : "No notifications"]
                                  .concat(ap.quiet > 0 ? [ap.quiet + " in the background"] : []).join("  ·  ")
                    }

                    // the notifications, by app, newest first
                    RowLayout {
                        Layout.fillWidth: true
                        visible: Notify.groups.length > 0
                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: pal.muted
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: root.u(11)
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.6
                        }
                        Text {
                            text: "Clear all"
                            color: clearAllM.containsMouse ? pal.fg : pal.primary
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: root.u(11)
                            MouseArea { id: clearAllM; anchors.fill: parent; anchors.margins: -root.u(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notify.clearAll() }
                        }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, root.u(330))
                        visible: Notify.groups.length > 0
                        contentHeight: groupsCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: groupsCol
                            width: parent.width
                            spacing: root.u(8)
                            Repeater {
                                id: groupCards
                                model: Notify.groups
                                delegate: Rectangle {
                                    id: grp
                                    required property var modelData
                                    readonly property bool focused: ap.focusGroup === modelData.key
                                    property Item closer: closeGlyph
                                    width: groupsCol.width
                                    implicitHeight: gcol.implicitHeight + root.u(16)
                                    radius: root.u(16)
                                    color: C.alpha(focused ? pal.primary : pal.fg, focused ? 0.12 : 0.045)
                                    border.width: 1
                                    border.color: focused ? C.alpha(pal.primary, 0.45) : C.alpha(pal.edge, Tokens.alpha.outline)
                                    Column {
                                        id: gcol
                                        x: root.u(10); y: root.u(8)
                                        width: parent.width - root.u(20)
                                        spacing: root.u(4)
                                        RowLayout {
                                            width: parent.width
                                            spacing: root.u(8)
                                            Kirigami.Icon { implicitWidth: root.u(18); implicitHeight: implicitWidth; source: grp.modelData.icon }
                                            Text {
                                                Layout.fillWidth: true
                                                text: grp.modelData.name + (grp.modelData.unread > 0 ? "  ·  " + grp.modelData.unread + " new" : "")
                                                elide: Text.ElideRight
                                                color: pal.fg
                                                font.family: Tokens.font.ui
                                                font.weight: Font.DemiBold
                                                font.pixelSize: root.u(12)
                                            }
                                            Text {
                                                id: closeGlyph
                                                text: "close"
                                                color: gx.containsMouse ? pal.fg : pal.muted
                                                font.family: Tokens.font.icons
                                                font.pixelSize: root.u(16)
                                                MouseArea { id: gx; anchors.fill: parent; anchors.margins: -root.u(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notify.clearApp(grp.modelData.key) }
                                            }
                                        }
                                        Repeater {
                                            model: grp.modelData.items.slice(0, 3)
                                            delegate: Rectangle {
                                                id: item
                                                required property var modelData
                                                width: gcol.width
                                                implicitHeight: icol.implicitHeight + root.u(10)
                                                radius: root.u(10)
                                                color: im.containsMouse ? C.alpha(pal.fg, 0.07) : "transparent"
                                                Column {
                                                    id: icol
                                                    x: root.u(26); y: root.u(5)
                                                    width: parent.width - root.u(54)
                                                    Text { width: parent.width; text: item.modelData.summary; elide: Text.ElideRight; color: pal.fg; font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: root.u(12) }
                                                    Text { width: parent.width; visible: text !== ""; text: item.modelData.body; textFormat: Text.StyledText; elide: Text.ElideRight; maximumLineCount: 1; color: pal.fgDim; font.family: Tokens.font.ui; font.pixelSize: root.u(12) }
                                                }
                                                Text {
                                                    anchors { right: parent.right; rightMargin: root.u(4); top: parent.top; topMargin: root.u(6) }
                                                    text: Qt.formatTime(item.modelData.created, "HH:mm")
                                                    color: pal.muted
                                                    font.family: Tokens.font.ui
                                                    font.pixelSize: root.u(10)
                                                }
                                                MouseArea {
                                                    id: im
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: item.modelData.hasDefault ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: { if (item.modelData.hasDefault) { Notify.activate(item.modelData.row); Shell.close() } }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // the quiet apps, one row each
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Notify.groups.length > 0 ? root.u(4) : 0
                        visible: ap.quiet > 0
                        text: "In the background"
                        color: pal.muted
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: root.u(11)
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.u(6)
                        Repeater {
                            id: rows
                            model: Tray
                            delegate: Rectangle {
                                id: row
                                required property int index
                                required property string key
                                required property string appId
                                required property string title
                                required property string tooltip
                                required property string iconName
                                required property string iconSource
                                required property bool itemIsMenu
                                required property bool hasMenu
                                required property int pid
                                // its icon on the bar: whether it's in the stack, and the names its window goes by
                                readonly property Item twin: root.stack ? root.stack.icons.itemAt(index) : null
                                visible: !!twin && twin.shown && twin.place.stack
                                readonly property string name: root.appName(appId, title)
                                readonly property string detail: {
                                    const _ = Windows.tasks.count
                                    const w = Windows.stateOf(pid, twin ? twin.names : [])
                                    const extra = String(tooltip || "").split("\n").filter(l => l && l.toLowerCase() !== name.toLowerCase())
                                    return [w === "minimized" ? "Minimized" : w ? "Open" : "In the tray"].concat(extra).join("  ·  ")
                                }
                                readonly property bool lit: rowArea.containsMouse || moreArea.containsMouse
                                Layout.fillWidth: true
                                implicitHeight: root.u(50)
                                radius: root.u(14)
                                color: C.alpha(pal.fg, rowArea.pressed ? 0.1 : lit ? 0.07 : 0.035)
                                border.width: 1
                                border.color: C.alpha(pal.edge, Tokens.alpha.outline)
                                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    onClicked: mouse => {
                                        const p = mapToGlobal(mouse.x, mouse.y)
                                        if (mouse.button === Qt.MiddleButton) { Tray.secondaryActivate(row.index, p.x, p.y); return }
                                        if (mouse.button === Qt.RightButton || row.itemIsMenu) { root.appMenu(row); return }
                                        if (Shell.debug) console.warn("ATOM apps pick", row.appId)
                                        Shell.close("apps")
                                        // the sheet has the focus, so the window comes back (or the app opens)
                                        if (!Windows.summon(row.pid, row.twin ? row.twin.names : [])) Tray.activate(row.index, p.x, p.y)
                                    }
                                    onWheel: wheel => Tray.scroll(row.index, wheel.angleDelta.y || wheel.angleDelta.x, wheel.angleDelta.y === 0)
                                }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: root.u(12); rightMargin: root.u(8) }
                                    spacing: root.u(12)
                                    AppIcon {
                                        Layout.preferredWidth: root.u(26)
                                        Layout.preferredHeight: root.u(26)
                                        iconName: row.iconName
                                        iconSource: row.iconSource
                                        scale: rowArea.pressed ? 0.92 : 1
                                        Behavior on scale { NumberAnimation { duration: Tokens.fast } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.u(1)
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.name
                                            elide: Text.ElideRight
                                            color: pal.fg
                                            font.family: Tokens.font.ui
                                            font.weight: Font.DemiBold
                                            font.pixelSize: root.u(13)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.detail
                                            elide: Text.ElideRight
                                            color: pal.fgDim
                                            font.family: Tokens.font.ui
                                            font.pixelSize: root.u(11)
                                        }
                                    }
                                    Text {      // its menu, for when a right click isn't what comes to mind
                                        visible: row.hasMenu
                                        Layout.preferredWidth: root.u(26)
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "more_horiz"
                                        color: moreArea.containsMouse ? pal.fg : row.lit ? pal.fgDim : pal.muted
                                        font.family: Tokens.font.icons
                                        font.pixelSize: root.u(18)
                                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                        MouseArea {
                                            id: moreArea
                                            anchors.fill: parent
                                            anchors.margins: -root.u(4)
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.appMenu(row)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Timer {     // tests (Shell.debug): where each row is, once the sheet has grown
                running: Shell.debug
                interval: 900
                onTriggered: {
                    for (let i = 0; i < rows.count; i++) {
                        const r = rows.itemAt(i)
                        if (!r || !r.visible) continue
                        const p = r.mapToGlobal(r.width / 2, r.height / 2)
                        console.warn("ATOM apps row", r.appId, Math.round(p.x), Math.round(p.y))
                    }
                    for (let i = 0; i < groupCards.count; i++) {
                        const g = groupCards.itemAt(i)
                        if (!g) continue
                        const p = g.closer.mapToGlobal(g.closer.width / 2, g.closer.height / 2)
                        console.warn("ATOM apps group", g.modelData.key, "close", Math.round(p.x), Math.round(p.y), g.focused ? "lit" : "")
                    }
                }
            }
        }
    }

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
                            Shell.open("apps", Screen.name, { x: p.x, y: p.y, width: width, height: height }, { group: bead.modelData.key })
                            Notify.markSeen(bead.modelData.key)
                        }
                    }
                }
            }
        }

        // the apps' icons. One with news (unseen notifications, or asking for you) stands on its own; the
        // quiet ones (open in the background, nothing new) rest on each other in a stack of stairs, one island:
        // a click opens their panel on the shell's sheet, like the control center's. News slides an app out of
        // the stack, and once it's been seen the app steps back in.
        Item {
            id: apps
            property alias icons: appIcons
            property alias island: stackIsland
            readonly property real slot: root.u(28)
            readonly property real step: root.u(9)      // how much of a stacked icon shows past the one in front
            readonly property real rise: root.u(2)      // each step stands this much higher
            readonly property int glide: Tokens.ms(380)
            property int quiet: 0                       // icons in the stack
            property int loud: 0                        // icons on their own
            // the island opens the apps' panel, the notifications' home too: a lone quiet app is just an icon
            // unless there's history to reach, and with no quiet app at all a bell stands in for the stack
            readonly property bool history: Notify.groups.length > 0
            readonly property bool stacked: quiet > 1 || (quiet === 1 && history)
            readonly property bool bell: quiet === 0 && history
            readonly property real stackWidth: quiet === 0 ? (bell ? slot : 0) : stacked ? slot + (quiet - 1) * step : slot
            property real shownWidth: stackWidth + loud * slot
            Behavior on shownWidth { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
            visible: quiet + loud > 0 || bell
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
            Component.onCompleted: { root.stack = apps; Qt.callLater(relayout) }
            Timer {     // tests (Shell.debug): where each icon ends up once it has glided there
                id: report
                interval: apps.glide + 80
                onTriggered: {
                    for (let i = 0; i < appIcons.count; i++) {
                        const it = appIcons.itemAt(i)
                        if (!it || !it.shown) continue
                        const p = it.mapToGlobal(it.width / 2, it.height / 2)
                        console.warn("ATOM tray at", it.appId, Math.round(p.x), Math.round(p.y), it.place.stack ? "stack" : "alone")
                    }
                    if (stackIsland.visible) {
                        const c = stackIsland.mapToGlobal(stackIsland.width / 2, stackIsland.height / 2)
                        console.warn("ATOM tray island", Math.round(c.x), Math.round(c.y))
                    }
                }
            }

            Rectangle {     // the stack's island lights up under the pointer, and in the accent while its panel is open
                anchors { fill: stackIsland; topMargin: root.u(5); bottomMargin: root.u(5) }
                visible: stackIsland.visible
                radius: height / 2
                color: C.alpha(stackIsland.open ? pal.primary : pal.fg, stackIsland.open ? 0.22 : stackIsland.pressed ? 0.12 : stackIsland.containsMouse ? 0.08 : 0)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }

            Repeater {
                id: appIcons
                model: Tray
                onItemAdded: Qt.callLater(apps.relayout)
                onItemRemoved: Qt.callLater(apps.relayout)
                // Plasma's tooltip wraps the icon's MouseArea (Qt Quick Controls' tooltips open as popup windows
                // that take the pointer from the bar: the next click only closed the tooltip)
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
                    property var place: ({ stack: true, i: 0 })
                    readonly property bool inStack: place.stack && apps.stacked     // drawn only: the island takes the pointer
                    visible: shown
                    width: apps.slot
                    height: apps.height
                    x: !place.stack ? apps.stackWidth + place.i * apps.slot : inStack ? place.i * apps.step : 0
                    y: inStack ? ((apps.quiet - 1) / 2 - place.i) * apps.rise : 0
                    z: place.stack ? apps.quiet - place.i : 0      // the lowest step in front
                    Behavior on x { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
                    Behavior on y { NumberAnimation { duration: apps.glide; easing.type: Tokens.grow } }
                    readonly property var lines: String(tooltip || title).split("\n")
                    mainText: inStack ? "" : lines[0]
                    subText: inStack ? "" : lines.slice(1).join("\n")
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.u(26); height: width; radius: width / 2
                        color: C.alpha(pal.fg, app.inStack ? 0 : area.pressed ? 0.16 : area.containsMouse ? 0.1 : 0)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    }
                    AppIcon {
                        anchors.centerIn: parent
                        width: root.u(18); height: width
                        iconName: app.iconName
                        iconSource: app.iconSource
                        scale: area.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.fast } }
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
                        enabled: !app.inStack
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

            Text {      // no quiet app, only the notifications' history: the bell is the island
                visible: apps.bell
                width: apps.slot
                height: apps.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "notifications"
                color: stackIsland.open ? pal.primary : pal.fg
                font.family: Tokens.font.icons
                font.pixelSize: root.u(18)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            // the stack, as one island over its icons: a click opens the apps' panel (root.appsPopup)
            Island {
                id: stackIsland
                kind: "apps"
                visible: apps.stacked || apps.bell
                z: 1000
                width: apps.stackWidth
                height: apps.height
                cursorShape: Qt.PointingHandCursor
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
