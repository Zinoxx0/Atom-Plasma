import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "Rice"
import "Rice/Color.js" as C
import "Weather.js" as W

// The clock block, in the wallpaper's quiet zone: (Clawd standing on the digits, on one screen,) the
// time in two weights with the colon in the accent, the date spaced out, and one status line
// (weather · theme · music). Hovering shows the next hours of weather. Ink (light or dark) and side
// (left or right) come from the layout, so it reads on that spot of that wallpaper.
DeskWindow {
    id: cw
    box: d.lay ? d.lay.clock : null

    readonly property bool right: d.lay ? d.lay.align === "right" : true
    readonly property bool dark: d.lay ? d.lay.ink === "dark" : false
    readonly property color ink: dark ? "#14151b" : "#f7f8fc"
    readonly property color inkDim: C.alpha(ink, 0.76)
    readonly property color accent: dark ? C.mix(d.pal.primary, "#000000", 0.3) : C.mix(d.pal.primary, "#ffffff", 0.08)
    readonly property real bh: height
    readonly property int timeSize: Math.round(bh * 0.36)
    readonly property int dateSize: Math.max(10, Math.round(bh * 0.062))
    readonly property int statusSize: Math.max(10, Math.round(bh * 0.058))
    readonly property var loc: Qt.locale("en_GB")
    readonly property int align: right ? Qt.AlignRight : Qt.AlignLeft
    // room for the shadow inside the window: on fractional scales the compositor stretches a window's
    // last pixel column, so anything drawn there (a shadow) shows as a hard line
    readonly property real pad: Math.round(Math.max(bh * 0.07, 30))

    // the status line: what's out there, which look this is, what's playing (the music card shows it
    // where it lives)
    readonly property var music: d.player
    readonly property var parts: [
        d.desk.theme ? d.desk.theme : "",
        !d.desk.media && music && music.present ? "♫  " + music.track + (music.artist ? " — " + music.artist : "") : ""
    ].filter(s => s !== "")

    HoverHandler { id: hover }

    Item {
        id: art
        anchors.fill: parent
        // one soft shadow (or glow, on dark ink) under everything, so it reads on any wallpaper. The
        // layer gets a transparent margin: a blur that reached its edge smeared into a 1 px line
        layer.enabled: true
        layer.sourceRect: Qt.rect(-cw.pad * 2, -cw.pad * 2, width + cw.pad * 4, height + cw.pad * 4)
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: cw.dark ? "#ffffff" : "#000000"
            shadowOpacity: cw.dark ? 0.5 : 0.55
            shadowBlur: 0.6
            shadowVerticalOffset: cw.dark ? 0 : 2
            shadowHorizontalOffset: 0
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: cw.bh * 0.2; leftMargin: cw.pad; rightMargin: cw.pad }
            spacing: 0

            Row {
                id: timeRow
                Layout.alignment: cw.align
                Text {
                    id: hh
                    text: Qt.formatTime(cw.d.now, "HH")
                    color: cw.ink
                    font.family: Tokens.font.display
                    font.weight: Font.Bold
                    font.pixelSize: cw.timeSize
                }
                Text {
                    text: ":"
                    color: cw.accent
                    font.family: Tokens.font.display
                    font.weight: Font.Light
                    font.pixelSize: cw.timeSize
                }
                Text {
                    id: mm
                    text: Qt.formatTime(cw.d.now, "mm")
                    color: cw.ink
                    font.family: Tokens.font.display
                    font.weight: Font.ExtraLight
                    font.pixelSize: cw.timeSize
                }
            }
            Text {
                Layout.alignment: cw.align
                Layout.topMargin: -Math.round(cw.timeSize * 0.1)
                text: cw.d.now.toLocaleDateString(cw.loc, "dddd  ·  d MMMM").toUpperCase()
                color: cw.inkDim
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: cw.dateSize
                font.letterSpacing: cw.dateSize * 0.32
            }
            Row {
                Layout.alignment: cw.align
                Layout.maximumWidth: col.width
                Layout.topMargin: Math.round(cw.bh * 0.035)
                spacing: Math.round(cw.statusSize * 0.5)
                Text {          // the weather leads: its glyph, temperature, the sky in a word
                    visible: !!cw.d.weather
                    anchors.verticalCenter: parent.verticalCenter
                    text: cw.d.weather ? W.icon(cw.d.weather.now.code, cw.d.weather.now.day) : ""
                    color: cw.accent
                    font.family: Tokens.font.icons
                    font.pixelSize: Math.round(cw.statusSize * 1.35)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, col.width - cw.statusSize * 2.2)
                    elide: Text.ElideRight
                    text: [cw.d.weather ? cw.d.weather.now.temp + "°  " + W.word(cw.d.weather.now.code) : ""].concat(cw.parts)
                          .filter(s => s !== "").join("   ·   ")
                    color: cw.ink
                    font.family: Tokens.font.ui
                    font.weight: Font.Medium
                    font.pixelSize: cw.statusSize
                }
            }
            // a check-in from Claude, in the hover forecast's place (so the window has room), until it's
            // settled (a click on Clawd marks it done); hovering still shows the forecast
            Text {
                visible: cw.d.asking && cw.d.desk.clawd === true && !hover.hovered
                Layout.alignment: cw.align
                Layout.maximumWidth: col.width
                Layout.topMargin: Math.round(cw.bh * 0.045)
                elide: Text.ElideRight
                text: "!   " + cw.d.askMsg
                color: cw.dark ? "#b4233c" : "#ff7d92"
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: cw.statusSize
            }
            // the next hours, on hover, on one line: hour, sky, temperature
            Row {
                Layout.alignment: cw.align
                Layout.topMargin: Math.round(cw.bh * 0.045)
                spacing: Math.round(cw.statusSize * 1.1)
                opacity: hover.hovered && cw.d.weather ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                Repeater {
                    model: cw.d.weather ? cw.d.weather.hours.slice(0, col.width < cw.statusSize * 30 ? 4 : 6) : []
                    Row {
                        required property var modelData
                        spacing: Math.round(cw.statusSize * 0.3)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.h
                            color: cw.inkDim
                            font.family: Tokens.font.ui
                            font.pixelSize: Math.round(cw.statusSize * 0.85)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: W.icon(parent.modelData.code, parent.modelData.day)
                            color: cw.accent
                            font.family: Tokens.font.icons
                            font.pixelSize: Math.round(cw.statusSize * 1.15)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.temp + "°"
                            color: cw.ink
                            font.family: Tokens.font.ui
                            font.weight: Font.DemiBold
                            font.pixelSize: Math.round(cw.statusSize * 0.9)
                        }
                    }
                }
            }
        }
    }

    // Clawd, standing on the minutes (one screen). Outside the shadowed layer: pixel art stays crisp
    Clawd {
        visible: cw.d.desk.clawd === true
        px: Math.max(2, Math.floor(cw.bh * 0.18 / 11))
        x: col.x + timeRow.x + mm.x + mm.width / 2 - width / 2
        y: col.y + timeRow.y + Math.round(cw.timeSize * 0.2) - height
        continuous: false
        mood: cw.d.mood
        usage: cw.d.peak
        working: cw.d.working
        activity: cw.d.activity
        weather: cw.d.sky
        daypart: cw.d.daypart
        season: cw.d.season
        pal: cw.d.pal.values
        alert: cw.d.asking
        onAlertClicked: cw.d.askDone()
        interactive: true
        animate: cw.visible
    }
}
