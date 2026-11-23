#pragma once
// Lets a hidden window give its video memory back. While `resting`, its scene graph and graphics resources
// aren't kept (QQuickWindow's persistentSceneGraph and persistentGraphics off) and are released at once if
// it's hidden; the next show rebuilds them (its first frame uploads everything again). Not resting: kept,
// Qt's default. (QML can call releaseResources() but not set the two flags, and with them on it frees only
// caches.)
// Qt 6.12 trap: a Shape drawn by the CurveRenderer comes back EMPTY after its scene graph was released (its new node
// gets no geometry until a path changes; the geometry renderer is fine): the first show after a rest re-syncs every
// Shape in the window (its renderer type set away and back = a full rebuild). It was the Atom launcher's blank jewel
// and its missing haze gaps (2026-11-23).
//
//   WindowRest { window: stage; resting: stage.idle && stage.phase === "closed" }
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

class WindowRest : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(bool resting READ resting WRITE setResting NOTIFY restingChanged)

public:
    explicit WindowRest(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    QQuickWindow *window() const { return m_window; }
    void setWindow(QQuickWindow *window)
    {
        if (m_window == window) {
            return;
        }
        if (m_window) {
            disconnect(m_window, nullptr, this, nullptr);
        }
        m_window = window;
        if (m_window) {
            connect(m_window, &QWindow::visibleChanged, this, [this](bool shown) {
                if (!shown && m_resting) {
                    m_released = true;      // hidden while resting: the scene graph goes
                } else if (shown && m_released) {
                    m_released = false;
                    resyncShapes(m_window->contentItem());
                }
            });
        }
        apply();
        Q_EMIT windowChanged();
    }
    bool resting() const { return m_resting; }
    void setResting(bool resting)
    {
        if (m_resting == resting) {
            return;
        }
        m_resting = resting;
        apply();
        Q_EMIT restingChanged();
    }

Q_SIGNALS:
    void windowChanged();
    void restingChanged();

private:
    void apply()
    {
        if (!m_window) {
            return;
        }
        m_window->setPersistentGraphics(!m_resting);
        m_window->setPersistentSceneGraph(!m_resting);
        if (m_resting && !m_window->isVisible()) {
            m_window->releaseResources();
            m_released = true;
        }
    }
    static void resyncShapes(QQuickItem *item)
    {
        if (!item) {
            return;
        }
        if (item->inherits("QQuickShape")) {
            const QVariant type = item->property("preferredRendererType");
            if (type.toInt() == 4) {        // CurveRenderer
                item->setProperty("preferredRendererType", 1);
                item->setProperty("preferredRendererType", type);
            }
        }
        const auto kids = item->childItems();
        for (QQuickItem *child : kids) {
            resyncShapes(child);
        }
    }

    QPointer<QQuickWindow> m_window;
    bool m_resting = false;
    bool m_released = false;
};
