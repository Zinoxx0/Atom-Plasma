import QtQuick
import QtQuick.Layouts
import QtCore
import Atom
import "../../Rice"
import "../../Rice/Color.js" as C

// The calendar panel (the clock island): the month on the left (today a filled circle, holidays in the
// tertiary colour, events as dots under their day; months slide when you change them) and the chosen
// day's agenda on the right (its holiday, its events, and, on today, what's next). Data: agenda.py
// (~/.cache/rice/calendar.json: Portuguese holidays + the Google Calendar of the secret iCal address).
// Keys: arrows move the day, Page Up/Down the month, Home goes back to today, Esc closes.
FocusScope {
    id: cal
    property RicePalette ricePalette: null
    property string screenName: ""
    property real ui: 1
    property string kind: ""
    property var args: ({})
    readonly property RicePalette pal: ricePalette
    function u(n) { return Math.round(n * ui) }

    readonly property real cell: u(44)
    readonly property real gridW: 7 * cell
    readonly property real agendaW: u(300)
    implicitWidth: gridW + u(28) + agendaW
    implicitHeight: Math.max(left.implicitHeight, u(360))

    // ------------------------------------------------------------------ data
    WatchedJson {
        id: agenda
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.cache/rice/calendar.json"
    }
    RiceShell { id: sh; onNewData: (source, data) => disconnectSource(source) }
    readonly property var feed: agenda.value || ({})      // (not `data`: every Item has one)
    readonly property bool connected: feed.source === "ical"
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function dayOf(iso) {       // "2026-11-20" (all day) or "2026-11-10T15:00+00:00"
        if (iso.length <= 10) { const p = iso.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]) }
        return new Date(iso)
    }
    // day key -> its events (all-day ones on every day they cover)
    readonly property var byDay: {
        const out = {}
        for (const e of (feed.events || [])) {
            if (e.allDay) {
                const end = dayOf(e.end), d = dayOf(e.start)
                do { (out[key(d)] = out[key(d)] || []).push(e); d.setDate(d.getDate() + 1) } while (d < end)
            } else {
                const k = key(new Date(e.start));
                (out[k] = out[k] || []).push(e)
            }
        }
        return out
    }
    readonly property var holidays: feed.holidays || ({})

    // ------------------------------------------------------------------ what's shown
    property date now: new Date()
    Timer { interval: 30000; running: cal.visible; repeat: true; onTriggered: cal.now = new Date() }
    property date selected: new Date()
    property date month: new Date(now.getFullYear(), now.getMonth(), 1)
    property int slide: 0                       // -1 / +1: the direction the month just moved
    function setMonth(y, m) {
        const next = new Date(y, m, 1)
        slide = next > month ? 1 : next < month ? -1 : 0
        month = next
        monthIn.restart()
    }
    function pick(d) {
        selected = d
        if (d.getMonth() !== month.getMonth() || d.getFullYear() !== month.getFullYear()) setMonth(d.getFullYear(), d.getMonth())
    }
    function step(days) { const d = new Date(selected); d.setDate(d.getDate() + days); pick(d) }
    function today() { now = new Date(); pick(new Date(now)) }
    readonly property bool onToday: key(selected) === key(now)

    // the sheet calls this as the panel comes in: back to today, fresh data
    function enter() {
        today()
        sh.connectSource('python3 "$HOME/.config/plasma-rice/agenda.py" >/dev/null #run')
        forceActiveFocus()
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onUpPressed: step(-7)
    Keys.onDownPressed: step(7)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) { setMonth(month.getFullYear(), month.getMonth() - 1); event.accepted = true }
        else if (event.key === Qt.Key_PageDown) { setMonth(month.getFullYear(), month.getMonth() + 1); event.accepted = true }
        else if (event.key === Qt.Key_Home) { today(); event.accepted = true }
    }

    // ------------------------------------------------------------------ the month
    ColumnLayout {
        id: left
        width: cal.gridW
        spacing: cal.u(8)

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: cal.u(4)
            Text {
                text: Qt.formatDate(cal.month, "MMMM")
                color: cal.pal.fg
                font.family: Tokens.font.display
                font.weight: Font.DemiBold
                font.pixelSize: cal.u(21)
            }
            Text {
                Layout.leftMargin: cal.u(6)
                text: Qt.formatDate(cal.month, "yyyy")
                color: cal.pal.muted
                font.family: Tokens.font.display
                font.pixelSize: cal.u(21)
            }
            Item { Layout.fillWidth: true }
            Repeater {      // Today (only away from this month), previous, next
                model: [{ label: "Today", glyph: "", act: 0 }, { label: "", glyph: "chevron_left", act: -1 }, { label: "", glyph: "chevron_right", act: 1 }]
                delegate: Rectangle {
                    id: nav
                    required property var modelData
                    readonly property bool away: cal.month.getMonth() !== cal.now.getMonth() || cal.month.getFullYear() !== cal.now.getFullYear()
                    visible: modelData.act !== 0 || away
                    implicitHeight: cal.u(30)
                    implicitWidth: modelData.label ? navText.implicitWidth + cal.u(20) : implicitHeight
                    radius: implicitHeight / 2
                    color: C.alpha(cal.pal.fg, navMouse.containsMouse ? 0.14 : 0.06)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Text {
                        id: navText
                        anchors.centerIn: parent
                        text: nav.modelData.label || nav.modelData.glyph
                        color: nav.modelData.label ? cal.pal.primary : cal.pal.fg
                        font.family: nav.modelData.label ? Tokens.font.ui : Tokens.font.icons
                        font.weight: Font.DemiBold
                        font.pixelSize: nav.modelData.label ? cal.u(12) : cal.u(18)
                    }
                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: nav.modelData.act === 0 ? cal.today() : cal.setMonth(cal.month.getFullYear(), cal.month.getMonth() + nav.modelData.act)
                    }
                }
            }
        }

        Row {       // the week, Monday first
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Text {
                    required property string modelData
                    required property int index
                    width: cal.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: index >= 5 ? cal.pal.tertiary : cal.pal.muted
                    opacity: 0.8
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: cal.u(11)
                }
            }
        }

        Item {
            Layout.preferredWidth: cal.gridW
            Layout.preferredHeight: 6 * cal.cell
            clip: true
            Grid {
                id: days
                columns: 7
                opacity: 1
                transform: Translate { id: shift }
                // 42 days from the Monday on or before the 1st
                readonly property date first: {
                    const d = new Date(cal.month), wd = (d.getDay() + 6) % 7
                    d.setDate(d.getDate() - wd)
                    return d
                }
                Repeater {
                    model: 42
                    delegate: Item {
                        id: day
                        required property int index
                        readonly property date date: { const d = new Date(days.first); d.setDate(d.getDate() + index); return d }
                        readonly property string k: cal.key(date)
                        readonly property bool inMonth: date.getMonth() === cal.month.getMonth()
                        readonly property bool isToday: k === cal.key(cal.now)
                        readonly property bool isSel: k === cal.key(cal.selected)
                        readonly property string holiday: cal.holidays[k] || ""
                        readonly property var evs: cal.byDay[k] || []
                        width: cal.cell
                        height: cal.cell
                        Rectangle {
                            anchors.centerIn: parent
                            width: cal.cell - cal.u(6); height: width; radius: width / 2
                            color: day.isToday ? cal.pal.primary
                                 : day.isSel ? C.alpha(cal.pal.primary, 0.16)
                                 : dm.containsMouse ? C.alpha(cal.pal.fg, 0.07) : "transparent"
                            border.width: day.isSel && !day.isToday ? 1.5 : 0
                            border.color: C.alpha(cal.pal.primary, 0.75)
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        }
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: day.evs.length || day.holiday ? -cal.u(3) : 0
                            text: day.date.getDate()
                            color: day.isToday ? cal.pal.onPrimary
                                 : day.holiday ? cal.pal.tertiary
                                 : day.inMonth ? cal.pal.fg : cal.pal.muted
                            opacity: day.inMonth ? 1 : 0.45
                            font.family: Tokens.font.ui
                            font.weight: day.isToday || day.holiday ? Font.Bold : Font.Medium
                            font.pixelSize: cal.u(14)
                        }
                        Row {       // a dot per event (three at most), a ring for a holiday
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height / 2 + cal.u(7)
                            spacing: cal.u(3)
                            opacity: day.inMonth ? 1 : 0.45
                            Rectangle {
                                visible: !!day.holiday
                                width: cal.u(5); height: width; radius: width / 2
                                color: "transparent"
                                border.width: 1.2
                                border.color: day.isToday ? cal.pal.onPrimary : cal.pal.tertiary
                            }
                            Repeater {
                                model: Math.min(3, day.evs.length)
                                Rectangle {
                                    width: cal.u(5); height: width; radius: width / 2
                                    color: day.isToday ? cal.pal.onPrimary : cal.pal.primary
                                }
                            }
                        }
                        MouseArea {
                            id: dm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cal.pick(day.date)
                        }
                    }
                }
            }
            ParallelAnimation {
                id: monthIn
                NumberAnimation { target: shift; property: "x"; from: cal.slide * cal.u(36); to: 0; duration: Tokens.ms(380); easing.type: Tokens.grow }
                NumberAnimation { target: days; property: "opacity"; from: cal.slide ? 0.2 : 1; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
            }
        }
    }

    // ------------------------------------------------------------------ the day's agenda
    Rectangle {
        x: cal.gridW + cal.u(14)
        width: 1
        height: cal.height
        color: C.alpha(cal.pal.edge, Tokens.alpha.outline)
    }
    ColumnLayout {
        id: right
        x: cal.gridW + cal.u(28)
        width: cal.agendaW
        height: cal.height
        spacing: cal.u(10)

        Text {
            text: cal.onToday ? "Today" : Qt.formatDate(cal.selected, "dddd")
            color: cal.pal.primary
            font.family: Tokens.font.ui
            font.weight: Font.DemiBold
            font.pixelSize: cal.u(12)
            font.letterSpacing: 0.6
            font.capitalization: Font.AllUppercase
        }
        Text {
            Layout.topMargin: -cal.u(6)
            text: Qt.formatDate(cal.selected, "d MMMM")
            color: cal.pal.fg
            font.family: Tokens.font.display
            font.weight: Font.Light
            font.pixelSize: cal.u(30)
        }
        Rectangle {     // its holiday
            visible: !!cal.holidays[cal.key(cal.selected)]
            Layout.fillWidth: true
            implicitHeight: cal.u(34)
            radius: Tokens.radius.md
            color: C.alpha(cal.pal.tertiary, 0.14)
            border.width: 1
            border.color: C.alpha(cal.pal.tertiary, 0.4)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: cal.u(12)
                spacing: cal.u(8)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "celebration"; color: cal.pal.tertiary; font.family: Tokens.font.icons; font.pixelSize: cal.u(17) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cal.holidays[cal.key(cal.selected)] || ""
                    color: cal.pal.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: cal.u(13)
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: cal.u(8)
            model: cal.byDay[cal.key(cal.selected)] || []
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: ev
                required property var modelData
                readonly property bool past: !modelData.allDay && new Date(modelData.end) < cal.now
                width: list.width
                implicitHeight: evCol.implicitHeight + cal.u(18)
                radius: Tokens.radius.md
                color: C.alpha(cal.pal.fg, 0.05)
                border.width: 1
                border.color: C.alpha(cal.pal.edge, Tokens.alpha.outline)
                opacity: past ? 0.5 : 1
                Rectangle {     // the event's colour along its left edge
                    x: cal.u(8); width: cal.u(3); radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height - cal.u(18)
                    color: cal.pal.primary
                }
                Column {
                    id: evCol
                    x: cal.u(20)
                    width: parent.width - cal.u(30)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cal.u(2)
                    Text {
                        text: ev.modelData.allDay ? "All day"
                            : Qt.formatTime(new Date(ev.modelData.start), "HH:mm") + " – " + Qt.formatTime(new Date(ev.modelData.end), "HH:mm")
                        color: cal.pal.muted
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: cal.u(11)
                    }
                    Text {
                        width: parent.width
                        text: ev.modelData.title
                        color: cal.pal.fg
                        elide: Text.ElideRight
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: cal.u(14)
                    }
                    Text {
                        visible: !!ev.modelData.location
                        width: parent.width
                        text: ev.modelData.location
                        color: cal.pal.fgDim
                        elide: Text.ElideRight
                        font.family: Tokens.font.ui
                        font.pixelSize: cal.u(12)
                    }
                }
            }
            // nothing planned (and how to connect the calendar, until it is)
            Column {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: cal.u(6)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "event_available"
                    color: C.alpha(cal.pal.fg, 0.25)
                    font.family: Tokens.font.icons
                    font.pixelSize: cal.u(34)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nothing planned"
                    color: cal.pal.muted
                    font.family: Tokens.font.ui
                    font.pixelSize: cal.u(13)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !cal.connected
                    width: cal.agendaW - cal.u(20)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Google Calendar: agenda.py set-url <secret iCal address>"
                    color: C.alpha(cal.pal.muted, 0.7)
                    font.family: Tokens.font.mono
                    font.pixelSize: cal.u(10)
                }
            }
        }

        // what's next (on today)
        Rectangle {
            id: nextUp
            readonly property var next: {
                const t = cal.now
                for (const e of (cal.feed.events || [])) {
                    const s = e.allDay ? cal.dayOf(e.start) : new Date(e.start)
                    if (!e.allDay && s > t) return e
                }
                return null
            }
            readonly property string when: {
                if (!next) return ""
                const s = new Date(next.start), mins = Math.round((s - cal.now) / 60000)
                if (mins < 60) return "In " + Math.max(1, mins) + " min"
                if (cal.key(s) === cal.key(cal.now)) return "At " + Qt.formatTime(s, "HH:mm")
                const tm = new Date(cal.now); tm.setDate(tm.getDate() + 1)
                if (cal.key(s) === cal.key(tm)) return "Tomorrow " + Qt.formatTime(s, "HH:mm")
                return Qt.formatDate(s, "ddd d") + ", " + Qt.formatTime(s, "HH:mm")
            }
            visible: cal.onToday && next !== null
            Layout.fillWidth: true
            implicitHeight: cal.u(40)
            radius: height / 2
            color: C.alpha(cal.pal.primary, 0.12)
            border.width: 1
            border.color: C.alpha(cal.pal.primary, 0.35)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: cal.u(14)
                spacing: cal.u(8)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "schedule"; color: cal.pal.primary; font.family: Tokens.font.icons; font.pixelSize: cal.u(17) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: cal.agendaW - cal.u(60)
                    elide: Text.ElideRight
                    text: nextUp.next ? nextUp.when + "  ·  " + nextUp.next.title : ""      // the when first: the title may be cut
                    color: cal.pal.fg
                    font.family: Tokens.font.ui
                    font.weight: Font.DemiBold
                    font.pixelSize: cal.u(12)
                }
            }
        }
    }
}
