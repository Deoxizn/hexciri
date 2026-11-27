#!/bin/bash
# Hexciri fork patch 16: tune jemalloc for Quickshell to reclaim startup heap memory.
# Forward-port of omarchy PR #20242 ("Tune jemalloc for Quickshell to reclaim
# startup heap memory", dhh) into bin/hexciri-launch-shell.
#
# What it does (PR behavior, unchanged): sets
# MALLOC_CONF="${MALLOC_CONF:-narenas:2,tcache_max:4096,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0}"
# on the quickshell launch env. Quickshell links jemalloc, which creates
# 4 * ncpus arenas by default and keeps dirty/muzzy pages from startup bursts
# (QML compilation, icon scanning, image decoding, Mesa shaders) resident.
# Two arenas, a 4 KiB thread cache, and a background purge thread return those
# pages quickly without stalling the GUI or render threads. An explicit caller
# MALLOC_CONF is still honored via ${MALLOC_CONF:-...}.
#
# Measured impact upstream (test/headless, real GPU rendering): Quickshell PSS
# 366.3 MiB -> 191.1 MiB (-175.2 MiB), anon heap 334.1 MiB -> 158.8 MiB.
# Caveats: that figure was measured on upstream's shell; Hexciri's heap profile
# differs, so the saving here will not be the same number. Whether Devi's
# Quickshell links jemalloc is expected but unconfirmed; if it does not, the
# env var is inert.
#
# Fork adaptation: upstream edits bin/omarchy-launch-shell; the fork file lands
# as bin/hexciri-launch-shell (renamed bin) and its env var is
# HEXCIRI_STARTUP_BACKGROUND, not OMARCHY_STARTUP_BACKGROUND, so the anchor
# is the fork spelling first, with the upstream spelling as a fallback for a
# tree the rename has not reached yet. The PR's diff touches only that one
# file (the test files it cites, test/shell.d/launch-shell-test.sh and
# test/shell.d/bar-startup-budget-test.sh, already existed upstream and are
# not part of the diff); the fork does not ship upstream tests, so this patch
# carries the bin change alone.
#
# Standalone: bash v2/patches/16-jemalloc.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is shell script, so bash -n DOES apply
# here (unlike the JS/QML patches) and runs on the patched file below.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "16-jemalloc.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- jemalloc tuning for Quickshell, omarchy PR #20242 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
rel = "bin/hexciri-launch-shell"
fp = root + "/" + rel

try:
    with open(fp) as f:
        s = f.read()
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping (jemalloc tuning)" % rel)
    sys.exit(0)

if "MALLOC_CONF=" in s:
    print("jemalloc tuning: already present, skipping")
    sys.exit(0)

# The PR's comment + MALLOC_CONF line, verbatim from the diff. The env line
# keeps its continuation backslash and gains two spaces of indent, exactly
# as upstream (the MALLOC_CONF line takes the original two-space indent).
COMMENT = (
    "  # Quickshell links jemalloc, which creates 4 * ncpus arenas by default and\n"
    "  # keeps dirty/muzzy pages from startup bursts (QML compilation, icon scanning,\n"
    "  # image decoding, Mesa shaders) resident. Two arenas, a 4 KiB thread cache,\n"
    "  # and a background purge thread return those pages quickly without stalling\n"
    "  # the GUI or render threads.\n"
    "  MALLOC_CONF=\"${MALLOC_CONF:-narenas:2,tcache_max:4096,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0}\" \\\n"
)

# Fork spelling first (the rename also renamed the env var); upstream spelling
# as a fallback for a tree the rename has not reached yet. Exactly one of
# them must occur exactly once.
for var in ("HEXCIRI_STARTUP_BACKGROUND", "OMARCHY_STARTUP_BACKGROUND"):
    old = '  %s="$startup_background" \\\n' % var
    if s.count(old) == 1:
        new = COMMENT + '    %s="$startup_background" \\\n' % var
        s = s.replace(old, new, 1)
        break
else:
    print("ERROR: anchor not found exactly once in %s (HEXCIRI count %d, OMARCHY count %d): jemalloc tuning"
          % (rel, s.count('  HEXCIRI_STARTUP_BACKGROUND="$startup_background" \\\n'),
             s.count('  OMARCHY_STARTUP_BACKGROUND="$startup_background" \\\n')), file=sys.stderr)
    sys.exit(1)

with open(fp, "w") as f:
    f.write(s)
print("patched: jemalloc tuning in %s (PR #20242)" % rel)
print("jemalloc patch: 1 file edit applied")
PY

# Syntax-check the edited file. It is shell script, so bash -n applies here.
if [ -f "$FORK_OUT/bin/hexciri-launch-shell" ]; then
  bash -n "$FORK_OUT/bin/hexciri-launch-shell" || die "bash -n failed on patched bin/hexciri-launch-shell"
fi
info "  jemalloc: Quickshell startup heap purge via MALLOC_CONF (PR #20242)"
