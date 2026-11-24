#!/usr/bin/env bash
# Hexciri fork patch 04: WidgetButton forwards click modifiers.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/04-widgetbutton.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "04-widgetbutton.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Patch WidgetButton to forward click modifiers (2026-11-24) ---
# Upstream WidgetButton's pressed signal carries only the button:
# onClicked passes mouse.button, modifiers are dropped. A widget
# therefore cannot tell Shift+right-click from a plain right-click.
# Nyxiri clock/weather need that distinction (2026-11-24, Devi:
# right-click opening settings stole the format swap): plain
# right-click cycles the clock format / sends the weather notification,
# Shift+right-click opens the standalone settings window. Forwarding is
# backward compatible: handlers that only take the button ignore the
# extra signal arg, and the triggerPress(button) callers in Bar.qml /
# KeyboardPanel keep working, modifiers defaults to Qt.NoModifier.
step "Patching WidgetButton to forward click modifiers"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
root = sys.argv[1]
path = root + "/shell/Ui/WidgetButton.qml"
with open(path) as f:
    s = f.read()
orig = s
old_sig = "  signal pressed(int button)"
assert "signal pressed(int button, int modifiers)" in s or s.count(old_sig) == 1, "WidgetButton pressed signal anchor not found"
s = s.replace(old_sig, """  // Hexciri (2026-11-24): pressed carries the click modifiers too,
  // so a widget can tell Shift+right-click (open its settings) from a
  // plain right-click (clock: cycle format, weather: status notification).
  signal pressed(int button, int modifiers)""", 1)
old_trig = """  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }"""
assert "function triggerPress(button, modifiers)" in s or s.count(old_trig) == 1, "WidgetButton triggerPress anchor not found"
s = s.replace(old_trig, """  function triggerPress(button, modifiers) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button, modifiers !== undefined ? modifiers : Qt.NoModifier)
  }""", 1)
old_click = "    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button) }"
assert "triggerPress(mouse.button, mouse.modifiers)" in s or s.count(old_click) == 1, "WidgetButton onClicked anchor not found"
s = s.replace(old_click, "    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button, mouse.modifiers) }", 1)
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("WidgetButton: pressed forwards click modifiers (Shift+right-click distinguishable)")
else:
    print("WidgetButton: modifiers forwarding already applied, skipping")
PY
