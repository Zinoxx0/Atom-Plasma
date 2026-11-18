import QtQuick
import org.kde.kirigami as Kirigami
import Rice

// Atom's Games (the user, 2026-11-16: banners like the Epic launcher, 2-3 rows, more when the launcher is small): the
// focused game's art fills the scene; the caption (its logo, play time, last session, Play / Options and the library's
// tools: Scan for games, Add a game, Open Steam); the library as a grid of banners on the right (Steam's library header;
// a game without one gets a card in its icon's colour), as many columns as fit, scrolling by rows; store chips (LT/RT).
// Keys/pad: the arrows walk the grid, left from its first column goes to the caption's buttons, right comes back.
Item {
    id: page
    required property var stage
    anchors.fill: parent
    readonly property var all: {
        page.stage.home.rev
        const rows = ((page.stage.home.pages[1] || {}).rows) || []
        const out = []
        for (const r of rows) for (const a of r.items) if (!out.some(x => x.key === a.key)) out.push(a)
        return out.map(a => ({ key: a.key, name: a.name, desc: a.desc, icon: a.icon, model: a.model, row: a.row, roles: a.roles,
                               banner: a.art ? a.art.header : "", hero: a.art ? a.art.hero : "", logo: a.art ? a.art.logo : "",
                               steam: !!a.art, played: a.played || 0, lastPlayed: a.lastPlayed || a.last || 0 }))
    }
    readonly property var stores: ["All", "Steam", "Other"]
    property int store: 0
    readonly property var games: all.filter(g => store === 0 || (store === 1) === g.steam)
    property int cur: 0
    property string zone: "grid"            // grid | cap (the caption's buttons)
    property int btn: 0
    readonly property var game: games[Math.min(cur, games.length - 1)] || null
    readonly property var tools: [["refresh", "Scan for games"], ["add", "Add a game"], ["open_in_new", "Open Steam"]]

    // the grid
    readonly property real cw: page.stage.d(440) * page.stage.launcher.homeSize / 1.1
    readonly property real ch: cw * 215 / 460
    readonly property real gap: page.stage.d(22)
    Item {
        id: lib
        x: page.stage.d(900); y: page.stage.d(130)
        width: page.stage.width - x - page.stage.side
        height: page.stage.height - y - page.stage.d(90)
        Row {
            id: chips
            anchors.right: parent.right
            spacing: page.stage.d(8)
            Text { text: "Library"; color: page.stage.look.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: page.stage.d(16); anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: page.stores
                Rectangle { required property string modelData; required property int index
                    width: ct.implicitWidth + page.stage.d(24); height: page.stage.d(34); radius: height / 2
                    color: page.store === index ? C.alpha(page.stage.look.fg, 0.14) : "transparent"
                    Text { id: ct; anchors.centerIn: parent; text: modelData; color: page.store === index ? page.stage.look.fg : page.stage.look.fgDim
                           font.family: Tokens.font.ui; font.weight: Font.Medium; font.pixelSize: page.stage.d(15) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.setStore(index) } }
            }
        }
        GridView {          // whole rows only (as many as fit), scrolled a row at a time; a margin inside for the focus's glow
            id: grid
            readonly property real pad: page.stage.d(16)
            anchors.top: chips.bottom; anchors.topMargin: page.stage.d(18) - pad
            readonly property int cols: Math.max(1, Math.floor((lib.width + page.gap) / (page.cw + page.gap)))
            readonly property int rows: Math.max(1, Math.floor((lib.height - chips.height - page.stage.d(18) + page.gap) / (page.ch + page.gap)))
            width: cols * cellWidth + 2 * pad
            height: rows * cellHeight + 2 * pad - page.gap
            anchors.right: parent.right; anchors.rightMargin: -page.gap - pad
            leftMargin: pad; rightMargin: pad; topMargin: pad; bottomMargin: pad
            cellWidth: page.cw + page.gap; cellHeight: page.ch + page.gap
            model: page.games.length
            interactive: false
            clip: true
            Behavior on contentY { NumberAnimation { duration: Tokens.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
            delegate: Item {
                id: card
                required property int index
                readonly property var g: page.games[index] || null
                readonly property bool on: page.zone === "grid" && page.cur === index
                width: page.cw; height: page.ch
                scale: on ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.ms(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Tokens.calmIn } }
                opacity: M.clamp((page.stage.atomT - 0.25 - index * 0.04) * 3)
                Kirigami.ShadowedRectangle {        // a game without a banner: its icon's colour
                    anchors.fill: parent; radius: page.stage.d(18)
                    visible: !card.g || !card.g.banner
                    color: C.mix(C.appTint(colours, page.stage.look.primary), "#000000", 0.45)
                    shadow.size: page.stage.d(30); shadow.yOffset: page.stage.d(12); shadow.color: Qt.rgba(0, 0, 0, 0.4)
                    ImagePalette { id: colours; source: card.g && !card.g.banner ? card.g.icon : "" }
                    Row { anchors.verticalCenter: parent.verticalCenter; x: page.stage.d(26); spacing: page.stage.d(18)
                        Kirigami.Icon { width: page.ch * 0.42; height: width; source: card.g ? card.g.icon : ""; anchors.verticalCenter: parent.verticalCenter }
                        Text { width: page.cw - page.ch * 0.42 - page.stage.d(80); text: card.g ? card.g.name : ""; color: "#ffffff"; wrapMode: Text.WordWrap; maximumLineCount: 2
                               anchors.verticalCenter: parent.verticalCenter
                               font.family: page.stage.wideFamily; font.pixelSize: page.ch * 0.13; font.variableAxes: page.stage.wide(112, 680) } }
                }
                Kirigami.ShadowedImage {
                    anchors.fill: parent; radius: page.stage.d(18)
                    visible: !!(card.g && card.g.banner)
                    source: visible ? card.g.banner : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    color: "transparent"
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
                    shadow.size: page.stage.d(30); shadow.yOffset: page.stage.d(12); shadow.color: Qt.rgba(0, 0, 0, 0.4)
                }
                Rectangle {     // the focus: a white ring and the accent's glow
                    anchors.fill: parent; anchors.margins: -page.stage.d(2); radius: page.stage.d(20)
                    color: "transparent"; border.width: Math.max(2, page.stage.d(2)); border.color: page.stage.look.fg
                    opacity: card.on ? 1 : hm.containsMouse ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.ms(200) } }
                    Rectangle { anchors.fill: parent; anchors.margins: -page.stage.d(10); radius: page.stage.d(28); z: -1; color: "transparent"
                                border.width: page.stage.d(10); border.color: C.alpha(page.stage.look.primary, card.on ? 0.3 : 0) }
                }
                MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onContainsMouseChanged: if (containsMouse && page.pointerMoved()) { page.zone = "grid"; page.cur = card.index }
                    onClicked: mouse => { page.cur = card.index; page.zone = "grid"
                        if (mouse.button === Qt.RightButton) page.options(card); else page.play() } }
            }
        }
    }
    // the pointer: only real moves count, not cards sliding under a still pointer
    property double lastMove: 0
    property double quietUntil: 0
    HoverHandler { onPointChanged: page.lastMove = Date.now() }
    function pointerMoved() { return Date.now() - lastMove < 120 && Date.now() > quietUntil }

    function setStore(i) { store = (i + stores.length) % stores.length; cur = 0 }
    onCurChanged: grid.positionViewAtIndex(cur, GridView.Contain)       // (the row comes into view, eased)
    function play() { if (game) page.stage.launch(game) }
    function options(card) { if (game && game.model) page.stage.launcher.menu.openFor(card || grid.currentItem, game.model, game.row) }
    function tool(i) {
        if (i === 0) { page.stage.shell('python3 "$HOME/.config/plasma-rice/rice.py" launcher-data #scan'); page.stage.say("Looking for games…"); return }
        Qt.openUrlExternally(i === 1 ? "steam://open/games" : "steam://open/main")          // (Steam's "Add a game" lives in its library)
        page.stage.launcher.close()
    }

    readonly property var caption: {
        const g = game
        if (!g) return { where: ["Games"], name: "No games yet", desc: "Install some in Steam, or add one", tools: page.tools }
        const hrs = g.played >= 90 ? (Math.round(g.played / 6) / 10) + " h" : g.played > 0 ? g.played + " min" : ""
        const facts = []
        if (hrs) facts.push([hrs, "played"])
        if (g.lastPlayed) facts.push([Qt.formatDate(new Date(g.lastPlayed * 1000), "MMM d"), "last session"])
        facts.push([g.steam ? "Steam" : "Other", "store"])
        return { where: [page.stores[page.store] === "All" ? "All games" : page.stores[page.store], (cur + 1) + " of " + games.length],
                 name: g.name, logo: g.logo || "", facts: facts, acts: [["A", "Play"], ["X", "Options"]], tools: page.tools }
    }
    function publish() {
        if (!page.stage) return
        page.stage.caption = page.caption
        page.stage.focusItem = game ? { hero: game.hero || "" } : null
        page.stage.capFocus = zone === "cap" ? btn : -1
    }
    onCaptionChanged: publish()
    onZoneChanged: publish()
    onBtnChanged: publish()
    Component.onCompleted: {
        page.stage.pageApi = { act: i => i === 0 ? page.play() : page.options(null), tool: i => page.tool(i),
                               wheel: dy => { page.zone = "grid"; page.cur = Math.max(0, Math.min(page.games.length - 1, page.cur + (dy > 0 ? -grid.cols : grid.cols))); page.quietUntil = Date.now() + 300 } }
        page.stage.hints = { pad: [["✥", "Move"], ["A", "Play"], ["X", "Options"], ["LT RT", "Store"], ["LB RB", "Pages"], ["Y", "Theme"], ["B", "Close"]],
                             keys: [["← ↑ ↓ →", "Move"], ["Enter", "Play"], ["Menu", "Options"], ["PgUp PgDn", "Store"], ["Tab", "Pages"], ["Esc", "Close"]] }
        publish()
    }
    Component.onDestruction: if (page.stage) page.stage.capFocus = -1
    Connections {
        target: page.stage
        function onPageKey(event) {
            const k = event.key, n = page.games.length, cols = grid.cols, acts = 2, nt = page.tools.length
            page.quietUntil = Date.now() + 500
            if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) page.setStore(page.store + (k === Qt.Key_PageDown ? 1 : -1))
            else if (page.zone === "grid") {
                if (k === Qt.Key_Up && page.cur - cols >= 0) page.cur -= cols
                else if (k === Qt.Key_Down && page.cur + cols < n) page.cur += cols
                else if (k === Qt.Key_Right && page.cur % cols < cols - 1 && page.cur + 1 < n) page.cur++
                else if (k === Qt.Key_Left && page.cur % cols > 0) page.cur--
                else if (k === Qt.Key_Left) { page.zone = "cap"; page.btn = 0 }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) page.play()
                else if (k === Qt.Key_Menu) page.options(null)
                else if (k !== Qt.Key_Up && k !== Qt.Key_Down && k !== Qt.Key_Right) return
            } else {            // the caption's buttons: Play, Options, then the tools under them
                const row = page.btn < acts ? 0 : 1, col = row ? page.btn - acts : page.btn, len = row ? nt : acts
                if (k === Qt.Key_Right && col === len - 1) page.zone = "grid"
                else if (k === Qt.Key_Right) page.btn++
                else if (k === Qt.Key_Left && col > 0) page.btn--
                else if (k === Qt.Key_Down && row === 0) page.btn = acts + Math.min(col, nt - 1)
                else if (k === Qt.Key_Up && row === 1) page.btn = Math.min(col, acts - 1)
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (page.btn < acts) page.stage.act(page.btn); else page.tool(page.btn - acts) }
                else if (k !== Qt.Key_Left && k !== Qt.Key_Up && k !== Qt.Key_Down) return
            }
            event.accepted = true
        }
    }
}
