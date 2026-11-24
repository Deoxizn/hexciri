#!/usr/bin/env bash
# Hexciri fork patch 02: menu audit fixes: dead rows out, shell IPC paths absolute.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/02-menu-audit.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "02-menu-audit.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  # Re-run quiet (2026-11-24, Devi: a plain `hexciri update` printed
  # ~500 lines of installer re-run spam, most of them "Kept: ... (already
  # current)" / "already present" / "already correct"). On a re-run those
  # go to the detail log only; changed / failed steps still print, and
  # the one-line "already up to date" status lines (run_pacman) stay on
  # screen, they are the per-step result.
  if [ "${IS_RERUN:-0}" = "1" ]; then
    case "$1" in
      Kept*|*already\ present*|*already\ correct*|*already\ current*|Theme\ already\ applied:*|*already\ enabled*)
        printf '[hexciri] %s\n' "$1" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
        return 0
        ;;
    esac
  fi
  printf '[hexciri] %s\n' "$1"
}
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}
# Fork-integrity helpers, verbatim from install.sh (00-compat-alias.sh
# calls bootstrap_ok; hyprlua_ok is here for any patch that needs it).
bootstrap_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 500 ] || return 1
  grep -q 'package.path' "$_f" 2>/dev/null || return 1
  grep -q 'HEXCIRI_PATH' "$_f" 2>/dev/null || return 1
  return 0
}
hyprlua_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 1000 ] || return 1
  grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1
  return 0
}

# --- Patch menu audit fixes: dead rows out, shell IPC paths absolute ---
# Menu audit 2026-11-23 (Devi: "basically super alt space menu needs a full
# audit"): every menu entry was checked against the forked bin/ allowlist.
# What this block does, all on the fork output before placement:
#  1. Deletes dead menu rows, and restores the FULL Install + Remove
#     subtrees (2026-11-24, Devi: full install/remove back, except
#     Omarchy specifics). A row stays when every hexciri-* command its
#     action names exists in bin/, so Package / AUR / Web App / TUI /
#     Style / Gaming / Browser / Terminal / Editor / Service / Development
#     / Dictation and their Remove counterparts come back: their backing
#     bins are in the allowlist now (is_allowed_bin above). A when/disabled
#     guard naming a missing command only hides or mis-guards the row, it
#     never runs, so only the action decides. Header rows (no action) stay
#     only while at least one child row under them stays. Still deleted:
#     Herdr (install.ai.herdr only: Herdr stays out, its installer curls
#     releases.herdr.dev and its theme/autostart bits are Omarchy-side),
#     Windows + preinstalls (Omarchy-specific), Docker rows (Docker out),
#     factory reset (btrfs-only), Emacs (dead upstream:
#     install-editor-emacs calls a bin that does not exist). AI install/
#     remove and Foot are BACK 2026-11-24 (correction to the 74fe03b3
#     restore, which wrongly dropped both): AI rows except Herdr, and
#     install.terminal.foot as an option only, Kitty stays the default.
#     Update > Channel (Hexciri has no channels), Update > Games /
#     Password (games-*/drive-* out of scope), Update > Config > Plymouth
#     (plymouth out), System > Screensaver (no screensaver binary ships
#     in v2). Update > Hexciri is BACK: hexciri-update is Phase 2, done
#     2026-11-24 (eos-update --aur + Hexciri self-update + mise).
#     Appearance > Unlock (plymouth), Learn > Herdr keybindings (Herdr out),
#     Setup > Default Editor > Neovim (neovim removed), Setup > Security >
#     Sudoless Docker (Docker out). The upstream jsonc is untouched.
#  2. Menu "Apps" row + bar trigger call hexciri-shell by absolute path:
#     both go through Util.execDetached, and a spawned process only finds
#     hexciri-shell if the shell's env carries /usr/share/hexciri/bin on
#     PATH. Super+Alt+Space works (Hyprland global shortcut, in-process)
#     while the bar Arch icon and the menu Apps click do nothing: same
#     spawn path, same missing lookup. Absolute path + the hexciri-shell
#     HEXCIRI_PATH default below make both independent of that env.
#  3. hexciri-shell defaults HEXCIRI_PATH to /usr/share/hexciri when unset
#     instead of failing: it is the fixed install path, and compat.sh
#     already applies the same default for the shell process itself.
#  4. shell.qml + Menu.qml execArgv call sites for hexciri-shell /
#     hexciri-menu-keybindings go absolute for the same reason.
#  5. launch-editor falls back to nano (was nvim); default-editor loses
#     its nvim choice (neovim removed, and its branch called the missing
#     hexciri-pkg-add).
# Idempotent: every replacement checks it is not already applied.
step "Patching menu audit fixes: dead rows out, shell IPC paths absolute"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import re
import sys

root = sys.argv[1]
changed = []

# 1. Delete dead menu rows, one entry per line in the jsonc.
menu = root + "/default/hexciri/hexciri-menu.jsonc"
with open(menu) as f:
    lines = f.read().splitlines()
bin_dir = root + "/bin"
have_bins = set(os.listdir(bin_dir)) if os.path.isdir(bin_dir) else set()
def _row_key(line):
    m = re.match(r'^\s*"([^"]+)"\s*:', line)
    return m.group(1) if m else None
def _action_tokens(line):
    m = re.search(r'"action"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
    return re.findall(r'hexciri-[a-z0-9-]+', m.group(1)) if m else []
dead = re.compile(
    r'^\s*"(update\.channel(\..*)?|'
    r'update\.omarchy|update\.games|update\.password|'
    r'update\.config\.plymouth|system\.screensaver|'
    r'learn\.herdr-keybindings|setup\.default\.editor\.neovim|'
    r'setup\.security\.sudoless-docker|appearance\.unlock)"\s*:'
)
kept = []
removed = []
kept_keys = set()
# Out of scope even when the action's helper exists: generic helpers
# (install-and-launch, install-app, launch-floating-terminal) make AI
# rows look valid, but Herdr is out (standing decision, 2026-11-24
# correction: AI agents ARE options, Devi just prefers opencode; only
# Herdr stays out). The prefix drop is Herdr only now; the exact drops
# are the Omarchy-specific / Docker / dead rows (windows, preinstalls,
# factory reset is btrfs-only, sudoless-docker needs Docker, docker-dbs
# needs Docker, Emacs is dead upstream). Foot is back as an Install >
# Terminal option only (Kitty stays default); there is no upstream
# remove.terminal.* subtree, Foot removes via Remove > Package.
_drop_prefix = (
    "install.ai.herdr",
    "remove.ai.herdr",
)
_drop_exact = {
    "install.windows", "install.preinstalls",
    "install.development.docker-dbs",
    "install.editor.emacs",
    "remove.windows", "remove.preinstalls", "remove.factory-reset",
    "remove.security.sudoless-docker",
}
for line in lines:
    key = _row_key(line)
    if key is None or not (key == "install" or key == "remove" or key.startswith("install.") or key.startswith("remove.")):
        if key is not None and dead.match(line):
            removed.append(line.strip()[:60])
            continue
        kept.append(line)
        continue
    if key in _drop_exact or key.startswith(_drop_prefix):
        removed.append(line.strip()[:60])
        continue
    toks = _action_tokens(line)
    if toks and any(t not in have_bins for t in toks):
        removed.append(line.strip()[:60])
        continue
    kept.append(line)
    kept_keys.add(key)
# Second pass, repeated until stable: drop header rows whose subtree has no
# kept row left. One pass is not enough, an empty submenu (development /
# javascript / php / elixir) keeps its parent alive for a round even
# though the submenu itself drops in the same round.
while True:
    final = []
    dropped_this_round = False
    for line in kept:
        key = _row_key(line)
        if key is not None and _action_tokens(line) == [] and (key == "install" or key == "remove" or key.startswith("install.") or key.startswith("remove.")):
            prefix = key + "."
            if not any(k.startswith(prefix) for k in kept_keys):
                removed.append(line.strip()[:60])
                dropped_this_round = True
                continue
        final.append(line)
    kept = final
    kept_keys = {_row_key(l) for l in kept if _row_key(l) is not None}
    if not dropped_this_round:
        break
if removed:
    with open(menu, "w") as f:
        f.write("\n".join(kept) + "\n")
    changed.append("menu: removed %d dead rows (full Install/Remove restored 2026-11-24 + AI/Foot correction, dropped only Herdr, windows, preinstalls, docker rows, factory-reset, emacs + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))
    for r in removed[:8]:
        print("  menu removed: " + r)
    if len(removed) > 8:
        print("  menu removed: ... and %d more" % (len(removed) - 8))
else:
    print("menu: no dead rows found (already patched?)")

# 1b. Menu lean (2026-11-24, Devi): Hexciri Settings now covers these
# rows, so they leave Super+Alt+Space. Bar position/background, dock
# position/autohide, window corners/transparency and DNS choices live
# in Settings (Bar / Dock / Appearance / System tabs); the parents go
# too, or they would be empty submenus. Install/Remove/Update/Learn/
# System stay: they are actions, not settings.
_lean = {
    "appearance.top-bar.background", "appearance.top-bar.background.opaque",
    "appearance.top-bar.background.glassy", "appearance.top-bar.background.clear",
    "appearance.top-bar.position", "appearance.top-bar.position.top",
    "appearance.top-bar.position.bottom", "appearance.top-bar.position.left",
    "appearance.top-bar.position.right",
    "appearance.windows.corners", "appearance.windows.corners.theme",
    "appearance.windows.corners.sharp", "appearance.windows.corners.rounded",
    "appearance.windows.transparency", "appearance.windows.transparency.opaque",
    "appearance.windows.transparency.transparent", "appearance.windows.transparency.glassy",
    "appearance.dock.autohide", "appearance.dock.always-on",
    "appearance.dock.position", "appearance.dock.position.top",
    "appearance.dock.position.bottom", "appearance.dock.position.left",
    "appearance.dock.position.right",
    "setup.network.dns", "setup.network.dns.dhcp", "setup.network.dns.cloudflare",
    "setup.network.dns.google", "setup.network.dns.alidns", "setup.network.dns.custom",
}
with open(menu) as _mf:
    _mlines = _mf.read().splitlines()
_kept2 = []
_lean_removed = 0
for _line in _mlines:
    _k = _row_key(_line)
    if _k is not None and _k in _lean:
        _lean_removed += 1
        continue
    _kept2.append(_line)
# 2026-11-24, Devi: no top-level Settings row in Super+Alt+Space.
# Settings opens via Super+Ctrl+S / launcher only. Any "settings"
# row left in the forked menu (added by the old lean patch) is
# removed here, so the next installer re-run drops it.
_settings_removed = 0
_kept3 = []
for _line in _kept2:
    if _row_key(_line) == "settings" and "hexciri-launch-settings" in _line:
        _settings_removed += 1
        continue
    _kept3.append(_line)
_kept2 = _kept3
if _lean_removed or _settings_removed or any(_row_key(_l) == "settings" for _l in _mlines):
    with open(menu, "w") as _mf:
        _mf.write("\n".join(_kept2) + "\n")
    changed.append("menu lean: removed %d settings rows now in Hexciri Settings, removed top-level Settings row (%d)" % (_lean_removed, _settings_removed))

with open(menu) as f:
    m = f.read()
m_orig = m
# 2. Menu Apps row: absolute hexciri-shell path.
if '"action":"hexciri-shell hexciri.dock apps"' in m:
    m = m.replace('"action":"hexciri-shell hexciri.dock apps"', '"action":"/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps"')
    changed.append("menu apps row: hexciri-shell by absolute path")
elif "/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps" in m:
    print("menu apps row already absolute, skipping")
else:
    print("WARN: menu apps action not found, apps row NOT patched")

if m != m_orig:
    with open(menu, "w") as f:
        f.write(m)

# 2b. Learn menu rework (2026-11-24, Devi: tmux not installed?, no kitty
# link, QS missing). Audit of all 9 upstream Learn rows: keybindings /
# hexciri / hyprland / arch / bash kept (all live); neovim -> zed (neovim
# is trimmed in v2, Zed is the default editor); community dropped (Omarchy
# Discord invite, Hexciri has no Discord); fish + kitty + quickshell added
# (interactive shell, default terminal, the shell itself). Tmux row kept,
# its backing config is copied into the fork above.
with open(menu) as f:
    _llines = f.read().splitlines()
_learn_out = []
_learn_changed = []
for _line in _llines:
    _k = _row_key(_line)
    if _k == "learn.neovim":
        _learn_out.append("  \"learn.zed\": {\"icon\":\"\uf15c\",\"label\":\"Zed\",\"action\":\"hexciri-launch-webapp 'https://zed.dev/docs'\"},")
        _learn_changed.append("learn.neovim -> learn.zed (neovim trimmed in v2)")
        continue
    if _k == "learn.community":
        _learn_changed.append("learn.community dropped (Omarchy Discord invite, Hexciri has none)")
        continue
    _learn_out.append(_line)
    if _k == "learn.bash" and not any('"learn.fish"' in _l for _l in _llines):
        _learn_out.append("  \"learn.fish\": {\"icon\":\"\U000f1183\",\"label\":\"Fish\",\"action\":\"hexciri-launch-webapp 'https://fishshell.com/docs/current/'\"},")
        _learn_out.append("  \"learn.kitty\": {\"icon\":\"\ue795\",\"label\":\"Kitty\",\"action\":\"hexciri-launch-webapp 'https://sw.kovidgoyal.net/kitty/'\"},")
        _learn_out.append("  \"learn.quickshell\": {\"icon\":\"\U000f09d1\",\"label\":\"Quickshell\",\"action\":\"hexciri-launch-webapp 'https://quickshell.org/docs/'\"},")
        _learn_changed.append("learn.fish + learn.kitty + learn.quickshell added")
with open(menu, "w") as f:
    f.write("\n".join(_learn_out) + "\n")
if _learn_changed:
    changed.append("menu learn rework: " + "; ".join(_learn_changed))

# 3. hexciri-shell: default HEXCIRI_PATH instead of failing when unset.
sh = root + "/bin/hexciri-shell"
with open(sh) as f:
    shs = f.read()
sh_orig = shs
_old_fail = '[[ -n ${HEXCIRI_PATH:-} ]] || fail "HEXCIRI_PATH is not set"'
_new_def = '[[ -n ${HEXCIRI_PATH:-} ]] || HEXCIRI_PATH="/usr/share/hexciri"'
if _old_fail in shs:
    shs = shs.replace(_old_fail, _new_def, 1)
    changed.append("hexciri-shell: HEXCIRI_PATH defaults to /usr/share/hexciri when unset")
elif _new_def in shs:
    print("hexciri-shell default already present, skipping")
else:
    print("WARN: hexciri-shell HEXCIRI_PATH check not found, default NOT applied")
if shs != sh_orig:
    with open(sh, "w") as f:
        f.write(shs)

# 4. Bar trigger + shell/menu execArgv call sites: absolute hexciri-shell.
bw = root + "/shell/plugins/menu/BarWidget.qml"
with open(bw) as f:
    b = f.read()
b_orig = b
if 'root.bar.run("hexciri-shell shell toggle hexciri.menu' in b:
    b = b.replace('root.bar.run("hexciri-shell shell toggle hexciri.menu', 'root.bar.run("/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu', 1)
    changed.append("bar trigger: hexciri-shell by absolute path")
elif "/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu" in b:
    print("bar trigger already absolute, skipping")
else:
    print("WARN: bar trigger hexciri-shell call not found, trigger NOT patched")
if b != b_orig:
    with open(bw, "w") as f:
        f.write(b)

sq = root + "/shell/shell.qml"
with open(sq) as f:
    q = f.read()
q_orig = q
if 'Util.execArgv(["hexciri-shell", target, method])' in q:
    q = q.replace('Util.execArgv(["hexciri-shell", target, method])', 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-shell", target, method])', 1)
    changed.append("shell.qml: hexciri-shell execArgv by absolute path")
elif 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-shell", target, method])' in q:
    print("shell.qml execArgv already absolute, skipping")
else:
    print("WARN: shell.qml hexciri-shell execArgv not found, NOT patched")
if q != q_orig:
    with open(sq, "w") as f:
        f.write(q)

mq = root + "/shell/plugins/menu/Menu.qml"
with open(mq) as f:
    mq_s = f.read()
mq_orig = mq_s
if 'Util.execArgv(["hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])' in mq_s:
    mq_s = mq_s.replace('Util.execArgv(["hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])', 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])', 1)
    changed.append("Menu.qml: hexciri-menu-keybindings execArgv by absolute path")
elif "/usr/share/hexciri/bin/hexciri-menu-keybindings" in mq_s:
    print("Menu.qml execArgv already absolute, skipping")
else:
    print("WARN: Menu.qml hexciri-menu-keybindings execArgv not found, NOT patched")
if mq_s != mq_orig:
    with open(mq, "w") as f:
        f.write(mq_s)

# 5. Editor fallbacks: launch-editor nvim -> nano, default-editor nvim out.
le = root + "/bin/hexciri-launch-editor"
with open(le) as f:
    le_s = f.read()
le_orig = le_s
if '|| editor="nvim"' in le_s:
    le_s = le_s.replace('|| editor="nvim"', '|| editor="nano"', 1)
    changed.append("launch-editor fallback nvim -> nano")
elif '|| editor="nano"' in le_s:
    print("launch-editor fallback already nano, skipping")
else:
    print("WARN: launch-editor nvim fallback not found, NOT patched")
if le_s != le_orig:
    with open(le, "w") as f:
        f.write(le_s)

de = root + "/bin/hexciri-default-editor"
with open(de) as f:
    de_s = f.read()
de_orig = de_s
de_s = re.sub(r'^nvim\) selection="nvim"; editor="nvim"; name="Neovim"; glyph=.*$\n', "", de_s, flags=re.M)
de_s = re.sub(r'^\s*nvim\) hexciri-pkg-add neovim ;;$\n', "", de_s, flags=re.M)
de_s = de_s.replace("<plain|code|cursor|zed|sublime_text|helix|vim|emacs|nvim>", "<plain|code|cursor|zed|sublime_text|helix|vim|emacs>")
if de_s != de_orig:
    with open(de, "w") as f:
        f.write(de_s)
    changed.append("default-editor: nvim choice removed (neovim not installed)")
else:
    print("default-editor: nvim choice already gone, skipping")

# 6. Herdr autostart: default/hypr/autostart.lua unconditionally starts a
#    Herdr server on every boot (systemd-run ... herdr server). Herdr is
#    deliberately out of v2 (bind removed, AI agents out of scope), so the
#    unit fails quietly on every boot. Remove the block, comments and all.
auto = root + "/default/hypr/autostart.lua"
with open(auto) as f:
    a_lines = f.read().splitlines()
a_start = None
for i, l in enumerate(a_lines):
    if "-- Start the herdr server inside the graphical session" in l:
        a_start = i
        break
if a_start is not None:
    a_end = None
    for j in range(a_start, len(a_lines)):
        if a_lines[j] == "  )":
            a_end = j + 1
            break
    if a_end is not None:
        del a_lines[a_start:a_end]
        if a_start < len(a_lines) and a_lines[a_start] == "":
            del a_lines[a_start]
        with open(auto, "w") as f:
            f.write("\n".join(a_lines) + "\n")
        changed.append("autostart: Herdr server block removed (Herdr out of v2 scope)")
    else:
        print("menu audit: herdr autostart block end not found, skipping")
else:
    print("menu audit: herdr autostart block already gone, skipping")

# 6. hexciri-font-set: second match block for the system-assigned
# monospace default (2026-11-24, Maple Mono NF). Upstream Omarchy's
# default/fontconfig/conf.avail/50-omarchy.conf assigns monospace to
# JetBrainsMono Nerd Font with mode="assign" before the user fonts.conf
# is read, so the first block's test (family == monospace) never matches
# and fc-match monospace keeps returning JetBrainsMono after font-set
# "succeeds": the menu never shows the chosen font as current. The
# second block matches the family the system assigned monospace to, so
# the chosen font wins either way. A two-string single test was tried
# and rejected: fontconfig warns multiple values in <test> are
# unsupported, and it misfired onto sans-serif. Two blocks, no warning.
fs = root + "/bin/hexciri-font-set"
with open(fs) as f:
    fs_s = f.read()
fs_orig = fs_s
_old_fc = """# fontconfig is the canonical source of truth \u2014 the hexciri shell, Qt apps,
# and anything resolving "monospace" all read from here. This file is loaded
# after the package-owned default, and prepend_first puts the chosen family at
# the head of the list so it wins over the family that default prefers.
fontconfig_file="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$(dirname "$fontconfig_file")"
cat >"$fontconfig_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
</fontconfig>
XML"""
_new_fc = """# fontconfig is the canonical source of truth \u2014 the hexciri shell, Qt apps,
# and anything resolving "monospace" all read from here. This file is loaded
# after the package-owned default, and prepend_first puts the chosen family at
# the head of the list so it wins over the family that default prefers.
# Hexciri 2026-11-24 (Maple Mono NF): a second match block is required.
# Upstream Omarchy ships default/fontconfig/conf.avail/50-omarchy.conf,
# whose monospace rule uses mode="assign" to replace the "monospace" alias
# with JetBrainsMono Nerd Font before this file is read, so the first
# block's test (family == monospace) never matches and fc-match monospace
# keeps returning JetBrainsMono even after font-set "succeeds" \u2014 the menu
# never shows the chosen font as current. The second block matches the
# family the system assigned monospace to, so the chosen font wins either
# way. Side effect, accepted: an app that asks for JetBrainsMono Nerd Font
# by name also resolves to the chosen font \u2014 that family IS the system
# monospace default, and font-set's job is to replace it.
fontconfig_file="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$(dirname "$fontconfig_file")"
cat >"$fontconfig_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Hexciri font-set second match: catches the system-assigned monospace default (see comment above) -->
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family" qual="any">
      <string>JetBrainsMono Nerd Font</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
</fontconfig>
XML"""
if _old_fc in fs_s:
    fs_s = fs_s.replace(_old_fc, _new_fc, 1)
    changed.append("font-set: second fonts.conf match block for JetBrainsMono Nerd Font (system-assigned monospace default, Maple Mono NF fix)")
elif _new_fc in fs_s:
    print("font-set second match block already present, skipping")
else:
    print("WARN: font-set fonts.conf heredoc not found, second match block NOT applied")
if fs_s != fs_orig:
    with open(fs, "w") as f:
        f.write(fs_s)

# 7. Menu row Install > Style > Font > Maple Mono CN (2026-11-24, PR #16025).
# Inserted after the iosevka row, the last upstream font row. Runs after
# the audit's write above, so the audit never drops it; the action token
# hexciri-install-font already exists in the fork bin, so the audit's
# token check and the post-placement invariant check both pass.
_maple_row = "  \"install.style.font.maple\": {\"icon\":\"\ue659\",\"label\":\"Maple Mono CN\",\"disabled\":\"hexciri-font-maple-cn-present\",\"action\":\"hexciri-launch-floating-terminal-with-presentation 'yay -S --needed --noconfirm maplemono-nf-cn && sleep 2 && hexciri-font-set \\\"Maple Mono NF CN\\\"'\"},"
with open(menu) as f:
    _m_lines = f.read().splitlines()
if any('"install.style.font.maple"' in _l for _l in _m_lines):
    print("menu maple row already present, skipping")
else:
    _inserted = False
    _out = []
    for _l in _m_lines:
        _out.append(_l)
        if '"install.style.font.iosevka"' in _l:
            _out.append(_maple_row)
            _inserted = True
    if _inserted:
        with open(menu, "w") as f:
            f.write("\n".join(_out) + "\n")
        changed.append("menu: Install > Style > Font > Maple Mono CN row added (maplemono-nf-cn via yay, pkg-add is pacman-only)")
    else:
        print("WARN: install.style.font.iosevka row not found, maple menu row NOT added")

# 8. hexciri-font-list: list dual-width fonts too (2026-11-24, PR #16025).
# omarchy-font-list asked fontconfig only for spacing=100 (pure monospace).
# Maple Mono NF CN reports spacing=90 (dual: Latin one cell, CJK two), so
# it was silently filtered out even when installed. Ask for both, dedup
# with sort -u. Dual width is still a fixed grid, exactly how a terminal
# draws CJK, and a stock install has no other spacing 90 font.
fl = root + "/bin/hexciri-font-list"
with open(fl) as f:
    fl_s = f.read()
fl_orig = fl_s
_bsn = chr(92) + "n"
_sq = chr(39)
_fl_old = 'fc-list :spacing=100 -f "%{family[0]}' + _bsn + '" | grep -v -i -E ' + _sq + 'emoji|signwriting|hexciri' + _sq + ' | sort -u'
_fl_new = chr(10).join([
    "# Dual-width fonts (spacing 90) are monospace too: their Latin glyphs are one",
    "# cell wide and their CJK glyphs exactly two, which is how a terminal draws CJK.",
    "{",
    '  fc-list :spacing=100 -f "%{family[0]}' + _bsn + '"',
    '  fc-list :spacing=90 -f "%{family[0]}' + _bsn + '"',
    "} | grep -v -i -E 'emoji|signwriting|hexciri' | sort -u",
])
if _fl_old in fl_s:
    fl_s = fl_s.replace(_fl_old, _fl_new, 1)
    changed.append("font-list: also list dual-width (spacing 90) fonts (PR #16025, Maple Mono NF CN)")
elif _fl_new in fl_s:
    print("font-list dual-width query already present, skipping")
else:
    print("WARN: font-list single-spacing line not found, dual-width query NOT applied")
if fl_s != fl_orig:
    with open(fl, "w") as f:
        f.write(fl_s)

# 9. i18n label for the Maple row (PR #16025 adds the same key upstream).
# English falls back to the jsonc label without it; this keeps the catalog
# complete for translators. Inserted after the iosevka entry's close.
_i18n = root + "/default/i18n/en/menu.json"
with open(_i18n) as f:
    _i_lines = f.read().splitlines()
if any('"install.style.font.maple"' in _l for _l in _i_lines):
    print("i18n maple label already present, skipping")
else:
    _idx = next((k for k, _l in enumerate(_i_lines) if '"install.style.font.iosevka"' in _l), None)
    if _idx is None:
        print("WARN: i18n iosevka entry not found, maple label NOT added")
    else:
        _close = next((k for k in range(_idx, len(_i_lines)) if _i_lines[k].strip() == "},"), None)
        if _close is None:
            print("WARN: i18n iosevka close not found, maple label NOT added")
        else:
            _i_lines[_close + 1:_close + 1] = ['  "install.style.font.maple": {', '    "label": "Maple Mono CN"', '  },']
            with open(_i18n, "w") as f:
                f.write(chr(10).join(_i_lines) + chr(10))
            changed.append("i18n: Maple Mono CN label added (PR #16025)")

# 9. The forked menu jsonc must still parse exactly like the shell parses
# it (2026-11-24, Devi: whole Super+Alt+Space menu empty after update).
# MenuModel.js stripJsonc drops full-line // comments and trailing
# commas, then JSON.parse; ONE bad row makes the WHOLE file unparseable,
# readMenuJsonc returns null, and a fresh shell has no previous rows, so
# the menu opens on nothingHere. The cf3bb1a maple row did exactly this:
# its action held bare "Maple Mono NF CN" quotes (Python \" in the row
# literal collapses to a bare quote; JSON needs \"). Grep checks for row
# presence cannot see this. Parse here, in the fork, so a broken menu
# dies before placement, never live.
import json
_menu_raw = open(menu).read()
_menu_stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', _menu_raw, flags=re.M)
_menu_stripped = re.sub(r',(\s*[}\]])', r'\1', _menu_stripped)
try:
    _menu_parsed = json.loads(_menu_stripped)
except Exception as _e:
    raise SystemExit("menu jsonc does not parse, shell would show an empty menu: %s" % _e)
for _r in ('apps', 'appearance', 'trigger', 'setup', 'install', 'remove', 'update', 'learn', 'system'):
    if _r not in _menu_parsed:
        raise SystemExit("menu jsonc missing root entry %s, shell would show an empty menu" % _r)
if 'hexciri-font-set "Maple Mono NF CN"' not in _menu_parsed.get('install.style.font.maple', {}).get('action', ''):
    raise SystemExit("menu maple row action lost its quoted font name")
changed.append("menu jsonc parses (%d entries, 9 root entries)" % len(_menu_parsed))

for c in changed:
    print("menu audit: " + c)
if not changed:
    print("menu audit: no changes needed")
PY

# Syntax-check the patched Lua at install time, like the hexciri.lua check
# above: a bad bind would otherwise only surface as a Hyprland error at boot.
if command -v luac5.1 >/dev/null 2>&1; then
  luac5.1 -p "$FORK_OUT/default/hypr/bindings/applications.lua" && info "applications.lua patch OK (luac5.1 syntax OK)" || warn "luac5.1 syntax check failed on patched applications.lua, Hyprland will report the real error at boot if this is broken."
elif command -v luac >/dev/null 2>&1; then
  luac -p "$FORK_OUT/default/hypr/bindings/applications.lua" && info "applications.lua patch OK (luac syntax OK)" || warn "luac syntax check failed on patched applications.lua, Hyprland will report the real error at boot if this is broken."
else
  warn "No luac5.1/luac binary found, skipping Lua syntax check on patched applications.lua (the patch mirrors the existing Obsidian bind line for line)."
fi
if command -v luac5.1 >/dev/null 2>&1; then
  luac5.1 -p "$FORK_OUT/default/hypr/bindings/utilities.lua" && info "utilities.lua patch OK (luac5.1 syntax OK)" || warn "luac5.1 syntax check failed on patched utilities.lua, Hyprland will report the real error at boot if this is broken."
elif command -v luac >/dev/null 2>&1; then
  luac -p "$FORK_OUT/default/hypr/bindings/utilities.lua" && info "utilities.lua patch OK (luac syntax OK)" || warn "luac syntax check failed on patched utilities.lua, Hyprland will report the real error at boot if this is broken."
fi
bash -n "$FORK_OUT/bin/hexciri-capture-screenshot" || die "bash -n failed on rewritten $FORK_OUT/bin/hexciri-capture-screenshot"
info "Bind patch done: Super+Space apps / Super+Alt+Space menu swap, Super+Shift+M Spotify, gnome-calculator, btm (bottom package), Herdr removed, cliamp/omawrite/Obsidian binds removed (ncspot/ghostwriter/obsidian not wanted), screenshot via grim+slurp, touchpad bottom-right = right click, Super+Shift+S web search + Super+Shift+C calculator reclaimed from region webapps (Google Maps / Hey Calendar), Super+Ctrl+S Settings reclaimed from Share (Share now Super+Ctrl+Shift+S)"
