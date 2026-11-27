#!/usr/bin/env bash
# Hexciri fork patch 58: load on-demand overlays and unplaced bar widgets
# lazily. Forward-port of omarchy PR #20410 ("load on-demand overlays and
# unplaced bar widgets lazily") into shell/plugins/emojis/Emojis.qml,
# shell/plugins/emojis/manifest.json, shell/plugins/reminders/manifest.json
# and shell/shell.qml.
# PR diff verified 2026-11-27 against
# https://github.com/omacom/omarchy/pull/20410.diff (4 files, no test hunks).
#
# What it does (PR behavior, unchanged):
#  - emojis + reminders overlays drop "keepLoaded": true from their
#    manifests, so the shell no longer compiles them at startup; they load
#    on first summon instead.
#  - Emojis.qml gains an emojisLoaded flag: the empty state ("no matches")
#    only shows once the emoji list has actually loaded, so a lazily loaded
#    overlay does not flash "no matches" while its data is still arriving.
#  - shell.qml syncPluginWidgets: a bar widget that is not placed in the bar
#    keeps only its metadata registered (bar editor and plugin listings
#    still see it) without compiling its QML tree until it is placed. The
#    drop/unload paths learn about those metadata-only registrations so a
#    disabled or removed plugin does not leave a stale registration behind.
#
# Fork adaptation: the hunks port verbatim. The fork's Emojis.qml already
# reads `visible: root.filteredEmojis.length === 0` (patch 43 dropped the
# displayModel ListModel and bound the grid to filteredEmojis), and the
# fork's syncPluginWidgets cleanup already uses the trackedIds form (patch
# 24), both matching upstream's diff context exactly. The only fork-side
# difference is whitespace: patch 24's cleanup block is compact (no blank
# lines between statements) where upstream's has them, so the cleanup edit
# is done as surgical replacements on the fork's exact text, carrying
# upstream's logic verbatim. No rename impact in the ported hunks.
#
# Standalone: bash v2/patches/58-lazy-overlays.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: all edited files are QML/JSON, so bash -n does not
# apply. Manifests are validated with python json.load below; QML gets
# qmllint when present, warning only (it fails on missing Quickshell
# imports even for valid files).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "58-lazy-overlays.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

step "Lazy-loading on-demand overlays and unplaced bar widgets (PR #20410)"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 58 lazy overlays edit failed"; }
import json
import sys

fork = sys.argv[1]


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _read(rel):
    try:
        with open(fork + "/" + rel, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping" % rel)
        return None


def _write(rel, s):
    with open(fork + "/" + rel, "w", encoding="utf-8") as f:
        f.write(s)


def _replace_once(s, rel, old, new, what):
    """If new is already there, skip; elif old occurs exactly once, replace;
    else die. Returns (new_s, changed_bool)."""
    if new in s:
        print("%s: already present, skipping" % what)
        return s, False
    if s.count(old) != 1:
        _die("anchor for %s occurs %d times, want exactly 1 in %s"
             % (what, s.count(old), rel))
    return s.replace(old, new, 1), True


# --- 1. shell/plugins/emojis/Emojis.qml: emojisLoaded flag ---
rel = "shell/plugins/emojis/Emojis.qml"
s = _read(rel)
if s is not None:
    changed_any = False
    s, c = _replace_once(
        s, rel,
        "  property var emojis: []\n",
        "  property var emojis: []\n  property bool emojisLoaded: false\n",
        "Emojis.qml emojisLoaded property")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        "    root.emojis = EmojiSearch.parseEmojis(raw)\n",
        "    root.emojis = EmojiSearch.parseEmojis(raw)\n    root.emojisLoaded = true\n",
        "Emojis.qml emojisLoaded set in loadEmojis")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        "            visible: root.filteredEmojis.length === 0\n",
        "            visible: root.emojisLoaded && root.filteredEmojis.length === 0\n",
        "Emojis.qml empty state waits for load")
    changed_any = changed_any or c
    if changed_any:
        if s.count("emojisLoaded") != 3:
            _die("emojisLoaded occurs %d times in %s, want exactly 3"
                 % (s.count("emojisLoaded"), rel))
        _write(rel, s)
        print("patched: Emojis.qml emojisLoaded flag in %s (PR #20410)" % rel)

# --- 2. Overlay manifests: drop keepLoaded ---
for rel in ("shell/plugins/emojis/manifest.json",
            "shell/plugins/reminders/manifest.json"):
    s = _read(rel)
    if s is None:
        continue
    if '"keepLoaded"' not in s:
        print("%s: keepLoaded already removed, skipping" % rel)
        continue
    if s.count('  "keepLoaded": true,\n') != 1:
        _die('keepLoaded line occurs %d times, want exactly 1 in %s'
             % (s.count('  "keepLoaded": true,\n'), rel))
    s = s.replace('  "keepLoaded": true,\n', "", 1)
    try:
        json.loads(s)
    except json.JSONDecodeError as e:
        _die("%s is not valid JSON after keepLoaded removal: %s" % (rel, e))
    _write(rel, s)
    print("patched: keepLoaded removed from %s (PR #20410)" % rel)

# --- 3. shell/shell.qml: lazy unplaced bar widgets ---
rel = "shell/shell.qml"
s = _read(rel)
if s is not None:
    changed_any = False

    # 3a. Metadata-only registration for unplaced widgets (verbatim
    # upstream insert, anchored on the meta block + in-flight comment).
    old_meta = (
        "        firstParty: !!manifest.__isFirstParty\n"
        "      }\n"
        "\n"
        "      // A load already in flight for this URL registers itself when it\n"
    )
    new_meta = (
        "        firstParty: !!manifest.__isFirstParty\n"
        "      }\n"
        "\n"
        "      var placed = shell.pluginRegistry.inBar(pluginId)\n"
        "\n"
        "      if (!placed) {\n"
        "\n"
        "        // Keep metadata in the registry so the bar editor and plugin listings\n"
        "        // still see the widget, without compiling its QML tree until placed.\n"
        "\n"
        "        if (existing) {\n"
        "\n"
        "          if (existing.component && typeof existing.component.destroy === \"function\")\n"
        "\n"
        "            existing.component.destroy()\n"
        "\n"
        "          shell.setPluginWidgetComponent(registryKey, null)\n"
        "\n"
        "        }\n"
        "\n"
        "        shell.barWidgetRegistry.register(registryKey, null, meta)\n"
        "\n"
        "        continue\n"
        "\n"
        "      }\n"
        "\n"
        "\n"
        "      // A load already in flight for this URL registers itself when it\n"
    )
    s, c = _replace_once(s, rel, old_meta, new_meta,
                         "syncPluginWidgets unplaced-widget lazy branch")
    changed_any = changed_any or c

    # 3b. Cleanup: include metadata-only registrations. The fork's
    # post-24 block is compact (no blank lines between statements), so
    # this is surgical on the fork's exact text, upstream logic verbatim.
    s, c = _replace_once(
        s, rel,
        "    // Drop registrations and in-flight loads for plugins that are no longer present or enabled.\n",
        "    // Drop registrations and in-flight loads for plugins that are no longer present or enabled,\n"
        "    // including metadata-only registrations for unplaced widgets not tracked in pluginWidgetComponents.\n",
        "syncPluginWidgets cleanup comment")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        "    var trackedIds = Object.keys(pluginWidgetComponents)\n",
        "    var trackedIds = Object.keys(pluginWidgetComponents)\n"
        "    var registered = shell.barWidgetRegistry.widgets || ({})\n"
        "    for (var rid in registered) {\n"
        "      if (registered[rid] && registered[rid].metadata && registered[rid].metadata.source === \"plugin\"\n"
        "          && trackedIds.indexOf(rid) === -1)\n"
        "        trackedIds.push(rid)\n"
        "    }\n",
        "syncPluginWidgets cleanup tracks metadata-only registrations")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        "      if (shell.barWidgetRegistry.has(id)) shell.barWidgetRegistry.unregister(id)\n"
        "      if (!nextWidgets) {\n"
        "        nextWidgets = ({})\n"
        "        for (var k in pluginWidgetComponents) nextWidgets[k] = pluginWidgetComponents[k]\n"
        "      }\n"
        "      delete nextWidgets[id]\n",
        "      if (shell.barWidgetRegistry.has(id)) shell.barWidgetRegistry.unregister(id)\n"
        "      if (pluginWidgetComponents[id] !== undefined) {\n"
        "        if (!nextWidgets) {\n"
        "          nextWidgets = ({})\n"
        "          for (var k in pluginWidgetComponents) nextWidgets[k] = pluginWidgetComponents[k]\n"
        "        }\n"
        "        delete nextWidgets[id]\n"
        "      }\n",
        "syncPluginWidgets cleanup only drops tracked components")
    changed_any = changed_any or c

    # 3c. Unload: also unregister metadata-only registrations.
    s, c = _replace_once(
        s, rel,
        "  function unloadPluginWidgets() {\n"
        "    for (var id in pluginWidgetComponents) shell.barWidgetRegistry.unregister(id)\n"
        "    pluginWidgetComponents = ({})\n"
        "  }\n",
        "  function unloadPluginWidgets() {\n"
        "    var registered = shell.barWidgetRegistry.widgets || ({})\n"
        "    var ids = Object.keys(pluginWidgetComponents)\n"
        "    for (var rid in registered) {\n"
        "      if (registered[rid] && registered[rid].metadata && registered[rid].metadata.source === \"plugin\"\n"
        "          && ids.indexOf(rid) === -1)\n"
        "        ids.push(rid)\n"
        "    }\n"
        "    for (var i = 0; i < ids.length; i++) shell.barWidgetRegistry.unregister(ids[i])\n"
        "    pluginWidgetComponents = ({})\n"
        "  }\n",
        "unloadPluginWidgets unregisters metadata-only registrations")
    changed_any = changed_any or c

    if changed_any:
        _write(rel, s)
        print("patched: syncPluginWidgets lazy unplaced widgets in %s (PR #20410)" % rel)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# qmllint when present, warning only (missing Quickshell imports fail it
# even for valid files).
if command -v qmllint >/dev/null 2>&1; then
  for _q in "$FORK_OUT/shell/plugins/emojis/Emojis.qml" "$FORK_OUT/shell/shell.qml"; do
    [ -f "$_q" ] && qmllint "$_q" 2>&1 | head -5 || warn "qmllint reported on $_q"
  done
else
  warn "qmllint not found, skipping QML parse check"
fi

printf 'lazy overlays patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 58: lazy overlays + unplaced bar widgets (PR #20410)"
