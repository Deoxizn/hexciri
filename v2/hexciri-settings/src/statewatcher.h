#pragma once

#include <QDateTime>
#include <QFileSystemWatcher>
#include <QHash>
#include <QLocalSocket>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QStringList>
#include <QTimer>

#include "store.h"

// Where a setting's value lives on disk, so a change made anywhere else (a
// keybinding, the Hexciri menu, a terminal) shows in the window at once.
// `ids` are setting ids, or a prefix ending in '*'; `lists` are the lists to
// load again when they are already showing.
struct WatchRule {
    QString path;
    bool dir = false;
    QStringList ids;
    QStringList lists;
};

// Watches the files and directories behind the settings, Hyprland's event
// socket, and PulseAudio's, and says which settings and lists to read again.
// Changes arriving together are said once.
class StateWatcher : public QObject {
    Q_OBJECT
public:
    StateWatcher(const Paths &paths, const QList<Setting> &settings, QObject *parent = nullptr);
    ~StateWatcher() override;

    // Starts watching files, and with `events`, Hyprland's and PulseAudio's
    // event streams too.
    void start(bool events);

    static QList<WatchRule> rules(const Paths &paths);
    // What a change to `path` (a file, or a directory whose entries changed)
    // asks to read again.
    static void resolve(const QList<WatchRule> &rules, const QStringList &allIds, const QString &path,
                        QStringList &ids, QStringList &lists);
    // The same for one line from Hyprland's event socket ("configreloaded>>").
    static void resolveHyprEvent(const QString &line, const QStringList &allIds, const QStringList &hyprIds,
                                 QStringList &ids, QStringList &lists);
    // The same for one line of `pactl subscribe`.
    static void resolvePulseEvent(const QString &line, const QStringList &allIds, QStringList &ids, QStringList &lists);
    static QStringList expand(const QStringList &patterns, const QStringList &allIds);

signals:
    void changed(const QStringList &ids, const QStringList &lists);

private:
    void rewatch();
    void onPath(const QString &path);
    void queue(const QStringList &ids, const QStringList &lists);
    void connectHyprland();
    void startPulse();
    QString stamp(const QString &path) const;

    QList<WatchRule> m_rules;
    QStringList m_allIds, m_hyprIds;
    QFileSystemWatcher m_watcher;
    // A file's size and time as last seen, so a change beside it in the same
    // directory doesn't count as a change to it.
    QHash<QString, QString> m_stamps;
    QTimer m_debounce;
    QSet<QString> m_ids, m_lists;
    QLocalSocket m_hypr;
    QTimer m_hyprRetry;
    QByteArray m_hyprBuffer;
    QProcess m_pulse;
    QTimer m_pulseRetry;
    bool m_stopping = false;
};
