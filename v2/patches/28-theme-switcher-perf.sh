#!/usr/bin/env bash
# Hexciri fork patch 28: theme switcher / icon-scan perf (upstream
# omacom/omarchy #20129, commit 4918a612d).
# - bin/hexciri-theme-set-icons: only bump the link-change field of
#   icons.revision when links actually changed; the file becomes two
#   tab-separated fields "<draw-rev>\t<links-rev>".
# - bin/hexciri-theme-switcher: find_preview via globs instead of find(1);
#   fast signature via one batched stat over the theme dirs; the slow
#   per-preview signature file is gone; preview rebuild iterates globs.
# - shell/services/AppLibrary.qml: icon scan dedups in awk (one winner per
#   basename, SVG before PNG, largest PNG per dir) instead of streaming
#   thousands of shadowed duplicates through sort into QML; the
#   icons.revision FileView parses the two-field revision and only
#   rescans the icon tree when the link-change field advances.
# - shell/services/BrightnessKeys.qml: max_brightness cached per device
#   (ensureMax), FileView read failures return NaN instead of a stale 0,
#   setProc no longer re-probes the device on every exit.
# - shell/services/PluginRegistry.qml: rescan() queues while a scan is
#   running (rescanQueued), no rescan/reaper restart while destroying,
#   ensureUserDir via mkdir argv, rescan on completed when firstPartyDir
#   is set.
# - shell/services/desktop-entries.sh: per-file bash parsing replaced by
#   one awk pass (BEGINFILE/ENDFILE, ids fed on fd 3).
# Ordered AFTER #19961 (patch 24, PluginRegistry) and #19968 (patch 26,
# AppLibrary): the AppLibrary icon-scan and icons.revision anchors below
# are against the POST-24/26 state (bash-array icon dirs, preload:false
# + reload() on the revision FileView). Apply 24, then 26, then this.
#
# Fork notes: rename map applied (HEXCIRI_THEMES_PATH, hexciri-hw-display,
# hexciri.osd, X-Hexciri-Dock-Click, ~/.local/state/hexciri/current).
# The upstream test-only change (test/shell.d/app-icon-scan-test.sh) is NOT
# ported: test/ is not in FORK_OUT. The awk rewrite in desktop-entries.sh
# needs gawk (BEGINFILE/ENDFILE, ERRNO, /dev/fd/3); Arch ships gawk as awk.
# Nyxiri check (2026-11-26): no Nyxiri source in this workspace parses
# icons.revision (workspace copies have no such reader; live-Nyxiri check
# unverified, no live checkout here). The two-field file keeps the draw
# revision first, so a first-field reader sees the same value as before.
#
# Standalone: bash v2/patches/28-theme-switcher-perf.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#   Pure removals live in REMOVALS, not REPLACEMENTS: a removal whose
#   "new" text is empty (or already present elsewhere) would make the
#   generic skip test think it is done and skip the deletion forever.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "28-theme-switcher-perf.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
    ('bin/hexciri-theme-set-icons',
     r'''run_batched ln -sfn -t "$LINKS" -- "${missing_links[@]}"
''',
     r'''links_changed=0

if (( ${#missing_links[@]} > 0 )); then
  run_batched ln -sfn -t "$LINKS" -- "${missing_links[@]}"
  links_changed=1
fi
''',
     'theme-set-icons: only link when links are missing'),
    ('bin/hexciri-theme-set-icons',
     r'''  [[ -L $link && $(readlink "$link") == "$icon" ]] && rm "$link"
''',
     r'''  if [[ -L $link && $(readlink "$link") == "$icon" ]]; then
    rm "$link"
    links_changed=1
  fi
''',
     'theme-set-icons: stale-link removal marks links changed'),
    ('bin/hexciri-theme-set-icons',
     r'''printf '%s\n' "${EPOCHREALTIME//[!0-9]/}" >"$CURRENT/icons.revision"''',
     r'''draw_rev=${EPOCHREALTIME//[!0-9]/}
links_rev=0

if [[ -r $CURRENT/icons.revision ]]; then
  IFS=$'\t ' read -r _ prev_links_rev _ <"$CURRENT/icons.revision" || true
  [[ $prev_links_rev =~ ^[0-9]+$ ]] && links_rev=$prev_links_rev
fi

if (( links_changed )); then
  links_rev=$draw_rev
fi

printf '%s\t%s\n' "$draw_rev" "$links_rev" >"$CURRENT/icons.revision"''',
     'theme-set-icons: two-field icons.revision (draw rev, links rev)'),
    ('bin/hexciri-theme-switcher',
     r'''find_preview() {
  local theme_path="$1"
  local preview preview_name

  for preview_name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp preview.mp4 preview.m4v preview.mov preview.webm preview.mkv preview.avi; do
    preview=$(find -L "$theme_path" -maxdepth 1 -type f -iname "$preview_name" -print -quit 2>/dev/null)

    if [[ -n $preview ]]; then
      printf '%s\n' "$preview"
      return
    fi
  done

  if [[ -d $theme_path/backgrounds ]]; then
    find -L "$theme_path/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \
         -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
      -print 2>/dev/null | sort | head -n 1
  fi
}
''',
     r'''find_preview() {
  local theme_path="$1"
  local ext match best=""

  local -a matches=()

  shopt -s nullglob nocaseglob

  for ext in png jpg jpeg webp gif bmp mp4 m4v mov webm mkv avi; do
    matches=("$theme_path/"[p]review."$ext")

    for match in "${matches[@]}"; do
      if [[ -f $match ]]; then
        shopt -u nocaseglob

        printf '%s\n' "$match"
        return
      fi
    done
  done

  if [[ -d $theme_path/backgrounds ]]; then
    for ext in jpg jpeg png gif bmp webp mp4 m4v mov webm mkv avi; do
      for match in "$theme_path/backgrounds"/*."$ext"; do
        [[ -f $match ]] || continue

        if [[ -z $best || $match < $best ]]; then
          best="$match"
        fi
      done
    done
  fi

  shopt -u nocaseglob

  [[ -n $best ]] && printf '%s\n' "$best"
}
''',
     'theme-switcher: find_preview via globs, no find(1)'),
    ('bin/hexciri-theme-switcher',
     r'''fast_signature="v2"$'\n'
for theme_dir in "$USER_THEMES_PATH" "$HEXCIRI_THEMES_PATH"; do
  if [[ -d $theme_dir ]]; then
    fast_signature+="$theme_dir:$(stat -Lc '%Y' "$theme_dir")"$'\n'

    while IFS= read -r -d '' theme_path; do
      fast_signature+="$theme_path:$(stat -Lc '%Y' "$theme_path")"$'\n'
    done < <(find -L "$theme_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null | sort -z)
  fi
done

if [[ ! -f $fast_signature_file ]] || ! cmp -s "$fast_signature_file" <(printf '%s' "$fast_signature"); then
  theme_signature=""
  for theme_dir in "$USER_THEMES_PATH" "$HEXCIRI_THEMES_PATH"; do
    if [[ -d $theme_dir ]]; then
      theme_signature+="$theme_dir:$(stat -Lc '%Y' "$theme_dir")"$'\n'

      while IFS= read -r -d '' theme_path; do
        preview=$(find_preview "$theme_path")
        theme_signature+="$theme_path:$(stat -Lc '%Y' "$theme_path")"$'\n'

        if [[ -n $preview ]]; then
          theme_signature+="$preview:$(stat -Lc '%s:%Y' "$preview")"$'\n'
        fi
      done < <(find -L "$theme_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null | sort -z)
    fi
  done
fi

if [[ ! -f $fast_signature_file ]] || ! cmp -s "$fast_signature_file" <(printf '%s' "$fast_signature"); then
  rm -rf "$preview_dir"
  mkdir -p "$preview_dir"

  while IFS= read -r theme_path; do
    theme_name=${theme_path##*/}
    preview=$(find_preview "$theme_path")

    if [[ -z $preview ]]; then
      preview=$(find_preview "$HEXCIRI_THEMES_PATH/$theme_name")
    fi

    add_theme_preview "$theme_name" "$preview"
  done < <(find -L "$USER_THEMES_PATH" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print 2>/dev/null | sort)

  while IFS= read -r theme_path; do
    theme_name=${theme_path##*/}
    preview=$(find_preview "$theme_path")
    add_theme_preview "$theme_name" "$preview"
  done < <(find -L "$HEXCIRI_THEMES_PATH" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)

  printf '%s' "$theme_signature" >"$signature_file"
  printf '%s' "$fast_signature" >"$fast_signature_file"
fi
''',
     r'''shopt -s nullglob

sig_dirs=()

for theme_dir in "$USER_THEMES_PATH" "$HEXCIRI_THEMES_PATH"; do
  if [[ -d $theme_dir ]]; then
    sig_dirs+=("$theme_dir")

    for theme_path in "$theme_dir"/*; do
      if [[ -d $theme_path || -L $theme_path ]]; then
        sig_dirs+=("$theme_path")
      fi
    done
  fi
done

fast_signature="v2"$'\n'

if (( ${#sig_dirs[@]} > 0 )); then
  fast_signature+="$(stat -Lc '%n:%Y' "${sig_dirs[@]}" 2>/dev/null)"$'\n'
fi

if [[ ! -f $fast_signature_file ]] || ! cmp -s "$fast_signature_file" <(printf '%s' "$fast_signature"); then
  rm -rf "$preview_dir"
  mkdir -p "$preview_dir"

  if [[ -d $USER_THEMES_PATH ]]; then
    for theme_path in "$USER_THEMES_PATH"/*; do
      [[ -d $theme_path || -L $theme_path ]] || continue

      theme_name=${theme_path##*/}
      preview=$(find_preview "$theme_path")

      if [[ -z $preview ]]; then
        preview=$(find_preview "$HEXCIRI_THEMES_PATH/$theme_name")
      fi

      add_theme_preview "$theme_name" "$preview"
    done
  fi

  if [[ -d $HEXCIRI_THEMES_PATH ]]; then
    for theme_path in "$HEXCIRI_THEMES_PATH"/*; do
      [[ -d $theme_path ]] || continue

      theme_name=${theme_path##*/}
      preview=$(find_preview "$theme_path")

      add_theme_preview "$theme_name" "$preview"
    done
  fi

  printf '%s' "$fast_signature" >"$fast_signature_file"
fi
''',
     'theme-switcher: batched stat signature, glob preview rebuild, no slow signature'),
    ('shell/services/AppLibrary.qml',
     r'''  property int themeRevision: 0

  // Maps a desktop id to the version of the package that owns it. Rescanned
''',
     r'''  property int themeRevision: 0
  property string lastLinksRevision: ""
  property bool iconsRevisionInitialized: false

  // Maps a desktop id to the version of the package that owns it. Rescanned
''',
     'AppLibrary: lastLinksRevision + iconsRevisionInitialized'),
    ('shell/services/AppLibrary.qml',
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
  }
''',
     r'''  function iconIndexScanCommand() {
    // List one winning app/device icon per basename across the XDG icon dirs
    // and /usr/share/pixmaps as "<path>" lines. Some desktop entries, such as
    // Print Settings, use device icons like "printer" instead of app icons.
    // Deduplicating in awk keeps SVG ahead of PNG, preserves XDG directory
    // precedence, picks the largest PNG size within a directory, and avoids
    // streaming thousands of shadowed duplicates into QML.
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
      '} | awk \'',
      '!length { dir++; next }',
      '{',
      '  name = $0; sub(/^.*\\//, "", name); sub(/\\.[^.]+$/, "", name);',
      '  if (!length(name)) next;',
      '  is_png = !/\\.svg$/;',
      '  sz = is_png && match($0, /\\/[0-9]+x[0-9]+[@\\/]/) ? substr($0, RSTART + 1) + 0 : 0;',
      '  if (!(name in best)) {',
      '    order[++count] = name;',
      '    best[name] = $0; best_png[name] = is_png; best_dir[name] = dir; best_sz[name] = sz;',
      '  } else if (!is_png) {',
      '    if (best_png[name]) { best[name] = $0; best_png[name] = 0; best_dir[name] = dir; best_sz[name] = 0 }',
      '  } else if (best_png[name] && (dir < best_dir[name] || (dir == best_dir[name] && sz > best_sz[name]))) {',
      '    best[name] = $0; best_dir[name] = dir; best_sz[name] = sz;',
      '  }',
      '}',
      'END {',
      '  for (i = 1; i <= count; i++) if (!best_png[order[i]]) print best[order[i]];',
      '  for (i = 1; i <= count; i++) if (best_png[order[i]]) print best[order[i]];',
      '}\''
    ].join(' ')
  }
''',
     'AppLibrary: icon scan dedups in awk, one winner per basename'),
    ('shell/services/AppLibrary.qml',
     r'''  FileView {
    path: root.home + "/.local/state/hexciri/current/icons.revision"
    watchChanges: true
    preload: false
    printErrors: false
    onFileChanged: {
      reload()
      root.themeRevision++
      root.refreshIcons()
    }
  }
''',
     r'''  FileView {
    path: root.home + "/.local/state/hexciri/current/icons.revision"
    watchChanges: true
    preload: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: root.iconsRevisionInitialized = true
    onLoaded: {
      var parts = String(text() || "").trim().split(/\s+/)
      var linksRev = parts.length >= 2 ? parts[1] : ""
      if (!root.iconsRevisionInitialized) {
        root.iconsRevisionInitialized = true
        root.lastLinksRevision = linksRev
        return
      }
      root.themeRevision++
      // Theme switches redraw existing icon files in place; only rescan the
      // icon tree when the link-change revision advances (or if an older writer
      // omitted it, or the index has not been populated yet).
      if (linksRev === "" || linksRev !== root.lastLinksRevision || Object.keys(root.iconIndex).length === 0) {
        root.lastLinksRevision = linksRev
        root.refreshIcons()
      }
    }
  }
''',
     'AppLibrary: two-field icons.revision, rescan only on link change'),
    ('shell/services/BrightnessKeys.qml',
     r'''  // The backlight hexciri-hw-display picks. Devices do not come and go at
  // runtime, but each press refreshes it for the next.
  property string device: ""
  readonly property string devicePath: device ? "/sys/class/backlight/" + device : ""
''',
     r'''  // The backlight hexciri-hw-display picks. Devices do not come and go at
  // runtime, so maxBrightness is cached per device and hexciri-hw-display is
  // only re-probed if reading the sysfs files fails.
  property string device: ""

  property int maxBrightness: 0
  readonly property string devicePath: device ? "/sys/class/backlight/" + device : ""

  onDeviceChanged: maxBrightness = 0

  function ensureMax() {
    if (root.maxBrightness > 0) return root.maxBrightness
    var max = readNumber(maxFile)
    if (max > 0) root.maxBrightness = max
    return root.maxBrightness
  }
''',
     'BrightnessKeys: maxBrightness cache + ensureMax()'),
    ('shell/services/BrightnessKeys.qml',
     r'''    var max = readNumber(maxFile)
    if (!(max > 0)) return false
    var current = Math.round(100 * readNumber(brightnessFile) / max)
''',
     r'''    var max = ensureMax()
    if (!(max > 0)) {
      if (!deviceProc.running) deviceProc.running = true
      return false
    }
    var level = readNumber(brightnessFile)
    if (!(level >= 0)) {
      root.maxBrightness = 0
      if (!deviceProc.running) deviceProc.running = true
      return false
    }
    var current = Math.round(100 * level / max)
''',
     'BrightnessKeys: handle() uses cached max, re-probes only on failure'),
    ('shell/services/BrightnessKeys.qml',
     r'''  function readNumber(file) {
    file.reload()
    file.waitForJob()
    return Number(String(file.text() || "").trim())
  }
''',
     r'''  function readNumber(file) {
    file.failed = false
    file.reload()
    file.waitForJob()
    if (file.failed) return NaN
    var raw = String(file.text() || "").trim()
    if (!raw) return NaN
    return Number(raw)
  }
''',
     'BrightnessKeys: readNumber returns NaN on missing/empty read'),
    ('shell/services/BrightnessKeys.qml',
     r'''  function showOsd() {
    var max = readNumber(maxFile)
    if (!host || !(max > 0)) return
    var percent = Math.round(100 * readNumber(brightnessFile) / max)
''',
     r'''  function showOsd() {
    var max = ensureMax()
    if (!host || !(max > 0)) return
    var level = readNumber(brightnessFile)
    if (!(level >= 0)) return
    var percent = Math.round(100 * level / max)
''',
     'BrightnessKeys: showOsd() uses cached max'),
    ('shell/services/BrightnessKeys.qml',
     r'''  FileView {
    id: brightnessFile
    path: root.devicePath ? root.devicePath + "/brightness" : ""
    blockLoading: true
    printErrors: false
  }
''',
     r'''  FileView {
    id: brightnessFile
    property bool failed: false
    path: root.devicePath ? root.devicePath + "/brightness" : ""
    blockLoading: true
    printErrors: false
    onLoadFailed: failed = true
  }
''',
     'BrightnessKeys: brightnessFile tracks load failure'),
    ('shell/services/BrightnessKeys.qml',
     r'''  FileView {
    id: maxFile
    path: root.devicePath ? root.devicePath + "/max_brightness" : ""
    blockLoading: true
    printErrors: false
  }
''',
     r'''  FileView {
    id: maxFile
    property bool failed: false
    path: root.devicePath ? root.devicePath + "/max_brightness" : ""
    blockLoading: true
    printErrors: false
    onLoadFailed: failed = true
  }
''',
     'BrightnessKeys: maxFile tracks load failure'),
    ('shell/services/BrightnessKeys.qml',
     r'''  Process {
    id: setProc
    onExited: {
      root.showOsd()
      if (!deviceProc.running) deviceProc.running = true
    }
  }
''',
     r'''  Process {
    id: setProc
    onExited: root.showOsd()
  }
''',
     'BrightnessKeys: setProc exit no longer re-probes device'),
    ('shell/services/PluginRegistry.qml',
     r'''  property bool scanning: false
  property string lastEnableError: ""
''',
     r'''  property bool scanning: false
  property bool rescanQueued: false
  property bool destroying: false
  property string lastEnableError: ""
''',
     'PluginRegistry: rescanQueued + destroying flags'),
    ('shell/services/PluginRegistry.qml',
     r'''    onExited: function(exitCode) {
      var output = scanStdout.text || ""
      registry.parseScanOutput(output)
    }
''',
     r'''    onExited: function(exitCode) {
      var output = scanStdout.text || ""
      registry.parseScanOutput(output)
      if (registry.rescanQueued && !registry.destroying) {
        registry.rescanQueued = false
        registry.rescan()
      }
    }
''',
     'PluginRegistry: queued rescan runs after scan exits'),
    ('shell/services/PluginRegistry.qml',
     r'''  property Process watcherReaper: Process {
    onExited: {
      localPluginWatcher.running = true
      registry.rescan()
    }
  }
''',
     r'''  property Process watcherReaper: Process {
    onExited: {
      if (registry.destroying) return
      localPluginWatcher.running = true
      registry.rescan()
    }
  }
''',
     'PluginRegistry: watcher reaper stops while destroying'),
    ('shell/services/PluginRegistry.qml',
     r'''  Component.onDestruction: {
    localPluginWatcherRestart.stop()
    localPluginWatcher.running = false
  }
''',
     r'''  Component.onDestruction: {
    destroying = true
    localPluginWatcherRestart.stop()
    localPluginWatcher.running = false
  }
''',
     'PluginRegistry: mark destroying on teardown'),
    ('shell/services/PluginRegistry.qml',
     r'''    onExited: localPluginWatcherRestart.restart()
''',
     r'''    onExited: {
      if (!registry.destroying) localPluginWatcherRestart.restart()
    }
''',
     'PluginRegistry: watcher restart stops while destroying'),
    ('shell/services/PluginRegistry.qml',
     r'''  function rescan() {
    if (scanning) return
    scanning = true
''',
     r'''  function rescan() {
    if (scanning) {
      registry.rescanQueued = true
      return
    }
    scanning = true
    registry.rescanQueued = false
''',
     'PluginRegistry: rescan() queues while a scan runs'),
    ('shell/services/PluginRegistry.qml',
     r'''  function ensureUserDir() {
    initProcess.command = ["bash", "-c", "mkdir -p \"$0\"", registry.pluginsDir]
    initProcess.running = true
  }
''',
     r'''  function ensureUserDir() {
    initProcess.command = ["mkdir", "-p", registry.pluginsDir]
    initProcess.running = true
  }
''',
     'PluginRegistry: ensureUserDir via mkdir argv, no bash -c'),
    ('shell/services/PluginRegistry.qml',
     r'''  Component.onCompleted: ensureUserDir()
''',
     r'''  Component.onCompleted: {
    if (firstPartyDir) rescan()
    ensureUserDir()
  }
''',
     'PluginRegistry: rescan on completed when firstPartyDir is set'),
    ('shell/services/desktop-entries.sh',
     r'''declare -A seen_ids
''',
     r'''declare -A seen_ids=()

files=()

ids=()
''',
     'desktop-entries: collect file/id lists instead of scanning inline'),
    ('shell/services/desktop-entries.sh',
     r'''scan_dir() {
  local dir=$1
  local file id

  [[ -d $dir ]] || return

  while IFS= read -r -d '' file; do
    id=${file#"$dir"/}
    id=${id%.desktop}
    id=${id//\//-}
    [[ -n ${seen_ids[$id]+set} ]] && continue
    seen_ids[$id]=1

    read_desktop_file "$file"
    if [[ $hidden == "true" ]]; then
      printf 'hidden\t%s\n' "$id"
    fi
    if [[ -n $dock_click ]]; then
      printf 'dock-click\t%s\t%s\n' "$dock_click" "$id"
    fi
  done < <(find "$dir" -type f -name '*.desktop' -print0 2>/dev/null | sort -z)
}
''',
     r'''collect_dir() {
  local dir=$1
  local file id

  [[ -d $dir ]] || return 0

  while IFS= read -r -d '' file; do
    id=${file#"$dir"/}
    id=${id%.desktop}
    id=${id//\//-}
    [[ -n ${seen_ids[$id]+set} ]] && continue
    seen_ids[$id]=1

    files+=("$file")

    ids+=("$id")

  done < <(find "$dir" -type f -name '*.desktop' -print0 2>/dev/null | sort -z)
}
''',
     'desktop-entries: scan_dir becomes collect_dir'),
    ('shell/services/desktop-entries.sh',
     r'''scan_dir "$HOME/.local/share/applications"

IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  scan_dir "$data_dir/applications"
done

scan_dir "$HOME/.nix-profile/share/applications"''',
     r'''collect_dir "$HOME/.local/share/applications"

IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  [[ -n $data_dir ]] && collect_dir "$data_dir/applications"
done

collect_dir "$HOME/.nix-profile/share/applications"

(( ${#files[@]} > 0 )) || exit 0

awk -v desktop_names="$desktop_names" '

  BEGIN {
    n = split(desktop_names, parts, ":")
    for (i = 1; i <= n; i++) {
      if (parts[i] != "") desktops[parts[i]] = 1
    }
  }

  function desktop_matches(list,    m, entries, i) {
    m = split(list, entries, ";")
    for (i = 1; i <= m; i++) {
      if (entries[i] != "" && (entries[i] in desktops)) return 1
    }
    return 0
  }

  BEGINFILE {
    if ((getline id < "/dev/fd/3") <= 0) id = ""
    in_desktop_entry = 0
    hidden = 0
    only_show_in = ""
    not_show_in = ""
    dock_click = ""
    if (ERRNO != "") nextfile
  }

  {
    sub(/\r$/, "")
    if ($0 ~ /^\[.*\]$/) {
      in_desktop_entry = ($0 == "[Desktop Entry]")
      next
    }
    if (!in_desktop_entry) next
    eq = index($0, "=")
    if (eq == 0) next

    key = substr($0, 1, eq - 1)
    value = substr($0, eq + 1)

    if ((key == "Hidden" || key == "NoDisplay") && value == "true") {
      hidden = 1
    } else if (key == "OnlyShowIn") {
      only_show_in = value
    } else if (key == "NotShowIn") {
      not_show_in = value
    } else if (key == "X-Hexciri-Dock-Click") {
      dock_click = value
    }
  }

  ENDFILE {
    if (id != "") {
      if (only_show_in != "" && !desktop_matches(only_show_in)) hidden = 1
      if (not_show_in != "" && desktop_matches(not_show_in)) hidden = 1
      if (hidden) printf "hidden\t%s\n", id
      if (dock_click != "") printf "dock-click\t%s\t%s\n", dock_click, id
    }
  }

' "${files[@]}" 3< <(printf '%s\n' "${ids[@]}")''',
     'desktop-entries: one awk pass over collected files'),
]

# Pure removals: (file, old, label). Skip test is "old absent", NOT
# "new present" — these delete text outright, so the generic
# REPLACEMENTS skip test would see nothing new and skip forever.
REMOVALS = [
    ('bin/hexciri-theme-switcher',
     r'''signature_file="$CACHE_PATH/signature"
''',
     'theme-switcher: drop the slow signature file (only fast-signature remains)'),
    ('shell/services/desktop-entries.sh',
     r'''desktop_matches() {
  local list=$1
  local desktop_name
  local entry

  IFS=":" read -ra desktop_parts <<< "$desktop_names"
  IFS=";" read -ra entries <<< "$list"

  for desktop_name in "${desktop_parts[@]}"; do
    [[ -z $desktop_name ]] && continue

    for entry in "${entries[@]}"; do
      [[ -z $entry ]] && continue
      [[ $entry == "$desktop_name" ]] && return 0
    done
  done

  return 1
}

''',
     'desktop-entries: drop bash desktop_matches (awk has its own)'),
    ('shell/services/desktop-entries.sh',
     r'''# Sets hidden and dock_click for one file.
read_desktop_file() {
  local file=$1
  local in_desktop_entry=0
  local only_show_in=
  local not_show_in=
  local line key value
  hidden=false
  dock_click=

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}

    if [[ $line =~ ^\[(.*)\]$ ]]; then
      [[ ${BASH_REMATCH[1]} == "Desktop Entry" ]] && in_desktop_entry=1 || in_desktop_entry=0
      continue
    fi

    (( in_desktop_entry )) || continue
    [[ $line == *=* ]] || continue

    key=${line%%=*}
    value=${line#*=}

    case $key in
      Hidden|NoDisplay)
        [[ $value == "true" ]] && hidden=true
        ;;
      OnlyShowIn)
        only_show_in=$value
        ;;
      NotShowIn)
        not_show_in=$value
        ;;
      X-Hexciri-Dock-Click)
        dock_click=$value
        ;;
    esac
  done < "$file"

  [[ -n $only_show_in ]] && ! desktop_matches "$only_show_in" && hidden=true
  [[ -n $not_show_in ]] && desktop_matches "$not_show_in" && hidden=true
  return 0
}

''',
     'desktop-entries: drop bash read_desktop_file (awk parses now)'),
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

for rel, old, label in REMOVALS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if old not in s:
        print("%s: already absent, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: removal anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, "", 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

for label in changed:
    print("patched: %s" % label)
print("28 patch: %d file edits applied" % len(changed))
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
for _f in bin/hexciri-theme-set-icons bin/hexciri-theme-switcher shell/services/desktop-entries.sh; do
  if [ -f "$FORK_OUT/$_f" ]; then
    bash -n "$FORK_OUT/$_f" || die "bash -n failed on patched $_f"
  fi
done
unset _f
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/services/AppLibrary.qml shell/services/BrightnessKeys.qml shell/services/PluginRegistry.qml; do
    if [ -f "$FORK_OUT/$_f" ]; then
      qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (warning only)"
    fi
  done
  unset _f
else
  warn "qmllint not found; QML syntax not checked here"
fi
info "  theme-switcher-perf: icon scan dedups in awk, two-field icons.revision, batched theme signature, cached max brightness, queued plugin rescans"
