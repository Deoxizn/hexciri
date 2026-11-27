#!/usr/bin/env bash
# Hexciri fork patch 35: notification IPC invokeAction skips a leaving toast.
# Forward-port of omarchy PR #20145 (commit 8660f2fd4,
# "Notification IPC invokeAction skips a leaving toast") into
# shell/plugins/notifications/Service.qml.
#
# What it does (PR behavior, unchanged): the IPC `invokeAction` handler
# now acts on `service.newestLive()` instead of `toasts.get(0)`, so
# pressing a notification button no longer hits a card that is already
# dismissing. Six lines.
#
# Fork adaptation: none. The hunk is rename-free and `newestLive()` is
# already defined and used at the pin (Service.qml). The landing file is
# the stock notification plugin, which the fork still ships: Nyxiri
# replaces the bar and the clock, not notifications.
#
# Tests: upstream's test/shell.d/notifications/logic.cjs is NOT in
# FORK_OUT (fork-shell.sh extracts only listed subsets; test/ is not
# one), and no existing patch touches tests, so this patch does not edit
# a test file. Verification is the upstream test's new invokeAction
# block replayed in sim (IPC invokeAction skips a leaving front toast
# and invokes the newest live card; empty toasts return "none") plus a
# diff of patched vs unpatched proving only the intended changes. See
# the coordinator's sim notes.
#
# Standalone: bash v2/patches/35-notification-toast-skip.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is QML only (Service.qml), so
# bash -n and node --check would fail on it by construction and are
# deliberately not used here. The end-of-patch check is qmllint when
# present, warning only: qmllint fails on missing Quickshell imports
# even for valid files.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "35-notification-toast-skip.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Notification invokeAction skips a leaving toast, omarchy PR #20145 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # IPC invokeAction(): newestLive() instead of toasts.get(0).
    ("shell/plugins/notifications/Service.qml",
     "    function invokeAction(n: int): string {\n"
     "      if (toasts.count === 0) return \"none\"\n"
     "      return service.runDeed(String(toasts.get(0).key), n - 1) ? \"ok\" : \"none\"\n"
     "    }",
     "    function invokeAction(n: int): string {\n"
     "      var key = service.newestLive()\n"
     "      if (!key) return \"none\"\n"
     "      return service.runDeed(key, n - 1) ? \"ok\" : \"none\"\n"
     "    }",
     "Service.qml invokeAction(): act on newestLive(), skip a leaving toast"),
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
print("notification-toast-skip patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited file. It is QML only, not bash and not JS,
# so bash -n and node --check would fail on it by construction and are
# deliberately not used here.
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/notifications/Service.qml" || warn "qmllint reported issues on patched Service.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping QML parse checks"
fi
info "  notification-toast-skip: IPC invokeAction skips a leaving toast (PR #20145)"
