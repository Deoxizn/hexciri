#!/bin/bash
# Hexciri fork patch 20: dock window matching (#20344) — the noAnim enabler
# plus the PR's bringForward changes, against the pin baseline.
#
# Two upstream pieces, both in shell/plugins/dock/Dock.qml only:
#
# 1. The ~55-line noAnim helper from omarchy commit 8807715c7 (#20126,
#    "Make shell UI interactions snappier"): pendingNoAnimUnsets /
#    scheduleNoAnimUnset / flushNoAnimUnsets / the 400 ms single-shot
#    noAnimUnsetTimer / Component.onDestruction flush, plus the bringForward
#    rewrite from a `sleep 0.4` shell command (Util.execDetached +
#    "hyprctl dispatch ...") to direct Hyprland.dispatch calls. Without
#    this, a restored minimized window can be left with no_anim stuck on
#    under rapid clicks, because the sleep-based unset is racy.
#
# 2. The Dock.qml bringForward changes from open PR #20344 (last reviewed
#    commit bb088cc, "dock window matching"): a workspace argument threaded
#    through activate() so a minimized window restores to the clicked
#    dock's workspace instead of always the focused monitor's, an
#    if (!window) return guard plus a guarded toplevel.activate() fallback,
#    and removal of omarchy-minimized-from-* tags on restore (the tag the
#    minimize helper leaves behind, so a restored window stops being
#    treated as minimized).
#
# Adaptation notes (vs upstream verbatim):
#   * Tag names are hexciri-minimized-from-* here, not
#     omarchy-minimized-from-*: the live rename map turns the generic
#     `omarchy-` prefix into `hexciri-`, and the fork's
#     hexciri-hyprland-window-minimize tags windows hexciri-minimized-from-N.
#     The regex matches the runtime tag; at the pin, windows carry no `tags`
#     field at all, so `window.tags || []` is an empty loop until #20344's
#     rawWindows rework lands — the loop is future-proofing, not live yet.
#   * activate()'s pickClickWindow map keeps `window.toplevel.activated`:
#     #20344 reads `window.activated`, which only exists on the windows its
#     rawWindows rework builds. Pin windows carry activation on the
#     toplevel; reading window.activated here would be undefined for every
#     window and break click cycling.
#   * #19970's bringForward address validation is NOT in this patch: it
#     lands in patch 23, built against this patch's output. This patch
#     keeps the pin's address handling (empty -> toplevel.activate, add
#     the 0x prefix) so patch 23's hunk applies cleanly on top.
#   * The PR's DockWindow.qml callers (bringForward with a workspace id
#     from the window picker / context menu) and its pidProc onDestruction
#     line are NOT ported: they belong to the full #20344 port (DockModel.js
#     rawWindows, DockWindow.qml picker), not this enabler backport. The
#     only in-tree caller here is activate(), which now passes the
#     workspace through.
#
# Standalone: bash v2/patches/20-dock-window-matching.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is QML, not bash, so the end-of-patch
# check is qmllint when present (warning-only: it cannot resolve the
# qs.* imports outside the running shell). bash -n would fail on it by
# construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "20-dock-window-matching.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}

# --- Dock window matching: noAnim helper (#20126) + bringForward (#20344) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The noAnim helper, verbatim from #20126 (commit 8807715c7). No
# omarchy-named strings in it, so no rename adaptation.
NOANIM_HELPER = """  property var pendingNoAnimUnsets: []

  function scheduleNoAnimUnset(address) {
    if (pendingNoAnimUnsets.indexOf(address) < 0)
      pendingNoAnimUnsets = pendingNoAnimUnsets.concat([address])
    noAnimUnsetTimer.restart()
  }

  function flushNoAnimUnsets() {
    noAnimUnsetTimer.stop()
    var addresses = pendingNoAnimUnsets
    pendingNoAnimUnsets = []
    for (var i = 0; i < addresses.length; i++)
      Hyprland.dispatch("hl.dsp.window.set_prop({ prop = \\"no_anim\\", value = \\"unset\\", window = \\"address:" + addresses[i] + "\\" })")
  }

  // If the dock is disabled or reloaded within 400ms of restoring a minimized
  // window, flush pending resets immediately so no_anim isn't left stuck on.
  Component.onDestruction: flushNoAnimUnsets()

  Timer {
    id: noAnimUnsetTimer
    interval: 400
    repeat: false
    onTriggered: root.flushNoAnimUnsets()
  }

"""

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # activate(): thread the workspace argument through to bringForward.
    # #20344's map reads window.activated; the pin's windows carry
    # activation on the toplevel, so that half is deliberately NOT ported
    # (see header). The fallback to the focused monitor keeps the
    # single-arg call from DockWindow.qml working unchanged.
    ("shell/plugins/dock/Dock.qml",
     "  function activate(item) {\n"
     "    if (!item) return\n"
     "    var monitor = Hyprland.focusedMonitor\n"
     "    var workspaceId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
     "    var mode = root.appLibrary ? root.appLibrary.dockClickMode(item.key) : \"\"\n"
     "    var index = DockModel.pickClickWindow(mode, item.windows.map(function(window) {\n"
     "      return { workspaceId: window.workspaceId, minimized: window.minimized, activated: window.toplevel.activated }\n"
     "    }), workspaceId)\n"
     "    if (index < 0) {\n"
     "      root.launch(item)\n"
     "      return\n"
     "    }\n"
     "    root.bringForward(item.windows[index])\n"
     "  }",
     "  function activate(item, targetWorkspaceId) {\n"
     "    if (!item) return\n"
     "    var workspaceId = Number(targetWorkspaceId)\n"
     "    if (!(workspaceId >= 1)) {\n"
     "      var monitor = Hyprland.focusedMonitor\n"
     "      workspaceId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
     "    }\n"
     "    var mode = root.appLibrary ? root.appLibrary.dockClickMode(item.key) : \"\"\n"
     "    var index = DockModel.pickClickWindow(mode, item.windows.map(function(window) {\n"
     "      return { workspaceId: window.workspaceId, minimized: window.minimized, activated: window.toplevel.activated }\n"
     "    }), workspaceId)\n"
     "    if (index < 0) {\n"
     "      root.launch(item)\n"
     "      return\n"
     "    }\n"
     "    root.bringForward(item.windows[index], workspaceId)\n"
     "  }",
     "Dock activate: thread target workspace through to bringForward"),
    # The noAnim helper, inserted after activate() and ahead of
    # bringForward (verbatim #20126). Anchored on activate()'s closing
    # lines rather than the bringForward comment, because the next edit
    # rewrites that comment: anchoring here keeps the re-run "already
    # present" check true after the comment changes.
    ("shell/plugins/dock/Dock.qml",
     "    root.bringForward(item.windows[index], workspaceId)\n"
     "  }\n"
     "\n",
     "    root.bringForward(item.windows[index], workspaceId)\n"
     "  }\n"
     "\n"
     + NOANIM_HELPER,
     "Dock: add noAnim helper (schedule/flushNoAnimUnsets, 400ms timer)"),
    # bringForward: #20126's in-process dispatch rewrite merged with
    # #20344's workspace argument, guards, and tag removal. Address
    # handling stays the pin's (no #19970 validation yet; patch 23).
    ("shell/plugins/dock/Dock.qml",
     "  // A window the dock brings forward lands on top of the others, focused; a\n"
     "  // minimized one first comes back to the workspace in front of the user.\n"
     "  function bringForward(window) {\n"
     "    var address = String(window.address || \"\")\n"
     "    if (!address) {\n"
     "      window.toplevel.activate()\n"
     "      return\n"
     "    }\n"
     "    if (address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
     "    var target = \"window = \\\"address:\" + address + \"\\\"\"\n"
     "    var steps = []\n"
     "    var after = []\n"
     "    if (window.minimized) {\n"
     "      var monitor = Hyprland.focusedMonitor\n"
     "      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
     "      if (!(workspace >= 1)) return\n"
     "      // A restored window is simply there again, without animating in.\n"
     "      steps.push(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"1\\\", \" + target + \" })\")\n"
     "      steps.push(\"hl.dsp.window.move({ workspace = \\\"\" + workspace + \"\\\", \" + target + \" })\")\n"
     "      after.push(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"unset\\\", \" + target + \" })\")\n"
     "    }\n"
     "    steps.push(\"hl.dsp.focus({ \" + target + \" })\")\n"
     "    steps.push(\"hl.dsp.window.alter_zorder({ mode = \\\"top\\\", \" + target + \" })\")\n"
     "    var dispatch = function(step) { return \"hyprctl dispatch \" + Util.shellQuote(step) }\n"
     "    var command = steps.map(dispatch).join(\" && \")\n"
     "    if (after.length > 0) command += \"; sleep 0.4; \" + after.map(dispatch).join(\"; \")\n"
     "    Util.execDetached(command)\n"
     "  }",
     "  // A window the dock brings forward lands on top of the others, focused; a\n"
     "  // minimized one first comes back to the clicked dock's workspace.\n"
     "  function bringForward(window) {\n"
     "    if (!window) return\n"
     "    var address = String(window.address || \"\")\n"
     "    if (!address) {\n"
     "      if (window.toplevel && typeof window.toplevel.activate === \"function\") window.toplevel.activate()\n"
     "      return\n"
     "    }\n"
     "    if (address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
     "    var target = \"window = \\\"address:\" + address + \"\\\"\"\n"
     "    if (window.minimized) {\n"
     "      var workspace = arguments.length > 1 ? Number(arguments[1]) : -1\n"
     "      if (!(workspace >= 1)) {\n"
     "        var monitor = Hyprland.focusedMonitor\n"
     "        workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
     "      }\n"
     "      if (!(workspace >= 1)) return\n"
     "      // A restored window is simply there again, without animating in.\n"
     "      Hyprland.dispatch(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"1\\\", \" + target + \" })\")\n"
     "      var tags = window.tags || []\n"
     "      for (var i = 0; i < tags.length; i++) {\n"
     "        var tag = String(tags[i] || \"\")\n"
     "        if (/^hexciri-minimized-from-[0-9]+$/.test(tag))\n"
     "          Hyprland.dispatch(\"hl.dsp.window.tag({ tag = \\\"-\" + tag + \"\\\", \" + target + \" })\")\n"
     "      }\n"
     "      Hyprland.dispatch(\"hl.dsp.window.move({ workspace = \\\"\" + workspace + \"\\\", \" + target + \" })\")\n"
     "      scheduleNoAnimUnset(address)\n"
     "    }\n"
     "    Hyprland.dispatch(\"hl.dsp.focus({ \" + target + \" })\")\n"
     "    Hyprland.dispatch(\"hl.dsp.window.alter_zorder({ mode = \\\"top\\\", \" + target + \" })\")\n"
     "  }",
     "Dock bringForward: in-process dispatch + workspace arg + guards + tag removal"),
]

for rel, old, new, label in REPLACEMENTS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if new in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

for label in changed:
    print("patched: %s" % label)
print("dock-window-matching patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited file. It is QML, not bash, so bash -n would fail
# on it by construction and is deliberately not used here. qmllint cannot
# resolve the qs.* imports outside the running shell, so it is warning-only.
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/dock/Dock.qml" || warn "qmllint reported issues on patched Dock.qml (warning-only)"
else
  warn "qmllint not found, skipping Dock.qml syntax check"
fi
info "  dock-window-matching: dock restores minimized windows in-process with no_anim unset (#20126 helper + #20344 bringForward)"
