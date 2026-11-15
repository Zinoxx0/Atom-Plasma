#pragma once
// One message bus for the whole process. Every QML engine that imports Atom.Native gets the same
// object, so widgets loaded by different engines can still talk.
//
//   Bus.send("open", { kind: "calendar", screen: Screen.name })      Connections { target: Bus; function onMessage(topic, data) {...} }
//   Bus.set("open", "calendar")      Bus.state.open                  (state: last value per key, with stateChanged)
//
// Other processes reach it over D-Bus: object /Atom on this process's session connection (in plasmashell,
// service org.kde.plasmashell), interface org.zinoxx.Atom, Post(topic, json): the JSON becomes `data`, is
// sent as a message AND kept as state[topic]. KWin's rice_islands script tells the shell this way which
// screen holds the bar's islands and which screens a fullscreen window covers; Peek(topic) reads a state back.
#include <QObject>
#include <QVariant>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class Bus : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.zinoxx.Atom")
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

public Q_SLOTS:
    Q_SCRIPTABLE void Post(const QString &topic, const QString &json);
    // state[topic] as JSON ("null" when there's none): KWin's rice_islands script asks for "cover", the
    // screens the shell's own full-screen surfaces cover (the launcher), which it treats as a fullscreen window
    Q_SCRIPTABLE QString Peek(const QString &topic) const;

Q_SIGNALS:
    void message(const QString &topic, const QVariant &data);
    void stateChanged();

private:
    explicit Bus(QObject *parent = nullptr);
    QVariantMap m_state;
};
