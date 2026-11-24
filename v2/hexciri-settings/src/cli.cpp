#include "version.h"
#include "cli.h"

#include "store.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTextStream>

static QTextStream &out() {
    static QTextStream s(stdout);
    return s;
}

static QTextStream &err() {
    static QTextStream s(stderr);
    return s;
}

static const char *usage =
    "Usage: hexciri-settings [open [pane[/page]]]\n"
    "       hexciri-settings list [pane] [--json]\n"
    "       hexciri-settings get <id> [--json]\n"
    "       hexciri-settings set <id> <value> [--json]\n"
    "       hexciri-settings reset <id> [--json]\n"
    "       hexciri-settings data <list> [--json]\n"
    "       hexciri-settings act <action> [args...]   (an argument starting with { is JSON)\n"
    "       hexciri-settings export <file>  |  hexciri-settings import <file>\n"
    "       hexciri-settings sync [status|check|upload [--force]|apply|connect <url>|create [name]|disconnect]\n"
    "       hexciri-settings skill install [--dir <path>]\n"
    "       hexciri-settings icon [--print --color <#rrggbb> [--rounding <px>]]\n"
    "\n"
    "Panes: wifi bluetooth vpn general notifications power storage software plugins\n"
    "       appearance wallpaper fonts desktop bar menu displays sound keyboard\n"
    "       pointer printers lock security firewall\n";

bool isCliCommand(const QStringList &args) {
    const QString command = args.value(1);
    return QStringList{"list", "get", "set", "reset", "data", "act", "export", "import", "sync", "icon", "skill", "help", "--help", "-h", "--version"}.contains(command);
}

static QString plain(const QVariant &v) {
    if (v.typeId() == QMetaType::Bool)
        return v.toBool() ? "true" : "false";
    if (v.typeId() == QMetaType::QVariantList || v.typeId() == QMetaType::QVariantMap)
        return QString::fromUtf8(QJsonDocument::fromVariant(v).toJson(QJsonDocument::Compact));
    return v.toString();
}

static int fail(bool json, const QString &message) {
    if (json)
        out() << QJsonDocument(QJsonObject{{"ok", false}, {"error", message}}).toJson(QJsonDocument::Compact) << "\n";
    err() << "hexciri-settings: " << message << "\n";
    return 1;
}

static QJsonObject describe(const Setting &s, const QVariant &value) {
    QJsonObject o{{"id", s.id}, {"pane", s.pane}, {"type", s.type}, {"label", s.label},
                  {"value", QJsonValue::fromVariant(value)}};
    if (s.max > s.min) {
        o.insert("min", s.min);
        o.insert("max", s.max);
    }
    if (!s.choices.isEmpty())
        o.insert("choices", QJsonArray::fromVariantList(s.choices));
    if (!s.choicesList.isEmpty())
        o.insert("choicesFrom", "hexciri-settings data " + s.choicesList);
    return o;
}

static const char *skill = R"(---
name: hexciri-settings
description: Read and change Hexciri desktop settings (Wi-Fi, sound, displays, keyboard, mouse and trackpad, appearance, theme, lock screen, default apps) through the hexciri-settings CLI instead of editing config files. Use when asked to change a desktop setting on Hexciri.
---

# Hexciri settings

`hexciri-settings` is the Settings app's command line. Every setting the window
shows can be read and changed here, with the same safety checks: Hyprland
changes go to one generated file and are rolled back if Hyprland rejects them.

```sh
hexciri-settings list --json               # every setting, its type, range, choices, value
hexciri-settings list keyboard --json      # one pane
hexciri-settings get keyboard.repeatRate
hexciri-settings set keyboard.repeatRate 45 --json
hexciri-settings data monitors --json      # live data: wifi, bluetooth, sinks, monitors, themes, ...
hexciri-settings act shortcut.add "SUPER + E" Files launch org.gnome.Nautilus.desktop
hexciri-settings act autostart.add syncthing Syncthing
hexciri-settings act rule.add '{"class":"^(mpv)$","float":true,"workspace":"3"}'
hexciri-settings export ~/Documents        # import <file> applies one
```

- Commands exit 0 on success and 1 on failure, with the reason on stderr.
- Values: booleans as `true`/`false`, numbers as numbers, choices exactly as
  listed. `choicesFrom` names the `data` list that holds a setting's choices.
- Run `list` first rather than guessing ids.
- Some changes ask for a password through the desktop's polkit prompt (time
  zone, computer name); tell the user to watch for it.
- `hexciri-settings open <pane>` opens the window on a pane for the user, and
  `hexciri-settings open <pane>/<page>` on a page inside one: general/about,
  general/update, general/language, general/datetime, general/loginitems,
  general/webapps, general/apps, general/troubleshooting,
  general/settingsapp, general/hooks, appearance/themes, desktop/rules, lock/bootscreen,
  keyboard/shortcuts, general/sync. If Settings is open, that window switches to it.
- `hexciri-settings sync status` shows whether Sync is connected to a repository
  and whether it has newer settings; `sync upload` sends this computer's
  settings and apps there, and `sync apply` brings this computer to match
  it (it only adds apps, and opens a terminal to install them). Ask the user
  before applying.
)";

static int installSkill(const QStringList &args) {
    QString dir = QDir::homePath() + "/.claude/skills/hexciri-settings";
    const int at = args.indexOf("--dir");
    if (at >= 0 && at + 1 < args.size())
        dir = args.value(at + 1);
    QDir().mkpath(dir);
    QSaveFile file(dir + "/SKILL.md");
    const QByteArray data(skill);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
        err() << "hexciri-settings: could not write " << file.fileName() << "\n";
        return 1;
    }
    out() << "Installed " << dir << "/SKILL.md\n";
    return 0;
}

int runCli(const QStringList &all, Store &store) {
    QStringList args = all.mid(1);
    const bool json = args.removeAll("--json") > 0;
    QString command = args.value(0);

    if (command == "help" || command == "--help" || command == "-h") {
        out() << usage;
        return 0;
    }
    if (command == "--version") {
        out() << "hexciri-settings " HEXCIRI_SETTINGS_VERSION "\n";
        return 0;
    }
    if (command == "icon") {
        // --print draws a fixed-color icon to stdout (the package's default);
        // otherwise the icon is drawn in the current theme's colors.
        if (args.contains("--print")) {
            const QString color = args.value(args.indexOf("--color") + 1, "#a9b1d6");
            const double rounding = args.contains("--rounding") ? args.value(args.indexOf("--rounding") + 1).toDouble() : 0;
            out() << Store::iconSvg(color, rounding);
            return 0;
        }
        const QString error = store.writeThemedIcon();
        if (!error.isEmpty())
            return fail(json, error);
        out() << store.iconPath() << "\n";
        return 0;
    }
    if (command == "skill") {
        if (args.value(1) != "install")
            return fail(false, "usage: hexciri-settings skill install [--dir <path>]");
        return installSkill(args);
    }

    if (command == "list") {
        const QString pane = args.value(1);
        QJsonArray rows;
        for (const Setting &s : store.settings()) {
            if (!pane.isEmpty() && s.pane != pane)
                continue;
            const QVariant value = store.read(s.id);
            rows << describe(s, value);
            if (!json)
                out() << s.id.leftJustified(32) << " " << plain(value) << "\n";
        }
        if (rows.isEmpty())
            return fail(json, "no settings in pane " + pane);
        if (json)
            out() << QJsonDocument(rows).toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    if (command == "reset") {
        const QString id = args.value(1);
        const Setting *s = store.setting(id);
        if (!s)
            return fail(json, "unknown setting " + id + " (see hexciri-settings list)");
        if (s->hyprOption.isEmpty())
            return fail(json, id + " is not kept by Settings, so there is nothing to reset; use set");
        const QString error = store.resetHypr(s->hyprOption);
        if (!error.isEmpty())
            return fail(json, error);
        command = "get";
    }

    if (command == "get" || command == "set") {
        const QString id = args.value(1);
        const Setting *s = store.setting(id);
        if (!s)
            return fail(json, "unknown setting " + id + " (see hexciri-settings list)");
        if (command == "set") {
            if (args.size() < 3)
                return fail(json, "usage: hexciri-settings set <id> <value>");
            const QString error = store.write(id, args.value(2));
            if (!error.isEmpty())
                return fail(json, error);
        }
        const QVariant value = store.read(id);
        if (json) {
            QJsonObject o = describe(*s, value);
            o.insert("ok", true);
            out() << QJsonDocument(o).toJson(QJsonDocument::Compact) << "\n";
        } else {
            out() << plain(value) << "\n";
        }
        return 0;
    }

    if (command == "act" || command == "export" || command == "import") {
        QString action = command == "act" ? args.value(1) : "settings." + command;
        QVariantList actArgs;
        for (const QString &a : args.mid(command == "act" ? 2 : 1)) {
            if (a.startsWith('{'))
                actArgs << QJsonDocument::fromJson(a.toUtf8()).object().toVariantMap();
            else
                actArgs << a;
        }
        if (command != "act" && actArgs.isEmpty())
            return fail(json, "usage: hexciri-settings " + command + " <file>");
        const QString error = store.act(action, actArgs);
        if (!error.isEmpty())
            return fail(json, error);
        if (json)
            out() << QJsonDocument(QJsonObject{{"ok", true}}).toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    if (command == "sync") {
        const QString sub = args.value(1, "status");
        if (sub == "status") {
            const QVariant data = store.list("sync");
            out() << QJsonDocument::fromVariant(data).toJson(json ? QJsonDocument::Compact : QJsonDocument::Indented);
            if (json)
                out() << "\n";
            return 0;
        }
        static const QStringList subs{"check", "upload", "apply", "connect", "create", "disconnect"};
        if (!subs.contains(sub))
            return fail(json, "usage: hexciri-settings sync [status|check|upload [--force]|apply|connect <url>|create [name]|disconnect]");
        QVariantList actArgs;
        if (sub == "upload")
            actArgs << (args.contains("--force") ? "force" : "");
        else if (sub == "connect" || sub == "create")
            actArgs << args.value(2);
        if (sub == "connect" && args.value(2).isEmpty())
            return fail(json, "usage: hexciri-settings sync connect <url>");
        const QString error = store.act("sync." + sub, actArgs);
        if (!error.isEmpty())
            return fail(json, error);
        if (json)
            out() << QJsonDocument(QJsonObject{{"ok", true}}).toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    if (command == "data") {
        const QString name = args.value(1);
        if (!store.listNames().contains(name) && !name.startsWith("defaults:"))
            return fail(json, "unknown list " + name + "; one of: " + store.listNames().join(", "));
        const QVariant data = store.list(name);
        out() << QJsonDocument::fromVariant(data).toJson(json ? QJsonDocument::Compact : QJsonDocument::Indented);
        if (json)
            out() << "\n";
        return 0;
    }

    return -1;
}
