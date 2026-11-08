#include "tray.h"

#include <QAction>
#include <QBuffer>
#include <QCoreApplication>
#include <QDBusArgument>
#include <QDebug>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QEvent>
#include <QIcon>
#include <QJSEngine>
#include <QMenu>
#include <QQmlEngine>
#include <QTimer>
#include <QtEndian>
#include <dbusmenuimporter.h>

namespace {
const bool kDebug = qEnvironmentVariableIsSet("ATOM_TRAY_DEBUG");
const QString kWatcher = QStringLiteral("org.kde.StatusNotifierWatcher");
const QString kWatcherPath = QStringLiteral("/StatusNotifierWatcher");
const QString kKdeItem = QStringLiteral("org.kde.StatusNotifierItem");
const QString kFdoItem = QStringLiteral("org.freedesktop.StatusNotifierItem");

// a(iiay): the icon in several sizes, ARGB32 in network byte order. The one nearest 64 px (not under 22).
QImage readPixmaps(const QDBusArgument &arg)
{
    QImage best;
    arg.beginArray();
    while (!arg.atEnd()) {
        int w = 0, h = 0;
        QByteArray bytes;
        arg.beginStructure();
        arg >> w >> h >> bytes;
        arg.endStructure();
        if (w <= 0 || h <= 0 || bytes.size() < w * h * 4) {
            continue;
        }
        const auto score = [](int s) { return s >= 22 ? std::abs(s - 64) : 1000 + (64 - s); };
        if (!best.isNull() && score(w) >= score(best.width())) {
            continue;
        }
        QImage img(w, h, QImage::Format_ARGB32);
        const quint32 *src = reinterpret_cast<const quint32 *>(bytes.constData());
        for (int y = 0; y < h; ++y) {
            quint32 *line = reinterpret_cast<quint32 *>(img.scanLine(y));
            for (int x = 0; x < w; ++x) {
                line[x] = qFromBigEndian(src[y * w + x]);
            }
        }
        best = img;
    }
    arg.endArray();
    return best;
}

QImage pixmapsOf(const QVariant &v)
{
    return v.canConvert<QDBusArgument>() ? readPixmaps(qvariant_cast<QDBusArgument>(v)) : QImage();
}

QString dataUrl(const QImage &img)
{
    if (img.isNull()) {
        return {};
    }
    QByteArray png;
    QBuffer buf(&png);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(png.toBase64());
}

// (s icon, a(iiay) pixmaps, s title, s text)
QString tooltipOf(const QVariant &v)
{
    if (!v.canConvert<QDBusArgument>()) {
        return {};
    }
    const QDBusArgument arg = qvariant_cast<QDBusArgument>(v);
    QString icon, title, text;
    arg.beginStructure();
    arg >> icon;
    readPixmaps(arg);
    arg >> title >> text;
    arg.endStructure();
    if (!text.isEmpty() && text != title) {
        return title.isEmpty() ? text : title + QLatin1Char('\n') + text;
    }
    return title;
}
}

// ---------------------------------------------------------------------------------------------- an item
class TrayItem : public QObject
{
    Q_OBJECT
public:
    TrayItem(const QString &spec, QObject *parent)
        : QObject(parent)
        , spec(spec)
    {
        const int slash = spec.indexOf(QLatin1Char('/'));
        service = slash < 0 ? spec : spec.left(slash);
        path = slash < 0 ? QStringLiteral("/StatusNotifierItem") : spec.mid(slash);
        debounce.setSingleShot(true);
        debounce.setInterval(30);
        connect(&debounce, &QTimer::timeout, this, &TrayItem::fetch);
        listen();
        fetch();
    }

    QString spec, service, path, iface = kKdeItem;
    QString id, title, status = QStringLiteral("Active"), iconName, attentionName, iconThemePath, tooltip, menuPath;
    QString iconUrl, attentionUrl;
    bool itemIsMenu = false;
    bool loaded = false;
    std::function<void(TrayItem *)> onChange;

    QString shownName() const { return status == QLatin1String("NeedsAttention") && !attentionName.isEmpty() ? attentionName : iconName; }
    QString shownUrl() const { return status == QLatin1String("NeedsAttention") && !attentionUrl.isEmpty() ? attentionUrl : iconUrl; }

public Q_SLOTS:
    void changed() { debounce.start(); }

private:
    QTimer debounce;

    void listen()
    {
        auto bus = QDBusConnection::sessionBus();
        for (const char *sig : {"NewTitle", "NewIcon", "NewAttentionIcon", "NewOverlayIcon", "NewToolTip", "NewStatus", "NewMenu"}) {
            bus.connect(service, path, iface, QLatin1String(sig), this, SLOT(changed()));
        }
    }
    void fetch()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
        m << iface;
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m, 5000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            QDBusPendingReply<QVariantMap> r = *w;
            if (r.isError()) {
                if (iface == kKdeItem && !loaded) {     // the freedesktop name of the same interface
                    iface = kFdoItem;
                    listen();
                    fetch();
                }
                return;
            }
            const QVariantMap p = r.value();
            id = p.value(QStringLiteral("Id")).toString();
            title = p.value(QStringLiteral("Title")).toString();
            status = p.value(QStringLiteral("Status"), QStringLiteral("Active")).toString();
            iconName = p.value(QStringLiteral("IconName")).toString();
            attentionName = p.value(QStringLiteral("AttentionIconName")).toString();
            iconThemePath = p.value(QStringLiteral("IconThemePath")).toString();
            itemIsMenu = p.value(QStringLiteral("ItemIsMenu")).toBool();
            menuPath = p.value(QStringLiteral("Menu")).value<QDBusObjectPath>().path();
            tooltip = tooltipOf(p.value(QStringLiteral("ToolTip")));
            // a name in a private icon folder: load it from there (QML's theme lookup can't see it)
            QImage img = pixmapsOf(p.value(QStringLiteral("IconPixmap")));
            if (!iconName.isEmpty() && !iconThemePath.isEmpty() && img.isNull()) {
                QIcon::setThemeSearchPaths(QIcon::themeSearchPaths() << iconThemePath);
                const QIcon icon = QIcon::fromTheme(iconName);
                if (!icon.isNull()) {
                    img = icon.pixmap(64).toImage();
                }
            }
            iconUrl = !iconName.isEmpty() && iconThemePath.isEmpty() ? QString() : dataUrl(img);
            const QImage att = pixmapsOf(p.value(QStringLiteral("AttentionIconPixmap")));
            attentionUrl = dataUrl(att);
            loaded = true;
            if (onChange) {
                onChange(this);
            }
        });
    }
};

// ---------------------------------------------------------------------------------------------- the model
Tray::Tray(QObject *parent)
    : QAbstractListModel(parent)
{
    m_hostName = QStringLiteral("org.kde.StatusNotifierHost-%1-atom").arg(QCoreApplication::applicationPid());
    QDBusConnection::sessionBus().registerService(m_hostName);
    auto *w = new QDBusServiceWatcher(kWatcher, QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForRegistration, this);
    connect(w, &QDBusServiceWatcher::serviceRegistered, this, &Tray::connectWatcher);    // kded came back
    connectWatcher();
}

Tray *Tray::create(QQmlEngine *, QJSEngine *)
{
    static Tray *tray = new Tray;       // one host for the whole process, whatever engine asks
    QJSEngine::setObjectOwnership(tray, QJSEngine::CppOwnership);
    return tray;
}

void Tray::connectWatcher()
{
    auto bus = QDBusConnection::sessionBus();
    bus.disconnect(kWatcher, kWatcherPath, kWatcher, QStringLiteral("StatusNotifierItemRegistered"), this, SLOT(registered(QString)));
    bus.disconnect(kWatcher, kWatcherPath, kWatcher, QStringLiteral("StatusNotifierItemUnregistered"), this, SLOT(unregistered(QString)));
    bus.connect(kWatcher, kWatcherPath, kWatcher, QStringLiteral("StatusNotifierItemRegistered"), this, SLOT(registered(QString)));
    bus.connect(kWatcher, kWatcherPath, kWatcher, QStringLiteral("StatusNotifierItemUnregistered"), this, SLOT(unregistered(QString)));
    QDBusMessage reg = QDBusMessage::createMethodCall(kWatcher, kWatcherPath, kWatcher, QStringLiteral("RegisterStatusNotifierHost"));
    reg << m_hostName;
    bus.asyncCall(reg);
    QDBusMessage get = QDBusMessage::createMethodCall(kWatcher, kWatcherPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    get << kWatcher << QStringLiteral("RegisteredStatusNotifierItems");
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(get), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusVariant> r = *w;
        if (kDebug) qWarning() << "atom tray: watcher items" << r.isError() << r.error().message() << (r.isError() ? QVariant() : r.value().variant());
        if (r.isError()) {
            return;
        }
        const QVariant v = r.value().variant();     // "as": a raw argument or already a list
        const QStringList specs = v.canConvert<QDBusArgument>() ? qdbus_cast<QStringList>(qvariant_cast<QDBusArgument>(v))
                                                                : v.toStringList();
        for (const QString &spec : specs) {
            registered(spec);
        }
    });
}

void Tray::registered(const QString &spec)
{
    if (kDebug) qWarning() << "atom tray: item" << spec;
    for (TrayItem *i : std::as_const(m_items)) {
        if (i->spec == spec) {
            return;
        }
    }
    auto *item = new TrayItem(spec, this);
    item->onChange = [this](TrayItem *i) { itemChanged(i); };
    beginInsertRows({}, m_items.size(), m_items.size());
    m_items.append(item);
    endInsertRows();
    Q_EMIT countChanged();
}

void Tray::unregistered(const QString &spec)
{
    for (int r = 0; r < m_items.size(); ++r) {
        if (m_items[r]->spec == spec) {
            beginRemoveRows({}, r, r);
            m_items.takeAt(r)->deleteLater();
            endRemoveRows();
            Q_EMIT countChanged();
            return;
        }
    }
}

void Tray::itemChanged(TrayItem *item)
{
    const int r = m_items.indexOf(item);
    if (r >= 0) {
        Q_EMIT dataChanged(index(r), index(r));
    }
}

TrayItem *Tray::at(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items[row] : nullptr;
}

int Tray::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant Tray::data(const QModelIndex &index, int role) const
{
    const TrayItem *i = at(index.row());
    if (!i) {
        return {};
    }
    switch (role) {
    case Key: return i->spec;
    case AppId: return i->id;
    case Title: return i->title.isEmpty() ? i->id : i->title;
    case Status: return i->loaded ? i->status : QStringLiteral("Passive");     // hidden until it has answered
    case IconName: return i->shownName();
    case IconSource: return i->shownUrl();
    case Tooltip: return i->tooltip;
    case ItemIsMenu: return i->itemIsMenu;
    case HasMenu: return !i->menuPath.isEmpty() && i->menuPath != QLatin1String("/");
    }
    return {};
}

QHash<int, QByteArray> Tray::roleNames() const
{
    return {{Key, "key"}, {AppId, "appId"}, {Title, "title"}, {Status, "status"}, {IconName, "iconName"},
            {IconSource, "iconSource"}, {Tooltip, "tooltip"}, {ItemIsMenu, "itemIsMenu"}, {HasMenu, "hasMenu"}};
}

static void callItem(TrayItem *i, const QString &method, const QVariantList &args)
{
    if (!i) {
        return;
    }
    QDBusMessage m = QDBusMessage::createMethodCall(i->service, i->path, i->iface, method);
    m.setArguments(args);
    QDBusConnection::sessionBus().asyncCall(m);
}

void Tray::activate(int row, int x, int y) { callItem(at(row), QStringLiteral("Activate"), {x, y}); }
void Tray::secondaryActivate(int row, int x, int y) { callItem(at(row), QStringLiteral("SecondaryActivate"), {x, y}); }
void Tray::contextMenu(int row, int x, int y) { callItem(at(row), QStringLiteral("ContextMenu"), {x, y}); }
void Tray::scroll(int row, int delta, bool horizontal)
{
    callItem(at(row), QStringLiteral("Scroll"), {delta, horizontal ? QStringLiteral("horizontal") : QStringLiteral("vertical")});
}

TrayMenu *Tray::menu(int row)
{
    TrayItem *i = at(row);
    if (!i || i->menuPath.isEmpty() || i->menuPath == QLatin1String("/")) {
        return nullptr;
    }
    auto *m = new TrayMenu(i->service, i->menuPath);
    QJSEngine::setObjectOwnership(m, QJSEngine::JavaScriptOwnership);
    return m;
}

// ---------------------------------------------------------------------------------------------- menus
TrayMenu::TrayMenu(const QString &service, const QString &path, QObject *parent)
    : QAbstractListModel(parent)
    , m_importer(new DBusMenuImporter(service, path, ASYNCHRONOUS, this))
    , m_ownsImporter(true)
{
    m_menu = m_importer->menu();
    if (m_menu) {
        m_menu->installEventFilter(this);
    }
    connect(m_importer, &DBusMenuImporter::menuUpdated, this, &TrayMenu::scheduleRebuild);
    m_importer->updateMenu();
}

TrayMenu::TrayMenu(DBusMenuImporter *importer, QMenu *menu, QObject *parent)
    : QAbstractListModel(parent)
    , m_importer(importer)
    , m_menu(menu)
{
    if (m_menu) {
        m_menu->installEventFilter(this);
        connect(m_importer, &DBusMenuImporter::menuUpdated, this, &TrayMenu::scheduleRebuild);
        QMetaObject::invokeMethod(m_menu, "aboutToShow");        // the importer fetches a submenu when it's shown
        rebuild();
    }
}

TrayMenu::~TrayMenu()
{
    if (m_menu) {
        m_menu->removeEventFilter(this);
    }
}

bool TrayMenu::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_menu && (event->type() == QEvent::ActionAdded || event->type() == QEvent::ActionRemoved
                              || event->type() == QEvent::ActionChanged)) {
        scheduleRebuild();
    }
    return false;
}

void TrayMenu::scheduleRebuild()
{
    if (m_pending) {
        return;
    }
    m_pending = true;
    QTimer::singleShot(20, this, [this] { m_pending = false; rebuild(); });
}

void TrayMenu::rebuild()
{
    if (!m_menu) {
        m_menu = m_importer ? m_importer->menu() : nullptr;
        if (m_menu) {
            m_menu->installEventFilter(this);
        }
    }
    beginResetModel();
    m_actions.clear();
    if (m_menu) {
        for (QAction *a : m_menu->actions()) {
            if (a->isVisible()) {
                m_actions.append(a);
            }
        }
    }
    endResetModel();
    Q_EMIT countChanged();
    if (!m_ready && !m_actions.isEmpty()) {
        m_ready = true;
        Q_EMIT readyChanged();
    }
}

int TrayMenu::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_actions.size();
}

QVariant TrayMenu::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_actions.size() || !m_actions[index.row()]) {
        return {};
    }
    const QAction *a = m_actions[index.row()];
    switch (role) {
    case Text: return QString(a->text()).remove(QLatin1Char('&'));
    case IconName: return a->icon().name();
    case IconSource: return a->icon().isNull() || !a->icon().name().isEmpty() ? QString() : dataUrl(a->icon().pixmap(32).toImage());
    case Enabled: return a->isEnabled();
    case Checkable: return a->isCheckable();
    case Checked: return a->isChecked();
    case Separator: return a->isSeparator();
    case HasSubmenu: return a->menu() != nullptr;
    }
    return {};
}

QHash<int, QByteArray> TrayMenu::roleNames() const
{
    return {{Text, "text"}, {IconName, "iconName"}, {IconSource, "iconSource"}, {Enabled, "enabled"},
            {Checkable, "checkable"}, {Checked, "checked"}, {Separator, "separator"}, {HasSubmenu, "hasSubmenu"}};
}

void TrayMenu::trigger(int row)
{
    if (row >= 0 && row < m_actions.size() && m_actions[row]) {
        m_actions[row]->trigger();          // the importer sends the click to the app
    }
}

TrayMenu *TrayMenu::submenu(int row)
{
    if (row < 0 || row >= m_actions.size() || !m_actions[row] || !m_actions[row]->menu()) {
        return nullptr;
    }
    auto *m = new TrayMenu(m_importer, m_actions[row]->menu());
    QJSEngine::setObjectOwnership(m, QJSEngine::JavaScriptOwnership);
    return m;
}

#include "tray.moc"
