#!/usr/bin/env bash
# Hexciri fork patch 75: wider Windows-key sweep (Devi 2026-11-27).
# One edit, one patch (REVISED 2026-11-27, see below): the bin sweep.
# Bin: extend the patch-74 bin/hexciri-windows-key (upstream
#     omarchy-windows-key, MSDM only) with the v1 shell's wider sweep
#     from root bin/hexciri-hw (windows_key): MSDM first, then OA3
#     efivars, then SMBIOS oem_strings, then every ACPI table.
#     Sources, in order:
#       1. MSDM: ${HEXCIRI_MSDM_PATH:-/sys/firmware/acpi/tables/MSDM}
#          (patch 74's env override, kept verbatim as the first source)
#       2. OA3: /sys/firmware/efi/efivars/OA3MSDMvariable-* (all matches)
#       3. SMBIOS: /sys/class/dmi/id/oem_strings
#       4. All ACPI tables: cat of /sys/firmware/acpi/tables/* piped
#          through strings, run under sudo (unconditional, v1 behaviour)
#     Each file source is read with strings first, cat fallback when
#     strings is missing (hexciri-cmd-present check, v2 bin convention),
#     sudo only when the file is unreadable. A found key is validated
#     by the same 5x5 regex as patch 74: [A-Z0-9]{5}(-[A-Z0-9]{5}){4}
#     (grep -aoEm1, first match wins, first source with a key wins).
#     When nothing is found anywhere: exit 1 with "No Windows license
#     key found in firmware (checked MSDM/OA3/SMBIOS + all ACPI
#     tables)." (the v1 message; patch 74's two MSDM-only messages go
#     away with the MSDM-only early exit they belonged to).
# REVISED 2026-11-27: the menu-icon edit that was here is REMOVED.
# It copied the icon from the upstream source tree next to FORK_OUT,
# but on a live update that tree is not there (0 candidates under
# /tmp/hexciri-install.*), so the edit died and aborted the whole
# update -- the exact failure its own header warned about. The icon
# was cosmetic; the row moves to Setup under patch 76 and keeps
# icon:"". If the glyph is ever wanted, it needs a source that exists
# in update mode, not this lookup.
#
# Fork adaptations / scope notes (bin):
# - No new env overrides: v1 has only HEXCIRI_MSDM_PATH, and this port
#   adds none. The OA3/SMBIOS/ACPI paths are the v1 literals. That
#   makes the sweep untestable against fake files by env var alone, so
#   the behaviour sims run the literal bin under bwrap with fake /sys
#   trees bind-mounted in (see the sim script), not a rewritten bin.
# - No new hard dependencies: strings degrades to cat, a missing or
#   failing sudo degrades to "no key from that source" (call sites use
#   `|| true`), grep is already required by patch 74. No dmidecode:
#   oem_strings is read straight from sysfs, as in v1.
# - This patch touches the key-extraction logic ONLY. No install.sh
#   companion edit (the windows-key allowlist entry from patch 74
#   already ships the bin), no menu change at all (patch 76 moves the
#   row to Setup; the wider sweep is behind that row wherever it sits).
#
# Devi context (2026-11-27): desktop is a CLX prebuilt; key retrieval
# did NOT work on his earlier stellarchy/noctarchy setups, yet Windows
# installs auto-license Home with no prompt. He ran the patch-74 row
# on the CLX desktop: "No Windows license key found in firmware."
# plus the floating terminal's "Failed (exit code 1)" line -- that is
# the EXPECTED MSDM-only outcome on that box, not a bug, and the wider
# sweep is exactly what might change the answer. A live not-found
# AFTER this patch still means "no key in any firmware table", not a
# broken port.
#
# Standalone: bash v2/patches/75-wider-key-sweep.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-swept tree prints "already present, skipping" for each
#   edit and changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "75-wider-key-sweep.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "75-wider-key-sweep.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 0. Guard: the shipped bin must be the patch-74 MSDM-only one ---
# Patches run after copy_subsets + rename_files + rewrite_contents and
# after patch 74, so FORK_OUT/bin/hexciri-windows-key must already exist
# here with the rename applied and the MSDM-only body -- or the swept
# body from a previous run of this patch (idempotency: a re-run skips
# the splice and still does the icon edit below). A missing bin or an
# unrenamed bin dies loudly -- never a silent no-op, never a double
# splice.
_BIN="$FORK_OUT/bin/hexciri-windows-key"
[ -f "$_BIN" ] || die "FORK_OUT/bin/hexciri-windows-key is missing: patch 74 must be applied first (bin copy loop + allowlist)"
[ -x "$_BIN" ] || die "FORK_OUT/bin/hexciri-windows-key is not executable"
grep -qF 'MSDM=${HEXCIRI_MSDM_PATH:-/sys/firmware/acpi/tables/MSDM}' "$_BIN" || die "hexciri-windows-key does not read HEXCIRI_MSDM_PATH: the patch-74 rename did not land (upstream var name changed at this pin?)"
grep -qF 'OMARCHY_MSDM_PATH' "$_BIN" && die "hexciri-windows-key still reads OMARCHY_MSDM_PATH: the rename did not apply"
if grep -qF 'sweep_acpi_tables' "$_BIN"; then
  info "windows-key wider sweep already present, skipping bin edit"
else
  grep -qF 'if [[ ! -e $MSDM ]]; then' "$_BIN" || die "hexciri-windows-key has no MSDM-only early exit and no sweep: not the patch-74 bin (upstream text changed?)"
  grep -qF 'read_msdm() {' "$_BIN" || die "hexciri-windows-key has no read_msdm helper: not the patch-74 bin"

# --- 1. Replace the MSDM-only body with the wider sweep ---
# The python block prints one "patched: ..." line (or an "already
# present, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it
# (patch 50's pattern). The splice keeps the shebang, the omarchy:
# metadata lines, `set -euo pipefail`, and the MSDM assignment, and
# replaces everything after the MSDM line with the v1 sweep body.
step "Widening hexciri-windows-key sweep (MSDM + OA3 + SMBIOS + ACPI tables)"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 75 bin edit failed"; }
import sys

fork = sys.argv[1]
binpath = fork + "/bin/hexciri-windows-key"

NEW_BODY = '''
# Wider sweep, ported from the v1 shell (root bin/hexciri-hw,
# windows_key): MSDM first, then OA3 efivars, then SMBIOS oem_strings,
# then every ACPI table. Patch 74 shipped MSDM only; a CLX prebuilt
# that auto-licenses Windows (digital entitlement) may keep its key in
# one of the other tables instead -- or in none of them, in which case
# the not-found message below is the correct outcome, not a failure.

extract_key() {
  grep -aoEm1 '[A-Z0-9]{5}(-[A-Z0-9]{5}){4}'
}

scan_file() { # <path> -- strings first, cat fallback; sudo for root-only files
  local path="$1" reader=strings
  hexciri-cmd-present strings || reader=cat
  if [[ -r $path ]]; then
    "$reader" "$path" 2>/dev/null | extract_key
  else
    sudo "$reader" "$path" 2>/dev/null | extract_key
  fi
}

sweep_acpi_tables() {
  local cmd
  if hexciri-cmd-present strings; then
    cmd='for f in /sys/firmware/acpi/tables/*; do [ -f "$f" ] && cat "$f" 2>/dev/null; done | strings'
  else
    cmd='for f in /sys/firmware/acpi/tables/*; do [ -f "$f" ] && cat "$f" 2>/dev/null; done'
  fi
  sudo bash -c "$cmd" 2>/dev/null | extract_key
}

key=""
sources=("$MSDM")
if compgen -G '/sys/firmware/efi/efivars/OA3MSDMvariable-*' >/dev/null 2>&1; then
  for path in /sys/firmware/efi/efivars/OA3MSDMvariable-*; do
    [[ -e $path ]] && sources+=("$path")
  done
fi
sources+=("/sys/class/dmi/id/oem_strings")

for path in "${sources[@]}"; do
  [[ -e $path && -f $path ]] || continue
  key="$(scan_file "$path" || true)"
  [[ -n $key ]] && break
done

if [[ -z $key ]] && compgen -G '/sys/firmware/acpi/tables/*' >/dev/null 2>&1; then
  key="$(sweep_acpi_tables || true)"
fi

if [[ -z $key ]]; then
  echo "No Windows license key found in firmware (checked MSDM/OA3/SMBIOS + all ACPI tables)." >&2
  exit 1
fi

printf '%s\\n' "$key"
'''


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


try:
    with open(binpath) as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output, patch 74 must be applied first" % binpath)

anchor = 'MSDM=${HEXCIRI_MSDM_PATH:-/sys/firmware/acpi/tables/MSDM}'
hits = [i for i, l in enumerate(lines) if anchor in l]
if len(hits) != 1:
    _die('MSDM assignment occurs %d times, refusing to guess' % len(hits))
msdm_idx = hits[0]
tail = "\n".join(lines[msdm_idx + 1:])
# The region being replaced must be the patch-74 MSDM-only body, not
# something else that happens to carry the same assignment line.
for needle in ('if [[ ! -e $MSDM ]]; then', 'read_msdm() {',
               'extract_key() {',
               'No Windows license key found in firmware.',
               'Firmware license table found, but no Windows product key could be extracted.'):
    if needle not in tail:
        _die('replaced region lacks %r: not the patch-74 bin' % needle)
if 'sweep_acpi_tables' in tail or 'oem_strings' in tail:
    _die('replaced region already contains sweep code, refusing to splice twice')

if 'sweep_acpi_tables' in "\n".join(lines):
    print("windows-key wider sweep already present, skipping")
else:
    new_lines = lines[:msdm_idx + 1] + NEW_BODY.splitlines()
    with open(binpath, "w") as f:
        f.write("\n".join(new_lines) + "\n")
    print("patched: hexciri-windows-key widened to MSDM + OA3 + SMBIOS + ACPI tables sweep")

# --- validation: the spliced bin must be exactly the intended shape ---
with open(binpath) as f:
    raw = f.read()
for needle in ('MSDM=${HEXCIRI_MSDM_PATH:-/sys/firmware/acpi/tables/MSDM}',
               'sweep_acpi_tables', 'OA3MSDMvariable-',
               '/sys/class/dmi/id/oem_strings',
               'No Windows license key found in firmware (checked MSDM/OA3/SMBIOS + all ACPI tables).',
               "[A-Z0-9]{5}(-[A-Z0-9]{5}){4}",
               'hexciri-cmd-present strings'):
    if needle not in raw:
        _die('spliced bin lacks %r' % needle)
for gone in ('read_msdm() {', 'if [[ ! -e $MSDM ]]; then',
             'No Windows license key found in firmware.',
             'Firmware license table found, but no Windows product key could be extracted.',
             'OMARCHY_MSDM_PATH'):
    if gone in raw:
        _die('spliced bin still contains patch-74-only text %r' % gone)
if raw.count('sweep_acpi_tables') != 2:
    _die('sweep_acpi_tables occurs %d times, want 2 (definition + call)'
         % raw.count('sweep_acpi_tables'))
print("bin shape verified (sweep present, MSDM-only body gone)")
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"
fi

# --- 2. The spliced bin must still parse ---
bash -n "$_BIN" || die "hexciri-windows-key fails bash -n after the splice"

printf 'windows-key sweep patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 75: hexciri-windows-key widened to MSDM + OA3 + SMBIOS + all-ACPI-tables sweep (v1 hexciri-hw port)"
