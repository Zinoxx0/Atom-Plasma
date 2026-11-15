#pragma once
// Says when one file changes: written in place, replaced by a rename (how the rice writes its JSON),
// created or deleted. Every FileWatch in the process shares ONE QFileSystemWatcher (one inotify instance,
// no thread), watching each file and its folder; a change is reported only when the file's identity or
// contents changed (inode, size, modification time), so a busy folder costs a stat per event, not a re-listing.
// A folder that doesn't exist yet is waited for on its nearest existing parent.
//
//   FileWatch { path: "/home/me/.cache/claude-usage.json"; onChanged: reread() }
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class FileWatch : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)

public:
    explicit FileWatch(QObject *parent = nullptr);
    ~FileWatch() override;

    QString path() const { return m_path; }
    void setPath(const QString &path);

    // (the hub's)
    void check();
    QString folder() const { return m_folder; }

Q_SIGNALS:
    void pathChanged();
    void changed();

private:
    QString m_path;
    QString m_folder;
    QByteArray m_seen;              // the last signature (inode, size, mtime; empty: no file)
};
