#!/usr/bin/env bash
# Hexciri fork patch 22: keyboard-layout label alignment at 1.25x scale.
# Forward-port of omarchy PR #20356 (head commit dae882e,
# "Align the keyboard layout label on scaled bars") into
# shell/plugins/bar/widgets/KeyboardLayout.qml.
#
# What it does (PR behavior, unchanged): the keyboard-layout WidgetButton
# gets a Translate transform whose y offset reads the scale of the monitor
# hosting its bar: 0 at 1.25x scale, 1.5 otherwise. The label is a text
# label next to optically centered glyphs, so the offset aligns it with
# the neighboring bar icons. Devi's desktop dokoz runs DP-4 at
# 3840x2160@144, scale 1.25, so this is the scale the fix targets.
#
# PR status note: upstream filed this as a DRAFT for discussion, with
# limited font and display-scale coverage and upstream before/after
# captures still pending. The diff itself is a single self-contained
# hunk in this one file, and it ports cleanly onto the pinned baseline,
# so it is built as-is; if upstream revises the draft, this patch gets
# revised with it.
#
# Fork adaptation: none needed. The PR touches no moduleName or manifest
# reference, only the WidgetButton body, so there is no
# omarchy.keyboard-layout -> hexciri.keyboard-layout rename inside this
# patch; the moduleName rename lives in the fork's own renaming step, as
# with the other bar-widget ports. The widget ships in the fork's default
# bar layout as hexciri.keyboard-layout (right section).
#
# Caveat: the widget hides itself on single-layout seats (visible
# requires multiple layouts or input methods), and Devi runs a single US
# layout, so the fix is invisible to him until he configures a second
# layout. The port is still clean and the file is shipped, so it builds.
#
# Tests: upstream's keyboard-layout shell tests are NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and no
# existing patch touches tests, so this patch does not edit a test file.
# Verification is a diff of patched vs unpatched over the pinned file
# (only the intended hunk) plus qmllint when present. This is QML-only
# layout behavior: no live bar run is possible in sim, so verification is
# diff + a careful read of the patched alignment flow.
#
# Standalone: bash v2/patches/22-keyboard-layout-scale.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is QML, not bash, so the
# end-of-patch check is qmllint when present (warning only: qmllint
# fails on missing Quickshell imports even for valid files). bash -n
# would fail on it by construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "22-keyboard-layout-scale.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Keyboard-layout label alignment at 1.25x scale, omarchy PR #20356 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The PR's hunk, verbatim: a Translate transform on the WidgetButton that
# reads the hosting monitor's scale and drops the 1.5px offset at 1.25x.
# Ported exactly as upstream wrote it, including the comment and the
# absence of blank lines around the block (the .diff hunk is +261,15:
# 6 context lines + 9 added lines, no added blanks).
TRANSFORM = """    // Align the painted language label with the neighboring bar icons.
    transform: Translate {
      y: {
        const window = root.QsWindow.window
        const monitor = window && window.screen ? Hyprland.monitorFor(window.screen) : null
        const scale = monitor && monitor.lastIpcObject ? monitor.lastIpcObject.scale : 1
        return scale === 1.25 ? 0 : 1.5
      }
    }
"""

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # KeyboardLayout.qml: the scale-aware Translate on the label button,
    # inserted between fontSize and horizontalMargin (PR #20356).
    ("shell/plugins/bar/widgets/KeyboardLayout.qml",
     "    fontSize: Style.font.caption\n"
     "    horizontalMargin: 6",
     "    fontSize: Style.font.caption\n"
     + TRANSFORM +
     "    horizontalMargin: 6",
     "KeyboardLayout label button: scale-aware Translate (PR #20356)"),
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
print("keyboard-layout-scale patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited file. It is QML, not bash, so bash -n would
# fail on it by construction and is deliberately not used here.
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/bar/widgets/KeyboardLayout.qml" || warn "qmllint reported issues on patched KeyboardLayout.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping KeyboardLayout.qml parse check"
fi
info "  keyboard-layout-scale: bar label now aligns at 1.25x scale (PR #20356)"
