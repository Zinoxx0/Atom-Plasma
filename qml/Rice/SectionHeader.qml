import QtQuick

// Small caps heading above a group in a popup ("PINNED", "RESULTS", ...).
Text {
    required override property RicePalette palette
    color: palette.fgDim
    opacity: 0.8
    font.family: Tokens.font.ui
    font.weight: Font.Bold
    font.pixelSize: Tokens.size.caption
    font.letterSpacing: 1.2
    font.capitalization: Font.AllUppercase
}
