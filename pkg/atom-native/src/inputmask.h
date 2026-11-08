#pragma once
// The part of a window that takes the pointer: the rounded rects in `shapes`; clicks anywhere else go
// through to whatever is below. An empty list lets every click through; `enabled: false` gives the
// whole window back its input.
//
//   InputMask { window: sheetWindow; shapes: open ? [{ x: s.x, y: s.y, width: s.width, height: s.height, radius: 24 }] : [] }
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class InputMask : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QVariantList shapes READ shapes WRITE setShapes NOTIFY shapesChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit InputMask(QObject *parent = nullptr);

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
