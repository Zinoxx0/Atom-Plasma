import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import Atom
import "Rice"
import "Rice/Color.js" as C

// The launcher, presented on the bare desktop. Opening it clears the desk: every window flies into its
// pin in the top band (Atom Windows.clear: minimized, KWin's magic lamp) and the wallpaper itself is the
// backdrop. The bar's jewel lifts off and glides up into the search capsule; a greeting settles above it;
// the pinned apps come out as candy-glass bubbles, then the app library: every category a frosted stack
// of its first apps, six to a row, that opens as a folder grown out of it. Typing grows the results out
// of the capsule. Everything is frosted with the screen's pre-blurred wallpaper (Atom Frost), so the glass
// fades and moves with its piece. Closing folds it all back into the jewel and brings the windows back
// exactly as they were (Windows.restore). Esc steps back (folder, query, then closes); so does a click on
// the bare wallpaper, Meta, or launching something.
// Mapped only while open: unmapping hands the keyboard back to the window that had it.
Window {
    id: stage
    required property var launcher
    required property var screenObj
    required property RicePalette rice
    required property Account account
    readonly property string screenName: screenObj ? screenObj.name : ""

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
    property real p: 0                          // the capsule: 0 = the jewel on the bar, 1 = in place
    property rect jewel: Qt.rect(0, 0, 0, 0)
    readonly property bool contentIn: phase === "open" || (phase === "opening" && p > 0.45)
    signal opened()

    function local(r) {
        if (!r || !screenObj) return Qt.rect(u(16), height - u(48), u(72), u(36))
        return Qt.rect(r.x - screenObj.virtualX, r.y - screenObj.virtualY, r.width, r.height)
    }
    onWantedChanged: wanted ? begin() : end()
    function begin() {
        jewel = local(Shell.anchor || Shell.island("launcher", screenName))
        shrink.stop()
        if (launcher.clearDesk) Windows.clear()
        if (phase === "closed") {
            p = 0
            folderAt = -1
            phase = "opening"
            waitFrame = true
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
        Windows.restore()
        shrink.restart()
    }
    onPhaseChanged: {
        if (!Shell.debug) return
        console.warn("ATOM stage", screenName, "phase", phase, Date.now() % 100000)
        if (phase === "open") console.warn("ATOM stage state home", home, "contentIn", contentIn, "searching", searching,
            "walls", walls, "stacks", stacks.length, "pins", pinCount, "greeting", greeting.opacity, greeting.y, "unit", unit)
        if (phase === "open" && stacks.length) {
            const r = stackRect(0)
            console.warn("ATOM stage stack0 at", Math.round(screenObj.virtualX + r.x + r.width / 2), Math.round(screenObj.virtualY + r.y + r.height / 2),
                         "power at", Math.round(powerBead.x + powerBead.width / 2), Math.round(powerBead.y + powerBead.height / 2))
        }
    }
    property bool waitFrame: false
    onFrameSwapped: if (waitFrame) { waitFrame = false; grow.restart() }
    NumberAnimation {
        id: grow
        target: stage; property: "p"; to: 1
        duration: Tokens.ms(620); easing.type: Easing.InOutCubic
        onFinished: if (stage.phase === "opening") stage.phase = "open"
    }
    NumberAnimation {
        id: shrink
        target: stage; property: "p"; to: 0
        duration: Tokens.ms(380); easing.type: Easing.InOutCubic
        onFinished: stage.phase = "closed"
    }

    // ------------------------------------------------------------------ scale: fit the screen
    readonly property int rows: Math.max(1, Math.ceil(stacks.length / 6))
    readonly property real unit: Math.max(0.6, Math.min(launcher.px(1), width / 1080,
                                                       height * 0.74 / (300 + rows * 190)))
    function u(n) { return Math.round(n * unit) }

    // ------------------------------------------------------------------ the frost: the bare wallpaper, blurred
    Item {
        id: backdropArt
        width: stage.width
        height: stage.height
        Image {
            anchors.fill: parent
            smooth: true
            fillMode: Image.PreserveAspectCrop
            readonly property string pre: stage.rice.values._glassFull || ""
            source: pre ? "file://" + pre : stage.rice.wallpaper ? "file://" + stage.rice.wallpaper : ""
            sourceSize.width: pre ? 0 : 96
        }
    }
    ShaderEffectSource {
        id: frostTex
        width: stage.width
        height: stage.height
        visible: false
        sourceItem: backdropArt
        hideSource: true
        smooth: true
        live: stage.phase !== "closed"
    }

    // ------------------------------------------------------------------ what it shows
    property int folderAt: -1                   // the open folder: an index into stacks
    readonly property bool searching: launcher.query !== ""
    readonly property bool walls: launcher.view === "walls"
    readonly property bool home: contentIn && !searching && !walls          // greeting, pins, library
    readonly property real homeOpacity: folderAt >= 0 ? 0 : 1       // a folder has the stage to itself

    Kicker.RecentUsageModel {
        id: recentDocs
        shownItems: Kicker.RecentUsageModel.OnlyDocs
    }
    // the library: every category but "All", then the recent files
    readonly property var stacks: {
        const out = launcher.categories.filter(c => c.label !== "All")
        if (recentDocs.count > 0) out.push({ label: "Recent files", icon: "description", model: recentDocs })
        return out
    }

    // ------------------------------------------------------------------ layout (window coordinates)
    readonly property real capW: Math.min(u(660), width - 2 * u(40))
    readonly property real capH: u(64)
    readonly property real capX: Math.round((width - capW) / 2)
    readonly property real capY: Math.round(height * 0.25)
    readonly property real pinSize: u(66)
    readonly property real pinGap: u(20)
    readonly property int pinMax: Math.max(1, Math.floor((Math.min(u(1000), width - 2 * u(40)) + pinGap) / (pinSize + pinGap)))
    readonly property int pinCount: Math.min(launcher.favorites ? launcher.favorites.count : 0, pinMax)
    readonly property real pinsY: capY + capH + u(42)
    readonly property real card: u(132)
    readonly property real cardGap: u(30)
    readonly property real rowH: card + u(58)
    readonly property real stacksY: pinsY + (pinCount > 0 ? pinSize + u(52) : 0)
    function stackRect(i) {
        const row = Math.floor(i / 6), col = i % 6
        const n = Math.min(6, stacks.length - row * 6)
        const rowW = n * card + (n - 1) * cardGap
        return Qt.rect(Math.round((width - rowW) / 2 + col * (card + cardGap)), stacksY + row * rowH, card, card)
    }

    // the capsule: from the jewel on the bar to its place
    readonly property real cx: jewel.x + (capX - jewel.x) * p
    readonly property real cy: jewel.y + (capY - jewel.y) * p
    readonly property real cw: jewel.width + (capW - jewel.width) * p
    readonly property real ch: jewel.height + (capH - jewel.height) * p


    // ------------------------------------------------------------------ the bare wallpaper takes clicks
    MouseArea {
        anchors.fill: parent
        enabled: stage.phase === "open"
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            if (stage.folderAt >= 0) stage.closeFolder()
            else stage.launcher.close()
        }
    }

    // ------------------------------------------------------------------ the jewel's light, around the capsule
    Shape {
        id: jewelLight
        enabled: false             // light only: under everything, takes no clicks
        readonly property real w: stage.capW * 1.7
        readonly property real h: stage.capH * 5.5
        x: stage.capX + stage.capW / 2 - w / 2
        y: stage.capY + stage.capH / 2 - h / 2
        width: w
        height: h
        visible: opacity > 0.01
        opacity: stage.p * (stage.walls ? 0 : 1)
        Behavior on opacity { NumberAnimation { duration: Tokens.slow } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: jewelLight.w / 2; centerY: jewelLight.h / 2; centerRadius: jewelLight.w / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: C.alpha(stage.rice.primary, 0.2 * Math.max(0.4, stage.rice.glow)) }
                GradientStop { position: 0.5; color: C.alpha(stage.rice.primary, 0.06 * Math.max(0.4, stage.rice.glow)) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: jewelLight.w; height: jewelLight.h; radius: jewelLight.h / 2 }
        }
    }

    property date now: new Date()
    Timer { running: stage.phase !== "closed"; repeat: true; interval: 5000; triggeredOnStart: true; onTriggered: stage.now = new Date() }

    // ------------------------------------------------------------------ greeting
    Column {
        id: greeting
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property bool shown: stage.home && stage.folderAt < 0
        y: stage.capY - height - stage.u(26) + (shown ? 0 : stage.u(14))
        spacing: stage.u(4)
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: greeting.shown ? Tokens.slow : Tokens.fast; easing.type: Tokens.enter } }
        Behavior on y { NumberAnimation { duration: greeting.shown ? Tokens.ms(560) : Tokens.fast; easing.type: Tokens.grow } }
        layer.enabled: stage.phase !== "closed"
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.9; shadowVerticalOffset: 2; shadowHorizontalOffset: 0 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property string first: String(stage.account.displayName || "").split(" ")[0]
            text: stage.launcher.greeting(stage.now.getHours()) + (first ? " " + first : "")
            color: stage.rice.fg
            font.family: Tokens.font.display
            font.weight: Font.Light
            font.pixelSize: stage.u(38)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(stage.now, "dddd, d MMMM") + "   ·   " + Qt.formatTime(stage.now, "HH:mm")
            color: stage.rice.fgDim
            font.family: Tokens.font.ui
            font.weight: Font.Medium
            font.pixelSize: stage.u(15)
            font.letterSpacing: 0.5
        }
    }

    // ------------------------------------------------------------------ the pinned apps: candy-glass bubbles
    Repeater {
        id: pins
        model: stage.launcher.favorites
        delegate: Frost {
            id: pin
            required property int index
            required property var model
            readonly property bool inRow: index < stage.pinCount
            readonly property bool shown: stage.home && inRow
            readonly property real baseX: Math.round((stage.width - (stage.pinCount * stage.pinSize + (stage.pinCount - 1) * stage.pinGap)) / 2
                                                     + index * (stage.pinSize + stage.pinGap))
            readonly property bool hot: pm.containsMouse || activeFocus
            readonly property color appTint: C.appTint(pinColors, stage.rice.primary)
            Kirigami.ImageColors { id: pinColors; source: pin.model.decoration }
            visible: inRow && opacity > 0.01
            backdrop: frostTex
            width: stage.pinSize
            height: stage.pinSize
            radius: width / 2
            x: baseX
            y: stage.pinsY + (shown ? (hot ? -stage.u(5) : 0) : stage.u(22))
            opacity: shown ? stage.homeOpacity : 0
            tintAlpha: hot ? 0.36 : 0.48
            rimA: hot ? appTint : stage.rice.primary
            rimB: hot ? appTint : stage.rice.tertiary
            rimAlpha: hot ? 0.75 : 0.3
            readonly property int delay: Tokens.ms(140 + index * 35)
            Behavior on y { SequentialAnimation {
                PauseAnimation { duration: pin.shown && !pin.hot && pin.opacity < 0.5 ? pin.delay : 0 }
                NumberAnimation { duration: pin.shown ? Tokens.ms(520) : Tokens.fast; easing.type: Tokens.grow } } }
            Behavior on opacity { SequentialAnimation {
                PauseAnimation { duration: pin.shown && pin.opacity < 0.5 ? pin.delay : 0 }
                NumberAnimation { duration: pin.shown ? Tokens.slow : Tokens.fast; easing.type: Tokens.enter } } }
            AppGlow {
                anchors.centerIn: parent
                width: parent.width * 1.25
                flat: 1
                tint: pin.appTint
                strength: (pin.hot ? 0.6 : 0.3) * Math.max(0.35, stage.rice.glow)
                Behavior on strength { NumberAnimation { duration: Tokens.base } }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.54); height: width
                source: pin.model.decoration
                scale: pm.pressed ? 0.92 : pin.hot ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
            }
            Text {      // its name, only while pointed at
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height + stage.u(8)
                text: pin.model.display
                color: stage.rice.fg
                opacity: pin.hot ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.4)
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: stage.u(12)
            }
            FocusRing { ink: stage.rice.edge; radius: pin.radius; shown: pin.activeFocus; gap: 2 }
            activeFocusOnTab: inRow
            Keys.onReturnPressed: stage.launcher.launch(stage.launcher.favorites, pin.index)
            Keys.onEnterPressed: stage.launcher.launch(stage.launcher.favorites, pin.index)
            MouseArea {
                id: pm
                anchors.fill: parent
                enabled: pin.shown
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) stage.launcher.menu.openFor(pin, stage.launcher.favorites, pin.index)
                    else stage.launcher.launch(stage.launcher.favorites, pin.index)
                }
            }
        }
    }

    // ------------------------------------------------------------------ the app library: a stack per category
    Repeater {
        id: library
        model: stage.stacks
        delegate: Stack {
            id: st
            required property int index
            required property var modelData
            readonly property rect at: stage.stackRect(index)
            readonly property bool shown: stage.home && stage.folderAt !== index
            launcher: stage.launcher
            rice: stage.rice
            cat: modelData
            unit: stage.unit
            backdrop: frostTex
            width: at.width
            height: at.height
            x: at.x
            y: at.y + (shown ? 0 : stage.u(26))
            opacity: shown ? stage.homeOpacity : 0
            enabled: stage.home && stage.folderAt < 0
            readonly property int delay: Tokens.ms(260 + index * 40)
            Behavior on y { SequentialAnimation {
                PauseAnimation { duration: st.shown && st.opacity < 0.5 ? st.delay : 0 }
                NumberAnimation { duration: st.shown ? Tokens.ms(560) : Tokens.fast; easing.type: Tokens.grow } } }
            Behavior on opacity { SequentialAnimation {
                PauseAnimation { duration: st.shown && st.opacity < 0.5 ? st.delay : 0 }
                NumberAnimation { duration: st.shown ? Tokens.slow : Tokens.fast; easing.type: Tokens.enter } } }
            onOpened: stage.openFolder(index)
        }
    }

    // ------------------------------------------------------------------ a folder, grown out of its stack
    property real fp: 0                         // 0 = the stack, 1 = the open folder
    property rect folderFrom: Qt.rect(0, 0, 0, 0)
    property var folderKeep: null               // the category it shows (kept while it folds back)
    readonly property rect folderTo: {
        const w = Math.min(u(1020), width - 2 * u(40))
        const n = folderKeep && folderKeep.model ? folderKeep.model.count : 0
        const h = Math.min(height - pinsY - u(110), u(98) + Math.max(1, Math.ceil(n / 6)) * u(122))
        return Qt.rect(Math.round((width - w) / 2), pinsY - u(10), w, h)
    }
    function openFolder(i) {
        if (Shell.debug) console.warn("ATOM stage folder open", i, stacks[i].label)
        folderFrom = stackRect(i)
        folderKeep = stacks[i]
        folderAt = i
        fold.stop()
        unfold.restart()
        Qt.callLater(() => folder.grid.forceActiveFocus())
    }
    function closeFolder() {
        if (folderAt < 0) return
        if (Shell.debug) console.warn("ATOM stage folder close", folderAt)
        folderFrom = stackRect(folderAt)
        folderAt = -1
        unfold.stop()
        fold.restart()
        search.forceActiveFocus()
    }
    NumberAnimation { id: unfold; target: stage; property: "fp"; to: 1; duration: Tokens.ms(480); easing.type: Tokens.grow }
    NumberAnimation { id: fold; target: stage; property: "fp"; to: 0; duration: Tokens.ms(300); easing.type: Easing.InOutCubic
                      onFinished: stage.folderKeep = null }
    Folder {
        id: folder
        launcher: stage.launcher
        rice: stage.rice
        unit: stage.unit
        cat: stage.folderKeep
        backdrop: frostTex
        visible: stage.fp > 0.01 && stage.phase !== "closed"
        x: stage.folderFrom.x + (stage.folderTo.x - stage.folderFrom.x) * stage.fp
        y: stage.folderFrom.y + (stage.folderTo.y - stage.folderFrom.y) * stage.fp
        width: stage.folderFrom.width + (stage.folderTo.width - stage.folderFrom.width) * stage.fp
        height: stage.folderFrom.height + (stage.folderTo.height - stage.folderFrom.height) * stage.fp
        radius: stage.u(26) + stage.u(4) * stage.fp
        opacity: stage.contentIn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
        reveal: Math.max(0, (stage.fp - 0.55) / 0.45)
        onDone: stage.closeFolder()
    }

    // ------------------------------------------------------------------ results, grown out of the capsule
    property real sp: searching && contentIn ? 1 : 0
    Behavior on sp { NumberAnimation { duration: stage.searching ? Tokens.ms(420) : Tokens.ms(220); easing.type: stage.searching ? Tokens.grow : Tokens.exit } }
    Frost {
        id: results
        readonly property real fullH: Math.min(stage.u(540), stage.height - y - stage.u(110))
        backdrop: frostTex
        visible: stage.sp > 0.01
        width: Math.min(stage.u(780), stage.width - 2 * stage.u(40))
        x: Math.round((stage.width - width) / 2)
        y: stage.capY + stage.capH + stage.u(12)
        height: Math.max(stage.u(40), fullH * stage.sp)
        radius: stage.u(26)
        tintAlpha: 0.6
        rimA: stage.rice.primary
        rimB: stage.rice.tertiary
        rimAlpha: 0.4
        opacity: Math.min(1, stage.sp * 2)
        clip: true
        SearchResults {
            x: stage.u(14)
            y: stage.u(14)
            width: results.width - 2 * stage.u(14)
            height: results.fullH - 2 * stage.u(14)
            opacity: Math.max(0, (stage.sp - 0.4) / 0.6)
            launcher: stage.launcher
            rice: stage.rice
            menu: stage.launcher.menu
            runnerModel: stage.launcher.runnerModel
        }
    }

    // ------------------------------------------------------------------ the capsule (the jewel, lifted)
    Frost {
        id: capsule
        backdrop: frostTex
        visible: stage.phase !== "closed" && opacity > 0.01
        x: stage.cx
        y: stage.cy
        width: stage.cw
        height: stage.ch
        radius: height / 2
        tintAlpha: 0.56
        rimA: stage.rice.primary
        rimB: stage.rice.tertiary
        rimAlpha: search.activeFocus ? 0.75 : 0.4
        lift: stage.p
        opacity: stage.walls ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Tokens.base } }
        // the jewel's own colour, fading as it lifts off the bar
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: stage.rice.primary
            opacity: Math.max(0, 1 - stage.p * 2.2)
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: search.forceActiveFocus() }
        Item {
            anchors.fill: parent
            anchors.leftMargin: stage.u(24)
            anchors.rightMargin: stage.u(18)
            opacity: Math.max(0, (stage.p - 0.5) / 0.5)
            Text {
                id: lens
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                color: search.activeFocus ? stage.rice.primary : stage.rice.muted
                font.family: Tokens.font.icons
                font.pixelSize: stage.u(26)
                Behavior on color { ColorAnimation { duration: Tokens.fast } }
            }
            TextInput {
                id: search
                anchors { left: lens.right; leftMargin: stage.u(14); right: hint.left; rightMargin: stage.u(12); top: parent.top; bottom: parent.bottom }
                verticalAlignment: TextInput.AlignVCenter
                color: stage.rice.fg
                selectionColor: stage.rice.primary
                selectedTextColor: stage.rice.onPrimary
                font.family: Tokens.font.ui
                font.pixelSize: stage.u(19)
                clip: true
                focus: true
                onTextChanged: stage.launcher.query = text
                Keys.onPressed: event => {
                    const L = stage.launcher
                    if (event.key === Qt.Key_Escape) {
                        if (stage.folderAt >= 0) stage.closeFolder()
                        else if (text) text = ""
                        else L.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && L.query)) {
                        if (L.query) L.moveSelection(1)
                        else if (stage.pinCount > 0) pins.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                        else if (library.count > 0) library.itemAt(0).forceActiveFocus(Qt.TabFocusReason)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        if (L.query) L.moveSelection(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (L.query) L.activateSelection()
                        event.accepted = true
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
                id: hint
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: stage.launcher.searching
                running: visible
                implicitWidth: stage.u(18); implicitHeight: implicitWidth
                color: stage.rice.primary
            }
        }
    }

    // ------------------------------------------------------------------ the Theme page, in a frosted card
    Frost {
        id: wallsCard
        readonly property real w: Math.min(stage.u(1220), stage.width - 2 * stage.u(40))
        backdrop: frostTex
        visible: opacity > 0.01
        width: w
        height: stage.height - 2 * stage.u(56)
        x: Math.round((stage.width - w) / 2)
        y: stage.u(56) + (stage.walls ? 0 : stage.u(24))
        opacity: stage.walls && stage.contentIn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.move } }
        Behavior on y { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } }
        radius: Tokens.radius.xl
        tintAlpha: 0.66
        rimA: stage.rice.primary
        rimB: stage.rice.tertiary
        MouseArea { anchors.fill: parent }
        Loader {
            id: wallsLoader
            anchors.fill: parent
            anchors.margins: Tokens.space.xl
            active: stage.walls || item !== null
            enabled: stage.walls
            onEnabledChanged: if (enabled && item) Qt.callLater(() => item.forceActiveFocus())
            onLoaded: { stage.launcher.wallsPane = item; if (stage.launcher.openTab) item.tab = stage.launcher.openTab; stage.launcher.openTab = ""; item.forceActiveFocus() }
            sourceComponent: WallpaperPane {
                cfg: stage.launcher.cfg
                mode: "desktop"
                onBack: { stage.launcher.view = "apps"; Qt.callLater(() => search.forceActiveFocus()) }
            }
        }
    }

    // ------------------------------------------------------------------ corners: Theme, power; battery saver
    // (an inline component sees no ids of this file: the backdrop comes in as a property)
    component Bead: Frost {
        id: bead
        property string glyph: ""
        property color glyphColor: "white"
        property color hotColor: "white"
        property bool shown: false
        property int order: 0
        signal clicked()
        readonly property bool hot: bm.containsMouse
        tintAlpha: hot ? 0.4 : 0.52
        rimAlpha: hot ? 0.7 : 0.3
        radius: width / 2
        opacity: shown ? 1 : 0
        Behavior on opacity { SequentialAnimation {
            PauseAnimation { duration: bead.shown && bead.opacity < 0.5 ? Tokens.ms(380 + bead.order * 60) : 0 }
            NumberAnimation { duration: bead.shown ? Tokens.slow : Tokens.fast } } }
        Text {
            anchors.centerIn: parent
            text: bead.glyph
            color: bead.hot ? bead.hotColor : bead.glyphColor
            font.family: Tokens.font.icons
            font.pixelSize: Math.round(bead.width * 0.46)
            Behavior on color { ColorAnimation { duration: Tokens.fast } }
            rotation: bead.hot && bead.glyph === "power_settings_new" ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Tokens.slow; easing.type: Tokens.grow } }
        }
        MouseArea { id: bm; anchors.fill: parent; enabled: bead.shown; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bead.clicked() }
    }
    Bead {
        id: powerBead
        backdrop: frostTex
        width: stage.u(52); height: width
        x: stage.width - width - stage.u(40)
        y: stage.height - height - stage.u(40)
        rimA: stage.rice.primary; rimB: stage.rice.tertiary
        glyph: "power_settings_new"; glyphColor: stage.rice.fg; hotColor: stage.rice.bad
        shown: stage.contentIn && !stage.walls
        order: 1
        // the ripple starts from this button (global coordinates)
        onClicked: stage.launcher.openPower({ x: stage.screenObj.virtualX + x, y: stage.screenObj.virtualY + y, width: width, height: height })
    }
    Bead {
        backdrop: frostTex
        width: stage.u(52); height: width
        x: powerBead.x - width - stage.u(14)
        y: powerBead.y
        rimA: stage.rice.primary; rimB: stage.rice.tertiary
        glyph: "palette"; glyphColor: stage.rice.fg; hotColor: stage.rice.primary
        shown: stage.contentIn && !stage.walls
        order: 0
        onClicked: stage.launcher.openWallpapers("desktop")
    }
    Frost {
        id: saver
        readonly property bool on: stage.launcher.saverShown
        readonly property real charge: Number(stage.launcher.batt["Percent"]) || 0
        backdrop: frostTex
        visible: (stage.launcher.unplugged || stage.launcher.saverOn) && opacity > 0.01
        height: stage.u(52)
        width: saverRow.implicitWidth + stage.u(40)
        x: stage.u(40)
        y: stage.height - height - stage.u(40)
        radius: height / 2
        tint: on ? stage.rice.green : Tokens.neutral.dark
        tintAlpha: on ? 0.3 : 0.52
        rimA: on ? stage.rice.green : stage.rice.primary
        rimB: on ? stage.rice.green : stage.rice.tertiary
        opacity: stage.contentIn && !stage.walls ? (stage.launcher.saverBusy ? 0.6 : 1) : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.slow } }
        Row {
            id: saverRow
            anchors.centerIn: parent
            spacing: stage.u(10)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: saver.on ? "eco" : saver.charge <= 10 ? "battery_alert" : "battery_" + Math.min(6, Math.round(saver.charge / 100 * 6)) + "_bar"
                color: saver.on ? stage.rice.green : saver.charge <= 20 ? stage.rice.warn : stage.rice.fg
                font.family: Tokens.font.icons
                font.pixelSize: stage.u(22)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (saver.on ? "Battery saver on" : "Battery saver") + "  ·  " + Math.round(saver.charge) + "%"
                color: stage.rice.fg
                font.family: Tokens.font.ui
                font.weight: Font.DemiBold
                font.pixelSize: stage.u(13)
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (!stage.launcher.saverBusy) stage.launcher.setSaver(!saver.on) }
    }

    onContentInChanged: if (contentIn) launcher.stageEntered()

    // fresh every time it opens: empty query, home, the search field ready to type in
    onOpened: {
        search.text = ""
        launcher.category = 0
        Qt.callLater(() => search.forceActiveFocus())
    }
}
