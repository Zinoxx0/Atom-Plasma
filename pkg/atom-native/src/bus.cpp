#include "bus.h"

#include <QDBusConnection>
#include <QJSEngine>
#include <QJsonDocument>
#include <QQmlEngine>

Bus::Bus(QObject *parent)
    : QObject(parent)
{
    // a second process importing Atom.Native has its own connection: the path never clashes
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/Atom"), this, QDBusConnection::ExportScriptableSlots);
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

void Bus::Post(const QString &topic, const QString &json)
{
    const QVariant data = QJsonDocument::fromJson(json.toUtf8()).toVariant();
    set(topic, data);
    send(topic, data);
}

QString Bus::Peek(const QString &topic) const
{
    if (!m_state.contains(topic)) {
        return QStringLiteral("null");
    }
    return QString::fromUtf8(QJsonDocument::fromVariant(m_state.value(topic)).toJson(QJsonDocument::Compact));
}
