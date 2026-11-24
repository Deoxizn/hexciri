#!/usr/bin/env python3
"""Remove the top-level Settings row from the Super+Alt+Space main menu.

Devi 2026-11-24 13:48 MST: settings plugin adds a "Settings" menu at the
bottom of main menu on super alt super, remove it.

Root cause: the menu-lean patch (2026-11-24, Settings app) inserted a
top-level "settings" row after "system" in the forked
default/hexciri/hexciri-menu.jsonc, so it is the last root row, the
bottom of the main menu. The plugin itself does not add it: its
Service.qml builds the Qt app, and its features.cpp menu code only
manages menu-search entries, not this row. Hexciri Settings stays
reachable via Super+Ctrl+S and the launcher icon, which is the point.

Fix, all in v2/install.sh:
1. Menu-lean fork patch: stop inserting the row, and delete any
   "settings" row calling hexciri-launch-settings already in the forked
   menu (so a machine that got the old patch loses it on the next
   installer re-run, which replaces /usr/share/hexciri wholesale).
   The "setup" row keeps its aliases:["settings"] (upstream, a summon
   route, not a visible row).
2. Placement verification: die if the forked menu still has a Settings
   row calling hexciri-launch-settings.
3. Settings step: if the old row ever landed in the user menu
   extensions file ~/.config/hexciri/extensions/hexciri-menu.jsonc,
   delete that exact line (scoped to the hexciri-launch-settings
   action, nothing else).

Base: live nyx install.sh blob 7c6047fad1fc464a79fd5826f63b5724bd13c4f9
(system-update-stale push 3ded4cb, already live).
"""
import hashlib
import sys

ROOT = "/home/hatch/workspace/hexiri-2.0"
PATH = ROOT + "/v2/install.sh"

with open(PATH, "rb") as f:
    data = f.read()
blob = b"blob " + str(len(data)).encode() + b"\0" + data
assert hashlib.sha1(blob).hexdigest() == "7c6047fad1fc464a79fd5826f63b5724bd13c4f9", \
    "base is not live HEAD (system-update-stale push), refusing to patch"
s = data.decode()

# --- 1. Menu-lean block: replace insertion with removal, by line surgery
# (avoids retyping the private-use icon glyph in _settings_row).
lines = s.split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith('_settings_row = '))
end = next(i for i, l in enumerate(lines)
            if 'changed.append("menu lean:' in l and i > start)
assert lines[start].startswith('_settings_row = '), lines[start]
assert 'added top-level Settings row' in lines[end], lines[end]
new_block = [
    '# 2026-11-24, Devi: no top-level Settings row in Super+Alt+Space.',
    '# Settings opens via Super+Ctrl+S / launcher only. Any "settings"',
    '# row left in the forked menu (added by the old lean patch) is',
    '# removed here, so the next installer re-run drops it.',
    '_settings_removed = 0',
    '_kept3 = []',
    'for _line in _kept2:',
    '    if _row_key(_line) == "settings" and "hexciri-launch-settings" in _line:',
    '        _settings_removed += 1',
    '        continue',
    '    _kept3.append(_line)',
    '_kept2 = _kept3',
    'if _lean_removed or _settings_removed or any(_row_key(_l) == "settings" for _l in _mlines):',
    '    with open(menu, "w") as _mf:',
    '        _mf.write("\\n".join(_kept2) + "\\n")',
    '    changed.append("menu lean: removed %d settings rows now in Hexciri Settings, removed top-level Settings row (%d)" % (_lean_removed, _settings_removed))',
]
lines[start:end + 1] = new_block
s = "\n".join(lines)
assert '_settings_row' not in s, "old _settings_row insertion still present"
assert 'added top-level Settings row' not in s

# --- 2. Placement verification: die if the Settings row survived.
ANCHOR = '''grep -q '"update.hexciri"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Update > Hexciri row missing (Phase 2 update)"'''
assert s.count(ANCHOR) == 1
s = s.replace(ANCHOR, ANCHOR + '''
grep -q '"settings".*hexciri-launch-settings' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "menu Settings row still present in hexciri-menu.jsonc (removed 2026-11-24, Settings opens via Super+Ctrl+S / launcher only)"''', 1)

# --- 3. Settings step: clean the user menu extensions file, if present.
ANCHOR2 = 'unset SETTINGS_PLUGIN_ID SETTINGS_PLUGIN_DIR SETTINGS_PLUGIN_URL _HEXCIRI_CLI _HEXCIRI_VALIDATE'
assert s.count(ANCHOR2) == 1
s = s.replace(ANCHOR2, '''# 2026-11-24, Devi: no Settings row in the main menu. If the old row
# ever landed in the user menu extensions file, drop that exact line
# (scoped to the hexciri-launch-settings action, nothing else).
# Super+Ctrl+S / launcher still open Settings.
_user_menu="$HOME/.config/hexciri/extensions/hexciri-menu.jsonc"
if [[ -f $_user_menu ]] && grep -q '"settings".*hexciri-launch-settings' "$_user_menu"; then
  sed -i '/"settings".*hexciri-launch-settings/d' "$_user_menu"
  info "  menu: removed Settings row from user menu extensions (Super+Ctrl+S / launcher only)"
fi
''' + ANCHOR2, 1)

# --- 4. Comment accuracy: hexciri-launch-settings is no longer a menu launcher.
OLD = '# hexciri-launch-settings (repo file v2/hexciri-launch-settings):\n# Super+Ctrl+S / menu Settings launcher. Opens hexciri-settings'
assert s.count(OLD) == 1
s = s.replace(OLD, '# hexciri-launch-settings (repo file v2/hexciri-launch-settings):\n# Super+Ctrl+S Settings launcher. Opens hexciri-settings', 1)

with open(PATH, "w") as f:
    f.write(s)
print("patched v2/install.sh")
print("new blob sha1:", hashlib.sha1(b"blob " + str(len(s.encode())).encode() + b"\0" + s.encode()).hexdigest())
print("lines:", s.count("\n"))
