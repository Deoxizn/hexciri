#!/usr/bin/env bash
# Hexciri fork patch 54: fwupdmgr exit 2 is "no updates", not a failure (Devi 2026-11-27).
# Hexciri-original (no upstream PR).
#
# Devi ran Update > Firmware and got a red "Failed (exit code 2)!" even
# though everything worked: metadata refreshed fine, both devices
# enumerated (TEAM TM8FPD002T, USB4 host controller), just "No updatable
# devices". fwupdmgr exits 2 when there is nothing to do, and
# bin/hexciri-update-firmware (set -e, with `sudo fwupdmgr update` as its
# last command) passed that 2 straight through, so the floating terminal
# wrapper reported failure. Not a hardware problem.
#
# The fix: capture the exit code. 2 prints "No firmware updates
# available." and exits 0; any other non-zero code still fails the script
# with that code, so real errors keep surfacing. The refresh step is
# untouched: a failed `fwupdmgr refresh --force` still fails the script
# under set -e. The `|| _fwupd_code=$?` form is what keeps set -e from
# killing the script before the code is read (a bare capture after a
# failing command would never run).
#
# Standalone: bash v2/patches/54-firmware-exit2.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "54-firmware-exit2.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "54-firmware-exit2.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. fwupdmgr exit-code handling (bin/hexciri-update-firmware) ---
# The python block prints one "patched: ..." line (or an "already
# present, skipping" line); output goes through a temp file, not straight
# to $_patch_log, so a trailing info line cannot clobber it (patch 50's
# pattern).
step "Treating fwupdmgr exit 2 as no updates in the firmware updater"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 54 firmware edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/bin/hexciri-update-firmware"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


MARKER = "# fwupdmgr exits 2 when there is nothing to do; that is not a failure."
BLOCK = [
    MARKER,
    "_fwupd_code=0",
    "sudo fwupdmgr update || _fwupd_code=$?",
    "if [[ $_fwupd_code -eq 2 ]]; then",
    '  echo "No firmware updates available."',
    "elif [[ $_fwupd_code -ne 0 ]]; then",
    '  exit "$_fwupd_code"',
    "fi",
]

try:
    with open(target, encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

if MARKER in lines:
    print("firmware: exit-2 handling already present, skipping")
else:
    # The bare `sudo fwupdmgr update` line must occur exactly once and be
    # the last command; anything else means the live file drifted.
    hits = [i for i, l in enumerate(lines) if l.strip() == "sudo fwupdmgr update"]
    if len(hits) != 1:
        _die('bare "sudo fwupdmgr update" occurs %d times, want exactly 1' % len(hits))
    i = hits[0]
    if i != len(lines) - 1:
        _die('bare "sudo fwupdmgr update" is not the last line, live file drifted')
    if "fwupdmgr refresh --force" not in "\n".join(lines[:i]):
        _die('refresh step "fwupdmgr refresh --force" missing before the update call')
    if "set -e" not in lines:
        _die('"set -e" missing, the exit-code capture reasoning does not hold')
    lines[i:i + 1] = BLOCK
    print("patched: fwupdmgr exit-2 handling in bin/hexciri-update-firmware")

with open(target, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: the edited script must still be valid bash, keep the
# refresh step, and have no bare update call left.
with open(target, encoding="utf-8") as f:
    raw = f.read()
if raw.count(MARKER) != 1:
    _die("marker occurs %d times after edit" % raw.count(MARKER))
if any(l.strip() == "sudo fwupdmgr update" for l in raw.splitlines()):
    _die("bare 'sudo fwupdmgr update' still present after edit")
if "fwupdmgr refresh --force" not in raw:
    _die("refresh step lost in edit")
print("firmware updater validates (%d lines)" % len(raw.splitlines()))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on the edited script: a bad edit here would break the
# whole Update > Firmware menu row.
bash -n "$FORK_OUT/bin/hexciri-update-firmware" || die "bash -n failed on bin/hexciri-update-firmware"

printf 'firmware exit-2 patch: %d firmware updater edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 54: fwupdmgr exit 2 (no updates) no longer reports failure"
