import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "Rice"
import "Rice/Color.js" as C

// Claude usage limits with Clawd in the panel.
// Data:    ~/.cache/claude-usage.json  (written by ~/.claude/statusline.sh)
// Colours: this screen's palette (RicePalette, written by ~/.config/plasma-rice/rice.py)
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property var palValues: pal.values     // Clawd takes the raw palette (it has its own `pal`)
    readonly property real uiScale: pal.uiScale

    // ---------- data ----------
    // the limits, watched (no polling); the 80% / 95% notifications come from ~/.claude/statusline.sh
    // when the data changes (contents/code/alerts.py)
    ClaudeUsage { id: limits; fast: root.expanded }
    readonly property var usage: limits.usage
    readonly property real now: limits.now
    RiceShell { id: sh }
    // a check-in Claude asked for (~/.config/plasma-rice/ask.sh): a big "!" over Clawd until "Done"
    // (or until Claude clears it); ClaudeAsk watches the file, no polling
    ClaudeAsk { id: checkIn }
    readonly property var ask: checkIn.ask
    readonly property bool asking: checkIn.asking
    Plasmoid.status: asking ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    function ackAsk() { checkIn.done() }
    // a double click on Clawd: Claude Code in a new terminal (KIO starts it in its own scope, so it
    // outlives plasmashell)
    function summonClaude() {
        root.expanded = false;
        sh.connectSource("kstart --application net.local.claude #claude");
    }

    readonly property var session: limits.session
    readonly property var weekly: limits.weekly
    readonly property bool hasData: limits.hasData
    readonly property real updatedAgo: limits.updatedAgo
    readonly property bool stale: limits.stale
    readonly property real peak: limits.peak
    // how full the usage is shows as how tired Clawd looks (Clawd.usage), not as a mood
    readonly property string mood: limits.mood

    // ---------- Clawd's situation ----------
    readonly property var clock: new Date(now * 1000)
    readonly property int hour: clock.getHours()
    readonly property string daypart: hour < 5 || hour >= 22 ? "night" : hour < 10 ? "morning"
                                    : hour < 18 ? "day" : "evening"
    readonly property bool weekend: clock.getDay() === 0 || clock.getDay() === 6
    readonly property string season: clock.getMonth() === 9 && clock.getDate() >= 24 ? "halloween"
        : clock.getMonth() === 11 && clock.getDate() <= 26 ? "xmas"
        : (clock.getMonth() === 11 && clock.getDate() === 31) || (clock.getMonth() === 0 && clock.getDate() === 1) ? "newyear" : ""
    // the status line rewrites the cache on every Claude Code update
    readonly property bool working: limits.working
    // what Claude Code is doing right now (its hooks write it, ClaudeActivity watches)
    ClaudeActivity { id: claude }
    readonly property string activity: claude.activity
    readonly property bool warm: limits.warm
    readonly property bool celebrate: limits.celebrate      // a window that was half used or more just reset
    readonly property var limitWin: limits.limitWin
    readonly property real sand: limits.sand

    readonly property string moodText: {
        if (celebrate) return "Fresh limits! Let's go.";
        if (mood === "limited") return "Out of energy. Recharging " + (limitWin.reset ? "until " + at(limitWin.reset) : "for a while") + ".";
        if (activity === "waiting") return "Claude is waiting for you.";
        if (activity === "done") return "All done!";
        if (peak >= 90) return "Running on fumes. So… sleepy.";
        if (mood === "sleep") return !hasData ? "No usage data yet."
                                   : daypart === "night" ? "Fast asleep. Goodnight!" : "Napping until Claude Code runs again.";
        const busy = ({ thinking: "Thinking it through…", typing: "Typing away with you.", building: "Running commands…",
                        reading: "Reading the code…", web: "Looking things up…", juggling: "Juggling subagents…",
                        sweeping: "Tidying up the context…" })[activity];
        if (busy) return peak >= 75 ? busy + " A bit sleepy." : busy;
        if (working && activity !== "idle") return daypart === "night" ? "Burning the midnight oil with you."
                          : warm ? "In the zone, a bit ahead of pace." : "In the zone with you.";
        if (peak >= 75) return "Getting sleepy. Maybe pace yourself.";
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
    function ringFrom(i, hot) { return hot ? pal.red : i === 0 ? pal.primary : pal.tertiary }
    function ringTo(i, hot) { return hot ? pal.orange : i === 0 ? pal.tertiary : pal.secondary }

    toolTipMainText: asking ? "Claude needs you" : "Claude"
    toolTipSubText: asking ? ask.msg + "\nOpen this to mark it done." : hasData ? "Session " + Math.round(session.pct) + "%  ·  Weekly " + Math.round(weekly.pct) + "%\n" + moodText
                            : "No usage data yet"
    preferredRepresentation: compactRepresentation

    // ---------- panel ----------
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // the same side padding as every rice bar widget
        Layout.minimumWidth: row.implicitWidth + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) Qt.openUrlExternally("https://claude.ai/settings/usage");
            else root.expanded = !root.expanded;
        }

        // the island around it lights up on hover (Panel Colorizer); Clawd says hi and its eyes follow
        // the pointer. A click on Clawd itself plays one of its acts, anywhere else opens the popup.
        onContainsMouseChanged: if (containsMouse) mini.greet()
        onPositionChanged: mouse => mini.lookAt(mini.mapFromItem(compact, mouse.x, mouse.y).x / mini.width)

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Tokens.space.sm * root.uiScale
            Clawd {
                id: mini
                px: 2 * root.uiScale
                continuous: false
                mood: root.mood
                usage: root.peak
                working: root.working
                activity: root.activity
                celebrate: root.celebrate
                warm: root.warm
                daypart: root.daypart
                weekend: root.weekend
                season: root.season
                sand: root.sand
                alert: root.asking
                pal: root.palValues
                hovered: compact.containsMouse
                onAlertClicked: root.expanded = true        // the popup has the message and Done
                onSummoned: root.summonClaude()
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 2
            }
            Repeater {
                model: 2
                RowLayout {
                    id: meter
                    required property int index
                    readonly property var info: index === 0 ? root.session : root.weekly
                    readonly property bool hot: info.pct >= 90
                    spacing: Tokens.space.xs * root.uiScale
                    Ring {
                        implicitWidth: 15 * root.uiScale; implicitHeight: implicitWidth
                        thickness: 3 * root.uiScale
                        instant: true    // a sweep per update would keep the panel redrawing
                        value: meter.info.pct
                        from: root.ringFrom(meter.index, meter.hot)
                        to: root.ringTo(meter.index, meter.hot)
                        track: C.alpha(pal.fg, 0.15)
                        showText: false
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: root.hasData ? Math.round(meter.info.pct) + "%" : "–"
                        color: meter.hot ? pal.red : pal.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.round(Tokens.size.body * root.uiScale)
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
        Layout.preferredWidth: 400
        Layout.preferredHeight: content.implicitHeight + 2 * Tokens.space.lg
        Layout.minimumWidth: 400
        Layout.minimumHeight: content.implicitHeight + 2 * Tokens.space.lg
        // never bigger than the content (it shrinks back when the check-in banner goes):
        // Plasma restores a remembered popup size otherwise
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        PopupIn {
            anchors.fill: parent
            active: root.expanded
            ricePalette: pal

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                spacing: Tokens.space.lg

                // a check-in from Claude (ask.sh)
                Rectangle {
                    visible: root.asking
                    Layout.fillWidth: true
                    implicitHeight: askRow.implicitHeight + 2 * Tokens.space.md
                    radius: Tokens.radius.md
                    color: C.alpha(pal.red, 0.13)
                    border.width: 1
                    border.color: C.alpha(pal.red, 0.45)
                    RowLayout {
                        id: askRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.md }
                        spacing: Tokens.space.md
                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34
                            radius: Tokens.radius.sm
                            color: pal.red
                            Text {
                                anchors.centerIn: parent
                                text: "!"
                                color: pal.surfaceLowest
                                font.family: Tokens.font.display
                                font.weight: Font.Black
                                font.pixelSize: 22
                            }
                        }
                        ColumnLayout {
                            spacing: Tokens.space.xxs
                            Layout.fillWidth: true
                            Text {
                                text: "Claude needs you"
                                color: pal.red
                                font.family: Tokens.font.ui
                                font.weight: Font.Bold
                                font.pixelSize: Tokens.size.body
                            }
                            Text {
                                text: root.ask ? root.ask.msg : ""
                                color: pal.fg
                                font.family: Tokens.font.ui
                                font.pixelSize: Tokens.size.body
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        Pill {
                            palette: pal
                            text: "Done"
                            accent: pal.red
                            onAccent: pal.surfaceLowest
                            onClicked: root.ackAsk()
                        }
                    }
                }

                PopupHeader {
                    Layout.fillWidth: true
                    palette: pal
                    title: "Claude"
                    subtitle: root.moodText
                    leading: GlassCard {
                        implicitWidth: 112; implicitHeight: 84
                        palette: pal
                        accent: pal.claude
                        Clawd {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 4
                            px: 4.2
                            mood: root.mood
                            usage: root.peak
                            working: root.working
                            activity: root.activity
                            celebrate: root.celebrate
                            warm: root.warm
                            daypart: root.daypart
                            weekend: root.weekend
                            season: root.season
                            sand: root.sand
                            alert: root.asking
                            pal: root.palValues
                            animate: root.expanded
                            onSummoned: root.summonClaude()
                        }
                    }
                    badge: Chip {
                        palette: pal
                        text: root.stale ? "idle" : "live"
                        dot: true
                        pulse: !root.stale && root.expanded
                        tint: root.stale ? pal.outline : pal.green
                        tooltip: root.hasData ? "Updated " + root.ago(root.updatedAgo) : "No usage data yet"
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
                            spacing: Tokens.space.sm

                            Ring {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 146; implicitHeight: 146
                                value: gauge.info.pct
                                pace: gauge.info.pace
                                label: gauge.modelData.title
                                from: root.ringFrom(gauge.index, gauge.hot)
                                to: root.ringTo(gauge.index, gauge.hot)
                                track: C.alpha(pal.fg, 0.08)
                                paceColor: pal.fg
                                textColor: pal.fg
                                subColor: pal.fgDim
                                active: root.expanded
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: gauge.info.expired ? "window reset" : gauge.info.reset ? "resets in " + root.until(gauge.info.reset) : "–"
                                color: pal.fg
                                font.family: Tokens.font.ui
                                font.weight: Font.DemiBold
                                font.pixelSize: Tokens.size.body
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                visible: gauge.info.reset > 0 && !gauge.info.expired
                                text: root.at(gauge.info.reset) + "  ·  " + gauge.modelData.span
                                color: pal.fgDim
                                font.family: Tokens.font.ui
                                font.pixelSize: Tokens.size.label
                            }
                            Chip {
                                Layout.alignment: Qt.AlignHCenter
                                visible: gauge.info.pace >= 0
                                readonly property bool ahead: gauge.info.pct > gauge.info.pace + 5
                                palette: pal
                                text: ahead ? "ahead of pace" : "on track"
                                tint: ahead ? pal.yellow : pal.green
                            }
                        }
                    }
                }

                // footer
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: C.alpha(pal.edge, Tokens.alpha.outline)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    Text {
                        text: root.hasData ? "Updated " + root.ago(root.updatedAgo) : "Waiting for a Claude Code session"
                        color: pal.fgDim
                        font.family: Tokens.font.ui
                        font.pixelSize: Tokens.size.label
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "dot = even pace"
                        color: pal.muted
                        font.family: Tokens.font.ui
                        font.pixelSize: Tokens.size.small
                    }
                    Pill {
                        palette: pal
                        icon: "open_in_new"
                        iconLast: true
                        text: "Usage page"
                        size: 28
                        onClicked: { Qt.openUrlExternally("https://claude.ai/settings/usage"); root.expanded = false }
                    }
                }
            }
        }
    }
}
