#!/usr/bin/env bash
# Hexciri fork patch 26: reap orphaned input watchers, batch Style
# queries, fix async races (upstream omacom/omarchy #19968, commit 4e633234d).
# InputDevices/InputMethodState/UntypedInput stop their watchers/timers on
# destruction and InputDevices reaps orphaned inotifywait watchers whose
# parent shell died; Style.qml batches three hyprctl getoption calls into
# one `hyprctl -j --batch` with refresh/font-resolve pending queues;
# MultiSelect runs one Process per refresh with an immutable seq;
# AppLibrary/BackgroundSwitch get rescan queues, argv-safe launches and
# `--` guards on ln/rm paths. Ordered before #20129 (patch 28) for
# AppLibrary.qml.
#
# Fork notes: rename map applied (hexciri-launch-tui, hexciri.osd,
# ~/.local/state/hexciri/current/icons.revision, `hexciri font set`).
# LIVE CHECK STILL OPEN (2026-11-26, cannot verify from here): `hyprctl
# --batch` (Style.qml) needs a live check against Hyprland 0.57 on Devi's
# machine; upstream ships it and falls back to nothing if the call fails
# (applyBatchOptionsJson leaves previous values on parse failure), but the
# batched form itself is unverified on 0.57. Test-only upstream files
# (test/shell.d/input-devices-test.sh, app-icon-scan-test.sh tweak) are
# NOT ported: test/ is not in FORK_OUT.
#
# Standalone: bash v2/patches/26-watcher-reaping-style.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "26-watcher-reaping-style.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    ('shell/Commons/InputDevices.qml',
     r'''  // /dev is watched beside /dev/input for one thing: /dev/input being created
  // again after it went away with the last device, when the watch on the old
  // directory is gone and has to be set up on the new one. udev's records for
  // input devices are the c13: entries, character major 13.
  Process {
    id: watcher
    command: ["bash", "-c",
      "dirs=(\"$2\"); for dir in \"$1\" \"$3\"; do [[ -d $dir ]] && dirs+=(\"$dir\"); done; "
        + "exec inotifywait -m -q -e create,delete,delete_self,moved_to --format '%w|%e|%f' \"${dirs[@]}\"",
      "input-devices", root.inputDir, root.devDir, root.udevDir]
    running: true
''',
     r'''  // /dev is watched beside /dev/input for one thing: /dev/input being created
  // again after it went away with the last device, when the watch on the old
  // directory is gone and has to be set up on the new one. udev's records for
  // input devices are the c13: entries, character major 13.
  //
  // Quickshell does not always stop Process children on exit, so each restart
  // can leave an orphaned inotifywait behind. Reap any matching watcher for
  // this devDir whose parent is no longer a shell before exec'ing ours.
  Process {
    id: watcher
    command: ["bash", "-c",
      "for p in /proc/[0-9]*; do "
        + "pid=${p#/proc/}; "
        + "[[ -r $p/cmdline && -r $p/stat ]] || continue; "
        + "mapfile -d '' args < \"$p/cmdline\" 2>/dev/null || continue; "
        + "[[ ${args[0]##*/} == \"inotifywait\" && ${args[4]:-} == \"create,delete,delete_self,moved_to\" && ${args[7]:-} == \"$2\" ]] || continue; "
        + "read -r stat < \"$p/stat\" 2>/dev/null || continue; "
        + "rest=${stat##*\\) }; read -r _ ppid _ <<< \"$rest\"; "
        + "[[ $ppid =~ ^[0-9]+$ ]] || continue; "
        + "read -r comm < \"/proc/$ppid/comm\" 2>/dev/null || comm=\"\"; "
        + "[[ $comm == \"quickshell\" || $comm == \"qs\" ]] || kill \"$pid\" 2>/dev/null || true; "
        + "done; "
        + "dirs=(\"$2\"); for dir in \"$1\" \"$3\"; do [[ -d $dir ]] && dirs+=(\"$dir\"); done; "
        + "exec inotifywait -m -q -e create,delete,delete_self,moved_to --format '%w|%e|%f' \"${dirs[@]}\"",
      "input-devices", root.inputDir, root.devDir, root.udevDir]
    running: true
''',
     'InputDevices: reap orphaned inotifywait watchers before exec'),
    ('shell/Commons/InputDevices.qml',
     r'''    id: restart
    interval: 1000
    onTriggered: watcher.running = true
  }
}
''',
     r'''    id: restart
    interval: 1000
    onTriggered: watcher.running = true
  }

  Component.onDestruction: {
    settle.stop()
    followUp.stop()
    recovered.stop()
    restart.stop()
    watcher.running = false
  }
}
''',
     'InputDevices: stop timers + watcher on destruction'),
    ('shell/Commons/InputMethodState.qml',
     r'''    id: restart
    interval: 5000
    onTriggered: watcher.running = true
  }
}
''',
     r'''    id: restart
    interval: 5000
    onTriggered: watcher.running = true
  }

  Component.onDestruction: {
    restart.stop()
    watcher.running = false
  }
}
''',
     'InputMethodState: stop restart timer + watcher on destruction'),
    ('shell/Commons/Style.qml',
     r'''  readonly property var easeOut: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]

  function refresh() {
    hyprctlProc.running = true
    gapsOutProc.running = true
    animationsProc.running = true
  }

  function scheduleRefresh() {
    refreshTimer.restart()
  }

  function applyRoundingJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var n = Number(json.int)
      if (isFinite(n) && n >= 0) cornerRadius = n
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  function applyGapsOutJson(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var css = String(json.css || "")
      var parts = css.match(/-?\d+(?:\.\d+)?/g) || []
      var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
      if (isFinite(n) && n >= 0) gapsOut = Math.max(0, Math.round(n / 2))
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  // Pull typography, bar dimensions, state tokens, and spacing out of the
''',
     r'''  readonly property var easeOut: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]

  property bool refreshPending: false
  property bool fontResolvePending: false

  function refresh() {
    if (hyprctlProc.running) {
      refreshPending = true
      return
    }
    hyprctlProc.running = true
  }

  function scheduleRefresh() {
    refreshTimer.restart()
  }

  function applyRoundingOption(json) {
    var n = Number(json.int)
    if (isFinite(n) && n >= 0) cornerRadius = n
  }

  function applyGapsOutOption(json) {
    var css = String(json.css || "")
    var parts = css.match(/-?\d+(?:\.\d+)?/g) || []
    var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
    if (isFinite(n) && n >= 0) gapsOut = Math.max(0, Math.round(n / 2))
  }

  function applyRoundingJson(raw) {
    try {
      applyRoundingOption(JSON.parse(raw || "{}"))
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  function applyGapsOutJson(raw) {
    try {
      applyGapsOutOption(JSON.parse(raw || "{}"))
    } catch (e) {
      // hyprctl missing / Hyprland not running — leave the previous value.
    }
  }

  function applyBatchOptionsJson(raw) {
    var chunks = String(raw || "").trim().split(/\n\s*\n/)
    for (var i = 0; i < chunks.length; i++) {
      var chunk = chunks[i].trim()
      if (!chunk) continue
      try {
        var json = JSON.parse(chunk)
        if (json.option === "decoration:rounding") applyRoundingOption(json)
        else if (json.option === "general:gaps_out") applyGapsOutOption(json)
        else if (json.option === "animations:enabled") root.reduceMotion = json.bool === false
      } catch (e) {
        // hyprctl missing / Hyprland not running — leave the previous value.
      }
    }
  }

  // Pull typography, bar dimensions, state tokens, and spacing out of the
''',
     'Style: refresh/font-resolve pending queues + option appliers + batch parser'),
    ('shell/Commons/Style.qml',
     r'''  property Process hyprctlProc: Process {
    id: hyprctlProc
    command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRoundingJson(text)
    }
  }

  property Process animationsProc: Process {
    id: animationsProc
    command: ["hyprctl", "-j", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.reduceMotion = JSON.parse(text || "{}").bool === false
        } catch (e) {
          // hyprctl missing / Hyprland not running — leave the previous value.
        }
      }
    }
  }

  // A reload is when the animations toggle, a theme or the user's own config
  // lands, and Hyprland only announces it once the new values are in effect.
  property Connections hyprlandEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.refresh()
    }
  }

  property Process gapsOutProc: Process {
    id: gapsOutProc
    command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyGapsOutJson(text)
    }
  }

  // Resolve the fontconfig alias to a concrete family name. `hexciri font
  // set <name>` rewrites ~/.config/fontconfig/fonts.conf and restarts the
  // shell, but rerun on file change anyway so manual edits propagate too.
  function resolveFontFamily() {
''',
     r'''  property Process hyprctlProc: Process {
    id: hyprctlProc
    command: ["hyprctl", "-j", "--batch", "getoption decoration:rounding ; getoption general:gaps_out ; getoption animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBatchOptionsJson(text)
    }
    onExited: {
      if (root.refreshPending) {
        root.refreshPending = false
        running = true
      }
    }
  }

  // A reload is when the animations toggle, a theme or the user's own config
  // lands, and Hyprland only announces it once the new values are in effect.
  property Connections hyprlandEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.refresh()
    }
  }

  // Resolve the fontconfig alias to a concrete family name. `hexciri font
  // set <name>` rewrites ~/.config/fontconfig/fonts.conf and restarts the
  // shell, but rerun on file change anyway so manual edits propagate too.
  function resolveFontFamily() {
''',
     'Style: single batched hyprctl --batch getoption call, drop animations/gapsOut procs'),
    ('shell/Commons/Style.qml',
     r'''  function resolveFontFamily() {
    fcMatchProc.running = true
  }

  property Process fcMatchProc: Process {
    id: fcMatchProc
    command: ["fc-match", "-f", "%{family[0]}", "monospace"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length > 0) root.resolvedFontFamily = name
      }
    }
  }

  property FileView fontconfigFile: FileView {
''',
     r'''  function resolveFontFamily() {
    if (fcMatchProc.running) {
      fontResolvePending = true
      return
    }
    fcMatchProc.running = true
  }

  property Process fcMatchProc: Process {
    id: fcMatchProc
    command: ["fc-match", "-f", "%{family[0]}", "monospace"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name.length > 0) root.resolvedFontFamily = name
      }
    }
    onExited: {
      if (root.fontResolvePending) {
        root.fontResolvePending = false
        running = true
      }
    }
  }

  property FileView fontconfigFile: FileView {
''',
     'Style: resolveFontFamily queues while fc-match runs; fcMatchProc re-runs on exit'),
    ('shell/Commons/Style.qml',
     r'''  property FileView fontconfigFile: FileView {
    path: Quickshell.env("HOME") + "/.config/fontconfig/fonts.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: root.resolveFontFamily()
    onLoaded: root.resolveFontFamily()
    onLoadFailed: root.resolveFontFamily()
  }

  // Re-poll Hyprland a beat after either input file changes. Hyprland's
''',
     r'''  property FileView fontconfigFile: FileView {
    path: Quickshell.env("HOME") + "/.config/fontconfig/fonts.conf"
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: {
      reload()
      root.resolveFontFamily()
    }
  }

  // Re-poll Hyprland a beat after either input file changes. Hyprland's
''',
     'Style: fontconfig FileView preload off, reload() on change'),
    ('shell/Commons/Style.qml',
     r'''  property FileView windowNoGapsToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/hexciri/toggles/hypr/window-no-gaps.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshTimer.restart()
    onLoaded: refreshTimer.restart()
    onLoadFailed: refreshTimer.restart()
  }

  Component.onCompleted: {
''',
     r'''  property FileView windowNoGapsToggle: FileView {
    path: Quickshell.env("HOME") + "/.local/state/hexciri/toggles/hypr/window-no-gaps.lua"
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: {
      reload()
      refreshTimer.restart()
    }
  }

  Component.onCompleted: {
''',
     'Style: window-no-gaps FileView preload off, reload() on change'),
    ('shell/Commons/UntypedInput.qml',
     r'''    id: resubscribe
    interval: 2000
    onTriggered: if (root.nodeId >= 0 && !events.running) {
      events.running = true
      root.refresh()
    }
  }
}
''',
     r'''    id: resubscribe
    interval: 2000
    onTriggered: if (root.nodeId >= 0 && !events.running) {
      events.running = true
      root.refresh()
    }
  }

  Component.onDestruction: {
    resubscribe.stop()
    events.running = false
  }
}
''',
     'UntypedInput: stop resubscribe timer + events on destruction'),
    ('shell/Ui/MultiSelect.qml',
     r'''  property int refreshSeq: 0
  readonly property int refreshTimeoutMs: 6000

  function refresh() {
    var cmd = arrayFrom(optionsCommand)
    if (cmd.length === 0) {
      rebuildFromStatic()
      return
    }
    refreshSeq++
    loadingOptions = true
    optionsError = ""
    optionsProcess.command = cmd
    optionsProcess.workingDirectory = optionsCommandCwd
    optionsProcess.running = false
    optionsProcess.running = true
    refreshTimeoutTimer.restart()
  }

  Timer {
    id: refreshTimeoutTimer
    interval: root.refreshTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.loadingOptions) return
      optionsProcess.running = false
      root.loadingOptions = false
      root.optionsError = Commons.I18n.t("multiSelect.timedOut")
    }
  }

  onOptionsChanged: if (arrayFrom(optionsCommand).length === 0) rebuildFromStatic()
''',
     r'''  property int refreshSeq: 0
  property bool _completed: false
  property var activeProcess: null
  readonly property int refreshTimeoutMs: 6000

  function stopActiveProcess() {
    if (!activeProcess) return
    var proc = activeProcess
    activeProcess = null
    proc.running = false
    proc.destroy()
  }

  function refresh() {
    var cmd = arrayFrom(optionsCommand)
    if (cmd.length === 0) {
      refreshSeq++
      refreshTimeoutTimer.stop()
      stopActiveProcess()
      loadingOptions = false
      optionsError = ""
      rebuildFromStatic()
      return
    }
    var seq = ++refreshSeq
    loadingOptions = true
    optionsError = ""
    stopActiveProcess()
    activeProcess = optionsProcessComponent.createObject(root, {
      seq: seq,
      command: cmd,
      workingDirectory: optionsCommandCwd,
      running: true
    })
    refreshTimeoutTimer.restart()
  }

  Timer {
    id: refreshTimeoutTimer
    interval: root.refreshTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.loadingOptions) return
      root.refreshSeq++
      root.stopActiveProcess()
      root.loadingOptions = false
      root.optionsError = Commons.I18n.t("multiSelect.timedOut")
    }
  }

  onOptionsChanged: if (arrayFrom(optionsCommand).length === 0) rebuildFromStatic()
''',
     'MultiSelect: per-refresh Process with immutable seq; empty-command path stops active run'),
    ('shell/Ui/MultiSelect.qml',
     r'''  onOptionsChanged: if (arrayFrom(optionsCommand).length === 0) rebuildFromStatic()
  onOptionsCommandChanged: refresh()
  Component.onCompleted: refresh()

  Process {
    id: optionsProcess
    running: false
    command: []

    property int seq: 0

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (optionsProcess.seq !== root.refreshSeq) return
        var result = root.parseCommandOutput(text)
        if (result.error) {
          root.optionsError = result.error
          root.resolvedOptions = root.normalizeAll(root.options)
        } else {
          var combined = root.arrayFrom(root.options)
          for (var j = 0; j < result.options.length; j++) combined.push(result.options[j])
          root.resolvedOptions = root.normalizeAll(combined)
        }
        root.recomputeFiltered()
        root.loadingOptions = false
        refreshTimeoutTimer.stop()
      }
    }

    onRunningChanged: if (running) seq = root.refreshSeq

    onExited: function(exitCode, exitStatus) {
      if (seq !== root.refreshSeq) return
      refreshTimeoutTimer.stop()
      if (exitCode !== 0) {
        root.loadingOptions = false
        root.optionsError = Commons.I18n.t("multiSelect.exited").arg(Commons.I18n.formatNumber(exitCode))
      }
    }
  }

  implicitWidth: Style.spacing.searchableDropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down || event.text === "j") {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.selectionLabel() || root.triggerLabel || root.noSelectionText
        color: root.selectionLabel() ? root.foreground : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // CloseOnPressOutsideParent treats a press on the trigger as inside,
        // so the popup is still open here and a second click collapses it
        // instead of reopening.
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      QQC.Popup {
        id: popup
        closePolicy: QQC.Popup.CloseOnPressOutsideParent | QQC.Popup.CloseOnEscape
        // Keep the trigger as the logical parent so CloseOnPressOutsideParent
        // treats a press on the trigger as inside, leaving the toggle to the
        // trigger's onClicked. The popup item is still rendered in the window
        // overlay, so it is not clipped by the trigger's ancestors. Position
        // and available height are recomputed on open and any time the
        // trigger's geometry changes, since a binding on mapToItem alone
        // won't reliably re-evaluate when ancestors scroll or resize.
        parent: trigger
        property real _anchorX: 0
        property real _anchorY: 0
        property real _availableBelow: 0
        readonly property var _windowItem: trigger.Window.window ? trigger.Window.window.contentItem : null
        readonly property real _windowHeight: _windowItem ? _windowItem.height : 0
        readonly property real _idealContent: resultList.contentHeight + Style.space(50)
        readonly property real _maxRowsHeight: root.popupRowHeight * 6 + 5 * Style.spacing.labelGap + Style.space(50)

        function reposition() {
          if (!parent) return
          var p = trigger.mapToItem(parent, 0, trigger.height + Style.spacing.xxs)
          _anchorX = p.x
          _anchorY = p.y
          // _anchorY is relative to the trigger; the clamp below needs the
          // anchor in window coordinates.
          var win = _windowItem ? trigger.mapToItem(_windowItem, 0, trigger.height + Style.spacing.xxs) : p
          _availableBelow = Math.max(0, _windowHeight - win.y - Style.space(12))
        }

        x: _anchorX
        y: _anchorY
        width: trigger.width
        // Clamp to whatever fits below the trigger; don't force popupMinHeight
        // when there isn't room, otherwise the popup overflows the window.
        implicitHeight: Math.min(_availableBelow, _idealContent, _maxRowsHeight)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        Connections {
          target: trigger
          function onXChanged() { popup.reposition() }
          function onYChanged() { popup.reposition() }
          function onWidthChanged() { popup.reposition() }
          function onHeightChanged() { popup.reposition() }
        }

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          reposition()
          searchField.text = ""
          root.refresh()
          root.recomputeFiltered()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onClosed: searchField.text = ""

        contentItem: Column {
          spacing: 0

          Item {
            id: searchHeader
            width: parent.width
            height: root.popupRowHeight + Style.spacing.controlPaddingX

            Row {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              spacing: Style.spacing.rowGap

              TextField {
                id: searchField
                width: parent.width - refreshButton.width - parent.spacing
                height: parent.height
                placeholderText: root.placeholderText
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body

                onTextChanged: {
                  root.recomputeFiltered()
                  if (resultList.count > 0) resultList.currentIndex = 0
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    popup.close(); event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.forceActiveFocus()
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.toggleCurrent()
                    }
                    event.accepted = true
                  }
                }
              }

              BorderSurface {
                id: refreshButton
                visible: root.arrayFrom(root.optionsCommand).length > 0
                enabled: !root.loadingOptions
                width: parent.height
                height: parent.height
                radius: Style.cornerRadius
                color: refreshHover.hovered
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : Style.normalFillFor(root.foreground, root.accent)
                borderSpec: refreshHover.hovered
                  ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
                  : Border.controlSpec("normal", root.foreground, root.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.loadingOptions ? "󰦖" : "󰑐"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body

                  RotationAnimator on rotation {
                    running: root.loadingOptions && !Style.reduceMotion
                    from: 0; to: 360
                    duration: Style.duration(800)
                    loops: Animation.Infinite
                  }
                }

                HoverHandler { id: refreshHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refresh()
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.10)
          }

          Item {
            width: parent.width
            height: popup.height - searchHeader.height - Style.spacing.xxs - 1

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: resultList.count === 0
              text: root.loadingOptions ? Commons.I18n.t("common.loading") : (root.optionsError !== "" ? root.optionsError : root.emptyText)
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ListView {
              id: resultList
              anchors.fill: parent
              spacing: Style.spacing.labelGap
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.filtered
              currentIndex: -1
              keyNavigationEnabled: false

              function toggleCurrent() {
                if (currentIndex < 0 || currentIndex >= root.filtered.length) return
                root.toggleValue(root.filtered[currentIndex].value)
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === Qt.Key_Down || event.text === "j") {
                  if (resultList.currentIndex >= resultList.count - 1) {
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex + 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || event.text === "k") {
                  if (resultList.currentIndex <= 0) {
                    searchField.forceActiveFocus()
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex - 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Space) {
                  resultList.toggleCurrent(); event.accepted = true
                }
              }

              delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool selected: root.isSelected(modelData.value)

                width: resultList.width
                height: Math.max(root.popupRowHeight, rowContent.implicitHeight + Style.spacing.rowPaddingX)
                color: index === resultList.currentIndex
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : "transparent"

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  spacing: Style.spacing.rowGap

                  BorderSurface {
                    id: checkbox
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Math.max(2, Style.cornerRadius / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    color: selected ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                    borderSpec: selected
                      ? Border.controlSpec("selected", root.foreground, root.accent)
                      : Border.controlSpec("normal", root.foreground, root.accent)

                    Text {
                      anchors.centerIn: parent
                      visible: selected
                      text: "✓"
                      color: Style.selectedStateColor(root.foreground, root.accent)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(checkbox.height * 0.85)
                      font.bold: true
                    }
                  }

                  Column {
                    width: parent.width - checkbox.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: index === resultList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: text !== ""
                      text: modelData.description
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: resultList.currentIndex = parent.index
                  onClicked: root.toggleValue(modelData.value)
                }
              }
            }
          }
        }
      }
    }
  }
}
''',
     r'''  onOptionsChanged: if (arrayFrom(optionsCommand).length === 0) rebuildFromStatic()
  onOptionsCommandChanged: if (_completed) refresh()
  Component.onCompleted: {
    _completed = true
    refresh()
  }
  Component.onDestruction: {
    refreshTimeoutTimer.stop()
    stopActiveProcess()
  }

  // One Process per refresh with an immutable seq so buffered stdout/exit
  // signals from a canceled run can never finish a newer refresh.
  Component {
    id: optionsProcessComponent

    Process {
      id: proc
      required property int seq
      property bool streamDone: false
      property bool processExited: false
      property string collectedStdout: ""
      property int lastExitCode: 0

      function maybeFinish() {
        if (!streamDone || !processExited) return
        if (root.activeProcess === proc) root.activeProcess = null
        if (seq === root.refreshSeq) {
          refreshTimeoutTimer.stop()
          root.loadingOptions = false
          if (lastExitCode !== 0) {
            root.optionsError = Commons.I18n.t("multiSelect.exited").arg(Commons.I18n.formatNumber(lastExitCode))
          } else {
            var result = root.parseCommandOutput(collectedStdout)
            if (result.error) {
              root.optionsError = result.error
              root.resolvedOptions = root.normalizeAll(root.options)
            } else {
              var combined = root.arrayFrom(root.options)
              for (var j = 0; j < result.options.length; j++) combined.push(result.options[j])
              root.resolvedOptions = root.normalizeAll(combined)
            }
            root.recomputeFiltered()
          }
        }
        proc.destroy()
      }

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          proc.collectedStdout = text
          proc.streamDone = true
          proc.maybeFinish()
        }
      }

      onExited: function(exitCode, exitStatus) {
        proc.lastExitCode = exitCode
        proc.processExited = true
        proc.maybeFinish()
      }
    }
  }

  implicitWidth: Style.spacing.searchableDropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down || event.text === "j") {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.selectionLabel() || root.triggerLabel || root.noSelectionText
        color: root.selectionLabel() ? root.foreground : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // CloseOnPressOutsideParent treats a press on the trigger as inside,
        // so the popup is still open here and a second click collapses it
        // instead of reopening.
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      QQC.Popup {
        id: popup
        closePolicy: QQC.Popup.CloseOnPressOutsideParent | QQC.Popup.CloseOnEscape
        // Keep the trigger as the logical parent so CloseOnPressOutsideParent
        // treats a press on the trigger as inside, leaving the toggle to the
        // trigger's onClicked. The popup item is still rendered in the window
        // overlay, so it is not clipped by the trigger's ancestors. Position
        // and available height are recomputed on open and any time the
        // trigger's geometry changes, since a binding on mapToItem alone
        // won't reliably re-evaluate when ancestors scroll or resize.
        parent: trigger
        property real _anchorX: 0
        property real _anchorY: 0
        property real _availableBelow: 0
        readonly property var _windowItem: trigger.Window.window ? trigger.Window.window.contentItem : null
        readonly property real _windowHeight: _windowItem ? _windowItem.height : 0
        readonly property real _idealContent: resultList.contentHeight + Style.space(50)
        readonly property real _maxRowsHeight: root.popupRowHeight * 6 + 5 * Style.spacing.labelGap + Style.space(50)

        function reposition() {
          if (!parent) return
          var p = trigger.mapToItem(parent, 0, trigger.height + Style.spacing.xxs)
          _anchorX = p.x
          _anchorY = p.y
          // _anchorY is relative to the trigger; the clamp below needs the
          // anchor in window coordinates.
          var win = _windowItem ? trigger.mapToItem(_windowItem, 0, trigger.height + Style.spacing.xxs) : p
          _availableBelow = Math.max(0, _windowHeight - win.y - Style.space(12))
        }

        x: _anchorX
        y: _anchorY
        width: trigger.width
        // Clamp to whatever fits below the trigger; don't force popupMinHeight
        // when there isn't room, otherwise the popup overflows the window.
        implicitHeight: Math.min(_availableBelow, _idealContent, _maxRowsHeight)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        Connections {
          target: trigger
          function onXChanged() { popup.reposition() }
          function onYChanged() { popup.reposition() }
          function onWidthChanged() { popup.reposition() }
          function onHeightChanged() { popup.reposition() }
        }

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          reposition()
          searchField.text = ""
          root.refresh()
          root.recomputeFiltered()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onClosed: searchField.text = ""

        contentItem: Column {
          spacing: 0

          Item {
            id: searchHeader
            width: parent.width
            height: root.popupRowHeight + Style.spacing.controlPaddingX

            Row {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              spacing: Style.spacing.rowGap

              TextField {
                id: searchField
                width: parent.width - refreshButton.width - parent.spacing
                height: parent.height
                placeholderText: root.placeholderText
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body

                onTextChanged: {
                  root.recomputeFiltered()
                  if (resultList.count > 0) resultList.currentIndex = 0
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    popup.close(); event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.forceActiveFocus()
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.toggleCurrent()
                    }
                    event.accepted = true
                  }
                }
              }

              BorderSurface {
                id: refreshButton
                visible: root.arrayFrom(root.optionsCommand).length > 0
                enabled: !root.loadingOptions
                width: parent.height
                height: parent.height
                radius: Style.cornerRadius
                color: refreshHover.hovered
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : Style.normalFillFor(root.foreground, root.accent)
                borderSpec: refreshHover.hovered
                  ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
                  : Border.controlSpec("normal", root.foreground, root.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.loadingOptions ? "󰦖" : "󰑐"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body

                  RotationAnimator on rotation {
                    running: root.loadingOptions && !Style.reduceMotion
                    from: 0; to: 360
                    duration: Style.duration(800)
                    loops: Animation.Infinite
                  }
                }

                HoverHandler { id: refreshHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refresh()
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.10)
          }

          Item {
            width: parent.width
            height: popup.height - searchHeader.height - Style.spacing.xxs - 1

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: resultList.count === 0
              text: root.loadingOptions ? Commons.I18n.t("common.loading") : (root.optionsError !== "" ? root.optionsError : root.emptyText)
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ListView {
              id: resultList
              anchors.fill: parent
              spacing: Style.spacing.labelGap
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.filtered
              currentIndex: -1
              keyNavigationEnabled: false

              function toggleCurrent() {
                if (currentIndex < 0 || currentIndex >= root.filtered.length) return
                root.toggleValue(root.filtered[currentIndex].value)
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === Qt.Key_Down || event.text === "j") {
                  if (resultList.currentIndex >= resultList.count - 1) {
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex + 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || event.text === "k") {
                  if (resultList.currentIndex <= 0) {
                    searchField.forceActiveFocus()
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex - 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Space) {
                  resultList.toggleCurrent(); event.accepted = true
                }
              }

              delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool selected: root.isSelected(modelData.value)

                width: resultList.width
                height: Math.max(root.popupRowHeight, rowContent.implicitHeight + Style.spacing.rowPaddingX)
                color: index === resultList.currentIndex
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : "transparent"

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  spacing: Style.spacing.rowGap

                  BorderSurface {
                    id: checkbox
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Math.max(2, Style.cornerRadius / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    color: selected ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                    borderSpec: selected
                      ? Border.controlSpec("selected", root.foreground, root.accent)
                      : Border.controlSpec("normal", root.foreground, root.accent)

                    Text {
                      anchors.centerIn: parent
                      visible: selected
                      text: "✓"
                      color: Style.selectedStateColor(root.foreground, root.accent)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(checkbox.height * 0.85)
                      font.bold: true
                    }
                  }

                  Column {
                    width: parent.width - checkbox.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: index === resultList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: text !== ""
                      text: modelData.description
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: resultList.currentIndex = parent.index
                  onClicked: root.toggleValue(modelData.value)
                }
              }
            }
          }
        }
      }
    }
  }
}
''',
     'MultiSelect: Component-per-refresh with maybeFinish; destroy on completion/cancel'),
    ('shell/Ui/PanelSlider.qml',
     r'''    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
''',
     r'''    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onCanceled: {
      if (!root.dragging) return
      root.dragging = false
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
''',
     'PanelSlider: onCanceled resets drag state'),
    ('shell/services/AppLibrary.qml',
     r'''  property bool iconRescanQueued: false

  // Hexciri's own app icons are linked into the user's icon dir and redrawn in
  // place after each theme switch, which then writes icons.revision. The
  // revision goes on their URLs to make images reload instead of showing the
  // cached previous theme, and the rescan picks up links created for the first
  // time.
  readonly property string home: Quickshell.env("HOME")
  readonly property string userIconsPath: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/icons/"
  property int themeRevision: 0

  // Maps a desktop id to the version of the package that owns it. Rescanned
  // each time the app grid opens, since upgrades leave desktop entries alone.
  property var versions: ({})
  property var pendingVersions: ({})

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  // True while the launch OSD is on screen. It outlives the launch that opened
  // it: closeLaunchFeedback() normally takes it down, and its own duration
  // (the rest of launchTimeout) dismisses it if a show lands after that close.
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""

  // Emitted whenever the visible application set may have changed: desktop
  // entries appeared or vanished, or the hidden-entry filters reloaded.
  signal appsChanged()

  // Emitted when removing an entry has to open a terminal (a package
  // uninstall asking for a password), so an open launcher can step aside.
  // Other removals happen in place and the entry just drops out of the list.
  signal removalNeedsTerminal()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    // Prefer the context-limited app/device index. An unconstrained themed
    // lookup can resolve an app name such as "zoom" to an action icon instead.
    var found = root.iconIndex[value]
    var revision = root.themeRevision
    if (found) return Util.fileUrl(found) + (found.indexOf(root.userIconsPath) === 0 ? "?theme=" + revision : "")
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // The shell may start before first-install packages have finished placing
  // their icons; consumers call this when they open so icons appear live.
  // A request during a scan queues one more, since the running scan may have
  // listed icons before they changed.
  function refreshIcons() {
    if (iconIndexScan.running) root.iconRescanQueued = true
    else iconIndexScan.running = true
  }

  function refreshVersions() {
''',
     r'''  property bool iconRescanQueued: false
  property bool desktopEntryRescanQueued: false

  // Hexciri's own app icons are linked into the user's icon dir and redrawn in
  // place after each theme switch, which then writes icons.revision. The
  // revision goes on their URLs to make images reload instead of showing the
  // cached previous theme, and the rescan picks up links created for the first
  // time.
  readonly property string home: Quickshell.env("HOME")
  readonly property string userIconsPath: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/icons/"
  property int themeRevision: 0

  // Maps a desktop id to the version of the package that owns it. Rescanned
  // each time the app grid opens, since upgrades leave desktop entries alone.
  property var versions: ({})
  property var pendingVersions: ({})

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  // True while the launch OSD is on screen. It outlives the launch that opened
  // it: closeLaunchFeedback() normally takes it down, and its own duration
  // (the rest of launchTimeout) dismisses it if a show lands after that close.
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""

  // Emitted whenever the visible application set may have changed: desktop
  // entries appeared or vanished, or the hidden-entry filters reloaded.
  signal appsChanged()

  // Emitted when removing an entry has to open a terminal (a package
  // uninstall asking for a password), so an open launcher can step aside.
  // Other removals happen in place and the entry just drops out of the list.
  signal removalNeedsTerminal()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    // Prefer the context-limited app/device index. An unconstrained themed
    // lookup can resolve an app name such as "zoom" to an action icon instead.
    var found = root.iconIndex[value]
    var revision = root.themeRevision
    if (found) return Util.fileUrl(found) + (found.indexOf(root.userIconsPath) === 0 ? "?theme=" + revision : "")
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // The shell may start before first-install packages have finished placing
  // their icons; consumers call this when they open so icons appear live.
  // A request during a scan queues one more, since the running scan may have
  // listed icons before they changed.
  function refreshIcons() {
    if (iconIndexScan.running) root.iconRescanQueued = true
    else iconIndexScan.running = true
  }

  function refreshDesktopEntries() {
    if (desktopEntryScan.running) root.desktopEntryRescanQueued = true
    else desktopEntryScan.running = true
  }

  function refreshVersions() {
''',
     'AppLibrary: desktop-entry rescan queue + refreshDesktopEntries()'),
    ('shell/services/AppLibrary.qml',
     r'''  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.beginLaunchFeedback(name)
    // A terminal app goes through Hexciri's TUI launcher, which names its
    // terminal window after the command (org.hexciri.nvim), so the dock and
    // titlebars can tell Neovim from the terminal it runs in.
    var command = root.terminalCommand(DesktopEntries.byId(id))
    if (command.length > 0) {
      Util.execDetached("hexciri-launch-tui " + command.map(function(word) { return Util.shellQuote(word) }).join(" "))
      return
    }
    // Start gtk-launch inside a scope under app-graphical.slice so apps do not
    // inherit wayland-wm@.service. Keeping gtk-launch as the desktop-entry
    // resolver supports IDs with spaces and entries that UWSM rejects.
    // Keep the .desktop suffix or ids like org.telegram.desktop won't resolve.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // The command a terminal entry runs, without the field codes it leaves for a
''',
     r'''  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.beginLaunchFeedback(name)
    // A terminal app goes through Hexciri's TUI launcher, which names its
    // terminal window after the command (org.hexciri.nvim), so the dock and
    // titlebars can tell Neovim from the terminal it runs in.
    var command = root.terminalCommand(DesktopEntries.byId(id))
    if (command.length > 0) {
      Util.execArgv(["hexciri-launch-tui"].concat(command))
      return
    }
    // Start gtk-launch inside a scope under app-graphical.slice so apps do not
    // inherit wayland-wm@.service. Keeping gtk-launch as the desktop-entry
    // resolver supports IDs with spaces and entries that UWSM rejects.
    // Keep the .desktop suffix or ids like org.telegram.desktop won't resolve.
    Util.execArgv(["uwsm-app", "--", "gtk-launch", "--", id + ".desktop"])
  }

  // The command a terminal entry runs, without the field codes it leaves for a
''',
     'AppLibrary: argv-safe launch (execArgv, no shell-quoted string)'),
    ('shell/services/AppLibrary.qml',
     r'''  function iconIndexScanCommand() {
    // List app/device icons across the XDG icon dirs and /usr/share/pixmaps as
    // "<path>" lines. Some desktop entries, such as Print Settings, use device
    // icons like "printer" instead of app icons. SVGs are emitted before PNGs
    // so the parser, which keeps the first hit per name, prefers scalable icons.
    // Within each icon dir, PNGs go largest size first, so a 256x256 beats a 32x32.
    return [
      'dirs="$HOME/.icons ${XDG_DATA_HOME:-$HOME/.local/share}/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      '{',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '    echo;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '} | awk -v OFS="\\t" \'!length { dir++; next } /\\.svg$/ { print 0, 0, 0, $0; next } { print 1, dir, (match($0, /\\/[0-9]+x[0-9]+[@\\/]/) ? substr($0, RSTART + 1) + 0 : 0), $0 }\'',
      '  | sort -s -t $\'\\t\' -k1,1n -k2,2n -k3,3nr | cut -f 4-'
    ].join(' ')
''',
     r'''  function iconIndexScanCommand() {
    // List app/device icons across the XDG icon dirs and /usr/share/pixmaps as
    // "<path>" lines. Some desktop entries, such as Print Settings, use device
    // icons like "printer" instead of app icons. SVGs are emitted before PNGs
    // so the parser, which keeps the first hit per name, prefers scalable icons.
    // Within each icon dir, PNGs go largest size first, so a 256x256 beats a 32x32.
    return [
      'dirs=("$HOME/.icons" "${XDG_DATA_HOME:-$HOME/.local/share}/icons");',
      'IFS=":" read -ra xdg_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}";',
      'for d in "${xdg_dirs[@]}"; do [[ -n $d ]] && dirs+=("$d/icons"); done;',
      '{',
      '  for base in "${dirs[@]}"; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '    echo;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
      '} | awk -v OFS="\\t" \'!length { dir++; next } /\\.svg$/ { print 0, 0, 0, $0; next } { print 1, dir, (match($0, /\\/[0-9]+x[0-9]+[@\\/]/) ? substr($0, RSTART + 1) + 0 : 0), $0 }\'',
      '  | sort -s -t $\'\\t\' -k1,1n -k2,2n -k3,3nr | cut -f 4-'
    ].join(' ')
''',
     'AppLibrary: icon scan dirs as a bash array (spaces in paths)'),
    ('shell/services/AppLibrary.qml',
     r'''  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      root.shell.hide("hexciri.osd")
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
''',
     r'''  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      if (root.shell) root.shell.hide("hexciri.osd")
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
''',
     'AppLibrary: guard shell.hide on null shell'),
    ('shell/services/AppLibrary.qml',
     r'''    onStarted: desktopEntryOutput.text = ""
    onExited: root.loadDesktopEntryScan(desktopEntryOutput.text)
  }

  Process {
''',
     r'''    onStarted: desktopEntryOutput.text = ""
    onExited: {
      root.loadDesktopEntryScan(desktopEntryOutput.text)
      if (root.desktopEntryRescanQueued) {
        root.desktopEntryRescanQueued = false
        running = true
      }
    }
  }

  Process {
''',
     'AppLibrary: desktop-entry scan re-runs when queued'),
    ('shell/services/AppLibrary.qml',
     r'''    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  FileView {
''',
     r'''    id: iconIndexDebounce
    interval: 750
    onTriggered: root.refreshIcons()
  }

  FileView {
''',
     'AppLibrary: icon debounce goes through refreshIcons()'),
    ('shell/services/AppLibrary.qml',
     r'''    path: root.home + "/.local/state/hexciri/current/icons.revision"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      root.themeRevision++
      root.refreshIcons()
    }
  }

  FileView {
    path: root.omarchyPath + "/default/hexciri/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: root.loadConfiguredHides(text())
    onLoadFailed: root.loadConfiguredHides("")
''',
     r'''    path: root.home + "/.local/state/hexciri/current/icons.revision"
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: {
      reload()
      root.themeRevision++
      root.refreshIcons()
    }
  }

  FileView {
    path: root.omarchyPath + "/default/hexciri/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: reload()
    onLoadFailed: root.loadConfiguredHides("")
''',
     'AppLibrary: icons.revision reload() on change; hides FileView reload() on change'),
    ('shell/services/AppLibrary.qml',
     r'''      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      root.launchOsdOpen = true
      root.shell.summon("hexciri.osd", JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: launchTimeout.interval - launchDelay.interval }))
    }
  }

  Timer {
''',
     r'''      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      if (!root.shell) return
      root.launchOsdOpen = true
      root.shell.summon("hexciri.osd", JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: launchTimeout.interval - launchDelay.interval }))
    }
  }

  Timer {
''',
     'AppLibrary: guard shell.summon on null shell'),
    ('shell/services/AppLibrary.qml',
     r'''    target: DesktopEntries.applications
    function onValuesChanged() {
      desktopEntryScan.running = true
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    desktopEntryScan.running = true
    iconIndexScan.running = true
  }
}
''',
     r'''    target: DesktopEntries.applications
    function onValuesChanged() {
      root.refreshDesktopEntries()
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    desktopEntryScan.running = true
    iconIndexScan.running = true
  }
}
''',
     'AppLibrary: desktop-entry changes go through refreshDesktopEntries()'),
    ('shell/services/BackgroundSwitch.qml',
     r'''  function startLink() {
    linkProc.target = pendingLink
    pendingLink = ""
    linkProc.command = ["ln", "-nsf", linkProc.target, backgroundLink]
    linkProc.running = true
  }

  function begin(path, clipPath) {
''',
     r'''  function startLink() {
    linkProc.target = pendingLink
    pendingLink = ""
    linkProc.command = ["ln", "-nsf", "--", linkProc.target, backgroundLink]
    linkProc.running = true
  }

  function begin(path, clipPath) {
''',
     'BackgroundSwitch: ln -- guards the link target'),
    ('shell/services/BackgroundSwitch.qml',
     r'''  function own(path) {
    if (path && path.indexOf(transitionCache + "/") === 0 && ownedCovers.indexOf(path) === -1)
      ownedCovers = ownedCovers.concat([path])
  }

  function advance() {
''',
     r'''  function own(path) {
    var prefix = transitionCache + "/"
    if (!path || path.indexOf(prefix) !== 0) return
    var name = path.slice(prefix.length)
    if (!name || name === "." || name === ".." || name.indexOf("/") !== -1) return
    if (ownedCovers.indexOf(path) === -1)
      ownedCovers = ownedCovers.concat([path])
  }

  function advance() {
''',
     'BackgroundSwitch: own() rejects empty/dotdot/slashed cover names'),
    ('shell/services/BackgroundSwitch.qml',
     r'''  function settle() {
    if (busy) return
    if (reloadPending && !playProc.running && !reloadLock.running) reloadLock.running = true
    var kept = []
    for (var path of ownedCovers) {
      if (path === intro.themeBackground) kept.push(path)
      else Quickshell.execDetached(["rm", "-f", path])
    }
    ownedCovers = kept
    // The queued selection goes back through hexciri-theme-bg-set, which
    // finds its intro under the settings and theme as they are now.
    if (queuedPath) {
      Quickshell.execDetached(["hexciri-theme-bg-set", queuedPath])
      queuedPath = ""
    }
  }

  // A reveal clears its token just before its animation starts, so settling
  // waits until both have changed.
  Connections {
    target: root.intro
    function onCoverPresented() { root.advance() }
    function onThemeTokenChanged() {
      // A theme switch taking the cover brings its own background.
      if (root.intro.themeToken && root.intro.themeToken !== root.token) root.queuedPath = ""
      Qt.callLater(root.settle)
    }
    function onRevealingChanged() { Qt.callLater(root.settle) }
  }

  // A theme switch holds this lock while it stages, and may start an intro
  // of its own before releasing it. The reload is decided once the lock is
  // taken and runs before it is released, so no new intro can start between.
  Process {
    id: reloadLock
    command: ["flock", root.themeSetLock, "bash", "-c", 'echo locked; read -r go; [[ $go != reload ]] || exec hexciri-restart-hyprctl']
    stdinEnabled: true
    stdout: SplitParser {
      onRead: {
        var go = !root.busy && !playProc.running
        if (go) root.reloadPending = false
        reloadLock.write(go ? "reload\n" : "wait\n")
      }
    }
  }

  Process {
    id: snapshotProc
''',
     r'''  function settle() {
    if (busy) return
    if (reloadPending && !playProc.running && !reloadLock.running) reloadLock.running = true
    var kept = []
    for (var path of ownedCovers) {
      if (path === intro.themeBackground) kept.push(path)
      else Quickshell.execDetached(["rm", "-f", "--", path])
    }
    ownedCovers = kept
    // The queued selection goes back through hexciri-theme-bg-set, which
    // finds its intro under the settings and theme as they are now.
    if (queuedPath) {
      Quickshell.execDetached(["hexciri-theme-bg-set", queuedPath])
      queuedPath = ""
    }
  }

  // A reveal clears its token just before its animation starts, so settling
  // waits until both have changed.
  Connections {
    target: root.intro
    function onCoverPresented() { root.advance() }
    function onThemeTokenChanged() {
      // A theme switch taking the cover brings its own background.
      if (root.intro.themeToken && root.intro.themeToken !== root.token) root.queuedPath = ""
      Qt.callLater(root.settle)
    }
    function onRevealingChanged() { Qt.callLater(root.settle) }
  }

  // A theme switch holds this lock while it stages, and may start an intro
  // of its own before releasing it. The reload is decided once the lock is
  // taken and runs before it is released, so no new intro can start between.
  Process {
    id: reloadLock
    command: ["flock", root.themeSetLock, "bash", "-c", 'echo locked; read -r go; [[ $go != reload ]] || exec hexciri-restart-hyprctl']
    stdinEnabled: true
    stdout: SplitParser {
      onRead: {
        var go = !root.busy && !playProc.running
        if (go) root.reloadPending = false
        reloadLock.write(go ? "reload\n" : "wait\n")
      }
    }
    onExited: root.settle()
  }

  Process {
    id: snapshotProc
''',
     'BackgroundSwitch: rm -- guards; reload lock settles on exit'),
    ('shell/services/BackgroundSwitch.qml',
     r'''    id: snapshotProc
    property string forToken: ""
    property string file: ""
    onExited: function(exitCode) {
      // A theme switch that took the cover meanwhile wins.
      if (forToken !== root.token || root.intro.themeToken !== "") {
        Quickshell.execDetached(["rm", "-f", file])
      } else if (exitCode === 0) {
        root.own(file)
        root.cover(file)
      } else {
        root.cover(root.displayedStill())
      }
    }
  }

  Process {
    id: linkProc
''',
     r'''    id: snapshotProc
    property string forToken: ""
    property string file: ""
    onExited: function(exitCode) {
      // A theme switch that took the cover meanwhile wins.
      if (forToken !== root.token || root.intro.themeToken !== "") {
        Quickshell.execDetached(["rm", "-f", "--", file])
      } else if (exitCode === 0) {
        root.own(file)
        root.cover(file)
      } else {
        root.cover(root.displayedStill())
      }
    }
  }

  Process {
    id: linkProc
''',
     'BackgroundSwitch: rm -- guards the stale-cover removal'),
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
print("26 patch: %d file edits applied" % len(changed))
PY

# The python block above writes through >>"$_patch_log", a separate open
# file description when _patch_log is /dev/stdout. If this script's stdout
# is a regular file, the shell's fd offset is still where it was before
# python ran, so the validation/info prints below would overwrite the
# start of python's output (observed in sim: the first patched: lines
# were clobbered by the trailing info line). Seek stdout to EOF first;
# a guarded no-op on terminals and pipes, where lseek fails.
python3 -c "import os
try:
    os.lseek(1, 0, os.SEEK_END)
except OSError:
    pass" 2>/dev/null || true

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist. bash -n does not
# apply to QML; qmllint is warning-only when present (Quickshell imports
# are not all resolvable here).
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/Commons/InputDevices.qml shell/Commons/InputMethodState.qml shell/Commons/Style.qml shell/Commons/UntypedInput.qml shell/Ui/MultiSelect.qml shell/Ui/PanelSlider.qml shell/services/AppLibrary.qml shell/services/BackgroundSwitch.qml; do
    if [ -f "$FORK_OUT/$_f" ]; then
      qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (warning only)"
    fi
  done
  unset _f
else
  warn "qmllint not found; QML syntax not checked here"
fi
info "  watcher-reaping-style: orphaned input watchers reaped, Style hyprctl batched, per-refresh MultiSelect processes"
