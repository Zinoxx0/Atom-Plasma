import QtQuick
import "Color.js" as C

// A card inside a popup: the palette's raised surface, a hairline outline and, optionally,
// an accent wash at the top. Radius defaults to md (popups are lg, so cards nest inside them).
Rectangle {
    id: card
    required override property RicePalette palette
    property color accent: "transparent"    // set to tint the top edge with an accent
    radius: Tokens.radius.md
    color: C.alpha(palette.surfaceHigh, Tokens.alpha.card)
    border.width: 1
    border.color: C.alpha("#ffffff", Tokens.alpha.outline)

    Rectangle {
        visible: card.accent.a > 0
        anchors.fill: parent
        anchors.margins: 1
        radius: card.radius - 1
        gradient: Gradient {
            GradientStop { position: 0; color: C.alpha(card.accent, Tokens.alpha.wash) }
            GradientStop { position: 0.6; color: "transparent" }
        }
    }
}
