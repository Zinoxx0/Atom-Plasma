import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import Atom
import Rice

// Gemini usage meter with Antigravity gravity waves in the panel (no mascot, no rings).
// Data:    ~/.t3/caches/antigravity.json (live T3 Code Antigravity quota windows) and
//          ~/.cache/gemini-usage.json (standalone local cache): qml/Rice/GeminiUsage.qml
// Activity: ~/.cache/gemini/activity.json (Antigravity hooks via bin/gemini-hook.sh): qml/Rice/GeminiActivity.qml
PlasmoidItem {
    id: root

    readonly property string myScreenName: root.Window.window ? Screen.name : ""
    PortalHost { id: portal; widget: root; kind: "gemini"; screenName: root.myScreenName; popup: root.popup }
    readonly property bool panelOpen: portal.open
    function togglePanel() { portal.toggle() }
    function openPanel() { portal.show() }
    function closePanel() { portal.close() }
    function hoverPanel() { portal.hover() }

    RicePalette { id: pal; output: Screen.name }
    readonly property real uiScale: pal.uiScale

    // Misc Modules live settings (Atom.Prefs watches ~/.config/atom-plasma/settings.json)
    readonly property bool moduleOn: Prefs.moduleEnabled("gemini", true)
    readonly property string starStyle: String(Prefs.moduleOpt("gemini", "star_style", "iridescent"))
    readonly property bool ripplesOn: !!Prefs.moduleOpt("gemini", "ripples", true)
    readonly property bool alertsOn: !!Prefs.moduleOpt("gemini", "alerts", true)
    readonly property bool show3p: !!Prefs.moduleOpt("gemini", "show_3p", false)
    onModuleOnChanged: if (!moduleOn && panelOpen) closePanel()

    readonly property bool live: moduleOn && (Shell.barShown(myScreenName) || panelOpen)
    readonly property bool covered: Windows.isFullscreen(myScreenName) || !Shell.barShown(myScreenName)

    GeminiUsage { id: limits; fast: root.panelOpen; busy: root.working; active: root.live }
    GeminiActivity { id: act; active: root.live }
    RiceShell {
        id: sh
        onNewData: (source, data) => disconnectSource(source)
    }

    readonly property var session: limits.session
    readonly property var weekly: limits.weekly
    readonly property var sharedSession: limits.sharedSession
    readonly property var sharedWeekly: limits.sharedWeekly
    readonly property bool hasData: limits.hasData
    readonly property real now: limits.now
    readonly property real peak: limits.peak
    readonly property bool limited: limits.limited
    readonly property bool warm: limits.warm
    readonly property bool stale: limits.stale
    readonly property bool working: act.working
    readonly property bool hot: peak >= 88

    // Trigger 80% / 95% desktop alert script when thresholds are crossed
    property real lastAlertPeak: 0
    onPeakChanged: {
        if (!live || !alertsOn || peak < 80) return
        if (Math.floor(peak / 5) !== Math.floor(lastAlertPeak / 5)) {
            lastAlertPeak = peak
            sh.connectSource('python3 "$HOME/.config/plasma-rice/plasmoids/com.zinoxx.geminiusage/contents/code/alerts.py" >/dev/null 2>&1 #gemalert')
        }
    }

    Plasmoid.status: !moduleOn ? PlasmaCore.Types.HiddenStatus
                   : limited ? PlasmaCore.Types.NeedsAttentionStatus
                   : PlasmaCore.Types.ActiveStatus

    function until(ts) {
        let s = Math.max(0, Math.floor(ts - now))
        const d = Math.floor(s / 86400); s -= d * 86400
        const h = Math.floor(s / 3600); s -= h * 3600
        const m = Math.floor(s / 60)
        if (d) return d + "d " + h + "h"
        if (h) return h + "h " + String(m).padStart(2, "0") + "m"
        return m + "m"
    }
    function at(ts) {
        const t = new Date(ts * 1000), today = new Date()
        const hm = Qt.formatTime(t, "HH:mm")
        return t.toDateString() === today.toDateString() ? hm : Qt.formatDate(t, "ddd") + " " + hm
    }
    function ago(s) {
        if (s < 90) return "just now"
        if (s < 3600) return Math.round(s / 60) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        return Math.round(s / 86400) + " d ago"
    }

    readonly property string statusLine: {
        if (limits.celebrate) return "Fresh limits · ready to build."
        if (limited) return "Limit reached · recharging" + (limits.limitWin.reset ? " until " + at(limits.limitWin.reset) : ".")
        if (working) return act.tool ? "Antigravity active · " + act.tool : "Rippling · Antigravity active"
        if (!hasData) return "Waiting for T3 Code or Gemini usage cache."
        if (peak >= 85) return "Running warm · consider pacing."
        if (warm) return "Moving briskly · ahead of even pace."
        return "Standing by · plenty of headroom."
    }

    readonly property real resetAt: limited && limits.limitWin.reset ? limits.limitWin.reset
                                  : hasData && !session.expired && session.reset ? session.reset : 0
    readonly property string resetText: resetAt > 0 ? until(resetAt) : hasData ? "5h 00m" : "–"

    toolTipMainText: "Gemini"
    toolTipSubText: hasData
        ? "5-hour " + Math.round(session.pct) + "%  ·  Weekly " + Math.round(weekly.pct) + "%\n" + statusLine
        : statusLine
    preferredRepresentation: compactRepresentation

    BarFit { id: fit; widget: root }
    readonly property var riceFit: compactRepresentationItem ? compactRepresentationItem.fitWidths : []

    // ---------- compact bar widget ----------
    compactRepresentation: MouseArea {
        id: compact
        visible: root.moduleOn
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        Text {
            id: cdFont
            visible: false
            font.family: Tokens.font.ui
            font.weight: Font.Medium
            font.pixelSize: Math.round(Tokens.size.label * root.uiScale)
            font.features: { "tnum": 1 }
        }
        TextMetrics { id: cdWidest; font: cdFont.font; text: "0h 00m" }
        readonly property real starBox: Math.round(28 * root.uiScale)
        readonly property real barsW: Math.round(40 * root.uiScale)
        readonly property real cdW: Tokens.space.sm * root.uiScale + Math.ceil(cdWidest.advanceWidth)
        readonly property real padL: Tokens.space.md * root.uiScale
        readonly property real padR: Tokens.space.sm * root.uiScale
        readonly property real bare: padL + starBox + Tokens.space.xs * root.uiScale + barsW + cdW + padR
        readonly property var fitWidths: root.moduleOn ? [bare, bare, bare] : [0, 0, 0]

        Layout.minimumWidth: root.moduleOn ? Math.ceil(bare) : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: root.moduleOn ? -1 : 0
        Layout.fillHeight: true

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) Qt.openUrlExternally("https://gemini.google.com/")
            else root.togglePanel()
        }
        onContainsMouseChanged: if (containsMouse) root.hoverPanel(); else portal.unhover()

        // Hairline divider between Gemini and the widget to its right (sysstats / next module)
        Rectangle {
            visible: root.moduleOn
            x: compact.width - compact.padR + Math.round((compact.padR + 6 + Tokens.space.md * root.uiScale) / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(16 * root.uiScale)
            color: C.alpha(pal.fg, 0.18)
        }

        RowLayout {
            x: compact.padL
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // 4-point Gemini star with quadrupole gravity wave field behind it
            Item {
                Layout.preferredWidth: compact.starBox
                Layout.preferredHeight: compact.starBox
                Layout.alignment: Qt.AlignVCenter

                GravityWave {
                    anchors.centerIn: parent
                    width: Math.round(46 * root.uiScale)
                    height: Math.round(38 * root.uiScale)
                    active: root.working
                    ripplesEnabled: root.ripplesOn
                    animate: !root.covered
                    hot: root.hot
                    starStyle: root.starStyle
                }
                GeminiStar {
                    anchors.centerIn: parent
                    width: Math.round(16 * root.uiScale)
                    height: width
                    starStyle: root.starStyle
                    hot: root.hot
                    floating: root.working && root.ripplesOn
                    animate: !root.covered
                    warnColor: pal.orange
                    hotColor: pal.red
                }
            }

            // Dual horizon light-bars (top: 5-hour session, bottom: weekly)
            Column {
                Layout.leftMargin: Tokens.space.xs * root.uiScale
                Layout.alignment: Qt.AlignVCenter
                spacing: Math.round(5 * root.uiScale)
                HorizonMeter {
                    width: compact.barsW
                    height: Math.max(3, Math.round(4 * root.uiScale))
                    value: root.session.pct
                    pace: root.session.pace
                    hot: root.session.pct >= 88
                    shimmer: root.working
                    animate: !root.covered
                    starStyle: root.starStyle
                    trackColor: C.alpha(pal.fg, 0.14)
                    paceColor: C.alpha(pal.fg, 0.62)
                    warnColor: pal.orange
                    hotColor: pal.red
                    paceExtra: Math.max(1, Math.round(1.5 * root.uiScale))
                }
                HorizonMeter {
                    width: compact.barsW
                    height: Math.max(3, Math.round(4 * root.uiScale))
                    value: root.weekly.pct
                    pace: root.weekly.pace
                    hot: root.weekly.pct >= 88
                    shimmer: false
                    animate: !root.covered
                    starStyle: root.starStyle
                    trackColor: C.alpha(pal.fg, 0.14)
                    paceColor: C.alpha(pal.fg, 0.62)
                    warnColor: pal.orange
                    hotColor: pal.red
                    paceExtra: Math.max(1, Math.round(1.5 * root.uiScale))
                }
            }

            // Tabular reset countdown
            Text {
                Layout.leftMargin: Tokens.space.sm * root.uiScale
                Layout.preferredWidth: compact.cdW - Tokens.space.sm * root.uiScale
                Layout.alignment: Qt.AlignVCenter
                text: root.resetText
                color: root.limited || root.hot ? pal.red : pal.fgDim
                font: cdFont.font
            }
        }
    }

    // ---------- popup sheet ----------
    property Component popup: Component {
        Item {
            id: full
            implicitWidth: 392
            implicitHeight: content.implicitHeight + 2 * Tokens.space.lg

            PopupIn {
                anchors.fill: parent
                active: root.panelOpen
                ricePalette: pal

                ColumnLayout {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.space.lg }
                    spacing: Tokens.space.md

                    PopupHeader {
                        Layout.fillWidth: true
                        palette: pal
                        title: "Gemini"
                        subtitle: root.statusLine
                        leading: GlassCard {
                            implicitWidth: 86; implicitHeight: 68
                            palette: pal
                            accent: root.hot ? pal.red : "#9b72cb"
                            Item {
                                anchors.fill: parent
                                clip: true
                                GravityWave {
                                    anchors.centerIn: parent
                                    width: 86; height: 68
                                    active: root.working
                                    ripplesEnabled: root.ripplesOn
                                    animate: root.panelOpen
                                    hot: root.hot
                                    starStyle: root.starStyle
                                }
                                GeminiStar {
                                    anchors.centerIn: parent
                                    width: 26; height: 26
                                    starStyle: root.starStyle
                                    hot: root.hot
                                    floating: root.working && root.ripplesOn
                                    animate: root.panelOpen
                                    warnColor: pal.orange
                                    hotColor: pal.red
                                }
                            }
                        }
                        badge: Chip {
                            palette: pal
                            text: root.limited ? "limit" : root.working ? "active" : root.stale ? "idle" : "synced"
                            dot: true
                            pulse: root.working && root.panelOpen
                            tint: root.limited ? pal.red : root.working ? "#9b72cb" : root.stale ? pal.outline : pal.green
                            tooltip: root.hasData ? "Updated " + root.ago(limits.updatedAgo) : "No usage data yet"
                        }
                    }

                    // Horizon quota cards (stable model keys so delegates never rebuild on timer ticks)
                    Repeater {
                        model: {
                            const list = [
                                { key: "session", title: "Gemini · 5-hour", span: "5 hours" },
                                { key: "weekly",  title: "Gemini · Weekly", span: "7 days" },
                            ]
                            if (root.show3p && limits.hasShared) {
                                list.push({ key: "3p5h", title: "Claude & GPT · 5-hour", span: "5 hours" })
                                list.push({ key: "3pwk", title: "Claude & GPT · Weekly", span: "7 days" })
                            }
                            return list
                        }
                        Rectangle {
                            id: card
                            required property var modelData
                            readonly property var info: modelData.key === "session" ? root.session
                                                      : modelData.key === "weekly" ? root.weekly
                                                      : modelData.key === "3p5h" ? root.sharedSession
                                                      : root.sharedWeekly
                            readonly property bool isHot: info.pct >= 88
                            visible: modelData.key === "session" || modelData.key === "weekly" || info.present
                            Layout.fillWidth: true
                            implicitHeight: cardCol.implicitHeight + 2 * Tokens.space.md
                            radius: Tokens.radius.md
                            color: C.alpha(pal.surfaceHigh, 0.55)
                            border.width: 1
                            border.color: C.alpha(isHot ? pal.red : pal.edge, isHot ? 0.42 : Tokens.alpha.outline)

                            ColumnLayout {
                                id: cardCol
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Tokens.space.md }
                                spacing: Tokens.space.sm

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: card.modelData.title
                                        color: pal.fg
                                        font.family: Tokens.font.ui
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Tokens.size.body
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: Math.round(card.info.pct) + "%"
                                        color: card.isHot ? pal.red : pal.fg
                                        font.family: Tokens.font.ui
                                        font.weight: Font.Bold
                                        font.pixelSize: Tokens.size.title
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                HorizonMeter {
                                    Layout.fillWidth: true
                                    implicitHeight: 8
                                    value: card.info.pct
                                    pace: card.info.pace
                                    hot: card.isHot
                                    shimmer: root.working && card.modelData.key === "session"
                                    animate: root.panelOpen
                                    starStyle: root.starStyle
                                    trackColor: C.alpha(pal.fg, 0.10)
                                    paceColor: C.alpha(pal.fg, 0.78)
                                    warnColor: pal.orange
                                    hotColor: pal.red
                                    paceExtra: 2.5
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space.sm
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.info.expired ? "Window reset"
                                            : card.info.reset > 0 ? "Resets in " + root.until(card.info.reset) + "  ·  " + root.at(card.info.reset)
                                            : "Fresh window ready  ·  " + card.modelData.span
                                        color: pal.fgDim
                                        font.family: Tokens.font.ui
                                        font.pixelSize: Tokens.size.label
                                        elide: Text.ElideRight
                                    }
                                    Chip {
                                        visible: card.info.pace >= 0
                                        readonly property bool ahead: card.info.pct > card.info.pace + 5
                                        palette: pal
                                        text: card.isHot ? "near limit" : ahead ? "ahead of pace" : "on track"
                                        tint: card.isHot ? pal.red : ahead ? pal.yellow : pal.green
                                    }
                                }
                            }
                        }
                    }

                    // Footer
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: C.alpha(pal.edge, Tokens.alpha.outline)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space.sm
                        Text {
                            text: root.hasData
                                ? "Updated " + root.ago(limits.updatedAgo) + (limits.sourceName ? "  ·  " + limits.sourceName : "")
                                : "Waiting for ~/.t3/caches/antigravity.json"
                            color: pal.fgDim
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.label
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "tick = even pace"
                            color: pal.muted
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.small
                        }
                    }
                }
            }
        }
    }
    fullRepresentation: Item { implicitWidth: 1; implicitHeight: 1 }
}
