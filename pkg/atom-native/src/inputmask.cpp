#include "inputmask.h"
#include "regions.h"

InputMask::InputMask(QObject *parent)
    : QObject(parent)
{
}

void InputMask::setWindow(QQuickWindow *window)
{
    if (m_window == window) {
        return;
    }
    if (m_window) {
        m_window->setMask(QRegion());
    }
    m_window = window;
    Q_EMIT windowChanged();
    schedule();
}

void InputMask::setShapes(const QVariantList &shapes)
{
    m_shapes = shapes;
    Q_EMIT shapesChanged();
    schedule();
}

void InputMask::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    Q_EMIT enabledChanged();
    schedule();
}

void InputMask::schedule()
{
    if (m_pending) {
        return;
    }
    m_pending = true;
    QMetaObject::invokeMethod(this, &InputMask::apply, Qt::QueuedConnection);
}

void InputMask::apply()
{
    m_pending = false;
    if (!m_window) {
        return;
    }
    if (!m_enabled) {
        m_window->setMask(QRegion());       // no mask: the whole window takes input
        return;
    }
    QRegion region = Atom::regionFromList(m_shapes);
    if (region.isEmpty()) {
        // QWindow reads an empty mask as "no mask"; one pixel outside the window means "no input at all"
        region = QRegion(-1, -1, 1, 1);
    }
    m_window->setMask(region);
}
