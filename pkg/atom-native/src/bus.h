#pragma once
// One message bus for the whole process. Every QML engine that imports Atom.Native gets the same
// object, so widgets loaded by different engines can still talk.
//
//   Bus.send("open", { kind: "calendar", screen: Screen.name })      Connections { target: Bus; function onMessage(topic, data) {...} }
//   Bus.set("open", "calendar")      Bus.state.open                  (state: last value per key, with stateChanged)
#include <QObject>
#include <QVariant>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class Bus : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)

public:
    static Bus *create(QQmlEngine *, QJSEngine *);
    static Bus *instance();

    QVariantMap state() const { return m_state; }
    Q_INVOKABLE void send(const QString &topic, const QVariant &data = {});
    Q_INVOKABLE void set(const QString &key, const QVariant &value);
    Q_INVOKABLE QVariant get(const QString &key) const { return m_state.value(key); }

Q_SIGNALS:
    void message(const QString &topic, const QVariant &data);
    void stateChanged();

private:
    explicit Bus(QObject *parent = nullptr);
    QVariantMap m_state;
};
