#pragma once
// KWin's blur behind part of a window: the rounded rects in `shapes` (window coordinates, logical px).
//
//   BlurBehind { window: sheetWindow; shapes: [{ x: s.x, y: s.y, width: s.width, height: s.height, radius: 24 }] }
//
// Bind `shapes` to an animated shape and the blur follows it, frame by frame: while the blur is on, a new
// shape goes out in the sync of the frame that draws it (render thread, GUI thread blocked), so KWin gets
// each region with its own frame. Sent from the event loop it went one frame EARLY: Qt advances the
// animations for the next frame while the render thread is still drawing this one, and the blur ran ahead
// of the glass. Switching it on or off goes through the event loop. An empty list (or enabled: false)
// removes the blur.
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QRegion>
#include <QVariantList>
#include <atomic>
#include <QtQml/qqmlregistration.h>

class BlurBehind : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QVariantList shapes READ shapes WRITE setShapes NOTIFY shapesChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit BlurBehind(QObject *parent = nullptr);
    ~BlurBehind() override;

    QQuickWindow *window() const { return m_window; }
    void setWindow(QQuickWindow *window);
    QVariantList shapes() const { return m_shapes; }
    void setShapes(const QVariantList &shapes);
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);

Q_SIGNALS:
    void windowChanged();
    void shapesChanged();
    void enabledChanged();

private:
    void schedule();
    void apply();
    void sync();

    QPointer<QQuickWindow> m_window;
    QVariantList m_shapes;
    QMutex m_mutex;                 // m_region / m_dirty, read in the render thread's sync
    QRegion m_region;               // made from m_shapes in the GUI thread (they may hold JS values)
    bool m_dirty = false;
    bool m_enabled = true;
    bool m_pending = false;
    std::atomic<bool> m_live{false}; // the blur is on (set from the event loop): the sync may move it
};
