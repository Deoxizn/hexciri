#!/usr/bin/env bash
# Hexciri fork patch 66: hardware video decode/encode in Chromium browsers (upstream #20376, Devi 2026-11-27).
# Upstream PR: https://github.com/omacom/omarchy/pull/20376 (diff verified 2026-11-27).
#
# Upstream adds three features to the --enable-features line of the shipped
# chrome-flags.conf / chromium-flags.conf and migrates existing live flags
# files: AcceleratedVideoDecodeLinuxGL, AcceleratedVideoDecodeLinuxZeroCopyGL,
# AcceleratedVideoEncoder.
#
# Fork differences (all verified against live nyx install.sh, 2026-11-27):
# - FORK_OUT/config/ holds ONLY chromium-flags.conf. install.sh copies just
#   that one file from upstream (install-browser then copies it to
#   ~/.config/<browser>-flags.conf for every Chromium browser, including
#   brave-origin). Upstream's chrome-flags.conf has no fork destination, so
#   only the chromium-flags.conf shipped default is edited here.
# - There is no migrations runner in the fork (install.sh: upstream
#   migrations are deliberately not copied). The live-files half of the
#   upstream migration therefore runs here, in this patch script, the same
#   way patch 49 already edits live user state ($HOME/.local/state) from a
#   patch script. Files touched, exactly as upstream:
#   ~/.config/{chromium,chrome,microsoft-edge-stable,brave,brave-origin}-flags.conf.
#   A file that does not exist is skipped; a feature already present is
#   skipped. The upstream grep/sed logic is copied verbatim, so an existing
#   --enable-features line is extended in place and a file with no such line
#   gains one appended feature per line.
# - The fork already has hexciri-install-video-decode, but it only acts on
#   Snapdragon/Qualcomm ARM (hexciri-hw-aarch64-qualcomm gate) and adds
#   --use-angle=gles-egl + AcceleratedVideoDecoder. It is untouched: this
#   patch is the general path, and the Snapdragon helper keeps doing its own
#   thing on those machines.
# - VA-API is a sure win on the Framework (AMD mesa). On the desktop (NVIDIA)
#   decode depends on VA-API driver setup being present; this patch ports the
#   flags and claims nothing about desktop decode working.
#
# Standalone: bash v2/patches/66-chromium-vaapi.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "66-chromium-vaapi.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "66-chromium-vaapi.sh: $1" >&2; exit 1; }
CHANGED=0

FEATURES=(
  AcceleratedVideoDecodeLinuxGL
  AcceleratedVideoDecodeLinuxZeroCopyGL
  AcceleratedVideoEncoder
)

# --- 1. Shipped default: FORK_OUT/config/chromium-flags.conf ---
# The --enable-features anchor must occur exactly once; anything else means
# the shipped file drifted from the pinned upstream (94a8c3c) shape.
step "Enabling hardware video decode/encode in the shipped chromium flags"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 66 shipped-flags edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/config/chromium-flags.conf"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


OLD = "--enable-features=TouchpadOverscrollHistoryNavigation,OverlayScrollbar"
NEW = OLD + ",AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder"

try:
    with open(target, encoding="utf-8") as f:
        raw = f.read()
except FileNotFoundError:
    _die("%s not found in fork output (install.sh copies only chromium-flags.conf to FORK_OUT/config/)" % target)

if NEW in raw:
    print("chromium-flags: VA-API features already present, skipping")
elif raw.count(OLD) != 1:
    _die("enable-features anchor occurs %d times in %s, want exactly 1" % (raw.count(OLD), target))
else:
    if "/usr/share/omarchy" in raw:
        _die("shipped flags still reference /usr/share/omarchy, the rename step did not run before this patch")
    raw = raw.replace(OLD, NEW, 1)
    with open(target, "w", encoding="utf-8") as f:
        f.write(raw)
    print("patched: VA-API features in config/chromium-flags.conf")

with open(target, encoding="utf-8") as f:
    raw = f.read()
if raw.count(NEW) != 1:
    _die("VA-API enable-features line occurs %d times after edit" % raw.count(NEW))
for feature in ("AcceleratedVideoDecodeLinuxGL", "AcceleratedVideoDecodeLinuxZeroCopyGL", "AcceleratedVideoEncoder"):
    if feature not in raw:
        _die("feature %s lost after edit" % feature)
if "/usr/share/hexciri/default/chromium/extensions/" not in raw:
    _die("extension load path no longer points at /usr/share/hexciri after edit")
print("shipped chromium flags validate (%d lines)" % len(raw.splitlines()))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# --- 2. Live user flags files: the upstream migration, run here ---
# Upstream migrations/1795778751.sh. Same file list, same per-feature
# grep/sed logic, copied verbatim. A missing file is skipped (that browser
# was never installed); a feature already listed is skipped. Runs against
# $HOME, which patch scripts have (patch 49 precedent).
step "Migrating existing browser flags files to hardware video decode/encode"
_LIVE_EDITS=0
for _flags_file in "$HOME"/.config/{chromium,chrome,microsoft-edge-stable,brave,brave-origin}-flags.conf; do
  [[ -f $_flags_file ]] || continue
  for _feature in "${FEATURES[@]}"; do
    _args=$(sed -E 's/(^|[[:space:]])#.*$//' "$_flags_file")
    if grep -Eq -- "(^|[[:space:]])--enable-features=([^[:space:]]*,)?$_feature([,:<[:space:]]|\$)" <<<"$_args"; then
      continue
    fi
    if grep -Eq -- '(^|[[:space:]])--enable-features=' <<<"$_args"; then
      sed -i --follow-symlinks -E \
        -e "s/^(([^#]*[[:space:]])?--enable-features=[^[:space:]#]*)/\1,$_feature/" \
        -e "s/--enable-features=,$_feature/--enable-features=$_feature/" "$_flags_file"
    else
      if [[ -n $(tail -c1 "$_flags_file") ]]; then
        echo >>"$_flags_file"
      fi
      printf '%s\n' "--enable-features=$_feature" >>"$_flags_file"
    fi
    _LIVE_EDITS=$((_LIVE_EDITS + 1))
    printf 'patched: %s gains %s\n' "$_flags_file" "$_feature" >>"$_patch_log"
  done
done
CHANGED=$((CHANGED + _LIVE_EDITS))
if [ "$_LIVE_EDITS" -eq 0 ]; then
  printf 'live flags files: VA-API features already present (or no browser flags files), skipping\n' >>"$_patch_log"
fi

printf 'chromium VA-API patch: %d shipped-flag edits + %d live-file feature adds applied\n' "$_PY_EDITS" "$_LIVE_EDITS" >>"$_patch_log"
info "  patch 66: hardware video decode/encode flags in Chromium browsers"
