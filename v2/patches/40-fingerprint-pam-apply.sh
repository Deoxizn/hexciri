#!/usr/bin/env bash
# Hexciri fork patch 40: fingerprint PAM-apply helper + setup refactor.
# Forward-port of omarchy PR #20337 (commit 10870ca48, "Add a full-screen
# fingerprint setup panel"), PORTABLE SLICE ONLY.
#
# What it does: the PAM configuration that used to live inline in
# hexciri-setup-security-fingerprint (setup_pam_config) now lives in its own
# helper, bin/hexciri-apply-fingerprint-pam, and the setup script calls the
# helper once a print is enrolled and verified. The helper puts fingerprint
# first in the sudo and polkit PAM stacks (pam_fprintd.so sufficient, with
# the clamshell gate before it: when the lid is shut the reader is
# unreachable, so the gate skips fingerprint and PAM drops straight to the
# password prompt instead of blocking on the reader until it times out).
# Real for the Framework 13's fingerprint reader. This is the prerequisite
# for open PR #20348.
#
# Fork adaptations:
# - Renamed: hexciri-apply-fingerprint-pam, hexciri-hw-laptop-closed.
# - The clamshell gate points at
#   /usr/share/hexciri/bin/hexciri-hw-laptop-closed: the installer's rename
#   map has a fixed-path rule for exactly this (bins live in
#   /usr/share/hexciri/bin, never /usr/bin), and the helper's comments are
#   rewritten to say so (the map alone would leave them pointing at
#   /usr/bin in prose).
# - The setup refactor does NOT add upstream's panel summon: there is no
#   hexciri.fingerprint panel in the fork (the panel QML needs shell panel
#   infra that is unverified, and the new omarchy.fingerprint plugin needs
#   rename work), so there is nothing to summon. The terminal flow is the
#   only flow: --terminal is declared in the metadata (as upstream) and
#   accepted, and the script runs its enrollment inline as before. When a
#   panel lands, the summon branch can be added then.
# - setup_pam_config is deleted outright (not left as a wrapper): the
#   helper is the only copy of that logic now, so the gate cannot drift
#   between files.
#
# Skipped from the PR, deliberately:
# - shell/plugins/panels/fingerprint/* + manifest (the panel; see above).
# - bin/omarchy-setup-security-fingerprint-enroll (the panel's event
#   backend: status/enroll/demo subcommands, run as root through pkexec;
#   with no panel it has no caller).
# - install/user/first-run/setup-fingerprint.hook (the fork has no
#   install/user/first-run/ provisioning tree; the fingerprint first-run
#   hook already had a live flock issue in the fork, fixed by disabling it).
# - i18n shell.json, menu.jsonc, docs/file-layout.md, shell/plugins/
#   README.md, manual/37-hardware-authentication.md (no fork landing:
#   shell panel catalogs and manual/ are not in FORK_OUT).
# - test/ changes (test/ is not in FORK_OUT; no existing patch touches
#   tests).
#
# Standalone: bash v2/patches/40-fingerprint-pam-apply.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: both edited files are bash, so the end-of-patch
# check is bash -n on each. The helper itself is never executed by this
# patch (it edits /etc/pam.d, which needs a real enrolled print).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "40-fingerprint-pam-apply.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
CHANGED=0
# Write a new file from stdin; idempotent via content compare, dies rather
# than clobbering a different existing file. $1 = FORK_OUT-relative path,
# $2 = mode (755 for bin/, 644 for config/drop-ins).
install_new_file() {
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
# --- Fingerprint PAM-apply helper + setup refactor, omarchy PR #20337 ---
install_new_file "bin/hexciri-apply-fingerprint-pam" 755 <<'HEXCIRI_EOF_FPRINT_PAM'
#!/bin/bash

# omarchy:summary=Put fingerprint authentication first in the sudo and polkit PAM stacks
# omarchy:requires-sudo=true
# omarchy:hidden=true

set -e

# The fingerprint setup runs this once a print is enrolled and verified: from a
# terminal as the user, where sudo asks, and from the fingerprint panel's
# helper, which pkexec has already made root.
as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# A clamshell gate runs before pam_fprintd in every stack: when the lid is
# shut the reader is unreachable, so it skips fingerprint (success=1) and PAM
# drops straight to the password prompt instead of blocking on the reader
# until it times out. Lid open → fingerprint, then password as the fallback.
#
# pam_exec needs a literal absolute path (no env expansion). Point at the
# fixed /usr/share/hexciri/bin path the placed Hexciri tree always provides,
# so the gate keeps working across updates: the installer places bin/ there
# on every fork+placement run, and no dev-link overlay moves it.
fprintd_gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/share/hexciri/bin/hexciri-hw-laptop-closed"

# Configure sudo
if ! grep -q pam_fprintd.so /etc/pam.d/sudo; then
  echo "Configuring sudo for fingerprint authentication..."
  as_root sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/sudo
fi
if ! grep -q 'hexciri-hw-laptop-closed' /etc/pam.d/sudo; then
  echo "Adding clamshell gate to sudo..."
  # Insert immediately before pam_fprintd so success=1 skips exactly it.
  as_root sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/sudo
fi

# Configure polkit
if [[ -f /etc/pam.d/polkit-1 ]]; then
  if ! grep -q 'pam_fprintd.so' /etc/pam.d/polkit-1; then
    echo "Configuring polkit for fingerprint authentication..."
    as_root sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/polkit-1
  fi
  if ! grep -q 'hexciri-hw-laptop-closed' /etc/pam.d/polkit-1; then
    echo "Adding clamshell gate to polkit..."
    as_root sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/polkit-1
  fi
else
  echo "Creating polkit configuration with fingerprint authentication..."
  # omarchy:heredoc-expands paths=none -- $fprintd_gate is the literal PAM
  # line defined above, shared with the sed insertions so the gate cannot
  # drift between files. The only path in it is the fixed /usr/share/hexciri/bin one.
  as_root tee /etc/pam.d/polkit-1 >/dev/null <<EOF
$fprintd_gate
auth      sufficient pam_fprintd.so
auth      include system-auth

account   include system-auth
password  include system-auth
session   include system-auth
EOF
fi
HEXCIRI_EOF_FPRINT_PAM
PY_COUNT_FILE="$(mktemp)"
export PY_COUNT_FILE
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import sys

root = sys.argv[1]
changed = []
SETUP_PAM_BLOCK = r"""setup_pam_config() {
  # A clamshell gate runs before pam_fprintd in every stack: when the lid is
  # shut the reader is unreachable, so it skips fingerprint (success=1) and PAM
  # drops straight to the password prompt instead of blocking on the reader
  # until it times out. Lid open → fingerprint, then password as the fallback.
  #
  # pam_exec needs a literal absolute path (no env expansion). Point at the
  # fixed /usr/bin path the hexciri package always provides, so the gate keeps
  # working across package installs and dev-link — the latter overlays
  # $HEXCIRI_PATH trees but leaves /usr/bin untouched.
  local fprintd_gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/share/hexciri/bin/hexciri-hw-laptop-closed"

  # Configure sudo
  if ! grep -q pam_fprintd.so /etc/pam.d/sudo; then
    echo "Configuring sudo for fingerprint authentication..."
    sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/sudo
  fi
  if ! grep -q 'hexciri-hw-laptop-closed' /etc/pam.d/sudo; then
    echo "Adding clamshell gate to sudo..."
    # Insert immediately before pam_fprintd so success=1 skips exactly it.
    sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/sudo
  fi

  # Configure polkit
  if [[ -f /etc/pam.d/polkit-1 ]]; then
    if ! grep -q 'pam_fprintd.so' /etc/pam.d/polkit-1; then
      echo "Configuring polkit for fingerprint authentication..."
      sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/polkit-1
    fi
    if ! grep -q 'hexciri-hw-laptop-closed' /etc/pam.d/polkit-1; then
      echo "Adding clamshell gate to polkit..."
      sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/polkit-1
    fi
  else
    echo "Creating polkit configuration with fingerprint authentication..."
    # omarchy:heredoc-expands paths=none -- $fprintd_gate is the literal PAM
    # line defined above, shared with the two sed insertions so the gate cannot
    # drift between files. The only path in it is the fixed /usr/bin one.
    sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
$fprintd_gate
auth      sufficient pam_fprintd.so
auth      include system-auth

account   include system-auth
password  include system-auth
session   include system-auth
EOF
  fi
}

"""
SETUP_REL = "bin/hexciri-setup-security-fingerprint"
try:
    with open(root + "/" + SETUP_REL) as f:
        s = f.read()
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping (setup refactor)" % SETUP_REL)
    s = None
if s is not None:
    # Delete setup_pam_config outright: the helper is now the only copy.
    # (A plain REPLACEMENTS entry cannot express a deletion: new="" is
    # trivially "already present", so this is handled explicitly.)
    if SETUP_PAM_BLOCK not in s:
        print("setup: setup_pam_config already removed, skipping")
    else:
        s = s.replace(SETUP_PAM_BLOCK, "", 1)
        changed.append("setup: delete inline setup_pam_config (moved to hexciri-apply-fingerprint-pam)")
    REPLACEMENTS = [
        ("setup: call hexciri-apply-fingerprint-pam after verified enrollment",
         "    setup_pam_config\n",
         "    hexciri-apply-fingerprint-pam\n"),
        ("setup: declare --terminal arg (panel summon not ported: no hexciri.fingerprint panel)",
         "# omarchy:summary=Set up fingerprint authentication for sudo, polkit, and lock screen\n",
         "# omarchy:summary=Set up fingerprint authentication for sudo, polkit, and lock screen\n# omarchy:args=[--terminal]\n"),
    ]
    for label, old, new in REPLACEMENTS:
        if new in s:
            print("%s: already present, skipping" % label)
            continue
        if s.count(old) != 1:
            print("ERROR: anchor not found exactly once in %s (count %d): %s" % (SETUP_REL, s.count(old), label), file=sys.stderr)
            sys.exit(1)
        s = s.replace(old, new, 1)
        changed.append(label)
    # Drift guard for the deletion above: its skip test is "old absent",
    # so a drifted block would skip the delete while the call-site edit
    # still lands, leaving a dead setup_pam_config behind. After this
    # refactor the name must occur nowhere in the file; die loud if it does.
    if "setup_pam_config" in s:
        print("ERROR: setup_pam_config still present in %s after the refactor (block drifted?)" % SETUP_REL, file=sys.stderr)
        sys.exit(1)
    with open(root + "/" + SETUP_REL, "w") as f:
        f.write(s)
with open(os.environ["PY_COUNT_FILE"], "w") as f:
    f.write(str(len(changed)))
for label in changed:
    print("patched: %s" % label)
print("fingerprint-pam-apply python edits: %d" % len(changed))
PY
py_edits="$(cat "$PY_COUNT_FILE")"
rm -f "$PY_COUNT_FILE"
total_edits=$((py_edits + CHANGED))
printf 'fingerprint-pam-apply patch: %d file edits applied\n' "$total_edits" >>"$_patch_log"

# Syntax-check the edited files. Both are bash.
bash -n "$FORK_OUT/bin/hexciri-apply-fingerprint-pam" || die "bash -n failed on patched hexciri-apply-fingerprint-pam"
bash -n "$FORK_OUT/bin/hexciri-setup-security-fingerprint" || die "bash -n failed on patched hexciri-setup-security-fingerprint"
info "  fingerprint-pam-apply: fingerprint PAM config now lives in hexciri-apply-fingerprint-pam (PR #20337 portable slice; panel not built)"
