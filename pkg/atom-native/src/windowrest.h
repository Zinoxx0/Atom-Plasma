#pragma once
// Lets a hidden window give its video memory back. While `resting`, its scene graph and graphics resources
// aren't kept (QQuickWindow's persistentSceneGraph and persistentGraphics off) and are released at once if
// it's hidden; the next show rebuilds them (its first frame uploads everything again). Not resting: kept,
// Qt's default. (QML can call releaseResources() but not set the two flags, and with them on it frees only
// caches.)
//
//   WindowRest { window: stage; resting: stage.idle && stage.phase === "closed" }
#include <QObject>
#include <QPointer>
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
        m_window = window;
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
        }
    }

    QPointer<QQuickWindow> m_window;
    bool m_resting = false;
};
