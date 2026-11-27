#!/usr/bin/env bash
# Hexciri fork patch 42: screenrecord faststart (idea-port only).
# Forward-port of the faststart half of omarchy PR #20105 ("screenrecord
# 4K cap + faststart", commit 571d969e2).
#
# What it does (upstream behavior, unchanged): the ffmpeg finalize pass
# gains `-movflags +faststart`, moving the MP4 index to the front so
# browsers can start playing a recording before the whole file downloads.
# Verified present in the upstream diff (finalize_recording, `local
# args=(-y -ss 0.1 -i "$latest" "${video_codec[@]}" -movflags +faststart)`).
#
# Idea-port only, by design: the fork's hexciri-capture-screenrecording
# is a rewrite, not upstream's file, and it already has the landscape 4K
# cap (default_resolution caps the focused monitor at 3840x2160). The
# rest of #20105 does NOT port:
#   * cap_resolution / region_resolution / per-monitor default_resolution
#     argument: the fork's rewrite has no such machinery (no region
#     resolution function, no monitor-arg plumbing); rebuilding it is a
#     rewrite of the rewrite, not a one-line port.
#   * portrait cap (2160x3840): does not apply — Devi's portrait monitor
#     is 1080x1920, below every cap threshold, so there is nothing to cap.
# The one line that does apply is the faststart flag in finalize_recording,
# where the fork's args construction (`local args=(-y -ss 0.1 -i "$latest"
# "${video_codec[@]}")`) is the same shape as upstream's. It is valid for
# both of the fork's codec paths (-c:v copy for clean recordings and
# libx264 re-encode for warmup-packet recordings); output is always .mp4.
#
# test/shell.d/* changes in the PR are not ported (test/ is not in FORK_OUT).
#
# Standalone: bash v2/patches/42-screenrecord-faststart.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Validation: bash -n on the edited hexciri-capture-screenrecording (it
# is shell code; no JS/QML is touched, so node --check / qmllint do not
# apply).
set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "42-screenrecord-faststart.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Screenrecord faststart, omarchy PR #20105 (commit 571d969e2, faststart only) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

REC = "bin/hexciri-capture-screenrecording"

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    (REC,
     '  # Trim the first frame, and normalize audio to -14 LUFS if present, in a single pass\n  local args=(-y -ss 0.1 -i "$latest" "${video_codec[@]}")',
     '  # Trim the first frame, normalize audio to -14 LUFS if present, and move the MP4 index to the\n  # front so browsers can start playing before the whole file downloads, in a single pass.\n  local args=(-y -ss 0.1 -i "$latest" "${video_codec[@]}" -movflags +faststart)',
     "screenrecord: finalize adds -movflags +faststart"),
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
print("screenrecord-faststart patch: %d file edits applied" % len(changed))
PY

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
if [ -f "$FORK_OUT/bin/hexciri-capture-screenrecording" ]; then
  bash -n "$FORK_OUT/bin/hexciri-capture-screenrecording" || die "bash -n failed on patched hexciri-capture-screenrecording"
fi
info "  screenrecord-faststart: finalized recordings carry +faststart so browsers play before full download (#20105)"
