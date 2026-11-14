import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import org.kde.plasma.plasmoid
import Atom
import "Rice"
import "Rice/Color.js" as C

// The clock island: "Sun 8  04:10" in the bar's type (Inter Display, ui.clock_pt x the screen's UI size,
// like the stock clock it replaces): the time bright and bold, the date dimmer and lighter. A click opens the calendar on the shell's sheet (Atom
// panels/Calendar.qml), grown out of this island. A small dot lights up when an event starts within half
// an hour. It keeps the agenda fresh: agenda.py every 15 minutes (it throttles: several clocks, one fetch).
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property real ui: pal.uiScale

    // the time, updated on the minute (no busy ticking)
    property date now: new Date()
    Timer {
        id: tick
        interval: 60000 - (Date.now() % 60000) + 50
        running: true
        onTriggered: { root.now = new Date(); interval = 60000 - (Date.now() % 60000) + 50; restart() }
    }

    // the agenda: fetched by agenda.py, watched here for the "soon" dot
    RiceShell { id: sh; onNewData: (source, data) => disconnectSource(source) }
    // every bar has a clock, but the islands show on one screen (kwin/rice_islands): only that bar's clock
    // fetches (all of them until KWin has said which, as before)
    Timer {
        interval: 15 * 60 * 1000
        running: Shell.barShown(root.Window.window ? Screen.name : "")
        repeat: true
        triggeredOnStart: true
        onTriggered: sh.connectSource('python3 "$HOME/.config/plasma-rice/agenda.py" >/dev/null #run')
    }
    WatchedJson {
        id: agenda
        path: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + "/.cache/rice/calendar.json"
    }
    readonly property var soon: {
        const t = now.getTime()
        for (const e of ((agenda.value || {}).events || [])) {
            if (e.allDay) continue
            const s = new Date(e.start).getTime()
            if (s > t && s - t <= 30 * 60000) return e
        }
        return null
    }

    toolTipMainText: Qt.formatDate(now, "dddd, d MMMM yyyy")
    toolTipSubText: soon ? "Soon: " + soon.title + " at " + Qt.formatTime(new Date(soon.start), "HH:mm") : "Calendar"
    preferredRepresentation: compactRepresentation

    compactRepresentation: Island {
        id: compact
        kind: "calendar"
        // whole pixels: the panel sizes a widget to the floor of a fractional width but keeps the room,
        // and the island's glass then parts at the joint (a hairline of wallpaper)
        Layout.minimumWidth: Math.ceil(row.implicitWidth) + 2 * Math.round(Tokens.space.md * root.ui)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Math.round(7 * root.ui)
            // the time leads (bright, bold, digits of one width: the island never shifts by the minute);
            // the date steps back (dimmer, lighter)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.now, "ddd d")
                color: compact.open ? C.alpha(pal.primary, 0.8) : pal.fgDim
                font.family: "Inter Display"
                font.weight: Font.Medium
                font.pointSize: Math.max(6, Math.round(11 * root.ui))
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatTime(root.now, "HH:mm")
                color: compact.open ? pal.primary : pal.fg
                font.family: "Inter Display"
                font.weight: Font.Bold
                font.pointSize: Math.max(6, Math.round(11 * root.ui))
                font.features: { "tnum": 1 }
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            Rectangle {     // an event within half an hour
                anchors.verticalCenter: parent.verticalCenter
                visible: root.soon !== null
                width: Math.round(6 * root.ui); height: width; radius: width / 2
                color: pal.primary
            }
        }
    }
    // never shown (the panel is the shell's), but a panel applet draws nothing without one
    fullRepresentation: Item {}
}
