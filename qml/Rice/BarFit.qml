import QtQuick
import QtQuick.Layouts

// How much a rice bar has to give up to fit its screen: a container query for the panel. When the
// widgets need more room than the bar has (a bar made on the 4K monitor, now on the laptop), they give
// things up in this order, the least useful first, and take them back as soon as there's room:
//   0  everything
//   1  the system rings (CPU, RAM, GPU) drop their numbers; the battery keeps its %
//   2  the Claude rings drop theirs
//   3  pinned apps that don't fit fold into a folder tile; Glimpse takes whatever room is left
//   4  the battery drops its % too (only when even a folded bar is too wide)
//
//   BarFit { id: fit; widget: root }      then fit.step (0..4), fit.animate
//
// A rice widget that changes with the steps puts `riceFit` on its PlasmoidItem: what it takes at each
// step (a short list repeats its last width). Everything else on the bar counts at its natural width.
// Every rice widget on the bar runs this same sum over the same numbers, so they all land on the same
// step without talking to each other. The widths are what each widget WOULD take at each step, not
// what it takes now, so giving something up never makes the sum say "it fits, take it back" (no
// flip-flopping); the room is the panel's own layout width, so it follows screens, bar lengths, tray
// icons coming and going and pins being added, all live.
Item {
    id: fit
    visible: false

    required property Item widget              // the widget's PlasmoidItem: the panel is looked up from it
    readonly property int last: 4

    // the panel's row of widgets (org.kde.panel's GridLayout, which every applet sits in directly)
    readonly property GridLayout panelLayout: {
        let p = widget ? widget.parent : null
        while (p) {
            if (p instanceof GridLayout) return p
            p = p.parent
        }
        return null
    }
    readonly property bool horizontal: !!panelLayout && panelLayout.flow === GridLayout.LeftToRight
    readonly property real room: panelLayout ? panelLayout.width : 0

    // the bar's width at each step. Measured once the widget is in place: while the panel is still making
    // the widgets, reading a neighbour's widths can make it build its representation right then, which
    // would ask for this step before it exists
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => fit.ready = true)
    readonly property var needs: {
        const out = []
        if (!ready || !horizontal) return out
        const kids = panelLayout.children
        for (let k = 0; k <= last; k++) {
            let sum = 0, n = 0
            for (let i = 0; i < kids.length; i++) {
                const c = kids[i]
                // the applets' containers and the panel's own stretch at the end; not the Repeater that
                // makes them (the layout leaves it out too)
                if (!c || !c.visible || (c.applet === undefined && !c.Layout.fillWidth)) continue
                n++
                // a rice widget's own widths (none yet while its representation is being made: then it
                // counts as nothing for that moment rather than through its Layout, which follows the step)
                const own = c.applet ? c.applet.riceFit : undefined
                if (own !== undefined && own !== null) {
                    sum += own.length ? own[Math.min(k, own.length - 1)] : 0
                    continue
                }
                // as the panel's expanding spacer measures them: a widget that stretches counts at its
                // least, any other at its preferred width within its limits
                const L = c.Layout
                sum += c.wantsToFillWidth ? L.minimumWidth
                     : Math.min(L.maximumWidth, Math.max(L.minimumWidth, L.preferredWidth))
            }
            out.push(sum + panelLayout.columnSpacing * Math.max(0, n - 1))
        }
        return out
    }
    readonly property int step: {
        if (room <= 0 || needs.length === 0) return 0
        for (let k = 0; k < needs.length; k++)
            if (needs[k] <= room + 0.5) return k
        return last
    }

    // changes glide only once the bar has settled: at login (or when a bar is made) a widget starts at
    // the step it needs instead of visibly giving things up
    property bool animate: false
    Timer { interval: 2000; running: true; onTriggered: fit.animate = true }
}
