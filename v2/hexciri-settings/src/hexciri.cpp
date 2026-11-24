// What Hexciri lets a person change that the rest of Settings didn't cover:
// its own on/off flags, the window look its toggles leave alone, the shell's
// look in shell.toml, the options of the bar's widgets, the weather's place,
// and the hooks that run when something happens.
#include "store.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

static QString tr(const char *text) { return QCoreApplication::translate("Store", text); }

static QString fileText(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

static QString saveText(const QString &path, const QString &text) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);
    const QByteArray data = text.toUtf8();
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size() || !f.commit())
        return tr("Could not write %1").arg(path);
    return {};
}

// --- shell.toml -----------------------------------------------------------------------
//
// The shell reads ~/.config/hexciri/shell.toml over the theme's own, key by
// key, and follows the file as it changes. Settings edits one line at a time,
// so comments and everything else stay as the person left them.

static const QRegularExpression tableLine(R"(^\s*\[([^\[\]]+)\]\s*(#.*)?$)");

static QRegularExpression keyLine(const QString &key) {
    return QRegularExpression("^(\\s*)" + QRegularExpression::escape(key) + "\\s*=\\s*(.*)$");
}

// A value without the comment after it; strings keep what is inside quotes.
static QString literalOf(const QString &rest) {
    const QString r = rest.trimmed();
    if (r.startsWith('"')) {
        const int end = r.indexOf('"', 1);
        return end > 0 ? r.left(end + 1) : r;
    }
    const int hash = r.indexOf('#');
    return (hash >= 0 ? r.left(hash) : r).trimmed();
}

QString Store::tomlValue(const QString &text, const QString &table, const QString &key) {
    QString current;
    const QRegularExpression line = keyLine(key);
    for (const QString &l : text.split('\n')) {
        const auto t = tableLine.match(l);
        if (t.hasMatch()) {
            current = t.captured(1).trimmed();
            continue;
        }
        if (current != table)
            continue;
        const auto m = line.match(l);
        if (m.hasMatch())
            return literalOf(m.captured(2));
    }
    return {};
}

QString Store::withTomlValue(const QString &text, const QString &table, const QString &key, const QString &literal) {
    QStringList lines = text.isEmpty() ? QStringList() : text.split('\n');
    const bool endsWithNewline = text.endsWith('\n');
    if (endsWithNewline)
        lines.removeLast();
    const QRegularExpression line = keyLine(key);
    QString current;
    int tableAt = -1, lastInTable = -1;
    for (int i = 0; i < lines.size(); ++i) {
        const auto t = tableLine.match(lines[i]);
        if (t.hasMatch()) {
            current = t.captured(1).trimmed();
            if (current == table) {
                tableAt = i;
                lastInTable = i;
            }
            continue;
        }
        if (current != table)
            continue;
        if (!lines[i].trimmed().isEmpty())
            lastInTable = i;
        const auto m = line.match(lines[i]);
        if (m.hasMatch()) {
            if (literal.isEmpty())
                lines.removeAt(i);
            else
                lines[i] = m.captured(1) + key + " = " + literal;
            return lines.join('\n') + "\n";
        }
    }
    if (literal.isEmpty())
        return text;
    if (tableAt >= 0) {
        lines.insert(lastInTable + 1, key + " = " + literal);
    } else {
        if (!lines.isEmpty() && !lines.last().trimmed().isEmpty())
            lines << QString();
        lines << "[" + table + "]" << key + " = " + literal;
    }
    return lines.join('\n') + "\n";
}

// The value the shell uses: the person's own, else the theme's.
QString Store::shellToml(const QString &table, const QString &key) const {
    const QString mine = tomlValue(fileText(m_paths.config + "/hexciri/shell.toml"), table, key);
    if (!mine.isEmpty())
        return mine;
    return tomlValue(fileText(m_paths.state + "/hexciri/current/theme/shell.toml"), table, key);
}

QString Store::setShellToml(const QString &table, const QString &key, const QString &literal) {
    const QString path = m_paths.config + "/hexciri/shell.toml";
    QMutexLocker lock(&m_stateLock);
    const QString before = fileText(path);
    const QString after = withTomlValue(before, table, key, literal);
    if (after == before)
        return {};
    return saveText(path, after);
}

static QString numberLiteral(double v) {
    QString s = QString::number(v, 'f', 2);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.')))
        s.chop(1);
    return s;
}

// --- Settings -------------------------------------------------------------------------

void Store::buildHexciri() {
    // A flag file in Hexciri's toggles directory, set with hexciri-toggle.
    auto hexciriFlag = [this](const QString &id, const QString &pane, const QString &label, const QString &name,
                              bool inverted) {
        Setting s;
        s.id = id;
        s.pane = pane;
        s.type = "bool";
        s.label = label;
        s.read = [this, name, inverted] { return QVariant(flag(name) != inverted); };
        s.write = [this, name, inverted](const QVariant &v) {
            return runOk("hexciri-toggle", {name, v.toBool() != inverted ? "on" : "off"});
        };
        add(s);
    };

    // ---- Wallpaper and theme --------------------------------------------------------
    {
        Setting s;
        s.id = "appearance.backgroundIntros"; s.pane = "wallpaper"; s.type = "bool";
        s.label = "Play a theme's intro video";
        s.read = [this] { return QVariant(!flag("background-intros-off")); };
        s.write = [this](const QVariant &v) {
            return runOk("hexciri-theme-bg-intro", {v.toBool() ? "enable" : "disable"});
        };
        add(s);
    }
    hexciriFlag("appearance.themeVscode", "appearance", "Theme VS Code", "skip-vscode-theme-changes", true);
    hexciriFlag("appearance.themeCursor", "appearance", "Theme Cursor", "skip-cursor-theme-changes", true);
    hexciriFlag("appearance.themeCodium", "appearance", "Theme VSCodium", "skip-codium-theme-changes", true);

    // ---- The shell's look (shell.toml) ----------------------------------------------
    auto tomlNumber = [this](const QString &id, const QString &pane, const QString &label, const QString &table,
                             const QString &key, double fallback, double min, double max, double step, bool integer) {
        Setting s;
        s.id = id;
        s.pane = pane;
        s.type = integer ? "int" : "real";
        s.label = label;
        s.min = min;
        s.max = max;
        s.step = step;
        s.read = [this, table, key, fallback, integer] {
            bool ok = false;
            const double v = shellToml(table, key).toDouble(&ok);
            const double value = ok ? v : fallback;
            return integer ? QVariant(qRound(value)) : QVariant(value);
        };
        s.write = [this, table, key](const QVariant &v) {
            return setShellToml(table, key, numberLiteral(v.toDouble()));
        };
        add(s);
    };
    tomlNumber("bar.height", "bar", "Bar height", "bar", "size-horizontal", 26, 18, 48, 1, true);
    tomlNumber("bar.sideWidth", "bar", "Bar width on the side of the screen", "bar", "size-vertical", 28, 18, 56, 1, true);
    tomlNumber("bar.backgroundAlpha", "bar", "Bar background opacity", "bar", "background-alpha", 1, 0.2, 1, 0.05, false);
    tomlNumber("appearance.spacingScale", "fonts", "Spacing in the shell", "spacing", "scale", 1, 0.75, 1.5, 0.05, false);
    {
        Setting s;
        s.id = "bar.scaleWithFont"; s.pane = "bar"; s.type = "bool"; s.label = "Bar grows with the text size";
        s.read = [this] { return QVariant(shellToml("bar", "scale-with-font") != "false"); };
        s.write = [this](const QVariant &v) { return setShellToml("bar", "scale-with-font", v.toBool() ? "true" : "false"); };
        add(s);
    }

    // ---- Desktop --------------------------------------------------------------------
    {
        Setting s;
        s.id = "desktop.fullscreenDesktop"; s.pane = "desktop"; s.type = "bool";
        s.label = "Full screen desktop";
        s.read = [this] { return QVariant(flag("bar-off") && flag("hypr/window-no-gaps.lua")); };
        s.write = [this](const QVariant &v) {
            return runOk("hexciri-toggle-fullscreen-desktop", {v.toBool() ? "on" : "off"}, 15000);
        };
        add(s);
    }
    {
        Setting s;
        s.id = "desktop.followMouse"; s.pane = "desktop"; s.type = "choice"; s.label = "Which window gets the keyboard";
        s.choices = {0, 1, 2, 3};
        s.hyprOption = "input:follow_mouse";
        s.read = [this] { return QVariant(hyprGet("input:follow_mouse").toInt()); };
        s.write = [this](const QVariant &v) { return hyprSet({{"input:follow_mouse", v.toInt()}}); };
        add(s);
    }
    // Window corners: Hexciri's sharp and rounded toggles, or a radius of
    // one's own when neither is on.
    {
        Setting s;
        s.id = "desktop.rounding"; s.pane = "appearance"; s.type = "int"; s.label = "Corner radius";
        s.min = 0; s.max = 20; s.step = 1;
        s.hyprOption = "decoration:rounding";
        s.read = [this] { return hyprGet("decoration:rounding"); };
        s.write = [this](const QVariant &v) {
            // A radius of one's own replaces the corner toggles, which
            // would otherwise decide.
            if (flag("hypr/corners-sharp.lua") || flag("hypr/corners-rounded.lua"))
                if (const QString error = runOk("hexciri-hyprland-corners", {"theme"}, 15000); !error.isEmpty())
                    return error;
            return hyprSet({{"decoration:rounding", v.toInt()}});
        };
        add(s);
    }
    addHypr("desktop.shadow", "appearance", "bool", "decoration:shadow:enabled", "Shadows under windows");
    addHypr("desktop.resizeOnBorder", "desktop", "bool", "general:resize_on_border", "Resize windows by dragging their border");
    addHypr("desktop.focusOnActivate", "desktop", "bool", "misc:focus_on_activate", "Switch to apps that ask for attention");
    addHypr("desktop.preserveSplit", "desktop", "bool", "dwindle:preserve_split", "Keep how windows split when they move");
    addHypr("desktop.columnWidth", "desktop", "real", "scrolling:column_width", "Width of a new column", 0.2, 1, 0.05);
    addHypr("desktop.hideOnKeyPress", "desktop", "bool", "cursor:hide_on_key_press", "Hide the pointer while typing");
    {
        Setting s;
        s.id = "desktop.warpOnWorkspace"; s.pane = "desktop"; s.type = "bool";
        s.label = "Move the pointer along when switching workspaces";
        s.hyprOption = "cursor:warp_on_change_workspace";
        s.read = [this] { return QVariant(hyprGet("cursor:warp_on_change_workspace").toInt() != 0); };
        s.write = [this](const QVariant &v) { return hyprSet({{"cursor:warp_on_change_workspace", v.toBool() ? 1 : 0}}); };
        add(s);
    }

    // ---- Keyboard -------------------------------------------------------------------
    {
        Setting s;
        s.id = "keyboard.model"; s.pane = "keyboard"; s.type = "text"; s.label = "Keyboard model";
        s.choicesList = "keyboardModels";
        s.hyprOption = "input:kb_model";
        s.read = [this] { return QVariant(hyprGet("input:kb_model").toString()); };
        s.write = [this](const QVariant &v) {
            static const QRegularExpression valid("^[A-Za-z0-9_+-]{0,40}$");
            if (!valid.match(v.toString()).hasMatch())
                return tr("Unknown keyboard model %1").arg(v.toString());
            return hyprSet({{"input:kb_model", v.toString()}});
        };
        add(s);
    }

    // Each layout's variant (US, international), in the order of the layouts.
    {
        Setting s;
        s.id = "keyboard.variants"; s.pane = "keyboard"; s.type = "text"; s.label = "Layout variants";
        s.choicesList = "keyboardVariants";
        s.read = [this] { return QVariant(hyprGet("input:kb_variant").toString()); };
        s.write = [this](const QVariant &v) {
            static const QRegularExpression valid("^[A-Za-z0-9_-]*(,[A-Za-z0-9_-]*)*$");
            const QString variants = v.toString().remove(' ');
            const int layouts = hyprGet("input:kb_layout").toString().split(',').size();
            if (!valid.match(variants).hasMatch() || variants.split(',').size() > layouts)
                return tr("Variants are xkb codes, one for each layout");
            // All empty is no variants at all.
            return hyprSet({{"input:kb_variant", QString(variants).remove(',').isEmpty() ? QString() : variants}});
        };
        add(s);
    }

    // ---- Where screenshots and recordings go ----------------------------------------
    auto folder = [this](const QString &id, const QString &label, const QString &variable) {
        Setting s;
        s.id = id;
        s.pane = "general";
        s.type = "text";
        s.label = label;
        s.read = [this, variable] {
            // What Settings set, not what this session started with, so a
            // folder put back to Hexciri's shows that at once.
            static const QRegularExpression line("^(?:export )?" + variable + "=(.*)$", QRegularExpression::MultilineOption);
            QString value = line.match(fileText(m_paths.config + "/uwsm/env.d/60-hexciri-settings")).captured(1).trimmed();
            if (value.size() >= 2 && value.startsWith('"') && value.endsWith('"'))
                value = value.mid(1, value.size() - 2);
            return QVariant(value);
        };
        s.write = [this, variable](const QVariant &v) { return setSessionVariable(variable, v.toString()); };
        add(s);
    };
    folder("general.screenshotDir", "Screenshots folder", "HEXCIRI_SCREENSHOT_DIR");
    folder("general.screenrecordDir", "Screen recordings folder", "HEXCIRI_SCREENRECORD_DIR");

    // ---- Hexciri's default mise tools -----------------------------------------------
    // A user opts out by having mise skip Hexciri's tools file, which
    // hexciri-mise-default-tools lists in ~/.config/mise/miserc.toml. Nothing
    // to show without that file.
    {
        Setting s;
        s.id = "software.miseDefaultTools";
        s.pane = "software";
        s.type = "bool";
        s.label = "Hexciri's default mise tools";
        s.read = [this] {
            QString tools = qEnvironmentVariable("HEXCIRI_MISE_CONFIG_PATH");
            if (tools.isEmpty()) tools = "/etc/mise/conf.d/hexciri-tools.toml";
            if (!QFileInfo::exists(tools)) return QVariant();
            const QStringList lines = fileText(m_paths.config + "/mise/miserc.toml").split('\n');
            const bool optedOut = std::any_of(lines.begin(), lines.end(), [&](const QString &l) {
                return !l.trimmed().startsWith('#') && l.contains(tools);
            });
            return QVariant(!optedOut);
        };
        s.write = [this](const QVariant &v) {
            return runOk("hexciri-mise-default-tools", {v.toBool() ? "enable" : "disable"}, 60000);
        };
        add(s);
    }
}

// A variable the next session starts with, in uwsm's env.d, which every
// login reads. An empty value removes it.
QString Store::setSessionVariable(const QString &name, const QString &value) {
    static const QRegularExpression validName("^[A-Z][A-Z0-9_]*$");
    if (!validName.match(name).hasMatch())
        return tr("Unknown setting %1").arg(name);
    if (!value.isEmpty() && (!value.startsWith('/') || value.contains('"') || value.contains('\\')
                             || value.contains('$') || value.contains('`') || value.contains('\n')))
        return tr("Choose a folder");
    const QString path = m_paths.config + "/uwsm/env.d/60-hexciri-settings";
    QStringList lines;
    for (const QString &l : fileText(path).split('\n', Qt::SkipEmptyParts))
        if (!l.startsWith('#') && !l.startsWith("export " + name + "=") && !l.startsWith(name + "="))
            lines << l;
    if (!value.isEmpty())
        lines << "export " + name + "=\"" + value + "\"";
    if (lines.isEmpty())
        return QFile::exists(path) && !QFile::remove(path) ? tr("Could not write %1").arg(path) : QString();
    lines.prepend("# Written by Settings; read by every new login.");
    return saveText(path, lines.join('\n') + "\n");
}

// --- Lists ----------------------------------------------------------------------------

static const QStringList hookTypes = {"post-boot", "post-update", "theme-set", "font-set", "battery-low", "pre-refresh-pacman"};

static bool validHookFile(const QString &name) {
    static const QRegularExpression valid("^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$");
    return valid.match(name).hasMatch() && !name.contains("..");
}

QVariant Store::listHexciri(const QString &name) {
    if (name == "hooks") {
        QVariantList out;
        for (const QString &type : hookTypes) {
            QVariantList items;
            const QDir dir(m_paths.config + "/hexciri/hooks/" + type + ".d");
            for (const QFileInfo &f : dir.entryInfoList(QDir::Files, QDir::Name)) {
                const bool sample = f.fileName().endsWith(".sample");
                items << QVariantMap{{"name", f.fileName()}, {"sample", sample},
                                     {"title", sample ? f.fileName().chopped(7) : f.fileName()},
                                     {"enabled", !sample || QFile::exists(f.absolutePath() + "/" + f.fileName().chopped(7))}};
            }
            out << QVariantMap{{"type", type}, {"items", items}};
        }
        return out;
    }
    if (name == "keyboardModels") {
        // The "! model" section of xkb's list: "  pc105  Generic 105-key PC".
        QVariantList out;
        bool inModels = false;
        for (const QString &line : fileText("/usr/share/X11/xkb/rules/base.lst").split('\n')) {
            if (line.startsWith('!')) {
                inModels = line.trimmed() == "! model";
                continue;
            }
            if (!inModels || line.trimmed().isEmpty())
                continue;
            const QString t = line.trimmed();
            const int space = t.indexOf(' ');
            if (space < 0)
                continue;
            out << QVariantMap{{"value", t.left(space)}, {"text", t.mid(space).trimmed()}};
        }
        return out;
    }
    if (name == "keyboardVariants") {
        // The "! variant" section: "  intl            us: English (US, intl., with dead keys)".
        QVariantList out;
        bool inVariants = false;
        static const QRegularExpression row(R"(^\s+(\S+)\s+([A-Za-z0-9_-]+):\s*(.+)$)");
        for (const QString &line : fileText("/usr/share/X11/xkb/rules/base.lst").split('\n')) {
            if (line.startsWith('!')) {
                inVariants = line.trimmed() == "! variant";
                continue;
            }
            const auto m = row.match(line);
            if (inVariants && m.hasMatch())
                out << QVariantMap{{"code", m.captured(1)}, {"layout", m.captured(2)}, {"name", m.captured(3).trimmed()}};
        }
        return out;
    }
    if (name == "weather") {
        const QJsonObject o = QJsonDocument::fromJson(
            fileText(m_paths.state + "/hexciri/settings/weather.json").toUtf8()).object();
        return QVariantMap{{"name", o.value("name").toString()}, {"set", !o.isEmpty()}};
    }
    if (name == "editors") {
        // Which editors Hexciri themes are installed, so their switches show.
        QVariantMap out;
        for (const QString &bin : {QStringLiteral("code"), QStringLiteral("cursor"), QStringLiteral("codium"),
                                   QStringLiteral("herdr")})
            out.insert(bin, !QStandardPaths::findExecutable(bin).isEmpty());
        return out;
    }
    return {};
}

// --- Actions --------------------------------------------------------------------------

QString Store::actHexciri(const QString &action, const QVariantList &args) {
    const QString a0 = args.value(0).toString();
    if (action == "bar.setOption") {
        // args: widget id, key, the value as JSON (null removes it), and
        // the widget's section and index, for widgets the bar has twice.
        static const QRegularExpression validWidget("^[A-Za-z0-9][A-Za-z0-9._-]*$");
        static const QRegularExpression validKey("^[A-Za-z][A-Za-z0-9_.-]{0,63}$");
        static const QStringList sections{"left", "centerBegin", "center", "centerEnd", "right", "tray"};
        const QString key = args.value(1).toString();
        if (!validWidget.match(a0).hasMatch() || a0.contains(".."))
            return tr("Unknown widget %1").arg(a0);
        if (!validKey.match(key).hasMatch())
            return tr("Unknown setting %1").arg(key);
        const QString json = args.value(2).toString();
        QJsonParseError parsed;
        QJsonDocument::fromJson("[" + json.toUtf8() + "]", &parsed);
        if (json.isEmpty() || parsed.error != QJsonParseError::NoError)
            return tr("Unknown setting %1").arg(key);
        QStringList command{"set", a0, key, json, "--json"};
        const QString section = args.value(3).toString();
        if (sections.contains(section))
            command << "--section" << section << "--index" << QString::number(qMax(0, args.value(4).toInt()));
        // The shell writes shell.json a moment later; wait for it, so the
        // page reads back the new value rather than snapping to the old.
        const QDateTime before = QFileInfo(m_paths.config + "/hexciri/shell.json").lastModified();
        const QString error = runOk("hexciri-bar", command, 15000);
        if (error.isEmpty())
            waitForShellWrite(before);
        return error;
    }
    if (action == "weather.location") {
        // An empty place goes back to finding it from the network.
        const QString place = a0.trimmed();
        if (place.isEmpty())
            return runOk("hexciri-weather-location", {"--clear"}, 10000);
        if (place.size() > 80 || place.startsWith('-') || place.contains('\n'))
            return tr("Type a city or a place");
        return runOk("hexciri-weather-location", {"--set", place}, 10000);
    }
    if (action == "folder.choose") {
        // The setting whose folder to choose, then the picker.
        if (a0 != "general.screenshotDir" && a0 != "general.screenrecordDir")
            return tr("Unknown setting %1").arg(a0);
        const ProcResult picked = run("hexciri-file-select", {"--title", tr("Choose a folder"), "--directory"}, 600000);
        if (!picked.ok() || picked.text().trimmed().isEmpty())
            return {};
        return write(a0, picked.text().trimmed().section('\n', 0, 0));
    }
    if (action.startsWith("hook.")) {
        const QString type = a0, file = args.value(1).toString();
        if (!hookTypes.contains(type))
            return tr("Unknown hook %1").arg(type);
        const QString dir = m_paths.config + "/hexciri/hooks/" + type + ".d";
        if (action == "hook.add") {
            const ProcResult picked = run("hexciri-file-select", {"--title", tr("Choose a script")}, 600000);
            if (!picked.ok() || picked.text().trimmed().isEmpty())
                return {};
            return runOk("hexciri-hook-install", {type, picked.text().trimmed().section('\n', 0, 0)}, 10000);
        }
        if (!validHookFile(file) || !QFileInfo(dir + "/" + file).isFile())
            return tr("Unknown hook %1").arg(file);
        const QString path = dir + "/" + file;
        if (action == "hook.edit")
            return launch("hexciri-launch-editor", {path});
        if (action == "hook.remove") {
            if (file.endsWith(".sample"))
                return tr("Hexciri's examples stay; turn them off instead");
            return QFile::remove(path) ? QString() : tr("Could not remove %1").arg(path);
        }
        if (action == "hook.use" || action == "hook.stopUsing") {
            // An example runs once there is a copy of it without .sample.
            if (!file.endsWith(".sample"))
                return tr("Unknown hook %1").arg(file);
            const QString target = dir + "/" + file.chopped(7);
            if (action == "hook.stopUsing")
                return !QFile::exists(target) || QFile::remove(target) ? QString() : tr("Could not remove %1").arg(target);
            if (QFile::exists(target))
                return {};
            if (!QFile::copy(path, target))
                return tr("Could not write %1").arg(target);
            QFile::setPermissions(target, QFile::permissions(target) | QFile::ExeOwner | QFile::ExeGroup | QFile::ExeOther);
            return {};
        }
    }
    return tr("Unknown action %1").arg(action);
}
