import QtQuick
import Qt5Compat.GraphicalEffects as GE

// layer.effect for a horizontally scrolling view: its ends fade out where there is more to
// scroll to, so an overflowing row reads as "more this way" instead of being cut off.
//
//   ListView { id: row; layer.enabled: row.contentWidth > row.width; layer.effect: EdgeFade { view: row } }
GE.OpacityMask {
    id: fade
    required property Flickable view
    property real reach: 28               // px of fade at each end

    readonly property bool moreLeft: view.contentX > view.originX + 2
    readonly property bool moreRight: view.contentX + view.width < view.originX + view.contentWidth - 2
    maskSource: Rectangle {
        width: fade.view.width
        height: fade.view.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: fade.moreLeft ? "transparent" : "black" }
            GradientStop { position: Math.min(0.45, fade.reach / Math.max(1, fade.view.width)); color: "black" }
            GradientStop { position: 1 - Math.min(0.45, fade.reach / Math.max(1, fade.view.width)); color: "black" }
            GradientStop { position: 1; color: fade.moreRight ? "transparent" : "black" }
        }
    }
}
