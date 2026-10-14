import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Claude usage limits with Clawd in the panel.
// Data:    ~/.cache/claude-usage.json  (written by ~/.claude/statusline.sh)
// Colours: ~/.local/state/rice/palette.json (written by ~/.config/plasma-rice/rice.py)
PlasmoidItem {
    id: root

    property var usage: null
    property var pal: ({})
    // per-screen size of the bar widgets (rice settings "bar_scale", in the palette as _scale)
    readonly property real uiScale: pal._scale || 1
    property real now: Date.now() / 1000

    function col(name, fallback) { return pal[name] ?? fallback }

    // ---------- data ----------
    readonly property string codeDir: Qt.resolvedUrl("../code/").toString().replace("file://", "")

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.endsWith("#ask")) {
                const out = (data["stdout"] ?? "").trim();
                let a = null;
                try { if (out) a = JSON.parse(out) } catch (e) {}
                root.ask = a;
            } else if (source.startsWith("cat ")) {
                const parts = (data["stdout"] ?? "").split("\n@@SEP@@\n");
                try { root.usage = JSON.parse(parts[0]) } catch (e) { root.usage = null }
                try { if (parts[1]) root.pal = JSON.parse(parts[1]) } catch (e) {}
            }
            disconnectSource(source);
        }
    }
    function refresh() {
        root.now = Date.now() / 1000;
        sh.connectSource('cat "$HOME/.cache/claude-usage.json" 2>/dev/null; printf "\\n@@SEP@@\\n"; { cat "$HOME/.local/state/rice/palette-' + screenName + '.json" || cat "$HOME/.local/state/rice/palette.json"; } 2>/dev/null');
    }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: root.expanded ? 1000 : 30000; running: true; repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
    // a check-in Claude asked for (~/.config/plasma-rice/ask.sh): a big "!" over Clawd until "Done"
    property var ask: null
    readonly property bool asking: ask !== null && !(ask.ack > 0)
    Plasmoid.status: asking ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    function ackAsk() {
        if (!ask) return;
        ask = Object.assign({}, ask, { ack: Math.floor(Date.now() / 1000) });
        sh.connectSource('sh "$HOME/.config/plasma-rice/ask.sh" --ack #ack');
    }
    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: sh.connectSource('cat "$HOME/.local/state/rice/ask.json" 2>/dev/null #ask')
    }
    Timer {   // limit notifications (80% / 95%), once per window
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: sh.connectSource("python3 '" + root.codeDir + "alerts.py'")
    }
    // the palette changes together with the colour scheme
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: refresh()
    // each bar follows its own screen's wallpaper (palette-<output>.json, see rice.py)
    readonly property string screenName: Screen.name
    onScreenNameChanged: refresh()

    function windowInfo(key, length) {
        const w = usage?.[key] ?? {};
        const reset = Number(w.resets_at ?? 0);
        const expired = reset > 0 && reset <= now;
        const pct = expired ? 0 : Number(w.used_percentage ?? 0);
        const start = reset - length;
        const pace = reset > 0 && !expired ? Math.max(0, Math.min(100, (now - start) / length * 100)) : -1;
        return { pct: pct, reset: reset, expired: expired, pace: pace };
    }
    readonly property var session: windowInfo("five_hour", 5 * 3600)
    readonly property var weekly: windowInfo("seven_day", 7 * 86400)
    readonly property bool hasData: usage !== null
    readonly property real updatedAgo: hasData ? now - Number(usage.updated ?? 0) : 1e9
    readonly property bool stale: updatedAgo > 30 * 60
    readonly property real peak: Math.max(session.pct, weekly.pct)
    readonly property string mood: peak >= 100 ? "limited" : peak >= 90 ? "panic" : peak >= 75 ? "sweat"
                                 : (stale || !hasData) ? "sleep" : "happy"

    // ---------- Clawd's situation ----------
    readonly property var clock: new Date(now * 1000)
    readonly property int hour: clock.getHours()
    readonly property string daypart: hour < 5 || hour >= 22 ? "night" : hour < 10 ? "morning"
                                    : hour < 18 ? "day" : "evening"
    readonly property bool weekend: clock.getDay() === 0 || clock.getDay() === 6
    readonly property string season: clock.getMonth() === 11 && clock.getDate() <= 26 ? "xmas"
        : (clock.getMonth() === 11 && clock.getDate() === 31) || (clock.getMonth() === 0 && clock.getDate() === 1) ? "newyear" : ""
    // the status line rewrites the cache on every Claude Code update
    readonly property bool working: hasData && updatedAgo < 180
    readonly property bool warm: session.pace >= 0 && session.pct >= 25 && session.pct > session.pace + 15
    // a party for 15 min when a window that was half used or more resets
    property real partyUntil: 0
    property real lastSession: -1
    property real lastWeekly: -1
    onSessionChanged: { if (lastSession >= 50 && session.pct < 5) partyUntil = now + 900; lastSession = session.pct }
    onWeeklyChanged: { if (lastWeekly >= 50 && weekly.pct < 5) partyUntil = now + 900; lastWeekly = weekly.pct }
    readonly property bool celebrate: now < partyUntil && mood !== "limited"
    // limited: the window that ran out, and how much of the wait is left (Clawd's hourglass)
    readonly property var limitWin: session.pct >= 100 ? session : weekly
    readonly property real sand: Math.max(0, Math.min(1, (limitWin.reset - now) / (session.pct >= 100 ? 5 * 3600 : 7 * 86400)))

    readonly property string moodText: {
        if (celebrate) return "Fresh limits! Let's go.";
        if (mood === "limited") return "Limit reached. Back " + (limitWin.reset ? "at " + at(limitWin.reset) : "soon") + ".";
        if (mood === "panic") return "Running on fumes!";
        if (mood === "sweat") return "Getting warm. Maybe pace yourself.";
        if (mood === "sleep") return !hasData ? "No usage data yet."
                                   : daypart === "night" ? "Fast asleep. Goodnight!" : "Napping until Claude Code runs again.";
        if (working) return daypart === "night" ? "Burning the midnight oil with you."
                          : warm ? "In the zone, a bit ahead of pace." : "In the zone with you.";
        if (season === "xmas") return "Ho ho ho. Plenty of room left.";
        return ({
            morning: "Good morning! Coffee's ready.",
            day:     weekend ? "Weekend mode. Plenty of room." : "Plenty of room. Let's build something.",
            evening: "Evening. Still plenty of room.",
            night:   "Up late? Plenty of room left.",
        })[daypart];
    }

    function until(ts) {
        let s = Math.max(0, Math.floor(ts - now));
        const d = Math.floor(s / 86400); s -= d * 86400;
        const h = Math.floor(s / 3600); s -= h * 3600;
        const m = Math.floor(s / 60);
        if (d) return d + "d " + h + "h";
        if (h) return h + "h " + String(m).padStart(2, "0") + "m";
        return m + "m";
    }
    function at(ts) {
        const t = new Date(ts * 1000), today = new Date();
        const hm = Qt.formatTime(t, "HH:mm");
        return t.toDateString() === today.toDateString() ? hm : Qt.formatDate(t, "ddd") + " " + hm;
    }
    function ago(s) {
        if (s < 90) return "just now";
        if (s < 3600) return Math.round(s / 60) + " min ago";
        if (s < 86400) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }
    function ringFrom(i, hot) { return hot ? col("red", "#f7768e") : i === 0 ? col("primary", "#7aa2f7") : col("tertiary", "#bb9af7") }
    function ringTo(i, hot) { return hot ? col("orange", "#ff9e64") : i === 0 ? col("tertiary", "#bb9af7") : col("secondary", "#9aa5ce") }

    toolTipMainText: asking ? "Claude needs you" : "Claude"
    toolTipSubText: asking ? ask.msg + "\nOpen this to mark it done." : hasData ? "Session " + Math.round(session.pct) + "%  ·  Weekly " + Math.round(weekly.pct) + "%\n" + moodText
                            : "No usage data yet"
    preferredRepresentation: compactRepresentation

    // ---------- panel ----------
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        Layout.minimumWidth: row.implicitWidth + 18 * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) Qt.openUrlExternally("https://claude.ai/settings/usage");
            else root.expanded = !root.expanded;
        }

        // the island around it lights up on hover (Panel Colorizer); Clawd just says hi
        onContainsMouseChanged: if (containsMouse) mini.hop()

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 7 * root.uiScale
            Clawd {
                id: mini
                px: 2 * root.uiScale
                continuous: false
                mood: root.mood
                working: root.working
                celebrate: root.celebrate
                warm: root.warm
                daypart: root.daypart
                weekend: root.weekend
                season: root.season
                sand: root.sand
                alert: root.asking
                pal: root.pal
                interactive: false
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 2
            }
            Repeater {
                model: 2
                RowLayout {
                    required property int index
                    readonly property var info: index === 0 ? root.session : root.weekly
                    readonly property bool hot: info.pct >= 90
                    spacing: 4 * root.uiScale
                    Ring {
                        implicitWidth: 15 * root.uiScale; implicitHeight: implicitWidth
                        thickness: 3 * root.uiScale
                        value: parent.info.pct
                        from: root.ringFrom(parent.index, parent.hot)
                        to: root.ringTo(parent.index, parent.hot)
                        track: Qt.alpha(root.col("on_surface", "#c0caf5"), 0.15)
                        showText: false
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents.Label {
                        text: root.hasData ? Math.round(parent.info.pct) + "%" : "–"
                        color: parent.hot ? root.col("red", "#f7768e") : root.col("on_surface", Kirigami.Theme.textColor)
                        font.family: "Inter"
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.round(13 * root.uiScale)
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
        Connections {
            target: root
            function onExpandedChanged() { if (root.expanded) mini.hop() }
        }
    }

    // ---------- popup ----------
    fullRepresentation: Item {
        id: full
        Layout.preferredWidth: 380
        Layout.preferredHeight: content.implicitHeight + 24
        Layout.minimumWidth: 380
        Layout.minimumHeight: content.implicitHeight + 24

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 18
            transformOrigin: Item.Bottom

            // a check-in from Claude (ask.sh)
            Rectangle {
                visible: root.asking
                Layout.fillWidth: true
                implicitHeight: askRow.implicitHeight + 24
                radius: 16
                color: Qt.alpha(root.col("red", "#f7768e"), 0.13)
                border.width: 1
                border.color: Qt.alpha(root.col("red", "#f7768e"), 0.45)
                RowLayout {
                    id: askRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 12
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34
                        radius: 10
                        color: root.col("red", "#f7768e")
                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: root.col("surface_lowest", "#16161e")
                            font.family: "Inter Display"; font.weight: Font.Black; font.pixelSize: 22
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: "Claude needs you"
                            color: root.col("red", "#f7768e")
                            font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 13
                        }
                        Text {
                            text: root.ask ? root.ask.msg : ""
                            color: root.col("on_surface", "#e5e1e7")
                            font.family: "Inter"; font.pixelSize: 13
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                    Rectangle {
                        implicitWidth: doneText.implicitWidth + 26
                        implicitHeight: 30
                        radius: 15
                        color: doneMouse.containsMouse ? root.col("red", "#f7768e") : Qt.alpha(root.col("red", "#f7768e"), 0.2)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: doneText
                            anchors.centerIn: parent
                            text: "Done"
                            color: doneMouse.containsMouse ? root.col("surface_lowest", "#16161e") : root.col("red", "#f7768e")
                            font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 12
                        }
                        MouseArea {
                            id: doneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ackAsk()
                        }
                    }
                }
            }

            // header
            RowLayout {
                spacing: 18
                Layout.fillWidth: true

                Rectangle {
                    implicitWidth: 112; implicitHeight: 84
                    radius: 20
                    color: Qt.alpha(root.col("surface_highest", "#353438"), 0.7)
                    border.width: 1
                    border.color: Qt.alpha(root.col("claude", "#d97757"), 0.25)
                    Clawd {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 4
                        px: 4.2
                        mood: root.mood
                        working: root.working
                        celebrate: root.celebrate
                        warm: root.warm
                        daypart: root.daypart
                        weekend: root.weekend
                        season: root.season
                        sand: root.sand
                        alert: root.asking
                        pal: root.pal
                        animate: root.expanded
                    }
                }

                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 8
                        Text {
                            text: "Claude"
                            color: root.col("on_surface", "#e5e1e7")
                            font.family: "Inter Display"
                            font.weight: Font.ExtraBold
                            font.pixelSize: 24
                        }
                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: chip.implicitWidth + 16
                            radius: 10
                            color: root.stale ? Qt.alpha(root.col("outline", "#918f9a"), 0.25)
                                              : Qt.alpha(root.col("green", "#9ece6a"), 0.18)
                            Row {
                                id: chip
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.stale ? root.col("outline", "#918f9a") : root.col("green", "#9ece6a")
                                    SequentialAnimation on opacity {
                                        running: !root.stale && root.expanded
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.3; duration: 900 }
                                        NumberAnimation { to: 1; duration: 900 }
                                    }
                                }
                                Text {
                                    text: root.stale ? "idle" : "live"
                                    color: root.stale ? root.col("on_surface_variant", "#c8c5d1") : root.col("green", "#9ece6a")
                                    font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 11
                                }
                            }
                        }
                    }
                    Text {
                        text: "Usage limits"
                        color: root.col("primary", "#7aa2f7")
                        font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 13
                    }
                    Text {
                        text: root.moodText
                        color: root.col("on_surface_variant", "#c8c5d1")
                        font.family: "Inter"; font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // gauges
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: [
                        { key: "session", title: "Session", span: "5 hours" },
                        { key: "weekly",  title: "Weekly",  span: "7 days" },
                    ]
                    ColumnLayout {
                        id: gauge
                        required property var modelData
                        required property int index
                        readonly property var info: modelData.key === "session" ? root.session : root.weekly
                        readonly property bool hot: info.pct >= 90
                        Layout.fillWidth: true
                        spacing: 8

                        Ring {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 146; implicitHeight: 146
                            value: gauge.info.pct
                            pace: gauge.info.pace
                            label: gauge.modelData.title
                            from: root.ringFrom(gauge.index, gauge.hot)
                            to: root.ringTo(gauge.index, gauge.hot)
                            track: Qt.alpha(root.col("on_surface", "#e5e1e7"), 0.08)
                            paceColor: root.col("on_surface", "#e5e1e7")
                            textColor: root.col("on_surface", "#e5e1e7")
                            subColor: root.col("on_surface_variant", "#c8c5d1")
                            active: root.expanded
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: gauge.info.expired ? "window reset" : gauge.info.reset ? "resets in " + root.until(gauge.info.reset) : "–"
                            color: root.col("on_surface", "#e5e1e7")
                            font.family: "Inter"; font.weight: Font.DemiBold; font.pixelSize: 13
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: gauge.info.reset > 0 && !gauge.info.expired
                            text: root.at(gauge.info.reset) + "  ·  " + gauge.modelData.span
                            color: root.col("on_surface_variant", "#c8c5d1")
                            font.family: "Inter"; font.pixelSize: 12
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            visible: gauge.info.pace >= 0
                            readonly property bool ahead: gauge.info.pct > gauge.info.pace + 5
                            implicitHeight: 22
                            implicitWidth: paceText.implicitWidth + 18
                            radius: 11
                            color: ahead ? Qt.alpha(root.col("yellow", "#e0af68"), 0.18) : Qt.alpha(root.col("green", "#9ece6a"), 0.15)
                            Text {
                                id: paceText
                                anchors.centerIn: parent
                                text: parent.ahead ? "ahead of pace" : "on track"
                                color: parent.ahead ? root.col("yellow", "#e0af68") : root.col("green", "#9ece6a")
                                font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            // footer
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.alpha(root.col("outline_variant", "#47464f"), 0.6)
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.hasData ? "Updated " + root.ago(root.updatedAgo) : "Waiting for a Claude Code session"
                    color: root.col("on_surface_variant", "#c8c5d1")
                    font.family: "Inter"; font.pixelSize: 12
                    Layout.fillWidth: true
                }
                Text {
                    text: "dot = even pace"
                    color: Qt.alpha(root.col("on_surface_variant", "#c8c5d1"), 0.7)
                    font.family: "Inter"; font.pixelSize: 11
                }
                Rectangle {
                    implicitWidth: linkRow.implicitWidth + 18
                    implicitHeight: 26
                    radius: 13
                    color: linkMouse.containsMouse ? root.col("primary", "#7aa2f7") : Qt.alpha(root.col("primary", "#7aa2f7"), 0.15)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Row {
                        id: linkRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: "Usage page"
                            color: linkMouse.containsMouse ? root.col("on_primary", "#1a1b26") : root.col("primary", "#7aa2f7")
                            font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 12
                        }
                        Text {
                            text: "open_in_new"
                            color: linkMouse.containsMouse ? root.col("on_primary", "#1a1b26") : root.col("primary", "#7aa2f7")
                            font.family: "Material Symbols Rounded"; font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: linkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Qt.openUrlExternally("https://claude.ai/settings/usage"); root.expanded = false }
                    }
                }
            }
        }

        // little pop when the popup opens
        ParallelAnimation {
            id: pop
            NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: content; property: "scale"; from: 0.94; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }
        Connections {
            target: root
            function onExpandedChanged() { if (root.expanded) pop.restart() }
        }
    }
}
