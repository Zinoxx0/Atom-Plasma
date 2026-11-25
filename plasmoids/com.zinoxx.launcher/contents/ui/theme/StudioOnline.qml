import QtQuick
import Atom
import Rice

// The Theme page's "Find more online": wallhaven, in the page's own language. A search field (describe it: a place, a
// mood, a time of day), your recent searches and a few ideas as chips, then what it found as a grid (shaped for the
// screen being edited, ones you have or had left out: bin/wallhaven.py --browse). Nothing is kept until you pick it:
// A (a click) adds it to your wallpapers (--get), A again sets it on the screen. More brings the next ones.
Item {
    id: on
    required property Item studio
    readonly property var lk: studio.look
    function d(px) { return studio.d(px) }
    readonly property alias field: field

    Row {
        id: bar
        spacing: on.d(10)
        Focusable {
            id: fieldBox
            studio: on.studio
            fkey: "on:field"
            width: on.d(640); height: on.d(52)
            lensRadius: height / 2
            readonly property bool typing: field.activeFocus
            desc: "<b>Search wallhaven</b> Describe it: a place, a mood, a time of day (cozy rain, night city, mountains)."
            act: typing ? "Search" : "Type"
            onActivated: { if (typing) on.studio.browse(field.text, false); else on.studio.startTyping(field) }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: C.alpha(on.lk.surfaceLowest, fieldBox.typing ? 0.7 : 0.45)
                border.width: on.d(1.5)
                border.color: fieldBox.typing ? on.lk.primary : C.alpha(on.lk.fg, 0.16)
                Behavior on border.color { ColorAnimation { duration: Tokens.ms(200) } }
            }
            Text {
                id: mag
                x: on.d(18); anchors.verticalCenter: parent.verticalCenter
                text: "search"; color: on.lk.fgDim
                font.family: Tokens.font.icons; font.pixelSize: on.d(22)
            }
            TextInput {
                id: field
                x: mag.x + mag.width + on.d(12)
                width: parent.width - x - on.d(20)
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: on.lk.fg
                selectionColor: on.lk.primary
                selectedTextColor: on.lk.surfaceLowest
                font.family: Tokens.font.ui; font.pixelSize: on.d(17)
                text: on.studio.onlineQuery
                onAccepted: on.studio.browse(text, false)
                Keys.onEscapePressed: event => { on.studio.stopTyping(); event.accepted = true }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) { on.studio.stopTyping(); on.studio.move(0, event.key === Qt.Key_Down ? 1 : -1); event.accepted = true }
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { on.studio.stopTyping(); on.studio.stepSection(event.key === Qt.Key_Tab ? 1 : -1); event.accepted = true }
                }
                Text {
                    visible: !field.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Describe what you'd like: cozy rain, night city, mountains…"
                    color: C.alpha(on.lk.fgDim, 0.8)
                    font: field.font
                }
            }
        }
        StudioChip {
            studio: on.studio
            anchors.verticalCenter: parent.verticalCenter
            fkey: "on:go"
            icon: "search"
            text: "Search"
            desc: "<b>Search</b> What you typed, or a surprise when it's empty."
            act: "Search"
            onActivated: on.studio.browse(field.text, false)
        }
    }
    // your recent searches, then ideas
    Flow {
        id: ideas
        y: bar.height + on.d(18)
        width: parent.width
        spacing: on.d(10)
        Repeater {
            model: on.studio.onlineIdeas
            StudioChip {
                required property var modelData
                studio: on.studio
                fkey: "on:idea:" + modelData.q
                icon: modelData.recent ? "history" : ""
                text: modelData.q
                chosen: on.studio.onlineQuery === modelData.q
                desc: "<b>" + modelData.q + "</b> " + (modelData.recent ? "You looked for this before: the next ones you don't have." : "An idea to start from.")
                act: "Search"
                onActivated: on.studio.browse(modelData.q, false)
            }
        }
    }
    Text {     // what's going on: looking, nothing new, no connection
        y: ideas.y + ideas.height + on.d(26)
        visible: on.studio.onlineState !== "" && !on.studio.onlineResults.length
        text: on.studio.onlineState === "busy" ? "Looking on wallhaven…" : on.studio.onlineState === "error" ? "Couldn't reach wallhaven. Check the connection and try again."
            : on.studio.onlineState === "empty" ? "Nothing new for that. Try other words." : "Search, or pick an idea above."
        color: on.lk.fgDim
        font.family: Tokens.font.ui; font.pixelSize: on.d(17)
    }
    StudioGrid {
        id: grid
        studio: on.studio
        visible: on.studio.onlineResults.length > 0
        y: ideas.y + ideas.height + on.d(24)
        width: on.width
        height: on.height - y
        fkey: "on:grid"
        list: on.studio.onlineResults
        index: on.studio.onlineIndex
        readonly property var cur: on.studio.onlineResults[on.studio.onlineIndex] || null
        act: cur && on.studio.added(cur) ? "Set on " + on.studio.targetLabel : "Add to yours"
        badgesOf: function (it) { return it.res ? [it.res] : [] }
        stateOf: function (it) { const s = on.studio.adding[it.id]; return !s ? "" : s === "busy" ? "busy" : "done" }
        tagOf: function (it) { return (it.res || "") + (it.fav ? "  ·  ♥ " + it.fav : "") }
        descOf: function (it) {
            return on.studio.added(it) ? "<b>In your wallpapers</b>" + (on.studio.actKey ? " " + on.studio.actKey + " sets it on " + on.studio.targetLabel + "." : "")
                 : "<b>From wallhaven</b> " + (it.res || "") + (it.fav ? ", liked " + it.fav + " times" : "") + (on.studio.actKey ? ". " + on.studio.actKey + " adds it to your wallpapers." : "")
        }
        onMoved: i => on.studio.setOnlineIndex(i)
        onActivated: it => on.studio.onlinePick(it)
    }
    function wheel(dy) { grid.wheel(dy) }
    Connections {
        target: on.studio
        function onOnlineFresh() { grid.toTop() }
        function onOnlineQueryChanged() { if (!field.activeFocus) field.text = on.studio.onlineQuery }
    }
}
