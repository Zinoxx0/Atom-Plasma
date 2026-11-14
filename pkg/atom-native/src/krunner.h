#pragma once
// KRunner's place on the bus, taken by the rice: every way KRunner opens (its shortcut, Alt+Space / Alt+F2 /
// Search through kglobalaccel's org.freedesktop.Application.Activate, Alt+Shift+F2's RunClipboard action,
// typing on the desktop through /App query) opens the launcher's own search instead (the finder).
//
//   KRunner.active = true       (the launcher widget; only in plasmashell, never in tests or other processes)
//   Connections { target: KRunner; function onRequested(action, query) {...} }    action: display | query | clipboard
//
// It owns org.kde.krunner on the session bus while active; the real KRunner must not run (rice.py masks its
// unit, plasma-krunner.service). If the name is taken when it turns active, it takes it the moment it's free.
#include <QDBusServiceWatcher>
#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

class KRunner : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool owner READ owner NOTIFY ownerChanged)       // it holds org.kde.krunner now

public:
    static KRunner *create(QQmlEngine *, QJSEngine *);
    bool active() const { return m_active; }
    void setActive(bool on);
    bool owner() const { return m_owner; }
    void request(const QString &action, const QString &query = {});

Q_SIGNALS:
    void activeChanged();
    void ownerChanged();
    void requested(const QString &action, const QString &query);

private:
    explicit KRunner(QObject *parent = nullptr);
    void claim();
    bool m_active = false;
    bool m_owner = false;
    bool m_exported = false;
    QDBusServiceWatcher *m_watcher = nullptr;
};

// /App, org.kde.krunner.App: what Plasma calls (the desktop's type-to-search: query)
class KRunnerApp : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.krunner.App")
public:
    explicit KRunnerApp(KRunner *k) : QObject(k), m_k(k) {}
public Q_SLOTS:
    Q_SCRIPTABLE void display() { m_k->request(QStringLiteral("display")); }
    Q_SCRIPTABLE void displaySingleRunner(const QString &) { m_k->request(QStringLiteral("display")); }
    Q_SCRIPTABLE void displayWithClipboardContents() { m_k->request(QStringLiteral("clipboard")); }
    Q_SCRIPTABLE void query(const QString &term) { m_k->request(QStringLiteral("query"), term); }
    Q_SCRIPTABLE void querySingleRunner(const QString &, const QString &term) { m_k->request(QStringLiteral("query"), term); }
    Q_SCRIPTABLE void toggleDisplay() { m_k->request(QStringLiteral("toggle")); }
private:
    KRunner *m_k;
};

// /org/kde/krunner, org.freedesktop.Application: kglobalaccel's shortcuts (KRunner is DBusActivatable)
class KRunnerActivation : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")
public:
    explicit KRunnerActivation(KRunner *k) : QObject(k), m_k(k) {}
public Q_SLOTS:
    Q_SCRIPTABLE void Activate(const QVariantMap &) { m_k->request(QStringLiteral("toggle")); }
    Q_SCRIPTABLE void Open(const QStringList &, const QVariantMap &) { m_k->request(QStringLiteral("display")); }
    Q_SCRIPTABLE void ActivateAction(const QString &action, const QVariantList &, const QVariantMap &)
    {
        m_k->request(action == QLatin1String("RunClipboard") ? QStringLiteral("clipboard") : QStringLiteral("display"));
    }
private:
    KRunner *m_k;
};
