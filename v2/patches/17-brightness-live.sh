#!/usr/bin/env bash
# Hexciri fork patch 17: live brightness slider + guarded state polls.
# Forward-port of omarchy PR #20297 (by aditya1944,
# "Apply monitor brightness slider updates live and guard state polls")
# into shell/plugins/panels/monitor/Panel.qml and shell/Ui/PanelSlider.qml.
#
# What it does (PR behavior, unchanged): the Display panel's brightness
# slider applies live while dragging instead of waiting for a 180ms
# debounce pause or release, and the periodic 5s state polls can no longer
# clobber a drag in progress. Internal backlights (eDP/LVDS/DSI) are written
# directly with brightnessctl via a lazily probed backlight device, external
# monitors keep going through the brightness helper with a 60ms leading-edge
# cooldown between drag writes, and release flushes the final value at once
# while skipping a duplicate write when the target is already applied or
# in flight. A write counter (brightnessWrites / readAfterBrightnessWrites)
# plus drag/in-flight state marks polls that started during or before a
# write as stale, so they keep the local slider level while still adding
# newly connected displays.
#
# Fork adaptation: the installer's rename map runs before patches, so the
# anchors below already expect the renamed fork text. New code uses the
# fork helper names: hexciri-brightness-display (external monitors) and
# hexciri-hw-display (backlight-device probe). brightnessctl is a system
# tool, not an omarchy command, and stays as-is; it is already in the
# base package set and already used by hexciri-brightness-display. The
# ShellIpc target (hexciri.monitor), the state-proc command
# (hexciri-monitor-state) and the OSD summon (hexciri.osd) are renamed by
# the installer's rename map, not by this patch, and the manifest.json
# "omarchy" key stays per the compat exception (repair pass restores it).
# previewBrightness and the 180ms brightnessDebounce are gone: the slider
# calls dragBrightness on move and commitBrightness on release.
#
# This PR does NOT touch the open monitor bug (DP 60Hz loop): that is
# scale/position, not brightness.
#
# Tests: upstream's test/shell.d/monitor-test.sh is NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and no
# existing patch touches tests, so this patch does not edit a test file.
# Verification is a node harness over the patched Panel.qml (same
# assertions as the PR's test: internal live drag + coalescing, release
# deduplication, external drag throttling + immediate release flush,
# stale-poll guarding, idle-poll updates) plus a diff of patched vs
# unpatched proving only the intended changes. See the coordinator's
# sim notes for the results.
#
# Standalone: bash v2/patches/17-brightness-live.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are QML only (Panel.qml,
# PanelSlider.qml), no JS file is touched, so there is nothing for
# node --check to run here. The end-of-patch check is qmllint when
# present, warning only: qmllint fails on missing Quickshell imports
# even for valid files. bash -n would fail on both files by construction
# and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "17-brightness-live.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Live brightness slider + guarded state polls, omarchy PR #20297 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The brightness-write machinery, verbatim from the PR except for the fork
# helper names (hexciri-brightness-display, hexciri-hw-display). Anchors
# below use the fork-renamed text the installer's rename map has already
# produced by the time patches run.
BRIGHTNESS_FUNCTIONS = r"""  function isInternalBacklight(name) {
    return /^(eDP|LVDS|DSI)-/.test(name || "") && root.backlightDevice !== ""
  }

  function ensureBacklightDevice(name) {
    if (!/^(eDP|LVDS|DSI)-/.test(name || "")) return
    if (!root.backlightDeviceProbed && !deviceProc.running) deviceProc.running = true
  }

  function brightnessCommand(name, percent) {
    if (isInternalBacklight(name))
      return ["brightnessctl", "-q", "-d", root.backlightDevice, "set", percent + "%"]
    return ["hexciri-brightness-display", "--no-osd", "--monitor", name, percent + "%"]
  }

  function startBrightnessWrite(name, percent) {
    root.brightnessSetQueued = false
    root.inFlightExitCode = -1
    root.inFlightBrightnessMonitor = name
    root.inFlightBrightnessPercent = percent
    root.inFlightInternalBacklight = isInternalBacklight(name)
    setBrightnessProc.command = brightnessCommand(name, percent)
    setBrightnessProc.running = true
  }

  function applyBrightness(name, value, throttled) {
    var percent = Model.clampBrightness(value)
    ensureBacklightDevice(name)
    root.brightnessWrites++
    showBrightness(name, percent)
    root.pendingBrightnessMonitor = name
    root.pendingBrightnessPercent = percent
    if (!throttled) brightnessThrottle.stop()
    if (setBrightnessProc.running || (throttled && brightnessThrottle.running)) {
      root.brightnessSetQueued = true
      return
    }
    startBrightnessWrite(name, percent)
  }

  function setDisplayBrightness(name, value) {
    applyBrightness(name, value, false)
  }

  function dragBrightness(name, value) {
    // External monitors (DDC/CI over I2C, Apple HID) get a short cooldown
    // between drag writes; internal kernel backlights run as fast as
    // setBrightnessProc finishes and coalesce intermediate moves.
    applyBrightness(name, value, !isInternalBacklight(name))
  }

  function commitBrightness(name, value) {
    var percent = Model.clampBrightness(value)
    brightnessThrottle.stop()
    var alreadyApplied = !setBrightnessProc.running && !root.brightnessSetQueued
      && root.lastWrittenMonitor === name && root.lastWrittenPercent === percent
    var alreadyInFlight = setBrightnessProc.running && !root.brightnessSetQueued
      && root.inFlightBrightnessMonitor === name && root.inFlightBrightnessPercent === percent
    if (alreadyApplied || alreadyInFlight) return
    setDisplayBrightness(name, percent)
  }"""

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # PanelSlider.qml: skip duplicate moved() emissions when the quantized
    # value has not changed, so a drag does not re-fire the brightness
    # write path on every pointer motion event.
    ("shell/Ui/PanelSlider.qml",
     "    onPositionChanged: function(mouse) {\n"
     "      if (!root.dragging) return\n"
     "      var next = valueFromX(mouse.x)\n"
     "      root.liveValue = next\n"
     "      root.moved(next)\n"
     "    }",
     "    onPositionChanged: function(mouse) {\n"
     "      if (!root.dragging) return\n"
     "      var next = valueFromX(mouse.x)\n"
     "      if (next === root.liveValue) return\n"
     "      root.liveValue = next\n"
     "      root.moved(next)\n"
     "    }",
     "PanelSlider onPositionChanged: skip duplicate moved() emissions"),
    # Panel.qml: brightness write/drag state properties.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  property var brightnessLevels: ({})\n"
     "  property string pendingBrightnessMonitor: \"\"\n"
     "  property int pendingBrightnessPercent: 0\n"
     "  property bool brightnessSetQueued: false",
     "  property var brightnessLevels: ({})\n"
     "  property string backlightDevice: \"\"\n"
     "  property bool backlightDeviceProbed: false\n"
     "  property string pendingBrightnessMonitor: \"\"\n"
     "  property int pendingBrightnessPercent: 0\n"
     "  property bool brightnessSetQueued: false\n"
     "  property string inFlightBrightnessMonitor: \"\"\n"
     "  property int inFlightBrightnessPercent: 0\n"
     "  property bool inFlightInternalBacklight: false\n"
     "  property int inFlightExitCode: -1\n"
     "  property string lastWrittenMonitor: \"\"\n"
     "  property int lastWrittenPercent: 0\n"
     "  property int brightnessWrites: 0\n"
     "  property int readAfterBrightnessWrites: 0\n"
     "  readonly property bool brightnessDragging: !!(panel.loadedContent && panel.loadedContent.brightnessSlider && panel.loadedContent.brightnessSlider.dragging)",
     "Panel.qml: add brightness write/drag state properties"),
    # Panel.qml: replace setDisplayBrightness + previewBrightness with the
    # live-write machinery. Anchor uses the fork-renamed helper name
    # (hexciri-brightness-display); the rename map produced it before
    # patches run.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  function setDisplayBrightness(name, value) {\n"
     "    var percent = Model.clampBrightness(value)\n"
     "    showBrightness(name, percent)\n"
     "    root.pendingBrightnessMonitor = name\n"
     "    root.pendingBrightnessPercent = percent\n"
     "\n"
     "    if (setBrightnessProc.running) {\n"
     "      root.brightnessSetQueued = true\n"
     "      return\n"
     "    }\n"
     "\n"
     "    root.brightnessSetQueued = false\n"
     "    setBrightnessProc.command = [\"hexciri-brightness-display\", \"--no-osd\", \"--monitor\", name, percent + \"%\"]\n"
     "    setBrightnessProc.running = true\n"
     "  }\n"
     "\n"
     "  function previewBrightness(name, value) {\n"
     "    var percent = Model.clampBrightness(value)\n"
     "    showBrightness(name, percent)\n"
     "    root.pendingBrightnessMonitor = name\n"
     "    root.pendingBrightnessPercent = percent\n"
     "    brightnessDebounce.restart()\n"
     "  }",
     BRIGHTNESS_FUNCTIONS,
     "Panel.qml: live brightness writes (drag/commit, brightnessctl for internal)"),
    # Panel.qml: updateDisplays keeps local levels when a poll is stale.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  // Brightness is taken from every poll, so a level set elsewhere replaces one\n"
     "  // shown here. The list itself is only taken when something besides\n"
     "  // brightness changed: a new one rebuilds the picker and the layout, which\n"
     "  // would drop a hover or a drag in progress on each poll.\n"
     "  function updateDisplays(displaysJson) {\n"
     "    var parsed = Model.parseDisplays(displaysJson)\n"
     "    var levels = {}\n"
     "    for (var i = 0; i < parsed.displays.length; i++) {\n"
     "      var display = parsed.displays[i]\n"
     "      if (display && display.enabled && typeof display.brightness === \"number\")\n"
     "        levels[display.name] = display.brightness\n"
     "    }\n"
     "    root.brightnessLevels = levels",
     "  // Brightness is taken from every poll unless a drag or write is in flight\n"
     "  // (or started while the poll was running), so stale reads cannot snap the\n"
     "  // slider back. The list itself is only taken when something besides\n"
     "  // brightness changed: a new one rebuilds the picker and the layout, which\n"
     "  // would drop a hover or a drag in progress on each poll.\n"
     "  function updateDisplays(displaysJson, keepBrightness) {\n"
     "    var parsed = Model.parseDisplays(displaysJson)\n"
     "    var levels = {}\n"
     "    for (var i = 0; i < parsed.displays.length; i++) {\n"
     "      var display = parsed.displays[i]\n"
     "      if (!display || !display.enabled) continue\n"
     "      if (keepBrightness && root.brightnessLevels[display.name] !== undefined)\n"
     "        levels[display.name] = root.brightnessLevels[display.name]\n"
     "      else if (typeof display.brightness === \"number\")\n"
     "        levels[display.name] = display.brightness\n"
     "    }\n"
     "    root.brightnessLevels = levels",
     "Panel.qml updateDisplays: keep local brightness on stale polls"),
    # Panel.qml: probe the backlight device when the panel opens.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  onOpenedChanged: {\n"
     "    closeRotateMenu()\n"
     "    if (opened) {\n"
     "      refresh()\n",
     "  onOpenedChanged: {\n"
     "    closeRotateMenu()\n"
     "    if (opened) {\n"
     "      refresh()\n"
     "      if (!root.backlightDeviceProbed && !deviceProc.running) deviceProc.running = true\n",
     "Panel.qml onOpenedChanged: probe backlight device on open"),
    # Panel.qml: stateProc records how many brightness writes had landed
    # when the poll started, so a poll that started mid-write is stale.
    ("shell/plugins/panels/monitor/Panel.qml",
     "    onRunningChanged: {\n"
     "      if (running) {\n"
     "        root.readAfterActions = root.actionsDone\n",
     "    onRunningChanged: {\n"
     "      if (running) {\n"
     "        root.readAfterActions = root.actionsDone\n"
     "        root.readAfterBrightnessWrites = (setBrightnessProc.running || root.brightnessSetQueued || brightnessThrottle.running)\n"
     "          ? -1\n"
     "          : root.brightnessWrites\n",
     "Panel.qml stateProc: snapshot brightness-write count on poll start"),
    # Panel.qml: stateProc completion skips brightnessPercent/levels when
    # a drag or write is in flight, or the poll predates a newer write.
    ("shell/plugins/panels/monitor/Panel.qml",
     "        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0\n"
     "        root.internalMonitor = String(lines[1] || \"\").trim()\n"
     "        root.externalMonitor = String(lines[2] || \"\").trim()\n"
     "        root.internalEnabled = String(lines[3] || \"\").trim() !== \"\"\n"
     "        root.focusedMonitor = String(lines[5] || \"\").trim()\n"
     "        root.monitorScale = root.normalizeScale(String(lines[6] || \"\").trim())\n"
     "        root.updateDisplays(String(lines[7] || \"[]\").trim())",
     "        var staleBrightness = root.brightnessDragging\n"
     "          || setBrightnessProc.running\n"
     "          || root.brightnessSetQueued\n"
     "          || brightnessThrottle.running\n"
     "          || root.readAfterBrightnessWrites !== root.brightnessWrites\n"
     "        if (!staleBrightness) {\n"
     "          root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0\n"
     "          root.lastWrittenMonitor = \"\"\n"
     "        }\n"
     "        root.internalMonitor = String(lines[1] || \"\").trim()\n"
     "        root.externalMonitor = String(lines[2] || \"\").trim()\n"
     "        root.internalEnabled = String(lines[3] || \"\").trim() !== \"\"\n"
     "        root.focusedMonitor = String(lines[5] || \"\").trim()\n"
     "        root.monitorScale = root.normalizeScale(String(lines[6] || \"\").trim())\n"
     "        root.updateDisplays(String(lines[7] || \"[]\").trim(), staleBrightness)",
     "Panel.qml stateProc: guard brightness against stale polls"),
    # Panel.qml: 180ms debounce becomes a 60ms leading-edge throttle that
    # flushes a queued external write.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  Timer {\n"
     "    id: brightnessDebounce\n"
     "    interval: 180\n"
     "    repeat: false\n"
     "    onTriggered: root.setDisplayBrightness(root.pendingBrightnessMonitor, root.pendingBrightnessPercent)\n"
     "  }",
     "  Timer {\n"
     "    id: brightnessThrottle\n"
     "    interval: 60\n"
     "    repeat: false\n"
     "    onTriggered: {\n"
     "      if (root.brightnessSetQueued && !setBrightnessProc.running) {\n"
     "        root.startBrightnessWrite(root.pendingBrightnessMonitor, root.pendingBrightnessPercent)\n"
     "      }\n"
     "    }\n"
     "  }",
     "Panel.qml: brightnessDebounce (180ms) -> brightnessThrottle (60ms)"),
    # Panel.qml: setBrightnessProc tracks exit codes and last-written
    # levels, clears a failed internal backlight device for re-probe, and
    # flushes queued writes (immediately when not dragging on external).
    ("shell/plugins/panels/monitor/Panel.qml",
     "    // the open-time refresh, and Component.onCompleted.\n"
     "    onRunningChanged: {\n"
     "      if (running) return\n"
     "      if (root.brightnessSetQueued) {\n"
     "        root.setDisplayBrightness(root.pendingBrightnessMonitor, root.pendingBrightnessPercent)\n"
     "      }\n"
     "    }",
     "    // the open-time refresh, and Component.onCompleted.\n"
     "    onExited: function(exitCode) {\n"
     "      root.inFlightExitCode = exitCode\n"
     "      root.brightnessWrites++\n"
     "      if (exitCode === 0) {\n"
     "        root.lastWrittenMonitor = root.inFlightBrightnessMonitor\n"
     "        root.lastWrittenPercent = root.inFlightBrightnessPercent\n"
     "      } else {\n"
     "        root.lastWrittenMonitor = \"\"\n"
     "        if (root.inFlightInternalBacklight) {\n"
     "          root.backlightDevice = \"\"\n"
     "          root.backlightDeviceProbed = false\n"
     "          if (!deviceProc.running) deviceProc.running = true\n"
     "        }\n"
     "      }\n"
     "    }\n"
     "    onRunningChanged: {\n"
     "      if (running) return\n"
     "      var sameAsSucceeded = root.inFlightExitCode === 0\n"
     "        && root.pendingBrightnessMonitor === root.inFlightBrightnessMonitor\n"
     "        && root.pendingBrightnessPercent === root.inFlightBrightnessPercent\n"
     "      if (root.brightnessSetQueued && sameAsSucceeded) root.brightnessSetQueued = false\n"
     "      if (!root.inFlightInternalBacklight) {\n"
     "        brightnessThrottle.restart()\n"
     "        if (root.brightnessSetQueued && !root.brightnessDragging) {\n"
     "          brightnessThrottle.stop()\n"
     "          root.startBrightnessWrite(root.pendingBrightnessMonitor, root.pendingBrightnessPercent)\n"
     "        }\n"
     "        return\n"
     "      }\n"
     "      if (root.brightnessSetQueued) {\n"
     "        root.startBrightnessWrite(root.pendingBrightnessMonitor, root.pendingBrightnessPercent)\n"
     "      }\n"
     "    }",
     "Panel.qml setBrightnessProc: track exits, flush queued writes"),
    # Panel.qml: the backlight-device probe process. Fork name
    # hexciri-hw-display: bin/omarchy-hw-display is copied by the
    # installer's hw-* allowlist and renamed by rename_files.
    ("shell/plugins/panels/monitor/Panel.qml",
     "  }\n"
     "\n"
     "  Timer {\n"
     "    id: mirrorRecheck",
     "  }\n"
     "\n"
     "  Process {\n"
     "    id: deviceProc\n"
     "    command: [\"hexciri-hw-display\"]\n"
     "    stdout: StdioCollector {\n"
     "      waitForEnd: true\n"
     "      onStreamFinished: {\n"
     "        root.backlightDeviceProbed = true\n"
     "        root.backlightDevice = String(text || \"\").trim()\n"
     "      }\n"
     "    }\n"
     "  }\n"
     "\n"
     "  Timer {\n"
     "    id: mirrorRecheck",
     "Panel.qml: add deviceProc (hexciri-hw-display backlight probe)"),
    # Panel.qml: expose the slider to root so brightnessDragging can read
    # its dragging state.
    ("shell/plugins/panels/monitor/Panel.qml",
     "      property alias scrollArea: scrollArea\n"
     "      property alias layoutMap: layoutMap\n",
     "      property alias scrollArea: scrollArea\n"
     "      property alias layoutMap: layoutMap\n"
     "      property alias brightnessSlider: brightnessSlider\n",
     "Panel.qml keyCatcher: alias brightnessSlider"),
    # Panel.qml: the slider applies live on move and commits on release.
    ("shell/plugins/panels/monitor/Panel.qml",
     "                onMoved: function(v) { if (root.current) root.previewBrightness(root.current.name, v) }\n"
     "                onReleased: function(v) {\n"
     "                  brightnessDebounce.stop()\n"
     "                  if (root.current) root.setDisplayBrightness(root.current.name, v)\n"
     "                }",
     "                onMoved: function(v) { if (root.current) root.dragBrightness(root.current.name, v) }\n"
     "                onReleased: function(v) { if (root.current) root.commitBrightness(root.current.name, v) }",
     "Panel.qml brightnessSlider: dragBrightness on move, commitBrightness on release"),
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
print("brightness-live patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are QML only, not bash and not JS,
# so bash -n and node --check would fail on both by construction and are
# deliberately not used here.
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/panels/monitor/Panel.qml" || warn "qmllint reported issues on patched Panel.qml (missing Quickshell imports also trip it; see output above)"
  qmllint "$FORK_OUT/shell/Ui/PanelSlider.qml" || warn "qmllint reported issues on patched PanelSlider.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping QML parse checks"
fi
info "  brightness-live: monitor brightness slider now applies live, state polls guard drags (PR #20297)"
