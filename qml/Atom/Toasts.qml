import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQCA
import org.kde.notificationmanager as NM
import "../Rice"
import "../Rice/Color.js" as C

// A screen's notification cards (in its SheetWindow): they show on the screen you're working on (the
// active window's; the main bar's when none), grow out of the status island (or the bar's corner),
// settle in a stack above it, newest nearest the island, and fold back into it when they go. The same
// app and sender (a chat) share one card with a count. Three at most; the rest wait behind "n more".
// Hover holds a card; a click runs its default action; the actions are pills; jobs show their progress.
// Do Not Disturb holds everything but critical ones (they still go to the history and the beads).
Item {
    id: toasts
    required property string screenName
    required property RicePalette pal
    property real ui: 1
    property rect island: Qt.rect(width - u(64), height - u(52), u(48), u(36))   // this window's coordinates (default: the bar's corner)
    property bool blocked: false                // the apps' panel is open here: news goes there
    function u(n) { return Math.round(n * ui) }

    // the screen they show on
    readonly property string home: Windows.activeScreen || mainScreen
    readonly property string mainScreen: {
        for (const k in Shell.islands) if (k.endsWith("/control")) return k.split("/")[0]
        return ""
    }
    readonly property bool here: home === screenName || (home === "" && screenName !== "")

    NM.Settings { id: settings }
    NM.Notifications {
        id: popups
        showNotifications: true
        showJobs: true
        showExpired: false
        showDismissed: false
        sortMode: NM.Notifications.SortByDate
        sortOrder: Qt.AscendingOrder
        groupMode: NM.Notifications.GroupDisabled
        urgencies: NM.Notifications.NormalUrgency | NM.Notifications.CriticalUrgency
        blacklistedDesktopEntries: settings.popupBlacklistedApplications
        blacklistedNotifyRcNames: settings.popupBlacklistedServices
    }
    readonly property bool quiet: NM.Server.inhibited
    // bumped on every change of the model: a new row's text arrives after the row itself, and the chat
    // grouping below reads rows by hand (data() isn't tracked by bindings)
    property int rev: 0
    Connections {
        target: popups
        function onDataChanged() { toasts.rev++ }
        function onRowsInserted() { toasts.rev++ }
        function onRowsRemoved() { toasts.rev++ }
        function onModelReset() { toasts.rev++ }
    }
    // a card goes with the earlier messages it stood for (from the newest down: rows shift as they go;
    // here, not in the card: removing its row destroys the card mid-loop)
    function dismiss(row, chat, closeIt) {
        for (let i = row; i >= 0; i--) {
            if (i !== row && chatAt(i) !== chat) continue
            const ix = popups.index(i, 0)
            if (closeIt) popups.close(ix); else popups.expire(ix)
        }
    }
    function chatAt(i) {
        const ix = popups.index(i, 0)
        return String(popups.data(ix, NM.Notifications.DesktopEntryRole) || popups.data(ix, NM.Notifications.ApplicationNameRole) || "")
             + "|" + String(popups.data(ix, NM.Notifications.SummaryRole) || "")
    }

    // the shapes that take the pointer (for the window's input mask), window coordinates
    property var shapes: []
    function measure() {
        const out = []
        for (let i = 0; i < stack.children.length; i++) {
            const c = stack.children[i]
            if (!c.visible || c.height < 2 || !c.isCard || c.leaving) continue    // a folding card lets go at once
            const p = c.mapToItem(toasts, 0, 0)
            out.push({ x: p.x, y: p.y, width: c.width, height: c.height, radius: u(20) })
        }
        if (more.visible) { const p = more.mapToItem(toasts, 0, 0); out.push({ x: p.x, y: p.y, width: more.width, height: more.height, radius: more.height / 2 }) }
        shapes = out
    }
    Timer { id: remeasure; interval: 30; onTriggered: toasts.measure() }
    // again once the stack's move has played: measured mid-way, a card that slid down when another left kept
    // a shape over the bar (it took the status island's clicks until the next toast)
    Timer { id: settled; interval: Tokens.ms(420) + 40; onTriggered: toasts.measure() }
    function remeasureSoon() { remeasure.restart(); settled.restart() }

    // ------------------------------------------------------------------ the stack
    readonly property real cardW: u(380)
    readonly property real edgeRight: Math.min(width - u(12), island.x + island.width)    // (not "right": FINAL on every Item)
    Column {
        id: stack
        x: Math.max(toasts.u(12), toasts.edgeRight - toasts.cardW)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: toasts.height - toasts.island.y + toasts.u(12)
        width: toasts.cardW
        spacing: toasts.u(10)
        onPositioningComplete: toasts.remeasureSoon()
        move: Transition { NumberAnimation { properties: "y"; duration: Tokens.ms(420); easing.type: Tokens.grow } }

        Rectangle {     // more waiting
            id: more
            readonly property bool isCard: false
            readonly property int hidden: Math.max(0, cards.shownCount - 3)
            visible: hidden > 0 && toasts.here
            anchors.right: parent.right
            height: toasts.u(28)
            width: moreText.implicitWidth + toasts.u(24)
            radius: height / 2
            color: C.alpha(Tokens.neutral.dark, 0.88)
            border.width: 1
            border.color: C.alpha(toasts.pal.edge, Tokens.alpha.outline)
            Text { id: moreText; anchors.centerIn: parent; text: more.hidden + " more"; color: toasts.pal.fgDim; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: toasts.u(12) }
        }

        Repeater {
            id: cards
            model: popups
            // a card per chat: the newest of its app + sender only
            property int shownCount: 0
            function recount() { let n = 0; for (let i = 0; i < count; i++) { const c = itemAt(i); if (c && c.lead) n++ } shownCount = n }
            onCountChanged: Qt.callLater(recount)
            delegate: Item {
                id: card
                required property int index
                required property var model
                readonly property bool isCard: true
                readonly property string chat: { toasts.rev; return String(model.desktopEntry || model.applicationName || "") + "|" + String(model.summary || "") }
                // later cards of the same chat absorb this one
                readonly property int later: {
                    toasts.rev
                    let n = 0
                    for (let i = index + 1; i < popups.count; i++) if (toasts.chatAt(i) === chat) n++
                    return n
                }
                readonly property int earlier: {
                    toasts.rev
                    let n = 0
                    for (let i = 0; i < index; i++) if (toasts.chatAt(i) === chat) n++
                    return n
                }
                readonly property bool lead: later === 0
                readonly property bool isJob: model.type === NM.Notifications.JobType
                readonly property bool critical: model.urgency === NM.Notifications.CriticalUrgency
                readonly property int slot: {          // 0 = nearest the island
                    toasts.rev
                    let n = 0
                    for (let i = index + 1; i < cards.count; i++) { const c = cards.itemAt(i); if (c && c.lead) n++ }
                    return n
                }
                readonly property bool shown: toasts.here && lead && slot < 3 && !toasts.blocked && (!toasts.quiet || critical)
                visible: shown || leaving
                width: stack.width
                height: visible ? body.implicitHeight : 0
                onLeadChanged: Qt.callLater(cards.recount)
                Component.onCompleted: { Qt.callLater(cards.recount); if (shown) { grow.restart(); popups.playSoundHint(popups.index(index, 0)) } }
                Component.onDestruction: toasts.remeasureSoon()     // a gone card may not move the others (no new positioning)
                onShownChanged: if (shown && !leaving) grow.restart()

                // time: its own, or 6 s (critical ones stay); hover holds it
                property bool leaving: false
                Timer {
                    id: life
                    interval: card.model.timeout > 0 ? card.model.timeout : 6500
                    running: card.shown && !card.critical && !card.isJob && !hold.hovered && !card.leaving
                    onTriggered: card.leave(false)
                }
                function leave(closeIt) {
                    leaving = true
                    toasts.remeasureSoon()
                    fold.closeIt = closeIt
                    fold.restart()
                }

                // grows out of the island: from its rect to the card's
                property real g: 1
                readonly property point from: {
                    const p = toasts.mapToItem(card, toasts.island.x + toasts.island.width / 2, toasts.island.y + toasts.island.height / 2)
                    return p
                }
                NumberAnimation { id: grow; target: card; property: "g"; from: 0; to: 1; duration: Tokens.ms(480); easing.type: Tokens.grow }
                SequentialAnimation {
                    id: fold
                    property bool closeIt: false
                    NumberAnimation { target: card; property: "g"; to: 0; duration: Tokens.ms(300); easing.type: Easing.InOutCubic }
                    ScriptAction { script: toasts.dismiss(card.index, card.chat, fold.closeIt) }
                }

                Item {
                    id: body
                    width: parent.width
                    implicitHeight: col.implicitHeight + toasts.u(28)
                    height: implicitHeight
                    opacity: Math.min(1, card.g * 1.6)
                    transform: [
                        Scale {
                            origin.x: card.from.x; origin.y: card.from.y
                            xScale: 0.25 + 0.75 * card.g; yScale: 0.25 + 0.75 * card.g
                        }
                    ]
                    HoverHandler { id: hold }
                    Rectangle {     // obsidian, lit at the top in the app's colour
                        anchors.fill: parent
                        radius: toasts.u(20)
                        color: C.alpha(Tokens.neutral.dark, 0.9)
                        border.width: 1
                        border.color: C.alpha(tint.c, hold.hovered ? 0.7 : 0.4)
                        Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                            height: toasts.u(46)
                            radius: parent.radius - 1
                            gradient: Gradient {
                                GradientStop { position: 0; color: C.alpha(tint.c, 0.16) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                    }
                    QtObject { id: tint; readonly property color c: C.appTint(colors, toasts.pal.primary) }
                    Kirigami.ImageColors { id: colors; source: card.model.applicationIconName || card.model.desktopEntry || "" }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: card.model.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (card.model.hasDefaultAction) popups.invokeDefaultAction(popups.index(card.index, 0))
                            Notify.markSeen(Notify.keyOf(card.model.desktopEntry, card.model.applicationName))
                            card.leave(false)
                        }
                    }
                    RowLayout {
                        id: col
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: toasts.u(14) }
                        spacing: toasts.u(12)
                        Item {      // the sender's picture, or the app's icon
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: toasts.u(42); implicitHeight: implicitWidth
                            Rectangle { anchors.fill: parent; radius: width / 2; color: C.alpha(tint.c, 0.18) }
                            KQCA.QImageItem {      // drawn through the round mask below
                                id: pic
                                anchors.fill: parent
                                visible: false
                                image: card.model.image
                                fillMode: KQCA.QImageItem.PreserveAspectCrop
                            }
                            Rectangle { id: picMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
                            MultiEffect {
                                anchors.fill: parent
                                visible: !pic.null
                                source: pic
                                maskEnabled: true
                                maskSource: picMask
                            }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                visible: pic.null
                                width: toasts.u(26); height: width
                                source: card.model.iconName || card.model.applicationIconName || card.model.desktopEntry || "preferences-desktop-notification"
                            }
                            Rectangle {     // the app, small on the corner of a picture
                                visible: !pic.null
                                anchors { right: parent.right; bottom: parent.bottom; margins: -toasts.u(3) }
                                width: toasts.u(18); height: width; radius: width / 2
                                color: Tokens.neutral.dark
                                Kirigami.Icon { anchors.centerIn: parent; width: toasts.u(13); height: width; source: card.model.applicationIconName || card.model.desktopEntry || "" }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: toasts.u(2)
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: (card.model.applicationName || "") + (card.earlier > 0 ? "   ·   +" + card.earlier : "")
                                    elide: Text.ElideRight
                                    color: C.mix(toasts.pal.muted, tint.c, 0.45)
                                    font.family: Tokens.font.ui
                                    font.weight: Font.DemiBold
                                    font.pixelSize: toasts.u(11)
                                }
                                Text {
                                    text: Qt.formatTime(card.model.created || new Date(), "HH:mm")
                                    color: toasts.pal.muted
                                    font.family: Tokens.font.ui
                                    font.pixelSize: toasts.u(11)
                                }
                                Rectangle {     // close
                                    implicitWidth: toasts.u(20); implicitHeight: implicitWidth; radius: implicitWidth / 2
                                    opacity: hold.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                                    color: C.alpha(toasts.pal.fg, xm.containsMouse ? 0.16 : 0.08)
                                    Text { anchors.centerIn: parent; text: "close"; color: toasts.pal.fg; font.family: Tokens.font.icons; font.pixelSize: toasts.u(13) }
                                    MouseArea { id: xm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.leave(true) }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: card.model.summary || ""
                                elide: Text.ElideRight
                                color: toasts.pal.fg
                                font.family: Tokens.font.ui
                                font.weight: Font.DemiBold
                                font.pixelSize: toasts.u(14)
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: card.model.body || ""
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: toasts.pal.fgDim
                                font.family: Tokens.font.ui
                                font.pixelSize: toasts.u(13)
                            }
                            Rectangle {     // a job's progress
                                visible: card.isJob
                                Layout.fillWidth: true
                                Layout.topMargin: toasts.u(4)
                                implicitHeight: toasts.u(6)
                                radius: height / 2
                                color: C.alpha(toasts.pal.fg, 0.1)
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, (card.model.percentage || 0) / 100))
                                    height: parent.height
                                    radius: height / 2
                                    color: toasts.pal.primary
                                    Behavior on width { NumberAnimation { duration: Tokens.base } }
                                }
                            }
                            Flow {      // its actions
                                Layout.fillWidth: true
                                Layout.topMargin: visible ? toasts.u(6) : 0
                                visible: (card.model.actionLabels || []).length > 0
                                spacing: toasts.u(6)
                                Repeater {
                                    model: card.model.actionLabels || []
                                    delegate: Rectangle {
                                        id: act
                                        required property int index
                                        required property string modelData
                                        height: toasts.u(28)
                                        width: actText.implicitWidth + toasts.u(22)
                                        radius: height / 2
                                        color: C.alpha(tint.c, am.containsMouse ? 0.3 : 0.18)
                                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                        Text { id: actText; anchors.centerIn: parent; text: act.modelData; color: toasts.pal.fg; font.family: Tokens.font.ui; font.weight: Font.DemiBold; font.pixelSize: toasts.u(12) }
                                        MouseArea {
                                            id: am
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { popups.invokeAction(popups.index(card.index, 0), card.model.actionNames[act.index]); card.leave(false) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    onHereChanged: remeasure.restart()
    onBlockedChanged: remeasure.restart()
    onQuietChanged: remeasure.restart()
}
