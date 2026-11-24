#include "statewatcher.h"

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>

// Settings whose value lives in Hyprland's running config, besides those kept
// in the generated file (which carry hyprOption): read again when Hyprland
// reloads, whoever made it reload.
static const QStringList hyprPatterns = {
    "keyboard.*", "pointer.*", "trackpad.*", "desktop.*", "appearance.corners", "appearance.transparency",
    "appearance.animations", "display.laptopScreen", "display.mirror",
};
// Lists that come from Hyprland's config: the displays, shortcuts, and rules.
static const QStringList hyprLists = {"monitors", "shortcuts", "keybindings", "windowRules", "loginItems"};

QList<WatchRule> StateWatcher::rules(const Paths &p) {
    const QString state = p.state + "/hexciri";
    const QString config = p.config;
    return {
        // Do Not Disturb, from the shell's notification service.
        {state + "/notifications/quiet.json", false, {"notifications.doNotDisturb"}, {}},
        // Hexciri's on/off flags, and the Hyprland snippets its toggles copy in.
        {state + "/toggles", true,
         {"appearance.*", "desktop.gaps", "desktop.oneWindowRatio", "desktop.barVisible", "desktop.fullscreenDesktop",
          "lock.screensaver", "power.suspendInMenu", "notifications.crashReports", "display.laptopScreen",
          "display.mirror", "pointer.touchpad", "pointer.touchscreen"},
         {"crashMutes"}},
        {state + "/toggles/hypr", true,
         {"appearance.*", "desktop.*", "display.laptopScreen", "display.mirror", "pointer.touchpad",
          "pointer.touchscreen"},
         {}},
        {state + "/indicators", true, {"lock.stayAwake"}, {}},
        {state + "/powerprofiles", true, {"power.*"}, {"power"}},
        {state + "/current", true, {"appearance.theme"}, {"themes", "backgrounds"}},
        {state + "/workspace-layouts", true, {"desktop.layout"}, {}},
        {state + "/defaults", true, {"general.editor"}, {}},
        {state + "/settings/weather.json", false, {}, {"weather"}},
        // The shell's settings: idle times, the bar, the dock, the clock, plugins.
        {config + "/hexciri/shell.json", false,
         {"lock.screensaverAfter", "lock.lockAfter", "desktop.barPosition", "desktop.dockPosition",
          "desktop.dockAutohide", "appearance.barBackground", "bar.*", "general.clockFormat",
          "general.clockVerticalFormat"},
         {"bar", "dock", "plugins"}},
        {config + "/hexciri/shell.toml", false, {"appearance.textSize", "appearance.spacingScale", "bar.*"}, {}},
        {config + "/hexciri/extensions/hexciri-menu.jsonc", false, {"integration.*"},
         {"menu", "menuCustom", "menuSearch"}},
        {config + "/hexciri/defaults", true, {"general.agent", "general.dictation"}, {}},
        {config + "/hexciri/backgrounds", true, {}, {"backgrounds"}},
        {config + "/hexciri/themes", true, {}, {"themes"}},
        {config + "/hexciri/plugins", true, {}, {"plugins", "bar"}},
        {config + "/hexciri/hooks", true, {}, {"hooks"}},
        {config + "/xdg-terminals.list", false, {"general.terminal"}, {}},
        {config + "/mimeapps.list", false, {"general.browser"}, {"fileTypes"}},
        {config + "/hypr/hyprsunset.conf", false, {"display.night*"}, {}},
        {config + "/uwsm/env.d", true, {"general.screenshotDir", "general.screenrecordDir"}, {}},
        {config + "/mise/miserc.toml", false, {"software.miseDefaultTools"}, {}},
        {config + "/git/config", false, {"security.git*"}, {}},
        {p.home + "/.gitconfig", false, {"security.git*"}, {}},
    };
}

QStringList StateWatcher::expand(const QStringList &patterns, const QStringList &allIds) {
    QStringList out;
    for (const QString &pattern : patterns) {
        if (pattern.endsWith('*')) {
            const QString prefix = pattern.chopped(1);
            for (const QString &id : allIds)
                if (id.startsWith(prefix) && !out.contains(id))
                    out << id;
        } else if (allIds.contains(pattern) && !out.contains(pattern)) {
            out << pattern;
        }
    }
    return out;
}

void StateWatcher::resolve(const QList<WatchRule> &rules, const QStringList &allIds, const QString &path,
                           QStringList &ids, QStringList &lists) {
    const QString clean = QDir::cleanPath(path);
    for (const WatchRule &r : rules) {
        const QString rp = QDir::cleanPath(r.path);
        // A directory rule covers the directory and what is in it; a file
        // rule its file, which an editor or an atomic write may replace
        // through its directory.
        const bool hit = r.dir ? (clean == rp || QFileInfo(clean).absolutePath() == rp)
                               : clean == rp;
        if (!hit)
            continue;
        for (const QString &id : expand(r.ids, allIds))
            if (!ids.contains(id))
                ids << id;
        for (const QString &l : r.lists)
            if (!lists.contains(l))
                lists << l;
    }
}

void StateWatcher::resolveHyprEvent(const QString &line, const QStringList &allIds, const QStringList &hyprIds,
                                    QStringList &ids, QStringList &lists) {
    const QString event = line.section(">>", 0, 0);
    auto add = [&](const QStringList &more, const QStringList &moreLists) {
        for (const QString &id : more)
            if (!ids.contains(id))
                ids << id;
        for (const QString &l : moreLists)
            if (!lists.contains(l))
                lists << l;
    };
    if (event == "configreloaded") {
        add(hyprIds, hyprLists);
        add(expand(hyprPatterns, allIds), {});
    } else if (event == "monitoradded" || event == "monitoraddedv2" || event == "monitorremoved"
               || event == "monitorremovedv2") {
        add(expand({"display.laptopScreen", "display.mirror", "display.brightness"}, allIds), {"monitors"});
    }
}

void StateWatcher::resolvePulseEvent(const QString &line, const QStringList &allIds, QStringList &ids,
                                     QStringList &lists) {
    // "Event 'change' on sink #56". Streams (sink-input, source-output) come
    // and go with every sound an app plays, and change nothing shown here.
    static const QRegularExpression device(R"(on (sink|source|server|card) #)");
    if (!device.match(line).hasMatch())
        return;
    for (const QString &id : expand({"sound.*"}, allIds))
        if (!ids.contains(id))
            ids << id;
    for (const QString &l : {QStringLiteral("sinks"), QStringLiteral("sources")})
        if (!lists.contains(l))
            lists << l;
}

StateWatcher::StateWatcher(const Paths &paths, const QList<Setting> &settings, QObject *parent)
    : QObject(parent), m_rules(rules(paths)) {
    for (const Setting &s : settings) {
        m_allIds << s.id;
        if (!s.hyprOption.isEmpty())
            m_hyprIds << s.id;
    }
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, [this] {
        QStringList ids(m_ids.begin(), m_ids.end()), lists(m_lists.begin(), m_lists.end());
        m_ids.clear();
        m_lists.clear();
        ids.sort();
        lists.sort();
        if (!ids.isEmpty() || !lists.isEmpty())
            emit changed(ids, lists);
    });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &StateWatcher::onPath);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &StateWatcher::onPath);
}

StateWatcher::~StateWatcher() {
    m_stopping = true;
    if (m_pulse.state() != QProcess::NotRunning) {
        m_pulse.kill();
        m_pulse.waitForFinished(1000);
    }
}

void StateWatcher::start(bool events) {
    rewatch();
    if (!events)
        return;
    connectHyprland();
    startPulse();
}

QString StateWatcher::stamp(const QString &path) const {
    const QFileInfo info(path);
    if (!info.exists())
        return {};
    return QString::number(info.size()) + ":" + QString::number(info.lastModified().toMSecsSinceEpoch());
}

// Watches each rule's file or directory, the files inside a directory (whose
// contents changing says nothing to the directory), and a file's directory,
// so a file that is replaced or appears later is still seen.
void StateWatcher::rewatch() {
    QStringList wanted;
    for (const WatchRule &r : m_rules) {
        const QFileInfo info(r.path);
        if (r.dir) {
            if (!info.isDir())
                continue;
            wanted << r.path;
            for (const QFileInfo &f : QDir(r.path).entryInfoList(QDir::Files | QDir::NoDotAndDotDot))
                wanted << f.absoluteFilePath();
        } else {
            if (info.isFile())
                wanted << r.path;
            if (QFileInfo(info.absolutePath()).isDir())
                wanted << info.absolutePath();
            if (!m_stamps.contains(r.path))
                m_stamps.insert(r.path, stamp(r.path));
        }
    }
    wanted.removeDuplicates();
    const QStringList watched = m_watcher.files() + m_watcher.directories();
    QStringList add;
    for (const QString &w : wanted)
        if (!watched.contains(w))
            add << w;
    if (!add.isEmpty())
        m_watcher.addPaths(add);
}

void StateWatcher::onPath(const QString &path) {
    QStringList ids, lists;
    resolve(m_rules, m_allIds, path, ids, lists);
    // A directory that holds a watched file: check whether that file changed,
    // rather than taking every change beside it for one.
    for (const WatchRule &r : m_rules) {
        if (r.dir || QFileInfo(r.path).absolutePath() != QDir::cleanPath(path))
            continue;
        const QString now = stamp(r.path);
        if (now == m_stamps.value(r.path))
            continue;
        m_stamps.insert(r.path, now);
        resolve(m_rules, m_allIds, r.path, ids, lists);
    }
    // A file rule seen through fileChanged: remember it, so its directory's
    // next event doesn't count it twice.
    if (m_stamps.contains(path))
        m_stamps.insert(path, stamp(path));
    rewatch();
    queue(ids, lists);
}

void StateWatcher::queue(const QStringList &ids, const QStringList &lists) {
    if (ids.isEmpty() && lists.isEmpty())
        return;
    for (const QString &id : ids)
        m_ids.insert(id);
    for (const QString &l : lists)
        m_lists.insert(l);
    m_debounce.start();
}

// Hyprland says what happens on its second socket, a line per event.
void StateWatcher::connectHyprland() {
    const QString signature = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (signature.isEmpty())
        return;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    const QString socket = runtime + "/hypr/" + signature + "/.socket2.sock";
    m_hyprRetry.setSingleShot(true);
    connect(&m_hyprRetry, &QTimer::timeout, this, [this, socket] { m_hypr.connectToServer(socket); });
    connect(&m_hypr, &QLocalSocket::readyRead, this, [this] {
        m_hyprBuffer += m_hypr.readAll();
        QStringList ids, lists;
        int at;
        while ((at = m_hyprBuffer.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(m_hyprBuffer.left(at));
            m_hyprBuffer.remove(0, at + 1);
            resolveHyprEvent(line, m_allIds, m_hyprIds, ids, lists);
        }
        queue(ids, lists);
    });
    // Hyprland restarting, or not up yet: try again, a little slower each time.
    auto retry = [this] {
        if (m_stopping)
            return;
        m_hyprBuffer.clear();
        m_hyprRetry.setInterval(qMin(30000, qMax(1000, m_hyprRetry.interval() * 2)));
        m_hyprRetry.start();
    };
    connect(&m_hypr, &QLocalSocket::disconnected, this, retry);
    connect(&m_hypr, &QLocalSocket::errorOccurred, this, retry);
    connect(&m_hypr, &QLocalSocket::connected, this, [this] { m_hyprRetry.setInterval(500); });
    m_hypr.connectToServer(socket);
}

// Volume, mute, and the default devices change from keys and the shell's
// panel; PulseAudio (PipeWire's) says so on `pactl subscribe`.
void StateWatcher::startPulse() {
    const QString pactl = QStandardPaths::findExecutable("pactl");
    if (pactl.isEmpty())
        return;
    m_pulseRetry.setSingleShot(true);
    m_pulseRetry.setInterval(5000);
    connect(&m_pulseRetry, &QTimer::timeout, this, [this, pactl] { m_pulse.start(pactl, {"subscribe"}); });
    connect(&m_pulse, &QProcess::readyReadStandardOutput, this, [this] {
        QStringList ids, lists;
        while (m_pulse.canReadLine())
            resolvePulseEvent(QString::fromUtf8(m_pulse.readLine()), m_allIds, ids, lists);
        queue(ids, lists);
    });
    connect(&m_pulse, &QProcess::finished, this, [this] {
        if (!m_stopping)
            m_pulseRetry.start();
    });
    m_pulse.start(pactl, {"subscribe"});
}
