import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.volume as Vol
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.brightnesscontrolplugin as Bright
import org.kde.plasma.private.batterymonitor as Batt
import org.kde.notificationmanager as NM
import org.kde.plasma.workspace.dbus as DBus
import Atom
import "../../Rice"
import "../../Rice/Color.js" as C
import "parts"

// The control center (the status island's panel): quick toggles (Wi-Fi, Bluetooth, Do Not Disturb, night
// light, the power profile, the battery saver), levels (volume, microphone, every screen's brightness),
// what's playing, the apps' own volumes, the room's lights when home (their arrow: the Room panel). Wi-Fi,
// Bluetooth and the audio output open their own page in place (the sheet reshapes around it). Esc steps
// back, then closes.
FocusScope {
    id: cc
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette
    function u(n) { return Math.round(n * ui) }

    readonly property real colW: u(370)
    readonly property real w: 2 * colW + u(24)
    property string page: ""                    // "" (main), "wifi", "bt", "audio"
    implicitWidth: w
    implicitHeight: page === "" ? main.implicitHeight : pageCol.implicitHeight
    Behavior on implicitHeight { enabled: false }

    function enter() { page = ""; room.refresh(); night.read(); forceActiveFocus() }
    Keys.onEscapePressed: event => { if (page) { page = ""; event.accepted = true } else event.accepted = false }

    // ------------------------------------------------------------------ the system
    RiceShell { id: sh; onNewData: (source, data) => { if (source.indexOf("#night") >= 0) { night.read(); nightRecheck.restart() } disconnectSource(source) } }
    function run(cmd, tag) { sh.connectSource(cmd + " #" + (tag || "run")) }

    PlasmaNM.EnabledConnections { id: radios }
    PlasmaNM.NetworkStatus { id: netStatus }
    PlasmaNM.Handler { id: nmHandler }
    readonly property string netName: {
        const s = String(netStatus.activeConnections || "")
        const line = s.split("\n").find(l => l.trim()) || ""
        return line.replace(/^.*?:\s*/, "").replace(/\s*\(.*$/, "").trim()
    }

    readonly property var bt: BluezQt.Manager
    readonly property var btDevices: Array.prototype.slice.call(bt.devices || [])     // a QML list: as an array
    readonly property var btConnected: btDevices.filter(d => d.connected)

    readonly property var sink: Vol.PreferredDevice.sink
    readonly property var source: Vol.PreferredDevice.source
    readonly property int normal: 65536             // PulseAudio's 100 %

    Bright.ScreenBrightnessControl { id: brightness; isSilent: true }
    Batt.PowerProfilesControl { id: profiles; isSilent: true }
    readonly property var profileNames: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })
    readonly property var profileIcons: ({ "power-saver": "eco", "balanced": "balance", "performance": "speed" })

    NM.Settings { id: notifySettings }
    readonly property bool dnd: {
        const u = notifySettings.notificationsInhibitedUntil
        return !!u && !isNaN(u) && u > new Date()
    }
    function setDnd(on) {
        notifySettings.notificationsInhibitedUntil = on ? new Date(Date.now() + 1000 * 3600 * 24 * 365 * 10) : undefined
        if (!on) notifySettings.revokeApplicationInhibitions()
        notifySettings.save()
    }

    // night light: KWin's, switched in its config (it may not be set up at all yet). KWin's night light
    // reloads only on a KConfigWatcher notification (--notify), not on /KWin reconfigure; the key is
    // deleted first so the write always counts as a change and notifies even when the file already held
    // the wanted value but KWin didn't (a write without --notify left them apart once).
    QtObject {
        id: night
        property bool on: false
        function read() {
            const r = DBus.SessionBus.asyncCall({ service: "org.kde.KWin", path: "/org/kde/KWin/NightLight", iface: "org.freedesktop.DBus.Properties",
                member: "Get", arguments: [new DBus.string("org.kde.KWin.NightLight"), new DBus.string("running")], signature: "(ss)" })
            r.finished.connect(() => { if (!r.isError) night.on = r.value === true; r.destroy() })
        }
        function set(want) {
            on = want
            cc.run("kwriteconfig6 --file kwinrc --group NightColor --key Active --delete"
                   + " && kwriteconfig6 --file kwinrc --group NightColor --key Active " + (want ? "true" : "false") + " --notify", "night")
        }
    }
    // KWin handles the notification on its own time: read again a moment after the write's answer
    Timer { id: nightRecheck; interval: 700; onTriggered: night.read() }

    // the battery (laptops), the rice's battery saver
    P5Support.DataSource { engine: "powermanagement"; connectedSources: ["Battery"]; onNewData: (s, d) => cc.batt = d }
    property var batt: ({})
    readonly property bool hasBattery: batt["Has Battery"] === true
    readonly property int charge: Number(batt["Percent"]) || 0
    readonly property bool charging: batt["State"] === "Charging" || batt["State"] === "FullyCharged"
    WatchedJson {
        id: saverFile
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.local/state/rice/battery-saver.json"
    }
    readonly property bool saverOn: !!(saverFile.value && saverFile.value.on)

    // the room's lights (Atom RoomLight, shared with the status island's button and the Room panel)
    readonly property var room: RoomLight
    onVisibleChanged: RoomLight.watch("control/" + screenName, visible)
    Component.onDestruction: RoomLight.watch("control/" + screenName, false)
    function openRoom() { Shell.open("room", cc.screenName, Shell.anchor) }
    NowPlaying { id: music; ticking: false }

    // a row of a list page
    component Row2: Rectangle {
        id: r2
        property var pal
        property real ui: 1
        property string glyph: ""
        property string iconName: ""
        property string title: ""
        property string sub: ""
        property bool on: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: Math.round(52 * ui)
        radius: Math.round(16 * ui)
        color: on ? C.alpha(pal.primary, r2m.containsMouse ? 0.26 : 0.18) : C.alpha(pal.fg, r2m.containsMouse ? 0.09 : 0.04)
        border.width: on ? 1 : 0
        border.color: C.alpha(pal.primary, 0.5)
        Behavior on color { ColorAnimation { duration: Tokens.fast } }
        Text {
            id: r2g
            visible: r2.glyph !== ""
            x: Math.round(14 * r2.ui)
            anchors.verticalCenter: parent.verticalCenter
            text: r2.glyph
            color: r2.on ? r2.pal.primary : r2.pal.fgDim
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(20 * r2.ui)
        }
        Kirigami.Icon {
            id: r2i
            visible: r2.glyph === "" && r2.iconName !== ""
            x: Math.round(12 * r2.ui)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(24 * r2.ui); height: width
            source: r2.iconName
        }
        Column {
            anchors { left: parent.left; leftMargin: Math.round(48 * r2.ui); right: parent.right; rightMargin: Math.round(12 * r2.ui); verticalCenter: parent.verticalCenter }
            Text { width: parent.width; text: r2.title; elide: Text.ElideRight; color: r2.pal.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: Math.round(13 * r2.ui) }
            Text { width: parent.width; visible: text !== ""; text: r2.sub; elide: Text.ElideRight; color: r2.pal.muted; font.family: Tokens.font.ui; font.pixelSize: Math.round(11 * r2.ui) }
        }
        MouseArea { id: r2m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r2.clicked() }
    }


    // ------------------------------------------------------------------ the main page
    RowLayout {
        id: main
        width: cc.w
        spacing: cc.u(24)
        visible: opacity > 0.01
        opacity: cc.page === "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        transform: Translate { x: cc.page === "" ? 0 : -cc.u(24); Behavior on x { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } } }

      // the controls
      ColumnLayout {
        Layout.preferredWidth: cc.colW
        Layout.alignment: Qt.AlignTop
        spacing: cc.u(12)

        // the header: the battery, settings, power
        RowLayout {
            Layout.fillWidth: true
            spacing: cc.u(8)
            Text {
                text: cc.hasBattery ? (cc.charging ? "battery_charging_full" : cc.charge <= 15 ? "battery_alert" : "battery_" + Math.min(6, Math.round(cc.charge / 100 * 6)) + "_bar") : "desktop_windows"
                color: cc.hasBattery && cc.charge <= 15 && !cc.charging ? cc.pal.bad : cc.pal.fgDim
                font.family: Tokens.font.icons
                font.pixelSize: cc.u(20)
            }
            Text {
                Layout.fillWidth: true
                readonly property int mins: Math.round((Number(cc.batt["Smoothed Remaining msec"]) || 0) / 60000)
                text: cc.hasBattery ? cc.charge + "%" + (cc.charging ? "  ·  charging" : mins > 0 ? "  ·  " + Math.floor(mins / 60) + " h " + (mins % 60) + " min left" : "")
                                    : Qt.formatDate(new Date(), "dddd, d MMMM")
                color: cc.pal.fg
                elide: Text.ElideRight
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: cc.u(13)
            }
            Repeater {
                model: [{ glyph: "settings", tip: "System Settings", act: "settings" }, { glyph: "power_settings_new", tip: "Power", act: "power" }]
                delegate: Rectangle {
                    id: hb
                    required property var modelData
                    implicitWidth: cc.u(34); implicitHeight: implicitWidth; radius: implicitWidth / 2
                    color: C.alpha(cc.pal.fg, hm.containsMouse ? 0.13 : 0.06)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Text {
                        anchors.centerIn: parent
                        text: hb.modelData.glyph
                        color: hm.containsMouse && hb.modelData.act === "power" ? cc.pal.bad : cc.pal.fg
                        font.family: Tokens.font.icons
                        font.pixelSize: cc.u(18)
                    }
                    MouseArea {
                        id: hm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (hb.modelData.act === "settings") { Shell.close(); cc.run("systemsettings") }
                            else Shell.open("power", cc.screenName, Shell.anchor)
                        }
                    }
                }
            }
        }

        // the toggles
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: cc.u(8)
            columnSpacing: cc.u(8)
            Tile {
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: radios.wirelessEnabled ? "wifi" : "wifi_off"
                label: "Wi-Fi"
                sub: !radios.wirelessEnabled ? "Off" : cc.netName || "On"
                on: radios.wirelessEnabled
                more: true
                onToggled: nmHandler.enableWireless(!radios.wirelessEnabled)
                onOpened: { nmHandler.requestScan(""); cc.page = "wifi" }
            }
            Tile {
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: cc.bt.bluetoothOperational ? (cc.btConnected.length ? "bluetooth_connected" : "bluetooth") : "bluetooth_disabled"
                label: "Bluetooth"
                sub: !cc.bt.bluetoothOperational ? "Off" : cc.btConnected.length ? cc.btConnected.map(d => d.name).join(", ") : "On"
                on: cc.bt.bluetoothOperational
                more: true
                onToggled: cc.bt.bluetoothBlocked = !cc.bt.bluetoothBlocked
                onOpened: cc.page = "bt"
            }
            Tile {
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: cc.dnd ? "do_not_disturb_on" : "notifications"
                label: "Do Not Disturb"
                sub: cc.dnd ? "Silenced" : "Off"
                on: cc.dnd
                onToggled: cc.setDnd(!cc.dnd)
            }
            Tile {
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: "nightlight"
                label: "Night light"
                sub: night.on ? "Warm" : "Off"
                on: night.on
                onToggled: night.set(!night.on)
            }
            Tile {
                Layout.fillWidth: true
                visible: (profiles.profiles || []).length > 0
                pal: cc.pal; ui: cc.ui
                readonly property string prof: profiles.activeProfile || "balanced"
                icon: cc.profileIcons[prof] || "balance"
                label: "Power profile"
                sub: cc.profileNames[prof] || prof
                on: prof !== "balanced"
                onToggled: {       // power saver -> balanced -> performance -> power saver
                    const order = ["power-saver", "balanced", "performance"].filter(p => (profiles.profiles || []).some(x => (x.Profile || x.profile || x) === p))
                    const next = order[(order.indexOf(prof) + 1) % order.length]
                    if (next) profiles.setProfile(next)
                }
            }
            Tile {
                Layout.fillWidth: true
                visible: cc.hasBattery
                pal: cc.pal; ui: cc.ui
                icon: "eco"
                label: "Battery saver"
                sub: cc.saverOn ? "On" : "Off"
                on: cc.saverOn
                onToggled: cc.run('python3 "$HOME/.config/plasma-rice/battery-saver.py" ' + (cc.saverOn ? "off" : "on"))
            }
        }

        // the levels
        Level {
            Layout.fillWidth: true
            visible: !!cc.sink
            pal: cc.pal; ui: cc.ui
            icon: !cc.sink || cc.sink.muted ? "volume_off" : cc.sink.volume > cc.normal * 0.6 ? "volume_up" : "volume_down"
            label: cc.sink ? (cc.sink.description || cc.sink.name) : ""
            value: cc.sink ? cc.sink.volume / cc.normal : 0
            dim: !!cc.sink && cc.sink.muted
            more: true
            onMoved: v => { if (cc.sink) { cc.sink.volume = Math.round(v * cc.normal); if (cc.sink.muted && v > 0) cc.sink.muted = false } }
            onIconClicked: if (cc.sink) cc.sink.muted = !cc.sink.muted
            onOpened: cc.page = "audio"
        }
        Level {
            Layout.fillWidth: true
            visible: !!cc.source
            pal: cc.pal; ui: cc.ui
            icon: !cc.source || cc.source.muted ? "mic_off" : "mic"
            label: cc.source ? (cc.source.description || cc.source.name) : ""
            value: cc.source ? cc.source.volume / cc.normal : 0
            dim: !!cc.source && cc.source.muted
            onMoved: v => { if (cc.source) { cc.source.volume = Math.round(v * cc.normal); if (cc.source.muted && v > 0) cc.source.muted = false } }
            onIconClicked: if (cc.source) cc.source.muted = !cc.source.muted
        }
        Repeater {
            model: brightness.displays
            delegate: Level {
                required property var model
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: "brightness_6"
                // "ASUSTek COMPUTER INC VG27AQA1A" -> "VG27AQA1A": the maker's name says nothing here
                label: String(model.label || model.displayName).replace(/^.*\b(inc|ltd|corp|co|gmbh)\b\.?\s*/i, "")
                value: model.maxBrightness > 0 ? model.brightness / model.maxBrightness : 0
                onMoved: v => brightness.setBrightness(model.displayName, Math.max(1, Math.round(v * model.maxBrightness)))
            }
        }

      }

      Rectangle {     // between the columns
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          color: C.alpha(cc.pal.edge, Tokens.alpha.outline)
      }

      // what's going on: playing, the apps' volumes, the room
      ColumnLayout {
        Layout.preferredWidth: cc.colW
        Layout.alignment: Qt.AlignTop
        spacing: cc.u(12)

        // what's playing
        Rectangle {
            Layout.fillWidth: true
            visible: music.present
            implicitHeight: cc.u(72)
            radius: cc.u(18)
            color: C.alpha(cc.pal.fg, 0.055)
            border.width: 1
            border.color: C.alpha(cc.pal.edge, Tokens.alpha.outline)
            Kirigami.ShadowedImage {
                id: art
                x: cc.u(10)
                anchors.verticalCenter: parent.verticalCenter
                width: cc.u(52); height: width
                radius: cc.u(12)
                color: C.alpha(cc.pal.fg, 0.08)
                source: music.artUrl
                fillMode: Image.PreserveAspectCrop
            }
            Column {
                anchors { left: art.right; leftMargin: cc.u(12); right: ctl.left; rightMargin: cc.u(8); verticalCenter: parent.verticalCenter }
                Text { width: parent.width; text: music.track; elide: Text.ElideRight; color: cc.pal.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: cc.u(13) }
                Text { width: parent.width; text: music.artist; elide: Text.ElideRight; color: cc.pal.fgDim; font.family: Tokens.font.ui; font.pixelSize: cc.u(12) }
            }
            Row {
                id: ctl
                anchors { right: parent.right; rightMargin: cc.u(10); verticalCenter: parent.verticalCenter }
                spacing: cc.u(2)
                Repeater {
                    model: [{ g: "skip_previous", a: 0 }, { g: music.playing ? "pause" : "play_arrow", a: 1 }, { g: "skip_next", a: 2 }]
                    delegate: Rectangle {
                        id: mb
                        required property var modelData
                        width: cc.u(mb.modelData.a === 1 ? 38 : 32); height: width; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: mb.modelData.a === 1 ? C.alpha(cc.pal.primary, mbm.containsMouse ? 0.4 : 0.28) : C.alpha(cc.pal.fg, mbm.containsMouse ? 0.12 : 0)
                        Text { anchors.centerIn: parent; text: mb.modelData.g; color: cc.pal.fg; font.family: Tokens.font.icons; font.pixelSize: cc.u(20) }
                        MouseArea {
                            id: mbm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mb.modelData.a === 0 ? music.prev() : mb.modelData.a === 1 ? music.toggle() : music.next()
                        }
                    }
                }
            }
        }

        // the apps' own volumes
        Text {
            visible: apps.count > 0
            text: "Apps"
            color: cc.pal.muted
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: cc.u(11)
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }
        Repeater {
            id: apps
            model: Vol.SinkInputModel {}
            delegate: Level {
                required property var model
                readonly property var po: model.PulseObject
                Layout.fillWidth: true
                pal: cc.pal; ui: cc.ui
                icon: po && po.muted ? "volume_off" : "graphic_eq"
                label: po ? ((po.client && po.client.name) || po.name) : ""
                value: po ? po.volume / cc.normal : 0
                dim: !!po && po.muted
                onMoved: v => { if (po) po.volume = Math.round(v * cc.normal) }
                onIconClicked: if (po) po.muted = !po.muted
            }
        }

        // the room's lights (at home): levels here, everything else on the Room panel (the arrow)
        RowLayout {
            Layout.fillWidth: true
            visible: room.present
            Text {
                Layout.fillWidth: true
                text: "Room"
                color: cc.pal.muted
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: cc.u(11)
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
            }
            Text {
                text: "Colours & more"
                color: roomMore.containsMouse ? cc.pal.fg : cc.pal.primary
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: cc.u(11)
                MouseArea { id: roomMore; anchors.fill: parent; anchors.margins: -cc.u(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cc.openRoom() }
            }
        }
        Level {
            Layout.fillWidth: true
            visible: room.present && room.lampReachable
            pal: cc.pal; ui: cc.ui
            icon: room.lampOn ? "light" : "light_off"
            label: "Bedside lamp" + (room.lampOn ? "" : "  ·  off")
            value: room.lampBright / 100
            dim: !room.lampOn
            onMoved: v => room.setLampBright(v * 100)
            onIconClicked: room.setLamp(!room.lampOn)
        }
        Level {
            Layout.fillWidth: true
            visible: room.present && room.roomReachable
            pal: cc.pal; ui: cc.ui
            icon: room.stripTrouble ? "bluetooth_disabled" : "wb_iridescent"
            label: "LED strip" + (room.stripTrouble ? "  ·  can't reach it" : room.stripOn ? "" : "  ·  off")
            value: room.stripBright / 100
            dim: !room.stripOn || room.stripTrouble
            onMoved: v => room.setStripBright(v * 100)
            onIconClicked: room.setStrip(!room.stripOn)
        }
        // nothing going on
        Column {
            Layout.fillWidth: true
            Layout.topMargin: cc.u(30)
            visible: !music.present && apps.count === 0 && !room.present
            spacing: cc.u(6)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "self_care"; color: C.alpha(cc.pal.fg, 0.25); font.family: Tokens.font.icons; font.pixelSize: cc.u(34) }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "All quiet"; color: cc.pal.muted; font.family: Tokens.font.ui; font.pixelSize: cc.u(13) }
        }
      }
    }

    // ------------------------------------------------------------------ the pages (Wi-Fi, Bluetooth, outputs)
    ColumnLayout {
        id: pageCol
        x: Math.round((cc.w - width) / 2)
        width: cc.colW + cc.u(60)
        spacing: cc.u(10)
        visible: opacity > 0.01
        opacity: cc.page !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        transform: Translate { x: cc.page !== "" ? 0 : cc.u(24); Behavior on x { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } } }

        RowLayout {
            Layout.fillWidth: true
            spacing: cc.u(8)
            Rectangle {
                implicitWidth: cc.u(34); implicitHeight: implicitWidth; radius: implicitWidth / 2
                color: C.alpha(cc.pal.fg, backM.containsMouse ? 0.13 : 0.06)
                Text { anchors.centerIn: parent; text: "arrow_back"; color: cc.pal.fg; font.family: Tokens.font.icons; font.pixelSize: cc.u(18) }
                MouseArea { id: backM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cc.page = "" }
            }
            Text {
                Layout.fillWidth: true
                text: cc.page === "wifi" ? "Wi-Fi" : cc.page === "bt" ? "Bluetooth" : "Sound output"
                color: cc.pal.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: cc.u(18)
            }
            Rectangle {     // more settings for this page
                implicitWidth: cc.u(34); implicitHeight: implicitWidth; radius: implicitWidth / 2
                color: C.alpha(cc.pal.fg, kcmM.containsMouse ? 0.13 : 0.06)
                Text { anchors.centerIn: parent; text: "tune"; color: cc.pal.fg; font.family: Tokens.font.icons; font.pixelSize: cc.u(18) }
                MouseArea {
                    id: kcmM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Shell.close(); cc.run("systemsettings " + (cc.page === "wifi" ? "kcm_networkmanagement" : cc.page === "bt" ? "kcm_bluetooth" : "kcm_pulseaudio")) }
                }
            }
        }

        // Wi-Fi: the networks around, the known ones connect with a click (others: System Settings)
        PlasmaNM.NetworkModel { id: nets }
        PlasmaNM.AppletProxyModel { id: netList; sourceModel: cc.page === "wifi" ? nets : null }
        Repeater {
            model: cc.page === "wifi" ? netList : null
            delegate: Row2 {
                required property var model
                readonly property bool wifi: model.Type === PlasmaNM.Enums.Wireless
                readonly property bool active: model.ConnectionState === PlasmaNM.Enums.Activated
                readonly property bool busy: model.ConnectionState === PlasmaNM.Enums.Activating
                visible: wifi
                Layout.preferredHeight: wifi ? implicitHeight : 0
                pal: cc.pal; ui: cc.ui
                glyph: model.Signal > 70 ? "signal_wifi_4_bar" : model.Signal > 45 ? "network_wifi_3_bar" : model.Signal > 20 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                title: model.ItemUniqueName || model.Name
                sub: active ? "Connected" : busy ? "Connecting…" : model.ConnectionPath ? "Saved" : (model.SecurityType > 0 ? "Secured" : "Open")
                on: active
                onClicked: {
                    if (active) nmHandler.deactivateConnection(model.ConnectionPath, model.DevicePath)
                    else if (model.ConnectionPath) nmHandler.activateConnection(model.ConnectionPath, model.DevicePath, model.SpecificPath)
                    else { Shell.close(); cc.run("systemsettings kcm_networkmanagement") }
                }
            }
        }

        // Bluetooth: the paired devices, a click connects or disconnects
        Repeater {
            model: cc.page === "bt" ? cc.btDevices.filter(d => d.paired) : []
            delegate: Row2 {
                required property var modelData
                pal: cc.pal; ui: cc.ui
                iconName: modelData.icon || "bluetooth"
                title: modelData.name
                sub: modelData.connected ? "Connected" + (modelData.battery ? "  ·  " + modelData.battery.percentage + "%" : "") : "Not connected"
                on: modelData.connected
                onClicked: modelData.connected ? modelData.disconnectFromDevice() : modelData.connectToDevice()
            }
        }
        Text {
            visible: cc.page === "bt" && !cc.bt.bluetoothOperational
            text: "Bluetooth is off"
            color: cc.pal.muted
            font.family: Tokens.font.ui
            font.pixelSize: cc.u(13)
        }

        // sound output: pick where it plays
        Repeater {
            model: cc.page === "audio" ? sinks : null
            delegate: Row2 {
                required property var model
                readonly property var po: model.PulseObject
                pal: cc.pal; ui: cc.ui
                glyph: po && po.default ? "volume_up" : "speaker"
                title: po ? (po.description || po.name) : ""
                sub: po && po.default ? "Playing here" : ""
                on: !!po && po.default
                onClicked: if (po) po.default = true
            }
        }
        Vol.SinkModel { id: sinks }
    }
}
