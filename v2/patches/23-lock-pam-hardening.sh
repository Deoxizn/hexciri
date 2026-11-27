#!/bin/bash
# Hexciri fork patch 23: lock-screen PAM settlement + QML hardening
# (omarchy commit 2f5ef897e, #19970).
#
# What it does, per file (upstream, verbatim except renames noted below):
#   * shell/plugins/lock/Service.qml: onError and onCompleted can both fire
#     for one password attempt; settle each attempt once. handlePasswordFailure
#     now gates on authenticatingPassword (so a second firing is a no-op)
#     and always clears pendingPassword even when the lock was already
#     dismissed; onCompleted mirrors the same settle-first shape. Before
#     this, a double firing double-counted the failure and could leave
#     pendingPassword set after unlock.
#   * shell/plugins/dock/Dock.qml: bringForward address validation — trim,
#     force the 0x prefix, reject anything not /^0x[0-9a-f]+$/i and fall
#     back to toplevel.activate() instead of interpolating an attacker's
#     string into a Hyprland dispatch. Built against the POST-patch-20
#     bringForward (in-process dispatch, workspace argument, guards, tag
#     removal); the validation hunk preserves patch 20's !window guard and
#     guarded toplevel.activate() fallback.
#   * shell/plugins/background/Background.qml: requestNativeSize refuses
#     non-absolute paths, and the magick identify call takes "--" before
#     the path so a wallpaper path starting with "-" cannot become a flag.
#   * shell/plugins/bar/widgets/Indicators.qml: the indicator Loader only
#     resolves ids matching /^[A-Za-z0-9_-]+$/, so a crafted indicator id
#     cannot escape ../indicators/ via path traversal.
#   * shell/plugins/panels/tailscale/Panel.qml: typing "j"/"k" in the
#     Mullvad region search reaches the text field instead of moving the
#     region cursor (Down/Up still move it).
#   * shell/plugins/panels/tailscale/Service.qml: closed-panel polls stay
#     light — Mullvad exit-node list and account list only run when the
#     panel wants details; authorizeTailscaleOperator rejects usernames
#     outside /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/ instead of passing them to
#     pkexec tailscale set --operator=.
#   * shell/plugins/panels/wifiqr/Panel.qml: safeIface() validates interface
#     names (/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/) before they reach
#     hexciri-network-qr / hexciri-network-password; close() marks an
#     in-flight password fetch as an expected stop; the QR matrix read
#     guards a short row.
#
# Adaptation notes (vs upstream verbatim):
#   * Renames only: hexciri-network-qr / hexciri-network-password in the
#     wifiqr hunks (the live rename map turns generic `omarchy-` into
#     `hexciri-`). The dock validation hunk keeps patch 20's
#     hexciri-minimized-from tag handling untouched (different region).
#   * No test-file edits: test/shell.d/{dock,lock-state,network-qr,
#     tailscale}-test.sh are NOT in FORK_OUT (fork-shell.sh extracts only
#     listed subsets; test/ is not one), and no existing patch touches
#     tests. The upstream assertions were re-run by hand against the
#     patched files in sim (node vm harness); see the README section.
#   * The lock onError handler itself is unchanged: at the pin it already
#     calls root.handlePasswordFailure(), which now settles once.
#
# Standalone: bash v2/patches/23-lock-pam-hardening.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are QML, not bash, so the end-of-patch
# check is qmllint when present (warning-only: it cannot resolve the
# qs.* imports outside the running shell). bash -n would fail on them by
# construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "23-lock-pam-hardening.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Lock PAM settlement + QML hardening (omarchy #19970, 2f5ef897e) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # Background: refuse non-absolute paths for native-size probes.
    ("shell/plugins/background/Background.qml",
     "    if (!path || isVideo(path) || nativeSizes[path] !== undefined || sizeQueue.indexOf(path) !== -1) return",
     "    if (!path || String(path).charAt(0) !== \"/\" || isVideo(path) || nativeSizes[path] !== undefined || sizeQueue.indexOf(path) !== -1) return",
     "Background requestNativeSize: refuse non-absolute paths"),
    # Background: "--" before the probed path so a leading "-" is not a flag.
    ("shell/plugins/background/Background.qml",
     "    sizeProbe.command = [\"magick\", \"identify\", \"-ping\", \"-format\", \"%w %h\", sizeProbe.path]",
     "    sizeProbe.command = [\"magick\", \"identify\", \"-ping\", \"-format\", \"%w %h\", \"--\", sizeProbe.path]",
     "Background probeNextSize: pass -- before the magick path"),
    # Indicators: only plain ids resolve into ../indicators/.
    ("shell/plugins/bar/widgets/Indicators.qml",
     "      source: indicatorSlot.indicatorId ? Qt.resolvedUrl(\"../indicators/\" + indicatorSlot.indicatorId + \".qml\") : \"\"",
     "      source: /^[A-Za-z0-9_-]+$/.test(indicatorSlot.indicatorId)\n"
     "        ? Qt.resolvedUrl(\"../indicators/\" + indicatorSlot.indicatorId + \".qml\")\n"
     "        : \"\"",
     "Indicators: validate indicator id before resolving its QML"),
    # Dock bringForward: hex-address validation, against the POST-patch-20
    # form (in-process dispatch, workspace arg, guards). The !window guard
    # and the guarded toplevel.activate() fallback from patch 20 survive.
    ("shell/plugins/dock/Dock.qml",
     "  function bringForward(window) {\n"
     "    if (!window) return\n"
     "    var address = String(window.address || \"\")\n"
     "    if (!address) {\n"
     "      if (window.toplevel && typeof window.toplevel.activate === \"function\") window.toplevel.activate()\n"
     "      return\n"
     "    }\n"
     "    if (address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
     "    var target = \"window = \\\"address:\" + address + \"\\\"\"",
     "  function bringForward(window) {\n"
     "    if (!window) return\n"
     "    var address = String(window.address || \"\").trim()\n"
     "    if (address && address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
     "    if (!/^0x[0-9a-f]+$/i.test(address)) {\n"
     "      if (window.toplevel && typeof window.toplevel.activate === \"function\") window.toplevel.activate()\n"
     "      return\n"
     "    }\n"
     "    var target = \"window = \\\"address:\" + address + \"\\\"\"",
     "Dock bringForward: validate hex window address before dispatch"),
    # Lock: settle each password attempt once, and always scrub
    # pendingPassword even when the lock was already dismissed.
    ("shell/plugins/lock/Service.qml",
     "  function handlePasswordFailure() {\n"
     "    if (!lockRequested) return\n"
     "\n"
     "    authenticatingPassword = false\n"
     "    enteredPassword = \"\"\n"
     "    pendingPassword = \"\"\n"
     "    failedAttempts += 1\n"
     "    failureMessage = I18n.t(\"lock.authenticationFailed\").arg(I18n.formatNumber(failedAttempts))\n"
     "    runWake()\n"
     "  }",
     "  // onError and onCompleted can both fire; settle each password attempt once\n"
     "  // and always clear pendingPassword even if the lock was already dismissed.\n"
     "  function handlePasswordFailure() {\n"
     "    if (!authenticatingPassword) return\n"
     "\n"
     "    authenticatingPassword = false\n"
     "    pendingPassword = \"\"\n"
     "\n"
     "    if (!lockRequested) return\n"
     "\n"
     "    enteredPassword = \"\"\n"
     "    failedAttempts += 1\n"
     "    failureMessage = I18n.t(\"lock.authenticationFailed\").arg(I18n.formatNumber(failedAttempts))\n"
     "    runWake()\n"
     "  }",
     "Lock handlePasswordFailure: settle once, always scrub pendingPassword"),
    # Lock: onCompleted settles through the same once-only gate instead of
    # clearing state unconditionally and then double-counting via onError.
    ("shell/plugins/lock/Service.qml",
     "    onCompleted: function(result) {\n"
     "      root.authenticatingPassword = false\n"
     "      root.pendingPassword = \"\"\n"
     "\n"
     "      if (!root.lockRequested) return\n"
     "      if (result === PamResult.Success) root.finishUnlock()\n"
     "      else root.handlePasswordFailure()\n"
     "    }",
     "    onCompleted: function(result) {\n"
     "      if (!root.authenticatingPassword) return\n"
     "\n"
     "      if (!root.lockRequested) {\n"
     "        root.authenticatingPassword = false\n"
     "        root.pendingPassword = \"\"\n"
     "        return\n"
     "      }\n"
     "\n"
     "      if (result === PamResult.Success) {\n"
     "        root.authenticatingPassword = false\n"
     "        root.pendingPassword = \"\"\n"
     "        root.finishUnlock()\n"
     "      } else {\n"
     "        root.handlePasswordFailure()\n"
     "      }\n"
     "    }",
     "Lock passwordPam onCompleted: settle once via authenticatingPassword gate"),
    # Tailscale panel: "j"/"k" type into the Mullvad search field; only
    # Down/Up move the region cursor.
    ("shell/plugins/panels/tailscale/Panel.qml",
     "                    if (event.key === Qt.Key_Down || event.text === \"j\") {\n"
     "                      root.moveMullvadRegionCursor(1)\n"
     "                      event.accepted = true\n"
     "                      return\n"
     "                    }\n"
     "                    if (event.key === Qt.Key_Up || event.text === \"k\") {\n"
     "                      root.moveMullvadRegionCursor(-1)\n"
     "                      event.accepted = true\n"
     "                      return\n"
     "                    }",
     "                    if (event.key === Qt.Key_Down) {\n"
     "                      root.moveMullvadRegionCursor(1)\n"
     "                      event.accepted = true\n"
     "                      return\n"
     "                    }\n"
     "                    if (event.key === Qt.Key_Up) {\n"
     "                      root.moveMullvadRegionCursor(-1)\n"
     "                      event.accepted = true\n"
     "                      return\n"
     "                    }",
     "Tailscale Mullvad search: j/k type instead of moving the cursor"),
    # Tailscale service: remember whether the panel wants full details
    # once, and reuse it for the status, exit-node, and account decisions.
    ("shell/plugins/panels/tailscale/Service.qml",
     "    var launched = false\n"
     "    if (!statusProcess.running) {\n"
     "      _statusOutput = \"\"\n"
     "      _statusError = \"\"\n"
     "      refreshing = true\n"
     "      _statusFullPeers = fullPeers === true || peersWanted || _pendingFullPeers",
     "    var launched = false\n"
     "    var wantPanelDetails = fullPeers === true || peersWanted\n"
     "    if (!statusProcess.running) {\n"
     "      _statusOutput = \"\"\n"
     "      _statusError = \"\"\n"
     "      refreshing = true\n"
     "      _statusFullPeers = wantPanelDetails || _pendingFullPeers",
     "Tailscale refresh: compute wantPanelDetails once for the poll"),
    ("shell/plugins/panels/tailscale/Service.qml",
     "    } else if ((fullPeers === true || peersWanted) && !_statusFullPeers) {",
     "    } else if (wantPanelDetails && !_statusFullPeers) {",
     "Tailscale refresh: reuse wantPanelDetails for the in-flight case"),
    # Tailscale service: a closed-panel (light) poll skips the Mullvad
    # exit-node list entirely.
    ("shell/plugins/panels/tailscale/Service.qml",
     "    if (!mullvadExitNodesProcess.running) {",
     "    if (wantPanelDetails && !mullvadExitNodesProcess.running) {",
     "Tailscale refresh: skip exit-node list while the panel is closed"),
    # Tailscale service: same gating for the account list.
    ("shell/plugins/panels/tailscale/Service.qml",
     "    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000",
     "    var shouldRefreshAccounts = forceAccounts === true || (wantPanelDetails && (accounts.length === 0 || now - _lastAccountsRefreshMs > 60000))",
     "Tailscale refresh: skip account list while the panel is closed"),
    # Tailscale service: reject malformed usernames before pkexec.
    ("shell/plugins/panels/tailscale/Service.qml",
     "    if (!installed || operatorProcess.running || userName === \"\") return",
     "    if (!installed || operatorProcess.running || !/^[A-Za-z0-9_][A-Za-z0-9_.-]*$/.test(userName)) return",
     "Tailscale authorizeTailscaleOperator: validate the username"),
    # wifiqr: interface-name validation helper, ahead of close().
    ("shell/plugins/panels/wifiqr/Panel.qml",
     "  function close() {\n"
     "    root.opened = false\n"
     "    root.pendingShow = false\n"
     "    if (qrProc.running) {\n"
     "      root.expectedStop = true\n"
     "      qrProc.running = false\n"
     "    }\n"
     "    if (pwProc.running) pwProc.running = false",
     "  function safeIface(value) {\n"
     "    var name = String(value || \"\").trim()\n"
     "    return /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(name) ? name : \"\"\n"
     "  }\n"
     "\n"
     "  function close() {\n"
     "    root.opened = false\n"
     "    root.pendingShow = false\n"
     "    if (qrProc.running) {\n"
     "      root.expectedStop = true\n"
     "      qrProc.running = false\n"
     "    }\n"
     "    if (pwProc.running) {\n"
     "      root.pwExpectedStop = true\n"
     "      pwProc.running = false\n"
     "    }",
     "wifiqr: add safeIface + mark in-flight password fetch as expected stop on close"),
    # wifiqr generate(): validate the requested interface before it
    # reaches hexciri-network-qr; a bad name fails the card, not the shell.
    ("shell/plugins/panels/wifiqr/Panel.qml",
     "    qrProc.command = requestedIface\n"
     "      ? [\"hexciri-network-qr\", \"--meta\", requestedIface]\n"
     "      : [\"hexciri-network-qr\", \"--meta\"]",
     "    var rawIface = String(requestedIface || \"\").trim()\n"
     "    var validIface = safeIface(rawIface)\n"
     "    if (rawIface !== \"\" && validIface === \"\") {\n"
     "      loading = false\n"
     "      error = I18n.t(\"wifiqr.generateFailed\")\n"
     "      return\n"
     "    }\n"
     "    qrProc.command = validIface\n"
     "      ? [\"hexciri-network-qr\", \"--meta\", validIface]\n"
     "      : [\"hexciri-network-qr\", \"--meta\"]",
     "wifiqr generate: validate the interface before running the generator"),
    # wifiqr: never trust the generator's reported interface name either.
    ("shell/plugins/panels/wifiqr/Panel.qml",
     "    if (parsed.meta.iface !== \"\") iface = parsed.meta.iface",
     "    if (parsed.meta.iface !== \"\") iface = safeIface(parsed.meta.iface)",
     "wifiqr updateQr: validate the reported interface name"),
    # wifiqr togglePassword(): only a valid interface reaches
    # hexciri-network-password.
    ("shell/plugins/panels/wifiqr/Panel.qml",
     "    if (pwProc.running || !iface) return\n"
     "    passwordError = \"\"\n"
     "    // Only a deliberate new lookup lowers the canceled-fetch guard, right as\n"
     "    // it launches -- see the pwProc comment.\n"
     "    pwExpectedStop = false\n"
     "    pwProc.command = [\"hexciri-network-password\", iface]",
     "    var validIface = safeIface(iface)\n"
     "    if (pwProc.running || !validIface) return\n"
     "    passwordError = \"\"\n"
     "    // Only a deliberate new lookup lowers the canceled-fetch guard, right as\n"
     "    // it launches -- see the pwProc comment.\n"
     "    pwExpectedStop = false\n"
     "    pwProc.command = [\"hexciri-network-password\", validIface]",
     "wifiqr togglePassword: validate the interface before the password lookup"),
    # wifiqr: a short QR row no longer throws on charAt.
    ("shell/plugins/panels/wifiqr/Panel.qml",
     "                  color: root.qrRows[matrixRow].charAt(matrixColumn) === \"1\" ? \"#111111\" : \"transparent\"",
     "                  color: (root.qrRows[matrixRow] || \"\").charAt(matrixColumn) === \"1\" ? \"#111111\" : \"transparent\"",
     "wifiqr QR matrix: guard a short row before charAt"),
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
print("lock-pam-hardening patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are QML, not bash, so bash -n would
# fail on them by construction and is deliberately not used here. qmllint
# cannot resolve the qs.* imports outside the running shell, so it is
# warning-only.
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/plugins/background/Background.qml shell/plugins/bar/widgets/Indicators.qml shell/plugins/dock/Dock.qml shell/plugins/lock/Service.qml shell/plugins/panels/tailscale/Panel.qml shell/plugins/panels/tailscale/Service.qml shell/plugins/panels/wifiqr/Panel.qml; do
    qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (warning-only)"
  done
else
  warn "qmllint not found, skipping QML syntax checks"
fi
info "  lock-pam-hardening: PAM password attempts settle once; dock/wifiqr/tailscale/indicator hardening (#19970)"
