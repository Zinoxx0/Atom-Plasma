#pragma once
// A game controller for the rice's full-screen surfaces (the launcher, its Theme page, the power overlay):
// while `active`, every pad on the machine (evdev /dev/input/event*: anything with a south button, read
// without grabbing it, so games and Steam still see everything) becomes the keys those surfaces already
// answer, sent to the window that has the keyboard as ordinary key events. The pad drives exactly what the
// keyboard drives, so nothing needs a second path:
//   D-pad, left stick   the arrows (held: they repeat)       A (south)   Enter       B (east)   Escape
//   LB / RB             Shift+Tab / Tab (the pages)          X (west)    Menu (an item's options)
// Every press is also a signal, `button(name)`, for what has no key (Y, north: the launcher's Theme page).
// Inactive, no device is open: a game in the foreground is never read.
//
//   Gamepad.active = true;  Gamepad.present (a pad is there);  Gamepad.inUse (the last input came from a pad)
//   Connections { target: Gamepad; function onButton(name) { ... } }   north | start | select | ...
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <memory>

class QQmlEngine;
class QJSEngine;
class QSocketNotifier;
class QFileSystemWatcher;
class QTimer;

class Gamepad : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool present READ present NOTIFY presentChanged)
    Q_PROPERTY(bool inUse READ inUse WRITE setInUse NOTIFY inUseChanged)
    Q_PROPERTY(bool sending READ sending)       // inside a key event the pad sent (read from a key handler)
    Q_PROPERTY(QString name READ name NOTIFY presentChanged)

public:
    static Gamepad *create(QQmlEngine *, QJSEngine *);
    bool active() const { return m_active; }
    void setActive(bool on);
    bool present() const { return !m_pads.isEmpty(); }
    bool inUse() const { return m_inUse; }
    void setInUse(bool on);
    bool sending() const { return m_sending; }
    QString name() const;

Q_SIGNALS:
    void activeChanged();
    void presentChanged();
    void inUseChanged();
    void button(const QString &name);

private:
    struct Axis { int min = 0; int max = 0; };
    // A pad lives as long as someone holds it: the list of open pads, and a read in progress. A key the pad
    // sends can close the surface, which turns the Gamepad off and closes every pad, from inside that read;
    // the read then sees fd < 0 and stops, and the pad goes away after it.
    struct Pad {
        int fd = -1;                        // -1: closed
        QString path, name;
        QSocketNotifier *notifier = nullptr;
        Axis x, y;
        int hatX = 0, hatY = 0;             // the D-pad as a hat (-1, 0, 1)
        int padX = 0, padY = 0;             // the D-pad as buttons
        int stickX = 0, stickY = 0;         // the left stick, past its threshold (-1, 0, 1)
    };
    explicit Gamepad(QObject *parent = nullptr);
    void scan();
    using PadRef = std::shared_ptr<Pad>;
    void open(const QString &path);
    void drop(Pad *p);                      // closes its device, nothing else (no signal, no key)
    void close(Pad *p);                     // drop(), then what it changes: present, the arrow held
    void closeAll();
    void read(PadRef pad);
    void steer();                           // the direction now held (every pad together): arrows, repeat
    void tap(int key, const QString &name, Qt::KeyboardModifiers mods = Qt::NoModifier);  // a button: its key, then button(name)
    void press(int key, Qt::KeyboardModifiers mods = Qt::NoModifier, bool repeat = false);

    bool m_active = false;
    bool m_inUse = false;
    bool m_sending = false;
    QHash<QString, PadRef> m_pads;
    QFileSystemWatcher *m_watch = nullptr;
    QTimer *m_repeat = nullptr;
    QTimer *m_rescan = nullptr;
    int m_held = 0;                         // the arrow held (a Qt::Key) or 0
};
