#!/usr/bin/env bash
# Hexciri fork patch 32: close stdio on theme-set snapshot cleanup.
# Forward-port of omarchy PR #20133 ("Close stdio on background snapshot
# cleanup in omarchy-theme-set", commit 4dc3e4d1f). One-liner x3,
# ride-along with the theme port.
#
# What it does (upstream behavior, unchanged): the `(sleep 3; rm ...)`
# background snapshot-cleanup jobs in theme-set now close stdin/stdout/
# stderr and fd 9 (`</dev/null >/dev/null 2>&1 9>&-`), so callers
# capturing theme-set output no longer hang 3s waiting on the background
# job's inherited descriptors.
#
# Fork note — dispatcher symlink: on live nyx bin/hexciri-theme-set is a
# symlink to bin/hexciri-theme (the theme dispatcher), not a real file.
# This patch follows the link and edits the resolved file, so it applies
# to whichever shape FORK_OUT has (real file on an installer-built tree,
# symlink on a repo-shaped tree). If the resolved target is missing from
# FORK_OUT the patch warns and skips; if the target is present but the
# three cleanup lines are not found, it dies loud, as usual for drift.
# Live-nyx verification of the dispatcher's contents was NOT possible
# while staging (GitHub blob fetches for the fork returned 503), so the
# push-time run is the decider for the symlink shape.
#
# test/shell.d/* changes in the PR are not ported (test/ is not in FORK_OUT).
#
# Standalone: bash v2/patches/32-theme-set-stdio-close.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Validation: bash -n on the resolved theme-set file (it is shell code;
# no JS/QML is touched, so node --check / qmllint do not apply).
set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "32-theme-set-stdio-close.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Close stdio on snapshot cleanup, omarchy PR #20133 (commit 4dc3e4d1f) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import sys

root = sys.argv[1]
changed = []

link = root + "/bin/hexciri-theme-set"
# bin/hexciri-theme-set is a symlink to bin/hexciri-theme on live nyx;
# realpath follows it (and is a no-op for a real file), so the edit lands
# in the file that actually holds set_theme_background either way.
target = os.path.realpath(link)
if not os.path.lexists(link):
    print("WARN: bin/hexciri-theme-set not in fork output, skipping (snapshot cleanup stdio)")
    sys.exit(0)
if not os.path.isfile(target):
    print("WARN: bin/hexciri-theme-set resolves to %s, not in fork output, skipping (snapshot cleanup stdio)" % target)
    sys.exit(0)

REPLACEMENTS = [
    ('    (sleep 3; rm -f "$OLD_BACKGROUND_SNAPSHOT" "$new_background_snapshot") &',
     '    (sleep 3; rm -f "$OLD_BACKGROUND_SNAPSHOT" "$new_background_snapshot") </dev/null >/dev/null 2>&1 9>&- &',
     "theme-set: both-snapshots cleanup closes stdio"),
    ('    (sleep 3; rm -f "$new_background_snapshot") &',
     '    (sleep 3; rm -f "$new_background_snapshot") </dev/null >/dev/null 2>&1 9>&- &',
     "theme-set: new-snapshot cleanup closes stdio"),
    ('      (sleep 3; rm -f "$OLD_BACKGROUND_SNAPSHOT") &',
     '      (sleep 3; rm -f "$OLD_BACKGROUND_SNAPSHOT") </dev/null >/dev/null 2>&1 9>&- &',
     "theme-set: old-snapshot cleanup closes stdio"),
]

with open(target) as f:
    s = f.read()
for old, new, label in REPLACEMENTS:
    if new in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (target, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    changed.append(label)
if changed:
    with open(target, "w") as f:
        f.write(s)

for label in changed:
    print("patched: %s" % label)
print("theme-set-stdio-close patch: %d file edits applied" % len(changed))
PY

# The edited file must still parse. Resolve the link the same way the
# patch does so the check runs against the real file, not the symlink.
_THEME_SET_RESOLVED="$(realpath "$FORK_OUT/bin/hexciri-theme-set" 2>/dev/null || true)"
if [ -n "$_THEME_SET_RESOLVED" ] && [ -f "$_THEME_SET_RESOLVED" ]; then
  bash -n "$_THEME_SET_RESOLVED" || die "bash -n failed on patched hexciri-theme-set"
fi
unset _THEME_SET_RESOLVED
info "  theme-set-stdio-close: background snapshot cleanup no longer holds theme-set callers for 3s (#20133)"
