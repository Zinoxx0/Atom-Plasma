#pragma once
// Shapes from QML as a QRegion: a list of { x, y, width, height, radius } objects (logical pixels of
// the window), each a rounded rectangle. Corners are cut row by row, so a blur or input region follows
// the curve instead of a square corner.
#include <QRegion>
#include <QVariantList>

namespace Atom {
QRegion roundedRect(const QRect &r, int radius);
QRegion regionFromList(const QVariantList &shapes);
}
