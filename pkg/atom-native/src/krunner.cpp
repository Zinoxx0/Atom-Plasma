#include "krunner.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QJSEngine>

static const QString Service = QStringLiteral("org.kde.krunner");

KRunner::KRunner(QObject *parent)
    : QObject(parent)
{
}

KRunner *KRunner::create(QQmlEngine *, QJSEngine *)
{
    static KRunner *k = new KRunner;    // one per process, like Bus
    QJSEngine::setObjectOwnership(k, QJSEngine::CppOwnership);
    return k;
}

void KRunner::setActive(bool on)
{
    // only plasmashell answers for KRunner: a test or another process never takes the name
    if (on == m_active || (on && QCoreApplication::applicationName() != QLatin1String("plasmashell"))) {
        return;
    }
    m_active = on;
    Q_EMIT activeChanged();
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (on) {
        if (!m_exported) {
            bus.registerObject(QStringLiteral("/App"), new KRunnerApp(this), QDBusConnection::ExportScriptableSlots);
            bus.registerObject(QStringLiteral("/org/kde/krunner"), new KRunnerActivation(this), QDBusConnection::ExportScriptableSlots);
            m_exported = true;
        }
        if (!m_watcher) {       // the real KRunner held it: take it the moment it lets go
            m_watcher = new QDBusServiceWatcher(Service, bus, QDBusServiceWatcher::WatchForUnregistration, this);
            connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
                if (m_active && !m_owner) {
                    claim();
                }
            });
        }
        claim();
    } else if (m_owner) {
        bus.unregisterService(Service);
        m_owner = false;
        Q_EMIT ownerChanged();
    }
}

void KRunner::claim()
{
    const bool ok = QDBusConnection::sessionBus().registerService(Service);
    if (ok != m_owner) {
        m_owner = ok;
        Q_EMIT ownerChanged();
    }
}

void KRunner::request(const QString &action, const QString &query)
{
    if (m_active) {
        Q_EMIT requested(action, query);
    }
}
