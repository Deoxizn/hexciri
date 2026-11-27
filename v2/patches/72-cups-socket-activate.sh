#!/usr/bin/env bash

# Hexciri fork patch 72: socket-activate CUPS so cupsd starts on demand.
# Forward-port of omarchy PR #20422 ("Socket-activate CUPS", rework).
#
# What it does (PR behavior, unchanged): cups.service is disabled and
# cups.socket + cups.path are enabled instead, so cupsd no longer sits
# resident from boot: the first client (a print dialog, lpstat, hplip)
# wakes it over the socket and it stops again when idle. Printing still
# works exactly as before; only the startup changes. Devi prints (HP
# printers, hplip installed), so this was checked, not assumed:
# socket activation is transparent to clients, hplip talks to cupsd
# through /run/cups/cups.sock and port 631, both owned by cups.socket,
# and no CUPS config changes. Upstream's acceptance test asserts the
# same thing: lpstat answers, the service activates on demand, and it
# stays inactive until a client connects.
#
# Fork adaptations (this is the rework half; read before assuming the
# patch missed a file):
# - Upstream's install/config/enable-services.sh hunk has NO landing in
#   the fork: install/config/ is never copied into FORK_OUT (only
#   install/helpers/ is), install.sh never references enable-services.sh,
#   and the fork enables its services in install.sh's "Verifying
#   EndeavourOS services" block, which does not include cups at all.
#   CUPS on a Hexciri machine comes enabled from the EndeavourOS base,
#   not from the fork installer. There is no fork file carrying a
#   "cups.service" line to edit, so staging a fork copy of
#   enable-services.sh would be a dead file nothing runs.
# - Upstream's bin/omarchy-upgrade-to-quattro hunk is SKIPPED:
#   install.sh explicitly skips omarchy-upgrade-to-quattro (it is an
#   Omarchy-to-quattro migrator, not a Hexciri path).
# - What IS ported is the half that matters on Devi's existing machines:
#   upstream's migrations/1795788620.sh. The fork has no migrations/
#   dir and no migrations runner, so this patch IS the migration
#   equivalent: it runs at install/update time (patches run on every
#   hexciri update, on a fresh fork tree) and converges the live system
#   to socket activation, using the migration's own logic verbatim in
#   shape: a pending stamp under /var/lib/hexciri/migrations/ (renamed
#   from /var/lib/omarchy/migrations/) records that the switch started
#   before cups.service is disabled (whose Also= also disables
#   cups.socket and cups.path), so an interrupted run finishes enabling
#   them on retry; installs where CUPS was deliberately disabled stay
#   untouched (service not enabled and no pending stamp means exit 0).
#   The switch is idempotent: once socket-activated, re-runs are a
#   no-op, so repeated hexciri updates do not touch service state.
#
# Safety notes:
# - The switch only fires when cups.service reports enabled. A masked,
#   disabled, or absent CUPS (not installed) is left alone.
# - The pending stamp is removed only after the socket and path are
#   enabled; if the run dies between disable and enable, the next
#   hexciri update sees the stamp and completes the switch instead of
#   leaving CUPS disabled entirely.
# - Active print jobs are not stopped mid-upgrade: `disable` only
#   removes the boot enablement, it does not stop a running cupsd, and
#   `enable --now` on the socket starts listening immediately, so a
#   running cupsd keeps serving until it exits on idle.
# - No new bin/ is added (nothing for install.sh's allowlist to carry)
#   and nothing is staged under FORK_OUT: this patch's payload is the
#   live-system convergence above. FORK_OUT is still required as $1 by
#   the apply.sh contract, but the patch writes no files into it.
#
# Skipped from the PR: migrations/1795788620.sh itself (no runner; its
# logic lives in this patch instead), test/acceptance.d/cups-test.sh
# (test/ is not in FORK_OUT; the sim replays its assertions against a
# mocked systemctl instead, see the README section).
#
# Standalone: bash v2/patches/72-cups-socket-activate.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. HEXCIRI_CUPS_MIGRATION_DIR
#   overrides the pending-stamp directory (sims/tests only; default is
#   /var/lib/hexciri/migrations). Idempotent: re-running on an
#   already socket-activated machine prints "already socket-activated,
#   skipping" and changes nothing.
#
# Syntax check note: there are no staged files to validate; the end of
# the patch verifies live state with systemctl (socket and path enabled,
# service not enabled) and dies if the switch did not converge. bash -n
# applies to this script itself.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "72-cups-socket-activate.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "72-cups-socket-activate.sh: $1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}
CHANGED=0

# --- Socket-activate CUPS, omarchy PR #20422 (migration equivalent) ---
step "Socket-activating CUPS so cupsd starts on demand"

# No systemd here (sim, container, chroot): nothing to converge, and the
# patch must not fail an install that has no live system to touch.
if ! command -v systemctl >/dev/null 2>&1; then
  printf 'cups: no systemctl on PATH, skipping (no live system to converge)\n' >>"$_patch_log"
  printf 'cups socket-activate patch: %d service edits applied\n' "$CHANGED" >>"$_patch_log"
  info "  patch 72: CUPS socket activation skipped (no systemctl here)"
  exit 0
fi

CUPS_MIGRATION_DIR="${HEXCIRI_CUPS_MIGRATION_DIR:-/var/lib/hexciri/migrations}"
pending="$CUPS_MIGRATION_DIR/1795788620-cups-socket"

# Deliberately disabled installs stay untouched: only a currently-enabled
# cups.service, or a pending stamp from an interrupted run, proceeds.
if ! systemctl is-enabled --quiet cups.service 2>/dev/null && [ ! -e "$pending" ]; then
  printf 'cups: cups.service not enabled and no pending switch, skipping\n' >>"$_patch_log"
  printf 'cups socket-activate patch: %d service edits applied\n' "$CHANGED" >>"$_patch_log"
  info "  patch 72: CUPS already socket-activated or deliberately disabled, nothing to do"
  exit 0
fi

# Record that the switch started before disabling cups.service (whose
# Also= also disables cups.socket and cups.path), so an interrupted run
# finishes enabling them on retry.
sudo install -d -m 0755 "$CUPS_MIGRATION_DIR"
sudo touch "$pending"
sudo systemctl disable cups.service
sudo systemctl enable --now cups.socket cups.path
sudo rm -f "$pending"
CHANGED=1
printf 'patched: cups.service disabled, cups.socket + cups.path enabled\n' >>"$_patch_log"

# --- validation: the switch must have converged ---
systemctl is-enabled --quiet cups.socket || die "cups.socket is not enabled after the switch"
systemctl is-enabled --quiet cups.path || die "cups.path is not enabled after the switch"
if systemctl is-enabled --quiet cups.service 2>/dev/null; then
  die "cups.service is still enabled after the switch"
fi
systemctl is-active --quiet cups.socket || die "cups.socket is not listening after the switch"
printf 'cups socket-activate patch: %d service edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 72: CUPS socket-activated (PR #20422; cupsd now starts on demand, printing unaffected)"
