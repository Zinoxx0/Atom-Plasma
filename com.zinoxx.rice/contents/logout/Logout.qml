import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtCore
import org.kde.plasma.private.sessions as Sessions
import "Rice"
import "Rice/Color.js" as C
import "autotrigger.js" as Auto

// The rice logout screen (ksmserver-logout-greeter loads it as `logoutmainscript`), in the spirit of
// wlogout: this screen's wallpaper, blurred, behind big rounded action tiles, the account's name,
// and a countdown on the action the prompt was opened for. Esc or a click outside cancels.
//
// The greeter provides, as context properties: screenGeometry, sdtype, maysd, canLogout,
// spdMethods, softwareUpdatePending (plus boot-entry hints this screen doesn't need). It connects
// the signals below. sdtype is KWorkSpace::ShutdownType: -1 default (all options, no countdown),
// 0 none and 3 logout (log out), 1 reboot, 2 halt.
Item {
    id: root
    width: screenGeometry.width
    height: screenGeometry.height

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    RicePalette { id: pal; output: Screen.name }
    Account { id: me }

    // ---------------------------------------------------------------- what's on offer
    readonly property string target: sdtype === 1 ? "reboot" : sdtype === 2 ? "shutdown"
                                    : sdtype === 0 || sdtype === 3 ? "logout" : ""
    readonly property bool updates: softwareUpdatePending === true
    readonly property var actions: [
        { id: "lock",      icon: "lock",               text: "Lock",      tint: "primary",  show: true },
        { id: "sleep",     icon: "bedtime",            text: "Sleep",     tint: "tertiary", show: !!(spdMethods && spdMethods.SuspendState) },
        { id: "hibernate", icon: "ac_unit",            text: "Hibernate", tint: "cyan",     show: !!(spdMethods && spdMethods.HibernateState) },
        { id: "logout",    icon: "logout",             text: "Log out",   tint: "yellow",   show: canLogout !== false },
        { id: "reboot",    icon: "restart_alt",        text: "Restart",   tint: "orange",   show: maysd !== false, hint: updates ? "with updates" : "" },
        { id: "shutdown",  icon: "power_settings_new", text: "Shut down", tint: "red",      show: maysd !== false, hint: updates ? "with updates" : "" },
    ].filter(a => a.show)

    function trigger(id) {
        countdown.stop();
        switch (id) {
        case "lock": root.lockScreenRequested(); break;
        case "sleep": root.suspendRequested(2); break;           // Solid::PowerManagement SuspendState
        case "hibernate": root.suspendRequested(4); break;       // HibernateState
        case "logout": root.logoutRequested(); break;
        case "reboot": root.updates ? root.rebootUpdateRequested() : root.rebootRequested(); break;
        case "shutdown": root.updates ? root.haltUpdateRequested() : root.haltRequested(); break;
        }
    }

    // ---------------------------------------------------------------- countdown
    // A specific prompt (restart, shut down, log out) goes ahead on its own after 30 s unless
    // someone moves through the tiles; the default prompt waits.
    readonly property int timeout: 30
    property real remaining: timeout
    property bool counting: target !== ""
    Timer {
        id: countdown
        interval: 100
        repeat: true
        running: root.counting
        onTriggered: {
            root.remaining = Math.max(0, root.remaining - 0.1);
            if (root.remaining <= 0) { stop(); root.trigger(root.target) }
        }
    }
    function stopCountdown() { root.counting = false; root.remaining = root.timeout }
    Component.onCompleted: Auto.onStop(() => root.stopCountdown())

    readonly property string status: {
        const s = Math.ceil(remaining) + (Math.ceil(remaining) === 1 ? " second" : " seconds");
        if (counting && target === "reboot") return "Restarting in " + s;
        if (counting && target === "shutdown") return "Shutting down in " + s;
        if (counting && target === "logout") return "Logging out in " + s;
        return "See you soon";
    }

    Sessions.SessionsModel {
        id: others
        includeUnusedSessions: false
        includeOwnSession: false
    }

    // ---------------------------------------------------------------- backdrop
    // this screen's wallpaper, decoded tiny and blurred: soft and cheap. It fades in once the
    // palette has named it (a moment after the screen appears), or after 400 ms with rice's global
    // wallpaper, so it never visibly swaps from one to the other.
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString()
    property bool backdropReady: pal.loaded
    Timer { interval: 400; running: !root.backdropReady; onTriggered: root.backdropReady = true }
    Image {
        id: wall
        anchors.fill: parent
        source: !root.backdropReady ? "" : pal.wallpaper ? "file://" + pal.wallpaper : root.home + "/.local/state/rice/wallpaper"
        sourceSize.width: 192
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: false
        // stays visible under the blur: the same picture, and what renderers without shaders show
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.enter } }
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        opacity: wall.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.enter } }
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 48
        saturation: 0.15
    }
    Rectangle {      // dim it, darker towards the edges
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(pal.surfaceLowest, 0.72) }
            GradientStop { position: 0.5; color: C.alpha(pal.surfaceLowest, 0.50) }
            GradientStop { position: 1; color: C.alpha(pal.surfaceLowest, 0.80) }
        }
    }
    MouseArea {      // a click outside the tiles stays in the session
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }
    Shortcut { sequence: "Escape"; onActivated: root.cancelRequested() }

    // ---------------------------------------------------------------- content
    FocusScope {
        id: content
        anchors.centerIn: parent
        width: column.width
        height: column.height
        focus: true

        // entrance: the dark settles, then the content rises into place
        opacity: 0
        transform: Translate { id: rise; y: 16 }
        ParallelAnimation {
            running: true
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
            NumberAnimation { target: rise; property: "y"; to: 0; duration: Tokens.ms(560); easing.type: Tokens.enter }
        }

        Column {
            id: column
            spacing: Tokens.space.xl

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.space.sm
                Rectangle {          // avatar, as in the session menu
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 96; height: 96; radius: 48
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: pal.primary }
                        GradientStop { position: 1; color: pal.tertiary }
                    }
                    border.width: 1
                    border.color: C.alpha("#ffffff", Tokens.alpha.outlineStrong)
                    Text {
                        anchors.centerIn: parent
                        text: me.initial
                        color: pal.onPrimary
                        font.family: Tokens.font.display
                        font.weight: Font.Black
                        font.pixelSize: 44
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: Tokens.space.sm
                    text: me.displayName
                    color: pal.fg
                    font.family: Tokens.font.display
                    font.weight: Font.ExtraBold
                    font.pixelSize: Tokens.size.hero
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.status
                    color: root.counting ? pal.col(root.actions.find(a => a.id === root.target)?.tint ?? "primary") : pal.fgDim
                    font.family: Tokens.font.ui
                    font.weight: root.counting ? Font.DemiBold : Font.Normal
                    font.pixelSize: Tokens.size.title
                    font.features: { "tnum": 1 }
                }
            }

            Row {
                id: tiles
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.space.lg
                Repeater {
                    id: tileRepeater
                    model: root.actions
                    Tile {
                        id: tileItem
                        required property var modelData
                        required property int index
                        palette: pal
                        icon: modelData.icon
                        text: modelData.text
                        hint: modelData.hint ?? ""
                        tint: pal.col(modelData.tint)
                        progress: root.counting && modelData.id === root.target ? root.remaining / root.timeout : -1
                        focus: modelData.id === (root.target || "lock")
                        onActivated: root.trigger(modelData.id)
                        // moving through the tiles is a decision in progress: stop the countdown everywhere
                        Keys.onLeftPressed: { Auto.stopAll(); if (index > 0) tileRepeater.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason) }
                        Keys.onRightPressed: { Auto.stopAll(); if (index < tileRepeater.count - 1) tileRepeater.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason) }
                        onActiveFocusChanged: if (activeFocus && modelData.id !== root.target && root.counting) Auto.stopAll()

                        // tiles arrive one after another
                        opacity: 0
                        transform: Translate { id: tileRise; y: 18 }
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: Tokens.ms(120 + tileItem.index * 45) }
                            ParallelAnimation {
                                NumberAnimation { target: tileItem; property: "opacity"; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                                NumberAnimation { target: tileRise; property: "y"; to: 0; duration: Tokens.slow; easing.type: Tokens.enter }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.space.md
                Chip {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: others.count > 0 && root.target !== "logout"
                    palette: pal
                    size: 26
                    icon: "group"
                    tint: pal.yellow
                    text: others.count === 1 ? "Someone else is logged in and may lose their work"
                                             : others.count + " other people are logged in and may lose their work"
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.space.sm
                    Pill {
                        palette: pal
                        icon: "close"
                        text: "Cancel"
                        accent: pal.fgDim
                        onAccent: pal.surfaceLowest
                        size: 34
                        onClicked: root.cancelRequested()
                    }
                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        palette: pal
                        text: "esc"
                        tint: pal.fgDim
                        size: 22
                    }
                }
            }
        }
    }
}
