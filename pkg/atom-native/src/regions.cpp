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
    QRegion region(r.adjusted(0, radius, 0, -radius));   // the straight middle band
    for (int i = 0; i < radius; ++i) {
        // the inset of this row: where a circle of `radius` crosses the row's middle
        const double dy = radius - i - 0.5;
        const int dx = int(std::ceil(radius - std::sqrt(double(radius) * radius - dy * dy)));
        region += QRect(r.x() + dx, r.y() + i, r.width() - 2 * dx, 1);
        region += QRect(r.x() + dx, r.y() + r.height() - 1 - i, r.width() - 2 * dx, 1);
    }
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
