#include "bus.h"

#include <QJSEngine>
#include <QQmlEngine>

Bus::Bus(QObject *parent)
    : QObject(parent)
{
}

Bus *Bus::instance()
{
    static Bus *bus = new Bus;      // lives as long as the process; no engine owns it
    return bus;
}

Bus *Bus::create(QQmlEngine *, QJSEngine *)
{
    Bus *bus = instance();
    QJSEngine::setObjectOwnership(bus, QJSEngine::CppOwnership);
    return bus;
}

void Bus::send(const QString &topic, const QVariant &data)
{
    Q_EMIT message(topic, data);
}

void Bus::set(const QString &key, const QVariant &value)
{
    if (m_state.value(key) == value && m_state.contains(key)) {
        return;
    }
    m_state.insert(key, value);
    Q_EMIT stateChanged();
}
