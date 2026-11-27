#!/usr/bin/env bash
# Hexciri fork patch 59: build plugin services before panels and bar
# widgets load. Forward-port of omarchy PR #20396 ("build plugin services
# before panels and bar widgets load") into shell/shell.qml.
# PR diff verified 2026-11-27 against
# https://github.com/omacom/omarchy/pull/20396.diff (3 files: shell.qml
# plus docs/testing.md and test/shell.d/lock-appear-budget-test.sh, which
# the fork does not ship, so only the shell.qml hunk ports).
#
# What it does (PR behavior, unchanged): the three separate
# onPluginsChanged handlers (services, panel entries, plugin widgets) run
# in registration order, which Quickshell does not guarantee, so the lock,
# polkit, notifications and idle services could wait behind the whole bar
# compiling before they could answer. One handler now runs them in our
# order: syncPluginApis, then _syncServices, syncPanelEntries and
# syncPluginWidgets. Services are built synchronously, and a synchronous
# load waits for every asynchronous one queued before it. Upstream's
# lock-appear budget tightened from 400% to 250% of shell-answer time on
# the back of this (~1.7x today, was 2.6-3.2x); the fork carries no such
# test, so the ratio is not re-asserted here.
#
# Fork adaptation: none. The three Connections blocks in the fork match
# upstream's diff context exactly (rename map only), so the merge ports
# verbatim. The onScanFinished handler already calls the three syncs in
# the same order and is untouched.
#
# Standalone: bash v2/patches/59-plugin-services-first.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is QML, so bash -n does not apply.
# qmllint when present, warning only (it fails on missing Quickshell
# imports even for valid files).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "59-plugin-services-first.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
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
CHANGED=0

step "Building plugin services before panels and bar widgets (PR #20396)"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 59 plugin services first edit failed"; }
import sys

fork = sys.argv[1]


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


rel = "shell/shell.qml"
try:
    with open(fork + "/" + rel, encoding="utf-8") as f:
        s = f.read()
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping (services-before-panels order)" % rel)
    sys.exit(0)

if "One handler, so the order is ours" in s:
    print("services-before-panels: already present, skipping")
    sys.exit(0)

# --- 1. Merge the three onPluginsChanged handlers into the first one. ---
old_first = (
    "  Connections {\n"
    "    target: shell.pluginRegistry\n"
    "    function onPluginsChanged() {\n"
    "      shell.syncPluginApis()\n"
    "      if (!shell.pluginReloading) shell._syncServices()\n"
    "    }\n"
    "  }\n"
)
new_first = (
    "  // One handler, so the order is ours: services before panels and bar\n"
    "  // widgets. Services are built synchronously, and a synchronous load waits\n"
    "  // for every asynchronous one queued before it. Behind the panels and\n"
    "  // widgets, the lock, polkit, notifications and idle all waited for the\n"
    "  // whole bar to compile before they could answer.\n"
    "\n"
    "  Connections {\n"
    "    target: shell.pluginRegistry\n"
    "    function onPluginsChanged() {\n"
    "      shell.syncPluginApis()\n"
    "      if (shell.pluginReloading) return\n"
    "      shell._syncServices()\n"
    "      shell.syncPanelEntries()\n"
    "      shell.syncPluginWidgets()\n"
    "    }\n"
    "  }\n"
)
if s.count(old_first) != 1:
    _die("services onPluginsChanged handler occurs %d times, want exactly 1" % s.count(old_first))
s = s.replace(old_first, new_first, 1)

# --- 2. Drop the now-redundant panel-entries handler. ---
old_panels = (
    "  Connections {\n"
    "    target: shell.pluginRegistry\n"
    "    function onPluginsChanged() { if (!shell.pluginReloading) shell.syncPanelEntries() }\n"
    "  }\n"
    "\n"
    "  Instantiator {\n"
)
new_panels = "  Instantiator {\n"
if s.count(old_panels) != 1:
    _die("panel-entries onPluginsChanged handler occurs %d times, want exactly 1" % s.count(old_panels))
s = s.replace(old_panels, new_panels, 1)

# --- 3. Drop the now-redundant plugin-widgets handler. ---
old_widgets = (
    "  // widgets use the same first-party manifest contract as third-party widgets.\n"
    "  Connections {\n"
    "    target: shell.pluginRegistry\n"
    "    function onPluginsChanged() { if (!shell.pluginReloading) shell.syncPluginWidgets() }\n"
    "  }\n"
    "\n"
    "  property var pluginWidgetComponents: ({})\n"
)
new_widgets = (
    "  // widgets use the same first-party manifest contract as third-party widgets.\n"
    "\n"
    "  property var pluginWidgetComponents: ({})\n"
)
if s.count(old_widgets) != 1:
    _die("plugin-widgets onPluginsChanged handler occurs %d times, want exactly 1" % s.count(old_widgets))
s = s.replace(old_widgets, new_widgets, 1)

# --- validation: exactly one handler left, calling all three syncs. ---
if s.count("function onPluginsChanged()") != 1:
    _die("onPluginsChanged occurs %d times after edit, want exactly 1" % s.count("function onPluginsChanged()"))
for call in ("shell._syncServices()", "shell.syncPanelEntries()", "shell.syncPluginWidgets()"):
    if call not in s:
        _die("%s lost after edit" % call)
if "if (shell.pluginReloading) return" not in s:
    _die("pluginReloading early return lost after edit")

with open(fork + "/" + rel, "w", encoding="utf-8") as f:
    f.write(s)
print("patched: services before panels and bar widgets in %s (PR #20396)" % rel)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# qmllint when present, warning only (missing Quickshell imports fail it
# even for valid files).
if command -v qmllint >/dev/null 2>&1; then
  if [ -f "$FORK_OUT/shell/shell.qml" ]; then
    qmllint "$FORK_OUT/shell/shell.qml" 2>&1 | head -5 || warn "qmllint reported on shell.qml"
  fi
else
  warn "qmllint not found, skipping QML parse check"
fi

printf 'plugin services first patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 59: plugin services before panels/widgets (PR #20396)"
