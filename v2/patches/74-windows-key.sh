#!/usr/bin/env bash
# Hexciri fork patch 74: Windows product key from firmware (Devi 2026-11-27).
# Forward-port of upstream bin/omarchy-windows-key at the pin
# (94a8c3c3321129fae87a329947711355897e69fd): prints the OEM Windows
# product key from /sys/firmware/acpi/tables/MSDM, sudo fallback when the
# table is unreadable, `strings` then `cat` extraction, regex
# [A-Z0-9]{5}(-[A-Z0-9]{5}){4}, exits 1 with "No Windows license key
# found in firmware." when the table is absent. Upstream has NO menu row
# calling it (verified: zero callers at the pin) -- Hexciri gets one
# where upstream never had it.
#
# Fork adaptations:
# - The bin ships via install.sh's bin copy loop, renamed omarchy- ->
#   hexciri- by the loop itself (bin/hexciri-windows-key). The loop only
#   copies what is_allowed_bin() admits, and the live allowlist has no
#   windows-key entry, so this patch carries a companion edit to
#   v2/install.sh (bare `windows-key`, staged alongside) and DIES unless
#   that entry is present (patch 52/56 guard pattern). The entry is
#   deliberately the bare name, NOT `windows-*`: a glob would also admit
#   windows-vm, the Docker/KVM VM manager that is explicitly out (see
#   the allowlist comment). The patch also dies if a `windows-*` glob
#   ever appears in is_allowed_bin.
# - Env override: upstream OMARCHY_MSDM_PATH. The fork rename rule says
#   rename, and install.sh's rewrite_contents already does it: its
#   OMARCHY_ -> HEXCIRI_ byte rule turns the variable into
#   HEXCIRI_MSDM_PATH when the fork is built, and `omarchy-cmd-present`
#   into `hexciri-cmd-present` via the omarchy- rule. This patch does NOT
#   re-rename the bin by hand; it verifies the rename actually landed
#   (HEXCIRI_MSDM_PATH present, OMARCHY_MSDM_PATH and omarchy-cmd-present
#   gone) and dies loudly if a future pin changes the upstream text so
#   the rename no longer applies. The `# omarchy:summary=` /
#   `# omarchy:requires-sudo=true` metadata lines legitimately remain:
#   the `omarchy:` prefix is a deliberate non-rename in rewrite_contents.
# - Menu row: System > "Windows product key", placed immediately AFTER
#   system.lock, anchored on that dotted key (never retyped PUA glyphs;
#   icon:"" per the patch 51 precedent, a patch-53-style sibling copy can
#   give it a glyph later). The anchor is stable in every fork state:
#   patch 02 never drops system.lock, and the row lands in the same place
#   whether patch 73 (screensaver, built in parallel) has landed or not --
#   if it has, the order is About, Screensaver, Lock, Windows product
#   key, Suspend...; if not, About, Lock, Windows product key,
#   Suspend.... No aliases (upstream menu rule: aliases are for
#   established alternate names only). Action runs the bin in a floating
#   terminal with the presentation wrapper, so the key stays on screen
#   to read/copy (hexciri-show-done holds it) instead of flashing past.
#
# Devi context (2026-11-27): his desktop is a CLX prebuilt; key
# retrieval did NOT work when he tried it on his earlier
# stellarchy/noctarchy setups, yet Windows installs auto-license Home
# with no prompt. A live "No Windows license key found in firmware." on
# his desktop is therefore a plausible CORRECT outcome, not proof the
# port is broken -- the auto-activation is likely a Microsoft digital
# entitlement (hardware hash) with no key embedded in an MSDM table, or
# the table is unreadable on his box. Do not treat a live not-found as a
# patch failure, and do not add extra retrieval methods beyond the
# upstream MSDM logic without flagging them as new scope first. (Note:
# the v1 shell's root bin/hexciri-hw already has a wider windows_key
# sweep -- MSDM + OA3 efivars + SMBIOS oem_strings + all ACPI tables --
# but that is v1-shell scope, NOT ported here; flag it as a possible
# follow-up, do not build it in this patch.)
#
# Standalone: bash v2/patches/74-windows-key.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "74-windows-key.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "74-windows-key.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 0. Guard: install.sh must allowlist the bare name windows-key ---
# The bin only ships if is_allowed_bin() admits it; without the entry the
# copy loop silently skips upstream omarchy-windows-key and the menu row
# below would call a missing command. Scoped to the function body so a
# stray comment mention cannot fake a pass (patch 52/56 pattern, stricter).
_INSTALL_SH="$HEXCIRI_REPO_ROOT/v2/install.sh"
[ -f "$_INSTALL_SH" ] || die "v2/install.sh not found under HEXCIRI_REPO_ROOT ($HEXCIRI_REPO_ROOT), cannot verify the bin allowlist"
_ALLOW_BODY="$(awk '/^is_allowed_bin\(\)/,/^}/' "$_INSTALL_SH")"
[ -n "$_ALLOW_BODY" ] || die "is_allowed_bin() not found in v2/install.sh, cannot verify the bin allowlist"
case "$_ALLOW_BODY" in
  *'windows-key'*) ;;
  *) die "v2/install.sh does not list windows-key in the bin allowlist (is_allowed_bin), add the bare name before this patch can apply (upstream bin/omarchy-windows-key would otherwise never ship)" ;;
esac
# A glob in the case list would read `windows-* |` (or `windows-*)` as
# the last entry); the explanatory comment below the list says
# "windows-* glob" with no such suffix, so it cannot fake a hit.
if printf '%s' "$_ALLOW_BODY" | grep -qE 'windows-\*( \||\))'; then  die "v2/install.sh lists a windows-* glob in the bin allowlist, which would also admit windows-vm (Docker/KVM VM manager, explicitly out); the entry must be the bare name windows-key only"
fi

# --- 1. The shipped bin must be the renamed upstream one ---
# Patches run after copy_subsets + rename_files + rewrite_contents, so
# FORK_OUT/bin/hexciri-windows-key must already exist here with the
# rename applied. A missing bin, or one that still carries upstream
# names, dies loudly -- never a menu row pointing at nothing.
_BIN="$FORK_OUT/bin/hexciri-windows-key"
[ -f "$_BIN" ] || die "FORK_OUT/bin/hexciri-windows-key is missing: the bin copy loop did not ship it (is_allowed_bin guard passed but the upstream file is gone at this pin?)"
[ -x "$_BIN" ] || die "FORK_OUT/bin/hexciri-windows-key is not executable"
grep -qF 'HEXCIRI_MSDM_PATH' "$_BIN" || die "hexciri-windows-key does not read HEXCIRI_MSDM_PATH: the OMARCHY_ -> HEXCIRI_ rename did not land (upstream var name changed at this pin?)"
grep -qF 'OMARCHY_MSDM_PATH' "$_BIN" && die "hexciri-windows-key still reads OMARCHY_MSDM_PATH: the rename did not apply"
grep -qF 'hexciri-cmd-present' "$_BIN" || die "hexciri-windows-key does not call hexciri-cmd-present: the omarchy- rename did not land"
grep -qF 'omarchy-cmd-present' "$_BIN" && die "hexciri-windows-key still calls omarchy-cmd-present: the rename did not apply"
grep -qF "[A-Z0-9]{5}(-[A-Z0-9]{5}){4}" "$_BIN" || die "hexciri-windows-key lost the upstream key regex"
grep -qF 'No Windows license key found in firmware.' "$_BIN" || die "hexciri-windows-key lost the upstream table-absent message"
grep -qF 'Firmware license table found, but no Windows product key could be extracted.' "$_BIN" || die "hexciri-windows-key lost the upstream no-key message"
grep -qF '/sys/firmware/acpi/tables/MSDM' "$_BIN" || die "hexciri-windows-key lost the upstream MSDM default path"

# --- 2. Menu row: System > Windows product key, after system.lock ---
# The python block prints one "patched: ..." line (or an "already present,
# skipping" line); output goes through a temp file, not straight to
# $_patch_log, so a trailing info line cannot clobber it (patch 50's
# pattern). Icon "" per patch 51: never retype a raw PUA glyph.
step "Adding System > Windows product key menu row"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 74 menu edit failed"; }
import json
import re
import sys

fork = sys.argv[1]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


try:
    with open(menu) as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output, patch 02 must be applied first" % menu)


def key_index(key):
    """Index of the line carrying dotted key `key`, or None. Dies if the
    key occurs more than once: the anchor must be unambiguous."""
    hits = [i for i, l in enumerate(lines) if ('"%s":' % key) in l]
    if len(hits) > 1:
        _die('menu key "%s" occurs %d times, refusing to guess' % (key, len(hits)))
    return hits[0] if hits else None


NEW_KEY = "system.windows-key"
NEW_ROW = ('  "system.windows-key": {"icon":"","label":"Windows product key",'
           '"action":"hexciri-launch-floating-terminal-with-presentation hexciri-windows-key"},')
NEW_ACTION = "hexciri-launch-floating-terminal-with-presentation hexciri-windows-key"

anchor = key_index("system.lock")
if anchor is None:
    _die('anchor "system.lock" not found in menu jsonc')
lock_line = lines[anchor]
if '"action":"hexciri-system-lock"' not in lock_line and '"action": "hexciri-system-lock"' not in lock_line:
    _die('anchor row system.lock does not call hexciri-system-lock: %r' % lock_line)

existing = key_index(NEW_KEY)
if existing is not None:
    if NEW_ACTION not in lines[existing]:
        _die('system.windows-key already exists with a different action: %r' % lines[existing])
    print("menu: Windows product key row already present, skipping")
else:
    lines[anchor + 1:anchor + 1] = [NEW_ROW]
    print("patched: System > Windows product key row added after system.lock")

with open(menu, "w") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: the jsonc must still parse exactly like the shell parses
# it (patch 02's check). One bad row empties the whole Super+Alt+Space menu.
with open(menu) as f:
    raw = f.read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[\}\]])', r'\1', stripped)
try:
    parsed = json.loads(stripped)
except Exception as e:  # noqa: BLE001 - any parse failure is fatal here
    _die("menu jsonc does not parse, shell would show an empty menu: %s" % e)
for r in ("apps", "appearance", "trigger", "setup", "install", "remove",
          "update", "learn", "system"):
    if r not in parsed:
        _die("menu jsonc missing root entry %s, shell would show an empty menu" % r)


def _row(key):
    row = parsed.get(key)
    if row is None:
        _die("menu jsonc missing row %s" % key)
    return row


row = _row(NEW_KEY)
if row.get("label") != "Windows product key":
    _die("windows-key row label is %r, want 'Windows product key'" % row.get("label"))
if row.get("action") != NEW_ACTION:
    _die("windows-key row action is %r, want %r" % (row.get("action"), NEW_ACTION))
if row.get("icon") != "":
    _die("windows-key row icon is %r, want empty (patch 51 precedent, no retyped PUA glyph)" % row.get("icon"))
# The anchor and its neighbours must be untouched by the insert.
lock = _row("system.lock")
if lock.get("action") != "hexciri-system-lock":
    _die("system.lock action changed: %r" % lock.get("action"))
if _row("system.about").get("label") != "About":
    _die("system.about changed")
if _row("system.suspend").get("action") != "systemctl suspend":
    _die("system.suspend action changed: %r" % _row("system.suspend").get("action"))
# No duplicate keys: json.loads keeps the last, so count in the raw text.
if raw.count('"%s":' % NEW_KEY) != 1:
    _die('menu key "%s" occurs %d times in the file'
         % (NEW_KEY, raw.count('"%s":' % NEW_KEY)))
print("menu jsonc parses (%d entries, 9 root entries, system.windows-key present)"
      % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'windows-key patch: %d menu row blocks applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 74: System > Windows product key row added (bin hexciri-windows-key, MSDM firmware key via HEXCIRI_MSDM_PATH override)"
