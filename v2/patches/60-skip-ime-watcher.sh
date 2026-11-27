#!/usr/bin/env bash
# Hexciri fork patch 60: skip the Python input-method watcher on single-layout installs (upstream omacom/omarchy #20411).
#
# Upstream #20411 (verified against the live .diff, 2026-11-27): the bar read
# Fcitx through one long-running reader, default/input-methods/indicator.py,
# started by shell/Commons/InputMethodState.qml and kept resident all session
# (~19 MiB Python+GLib) even when there is nothing to switch between. The PR
# resolves Fcitx's profile path from the bus owner's environment (following
# symlinks), watches it with FileView, and on a single-group, single
# keyboard-* profile keeps the state in-process and skips starting
# indicator.py until the profile gains another group, method, or composition
# engine, is unreadable, or Super+I starts it on demand (released after
# 30 s idle). Any multi-group / multi-method / non-keyboard profile still
# starts the live watcher, and an empty or unreadable profile falls back to
# it, so this is safe on machines that do add a second layout later.
#
# Devi's machines are single US layout, so the watcher stays unloaded.
#
# Fork notes:
# - Rename map applied: Quickshell.env("HEXCIRI_PATH") in the watcher command
#   (the one OMARCHY_PATH reference in the file).
# - Pre-image is the live fork file, NOT the pin: patch 26 (#19968) already
#   added the Component.onDestruction block (restart.stop() +
#   watcher.running = false) that the PR's last hunk replaces, so the patch
#   anchors on the patch-26 form and dies loudly if it is not there.
#   (The PR base is newer than pin 94a8c3c: a bare `git apply` of the .diff
#   onto the pin file fails; the derived post-PR content was produced by
#   applying the .diff onto pin + patch 26, then the rename, and the two new
#   files below are that derived content byte-exact, never retyped.)
# - New file shell/Commons/InputMethodProfile.js (parseProfile, plus the
#   upstream node-test cases it carries) lands via the installer's whole
#   shell/ copy; no qmldir entry is needed for a relative .js import, and no
#   bin allowlist applies (not a bin/).
# - Upstream docs/input-methods.md hunk NOT ported: docs/ is not in FORK_OUT
#   and the repo has no docs/input-methods.md. Upstream
#   test/shell.d/input-indicator-test.sh hunk NOT ported: test/ is not in
#   FORK_OUT (patch 26 precedent); the parseProfile cases are behaviour-
#   simmed with node at build time instead (see the batch report).
# - No install.sh placement step needed: both files are under shell/, which
#   the installer copies wholesale and places.
#
# Standalone: bash v2/patches/60-skip-ime-watcher.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "60-skip-ime-watcher.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "60-skip-ime-watcher.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. InputMethodState.qml: in-process single-layout state, watcher on demand ---
# Whole-file replacement, not a surgical edit: the PR rewrites ~85% of this
# 38-line file (new properties, profile resolution, FileView, on-demand
# cycle, idle release). The replacement content is the upstream post-PR file
# with the HEXCIRI_PATH rename, derived mechanically (see header); the
# pre-image anchors below must all match first, so a drifted live file dies
# loudly instead of being overwritten blind.
step "Skipping the Python input-method watcher on single-layout installs"
_STATE="$FORK_OUT/shell/Commons/InputMethodState.qml"
_PROFILE="$FORK_OUT/shell/Commons/InputMethodProfile.js"
[ -f "$_STATE" ] || die "shell/Commons/InputMethodState.qml not found in fork output"
if grep -q 'InputMethodProfile' "$_STATE"; then
  if [ -f "$_PROFILE" ] && grep -q 'function parseProfile' "$_PROFILE"; then
    info "  patch 60: input-method watcher skip already present, skipping"
  else
    die "InputMethodState.qml already references InputMethodProfile but the .js is missing or wrong"
  fi
else
  grep -q 'if (!watcher.running) return false' "$_STATE" || die "pre-image anchor missing: old cycle() form not found, live file drifted"
  grep -q 'running: true' "$_STATE" || die "pre-image anchor missing: watcher 'running: true' not found, live file drifted"
  grep -q 'watcher.running = false' "$_STATE" || die "pre-image anchor missing: patch-26 onDestruction (watcher.running = false) not found, live file drifted"
  grep -q 'Quickshell.env("HEXCIRI_PATH")' "$_STATE" || die "pre-image anchor missing: HEXCIRI_PATH watcher command not found, live file drifted"
  [ ! -e "$_PROFILE" ] || die "InputMethodProfile.js already exists but InputMethodState.qml does not reference it, unexpected state"
  cat > "$_STATE" <<'INPUTMETHODSTATE_QML_EOF'
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "InputMethodProfile.js" as InputMethodProfile

Singleton {
  id: root
  property var state: ({})
  property bool profileResolved: false
  property string resolvedProfilePath: ""
  property bool watcherForced: false
  property bool profileNeedsWatcher: false
  property bool restartPending: false
  property string pendingCycle: ""

  readonly property bool shouldRunWatcher: watcherForced || profileNeedsWatcher

  // Parse the resolved Fcitx profile so single-layout installs avoid keeping
  // the 19 MiB Python+GLib indicator.py process resident when there is nothing
  // to switch between. Any profile with multiple groups, multiple methods, or
  // a non-keyboard composition engine starts the live watcher.
  function applyProfile(raw) {
    var parsed = InputMethodProfile.parseProfile(raw)
    root.profileNeedsWatcher = parsed.needsWatcher
    if (!parsed.needsWatcher && !root.shouldRunWatcher) {
      root.state = {
        methods: parsed.methods,
        current: parsed.methods[0],
        name: "",
        label: "",
        language: ""
      }
    }
  }

  function refreshProfilePath() {
    if (!resolveProfile.running) resolveProfile.running = true
  }

  function cycle(back) {
    var cmd = back ? "cycle back\n" : "cycle\n"
    if (watcher.running) {
      if (root.watcherForced) forcedIdleTimer.restart()
      watcher.write(cmd)
      return true
    }
    // Start the watcher on demand (e.g. Super+I cycling multiple Hyprland XKB
    // layouts on a single-IM Fcitx profile) and flush the cycle once up.
    root.pendingCycle = cmd
    root.restartPending = false
    root.watcherForced = true
    forcedIdleTimer.restart()
    return true
  }

  // Follow org.fcitx.Fcitx5 starting or restarting (e.g. after login startup
  // ordering, a service drop-in changing FCITX_CONFIG_HOME, or relinked
  // dotfiles) without keeping Python resident (~240 KiB PSS vs 19 MiB).
  Process {
    id: ownerWatch
    command: [
      "setpriv", "--pdeathsig", "TERM",
      "dbus-monitor", "--session",
      "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.fcitx.Fcitx5'"
    ]
    running: !root.shouldRunWatcher
    stdout: SplitParser {
      onRead: data => {
        if (String(data).indexOf("member=NameOwnerChanged") !== -1)
          root.refreshProfilePath()
      }
    }
  }

  // Locate Fcitx's actual profile path from the bus owner's environment (so a
  // service drop-in that moves FCITX_CONFIG_HOME/XDG_CONFIG_HOME is followed),
  // falling back to the shell's environment, and resolve symlinks so FileView
  // catches atomic saves that replace a dotfiles symlink target.
  Process {
    id: resolveProfile
    command: [
      "bash", "-c",
      'pid=$(busctl --user --timeout=1s call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.fcitx.Fcitx5 2>/dev/null | awk "{print \\$2}")\n' +
      'home=$HOME\n' +
      'fcitx_home=${FCITX_CONFIG_HOME:-}\n' +
      'xdg_home=${XDG_CONFIG_HOME:-}\n' +
      'if [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/environ ]]; then\n' +
      '  fcitx_home=""\n' +
      '  xdg_home=""\n' +
      '  while IFS= read -r -d "" entry; do\n' +
      '    case $entry in\n' +
      '      HOME=*) home=${entry#HOME=} ;;\n' +
      '      FCITX_CONFIG_HOME=*) fcitx_home=${entry#FCITX_CONFIG_HOME=} ;;\n' +
      '      XDG_CONFIG_HOME=*) xdg_home=${entry#XDG_CONFIG_HOME=} ;;\n' +
      '    esac\n' +
      '  done <"/proc/$pid/environ"\n' +
      'fi\n' +
      'if [[ -n $fcitx_home ]]; then\n' +
      '  [[ $fcitx_home == /* ]] || fcitx_home="$home/$fcitx_home"\n' +
      '  profile="$fcitx_home/profile"\n' +
      'else\n' +
      '  if [[ -n $xdg_home ]]; then\n' +
      '    [[ $xdg_home == /* ]] || xdg_home="$home/$xdg_home"\n' +
      '  else\n' +
      '    xdg_home="$home/.config"\n' +
      '  fi\n' +
      '  profile="$xdg_home/fcitx5/profile"\n' +
      'fi\n' +
      'readlink -f "$profile" 2>/dev/null || printf "%s\\n" "$profile"\n'
    ]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var resolved = String(text || "").trim()
        root.profileResolved = true
        if (resolved) {
          if (root.resolvedProfilePath === resolved) profileFile.reload()
          else root.resolvedProfilePath = resolved
        } else {
          root.profileNeedsWatcher = true
        }
      }
    }
    onExited: function(code) {
      if (!root.profileResolved) {
        root.profileResolved = true
        if (!root.resolvedProfilePath) root.profileNeedsWatcher = true
      }
    }
  }

  FileView {
    id: profileFile
    path: root.resolvedProfilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyProfile(text())
    onLoadFailed: root.profileNeedsWatcher = true
    onFileChanged: reload()
  }

  // One reader and pending selection for every monitor's keyboard widget.
  Process {
    id: watcher
    command: ["/usr/bin/python3", Quickshell.env("HEXCIRI_PATH") + "/default/input-methods/indicator.py"]
    running: root.shouldRunWatcher && !root.restartPending
    stdinEnabled: true
    onRunningChanged: {
      if (running && root.pendingCycle !== "") {
        var cmd = root.pendingCycle
        root.pendingCycle = ""
        watcher.write(cmd)
      }
    }
    stdout: SplitParser {
      onRead: data => {
        try { root.state = JSON.parse(data) } catch (e) {}
      }
    }
    onExited: {
      root.pendingCycle = ""
      if (root.shouldRunWatcher) {
        root.state = ({})
        root.restartPending = true
        restart.restart()
      } else {
        root.applyProfile(profileFile.text())
        root.refreshProfilePath()
      }
    }
  }

  Timer {
    id: restart
    interval: 5000
    onTriggered: root.restartPending = false
  }

  // Release an on-demand Super+I watcher once idle so a single accidental press
  // on a single-layout machine does not keep indicator.py resident all session.
  Timer {
    id: forcedIdleTimer
    interval: 30000
    onTriggered: root.watcherForced = false
  }

  Component.onDestruction: {
    restart.stop()
    forcedIdleTimer.stop()
    ownerWatch.running = false
    root.watcherForced = false
    root.profileNeedsWatcher = false
  }
}
INPUTMETHODSTATE_QML_EOF
  cat > "$_PROFILE" <<'INPUTMETHODPROFILE_JS_EOF'
// Parse an Fcitx5 profile file to decide whether the long-running Python
// indicator.py watcher is needed. Single-group, single-keyboard-* profiles
// have nothing to switch between and stay in-process until the profile changes.
function parseProfile(raw) {
  var text = String(raw || "")
  if (!text.trim()) return { needsWatcher: true, methods: [] }

  var section = ""
  var groupCount = 0
  var methods = []
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    if (line.charAt(0) === "[" && line.charAt(line.length - 1) === "]") {
      section = line.slice(1, -1)
      if (/^Groups\/\d+$/.test(section)) groupCount += 1
      continue
    }
    if (/^Groups\/0\/Items\/\d+$/.test(section) && line.indexOf("Name=") === 0) {
      var name = line.slice(5).trim()
      if (name && methods.indexOf(name) === -1) methods.push(name)
    }
  }

  var singleKeyboard = groupCount <= 1 && methods.length === 1 && methods[0].indexOf("keyboard-") === 0
  return { needsWatcher: !singleKeyboard, methods: methods }
}

if (typeof module !== "undefined") {
  module.exports = { parseProfile: parseProfile }
}
INPUTMETHODPROFILE_JS_EOF
  _a8e1e72b2a2e0f5d1bc039d8a2fd72fc8a6fd11b03c94476e288ca5b43453eca="$(sha256sum "$_STATE" | cut -d' ' -f1)"
  _2a78ea1456ec5ba3d93275fb9e60ee3249059ddc265f971e1313444f81f1b2ec="$(sha256sum "$_PROFILE" | cut -d' ' -f1)"
  [ "$_a8e1e72b2a2e0f5d1bc039d8a2fd72fc8a6fd11b03c94476e288ca5b43453eca" = "a8e1e72b2a2e0f5d1bc039d8a2fd72fc8a6fd11b03c94476e288ca5b43453eca" ] || die "InputMethodState.qml sha256 mismatch after write (got $_a8e1e72b2a2e0f5d1bc039d8a2fd72fc8a6fd11b03c94476e288ca5b43453eca)"
  [ "$_2a78ea1456ec5ba3d93275fb9e60ee3249059ddc265f971e1313444f81f1b2ec" = "2a78ea1456ec5ba3d93275fb9e60ee3249059ddc265f971e1313444f81f1b2ec" ] || die "InputMethodProfile.js sha256 mismatch after write (got $_2a78ea1456ec5ba3d93275fb9e60ee3249059ddc265f971e1313444f81f1b2ec)"
  grep -q 'running: root.shouldRunWatcher && !root.restartPending' "$_STATE" || die "watcher running binding missing after write"
  grep -q 'function parseProfile' "$_PROFILE" || die "parseProfile missing after write"
  grep -q 'OMARCHY' "$_STATE" && die "OMARCHY reference leaked into InputMethodState.qml" || true
  grep -q 'OMARCHY' "$_PROFILE" && die "OMARCHY reference leaked into InputMethodProfile.js" || true
  printf 'patched: InputMethodState.qml + InputMethodProfile.js (watcher skipped on single-layout profiles)\n' >> "$_patch_log"
  CHANGED=1
fi

printf 'input-method watcher skip patch: %d file set(s) applied\n' "$CHANGED" >> "$_patch_log"
info "  patch 60: Python input-method watcher skipped on single-layout installs (19 MiB stays unloaded)"
