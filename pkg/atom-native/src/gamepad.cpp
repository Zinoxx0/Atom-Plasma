#include "gamepad.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSet>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QJSEngine>
#include <QKeyEvent>
#include <QPointer>
#include <QSocketNotifier>
#include <QTimer>
#include <QWindow>

#include <cerrno>
#include <utility>

#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
constexpr int RepeatDelay = 380;            // ms before a held direction repeats, then every RepeatEvery
constexpr int RepeatEvery = 115;
constexpr double StickOn = 0.55;            // of the stick's travel: a direction starts past this...
constexpr double StickOff = 0.35;           // ...and lets go below this (no flutter at the edge)

bool testBit(const unsigned long *bits, int bit)
{
    return bits[bit / (8 * sizeof(long))] & (1UL << (bit % (8 * sizeof(long))));
}
}

Gamepad::Gamepad(QObject *parent)
    : QObject(parent)
{
    m_repeat = new QTimer(this);
    connect(m_repeat, &QTimer::timeout, this, [this] {
        m_repeat->setInterval(RepeatEvery);
        if (m_held) {
            press(m_held, Qt::NoModifier, true);
        }
    });
    m_rescan = new QTimer(this);            // a new device node needs a moment before udev lets us read it
    m_rescan->setSingleShot(true);
    m_rescan->setInterval(400);
    connect(m_rescan, &QTimer::timeout, this, &Gamepad::scan);
}

Gamepad *Gamepad::create(QQmlEngine *, QJSEngine *)
{
    static Gamepad *g = new Gamepad;        // one per process, like Bus
    QJSEngine::setObjectOwnership(g, QJSEngine::CppOwnership);
    return g;
}

QString Gamepad::name() const
{
    return m_pads.isEmpty() ? QString() : m_pads.cbegin().value()->name;
}

void Gamepad::setActive(bool on)
{
    if (on == m_active) {
        return;
    }
    m_active = on;
    if (on) {
        if (!m_watch) {
            m_watch = new QFileSystemWatcher(this);
            connect(m_watch, &QFileSystemWatcher::directoryChanged, this, [this] { m_rescan->start(); });
        }
        m_watch->addPath(QStringLiteral("/dev/input"));
        scan();
    } else {
        if (m_watch) {
            m_watch->removePaths(m_watch->directories());
        }
        m_rescan->stop();
        closeAll();
        setInUse(false);
    }
    Q_EMIT activeChanged();
}

void Gamepad::setInUse(bool on)
{
    if (on != m_inUse) {
        m_inUse = on;
        Q_EMIT inUseChanged();
    }
}

void Gamepad::scan()
{
    if (!m_active) {
        return;
    }
    const QStringList nodes = QDir(QStringLiteral("/dev/input")).entryList({QStringLiteral("event*")}, QDir::System);
    QSet<QString> seen;
    for (const QString &n : nodes) {
        seen.insert(QStringLiteral("/dev/input/") + n);
    }
    // unplugged, or unplugged and another device given the same node meanwhile (the kernel reuses the
    // lowest free eventN): the open one isn't the one at that path any more
    const QList<PadRef> pads = m_pads.values();
    for (const PadRef &p : pads) {
        int version = 0;                    // (a removed device answers nothing but ENODEV)
        if (p->fd >= 0 && (!seen.contains(p->path) || ioctl(p->fd, EVIOCGVERSION, &version) < 0)) {
            close(p.get());                 // (may send an arrow's release: a handler may turn us off)
        }
    }
    if (!m_active) {
        return;
    }
    for (const QString &path : std::as_const(seen)) {
        if (!m_pads.contains(path)) {
            open(path);
        }
    }
}

void Gamepad::open(const QString &path)
{
    const int fd = ::open(QFile::encodeName(path).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        return;                             // not ours to read (keyboards, mice: root's), or gone
    }
    unsigned long keys[(KEY_MAX + 1) / (8 * sizeof(long)) + 1] = {};
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0 || !testBit(keys, BTN_SOUTH)) {
        ::close(fd);                        // not a gamepad
        return;
    }
    auto pad = std::make_shared<Pad>();
    Pad *p = pad.get();
    p->fd = fd;
    p->path = path;
    char name[256] = {};
    ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
    p->name = QString::fromUtf8(name);
    // Xbox pads (xpad, and the Bluetooth ones through hid-generic) report X as BTN_X = 0x133, which the kernel
    // also names BTN_NORTH, and Y as 0x134 = BTN_WEST: by place X is the LEFT button. Steam's database says
    // the same (x:b3). Pads that follow the kernel's spec put their left button on BTN_WEST.
    input_id id{};
    ioctl(fd, EVIOCGID, &id);
    p->xbox = id.vendor == 0x045e || p->name.contains(QLatin1String("xbox"), Qt::CaseInsensitive)
              || p->name.contains(QLatin1String("x-box"), Qt::CaseInsensitive);
    input_absinfo a{};
    if (ioctl(fd, EVIOCGABS(ABS_X), &a) == 0) {
        p->x = {a.minimum, a.maximum};
    }
    if (ioctl(fd, EVIOCGABS(ABS_Y), &a) == 0) {
        p->y = {a.minimum, a.maximum};
    }
    p->notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    // (weak: the list owns the pad; the read holds it only while it runs)
    connect(p->notifier, &QSocketNotifier::activated, this, [this, weak = std::weak_ptr<Pad>(pad)] {
        if (PadRef pad = weak.lock()) {
            read(std::move(pad));
        }
    });
    const bool was = present();
    m_pads.insert(path, std::move(pad));
    if (!was) {
        Q_EMIT presentChanged();
    }
}

void Gamepad::drop(Pad *p)
{
    if (p->fd < 0) {
        return;
    }
    // the notifier may be the one whose signal we're in (a read that found the device gone): it goes
    // after the event, and it stops watching the descriptor before the descriptor is closed
    p->notifier->setEnabled(false);
    p->notifier->deleteLater();
    p->notifier = nullptr;
    ::close(p->fd);
    p->fd = -1;
    const auto it = m_pads.constFind(p->path);
    if (it != m_pads.cend() && it.value().get() == p) {
        m_pads.erase(it);                   // (last: this may be what frees the pad)
    }
}

void Gamepad::close(Pad *p)
{
    const bool was = present();
    drop(p);                                // (p may be gone now: only the list's state from here)
    if (was && !present()) {
        Q_EMIT presentChanged();
    }
    steer();                                // its directions no longer count
}

void Gamepad::closeAll()
{
    m_held = 0;                             // first: nothing below sends a key
    m_repeat->stop();
    const bool was = present();
    const QList<PadRef> pads = m_pads.values();
    for (const PadRef &p : pads) {
        drop(p.get());
    }
    if (was) {
        Q_EMIT presentChanged();
    }
}

void Gamepad::read(PadRef pad)
{
    // Every key and signal below runs QML at once, and it can close the surface: the Gamepad turns off and
    // closes this pad. `pad` keeps it alive meanwhile; after each one, a closed pad (fd < 0) ends the read.
    Pad *p = pad.get();
    input_event ev[64];
    while (p->fd >= 0) {
        const ssize_t n = ::read(p->fd, ev, sizeof(ev));
        if (n <= 0) {
            if (n == 0 || (errno != EAGAIN && errno != EINTR)) {
                close(p);                   // gone (ENODEV): another may be on its way at the same node
                if (m_active) {
                    m_rescan->start();
                }
            }
            return;
        }
        bool dir = false;
        for (size_t i = 0; i < size_t(n) / sizeof(input_event) && p->fd >= 0; i++) {
            const input_event &e = ev[i];
            if (e.type == EV_ABS) {
                auto stick = [](int v, const Axis &ax, int held) {
                    if (ax.max <= ax.min) {
                        return 0;
                    }
                    const double c = (ax.min + ax.max) / 2.0, k = (v - c) / ((ax.max - ax.min) / 2.0);
                    const double on = held ? StickOff : StickOn;
                    return k <= -on ? -1 : k >= on ? 1 : 0;
                };
                if (e.code == ABS_HAT0X) { p->hatX = e.value < 0 ? -1 : e.value > 0 ? 1 : 0; dir = true; }
                else if (e.code == ABS_HAT0Y) { p->hatY = e.value < 0 ? -1 : e.value > 0 ? 1 : 0; dir = true; }
                else if (e.code == ABS_X) { const int s = stick(e.value, p->x, p->stickX); if (s != p->stickX) { p->stickX = s; dir = true; } }
                else if (e.code == ABS_Y) { const int s = stick(e.value, p->y, p->stickY); if (s != p->stickY) { p->stickY = s; dir = true; } }
            } else if (e.type == EV_KEY && e.value != 2) {      // (2: the kernel's own repeat: ours is above)
                const bool down = e.value == 1;
                switch (e.code) {
                case BTN_DPAD_UP: p->padY = down ? -1 : (p->padY == -1 ? 0 : p->padY); dir = true; break;
                case BTN_DPAD_DOWN: p->padY = down ? 1 : (p->padY == 1 ? 0 : p->padY); dir = true; break;
                case BTN_DPAD_LEFT: p->padX = down ? -1 : (p->padX == -1 ? 0 : p->padX); dir = true; break;
                case BTN_DPAD_RIGHT: p->padX = down ? 1 : (p->padX == 1 ? 0 : p->padX); dir = true; break;
                default:
                    if (!down) {
                        break;
                    }
                    const int place = p->xbox && e.code == BTN_NORTH ? BTN_WEST : p->xbox && e.code == BTN_WEST ? BTN_NORTH : e.code;
                    switch (place) {
                    case BTN_SOUTH: tap(Qt::Key_Return, QStringLiteral("south")); break;
                    case BTN_EAST: tap(Qt::Key_Escape, QStringLiteral("east")); break;
                    case BTN_WEST: tap(Qt::Key_Menu, QStringLiteral("west")); break;
                    case BTN_NORTH: tap(0, QStringLiteral("north")); break;
                    case BTN_TL: tap(Qt::Key_Backtab, QStringLiteral("lb"), Qt::ShiftModifier); break;
                    case BTN_TR: tap(Qt::Key_Tab, QStringLiteral("rb")); break;
                    case BTN_START: tap(0, QStringLiteral("start")); break;
                    case BTN_SELECT: tap(0, QStringLiteral("select")); break;
                    default: break;
                    }
                }
            }
        }
        if (dir && p->fd >= 0) {
            steer();
        }
    }
}

void Gamepad::steer()
{
    int dx = 0, dy = 0;
    for (const PadRef &p : std::as_const(m_pads)) {
        dx += p->hatX + p->padX + p->stickX;
        dy += p->hatY + p->padY + p->stickY;
    }
    dx = dx < 0 ? -1 : dx > 0 ? 1 : 0;
    dy = dy < 0 ? -1 : dy > 0 ? 1 : 0;
    // one arrow at a time: a diagonal keeps the one already held, else the vertical
    int key = 0;
    const int h = dx < 0 ? Qt::Key_Left : dx > 0 ? Qt::Key_Right : 0;
    const int v = dy < 0 ? Qt::Key_Up : dy > 0 ? Qt::Key_Down : 0;
    if (h && v) {
        key = (m_held == h || m_held == v) ? m_held : v;
    } else {
        key = h ? h : v;
    }
    if (key == m_held) {
        return;
    }
    m_held = key;
    m_repeat->stop();
    if (key) {
        press(key);
        m_repeat->setInterval(RepeatDelay);
        m_repeat->start();
    }
}

void Gamepad::tap(int key, const QString &name, Qt::KeyboardModifiers mods)
{
    if (key) {
        press(key, mods);
    } else if (m_active) {
        setInUse(true);
    }
    if (m_active) {                         // (its key may have closed the surface: then it's not for anyone)
        Q_EMIT button(name);
    }
}

void Gamepad::press(int key, Qt::KeyboardModifiers mods, bool repeat)
{
    if (!m_active) {
        return;                             // (a handler turned us off earlier in this read)
    }
    setInUse(true);
    // the press can close the window it went to (Escape on the power overlay): the release then goes nowhere
    QPointer<QWindow> w = QGuiApplication::focusWindow();
    if (!w) {
        return;
    }
    m_sending = true;
    QKeyEvent down(QEvent::KeyPress, key, mods, QString(), repeat);
    QCoreApplication::sendEvent(w, &down);
    if (w) {
        QKeyEvent up(QEvent::KeyRelease, key, mods, QString(), repeat);
        QCoreApplication::sendEvent(w, &up);
    }
    m_sending = false;
}
