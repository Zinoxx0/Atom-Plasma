import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "Rice"
import "Rice/Color.js" as C

// HyDE-style wallpaper selector: a grid of ~/Pictures/Wallpapers; clicking one
// runs ~/.config/plasma-rice/rice.py, which sets it on the chosen screen(s) and
// re-themes the desktop from it. Scroll on the panel icon to step through this
// screen's wallpapers. Presets keep every screen's wallpaper under a short name
// (rice.py preset), to flip between whole looks.
PlasmoidItem {
    id: root

    RicePalette { id: pal; output: Screen.name }
    readonly property real uiScale: pal.uiScale
    property string home: ""
    property var walls: []          // file names in ~/Pictures/Wallpapers
    property string current: ""     // last wallpaper picked (drives the global theme)
    property var screens: []        // [{name, label, main, image, thumb}] left to right, from rice.py screens
    property string busy: ""        // "" | "apply" | "fetch"
    property string pending: ""     // path being applied
    property string status: ""
    property bool loaded: false
    property var fresh: []          // file names brought by the last "Get more" (badged in the grid)
    property var presets: []        // [{name, screens: {output: image}, theme, thumbs: {output: thumb}}]
    property bool naming: false     // the preset name field is out

    readonly property string screenName: Screen.name   // output this bar is on
    onScreenNameChanged: reload()
    // screens the popup applies to: "all" or an output name (remembered; falls back if unplugged)
    readonly property string target: screens.some(s => s.name === Plasmoid.configuration.target) ? Plasmoid.configuration.target : "all"
    readonly property var targetScreen: screens.find(s => s.name === target) ?? null
    readonly property var here: screens.find(s => s.name === screenName) ?? null

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function pathOf(name) { return home + "/Pictures/Wallpapers/" + name }
    // already showing on every screen the popup targets (then a click does nothing)
    function isCurrent(path) {
        return targetScreen ? targetScreen.image === path
             : screens.length ? screens.every(s => s.image === path) : path === current;
    }
    function pick(name) { const p = pathOf(name); if (!isCurrent(p)) apply(p) }
    function thumb(name) { return "file://" + home + "/.cache/rice/thumbs-plasma/" + name.replace(/\.[^.]+$/, "") + ".jpg" }
    function fileName(p) { return p ? p.split("/").pop() : "" }

    // The grid's model, kept in step with `walls` in place: a reload (every time the popup
    // opens) only inserts and removes what changed, so the grid keeps its delegates and their
    // loaded thumbnails instead of rebuilding and fading everything in again.
    ListModel { id: wallModel }
    function syncModel(names) {
        const want = new Set(names);
        for (let i = wallModel.count - 1; i >= 0; i--)
            if (!want.has(wallModel.get(i).name)) wallModel.remove(i);
        // both lists are sorted the same way, so what's left is in order: fill in the gaps
        for (let i = 0; i < names.length; i++)
            if (i >= wallModel.count || wallModel.get(i).name !== names[i]) wallModel.insert(i, { name: names[i] });
    }

    RiceShell {
        id: sh
        onNewData: (source, data) => {
            const out = data["stdout"] ?? "";
            const kind = (source.match(/#(\w+) \d+$/) || [])[1];     // the tags in a fetch could contain anything
            if (kind === "list") {
                const parts = out.split("\n@@\n");
                root.home = (parts[0] ?? "").trim();
                const names = (parts[1] ?? "").split("\n").filter(s => s.length);
                root.current = (parts[2] ?? "").trim();
                try { root.screens = JSON.parse(parts[3]) } catch (e) {}
                try { root.presets = JSON.parse(parts[4]) } catch (e) {}
                root.syncModel(names);
                root.walls = names;
                root.loaded = true;
            } else if (kind === "apply") {
                root.busy = ""; root.pending = "";
                root.reload();
            } else if (kind === "psave") {
                const name = out.trim();
                root.status = name ? "Saved preset “" + name + "”" : "Couldn't save the preset";
                root.reload();
            } else if (kind === "pdelete") {
                root.reload();
            } else if (kind === "fetch") {
                root.busy = "";
                try {
                    const r = JSON.parse(out);
                    const what = "“" + r.tags.join(", ") + "”";
                    root.fresh = r.saved.map(p => root.fileName(p));
                    root.status = r.saved.length ? "Added " + r.saved.length + " for " + what : "Nothing new for " + what;
                    if (r.thin && r.thin.length) root.status += " · no luck with " + r.thin.join(", ");
                } catch (e) { root.status = "Couldn't reach wallhaven" }
                root.reload();
            }
            disconnectSource(source);
        }
    }
    function reload() {
        sh.connectSource('echo "$HOME"; printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" thumbs; '
            + 'find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -printf "%f\\n" | sort; '
            + 'printf "\\n@@\\n"; readlink -f "$HOME/.local/state/rice/wallpaper"; '
            + 'printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" screens; '
            + 'printf "\\n@@\\n"; python3 "$HOME/.config/plasma-rice/rice.py" presets #list ' + Date.now());
    }
    // scr: "all", "focused" or an output name; defaults to the popup's target
    function apply(arg, scr) {
        if (busy) return;
        busy = "apply"; pending = arg; status = "";
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" ' + q(arg) + ' --screen ' + q(scr || target) + ' #apply ' + Date.now());
    }
    function stepHere(arg) { apply(arg, screenName || "focused") }
    // tags: "modern, clean, aesthetic"; each click brings the next best matches (wallhaven.py).
    // Empty: one of the default themes.
    function fetch(tags) {
        if (busy) return;
        const t = String(tags ?? "").trim();
        busy = "fetch"; status = t ? "Looking for “" + t + "”…" : "Fetching from wallhaven…";
        if (t) {
            Plasmoid.configuration.tags = t;
            Plasmoid.configuration.tagHistory = [t].concat(Plasmoid.configuration.tagHistory
                .filter(h => h.toLowerCase() !== t.toLowerCase())).slice(0, 6);
        }
        sh.connectSource('python3 "$HOME/.config/plasma-rice/wallhaven.py" 6 ' + q(t) + ' #fetch ' + Date.now());
    }
    // presets: names up to 10 characters (rice.py trims them the same way)
    function savePreset(name) {
        const n = String(name ?? "").trim().slice(0, 10);
        naming = false;
        if (!n) return;
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset save ' + q(n) + ' #psave ' + Date.now());
    }
    function loadPreset(name) {
        if (busy) return;
        busy = "apply"; pending = "preset:" + name; status = "";
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset load ' + q(name) + ' #apply ' + Date.now());
    }
    function deletePreset(name) {
        status = "Deleted preset “" + name + "”";
        sh.connectSource('python3 "$HOME/.config/plasma-rice/rice.py" preset delete ' + q(name) + ' #pdelete ' + Date.now());
    }
    // on screen right now: every connected screen it knows shows its wallpaper, and the theme is its
    function presetIsOn(pr) {
        const known = screens.filter(s => pr.screens[s.name] !== undefined);
        return known.length > 0 && known.every(s => s.image === pr.screens[s.name]) && current === pr.theme;
    }
    // its thumbnails, left to right like the screens
    function presetThumbs(pr) {
        const order = screens.map(s => s.name);
        return Object.keys(pr.thumbs || {}).sort((a, b) => order.indexOf(a) - order.indexOf(b)).map(o => pr.thumbs[o]);
    }
    function forgetTags(t) { Plasmoid.configuration.tagHistory = Plasmoid.configuration.tagHistory.filter(h => h !== t) }
    function openFolder() { Qt.openUrlExternally("file://" + home + "/Pictures/Wallpapers") }

    Component.onCompleted: reload()
    onExpandedChanged: if (root.expanded) reload(); else naming = false
    // rice.py re-themes by switching the colour scheme: a wallpaper changed from elsewhere
    readonly property color themeAccent: Kirigami.Theme.highlightColor
    onThemeAccentChanged: reload()

    Plasmoid.contextualActions: [
        PlasmaCore.Action { text: "Next wallpaper (this screen)"; icon.name: "go-next"; onTriggered: root.stepHere("next") },
        PlasmaCore.Action { text: "Previous wallpaper (this screen)"; icon.name: "go-previous"; onTriggered: root.stepHere("prev") },
        PlasmaCore.Action { text: "Random wallpaper (this screen)"; icon.name: "media-playlist-shuffle"; onTriggered: root.stepHere("random") },
        PlasmaCore.Action { text: "Get more from wallhaven"; icon.name: "download"; onTriggered: root.fetch(Plasmoid.configuration.tags) },
        PlasmaCore.Action { text: "Open wallpaper folder"; icon.name: "folder-pictures"; onTriggered: root.openFolder() }
    ]

    toolTipMainText: "Wallpaper"
    toolTipSubText: (here ? fileName(here.image) : fileName(current)) + "\nScroll to switch this screen · click for all"
    preferredRepresentation: compactRepresentation

    // ---------- panel: tiny rounded preview of this screen's wallpaper ----------
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        // the same side padding as every rice bar widget
        Layout.minimumWidth: chip.width + 2 * Tokens.space.md * root.uiScale
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded
        property real acc: 0
        onWheel: wheel => {
            acc += wheel.angleDelta.y;
            if (Math.abs(acc) >= 120 && !root.busy) { root.stepHere(acc < 0 ? "next" : "prev"); acc = 0 }
        }

        Item {
            id: chip
            anchors.centerIn: parent
            width: Math.round(34 * root.uiScale); height: Math.round(22 * root.uiScale)
            scale: compact.containsMouse ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
            Kirigami.ShadowedImage {
                anchors.fill: parent
                radius: Tokens.radius.xs
                color: C.alpha(pal.fg, 0.08)
                source: root.here && root.here.thumb ? "file://" + root.here.thumb
                      : root.current && root.home ? root.thumb(root.fileName(root.current)) : ""
                sourceSize.width: 96
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.xs
                color: "transparent"
                border.width: 1.5
                border.color: compact.containsMouse || root.expanded ? pal.primary : C.alpha(pal.fg, 0.35)
                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
            }
            Rectangle {   // re-theming: a stepped spinner (a smooth one would keep the panel redrawing)
                anchors.fill: parent
                radius: Tokens.radius.xs
                visible: root.busy === "apply"
                color: C.alpha(pal.col("background"), 0.6)
                Busy {
                    anchors.centerIn: parent
                    width: Math.round(14 * root.uiScale); height: width
                    running: root.busy === "apply"
                    color: pal.primary
                }
            }
        }
    }

    // ---------- popup ----------
    fullRepresentation: Item {
        Layout.preferredWidth: 800
        Layout.preferredHeight: 620
        Layout.minimumWidth: 580
        Layout.minimumHeight: 440

        PopupIn {
            anchors.fill: parent
            active: root.expanded
            ricePalette: pal

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.space.lg
                spacing: Tokens.space.md

                PopupHeader {
                    Layout.fillWidth: true
                    palette: pal
                    title: "Wallpaper"
                    subtitle: !root.loaded ? "" : root.targetScreen ? root.fileName(root.targetScreen.image) || "–"
                            : root.screens.some(s => s.image !== root.screens[0].image) ? root.screens.length + " screens, different wallpapers"
                            : root.fileName(root.current) || "–"
                    subtitleLines: 1
                    // this screen's palette as overlapping candy dots
                    trailing: Row {
                        spacing: -6
                        Repeater {
                            model: ["primary", "secondary", "tertiary", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
                            Rectangle {
                                id: dotItem
                                required property string modelData
                                required property int index
                                width: 24; height: 24; radius: 12
                                color: pal.col(modelData)
                                border.width: 2
                                border.color: pal.surface
                                z: dotTip.containsMouse ? 30 : 20 - index
                                scale: dotTip.containsMouse ? 1.2 : 1
                                Behavior on scale { NumberAnimation { duration: Tokens.fast; easing.type: Tokens.enter } }
                                PlasmaCore.ToolTipArea {
                                    id: dotTip
                                    anchors.fill: parent
                                    mainText: dotItem.modelData
                                    subText: String(pal.col(dotItem.modelData))
                                }
                            }
                        }
                    }
                }

                // target screens: All, then one chip per screen (left to right) showing what's on it
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    visible: root.screens.length > 1
                    Repeater {
                        id: screenChips
                        model: root.screens.length > 1 ? [{ name: "all", label: "All screens", thumb: "", main: false }].concat(root.screens) : []
                        Rectangle {
                            id: scr
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.target === modelData.name
                            readonly property bool hot: scrHover.containsMouse || activeFocus
                            implicitHeight: 44
                            implicitWidth: scrRow.implicitWidth + 2 * Tokens.space.sm + 2
                            radius: Tokens.radius.sm
                            color: selected ? C.alpha(pal.primary, scrHover.pressed ? 0.26 : 0.18)
                                 : C.alpha(pal.fg, scrHover.pressed ? 0.14 : hot ? 0.09 : 0.05)
                            border.width: 1
                            border.color: selected ? pal.primary : hot ? C.alpha(pal.primary, 0.6) : C.alpha(pal.fg, Tokens.alpha.outline)
                            Behavior on color { ColorAnimation { duration: Tokens.fast } }
                            Behavior on border.color { ColorAnimation { duration: Tokens.fast } }

                            function choose() { Plasmoid.configuration.target = modelData.name; Qt.callLater(grid.showCurrent) }
                            activeFocusOnTab: true
                            Keys.onReturnPressed: choose()
                            Keys.onEnterPressed: choose()
                            Keys.onSpacePressed: choose()
                            Keys.onLeftPressed: if (index > 0) screenChips.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                            Keys.onRightPressed: if (index < screenChips.count - 1) screenChips.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)

                            RowLayout {
                                id: scrRow
                                anchors.centerIn: parent
                                spacing: Tokens.space.sm
                                Item {
                                    implicitWidth: 44; implicitHeight: 26
                                    Kirigami.ShadowedImage {
                                        anchors.fill: parent
                                        visible: scr.modelData.thumb !== ""
                                        radius: Tokens.radius.xs
                                        color: C.alpha(pal.fg, 0.08)
                                        source: scr.modelData.thumb ? "file://" + scr.modelData.thumb : ""
                                        sourceSize.width: 96
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: scr.modelData.name === "all"
                                        text: "view_column"
                                        color: scr.selected ? pal.primary : pal.fgDim
                                        font.family: Tokens.font.icons
                                        font.pixelSize: 22
                                    }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Text {
                                        text: scr.modelData.label
                                        color: pal.fg
                                        font.family: Tokens.font.ui
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Tokens.size.label
                                    }
                                    Text {
                                        text: scr.modelData.name === "all" ? root.screens.length + " screens"
                                            : scr.modelData.name + (scr.modelData.main ? " · main" : "")
                                        color: pal.muted
                                        font.family: Tokens.font.ui
                                        font.pixelSize: Tokens.size.caption
                                    }
                                }
                            }
                            FocusRing { radius: scr.radius }
                            MouseArea {
                                id: scrHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scr.choose()
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    Pill { palette: pal; icon: "shuffle"; text: "Shuffle"; busy: root.busy === "apply" && root.pending === "random"; onClicked: root.apply("random") }
                    Pill { palette: pal; icon: "skip_previous"; tooltip: "Previous"; onClicked: root.apply("prev") }
                    Pill { palette: pal; icon: "skip_next"; tooltip: "Next"; onClicked: root.apply("next") }
                    Pill { palette: pal; icon: "folder_open"; tooltip: "Open the wallpaper folder"; accent: pal.secondary; onAccent: pal.col("on_secondary"); onClicked: root.openFolder() }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.maximumWidth: 420
                        text: root.status || (root.loaded ? root.walls.length + " wallpapers" : "")
                        elide: Text.ElideRight
                        color: pal.muted
                        font.family: Tokens.font.ui
                        font.pixelSize: Tokens.size.label
                    }
                }

                // presets: the wallpaper of every screen under a name; click to bring the look back,
                // right-click to delete. Saving asks for a name (10 characters at most).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space.xs + 2
                        visible: root.presets.length > 0
                        Repeater {
                            model: root.presets
                            Rectangle {
                                id: pc
                                required property var modelData
                                readonly property bool isOn: root.presetIsOn(modelData)
                                readonly property bool applying: root.busy === "apply" && root.pending === "preset:" + modelData.name
                                readonly property bool hot: pcMouse.containsMouse || activeFocus
                                implicitHeight: 34
                                implicitWidth: pcRow.implicitWidth + 2 * Tokens.space.sm
                                radius: Tokens.radius.sm
                                color: isOn ? C.alpha(pal.primary, pcMouse.pressed ? 0.26 : 0.18)
                                     : C.alpha(pal.fg, pcMouse.pressed ? 0.14 : hot ? 0.09 : 0.05)
                                border.width: 1
                                border.color: isOn ? pal.primary : hot ? C.alpha(pal.primary, 0.6) : C.alpha(pal.fg, Tokens.alpha.outline)
                                Behavior on color { ColorAnimation { duration: Tokens.fast } }
                                Behavior on border.color { ColorAnimation { duration: Tokens.fast } }

                                activeFocusOnTab: true
                                Keys.onReturnPressed: root.loadPreset(modelData.name)
                                Keys.onEnterPressed: root.loadPreset(modelData.name)
                                Keys.onSpacePressed: root.loadPreset(modelData.name)
                                Keys.onDeletePressed: root.deletePreset(modelData.name)

                                Row {
                                    id: pcRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.space.sm
                                    Row {           // its screens' wallpapers, overlapping like a fanned deck
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: -10
                                        Repeater {
                                            model: root.presetThumbs(pc.modelData)
                                            Kirigami.ShadowedImage {
                                                required property string modelData
                                                required property int index
                                                z: 10 - index
                                                width: 32; height: 20
                                                radius: 4
                                                color: C.alpha(pal.fg, 0.08)
                                                border.width: 1.5
                                                border.color: pal.surface
                                                source: "file://" + modelData
                                                sourceSize.width: 96
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: pc.modelData.name
                                        color: pc.isOn || pc.hot ? pal.fg : pal.fgDim
                                        font.family: Tokens.font.ui
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Tokens.size.label
                                    }
                                    Busy {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: pc.applying
                                        width: 14; height: 14
                                        running: pc.applying
                                        color: pal.primary
                                    }
                                }
                                FocusRing { radius: pc.radius }
                                PlasmaCore.ToolTipArea {
                                    anchors.fill: parent
                                    mainText: pc.modelData.name
                                    subText: (pc.isOn ? "On screen now" : "Click to bring this look back") + " · right-click to delete"
                                    MouseArea {
                                        id: pcMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) root.deletePreset(pc.modelData.name)
                                            else if (!pc.isOn) root.loadPreset(pc.modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {          // nothing saved yet
                        Layout.fillWidth: true
                        visible: root.presets.length === 0 && !root.naming
                        text: "Presets keep the wallpaper of every screen, to come back to a look"
                        elide: Text.ElideRight
                        color: pal.muted
                        font.family: Tokens.font.ui
                        font.pixelSize: Tokens.size.label
                    }
                    Item { Layout.fillWidth: true; visible: root.presets.length === 0 && root.naming }
                    TagField {
                        id: presetField
                        Layout.preferredWidth: 190
                        visible: root.naming
                        palette: pal
                        glyph: "bookmark"
                        maximumLength: 10
                        placeholder: "Name, 10 letters max"
                        accent: pal.primary
                        onAccent: pal.onPrimary
                        onAccepted: root.savePreset(text)
                        onEscaped: root.naming = false
                    }
                    Pill {
                        palette: pal
                        size: 34
                        icon: root.naming ? "check" : "bookmark_add"
                        text: root.naming ? "Save" : "Save preset"
                        tooltip: root.naming ? "" : "Keep the wallpaper of every screen under a name"
                        onClicked: {
                            if (root.naming) { root.savePreset(presetField.text); return }
                            presetField.text = "";
                            root.naming = true;
                            Qt.callLater(presetField.focusText);
                        }
                    }
                }

                // get more: describe what you want, wallhaven.py finds the best matches you don't have yet
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space.sm
                    TagField {
                        id: tagField
                        Layout.fillWidth: true
                        palette: pal
                        text: Plasmoid.configuration.tags
                        placeholder: "Describe what you want: modern, clean, aesthetic…"
                        accent: pal.tertiary
                        onAccent: pal.col("on_tertiary")
                        busy: root.busy === "fetch"
                        onAccepted: root.fetch(text)
                    }
                    Pill {
                        palette: pal
                        size: tagField.implicitHeight
                        icon: "cloud_download"
                        text: "Get more"
                        accent: pal.tertiary
                        onAccent: pal.col("on_tertiary")
                        busy: root.busy === "fetch"
                        onClicked: root.fetch(tagField.text)
                    }
                }
                // recent searches: click to get more of the same, right-click to forget
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space.xs + 2
                    visible: Plasmoid.configuration.tagHistory.length > 0
                    Repeater {
                        model: Plasmoid.configuration.tagHistory
                        Chip {
                            id: recent
                            required property string modelData
                            palette: pal
                            interactive: true
                            bold: false
                            size: 24
                            text: modelData
                            tint: pal.tertiary
                            tooltip: "Get more like this · right-click to forget"
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { root.forgetTags(recent.modelData); return }
                                tagField.text = recent.modelData;
                                root.fetch(recent.modelData);
                            }
                        }
                    }
                }

                // grid (with its loading and empty states)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        id: grid
                        anchors.fill: parent
                        visible: root.loaded && wallModel.count > 0
                        clip: true
                        cellWidth: Math.floor(width / 4)
                        cellHeight: Math.round(cellWidth * 9 / 16)
                        model: wallModel
                        // keep every thumbnail's delegate alive while scrolling (a few dozen)
                        cacheBuffer: Math.max(0, Math.ceil(wallModel.count / 4) * cellHeight)
                        boundsBehavior: Flickable.StopAtBounds
                        QQC2.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

                        // only what a reload really adds (a "Get more") arrives animated
                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.base; easing.type: Tokens.enter }
                            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
                        }
                        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Tokens.fast; easing.type: Tokens.exit } }
                        displaced: Transition { NumberAnimation { properties: "x,y"; duration: Tokens.base; easing.type: Tokens.move } }

                        // keyboard: Tab in, arrows to move, Enter to apply
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        currentIndex: -1
                        onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
                        Keys.onReturnPressed: if (currentIndex >= 0) root.pick(wallModel.get(currentIndex).name)
                        Keys.onEnterPressed: if (currentIndex >= 0) root.pick(wallModel.get(currentIndex).name)
                        Keys.onSpacePressed: if (currentIndex >= 0) root.pick(wallModel.get(currentIndex).name)

                        delegate: Item {
                            id: cell
                            required property string name
                            required property int index
                            readonly property string path: root.pathOf(name)
                            readonly property var usedOn: root.screens.filter(s => s.image === path)   // screens showing it
                            readonly property bool isCurrent: root.isCurrent(path)
                            readonly property bool applying: root.busy === "apply" && root.pending === path
                            readonly property bool focused: GridView.isCurrentItem && grid.activeFocus
                            readonly property bool hot: hover.containsMouse || focused
                            width: grid.cellWidth
                            height: grid.cellHeight
                            z: hot ? 2 : 0

                            Item {
                                id: tile
                                anchors.fill: parent
                                anchors.margins: Tokens.space.xs + 2
                                scale: hover.pressed ? 0.97 : cell.hot ? 1.04 : 1
                                Behavior on scale { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }

                                // soft glow behind the hovered/current tile
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    radius: Tokens.radius.md + 4
                                    color: "transparent"
                                    border.width: 4
                                    border.color: C.alpha(pal.primary, cell.isCurrent ? 0.35 : cell.hot ? 0.2 : 0)
                                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                                }
                                Rectangle {   // placeholder while the thumbnail loads
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    color: C.alpha(pal.fg, 0.06)
                                    visible: img.status !== Image.Ready
                                }
                                Kirigami.ShadowedImage {
                                    id: img
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    color: "transparent"
                                    source: root.home ? root.thumb(cell.name) : ""
                                    sourceSize.width: 480
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.base; easing.type: Tokens.enter } }
                                }
                                Rectangle {   // hover brighten
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    color: "white"
                                    opacity: cell.hot ? 0.06 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.fast } }
                                }
                                Chip {   // which screens show it (only with more than one screen)
                                    visible: root.screens.length > 1 && cell.usedOn.length > 0
                                    anchors { left: parent.left; bottom: parent.bottom; margins: Tokens.space.sm }
                                    palette: pal
                                    size: 20
                                    solid: true
                                    tint: C.alpha(pal.col("background"), 0.8)
                                    textColor: pal.fg
                                    text: cell.usedOn.length === root.screens.length ? "All screens" : cell.usedOn.map(s => s.label).join(" · ")
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    color: "transparent"
                                    border.width: cell.isCurrent ? 2.5 : 1
                                    border.color: cell.isCurrent ? pal.primary
                                                : cell.hot ? C.alpha(pal.primary, 0.8)
                                                : C.alpha(pal.fg, Tokens.alpha.outline)
                                    Behavior on border.color { ColorAnimation { duration: Tokens.fast } }
                                }
                                Chip {   // just fetched
                                    visible: root.fresh.indexOf(cell.name) >= 0
                                    anchors { left: parent.left; top: parent.top; margins: Tokens.space.sm }
                                    palette: pal
                                    size: 20
                                    solid: true
                                    tint: pal.tertiary
                                    text: "NEW"
                                }
                                Rectangle {   // "current" badge
                                    visible: cell.isCurrent
                                    anchors { right: parent.right; top: parent.top; margins: Tokens.space.sm }
                                    width: 24; height: 24; radius: 12
                                    color: pal.primary
                                    Text {
                                        anchors.centerIn: parent
                                        text: "check"
                                        color: pal.onPrimary
                                        font.family: Tokens.font.icons
                                        font.pixelSize: 17
                                        font.weight: Font.Bold
                                    }
                                }
                                Rectangle {   // applying overlay
                                    anchors.fill: parent
                                    radius: Tokens.radius.md
                                    visible: cell.applying
                                    color: C.alpha(pal.col("background"), 0.55)
                                    Busy {
                                        anchors.centerIn: parent
                                        width: 28; height: 28
                                        running: cell.applying
                                        color: pal.primary
                                    }
                                }
                                FocusRing { radius: Tokens.radius.md; shown: cell.focused }
                                MouseArea {
                                    id: hover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: cell.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: root.pick(cell.name)
                                }
                            }
                        }

                        function showCurrent() {
                            const want = root.targetScreen ? root.targetScreen.image : root.current;
                            const i = root.walls.findIndex(n => root.home + "/Pictures/Wallpapers/" + n === want);
                            if (i >= 0) positionViewAtIndex(i, GridView.Contain);
                        }
                        Connections {
                            target: root
                            function onExpandedChanged() { if (root.expanded) Qt.callLater(grid.showCurrent) }
                            // after a "Get more", bring the first new one into view
                            function onWallsChanged() {
                                const i = root.walls.findIndex(n => root.fresh.indexOf(n) >= 0);
                                if (i >= 0) Qt.callLater(() => grid.positionViewAtIndex(i, GridView.Contain));
                            }
                        }
                    }

                    // loading: placeholder tiles breathing while the first list comes in
                    Grid {
                        id: skeleton
                        anchors.fill: parent
                        visible: !root.loaded
                        columns: 4
                        readonly property real cw: Math.floor(width / 4)
                        Repeater {
                            model: 8
                            Item {
                                width: skeleton.cw; height: Math.round(skeleton.cw * 9 / 16)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space.xs + 2
                                    radius: Tokens.radius.md
                                    color: C.alpha(pal.fg, 0.06)
                                    SequentialAnimation on opacity {
                                        running: skeleton.visible && root.expanded
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }
                    }

                    // empty: nothing in ~/Pictures/Wallpapers yet
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: root.loaded && wallModel.count === 0
                        spacing: Tokens.space.sm
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "wallpaper"
                            color: pal.muted
                            font.family: Tokens.font.icons
                            font.pixelSize: 48
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No wallpapers yet"
                            color: pal.fg
                            font.family: Tokens.font.display
                            font.weight: Font.Bold
                            font.pixelSize: Tokens.size.title
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Drop images in ~/Pictures/Wallpapers, or get some from wallhaven."
                            color: pal.fgDim
                            font.family: Tokens.font.ui
                            font.pixelSize: Tokens.size.label
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Tokens.space.sm
                            spacing: Tokens.space.sm
                            Pill { palette: pal; icon: "cloud_download"; text: "Get some"; accent: pal.tertiary; onAccent: pal.col("on_tertiary"); busy: root.busy === "fetch"; onClicked: root.fetch(tagField.text) }
                            Pill { palette: pal; icon: "folder_open"; text: "Open folder"; accent: pal.secondary; onAccent: pal.col("on_secondary"); onClicked: root.openFolder() }
                        }
                    }
                }
            }
        }
    }
}
