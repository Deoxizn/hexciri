#!/usr/bin/env bash
# Hexciri fork patch 56: replace udiskie with a bash UDisks2 automounter (upstream PR #20412, Devi 2026-11-27).
# Upstream: https://github.com/omacom/omarchy/pull/20412
# Verified against the PR's actual .diff (2026-11-27) and the merged file on
# quattro (bin/omarchy-drive-automount, bin/omarchy-drive-unlock).
#
# Upstream drops udiskie (~23 MiB resident Python) for a gdbus-monitor +
# bash watcher (~1.8 MiB) that mounts removable filesystems with
# HintAuto=true / HintIgnore=false (following CryptoBackingDevice for
# unlocked LUKS cleartext devices) and delegates locked LUKS partitions to
# omarchy-drive-unlock. The PR has five parts; the fork takes them as:
#
#   1. bin/omarchy-drive-automount (new) -> FORK_OUT/bin/hexciri-drive-automount,
#      created here from an embedded copy (the pinned tarball predates the
#      PR, so install.sh has nothing to copy). Renames applied: the
#      omarchy-drive-unlock call/comment become hexciri-drive-unlock.
#      The "# omarchy:summary=" header stays, as in every other fork bin.
#   2. bin/omarchy-drive-unlock (comment-only change upstream) -> the fork
#      NEVER had this file (upstream added it after the pin; the fork
#      skips LUKS scripts in copy_subsets), so it is created here from an
#      embedded copy of the merged upstream version, renamed:
#      hexciri-shell -q hexciri.polkit unlockDrive, Usage: hexciri-drive-unlock.
#      The PR's removal of the trailing `exit 1` is kept: the unlock call
#      is fire-and-forget from the automounter, exit status is meaningless.
#   3. default/hypr/autostart.lua: the udiskie launch line becomes
#      hexciri-drive-automount. Note the fork's line has no --password-prompt
#      (that arrived upstream after the pin); the anchor is the fork's line.
#   4. install/omarchy-base.packages udiskie -> udisks2: fork equivalent is
#      v2/install.sh CORE_PKGS line 707. Patches never edit install.sh, so
#      this patch does NOT do the swap; it warns if udiskie is still listed.
#      Companion install.sh edit (coordinator, with the push): replace
#      `udiskie` with `udisks2`, update the comment at lines 712-713 and the
#      health check at line 4725. udisks2 is near-certainly already present
#      (gnome-disk-utility depends on it), so existing installs are safe.
#   5. migrations/1795785360.sh (omarchy-pkg-add udisks2): NOT ported.
#      The fork does not run upstream migrations (copy_subsets skips them);
#      the package swap covers fresh installs, and udisks2 is already a
#      dependency of gnome-disk-utility on existing installs.
#
# LUKS caveat (do not over-claim): the bins preserve the LUKS delegation
# exactly as upstream wrote it, but the shell side they talk to
# (PolkitAgent.qml unlockDrive IPC + drive card) arrived upstream after
# the pin and is NOT in the fork. A locked LUKS partition would fire
# hexciri-drive-unlock, whose hexciri-shell call finds no unlockDrive
# target and fails silently in the background (>/dev/null 2>&1 &): no
# crash, no hang, just no unlock card until the shell side is ported.
# Devi has no LUKS, so nothing regresses for him; the automount path is
# the part that matters here.
#
# Allowlist: the new bins must be first-class shipped bins. install.sh
# copies upstream bin/omarchy-drive-automount only when `drive-*` is in
# is_allowed_bin (today it is not: no `drive-` match in install.sh). This
# patch follows patch 52's guard pattern and DIES if `drive-*` is absent
# from v2/install.sh, so the coordinator adds `drive-*` to the allowlist
# with the push. The patch still writes the files itself (the pinned
# tarball has no upstream copy to copy); the allowlist entry is what
# makes a future pin carry the file, and what keeps the bin a known
# shipped script rather than a patch-only smuggle.
#
# Standalone: bash v2/patches/56-udisks2-automounter.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "56-udisks2-automounter.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "56-udisks2-automounter.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 0. Guard: install.sh must allowlist drive-* (patch 52's pattern) ---
# The new automounter only ships as a known bin when is_allowed_bin carries
# it; without the entry a future pin would silently drop the upstream file
# and the patch would be the only thing standing between the fork and a
# missing automounter.
grep -qF 'drive-*' "$HEXCIRI_REPO_ROOT/v2/install.sh" 2>/dev/null || die "v2/install.sh does not list drive-* in the bin allowlist, add it before this patch can apply (upstream bin/omarchy-drive-automount would otherwise never ship)"
if grep -q '^  udiskie$' "$HEXCIRI_REPO_ROOT/v2/install.sh" 2>/dev/null; then
  warn "v2/install.sh still lists udiskie in CORE_PKGS; companion edit swaps it for udisks2 and updates the lines 712-713 comment + line 4725 health check"
fi

# Write a new fork file from stdin; idempotent via content compare. $1 =
# FORK_OUT-relative path, $2 = mode (755 for bin/). A present file with
# identical content skips; a present file with different content dies
# rather than clobbering unknown content (e.g. a future pin shipping its
# own copy of the file, which then needs a patch revision, not a silent
# overwrite). Adapted from patch 49's replace_file, but for creation.
create_file() {
  local rel="$1" mode="$2" dest tmp
  dest="$FORK_OUT/$rel"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      printf '%s: already present, skipping\n' "$rel" >>"$_patch_log"
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    die "$rel already exists with different content, refusing to clobber it"
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod "$mode" "$dest"
  CHANGED=$((CHANGED + 1))
  printf 'patched: created %s\n' "$rel" >>"$_patch_log"
}

# --- 1. New bin: hexciri-drive-automount (upstream PR #20412, renamed) ---
# Content transcribed from the merged upstream file (quattro
# bin/omarchy-drive-automount, verified against the PR .diff): only the
# omarchy-drive-unlock references are renamed to hexciri-drive-unlock.
# Blank-line layout follows the fetched rendering; every code line is
# verbatim upstream.
step "Creating the bash UDisks2 automounter"
create_file "bin/hexciri-drive-automount" 755 <<'HEXCIRI_EOF_DRIVE_AUTOMOUNT'
#!/bin/bash


# omarchy:summary=Automount removable drives and prompt to unlock encrypted ones

# omarchy:hidden=true


# Lightweight UDisks2 event watcher replacing udiskie (~23 MiB Python) with
# gdbus monitor + bash (~1.8 MiB). Mounts removable filesystems with
# HintAuto=true and HintIgnore=false (following CryptoBackingDevice for
# unlocked LUKS cleartext devices), and delegates locked LUKS partitions to
# hexciri-drive-unlock.


set -uo pipefail


decode_udisks_name() {
  local raw=$1 out="" hex=""

  while [[ $raw =~ ^([^_]*)_([0-9a-fA-F]{2})(.*)$ ]]; do
    out+=${BASH_REMATCH[1]}

    printf -v hex "\\x${BASH_REMATCH[2]}"

    out+=$hex

    raw=${BASH_REMATCH[3]}

  done

  printf '%s%s\n' "$out" "$raw"

}


handle_block_device() {
  local path=$1 name dev hint_path backing mount_points cleartext

  local -a props


  name=$(decode_udisks_name "${path##*/}")

  dev="/dev/$name"

  [[ -b $dev ]] || return 0


  # Unlocked LUKS cleartext devices (/dev/dm-*) have no direct Drive and report
  # HintAuto=false; inherit automount hints from their encrypted backing device.

  hint_path=$path

  backing=$(
    busctl get-property org.freedesktop.UDisks2 "$path" \
      org.freedesktop.UDisks2.Block CryptoBackingDevice 2>/dev/null
  )

  if [[ $backing =~ ^o\ \"(/.+)\"$ ]]; then
    hint_path=${BASH_REMATCH[1]}

  fi


  mapfile -t props < <(
    busctl get-property org.freedesktop.UDisks2 "$hint_path" \
      org.freedesktop.UDisks2.Block HintAuto HintIgnore 2>/dev/null
  )

  [[ ${props[0]:-} == "b true" && ${props[1]:-} == "b false" ]] || return 0


  if mount_points=$(
    busctl get-property org.freedesktop.UDisks2 "$path" \
      org.freedesktop.UDisks2.Filesystem MountPoints 2>/dev/null
  ); then
    if [[ $mount_points == "aay 0" ]]; then
      udisksctl mount --no-user-interaction -b "$dev" >/dev/null 2>&1 &
    fi

    return 0
  fi


  if cleartext=$(
    busctl get-property org.freedesktop.UDisks2 "$path" \
      org.freedesktop.UDisks2.Encrypted CleartextDevice 2>/dev/null
  ); then
    if [[ $cleartext == 'o "/"' ]]; then
      hexciri-drive-unlock "$dev" >/dev/null 2>&1 &
    fi

  fi

}


scan_existing() {
  local path

  while IFS= read -r path; do
    [[ $path == /org/freedesktop/UDisks2/block_devices/* ]] || continue
    handle_block_device "$path"
  done < <(busctl tree --list org.freedesktop.UDisks2 2>/dev/null)

}


# Subscribe before scanning so drives plugged in during startup are never missed.

coproc MONITOR {
  setpriv --pdeathsig TERM gdbus monitor --system \
    --dest org.freedesktop.UDisks2 --object-path /org/freedesktop/UDisks2 2>/dev/null
}


# Wait for gdbus monitor's initial "Monitoring signals..." line so the D-Bus
# subscription is active before enumerating existing devices.

IFS= read -r _ <&"${MONITOR[0]}" || exit 0


scan_existing


while IFS= read -r line <&"${MONITOR[0]}"; do
  if [[ $line =~ InterfacesAdded\ \(objectpath\ \'(/org/freedesktop/UDisks2/block_devices/[^\']+)\' ]]; then
    handle_block_device "${BASH_REMATCH[1]}"
  fi
done
HEXCIRI_EOF_DRIVE_AUTOMOUNT

# --- 2. New bin: hexciri-drive-unlock (merged upstream version, renamed) ---
# The fork never had this file (added upstream after the pin), so it is
# created whole. Renames: omarchy-drive-unlock -> hexciri-drive-unlock
# (Usage + comments), omarchy-shell -> hexciri-shell, omarchy.polkit ->
# hexciri.polkit. No trailing `exit 1`: the PR removed it, the call is
# fire-and-forget from the automounter.
step "Creating the LUKS unlock helper the automounter delegates to"
create_file "bin/hexciri-drive-unlock" 755 <<'HEXCIRI_EOF_DRIVE_UNLOCK'
#!/bin/bash


# omarchy:summary=Ask for an encrypted drive's password in the shell and unlock it

# omarchy:args=<device>

# omarchy:hidden=true


# Called by hexciri-drive-automount when a locked LUKS partition appears. The
# shell asks for the password and unlocks the drive itself, so a wrong password
# shakes the card and is asked again; hexciri-drive-automount then mounts the
# unlocked cleartext device as it appears.


device=${1:?Usage: hexciri-drive-unlock <device>}

disk=$(lsblk -dno PKNAME "$device")

name=$(lsblk -dno LABEL "$device")

[[ -n $name ]] || name=$(lsblk -dno MODEL "/dev/${disk:-${device#/dev/}}" | sed 's/ *$//')

size=$(lsblk -dno SIZE "$device" | tr -d ' ')


hexciri-shell -q hexciri.polkit unlockDrive "$device" "${name:+$name · }$size"
HEXCIRI_EOF_DRIVE_UNLOCK

# --- 3. Autostart: launch the automounter instead of udiskie ---
# The fork's udiskie line has no --password-prompt (that arrived upstream
# after the pin); anchor on the fork's line exactly as it ships.
step "Switching autostart from udiskie to the new automounter"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 56 autostart edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/default/hypr/autostart.lua"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


OLD = '  hl.exec_cmd("sleep 2 && " .. o.launch("udiskie --automount --no-notify --no-tray"))'
NEW = '  hl.exec_cmd("sleep 2 && " .. o.launch("hexciri-drive-automount"))'

try:
    with open(target, encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

if NEW in lines:
    if OLD in lines:
        _die("both old udiskie and new automount lines present, half-patched state")
    print("autostart: drive automounter already present, skipping")
else:
    hits = [i for i, l in enumerate(lines) if l == OLD]
    if len(hits) != 1:
        _die("udiskie autostart line occurs %d times, want exactly 1" % len(hits))
    lines[hits[0]] = NEW
    print("patched: autostart launches hexciri-drive-automount instead of udiskie")

with open(target, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: no udiskie reference left, new line exactly once.
with open(target, encoding="utf-8") as f:
    raw = f.read()
if "udiskie" in raw:
    _die("udiskie still mentioned in autostart.lua after edit")
if raw.count(NEW) != 1:
    _die("automount launch line occurs %d times after edit" % raw.count(NEW))
print("autostart validates (%d lines)" % len(raw.splitlines()))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on both new bins: a bad embed here would break
# automount for every removable drive.
bash -n "$FORK_OUT/bin/hexciri-drive-automount" || die "bash -n failed on bin/hexciri-drive-automount"
bash -n "$FORK_OUT/bin/hexciri-drive-unlock" || die "bash -n failed on bin/hexciri-drive-unlock"

printf 'udisks2 automounter patch: %d drive-bin/autostart edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 56: udiskie replaced by bash UDisks2 automounter (upstream #20412)"
