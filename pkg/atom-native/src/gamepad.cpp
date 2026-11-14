#include "gamepad.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSet>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QJSEngine>
#include <QKeyEvent>
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
        const QString path = QStringLiteral("/dev/input/") + n;
        seen.insert(path);
        if (!m_pads.contains(path)) {
            open(path);
        }
    }
    for (Pad *p : m_pads.values()) {        // unplugged
        if (!seen.contains(p->path)) {
            close(p);
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
    auto *p = new Pad;
    p->fd = fd;
    p->path = path;
    char name[256] = {};
    ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
    p->name = QString::fromUtf8(name);
    input_absinfo a{};
    if (ioctl(fd, EVIOCGABS(ABS_X), &a) == 0) {
        p->x = {a.minimum, a.maximum};
    }
    if (ioctl(fd, EVIOCGABS(ABS_Y), &a) == 0) {
        p->y = {a.minimum, a.maximum};
    }
    p->notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(p->notifier, &QSocketNotifier::activated, this, [this, p] { read(p); });
    const bool was = present();
    m_pads.insert(path, p);
    if (!was) {
        Q_EMIT presentChanged();
    }
}

void Gamepad::close(Pad *p)
{
    m_pads.remove(p->path);
    delete p->notifier;
    ::close(p->fd);
    delete p;
    steer();
    if (m_pads.isEmpty()) {
        Q_EMIT presentChanged();
    }
}

void Gamepad::closeAll()
{
    const auto pads = m_pads.values();
    for (Pad *p : pads) {
        close(p);
    }
    m_held = 0;
    m_repeat->stop();
}

void Gamepad::read(Pad *p)
{
    input_event ev[64];
    for (;;) {
        const ssize_t n = ::read(p->fd, ev, sizeof(ev));
        if (n <= 0) {
            if (n == 0 || (errno != EAGAIN && errno != EINTR)) {
                close(p);                   // gone (ENODEV)
            }
            return;
        }
        bool dir = false;
        for (size_t i = 0; i < size_t(n) / sizeof(input_event); i++) {
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
                    switch (e.code) {
                    case BTN_SOUTH: press(Qt::Key_Return); Q_EMIT button(QStringLiteral("south")); break;
                    case BTN_EAST: press(Qt::Key_Escape); Q_EMIT button(QStringLiteral("east")); break;
                    case BTN_WEST: press(Qt::Key_Menu); Q_EMIT button(QStringLiteral("west")); break;
                    case BTN_NORTH: setInUse(true); Q_EMIT button(QStringLiteral("north")); break;
                    case BTN_TL: press(Qt::Key_Backtab, Qt::ShiftModifier); Q_EMIT button(QStringLiteral("lb")); break;
                    case BTN_TR: press(Qt::Key_Tab); Q_EMIT button(QStringLiteral("rb")); break;
                    case BTN_START: setInUse(true); Q_EMIT button(QStringLiteral("start")); break;
                    case BTN_SELECT: setInUse(true); Q_EMIT button(QStringLiteral("select")); break;
                    default: break;
                    }
                }
            }
        }
        if (dir) {
            steer();
        }
    }
}

void Gamepad::steer()
{
    int dx = 0, dy = 0;
    for (const Pad *p : std::as_const(m_pads)) {
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

void Gamepad::press(int key, Qt::KeyboardModifiers mods, bool repeat)
{
    setInUse(true);
    QWindow *w = QGuiApplication::focusWindow();
    if (!w) {
        return;
    }
    m_sending = true;
    QKeyEvent down(QEvent::KeyPress, key, mods, QString(), repeat);
    QCoreApplication::sendEvent(w, &down);
    QKeyEvent up(QEvent::KeyRelease, key, mods, QString(), repeat);
    QCoreApplication::sendEvent(w, &up);
    m_sending = false;
}
