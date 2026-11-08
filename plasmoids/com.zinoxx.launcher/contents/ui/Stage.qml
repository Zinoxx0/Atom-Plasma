import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import Atom
import "Rice"
import "Rice/Color.js" as C

// The launcher, fullscreen. It grows out of the bar's jewel (the accent pill): the pill's colour opens
// into this screen's wallpaper, blurred and dimmed, until it fills the screen; then the clock and a
// greeting, the search, the pinned apps, the categories and the grid rise in one after another. In the
// corner: the Theme page and the power orb. Typing searches; Esc clears, then closes; so does a click
// on the empty backdrop, Meta, or launching something (it shrinks back into the jewel).
// It is mapped only while open: unmapping hands the keyboard back to the window that had it, and the
// grow starts on the first frame, so the ~50 ms a surface takes to map is part of the motion.
Window {
    id: stage
    required property var launcher
    required property var screenObj
    required property RicePalette rice
    required property Account account
    readonly property string screenName: screenObj ? screenObj.name : ""
    function px(n) { return launcher.px(n) }

    screen: screenObj
    x: screenObj ? screenObj.virtualX : 0
    y: screenObj ? screenObj.virtualY : 0
    width: screenObj ? screenObj.width : 0
    height: screenObj ? screenObj.height : 0
    onScreenChanged: if (screenObj && screen?.name !== screenObj.name) screen = screenObj
    transientParent: null
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: phase !== "closed"

    LayerShell.Window.scope: "atom-launcher"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                             | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true
    LayerShell.Window.wantsToBeOnActiveScreen: false

    // ------------------------------------------------------------------ open / close
    readonly property bool wanted: Shell.kind === "launcher" && Shell.screen === screenName
    property string phase: "closed"             // closed, opening, open, closing
    property real p: 0                          // 0 = the jewel, 1 = the whole screen
    property rect jewel: Qt.rect(0, 0, 0, 0)
    readonly property bool contentIn: phase === "open" || (phase === "opening" && p > 0.4)
    signal opened()

    function local(r) {
        if (!r || !screenObj) return Qt.rect(px(16), height - px(48), px(64), px(36))
        return Qt.rect(r.x - screenObj.virtualX, r.y - screenObj.virtualY, r.width, r.height)
    }
    onWantedChanged: wanted ? begin() : end()
    function begin() {
        jewel = local(Shell.anchor || Shell.island("launcher", screenName))
        shrink.stop()
        if (phase === "closed") {
            p = 0
            phase = "opening"
            waitFrame = true            // grow once the surface is up
            opened()
        } else {
            phase = "opening"
            grow.restart()
        }
    }
    function end() {
        if (phase === "closed" || phase === "closing") return
        phase = "closing"
        grow.stop()
        waitFrame = false
        shrink.restart()
    }
    onPhaseChanged: if (Shell.debug) console.warn("ATOM stage", screenName, "phase", phase, "p", p.toFixed(2), Date.now() % 100000)
    onVisibleChanged: if (Shell.debug) console.warn("ATOM stage", screenName, "visible", visible, Date.now() % 100000)
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) { waitFrame = false; grow.restart() }
    NumberAnimation {
        id: grow
        target: stage; property: "p"; to: 1
        duration: Tokens.ms(460); easing.type: Tokens.grow
        onFinished: if (stage.phase === "opening") stage.phase = "open"
    }
    NumberAnimation {
        id: shrink
        target: stage; property: "p"; to: 0
        duration: Tokens.ms(300); easing.type: Tokens.exit
        onFinished: stage.phase = "closed"
    }

    // ------------------------------------------------------------------ the growing shape
    // from the jewel to the screen; its fill is the jewel's colour at first, then the blurred wallpaper
    // under a dim that deepens as it grows
    readonly property real rx: jewel.x * (1 - p)
    readonly property real ry: jewel.y * (1 - p)
    readonly property real rw: jewel.width + (width - jewel.width) * p
    readonly property real rh: jewel.height + (height - jewel.height) * p
    readonly property real rr: Math.min(jewel.height / 2, px(28)) * (1 - p)
    readonly property real wash: Math.max(0, 1 - p * 2.6)     // how much of the jewel's colour is left

    // the backdrop, drawn once at screen size and handed to the shape as a texture (smooth when stretched)
    Item {
        id: backdropArt
        width: stage.width
        height: stage.height
        Image {
            anchors.fill: parent
            smooth: true
            fillMode: Image.PreserveAspectCrop
            // the pre-blurred screen (rice.py, palette _glassFull); before rice.py has made one, a tiny copy
            // of the wallpaper stretched up reads as a blur too
            readonly property string pre: stage.rice.values._glassFull || ""
            source: pre ? "file://" + pre : stage.rice.wallpaper ? "file://" + stage.rice.wallpaper : ""
            sourceSize.width: pre ? 0 : 96
        }
    }
    ShaderEffectSource {
        id: backdrop
        width: stage.width
        height: stage.height
        visible: false
        sourceItem: backdropArt
        hideSource: true
        smooth: true
        live: stage.phase !== "closed"
    }
    Shape {
        anchors.fill: parent
        visible: stage.phase !== "closed"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillItem: backdrop
            PathRectangle { x: stage.rx; y: stage.ry; width: stage.rw; height: stage.rh; radius: stage.rr }
        }
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            readonly property color dim: Qt.rgba(0.03, 0.035, 0.06, stage.rice.light ? 0.28 : 0.42)
            readonly property color jewelFill: stage.rice.primary
            fillColor: Qt.rgba(jewelFill.r * stage.wash + dim.r * (1 - stage.wash),
                               jewelFill.g * stage.wash + dim.g * (1 - stage.wash),
                               jewelFill.b * stage.wash + dim.b * (1 - stage.wash),
                               stage.wash + dim.a * (1 - stage.wash))
            PathRectangle { x: stage.rx; y: stage.ry; width: stage.rw; height: stage.rh; radius: stage.rr }
        }
    }
    // depth: a little darker toward the bottom, where the grid sits (only once it covers the screen)
    Rectangle {
        anchors.fill: parent
        opacity: Math.max(0, (stage.p - 0.75) / 0.25)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 0.55; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.32) }
        }
    }
    // a click on the empty backdrop closes it
    MouseArea {
        anchors.fill: parent
        enabled: stage.phase === "open"
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: stage.launcher.close()
    }

    // ------------------------------------------------------------------ content
    // each block rises in after the one before it, and all leave together, fast
    // (an inline component sees no ids of this file: shown and lift come in as properties)
    component Rise: Item {
        id: rise
        property int order: 0
        property bool shown: false
        property real lift: 16
        readonly property int delay: order * Tokens.ms(55)
        opacity: shown ? 1 : 0
        Behavior on opacity { SequentialAnimation {
            PauseAnimation { duration: rise.shown ? rise.delay : 0 }
            NumberAnimation { duration: rise.shown ? Tokens.slow : Tokens.fast; easing.type: rise.shown ? Tokens.enter : Tokens.exit } } }
        transform: Translate {
            y: rise.shown ? 0 : rise.lift
            Behavior on y { SequentialAnimation {
                PauseAnimation { duration: rise.shown ? rise.delay : 0 }
                NumberAnimation { duration: rise.shown ? Tokens.ms(520) : Tokens.fast; easing.type: rise.shown ? Tokens.grow : Tokens.exit } } }
        }
    }

    onContentInChanged: if (contentIn) launcher.stageEntered()

    property date now: new Date()
    Timer { running: stage.phase !== "closed"; repeat: true; interval: 5000; triggeredOnStart: true; onTriggered: stage.now = new Date() }

    // the content only shows inside the growing shape (its bounds: the corners are small by then)
    Item {
        id: reveal
        x: stage.rx; y: stage.ry; width: stage.rw; height: stage.rh
        clip: stage.p < 1
        visible: stage.phase !== "closed"
    FocusScope {
        id: content
        x: -stage.rx
        y: -stage.ry
        width: stage.width
        height: stage.height
        focus: true
        visible: stage.phase !== "closed"
        enabled: stage.phase === "open" || stage.phase === "opening"
        readonly property real margin: stage.px(44)
        readonly property real colW: Math.min(stage.px(1000), stage.width - 2 * margin)

        // the apps: clock and greeting, search, then pinned / categories / grid or the results
        ColumnLayout {
            id: column
            x: Math.round((stage.width - content.colW) / 2)
            y: Math.round(Math.min(stage.px(72), stage.height * 0.07))
            width: content.colW
            height: stage.height - y - stage.px(112)
            spacing: 0
            opacity: stage.launcher.view === "apps" ? 1 : 0
            visible: opacity > 0
            enabled: stage.launcher.view === "apps"
            Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }

            Rise {
                order: 0
                shown: stage.contentIn; lift: stage.px(16)
                Layout.fillWidth: true
                implicitHeight: clockText.implicitHeight
                Text {
                    id: clockText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(stage.now, "HH:mm")
                    color: stage.rice.fg
                    font.family: Tokens.font.display
                    font.weight: Font.Light
                    font.pixelSize: stage.px(88)
                    font.letterSpacing: -stage.px(2)
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.5); shadowBlur: 0.8; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 }
                }
            }
            Rise {
                order: 1
                shown: stage.contentIn; lift: stage.px(16)
                Layout.fillWidth: true
                implicitHeight: greet.implicitHeight
                Text {
                    id: greet
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property string first: String(stage.account.displayName || "").split(" ")[0]
                    text: stage.launcher.greeting(stage.now.getHours()) + (first ? " " + first : "") + "   ·   "
                          + Qt.formatDate(stage.now, "dddd, d MMMM")
                    color: stage.rice.fgDim
                    font.family: Tokens.font.ui
                    font.weight: Font.Medium
                    font.pixelSize: stage.px(Tokens.size.title + 1)
                }
            }
            Item { implicitHeight: stage.px(30) }

            // search
            Rise {
                order: 2
                shown: stage.contentIn; lift: stage.px(16)
                Layout.fillWidth: true
                implicitHeight: searchBox.height
                Rectangle {
                    id: searchBox
                    width: parent.width
                    height: stage.px(56)
                    radius: height / 2
                    color: C.alpha(stage.rice.surfaceLowest, search.activeFocus ? 0.62 : 0.5)
                    border.width: 1
                    border.color: search.activeFocus ? C.alpha(stage.rice.primary, 0.8) : C.alpha(stage.rice.edge, Tokens.alpha.outlineStrong)
                    Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: search.forceActiveFocus() }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: stage.px(22)
                        anchors.rightMargin: stage.px(16)
                        spacing: stage.px(14)
                        Text {
                            text: "search"
                            color: search.activeFocus ? stage.rice.primary : stage.rice.muted
                            font.family: Tokens.font.icons
                            font.pixelSize: stage.px(24)
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TextInput {
                                id: search
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: stage.rice.fg
                                selectionColor: stage.rice.primary
                                selectedTextColor: stage.rice.onPrimary
                                font.family: Tokens.font.ui
                                font.pixelSize: stage.px(Tokens.size.heading)
                                clip: true
                                focus: true
                                onTextChanged: stage.launcher.query = text
                                Keys.onPressed: event => {
                                    const L = stage.launcher
                                    if (event.key === Qt.Key_Escape) {
                                        if (text) text = ""; else L.close()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && L.query)) {
                                        if (L.query) L.moveSelection(1)
                                        else { browse.gridView.forceActiveFocus(Qt.TabFocusReason); if (browse.gridView.currentIndex < 0) browse.gridView.currentIndex = 0 }
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Up) {
                                        if (L.query) L.moveSelection(-1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (L.query) L.activateSelection()
                                        else if (browse.gridView.currentIndex >= 0) L.launch(L.browseModel, browse.gridView.currentIndex)
                                        event.accepted = true
                                    }
                                }
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !search.text && !search.preeditText
                                text: "Search apps, settings, files… or do maths"
                                color: stage.rice.muted
                                font: search.font
                                elide: Text.ElideRight
                            }
                        }
                        Busy {
                            visible: stage.launcher.searching
                            running: visible
                            implicitWidth: stage.px(18); implicitHeight: implicitWidth
                            color: stage.rice.primary
                        }
                    }
                }
            }
            Item { implicitHeight: stage.px(26) }

            // pinned, categories and the grid; or the results
            Rise {
                order: 3
                shown: stage.contentIn; lift: stage.px(16)
                Layout.fillWidth: true
                Layout.fillHeight: true
                AppBrowse {
                    id: browse
                    anchors.fill: parent
                    visible: !stage.launcher.query
                    launcher: stage.launcher
                    rice: stage.rice
                    menu: stage.launcher.menu
                    kickerDrag: stage.launcher.kickerDrag
                    searchField: search
                }
                SearchResults {
                    anchors.fill: parent
                    visible: !!stage.launcher.query
                    launcher: stage.launcher
                    rice: stage.rice
                    menu: stage.launcher.menu
                    runnerModel: stage.launcher.runnerModel
                }
            }
        }

        // the Theme page (wallpapers, colours, size, lights) in a big glass card, built the first time
        Loader {
            id: walls
            readonly property real w: Math.min(stage.px(1220), stage.width - 2 * content.margin)
            readonly property real h: stage.height - 2 * stage.px(56)
            x: Math.round((stage.width - w) / 2)
            y: stage.px(56)
            width: w
            height: h
            active: stage.launcher.view === "walls" || item !== null
            opacity: stage.launcher.view === "walls" ? 1 : 0
            visible: opacity > 0
            enabled: stage.launcher.view === "walls"
            Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
            transform: Translate { x: stage.launcher.view === "walls" ? 0 : stage.px(28); Behavior on x { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } } }
            onEnabledChanged: if (enabled && item) Qt.callLater(() => item.focusPane())
            onLoaded: { stage.launcher.wallsPane = item; if (stage.launcher.openTab) item.tab = stage.launcher.openTab; stage.launcher.openTab = ""; item.focusPane() }
            sourceComponent: Item {
                property alias tab: pane.tab
                Glass {
                    anchors.fill: parent
                    radius: Tokens.radius.xl
                    fill: stage.rice.light ? Tokens.neutral.light : Tokens.neutral.dark
                    fillAlpha: 0.72
                    rimA: stage.rice.primary
                    rimB: stage.rice.tertiary
                }
                WallpaperPane {
                    id: pane
                    anchors.fill: parent
                    anchors.margins: Tokens.space.xl
                    cfg: stage.launcher.cfg
                    mode: "desktop"
                    onBack: { stage.launcher.view = "apps"; Qt.callLater(() => search.forceActiveFocus()) }
                }
                function focusPane() { pane.forceActiveFocus() }
            }
        }

        // bottom right: the Theme page and the power orb
        Rise {
            order: 4
            shown: stage.contentIn; lift: stage.px(16)
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: content.margin; bottomMargin: content.margin }
            implicitWidth: corner.implicitWidth
            implicitHeight: corner.implicitHeight
            Row {
                id: corner
                spacing: stage.px(12)
                layoutDirection: Qt.RightToLeft
                PowerOrb {
                    id: orb
                    size: stage.px(48)
                    fg: stage.rice.fg
                    fill: C.alpha(stage.rice.surfaceLowest, 0.55)
                    edge: C.alpha(stage.rice.edge, Tokens.alpha.outlineStrong)
                    tones: ({ primary: stage.rice.primary, secondary: stage.rice.secondary, tertiary: stage.rice.tertiary,
                              warn: stage.rice.warn, bad: stage.rice.bad })
                    onTriggered: a => { stage.launcher.close(); stage.launcher.run(a.cmd) }
                }
                Rectangle {     // the Theme page: hidden while the orb is out (its pill grows over here)
                    width: stage.px(48); height: width; radius: width / 2
                    opacity: orb.open ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                    color: C.alpha(stage.rice.surfaceLowest, themeMouse.containsMouse ? 0.7 : 0.55)
                    border.width: 1
                    border.color: C.alpha(stage.rice.edge, themeMouse.containsMouse ? Tokens.alpha.outlineStrong : Tokens.alpha.outline)
                    Text {
                        anchors.centerIn: parent
                        text: "palette"
                        color: themeMouse.containsMouse ? stage.rice.primary : stage.rice.fg
                        font.family: Tokens.font.icons
                        font.pixelSize: stage.px(23)
                        Behavior on color { ColorAnimation { duration: Tokens.fast } }
                    }
                    MouseArea {
                        id: themeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: stage.launcher.openWallpapers("desktop")
                    }
                }
            }
        }

        // bottom left: the battery saver, only while the laptop runs on battery (or the saver is on)
        Rise {
            order: 4
            shown: stage.contentIn; lift: stage.px(16)
            visible: stage.launcher.unplugged || stage.launcher.saverOn
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: content.margin; bottomMargin: content.margin }
            implicitWidth: saver.width
            implicitHeight: saver.height
            Rectangle {
                id: saver
                readonly property bool on: stage.launcher.saverShown
                readonly property real charge: Number(stage.launcher.batt["Percent"]) || 0
                height: stage.px(48)
                width: saverRow.implicitWidth + stage.px(36)
                radius: height / 2
                color: on ? C.alpha(stage.rice.green, saverMouse.containsMouse ? 0.3 : 0.22)
                          : C.alpha(stage.rice.surfaceLowest, saverMouse.containsMouse ? 0.7 : 0.55)
                border.width: 1
                border.color: on ? C.alpha(stage.rice.green, 0.6) : C.alpha(stage.rice.edge, Tokens.alpha.outline)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                opacity: stage.launcher.saverBusy ? 0.6 : 1
                Row {
                    id: saverRow
                    anchors.centerIn: parent
                    spacing: stage.px(10)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: saver.on ? "eco" : saver.charge <= 10 ? "battery_alert" : "battery_" + Math.min(6, Math.round(saver.charge / 100 * 6)) + "_bar"
                        color: saver.on ? stage.rice.green : saver.charge <= 20 ? stage.rice.warn : stage.rice.fg
                        font.family: Tokens.font.icons
                        font.pixelSize: stage.px(22)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (saver.on ? "Battery saver on" : "Battery saver") + "  ·  " + Math.round(saver.charge) + "%"
                        color: stage.rice.fg
                        font.family: Tokens.font.ui
                        font.weight: Font.DemiBold
                        font.pixelSize: stage.px(Tokens.size.body)
                    }
                }
                MouseArea {
                    id: saverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!stage.launcher.saverBusy) stage.launcher.setSaver(!saver.on)
                }
            }
        }
    }

    }

    // fresh every time it opens: empty query, All, the first app, the search field ready to type in
    onOpened: {
        search.text = ""
        launcher.category = 0
        browse.gridView.currentIndex = -1
        browse.gridView.positionViewAtBeginning()
        browse.pinnedView.positionViewAtBeginning()
        orb.open = false
        Qt.callLater(() => search.forceActiveFocus())
    }
}
