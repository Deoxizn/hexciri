#!/usr/bin/env python3
"""Patch Install > Style > Background to Strata (2026-11-24, Devi 14:16-14:17 MST).

Symptom: Install > Style > Background loads nothing.

Root cause, proven against live nyx HEAD 91299f9 and the sim7 fork output:
- Menu row install.style.background (default/hexciri/hexciri-menu.jsonc)
  action is `hexciri-theme-bg-install`.
- That bin, forked verbatim from upstream Omarchy, is:
    CURRENT_THEME_NAME=$(cat "$HOME/.local/state/hexciri/current/theme.name")
    THEME_USER_BACKGROUNDS="$HOME/.config/hexciri/backgrounds/$CURRENT_THEME_NAME"
    mkdir -p "$THEME_USER_BACKGROUNDS"
    folio "$THEME_USER_BACKGROUNDS"
- Folio is NOT installed in Hexciri v2 (Devi: file manager is Strata via
  GitHub, not Folio; no nautilus either), so the last line fails silently
  and nothing opens. Devi guessed exactly this at 14:17 MST.
- The fork rename only mapped folio -> strata for the uwsm-app invocation
  (`-- folio` -> `-- strata` in launch-files); the bare `folio <dir>` call
  in theme-bg-install was never touched. It is one of only two bare-folio
  calls left in the fork (the other is hexciri-install-gaming-retroarch
  `setsid folio "$HOME/Games"`, out of scope here, noted in the report).

Fix, in v2/install.sh only (fork patch, so patch_fingerprint changes and
the next hexciri update re-applies it):
1. bin/hexciri-theme-bg-install: `folio "$THEME_USER_BACKGROUNDS"` ->
   `hexciri-launch-files "$THEME_USER_BACKGROUNDS"` (the v2 file-manager
   launcher, strata via uwsm-app). No Folio/nautilus install.
2. bin/hexciri-launch-files: `exec setsid uwsm-app -- strata` ->
   `exec setsid uwsm-app -- strata "$@"`. The launcher dropped its
   arguments, so even after (1) Strata would have opened at its home
   folder, not the theme backgrounds folder. With zero args "$@" expands
   to nothing, so Super+Shift+F (no-arg call) is unchanged, and
   hexciri-launch-nautilus (exec hexciri-launch-files "$@") now forwards
   its path too. Strata accepts a path argument: hexciri-launch-files-cwd
   already passes strata "$(hexciri-cmd-terminal-cwd)".
3. Placement verification dies if either patch is missing.

Base: live nyx HEAD 91299f9, install.sh sha256
c8f305ea3a5043f9c98c44184acc8b3e80fa22cb04d7698109e81e531eacf4cd.
This script works on BG_INSTALL_PATH (default /tmp/bg-live/install.sh),
NOT on the shared ~/workspace/hexiri-2.0/v2/install.sh, because a sibling
agent (minimal re-apply) is concurrently editing that file from the same
base; the push script re-fetches live HEAD and pushes from a separate
source dir, so neither agent clobbers the other.
"""
import hashlib
import os
import sys

P = os.environ.get("BG_INSTALL_PATH", "/tmp/bg-live/install.sh")
BASE_SHA = "c8f305ea3a5043f9c98c44184acc8b3e80fa22cb04d7698109e81e531eacf4cd"

data = open(P, "rb").read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, \
    f"install.sh is not live nyx HEAD 91299f9 ({hashlib.sha256(data).hexdigest()}), refusing to patch"
s = data.decode()
orig = s

anchor = 'step "Patching dock pinned list: Strata, Spotify, Brave Origin, Zed, Kitty"'
assert s.count(anchor) == 1, "dock step anchor not found exactly once"

block = '''# --- Patch background install to Strata (2026-11-24, Devi: Install > Style > Background loads nothing) ---
# Upstream bin/omarchy-theme-bg-install (menu row install.style.background,
# action hexciri-theme-bg-install) ends with bare `folio "$THEME_USER_BACKGROUNDS"`.
# Folio is not installed in Hexciri v2 (Devi: file manager is Strata via GitHub,
# not Folio; no nautilus either), so the command fails silently and nothing
# opens. The fork rename only mapped folio -> strata for the uwsm-app
# invocation in launch-files; the bare `folio <dir>` call here was never
# touched. Fix: open the folder with hexciri-launch-files (the v2
# file-manager launcher, strata via uwsm-app). That launcher dropped its
# arguments, so it is patched here too to forward "$@" to strata (zero
# args expands to nothing, so Super+Shift+F is unchanged). Strata accepts
# a path argument: hexciri-launch-files-cwd already passes
# strata "$(hexciri-cmd-terminal-cwd)". No Folio/nautilus install.
step "Patching background install to Strata file manager"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
root = sys.argv[1]
# 1. Background install: folio -> Strata launcher, with the folder path.
path = root + "/bin/hexciri-theme-bg-install"
with open(path) as f:
    s = f.read()
orig = s
old = 'folio "$THEME_USER_BACKGROUNDS"'
assert s.count(old) == 1, "theme-bg-install folio anchor not found"
s = s.replace(old, 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"', 1)
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("theme-bg-install: opens backgrounds folder with hexciri-launch-files (Strata), not folio")
else:
    print("theme-bg-install: Strata launcher already applied, skipping")
# 2. File-manager launcher: forward its arguments to strata.
path = root + "/bin/hexciri-launch-files"
with open(path) as f:
    s = f.read()
orig = s
old = "exec setsid uwsm-app -- strata"
assert s.count(old) == 1, "launch-files strata anchor not found"
s = s.replace(old, 'exec setsid uwsm-app -- strata "$@"', 1)
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("launch-files: forwards \\"$@\\" to strata (folder opens at the requested path)")
else:
    print("launch-files: \\"$@\\" forwarding already applied, skipping")
PY

'''
s = s.replace(anchor, block + anchor, 1)

# Placement verification, right after the WidgetButton check.
old_verify = '''grep -q 'signal pressed(int button, int modifiers)' "$HEXCIRI_PATH/shell/Ui/WidgetButton.qml" || die "WidgetButton does not forward click modifiers, Shift+right-click settings cannot be told from plain right-click (2026-11-24)"'''
assert s.count(old_verify) == 1, "WidgetButton verify anchor not found exactly once"
new_verify = old_verify + '''
grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"
grep -q 'strata "$@"' "$HEXCIRI_PATH/bin/hexciri-launch-files" || die "launch-files drops its path argument, background folder opens at Strata home instead of the theme backgrounds folder (2026-11-24)"'''
s = s.replace(old_verify, new_verify, 1)

assert s != orig
with open(P, "w") as f:
    f.write(s)
print("patched", P)
print("new sha256:", hashlib.sha256(s.encode()).hexdigest())
print("lines:", s.count("\n"))
