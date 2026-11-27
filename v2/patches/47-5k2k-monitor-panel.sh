#!/usr/bin/env bash
# Hexciri fork patch 47: 5K2K monitor label + queued text-size steps.
# Forward-port of omarchy PR #20026 (commit 6169f05c8, "Label 5120x2160
# as 5K2K") and PR #20143 (commit c49f09b82, "Queue rapid monitor
# text-size steps") into shell/plugins/panels/monitor/Model.js and
# shell/plugins/panels/monitor/Panel.qml.
#
# What it does (PR behavior, unchanged):
# - #20026: a 5120x2160 mode is labeled "5K2K" instead of "4K".
#   One line in resolutionLabel(), ordered after the 5K check and
#   before the 4K check. Devi has no 5120x2160 display, so this is a
#   correctness label only, no direct benefit to him.
# - #20143: rapid text-size steps queue the latest value
#   (pendingTextSize) while textScaleProc is running instead of
#   dropping it and leaving textSizePreviewIndex stuck, and a mouse
#   slider release keeps the preview stop until Style catches up
#   (or clears it on failure). Step/slider input goes through a new
#   applyTextSizeStop(); the textScaleProc completion handler drains
#   the queue or clears the preview.
#
# Fork adaptation: the text-size CLI is fork-renamed
# (`hexciri-display-text-size`; the installer's rename map produces
# it before patches run), so the setTextSize anchor and the new code
# use that name. No other renames in the changed lines. The landing
# files are the stock monitor panel, which the fork still ships
# (patch 17 already edits the same Panel.qml for brightness; none of
# its edits touch these six anchors, and the onOpenedChanged anchor
# here starts below the line patch 17 adds inside the opened branch).
# Hexciri Settings is the fork's monitor UI for layout/scale, but the
# stock monitor panel's text-size slider and resolution labels are
# still live in the shell, so this ports.
#
# Tests: upstream's test/shell.d/monitor-test.sh is NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and
# no existing patch touches tests, so this patch does not edit a test
# file. Verification is the upstream tests' new assertions replayed in
# sim (resolutionLabel('5120x2160') is '5K2K' with 6K/5K/4K/1440p
# unchanged; rapid text-size steps queue and drain in order; slider
# release previews the stop and clears on failure) plus a diff of
# patched vs unpatched proving only the intended changes. See the
# coordinator's sim notes.
#
# Standalone: bash v2/patches/47-5k2k-monitor-panel.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are QML and JS (Panel.qml,
# Model.js). node --check runs on the JS file; qmllint runs on the QML
# file when present, warning only (it fails on missing Quickshell
# imports even for valid files). bash -n would fail on both by
# construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "47-5k2k-monitor-panel.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- 5K2K label (#20026) + queued text-size steps (#20143) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run). Anchors use the
# fork-renamed CLI name hexciri-display-text-size, which the installer's
# rename map has already produced by the time patches run.
REPLACEMENTS = [
    # #20026: 5120x2160 is "5K2K", between the 5K and 4K checks.
    ("shell/plugins/panels/monitor/Model.js",
     "  if (w >= 5120 && h >= 2880) return \"5K\"\n"
     "  if (w >= 3840 && h >= 2160) return \"4K\"",
     "  if (w >= 5120 && h >= 2880) return \"5K\"\n"
     "  if (w >= 5120 && h >= 2160) return \"5K2K\"\n"
     "  if (w >= 3840 && h >= 2160) return \"4K\"",
     "Model.js resolutionLabel(): 5120x2160 is 5K2K"),
    # #20143: pendingTextSize property + setTextSize queues while the
    # CLI process is running.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  function setTextSize(px) {\n"
     "    textScaleProc.command = [\"hexciri-display-text-size\", String(px)]\n"
     "    if (!textScaleProc.running) textScaleProc.running = true\n"
     "  }",
     "  property int pendingTextSize: -1\n"
     "\n"
     "  function setTextSize(px) {\n"
     "    if (textScaleProc.running) {\n"
     "      pendingTextSize = px\n"
     "      return\n"
     "    }\n"
     "\n"
     "    pendingTextSize = -1\n"
     "    textScaleProc.command = [\"hexciri-display-text-size\", String(px)]\n"
     "    textScaleProc.running = true\n"
     "  }",
     "Panel.qml: pendingTextSize + setTextSize queues while busy"),
    # #20143: step input goes through applyTextSizeStop().
    ("shell/plugins/panels/monitor/Panel.qml",
     "  function adjustTextSize(deltaSteps) {\n"
     "    var idx = currentTextIndex() + deltaSteps\n"
     "    if (idx < 0) idx = 0\n"
     "    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1\n"
     "    markReflowing()\n"
     "    textSizePreviewIndex = idx\n"
     "    setTextSize(textSizeStops[idx])\n"
     "  }",
     "  function applyTextSizeStop(idx) {\n"
     "    idx = Math.max(0, Math.min(textSizeStops.length - 1, Math.round(idx)))\n"
     "    markReflowing()\n"
     "    textSizePreviewIndex = idx\n"
     "    setTextSize(textSizeStops[idx])\n"
     "  }\n"
     "\n"
     "  function adjustTextSize(deltaSteps) {\n"
     "    applyTextSizeStop(currentTextIndex() + deltaSteps)\n"
     "  }",
     "Panel.qml: applyTextSizeStop() + adjustTextSize via it"),
    # #20143: closing the panel while no text-size change is in flight
    # clears a stale preview. Anchor starts below the line patch 17
    # adds inside the opened branch, so the two patches do not collide.
    ("shell/plugins/panels/monitor/Panel.qml",
     "      cursorActive = false\n"
     "    }\n"
     "  }",
     "      cursorActive = false\n"
     "    } else if (!textScaleProc.running) {\n"
     "      textSizePreviewIndex = -1\n"
     "    }\n"
     "  }",
     "Panel.qml onOpenedChanged: clear preview on close when idle"),
    # #20143: textScaleProc drains the queue on completion and clears
    # the preview on failure / once Style catches up.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  Process {\n"
     "    id: textScaleProc\n"
     "    stdout: StdioCollector { waitForEnd: true }\n"
     "  }",
     "  Process {\n"
     "    id: textScaleProc\n"
     "    stdout: StdioCollector { waitForEnd: true }\n"
     "    onExited: function(exitCode) {\n"
     "      if (exitCode !== 0 && root.pendingTextSize < 0) root.textSizePreviewIndex = -1\n"
     "    }\n"
     "    onRunningChanged: {\n"
     "      if (running) return\n"
     "      if (root.pendingTextSize >= 0) {\n"
     "        var next = root.pendingTextSize\n"
     "        root.pendingTextSize = -1\n"
     "        root.setTextSize(next)\n"
     "      } else if (root.textSizePreviewIndex >= 0\n"
     "          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex) {\n"
     "        root.textSizePreviewIndex = -1\n"
     "      }\n"
     "    }\n"
     "  }",
     "Panel.qml textScaleProc: drain queue / clear preview on completion"),
    # #20143: slider release goes through applyTextSizeStop().
    ("shell/plugins/panels/monitor/Panel.qml",
     "                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }",
     "                onReleased: function(v) { root.applyTextSizeStop(v) }",
     "Panel.qml textSizeSlider: release via applyTextSizeStop()"),
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
print("5k2k-monitor-panel patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. Model.js is JS (node --check applies);
# Panel.qml is QML (qmllint when present, warning only). bash -n would
# fail on both by construction and is deliberately not used here.
node --check "$FORK_OUT/shell/plugins/panels/monitor/Model.js" || die "node --check failed on patched Model.js"
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/panels/monitor/Panel.qml" || warn "qmllint reported issues on patched Panel.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping QML parse checks"
fi
info "  5k2k-monitor-panel: 5120x2160 labeled 5K2K, rapid text-size steps queue instead of dropping (PRs #20026, #20143)"
