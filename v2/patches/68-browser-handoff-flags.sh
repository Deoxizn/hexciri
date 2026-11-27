#!/usr/bin/env bash
# Hexciri fork patch 68: browser handoff allows process-wide GPU/Wayland flags + pure-bash flag parsing (upstream #20390, Devi 2026-11-27).
# Upstream PR: https://github.com/omacom/omarchy/pull/20390 (diff verified 2026-11-27).
#
# Upstream rewrites bin/omarchy-cmd-browser-handoff's flags-file gate. The old
# gate piped the flags file through sed/tr/grep and bailed to the launcher on
# ANY flag outside a small allowlist, so a process-wide GPU/Wayland flag in the
# flags file (for example --use-angle=, added by install-video-decode, or
# --enable-gpu-rasterization) silently broke the singleton handoff and every
# URL open paid for a second browser process. The new gate is pure bash: it
# reads /etc/<flags> and ~/.config/<flags> word by word, allows the
# process-wide startup flags the running browser already has
# (--ozone-platform=*, --ozone-platform-hint=*, --password-store=*,
# --enable-features=*, --disable-features=*, --load-extension=*, --use-gl=*,
# --use-angle=*, --wayland-text-input-version=*, --no-default-browser-check,
# --no-first-run, --enable-gpu-rasterization, --enable-zero-copy,
# --enable-wayland-ime, --ignore-gpu-blocklist), and still bails on anything
# else (for example --new-window), which may be meant for each launch. The
# data-directory checks move before the socket check and are unchanged in
# effect. The flags check itself moves after the socket check, so a cold
# launch (no live socket) can exit before reading flags.
#
# Fork differences (verified against live nyx, 2026-11-27):
# - Only the comment wording changes (Omarchy -> Hexciri). The fork's
#   handoff already covers brave-origin (/usr/bin/brave-origin,
#   BraveSoftware/Brave-Origin, brave-origin-flags.conf) alongside chromium,
#   chrome, brave and edge, and the new loop reads whatever $flags names, so
#   no per-browser change is needed.
# - Direct interaction with patch 66: patch 66's new --enable-features
#   entries (AcceleratedVideoDecodeLinuxGL etc.) were already in the old
#   allowlist, and stay allowed here. The flags patch 66 does NOT add
#   (--use-angle=) is now allowed too, which is the point: install-video-decode
#   writes --use-angle=gles-egl on Snapdragon machines, and on x86 a user-set
#   --use-angle= no longer breaks handoff.
# Upstream's test-only changes are not ported: the fork does not ship test/.
#
# Standalone: bash v2/patches/68-browser-handoff-flags.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "68-browser-handoff-flags.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "68-browser-handoff-flags.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. bin/hexciri-cmd-browser-handoff ---
# Both replaced blocks assert exactly one occurrence in the pinned (94a8c3c)
# file; a drifted live file dies loudly instead of silently half-applying.
step "Letting process-wide GPU/Wayland flags through the browser handoff"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 68 handoff edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/bin/hexciri-cmd-browser-handoff"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _replace_once(text, old, new, where):
    if text.count(old) != 1:
        _die("anchor occurs %d times in %s, want exactly 1: %s" % (text.count(old), where, old.splitlines()[0][:80]))
    return text.replace(old, new, 1)


try:
    with open(target, encoding="utf-8") as f:
        raw = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

MARKER = "# The running browser already has the process-wide startup flags from the flags"
if MARKER in raw:
    print("browser-handoff: process-wide flags gate already present, skipping")
else:
    raw = _replace_once(raw, r'''# The running browser already has the process flags Hexciri ships in the flags
# file. Any other flag there may be meant for each launch, and a data directory
# from the environment is another browser, so leave those to the launcher.
if [[ -n ${CHROME_USER_DATA_DIR:-}${CHROME_CONFIG_HOME:-} ]] ||
  cat "/etc/$flags" "$config/$flags" 2>/dev/null | sed 's/#.*//' | tr -s '[:space:]' '\n' |
    grep -vE '^(--(ozone-platform|ozone-platform-hint|password-store|enable-features|load-extension)=.*|--no-default-browser-check|--no-first-run)?$' | grep -q .; then
  exit 1
fi

for arg in "$@"; do
  [[ $arg == --user-data-dir* ]] && exit 1
done

# The socket lives in a /tmp dir, which another user could recreate once a
# crashed browser's is cleaned away, so only a socket of our own gets the URL.
socket="$config/$profile/SingletonSocket"
[[ -S $socket && -O $socket ]] || exit 1''',
                        r'''# A data directory from the environment or command line belongs to another
# browser, and a cold launch (no live socket) can exit before reading flags.
[[ -z ${CHROME_USER_DATA_DIR:-}${CHROME_CONFIG_HOME:-} ]] || exit 1

for arg in "$@"; do
  [[ $arg == --user-data-dir* ]] && exit 1
done

# The socket lives in a /tmp dir, which another user could recreate once a
# crashed browser's is cleaned away, so only a socket of our own gets the URL.
socket="$config/$profile/SingletonSocket"
[[ -S $socket && -O $socket ]] || exit 1

# The running browser already has the process-wide startup flags from the flags
# file. Any other flag there may be meant for each launch, so leave those to
# the launcher.
for file in "/etc/$flags" "$config/$flags"; do
  [[ -r $file ]] || continue
  while IFS= read -r line || [[ -n $line ]]; do
    read -ra words <<<"${line%%#*}"
    for word in "${words[@]}"; do
      case $word in
      --ozone-platform=* | --ozone-platform-hint=* | --password-store=* | \
        --enable-features=* | --disable-features=* | --load-extension=* | \
        --use-gl=* | --use-angle=* | --wayland-text-input-version=* | \
        --no-default-browser-check | --no-first-run | --enable-gpu-rasterization | \
        --enable-zero-copy | --enable-wayland-ime | --ignore-gpu-blocklist) ;;
      *) exit 1 ;;
      esac
    done
  done <"$file"
done''', target)
    with open(target, "w", encoding="utf-8") as f:
        f.write(raw)
    print("patched: process-wide flags gate in bin/hexciri-cmd-browser-handoff")

with open(target, encoding="utf-8") as f:
    raw = f.read()
for needle in ("--use-angle=*", "--enable-gpu-rasterization", "--enable-zero-copy",
               "--enable-wayland-ime", "--ignore-gpu-blocklist", "--disable-features=*",
               "--wayland-text-input-version=*", 'for file in "/etc/$flags" "$config/$flags"'):
    if needle not in raw:
        _die("handoff lost %r after edit" % needle)
if "grep -vE" in raw:
    _die("old grep-based flags gate still present after edit")
if raw.count(MARKER) != 1:
    _die("process-wide flags marker occurs %d times after edit" % raw.count(MARKER))
if "CHROME_USER_DATA_DIR" not in raw or "--user-data-dir*" not in raw:
    _die("data-directory guards lost after edit")
print("browser handoff validates (%d lines)" % len(raw.splitlines()))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on the edited script: a bad edit here would break every
# URL handoff to the running browser.
bash -n "$FORK_OUT/bin/hexciri-cmd-browser-handoff" || die "bash -n failed on bin/hexciri-cmd-browser-handoff"

printf 'browser handoff patch: %d handoff edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 68: browser handoff allows process-wide GPU/Wayland flags"
