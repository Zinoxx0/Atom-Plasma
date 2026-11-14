#include "regions.h"

#include <QVariantMap>
#include <cmath>

namespace Atom {

QRegion roundedRect(const QRect &r, int radius)
{
    if (r.isEmpty()) {
        return {};
    }
    radius = std::clamp(radius, 0, std::min(r.width(), r.height()) / 2);
    if (radius == 0) {
        return QRegion(r);
    }
    // the inset of a corner's row i (0 = the outermost): where a circle of `radius` crosses the row's middle
    const auto inset = [radius](int i) {
        const double dy = radius - i - 0.5;
        return int(std::ceil(radius - std::sqrt(double(radius) * radius - dy * dy)));
    };
    // Rows go in bands: the rows that share an inset (exact, every small corner), or for a big curve (the
    // power overlay's ripple is a circle as big as the screen, rebuilt every frame) the rows within `slack`
    // px of the band's first, which is the narrowest: the band stays inside the curve. The rects are made
    // in order and set at once (adding them one by one costs as much as all those before it each time:
    // 116 ms for a 4K screen's circle, and KWin pays it again for every rect it's sent).
    const int slack = std::clamp(radius / 64, 1, 24);
    QList<QRect> bands;                     // the top corners' bands, outermost first
    for (int i = 0; i < radius;) {
        const int dx = inset(i);
        int j = i + 1;
        while (j < radius && dx - inset(j) < slack) {
            ++j;
        }
        bands.append(QRect(r.x() + dx, r.y() + i, r.width() - 2 * dx, j - i));
        i = j;
    }
    QList<QRect> rects = bands;
    if (r.height() > 2 * radius) {          // the straight middle
        rects.append(QRect(r.x(), r.y() + radius, r.width(), r.height() - 2 * radius));
    }
    for (auto b = bands.crbegin(); b != bands.crend(); ++b) {      // the bottom corners, mirrored
        rects.append(QRect(b->x(), r.y() + r.height() - (b->y() - r.y()) - b->height(), b->width(), b->height()));
    }
    QRegion region;
    region.setRects(rects.constData(), int(rects.size()));
    return region;
}

QRegion regionFromList(const QVariantList &shapes)
{
    QRegion region;
    for (const QVariant &v : shapes) {
        const QVariantMap m = v.toMap();
        const QRect r(int(std::round(m.value(QStringLiteral("x")).toDouble())),
                      int(std::round(m.value(QStringLiteral("y")).toDouble())),
                      int(std::round(m.value(QStringLiteral("width")).toDouble())),
                      int(std::round(m.value(QStringLiteral("height")).toDouble())));
        region += roundedRect(r, int(std::round(m.value(QStringLiteral("radius")).toDouble())));
    }
    return region;
}

}
