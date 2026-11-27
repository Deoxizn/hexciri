#!/bin/bash
# Hexciri fork patch 25: snappier shell UI, fewer subprocess forks
# (omarchy commit 8807715c7, #20126).
#
# What it does, per file (upstream, verbatim except renames noted below):
#   * shell/plugins/background/Background.qml: openSelector() summons the
#     image picker in-process via shell.summon("hexciri.image-picker")
#     with the IPC route as fallback, and the bgSwitchProc helper process
#     goes away; the reveal mask only allocates its full-screen layer
#     while a transition is active.
#   * shell/plugins/bar/widgets/Microphone.qml: middle-click toggles the
#     audio panel in-process via bar.shell.toggle("hexciri.audio"), with
#     the hexciri-shell run as fallback.
#   * shell/plugins/bar/widgets/Tray.qml: the drawer expands in 200 ms
#     and collapses in 135 ms (was a single 600 ms Waybar-matching
#     animation), driven by an explicit NumberAnimation instead of a
#     Behavior so a rapid hover-off still lands.
#   * shell/plugins/bar/widgets/Workspaces.qml: workspace focus dispatches
#     in-process via Hyprland.dispatch instead of bar.run("hyprctl ...").
#   * shell/plugins/menu/BarWidget.qml: the menu trigger toggles in-process
#     via bar.shell.toggle("hexciri.menu"), with the shell run as fallback.
#     The fallback keeps patch 02's absolute hexciri-shell path.
#   * shell/plugins/panels/audio/Panel.qml: a Bluetooth (bluez_output.*)
#     sink is its own volume sink like an ALSA one, so no script round-trip.
#   * shell/plugins/panels/power/Panel.qml: the power panel reads the
#     battery service in-process (firstPartyServiceFor("hexciri.battery"))
#     instead of the system-stats script: batteryService property,
#     profileName/syncActiveProfile with a deferred profile, refresh()
#     only re-reads profiles when the list is empty, updateKeyValue
#     becomes updateBatteryInfo (systemInfo goes away with systemProc),
#     setProfile reflects immediately, profile changes reconcile from
#     PowerProfiles / the battery service, actionProc reconciles back to
#     the true profile on failure, and the hero percent falls back to the
#     UPower fraction when the script reports nothing.
#   * shell/plugins/services/media/Service.qml: volume keys act in-process
#     on Bluetooth sinks too, not just ALSA.
#   * shell/plugins/dock/Dock.qml: this commit's Dock.qml hunk (the noAnim
#     helper + in-process bringForward) was ALREADY delivered by patch 20,
#     which also carries #20344's deltas and #19970's validation (patch 23)
#     on top of it. Patch 25 therefore does NOT rewrite bringForward: it
#     verifies the helper is present and the sleep-0.4 form is gone, and
#     skips Dock.qml. If the helper is missing but the pin-era bringForward
#     is still there (patch 20 never applied), it applies this commit's
#     Dock.qml hunk as a fallback; any other Dock.qml state dies loud
#     instead of silently dropping the #20344/#19970 deltas.
#
# Adaptation notes (vs upstream verbatim):
#   * Renames only: hexciri-shell / hexciri.menu / hexciri.audio /
#     hexciri.image-picker / hexciri.battery / hexciri-powerprofiles-set /
#     hexciri-battery-status / hexciri-audio-output-sink (the live rename
#     map turns `omarchy-` / `omarchy.` into `hexciri-` / `hexciri.`).
#     The menu BarWidget fallback keeps patch 02's absolute path
#     /usr/share/hexciri/bin/hexciri-shell; the microphone fallback keeps
#     the bare hexciri-shell call (patch 02 never absolutized it).
#   * No test-file edits: test/shell.d/{audio,dock}-test.sh are NOT in
#     FORK_OUT (fork-shell.sh extracts only listed subsets; test/ is not
#     one), and no existing patch touches tests. The upstream dock/audio
#     assertions were re-run by hand against the patched files in sim
#     (node vm harness); see the README section.
#   * The power panel's new Connections blocks reference PowerProfiles
#     and batteryService.activePowerProfile / refreshPowerProfile() exactly
#     as upstream: no import change (Quickshell.Services.UPower is already
#     imported), and the battery service calls are guarded (typeof check /
#     null-safe) so a shell without firstPartyServiceFor keeps working.
#
# Standalone: bash v2/patches/25-snappier-shell-ui.sh [FORK_OUT]
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
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "25-snappier-shell-ui.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Snappier shell UI, fewer forks (omarchy #20126, 8807715c7) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # Background: summon the picker in-process; IPC route stays as fallback.
    ("shell/plugins/background/Background.qml",
     "  function openSelector() {\n"
     "    if (!bgSwitchProc.running) bgSwitchProc.running = true\n"
     "  }",
     "  function openSelector() {\n"
     "    var payload = JSON.stringify({ source: \"backgrounds\" })\n"
     "\n"
     "    // A cloned background may not summon the picker in-process, so it takes\n"
     "    // the IPC route instead.\n"
     "    if (!root.shell || !root.shell.summon(\"hexciri.image-picker\", payload))\n"
     "      Util.execArgv([\"hexciri-shell\", \"shell\", \"summon\", \"hexciri.image-picker\", payload])\n"
     "  }",
     "Background openSelector: summon the picker in-process"),
    # Background: the bgSwitchProc helper process goes away with the old
    # openSelector (openThemeSwitcher next to it already uses summon).
    # NOTE: pure removal — see REMOVALS below. It cannot live in
    # REPLACEMENTS: its `new` text ("Process { id: sizeProbe") is already
    # in the file, so the generic "new in s" check would skip it forever.
    # Background: only allocate the full-screen mask layer mid-transition.
    ("shell/plugins/background/Background.qml",
     "      Item {\n"
     "        id: revealMask\n"
     "        anchors.fill: parent\n"
     "        visible: false\n"
     "        layer.enabled: true",
     "      Item {\n"
     "        id: revealMask\n"
     "        anchors.fill: parent\n"
     "        visible: false\n"
     "        // Only allocate the full-screen mask layer while a transition is active.\n"
     "        layer.enabled: root.incomingBackground !== \"\"",
     "Background revealMask: allocate the mask layer only mid-transition"),
    # Microphone: middle-click toggles the audio panel in-process.
    ("shell/plugins/bar/widgets/Microphone.qml",
     "    onPressed: function(b) {\n"
     "      if (b === Qt.MiddleButton) root.bar.run(\"hexciri-shell shell toggle hexciri.audio\")\n"
     "      else root.toggleMute()\n"
     "    }",
     "    onPressed: function(b) {\n"
     "      if (b === Qt.MiddleButton) {\n"
     "        if (!root.bar) return\n"
     "        if (!root.bar.shell || typeof root.bar.shell.toggle !== \"function\" || !root.bar.shell.toggle(\"hexciri.audio\", \"{}\"))\n"
     "          root.bar.run(\"hexciri-shell shell toggle hexciri.audio\")\n"
     "      } else {\n"
     "        root.toggleMute()\n"
     "      }\n"
     "    }",
     "Microphone middle-click: toggle the audio panel in-process"),
    # Tray: brisk expand, slightly faster collapse, explicit animation.
    ("shell/plugins/bar/widgets/Tray.qml",
     "  // Match Waybar's group/tray-expander drawer transition-duration.\n"
     "  readonly property int animationDuration: 600\n"
     "  property real revealProgress: expanded || holdOpen ? 1 : 0",
     "  // Expand briskly on hover and collapse slightly faster so the drawer stays crisp.\n"
     "  readonly property int expandDuration: 200\n"
     "  readonly property int collapseDuration: 135\n"
     "  readonly property bool drawerOpen: expanded || holdOpen\n"
     "  property real revealProgress: 0",
     "Tray drawer: 200ms expand / 135ms collapse timings"),
    ("shell/plugins/bar/widgets/Tray.qml",
     "  Behavior on revealProgress {\n"
     "    NumberAnimation { duration: Style.duration(root.animationDuration); easing.type: Easing.OutCubic }\n"
     "  }",
     "  Component.onCompleted: revealProgress = drawerOpen ? 1 : 0\n"
     "\n"
     "  onDrawerOpenChanged: {\n"
     "    revealAnimation.stop()\n"
     "    var target = drawerOpen ? 1 : 0\n"
     "    var duration = Style.duration(drawerOpen ? expandDuration : collapseDuration)\n"
     "    if (duration <= 0) {\n"
     "      revealProgress = target\n"
     "      return\n"
     "    }\n"
     "    revealAnimation.to = target\n"
     "    revealAnimation.duration = duration\n"
     "    revealAnimation.start()\n"
     "  }\n"
     "\n"
     "  NumberAnimation {\n"
     "    id: revealAnimation\n"
     "    target: root\n"
     "    property: \"revealProgress\"\n"
     "    easing.type: Easing.Bezier\n"
     "    easing.bezierCurve: Style.easeOut\n"
     "  }",
     "Tray drawer: explicit reveal animation driven by drawerOpen"),
    # Workspaces: focus in-process instead of a hyprctl subprocess.
    ("shell/plugins/bar/widgets/Workspaces.qml",
     "  function dispatch(expression) {\n"
     "    if (root.bar) root.bar.run(\"hyprctl dispatch \" + Util.shellQuote(expression))\n"
     "  }",
     "  function dispatch(expression) {\n"
     "    Hyprland.dispatch(expression)\n"
     "  }",
     "Workspaces dispatch: Hyprland.dispatch in-process"),
    # Menu trigger: toggle in-process; the fallback keeps patch 02's
    # absolute hexciri-shell path.
    ("shell/plugins/menu/BarWidget.qml",
     "      else root.bar.run(\"/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu '{\\\"menu\\\":\\\"root\\\"}'\")",
     "      else if (!root.bar.shell || typeof root.bar.shell.toggle !== \"function\" || !root.bar.shell.toggle(\"hexciri.menu\", JSON.stringify({ menu: \"root\" })))\n"
     "        root.bar.run(\"/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu '{\\\"menu\\\":\\\"root\\\"}'\")",
     "Menu trigger: toggle the menu in-process"),
    # Audio panel: a Bluetooth sink is its own volume sink, like ALSA.
    ("shell/plugins/panels/audio/Panel.qml",
     "    // A hardware output is its own volume sink, as hexciri-audio-output-sink\n"
     "    // reports without looking further, so only a DSP sink needs the script.\n"
     "    if (sink && String(sink.name).indexOf(\"alsa_output.\") === 0) {\n"
     "      volumeSinkName = String(sink.name)\n"
     "      return\n"
     "    }",
     "    // A hardware output (ALSA or Bluetooth) is its own volume sink, as\n"
     "    // hexciri-audio-output-sink reports without looking further, so only a DSP\n"
     "    // sink needs the script.\n"
     "    var name = sink ? String(sink.name) : \"\"\n"
     "    if (name.indexOf(\"alsa_output.\") === 0 || name.indexOf(\"bluez_output.\") === 0) {\n"
     "      volumeSinkName = name\n"
     "      return\n"
     "    }",
     "Audio panel: Bluetooth sinks resolve without the script"),
    # Power panel: read the battery service in-process; systemInfo goes
    # away with the system-stats script.
    ("shell/plugins/panels/power/Panel.qml",
     "  property var batteryInfo: ({})\n"
     "  property var systemInfo: ({})",
     "  property var batteryInfo: ({})\n"
     "  readonly property var batteryService: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === \"function\"\n"
     "    ? bar.shell.firstPartyServiceFor(\"hexciri.battery\") : null",
     "Power panel: read the battery service in-process"),
    # Power panel: profile helpers + deferred profile, ahead of refresh().
    ("shell/plugins/panels/power/Panel.qml",
     "  function refresh() {",
     "  function profileName(profile) {\n"
     "    switch (profile) {\n"
     "      case PowerProfile.PowerSaver: return \"power-saver\"\n"
     "      case PowerProfile.Performance: return \"performance\"\n"
     "      default: return \"balanced\"\n"
     "    }\n"
     "  }\n"
     "\n"
     "  property string deferredProfile: \"\"\n"
     "\n"
     "  function syncActiveProfile(name, force) {\n"
     "    if (!name) return\n"
     "    if (!force && actionProc.running) {\n"
     "      deferredProfile = name\n"
     "      return\n"
     "    }\n"
     "    activeProfile = name\n"
     "    if (opened && !cursorActive) {\n"
     "      var idx = profiles.indexOf(activeProfile)\n"
     "      if (idx >= 0) profileIndex = idx\n"
     "    }\n"
     "  }\n"
     "\n"
     "  function refresh() {",
     "Power panel: profileName/syncActiveProfile + deferred profile"),
    # Power panel: refresh() only re-reads profiles when the list is empty.
    ("shell/plugins/panels/power/Panel.qml",
     "    if (!batteryProc.running) batteryProc.running = true\n"
     "    if (!profilesProc.running) profilesProc.running = true\n"
     "    if (!systemProc.running) systemProc.running = true",
     "    if (!batteryProc.running) batteryProc.running = true\n"
     "    if (profiles.length === 0 && !profilesProc.running) profilesProc.running = true",
     "Power panel refresh: only re-read profiles when the list is empty"),
    # Power panel: updateKeyValue becomes updateBatteryInfo.
    ("shell/plugins/panels/power/Panel.qml",
     "  function updateKeyValue(raw, targetName) {\n"
     "    var next = Model.parseKeyValue(raw)\n"
     "    // Keep last known good data if a refresh briefly returns nothing — happens\n"
     "    // around AC plug/unplug events. Avoids the section collapsing mid-transition.\n"
     "    if (Object.keys(next).length === 0) return\n"
     "    if (targetName === \"battery\") batteryInfo = next\n"
     "    else systemInfo = next\n"
     "  }",
     "  function updateBatteryInfo(raw) {\n"
     "    var next = Model.parseKeyValue(raw)\n"
     "    // Keep last known good data if a refresh briefly returns nothing — happens\n"
     "    // around AC plug/unplug events. Avoids the section collapsing mid-transition.\n"
     "    if (Object.keys(next).length === 0) return\n"
     "    batteryInfo = next\n"
     "  }",
     "Power panel: updateKeyValue becomes updateBatteryInfo"),
    # Power panel: reflect the chosen profile immediately; the exit /
    # reactive handlers reconcile back to the true profile.
    ("shell/plugins/panels/power/Panel.qml",
     "  function setProfile(profile) {\n"
     "    if (!profile || actionProc.running) return\n"
     "    actionProc.command = [\"hexciri-powerprofiles-set\", root.discharging ? \"battery\" : \"ac\", profile]\n"
     "    actionProc.running = true\n"
     "  }",
     "  function setProfile(profile) {\n"
     "    if (!profile || actionProc.running) return\n"
     "    // Reflect the chosen profile immediately; on failure or daemon change, the\n"
     "    // exit/reactive handlers reconcile back to the true active profile.\n"
     "    deferredProfile = \"\"\n"
     "    activeProfile = profile\n"
     "    var idx = profiles.indexOf(profile)\n"
     "    if (idx >= 0) profileIndex = idx\n"
     "    actionProc.command = [\"hexciri-powerprofiles-set\", root.discharging ? \"battery\" : \"ac\", profile]\n"
     "    actionProc.running = true\n"
     "  }",
     "Power panel setProfile: reflect the chosen profile immediately"),
    # Power panel: sync from the battery service when the panel opens.
    ("shell/plugins/panels/power/Panel.qml",
     "      refresh()\n"
     "      var idx = profiles.indexOf(activeProfile)\n"
     "      profileIndex = idx >= 0 ? idx : 0\n"
     "      cursorActive = false",
     "      if (batteryService && batteryService.activePowerProfile)\n"
     "        syncActiveProfile(batteryService.activePowerProfile)\n"
     "      refresh()\n"
     "      var idx = profiles.indexOf(activeProfile)\n"
     "      profileIndex = idx >= 0 ? idx : 0\n"
     "      cursorActive = false",
     "Power panel onOpened: sync the profile from the battery service"),
    # Power panel: reconcile profile changes from PowerProfiles and from
    # the battery service.
    ("shell/plugins/panels/power/Panel.qml",
     "  visible: batteryPresent\n"
     "  implicitWidth: batteryPresent ? button.implicitWidth : 0\n"
     "  implicitHeight: batteryPresent ? button.implicitHeight : 0\n"
     "\n"
     "  Process {\n"
     "    id: batteryProc",
     "  visible: batteryPresent\n"
     "  implicitWidth: batteryPresent ? button.implicitWidth : 0\n"
     "  implicitHeight: batteryPresent ? button.implicitHeight : 0\n"
     "\n"
     "  Connections {\n"
     "    target: PowerProfiles\n"
     "    function onProfileChanged() { root.syncActiveProfile(root.profileName(PowerProfiles.profile)) }\n"
     "  }\n"
     "\n"
     "  Connections {\n"
     "    target: root.batteryService\n"
     "    function onActivePowerProfileChanged() {\n"
     "      if (root.batteryService) root.syncActiveProfile(root.batteryService.activePowerProfile)\n"
     "    }\n"
     "  }\n"
     "\n"
     "  Process {\n"
     "    id: batteryProc",
     "Power panel: reconcile profile changes from PowerProfiles / battery service"),
    # Power panel: batteryProc feeds updateBatteryInfo now.
    ("shell/plugins/panels/power/Panel.qml",
     "    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, \"battery\") }",
     "    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBatteryInfo(text) }",
     "Power panel batteryProc: feed updateBatteryInfo"),
    # Power panel: the system-stats process goes away with systemInfo.
    # NOTE: pure removal — see REMOVALS below. Its `new` text
    # ("Process { id: actionProc") is already in the file, so the generic
    # "new in s" check would skip it forever.
    # Power panel: actionProc reconciles the profile on exit.
    ("shell/plugins/panels/power/Panel.qml",
     "  Process {\n"
     "    id: actionProc\n"
     "    onExited: root.refresh()\n"
     "  }",
     "  Process {\n"
     "    id: actionProc\n"
     "    onExited: function(exitCode) {\n"
     "      var deferred = root.deferredProfile\n"
     "      root.deferredProfile = \"\"\n"
     "      if (exitCode !== 0) {\n"
     "        if (root.batteryService && root.batteryService.activePowerProfile)\n"
     "          root.syncActiveProfile(root.batteryService.activePowerProfile, true)\n"
     "        if (!profilesProc.running) profilesProc.running = true\n"
     "      } else {\n"
     "        if (deferred !== \"\") root.syncActiveProfile(deferred, true)\n"
     "        if (root.batteryService) root.batteryService.refreshPowerProfile()\n"
     "        else if (!profilesProc.running) profilesProc.running = true\n"
     "      }\n"
     "    }\n"
     "  }",
     "Power panel actionProc: reconcile the profile on exit"),
    # Power panel: fall back to the UPower fraction for the hero percent.
    ("shell/plugins/panels/power/Panel.qml",
     "            text: root.reading(root.batteryInfo.percentage) || \"—\"",
     "            text: root.reading(root.batteryInfo.percentage)\n"
     "              || (root.batteryPresent ? Commons.I18n.formatNumber(Math.round(root.batteryFraction * 100)) + \"%\" : \"—\")",
     "Power panel hero percent: fall back to the UPower fraction"),
    # Media service: volume keys act in-process on Bluetooth sinks too.
    ("shell/plugins/services/media/Service.qml",
     "  // sink it feeds on every press, from the live routing. An ALSA sink is its\n"
     "  // own physical sink, so only then do the keys act here; any other default\n"
     "  // sink falls back to the script.\n"
     "  readonly property var defaultSink: Pipewire.defaultAudioSink\n"
     "  readonly property var volumeSink: defaultSink && String(defaultSink.name).indexOf(\"alsa_output.\") === 0 ? defaultSink : null",
     "  // sink it feeds on every press, from the live routing. An ALSA or Bluetooth\n"
     "  // sink is its own physical sink, so keys act here; any other default sink\n"
     "  // (such as a DSP filter-chain) falls back to the script.\n"
     "  readonly property var defaultSink: Pipewire.defaultAudioSink\n"
     "  readonly property var volumeSink: defaultSink && (String(defaultSink.name).indexOf(\"alsa_output.\") === 0 || String(defaultSink.name).indexOf(\"bluez_output.\") === 0) ? defaultSink : null",
     "Media service: volume keys act on Bluetooth sinks too"),
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

# Pure removals: (file, old, new, label). Unlike REPLACEMENTS, the skip
# test here is "old absent" — the `new` text of a deletion is a surviving
# neighbour block that is already in the file, so "new in s" would report
# the removal done when it never ran. Both removals are load-bearing:
# bgSwitchProc is dead once openSelector summons in-process, and
# systemProc calls updateKeyValue, which the replacement above renames to
# updateBatteryInfo — leaving the block would call a missing function.
REMOVALS = [
    ("shell/plugins/background/Background.qml",
     "  // hexciri-theme-bg-set tells this service of the new background itself. A\n"
     "  // refresh here would start an ordinary transition under an intro's cover.\n"
     "  Process {\n"
     "    id: bgSwitchProc\n"
     "    command: [\"bash\", \"-c\", \"background=$(hexciri-theme-bg-switcher); [[ -n $background ]] && hexciri-theme-bg-set \\\"$background\\\"\"]\n"
     "  }\n"
     "\n"
     "  Process {\n"
     "    id: sizeProbe",
     "  Process {\n"
     "    id: sizeProbe",
     "Background: remove the bgSwitchProc helper process"),
    ("shell/plugins/panels/power/Panel.qml",
     "  Process {\n"
     "    id: systemProc\n"
     "    command: [\"hexciri-system-stats\"]\n"
     "    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, \"system\") }\n"
     "  }\n"
     "\n"
     "  Process {\n"
     "    id: actionProc",
     "  Process {\n"
     "    id: actionProc",
     "Power panel: remove the system-stats process"),
]

for rel, old, new, label in REMOVALS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if old not in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

# --- Dock.qml: this commit's hunk already landed in patch 20. ---
# Verify that, and only fall back to applying the hunk when patch 20 never
# ran (pin-era bringForward still present). Any other state dies loud so a
# rewrite here can never silently drop patch 20's #20344 deltas or patch
# 23's validation hunk.
_dock_rel = "shell/plugins/dock/Dock.qml"
_dock_fp = root + "/" + _dock_rel
try:
    with open(_dock_fp) as f:
        _dock = f.read()
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping (Dock.qml snappier check)" % _dock_rel)
    _dock = None
if _dock is not None:
    if "function scheduleNoAnimUnset(address)" in _dock:
        if "sleep 0.4" in _dock:
            print("ERROR: Dock.qml has the noAnim helper but still builds a sleep 0.4 command — inconsistent state, refusing to touch it", file=sys.stderr)
            sys.exit(1)
        print("Dock.qml: noAnim helper already present via patch 20, skipping")
    elif "sleep 0.4" in _dock and "var steps = []" in _dock:
        # Patch 20 never applied: apply #20126's Dock.qml hunk (helper +
        # in-process bringForward) against the pin-era function. No #20344
        # deltas exist in this state, so none can be dropped.
        _helper = (
            "  property var pendingNoAnimUnsets: []\n"
            "\n"
            "  function scheduleNoAnimUnset(address) {\n"
            "    if (pendingNoAnimUnsets.indexOf(address) < 0)\n"
            "      pendingNoAnimUnsets = pendingNoAnimUnsets.concat([address])\n"
            "    noAnimUnsetTimer.restart()\n"
            "  }\n"
            "\n"
            "  function flushNoAnimUnsets() {\n"
            "    noAnimUnsetTimer.stop()\n"
            "    var addresses = pendingNoAnimUnsets\n"
            "    pendingNoAnimUnsets = []\n"
            "    for (var i = 0; i < addresses.length; i++)\n"
            "      Hyprland.dispatch(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"unset\\\", window = \\\"address:\" + addresses[i] + \"\\\" })\")\n"
            "  }\n"
            "\n"
            "  // If the dock is disabled or reloaded within 400ms of restoring a minimized\n"
            "  // window, flush pending resets immediately so no_anim isn't left stuck on.\n"
            "  Component.onDestruction: flushNoAnimUnsets()\n"
            "\n"
            "  Timer {\n"
            "    id: noAnimUnsetTimer\n"
            "    interval: 400\n"
            "    repeat: false\n"
            "    onTriggered: root.flushNoAnimUnsets()\n"
            "  }\n"
            "\n"
        )
        _old_bf = (
            "  // A window the dock brings forward lands on top of the others, focused; a\n"
            "  // minimized one first comes back to the workspace in front of the user.\n"
            "  function bringForward(window) {\n"
            "    var address = String(window.address || \"\")\n"
            "    if (!address) {\n"
            "      window.toplevel.activate()\n"
            "      return\n"
            "    }\n"
            "    if (address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
            "    var target = \"window = \\\"address:\" + address + \"\\\"\"\n"
            "    var steps = []\n"
            "    var after = []\n"
            "    if (window.minimized) {\n"
            "      var monitor = Hyprland.focusedMonitor\n"
            "      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
            "      if (!(workspace >= 1)) return\n"
            "      // A restored window is simply there again, without animating in.\n"
            "      steps.push(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"1\\\", \" + target + \" })\")\n"
            "      steps.push(\"hl.dsp.window.move({ workspace = \\\"\" + workspace + \"\\\", \" + target + \" })\")\n"
            "      after.push(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"unset\\\", \" + target + \" })\")\n"
            "    }\n"
            "    steps.push(\"hl.dsp.focus({ \" + target + \" })\")\n"
            "    steps.push(\"hl.dsp.window.alter_zorder({ mode = \\\"top\\\", \" + target + \" })\")\n"
            "    var dispatch = function(step) { return \"hyprctl dispatch \" + Util.shellQuote(step) }\n"
            "    var command = steps.map(dispatch).join(\" && \")\n"
            "    if (after.length > 0) command += \"; sleep 0.4; \" + after.map(dispatch).join(\"; \")\n"
            "    Util.execDetached(command)\n"
            "  }"
        )
        _new_bf = (
            "  // A window the dock brings forward lands on top of the others, focused; a\n"
            "  // minimized one first comes back to the workspace in front of the user.\n"
            "  function bringForward(window) {\n"
            "    var address = String(window.address || \"\")\n"
            "    if (!address) {\n"
            "      window.toplevel.activate()\n"
            "      return\n"
            "    }\n"
            "    if (address.indexOf(\"0x\") !== 0) address = \"0x\" + address\n"
            "    var target = \"window = \\\"address:\" + address + \"\\\"\"\n"
            "    if (window.minimized) {\n"
            "      var monitor = Hyprland.focusedMonitor\n"
            "      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1\n"
            "      if (!(workspace >= 1)) return\n"
            "      // A restored window is simply there again, without animating in.\n"
            "      Hyprland.dispatch(\"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"1\\\", \" + target + \" })\")\n"
            "      Hyprland.dispatch(\"hl.dsp.window.move({ workspace = \\\"\" + workspace + \"\\\", \" + target + \" })\")\n"
            "      scheduleNoAnimUnset(address)\n"
            "    }\n"
            "    Hyprland.dispatch(\"hl.dsp.focus({ \" + target + \" })\")\n"
            "    Hyprland.dispatch(\"hl.dsp.window.alter_zorder({ mode = \\\"top\\\", \" + target + \" })\")\n"
            "  }"
        )
        if _dock.count(_old_bf) != 1:
            print("ERROR: pin-era bringForward anchor not found exactly once in %s (count %d)" % (_dock_rel, _dock.count(_old_bf)), file=sys.stderr)
            sys.exit(1)
        _dock = _dock.replace(_old_bf, _helper + _new_bf, 1)
        with open(_dock_fp, "w") as f:
            f.write(_dock)
        changed.append("Dock.qml: noAnim helper + in-process bringForward (fallback, patch 20 absent)")
    else:
        print("ERROR: Dock.qml is in an unexpected state (no noAnim helper, no pin-era bringForward) — refusing to rewrite bringForward and risk dropping #20344/#19970 deltas", file=sys.stderr)
        sys.exit(1)

for label in changed:
    print("patched: %s" % label)
print("snappier-shell-ui patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are QML, not bash, so bash -n would
# fail on them by construction and is deliberately not used here. qmllint
# cannot resolve the qs.* imports outside the running shell, so it is
# warning-only.
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/plugins/background/Background.qml shell/plugins/bar/widgets/Microphone.qml shell/plugins/bar/widgets/Tray.qml shell/plugins/bar/widgets/Workspaces.qml shell/plugins/menu/BarWidget.qml shell/plugins/panels/audio/Panel.qml shell/plugins/panels/power/Panel.qml shell/plugins/services/media/Service.qml shell/plugins/dock/Dock.qml; do
    qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (warning-only)"
  done
else
  warn "qmllint not found, skipping QML syntax checks"
fi
info "  snappier-shell-ui: in-process shell.toggle / Hyprland.dispatch, faster tray, bluez sinks (#20126)"
