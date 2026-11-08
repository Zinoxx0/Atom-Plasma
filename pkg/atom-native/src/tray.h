#pragma once
// The apps' tray icons (StatusNotifierItems) for the status island, without Plasma's system tray.
//
//   Tray (singleton, a list model): one row per app icon the session's StatusNotifierWatcher knows
//     roles: key, appId, title, status ("Passive" | "Active" | "NeedsAttention"), iconName, iconSource
//            (a data: URL when the app sends pixels instead of a name), tooltip, itemIsMenu, hasMenu
//     activate(row, x, y), secondaryActivate(row, x, y), scroll(row, delta, horizontal), contextMenu(row, x, y)
//     menu(row) -> TrayMenu (the app's menu, read over DBusMenu; null when it has none)
//   TrayMenu (a list model): text, iconName, iconSource, enabled, checkable, checked, separator, hasSubmenu
//     trigger(row), submenu(row) -> TrayMenu; `ready` once the app has answered
//
// Tray registers this process as a StatusNotifierHost (apps only show an icon while some host exists)
// and follows icons coming, changing and going.
#include <QAbstractListModel>
#include <QDBusConnection>
#include <QImage>
#include <QPointer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QMenu;
class QAction;
class DBusMenuImporter;
class QDBusPendingCallWatcher;
class QQmlEngine;
class QJSEngine;

class TrayMenu : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("from Tray.menu()")
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles { Text = Qt::UserRole + 1, IconName, IconSource, Enabled, Checkable, Checked, Separator, HasSubmenu };
    TrayMenu(const QString &service, const QString &path, QObject *parent = nullptr);   // a root menu
    TrayMenu(DBusMenuImporter *importer, QMenu *menu, QObject *parent = nullptr);       // a submenu
    ~TrayMenu() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool ready() const { return m_ready; }

    Q_INVOKABLE void trigger(int row);
    Q_INVOKABLE TrayMenu *submenu(int row);

Q_SIGNALS:
    void readyChanged();
    void countChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void rebuild();
    void scheduleRebuild();
    bool m_pending = false;
    QPointer<DBusMenuImporter> m_importer;
    bool m_ownsImporter = false;
    QPointer<QMenu> m_menu;
    QList<QPointer<QAction>> m_actions;
    bool m_ready = false;
};

class TrayItem;

class Tray : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles { Key = Qt::UserRole + 1, AppId, Title, Status, IconName, IconSource, Tooltip, ItemIsMenu, HasMenu };
    static Tray *create(QQmlEngine *, QJSEngine *);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void activate(int row, int x, int y);
    Q_INVOKABLE void secondaryActivate(int row, int x, int y);
    Q_INVOKABLE void scroll(int row, int delta, bool horizontal);
    Q_INVOKABLE void contextMenu(int row, int x, int y);
    Q_INVOKABLE TrayMenu *menu(int row);

Q_SIGNALS:
    void countChanged();

private Q_SLOTS:
    void registered(const QString &spec);
    void unregistered(const QString &spec);

private:
    explicit Tray(QObject *parent = nullptr);
    void connectWatcher();
    void itemChanged(TrayItem *item);
    TrayItem *at(int row) const;
    QList<TrayItem *> m_items;
    QString m_hostName;
};
