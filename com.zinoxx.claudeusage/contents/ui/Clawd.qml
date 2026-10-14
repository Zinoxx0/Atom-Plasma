import QtQuick

// Clawd, the Claude Code creature, as pixel art that reacts to your usage, to
// whether Claude Code is working, to the time of day and to the season.
//
// The art is drawn in grid cells (22 x 10; hats and bubbles poke above row 0)
// and scaled up by `px`. In the panel (continuous: false) it only moves in
// stepped pixel-art frames, short bursts every few seconds: a smooth looping
// animation in a panel widget keeps plasmashell + KWin redrawing at full
// refresh rate (~27 W on the NVIDIA). The popup adds a smooth idle bob.
Item {
    id: root

    property string mood: "happy"   // happy | sweat | panic | limited | sleep
    property bool working: false    // a Claude Code session is live
    property bool celebrate: false  // a usage window just reset
    property bool warm: false       // using the session faster than its even pace
    property string daypart: "day"  // morning | day | evening | night
    property bool weekend: false
    property string season: ""      // "" | xmas | newyear
    property real sand: 1           // limited: share of the wait still to go (hourglass)
    property var pal: ({})
    property real px: 8
    property bool interactive: true // false in the panel, so clicks reach the applet
    property bool animate: true     // pause everything when hidden
    property bool continuous: true  // smooth looping motion (popup only)

    readonly property bool live: visible && animate
    readonly property bool looping: live && continuous

    implicitWidth: 22 * px
    implicitHeight: 10 * px

    function col(name, fallback) { return pal[name] ?? fallback }

    // ---------- what Clawd looks like right now ----------
    property bool blinking: false
    property bool hopping: false
    property bool peeking: false    // poked while asleep: opens its eyes for a moment
    property int glance: 0          // -1 | 0 | 1
    property int armL: 0            // 1 = raised
    property int armR: 0
    property int drip: 0            // sweat drop frame (3 = gone)
    property int shake: 0
    property int typed: 1           // length of the line being typed in the code window
    property int zz: 0              // Zzz frame
    property int twinkle: 0         // stars, confetti, steam

    // a reset party wakes it up
    readonly property bool asleep: mood === "sleep" && !celebrate
    readonly property bool sitting: mood === "limited"
    readonly property string face: mood === "panic" ? "wide" : mood === "limited" ? "flat"
                                 : asleep && !peeking ? "sleep" : celebrate ? "joy" : "open"
    readonly property string eyes: blinking && (face === "open" || face === "wide") ? "blink" : face
    readonly property string hat: celebrate ? "party" : season === "xmas" ? "santa"
                                : season === "newyear" ? "party" : daypart === "night" ? "nightcap" : ""
    // one thing at a time on the right: an hourglass while limited, the code
    // window while Claude Code works, coffee in the morning
    readonly property string held: mood === "limited" ? "hourglass" : asleep ? ""
                                 : working ? "code" : daypart === "morning" ? "mug" : ""
    readonly property bool shades: weekend && daypart === "day" && mood === "happy" && !working && !celebrate
    readonly property bool blush: warm || celebrate || mood === "sweat"
    readonly property bool star: daypart === "night" && !asleep && held !== "code" && !celebrate
    readonly property int gaze: glance !== 0 ? glance : held === "code" || held === "hourglass" ? 1 : 0

    readonly property color base: mood === "panic" || mood === "limited" ? "#e85d43"
                                : asleep ? "#b98a78" : col("claude", "#d97757")
    // the light follows the time of day: golden morning, rosy evening, moonlit night
    readonly property color body: daypart === "night" ? Qt.tint(base, Qt.alpha(col("blue", "#8e9cf6"), 0.18))
                                : daypart === "evening" ? Qt.tint(base, "#1aff6f91")
                                : daypart === "morning" ? Qt.tint(base, "#16ffd27a") : base
    readonly property color hi: Qt.lighter(body, 1.16)
    readonly property color lo: Qt.darker(body, 1.25)
    readonly property color ink: "#1f1e1d"
    readonly property color cream: "#f3ede4"

    component Px: Rectangle { width: 1; height: 1; antialiasing: false }

    Item {
        id: art
        width: 22
        height: 10
        scale: root.px
        transformOrigin: Item.TopLeft

        // ground shadow, fainter while hopping
        Rectangle {
            x: 3.5; y: 9.75; width: 13; height: 0.6; radius: 0.3
            color: "black"
            opacity: 0.22 * (1 + figure.y / 4)
        }

        Item {
            id: figure
            x: root.shake * 0.5

            // legs, folded under while sitting
            Repeater {
                model: [5, 7, 12, 14]
                Px {
                    required property int modelData
                    x: modelData; y: root.sitting ? 9 : 8
                    height: root.sitting ? 1 : 2
                    color: root.lo
                }
            }

            Item {
                id: upper
                y: root.sitting ? 1 : 0

                // body: top light, darker underside, arms
                Px { x: 4; width: 12; height: 8; color: root.body }
                Px { x: 5; width: 10; color: root.hi }
                Px { x: 4; y: 7; width: 12; color: root.lo }
                Px { x: 2; y: 4 - root.armL; width: 2; height: 2; color: root.body }
                Px { x: 16; y: 4 - root.armR; width: 2; height: 2; color: root.body }

                // eyes
                Repeater {
                    model: [{ ex: 6, side: 1 }, { ex: 13, side: -1 }]
                    Item {
                        id: eye
                        required property var modelData
                        readonly property int ex: modelData.ex
                        readonly property int g: ex + root.gaze
                        readonly property string s: root.eyes
                        readonly property bool arc: s === "joy" || s === "sleep"
                        Px { visible: eye.s === "open"; x: eye.g; y: 2; height: 2; color: root.ink }
                        Px { visible: eye.s === "blink"; x: eye.g; y: 3; color: root.ink }
                        Px { visible: eye.s === "wide"; x: eye.modelData.side > 0 ? eye.ex : eye.ex - 1; y: 2; width: 2; height: 2; color: root.ink }
                        Px { visible: eye.s === "flat"; x: eye.ex - 1; y: 3; width: 3; color: root.ink }
                        // ^ ^ overjoyed, ‿ ‿ asleep
                        Px { visible: eye.arc; x: eye.ex; y: eye.s === "joy" ? 2 : 3; color: root.ink }
                        Px { visible: eye.arc; x: eye.ex - 1; y: eye.s === "joy" ? 3 : 2; color: root.ink }
                        Px { visible: eye.arc; x: eye.ex + 1; y: eye.s === "joy" ? 3 : 2; color: root.ink }
                    }
                }
                Px { visible: root.blush; x: 5; y: 4; color: "#f58c9a"; opacity: 0.8 }
                Px { visible: root.blush; x: 14; y: 4; color: "#f58c9a"; opacity: 0.8 }

                // weekend daytime: shades
                Item {
                    visible: root.shades
                    Px { x: 4; y: 2; width: 12; color: "#141318" }
                    Px { x: 5; y: 3; width: 3; color: "#141318" }
                    Px { x: 12; y: 3; width: 3; color: "#141318" }
                    Px { x: 5; y: 2; color: "#5d5868" }
                    Px { x: 12; y: 2; color: "#5d5868" }
                }

                // night cap (Santa hat in December), drooping to the left
                Item {
                    id: cap
                    visible: root.hat === "nightcap" || root.hat === "santa"
                    readonly property color c: root.hat === "santa" ? "#d63a48" : root.col("blue_dim", "#6d78c6")
                    readonly property color trim: root.hat === "santa" ? root.cream : root.col("blue", "#8e9cf6")
                    Px { x: 5; y: -4; width: 5; color: cap.c }
                    Px { x: 3; y: -3; color: cap.c }
                    Px { x: 6; y: -3; width: 7; color: cap.c }
                    Px { x: 5; y: -2; width: 10; color: cap.c }
                    Px { x: 4; y: -1; width: 12; color: cap.trim }
                    Rectangle { x: 2; y: -2; width: 2; height: 2; radius: 0.7; color: root.cream }
                }

                // party hat
                Item {
                    visible: root.hat === "party"
                    Px { x: 7; y: -1; width: 6; color: root.col("magenta", "#ca95ec") }
                    Px { x: 8; y: -2; width: 4; color: root.col("cyan", "#70d3f6") }
                    Px { x: 9; y: -3; width: 2; color: root.col("yellow", "#e2ae69") }
                    Px { x: 9; y: -4; width: 2; color: root.cream }
                }
                Repeater {   // confetti
                    model: [{ x: 1, y: -3, c: "magenta" }, { x: 3, y: -1, c: "yellow" }, { x: 0, y: 0, c: "cyan" },
                            { x: 14, y: -4, c: "green" }, { x: 16, y: -2, c: "red" }]
                    Px {
                        required property var modelData
                        required property int index
                        visible: root.celebrate && (index + root.twinkle) % 4 !== 0
                        x: modelData.x; y: modelData.y
                        color: root.col(modelData.c, "#ffffff")
                    }
                }

                // code window while Claude Code works
                Item {
                    visible: root.held === "code"
                    Rectangle {
                        x: 17; y: -3; width: 5; height: 5; radius: 0.8
                        color: root.col("surface_lowest", "#150611")
                        border.width: 0.4
                        border.color: Qt.alpha(root.col("primary", "#e9a863"), 0.8)
                    }
                    Px { x: 18; y: -2; width: 3; color: root.col("primary", "#e9a863") }
                    Px { x: 18; y: 0; width: 1 + root.typed % 3; color: root.col("tertiary", "#b1c57b") }
                }

                // morning coffee
                Item {
                    visible: root.held === "mug"
                    Px { x: 18; y: 3; width: 2; height: 3; color: root.cream }
                    Px { x: 18; y: 3; width: 2; color: "#6f4330" }
                    Px { x: 18; y: 5; width: 2; color: root.col("primary", "#e9a863") }
                    Px { x: 20; y: 4; color: root.cream }
                    Px { x: 18 + root.twinkle % 2; y: 1; color: root.cream; opacity: 0.4 }
                    Px { x: 19 - root.twinkle % 2; y: 0; color: root.cream; opacity: 0.22 }
                }

                // hourglass while limited: the top drains as the reset gets closer
                Item {
                    id: glass
                    visible: root.held === "hourglass"
                    readonly property color wood: root.col("secondary", "#deb58e")
                    readonly property color pane: Qt.alpha("#ffffff", 0.16)
                    readonly property color grain: root.col("yellow", "#e2ae69")
                    Px { x: 18; y: 1; width: 3; color: glass.wood }
                    Px { x: 18; y: 2; width: 3; color: glass.pane }
                    Px { x: 19; y: 3; color: glass.pane }
                    Px { x: 18; y: 4; width: 3; color: glass.pane }
                    Px { x: 18; y: 5; width: 3; color: glass.wood }
                    Px { visible: root.sand > 0.05; x: root.sand > 0.6 ? 18 : 19; y: 2; width: root.sand > 0.6 ? 3 : 1; color: glass.grain }
                    Px { visible: root.sand > 0.02; x: 19; y: 3; color: glass.grain }
                    Px { x: root.sand > 0.4 ? 19 : 18; y: 4; width: root.sand > 0.4 ? 1 : 3; color: glass.grain }
                }

                // sweat, a second drop when it's bad
                Rectangle {
                    visible: (root.mood === "sweat" || root.mood === "panic") && root.drip < 3
                    x: 2; y: root.drip; width: 1; height: 2; radius: 0.5
                    color: "#8ec5ff"; opacity: root.drip === 2 ? 0.45 : 0.95
                }
                Rectangle {
                    visible: root.mood === "panic" && root.held === "" && root.drip < 3
                    x: 19; y: root.drip; width: 1; height: 2; radius: 0.5
                    color: "#8ec5ff"; opacity: root.drip === 2 ? 0.45 : 0.95
                }

                // Zzz
                Repeater {
                    model: [{ x: 16, y: 0 }, { x: 18, y: -4 }]
                    Item {
                        id: zed
                        required property var modelData
                        required property int index
                        readonly property color c: Qt.alpha(root.cream, 0.85)
                        x: modelData.x; y: modelData.y
                        visible: root.asleep && !root.peeking && (index === 0 ? root.zz % 3 !== 2 : root.zz % 3 !== 0)
                        Px { width: 4; color: zed.c }
                        Px { x: 2; y: 1; color: zed.c }
                        Px { x: 1; y: 2; color: zed.c }
                        Px { y: 3; width: 4; color: zed.c }
                    }
                }

                // a star out at night
                Item {
                    id: twinkler
                    visible: root.star
                    readonly property color c: root.col("yellow_bright", "#f2c285")
                    x: 19; y: -3
                    Px { x: 1; y: 1; color: twinkler.c }
                    Px { visible: root.twinkle % 3 !== 2; x: 1; color: twinkler.c; opacity: 0.6 }
                    Px { visible: root.twinkle % 3 !== 2; y: 1; color: twinkler.c; opacity: 0.6 }
                    Px { visible: root.twinkle % 3 !== 2; x: 2; y: 1; color: twinkler.c; opacity: 0.6 }
                    Px { visible: root.twinkle % 3 !== 2; x: 1; y: 2; color: twinkler.c; opacity: 0.6 }
                }
            }
        }
    }

    // ---------- motion ----------
    Timer {   // blink every few seconds
        interval: 3200 + Math.random() * 2500
        running: root.live && (root.face === "open" || root.face === "wide") && !root.shades
        repeat: true
        onTriggered: { root.blinking = true; unblink.restart(); interval = 3200 + Math.random() * 2500 }
    }
    Timer { id: unblink; interval: 140; onTriggered: root.blinking = false }

    // each state's own little loop: a short burst of frames every few seconds
    readonly property string loop: asleep ? "snore" : mood === "panic" ? "panic"
                                 : mood === "sweat" ? "sweat" : held === "code" ? "type"
                                 : celebrate ? "cheer" : ""
    readonly property var loops: ({
        snore: { every: 2400 },
        type:  { every: 4200, step: 150, n: 6 },
        sweat: { every: 3600, step: 240, n: 4 },
        panic: { every: 2000, step: 90,  n: 6 },
        cheer: { every: 8000, step: 180, n: 4 },
        wave:  { step: 200, n: 4 },
    })
    property string bursting: ""
    property int step: 0
    function burst(kind) {
        if (bursting) return;
        bursting = kind; step = 0;
        stepper.interval = loops[kind].step;
        stepper.start();
    }
    Timer {
        interval: root.loop ? root.loops[root.loop].every * (root.continuous ? 0.45 : 1) : 1000
        running: root.live && root.loop !== ""
        repeat: true
        onTriggered: root.loop === "snore" ? root.zz++ : root.burst(root.loop)
    }
    Timer {
        id: stepper
        repeat: true
        onTriggered: {
            const k = root.bursting, i = root.step++;
            if (k === "type") { root.armL = i % 2; root.armR = 1 - i % 2; if (i === 1 || i === 4) root.typed++ }
            else if (k === "sweat") root.drip = (i + 1) % 4;
            else if (k === "panic") { root.shake = [1, -1, 1, -1, 0, 0][i]; root.drip = [1, 1, 2, 2, 3, 0][i] }
            else if (k === "cheer") { root.armL = root.armR = (i + 1) % 2; root.twinkle++ }
            else if (k === "wave") root.armL = (i + 1) % 2;
            if (root.step >= root.loops[k].n) {
                stop();
                root.bursting = "";
                root.armL = root.armR = root.shake = 0;
            }
        }
    }

    // now and then: look around, wave or hop
    Timer {
        interval: 20000
        running: root.live && !root.asleep && root.mood !== "limited"
        repeat: true
        onTriggered: {
            interval = root.continuous ? 5000 + Math.random() * 6000 : 16000 + Math.random() * 18000;
            if (root.bursting || root.hopping) return;
            const r = Math.random();
            if (r < 0.45) { root.glance = Math.random() < 0.5 ? -1 : 1; unglance.restart() }
            else if (r < 0.7) root.burst("wave");
            else root.hop();
        }
    }
    Timer { id: unglance; interval: 1500; onTriggered: root.glance = 0 }

    // popup only: stars and steam twinkle, a soft idle bob
    Timer { interval: 650; running: root.looping; repeat: true; onTriggered: root.twinkle++ }
    SequentialAnimation {
        running: root.looping && !root.hopping
        loops: Animation.Infinite
        onRunningChanged: if (!running && !root.hopping) figure.y = 0
        NumberAnimation {
            target: figure; property: "y"
            to: root.asleep || root.sitting ? -0.25 : -0.45
            duration: root.mood === "panic" ? 180 : root.asleep ? 1800 : 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: figure; property: "y"; to: 0
            duration: root.mood === "panic" ? 180 : root.asleep ? 1800 : 700
            easing.type: Easing.InOutSine
        }
    }

    // poked: hop; asleep it opens its eyes instead, limited it looks up at you
    function hop() {
        if (asleep) { peeking = true; unpeek.restart(); return }
        if (mood === "limited") { glance = -1; unglance.restart(); return }
        if (!hopAnim.running) hopAnim.start();
    }
    Timer { id: unpeek; interval: 1100; onTriggered: root.peeking = false }
    SequentialAnimation {
        id: hopAnim
        onStarted: root.hopping = true
        onFinished: root.hopping = false
        NumberAnimation { target: figure; property: "y"; to: -2.2; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: figure; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }
    MouseArea { anchors.fill: parent; enabled: root.interactive; onClicked: root.hop(); cursorShape: Qt.PointingHandCursor }
}
