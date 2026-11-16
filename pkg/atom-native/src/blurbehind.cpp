#include "blurbehind.h"
#include "regions.h"

#include <KWindowEffects>
#include <QMutexLocker>

BlurBehind::BlurBehind(QObject *parent)
    : QObject(parent)
{
}

BlurBehind::~BlurBehind()
{
    if (m_window) {
        disconnect(m_window, nullptr, this, nullptr);
        KWindowEffects::enableBlurBehind(m_window, false);
    }
}

void BlurBehind::setWindow(QQuickWindow *window)
{
    if (m_window == window) {
        return;
    }
    if (m_window) {
        disconnect(m_window, nullptr, this, nullptr);
        KWindowEffects::enableBlurBehind(m_window, false);
    }
    m_live = false;
    m_window = window;
    if (m_window) {
        connect(m_window, &QQuickWindow::beforeSynchronizing, this, &BlurBehind::sync, Qt::DirectConnection);
    }
    Q_EMIT windowChanged();
    schedule();
}

void BlurBehind::setShapes(const QVariantList &shapes)
{
    m_shapes = shapes;
    const QRegion region = Atom::regionFromList(shapes);
    {
        QMutexLocker lock(&m_mutex);
        m_region = region;
        m_dirty = true;
    }
    Q_EMIT shapesChanged();
    if (m_live && m_enabled && m_window && m_window->isExposed() && !region.isEmpty()) {
        m_window->update();             // its frame's sync sends it (one is on its way: the shape is drawn)
    } else {
        schedule();                     // on, off, or not drawing: the event loop
    }
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
    QRegion region;
    {
        QMutexLocker lock(&m_mutex);
        region = m_region;
        m_dirty = false;
    }
    // an empty region would mean "the whole window" to KWin: switch the blur off instead
    if (!m_enabled || region.isEmpty()) {
        KWindowEffects::enableBlurBehind(m_window, false);
        m_live = false;
    } else {
        KWindowEffects::enableBlurBehind(m_window, true, region);
        m_live = true;
    }
}

// The render thread, at the start of a frame's sync, with the GUI thread blocked until it ends (so nothing
// else touches KWindowEffects meanwhile). Only moves a blur that is already on: the region goes out ahead of
// the frame's commit, which applies both together. KWindowEffects then only updates its map and sends
// set_blur_region (no QObjects made, no filters or connections: those came with switching it on).
void BlurBehind::sync()
{
    QRegion region;
    {
        QMutexLocker lock(&m_mutex);
        if (!m_dirty || !m_live) {
            return;
        }
        region = m_region;
        m_dirty = false;
    }
    if (region.isEmpty()) {             // switching off: the event loop's job
        QMetaObject::invokeMethod(this, &BlurBehind::apply, Qt::QueuedConnection);
        return;
    }
    KWindowEffects::enableBlurBehind(m_window, true, region);
}
