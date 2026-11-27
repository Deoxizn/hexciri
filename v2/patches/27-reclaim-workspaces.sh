#!/usr/bin/env bash
# Hexciri fork patch 27: reclaim workspaces left without a monitor.
# Forward-port of omarchy PR #20185 (commit 2dfb187fa,
# "Reclaim workspaces left without a monitor") into
# default/hypr/monitor-workspaces.lua.
#
# What it does (PR behavior, unchanged): a workspace whose monitor is nil
# (left behind by an unplug) is now reclaimed to the focused monitor on
# focus / move-window instead of being unreachable. The old reclaim() guard
# early-returned when workspace.monitor was nil, so Super+<n> / move-window
# never brought it home. The new guard only returns when the workspace is
# already on the target monitor, moves it home, and only settles the old
# monitor when there was one (nil-safe `if away`).
#
# Fork adaptation: none. The hunk is rename-free (no `omarchy` strings in
# the changed lines) and Hyprland-side Lua, not Nyxiri QML, so it applies
# despite the stock bar being replaced. This is NOT the fork's monitor
# reboot bug (DP 60Hz loop / monitors.lua vs Hexciri Settings writers) and
# does not fix it; it only covers workspaces orphaned by an unplug.
#
# Tests: upstream's test/shell.d/hyprland-monitor-workspaces-test.sh is NOT
# in FORK_OUT (fork-shell.sh extracts only listed subsets; test/ is not
# one), and no existing patch touches tests, so this patch does not edit a
# test file. Verification is the upstream test's new `reclaim_monitorless`
# case replayed in sim (monitorless workspace comes home on focus and on
# move-window, windows stay reachable) plus a diff of patched vs unpatched
# proving only the intended changes. See the coordinator's sim notes.
#
# Standalone: bash v2/patches/27-reclaim-workspaces.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is Lua only, so bash -n and
# node --check would fail on it by construction and are deliberately not
# used here. No lua/luac interpreter is present in the sim VM, so the
# end-of-patch check is the anchor-exactness above plus the sim harness;
# qmllint does not apply (no QML touched).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "27-reclaim-workspaces.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Reclaim workspaces left without a monitor, omarchy PR #20185 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # reclaim(): a monitorless workspace is no longer an early return;
    # only a workspace already on the target monitor is.
    ("default/hypr/monitor-workspaces.lua",
     "  if not workspace or not workspace.monitor or workspace.monitor.name == monitor.name then\n"
     "    return\n"
     "  end",
     "  if not workspace or (workspace.monitor and workspace.monitor.name == monitor.name) then\n"
     "    return\n"
     "  end",
     "monitor-workspaces.lua reclaim(): reclaim a monitorless workspace"),
    # reclaim(): only settle the old monitor when there was one.
    ("default/hypr/monitor-workspaces.lua",
     "  local monitors = connected()\n"
     "  settle(away, monitors, assign(monitors))\n"
     "end",
     "  if away then\n"
     "    local monitors = connected()\n"
     "    settle(away, monitors, assign(monitors))\n"
     "  end\n"
     "end",
     "monitor-workspaces.lua reclaim(): settle old monitor only if it exists"),
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
print("reclaim-workspaces patch: %d file edits applied" % len(changed))
PY

info "  reclaim-workspaces: workspaces orphaned by an unplug are reclaimed to the focused monitor (PR #20185)"
