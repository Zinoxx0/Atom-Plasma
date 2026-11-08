#pragma once
// KWin's blur behind part of a window: the rounded rects in `shapes` (window coordinates, logical px).
//
//   BlurBehind { window: sheetWindow; shapes: [{ x: s.x, y: s.y, width: s.width, height: s.height, radius: 24 }] }
//
// Bind `shapes` to an animated shape and the blur follows it: changes made in one event-loop pass are
// sent together, once. An empty list (or enabled: false) removes the blur.
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QVariantList>
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

    QPointer<QQuickWindow> m_window;
    QVariantList m_shapes;
    bool m_enabled = true;
    bool m_pending = false;
};
