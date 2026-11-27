#!/usr/bin/env bash
# Hexciri fork patch 71: Bluetooth off blocks only hci* rfkill switches (upstream PR #20378, Devi 2026-11-27).
# Upstream: https://github.com/omacom/omarchy/pull/20378
# Verified against the PR's actual .diff (2026-11-27): a power_off()
# function in bin/omarchy-bluetooth-power plus two call-site swaps
# (off, toggle). The PR's test/shell.d changes are not ported: the fork
# ships no upstream test tree.
#
# Laptops with a platform ACPI rfkill switch (e.g. ThinkPad's
# tpacpi_bluetooth_sw) cut power to the internal USB port when that switch
# is blocked, unplugging hci0 from BlueZ so the bar icon vanishes and
# re-enabling needs a full USB re-enumeration and firmware reload.
# Blocking only the hci* switches still persists across reboots via
# systemd-rfkill while keeping the adapter visible in Powered: no state.
# Power-on is untouched: it still unblocks the whole `bluetooth` class.
# Fallback preserved: with no hci* switch present, off blocks `bluetooth`
# exactly as before, so machines without a platform switch (both of
# Devi's: desktop dokoz, Framework 13) behave byte-identically.
#
# Standalone: bash v2/patches/71-bluetooth-rfkill-hci.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "71-bluetooth-rfkill-hci.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "71-bluetooth-rfkill-hci.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. power_off() in bin/hexciri-bluetooth-power + off/toggle call sites ---
# Anchors are the fork's own lines (verified against the post-51 sim tree;
# no patch 52-54 touches this file). The power_on() tail and the case
# branches are identical to upstream; the fork's only differences here are
# the HEXCIRI_ env prefix and the hexciri- script name, which this patch
# does not touch. Each anchor block must occur exactly once; a half-present
# state (marker without both call sites, or vice versa) dies loudly.
step "Blocking only hci* rfkill switches on Bluetooth off"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 71 bluetooth-power edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/bin/hexciri-bluetooth-power"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


MARKER = "# Block the BlueZ controller rfkill switches (hci*) rather than the whole"
POWER_OFF = [
    MARKER,
    "# `bluetooth` class. Laptops with a platform ACPI switch (e.g. ThinkPad's",
    "# tpacpi_bluetooth_sw) cut power to the internal USB port when that switch is",
    "# blocked, unplugging hci0 from BlueZ so the bar icon vanishes and re-enabling",
    "# requires a full USB re-enumeration and firmware reload. Blocking hci* still",
    "# persists across reboots via systemd-rfkill while keeping the adapter visible",
    "# in Powered: no state.",
    "power_off() {",
    "  local -a ids=()",
    "  local id device",
    "",
    "  while read -r id device; do",
    "    [[ $id =~ ^[0-9]+$ && $device == hci* ]] && ids+=(\"$id\")",
    "  done < <(LC_ALL=C rfkill --raw --noheadings --output ID,DEVICE list bluetooth 2>/dev/null)",
    "",
    "  if (( ${#ids[@]} > 0 )); then",
    '    rfkill block "${ids[@]}"',
    "  else",
    "    rfkill block bluetooth",
    "  fi",
    "}",
]
# End of power_on(): the `}` closing it, then the case dispatch.
POWER_ON_TAIL = '  echo "hexciri-bluetooth-power: adapter did not come up" >&2'
# The two call sites, each anchored on its unique surrounding lines so the
# bare `rfkill block bluetooth` inside power_off's own fallback is never
# mistaken for one.
OFF_BLOCK = [
    "  off)",
    "    # No bluetoothctl power off to go with this: the block already drops the",
    "    # adapter to Powered: no, and it is the half that survives the reboot.",
    "    rfkill block bluetooth",
]
TOGGLE_BLOCK = [
    "  toggle)",
    "    if powered; then",
    "      rfkill block bluetooth",
]

try:
    with open(target, encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output" % target)


def find_block(block):
    """Indices where block occurs as consecutive lines."""
    hits = []
    for i in range(len(lines) - len(block) + 1):
        if lines[i:i + len(block)] == block:
            hits.append(i)
    return hits


def find_off_call():
    hits = find_block(OFF_BLOCK)
    if len(hits) != 1:
        _die("off-branch block occurs %d times, want exactly 1" % len(hits))
    return hits[0] + len(OFF_BLOCK) - 1


def find_toggle_call():
    hits = find_block(TOGGLE_BLOCK)
    if len(hits) != 1:
        _die("toggle-branch block occurs %d times, want exactly 1" % len(hits))
    return hits[0] + len(TOGGLE_BLOCK) - 1


if MARKER in lines:
    # Already inserted: both call sites must already point at power_off,
    # otherwise this is a half-patched state, not idempotency.
    off = find_off_call() if find_block(OFF_BLOCK) else None
    tog = find_toggle_call() if find_block(TOGGLE_BLOCK) else None
    if off is not None or tog is not None:
        _die("power_off() present but a call site still uses bare rfkill block bluetooth, half-patched state")
    if lines.count("    power_off") != 1 or lines.count("      power_off") != 1:
        _die("power_off() present but call sites are not exactly one off + one toggle")
    print("bluetooth-power: hci-only power_off already present, skipping")
else:
    if "    power_off" in lines or "      power_off" in lines:
        _die("power_off call sites present but power_off() missing, half-patched state")
    # Insert power_off() between power_on()'s closing `}` and `case`.
    tails = [i for i, l in enumerate(lines) if l == POWER_ON_TAIL]
    if len(tails) != 1:
        _die("power_on() tail occurs %d times, want exactly 1" % len(tails))
    i = tails[0]
    # power_on() ends `return 1` / `}` / blank / `case "${1:-}" in`.
    if lines[i + 1:i + 4] != ["  return 1", "}", ""]:
        _die("lines after the power_on() tail are not return 1 + } + blank, live file drifted")
    if lines[i + 4] != 'case "${1:-}" in':
        _die('no case dispatch after power_on(), live file drifted')
    lines[i + 3:i + 3] = POWER_OFF
    print("patched: power_off() blocks only hci* rfkill switches")
    # Both call sites must exist exactly once before they are swapped.
    off_line = find_off_call()
    lines[off_line] = "    power_off"
    print("patched: off branch uses power_off")
    tog_line = find_toggle_call()
    lines[tog_line] = "      power_off"
    print("patched: toggle branch uses power_off")

with open(target, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: marker once, both call sites, one bare-block fallback left.
# NOTE: count whole lines, not substrings: "      power_off" (toggle)
# contains "    power_off" (off) as a substring.
with open(target, encoding="utf-8") as f:
    lines_after = f.read().splitlines()
    raw = "\n".join(lines_after)
if lines_after.count(MARKER) != 1:
    _die("power_off() marker occurs %d times after edit" % lines_after.count(MARKER))
if lines_after.count("    power_off") != 1 or lines_after.count("      power_off") != 1:
    _die("power_off call sites are not exactly one off + one toggle after edit")
if raw.count("rfkill block bluetooth") != 1:
    _die("bare 'rfkill block bluetooth' occurs %d times after edit, want exactly 1 (the power_off fallback)" % raw.count("rfkill block bluetooth"))
if raw.count("rfkill unblock bluetooth") != 1:
    _die("power_on's 'rfkill unblock bluetooth' lost or duplicated after edit")
print("bluetooth-power validates (%d lines)" % len(lines_after))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on the edited script: a bad edit here would break every
# Bluetooth on/off/toggle path.
bash -n "$FORK_OUT/bin/hexciri-bluetooth-power" || die "bash -n failed on bin/hexciri-bluetooth-power"

printf 'bluetooth rfkill patch: %d bluetooth-power edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 71: Bluetooth off blocks only hci* rfkill switches (upstream #20378)"
