#include "blurbehind.h"
#include "regions.h"

#include <KWindowEffects>

BlurBehind::BlurBehind(QObject *parent)
    : QObject(parent)
{
}

BlurBehind::~BlurBehind()
{
    if (m_window) {
        KWindowEffects::enableBlurBehind(m_window, false);
    }
}

void BlurBehind::setWindow(QQuickWindow *window)
{
    if (m_window == window) {
        return;
    }
    if (m_window) {
        KWindowEffects::enableBlurBehind(m_window, false);
    }
    m_window = window;
    Q_EMIT windowChanged();
    schedule();
}

void BlurBehind::setShapes(const QVariantList &shapes)
{
    m_shapes = shapes;
    Q_EMIT shapesChanged();
    schedule();
}

void BlurBehind::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    Q_EMIT enabledChanged();
    schedule();
}

void BlurBehind::schedule()
{
    if (m_pending) {
        return;
    }
    m_pending = true;
    QMetaObject::invokeMethod(this, &BlurBehind::apply, Qt::QueuedConnection);
}

void BlurBehind::apply()
{
    m_pending = false;
    if (!m_window) {
        return;
    }
    const QRegion region = Atom::regionFromList(m_shapes);
    // an empty region would mean "the whole window" to KWin: switch the blur off instead
    if (!m_enabled || region.isEmpty()) {
        KWindowEffects::enableBlurBehind(m_window, false);
    } else {
        KWindowEffects::enableBlurBehind(m_window, true, region);
    }
}
