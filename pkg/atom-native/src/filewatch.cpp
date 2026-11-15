#include "filewatch.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QSet>

#include <sys/stat.h>

namespace
{

// what the file is right now: inode, size and modification time ("" when there's no file)
QByteArray signature(const QString &path)
{
    struct stat st;
    if (path.isEmpty() || ::stat(QFile::encodeName(path).constData(), &st) != 0) {
        return {};
    }
    return QByteArray::number(qulonglong(st.st_ino)) + ':' + QByteArray::number(qlonglong(st.st_size)) + ':'
        + QByteArray::number(qlonglong(st.st_mtim.tv_sec)) + '.' + QByteArray::number(qlonglong(st.st_mtim.tv_nsec));
}

// the folder itself, or while it doesn't exist, its nearest parent that does (its creation shows there)
QString existingFolder(QString dir)
{
    while (!dir.isEmpty() && !QFileInfo(dir).isDir()) {
        const QString up = QFileInfo(dir).absolutePath();
        if (up == dir) {
            return {};
        }
        dir = up;
    }
    return dir;
}

// One watcher for the whole process (it lives as long as the process: no engine owns it)
class WatchHub : public QObject
{
public:
    static WatchHub *instance()
    {
        static WatchHub *hub = new WatchHub;
        return hub;
    }

    void add(FileWatch *w)
    {
        m_watches.insert(w);
        refresh();
    }
    void remove(FileWatch *w)
    {
        if (m_watches.remove(w)) {
            refresh();
        }
    }

private:
    WatchHub()
    {
        connect(&m_fsw, &QFileSystemWatcher::directoryChanged, this, &WatchHub::changedAt);
        connect(&m_fsw, &QFileSystemWatcher::fileChanged, this, &WatchHub::changedAt);
    }

    void changedAt(const QString &path)
    {
        const QString under = path.endsWith(QLatin1Char('/')) ? path : path + QLatin1Char('/');
        // (a copy: a changed() handler may add or remove watches)
        const auto watches = m_watches;
        for (FileWatch *w : watches) {
            if (m_watches.contains(w) && (w->path() == path || w->path().startsWith(under))) {
                w->check();
            }
        }
        refresh();          // a file replaced by a rename lost its watch; a folder may have appeared
    }

    // watch exactly what the watches need: each file that exists, and each one's folder (or its nearest
    // existing parent)
    void refresh()
    {
        QSet<QString> want;
        for (FileWatch *w : std::as_const(m_watches)) {
            if (QFileInfo::exists(w->path())) {
                want.insert(w->path());
            }
            const QString dir = existingFolder(w->folder());
            if (!dir.isEmpty()) {
                want.insert(dir);
            }
        }
        QSet<QString> have;
        for (const QString &p : m_fsw.files()) {
            have.insert(p);
        }
        for (const QString &p : m_fsw.directories()) {
            have.insert(p);
        }
        const QSet<QString> gone = have - want;
        const QSet<QString> added = want - have;
        if (!gone.isEmpty()) {
            m_fsw.removePaths(QStringList(gone.cbegin(), gone.cend()));
        }
        if (!added.isEmpty()) {
            m_fsw.addPaths(QStringList(added.cbegin(), added.cend()));
        }
    }

    QFileSystemWatcher m_fsw;
    QSet<FileWatch *> m_watches;
};

} // namespace

FileWatch::FileWatch(QObject *parent)
    : QObject(parent)
{
}

FileWatch::~FileWatch()
{
    WatchHub::instance()->remove(this);
}

void FileWatch::setPath(const QString &path)
{
    if (path == m_path) {
        return;
    }
    m_path = path.isEmpty() ? QString() : QDir::cleanPath(path);
    m_folder = m_path.isEmpty() ? QString() : QFileInfo(m_path).absolutePath();
    m_seen = signature(m_path);         // (what's there now was read by whoever set the path)
    if (m_path.isEmpty()) {
        WatchHub::instance()->remove(this);
    } else {
        WatchHub::instance()->add(this);
    }
    Q_EMIT pathChanged();
}

void FileWatch::check()
{
    const QByteArray now = signature(m_path);
    if (now != m_seen) {
        m_seen = now;
        Q_EMIT changed();
    }
}
