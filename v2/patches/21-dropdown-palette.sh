#!/usr/bin/env bash
# Hexciri fork patch 21: reset partial shell palettes on reload and select
# clicked dropdown rows.
# Forward-port of omarchy PR #20353 (ryanrhughes,
# "Reset partial shell palettes on reload and select clicked dropdown rows")
# into shell/Commons/Color.qml, shell/Ui/Dropdown.qml and
# shell/Ui/SearchableDropdown.qml. Diff fetched 2026-11-27 via the PR .diff
# (the anonymous git clone tripped an execution-risk check, so git work was
# stopped and browser.open on
# https://github.com/omacom/omarchy/pull/20353.diff was used instead).
# The PR title and both fixes were confirmed against that diff; it touches
# both dropdown files, not just one.
#
# What it does (PR behavior, unchanged):
# (a) Dropdown rows: a click currently relies on hover (onPositionChanged)
# to select the row before onClicked applies it, so an absolute pointer
# (pen tablet, VM tablet, remote desktop) that jumps and clicks in one
# event applies the wrong row. The fix sets currentIndex to the clicked
# row's index inside onClicked, before selectCurrent(), in both
# Dropdown.qml (optionList) and SearchableDropdown.qml (resultList).
# MultiSelect.qml toggles directly on click, so it is out of scope.
# (b) Palette: loadColors() used to leave any key a theme omits at its
# previous value, so a partial palette kept stale colors from the last
# theme. The fix collects every key from the file first, then resolves
# all six roles from that file alone: explicit foreground/background/
# accent win over their Base24 aliases (color7/color0/color4), red/color1
# and yellow/color3 feed urgent/warning, muted falls back to color8 then
# foreground, and anything still missing falls back to _paletteDefaults
# (the old hardcoded defaults, now named in one place).
#
# Fork adaptation: none needed in the touched lines. The PR's hunks contain
# no `omarchy` identifiers at all. The two `omarchy` strings elsewhere in
# Color.qml are NOT in the PR diff and are already handled by the fork
# step: fork-shell.sh's rename pass maps `/omarchy/current/theme` (line 17,
# context only for the palette hunk) and `~/.config/omarchy/shell.toml`
# (line 251, the user-override path) to their hexciri forms before any
# patch runs, so this patch deliberately does not touch them — an anchor
# on the omarchy spelling would die on a real FORK_OUT.
#
# Tests: upstream's test/shell.d/color-palette-test.sh (new) and the
# dropdown-test.sh / tst_dropdown.qml extensions are NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and no
# existing patch touches tests, so this patch does not edit a test file.
# Verification is sim-run diff proof plus a read of the patched
# click-select and palette-reset flow (see the README section in
# pr-batch-work for the results).
#
# Standalone: bash v2/patches/21-dropdown-palette.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are QML, not bash, so the
# end-of-patch check is qmllint when present (warning only: qmllint fails
# on missing Quickshell imports even for valid files). bash -n would fail
# on all three files by construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "21-dropdown-palette.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Dropdown click-select + palette reset, omarchy PR #20353 (2026-11-27) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The palette defaults, verbatim from the PR. The old hardcoded literals
# become one named dict so loadColors() can reset omitted keys to them.
# Note the `+ '"'` on OLD_PALETTE's last line: a raw triple-quoted string
# cannot end in a content `"`, the terminator would swallow it (and the
# leftover quote would corrupt the patched file), so the closing quote is
# concatenated. Do not "simplify" that line back to plain `"""`.
OLD_PALETTE = r"""  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  // A caution short of urgent: the theme's yellow.
  property color warning: "#c4a35a"
  property color muted: "#707880""" + '"'

NEW_PALETTE = r"""  readonly property var _paletteDefaults: ({
    foreground: "#cacccc",
    background: "#101315",
    accent: "#cacccc",
    urgent: "#a55555",
    warning: "#c4a35a",
    muted: "#707880"
  })

  property color foreground: _paletteDefaults.foreground
  property color background: _paletteDefaults.background
  property color accent: _paletteDefaults.accent
  property color urgent: _paletteDefaults.urgent
  // A caution short of urgent: the theme's yellow.
  property color warning: _paletteDefaults.warning
  property color muted: _paletteDefaults.muted"""

# loadColors(), verbatim from the PR: collect every key from the file into
# `named` first, then resolve all six roles from that file alone, so a
# missing key resets to its default instead of keeping the previous
# theme's color. Explicit keys beat Base24 aliases regardless of order.
OLD_LOADCOLORS = r"""  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var foundMuted = false
    var loadedForeground = false
    var loadedBackground = false
    var color0Value = ""
    var color4Value = ""
    var color7Value = ""
    var color8Value = ""
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") { foreground = match[2]; loadedForeground = true }
      else if (match[1] === "background") { background = match[2]; loadedBackground = true }
      // Prefer the explicit `accent` key; only fall back to color4 when the
      // theme doesn't define a separate accent. color4 appears later in the
      // file so the old single-property approach clobbered accent with it.
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "muted") { muted = match[2]; foundMuted = true }
      else if (match[1] === "color0") color0Value = match[2]
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "color7") color7Value = match[2]
      else if (match[1] === "color8") color8Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
      else if (match[1] === "yellow" || match[1] === "color3") warning = match[2]
    }
    if (!loadedBackground && color0Value.length > 0) background = color0Value
    if (!loadedForeground && color7Value.length > 0) foreground = color7Value
    if (!foundAccent && color4Value.length > 0) accent = color4Value
    if (!foundMuted) muted = color8Value.length > 0 ? color8Value : foreground
  }"""

NEW_LOADCOLORS = r"""  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var named = Object.create(null)
    var nextUrgent = _paletteDefaults.urgent
    var nextWarning = _paletteDefaults.warning
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      var key = match[1]
      var value = match[2]
      named[key] = value
      if (key === "red" || key === "color1") nextUrgent = value
      else if (key === "yellow" || key === "color3") nextWarning = value
    }
    // Resolve every stop from this file so a missing key cannot retain a color
    // from the previous theme. Explicit foreground, background, and accent
    // take precedence over their Base24 aliases.
    foreground = named.foreground || named.color7 || _paletteDefaults.foreground
    background = named.background || named.color0 || _paletteDefaults.background
    accent = named.accent || named.color4 || _paletteDefaults.accent
    urgent = nextUrgent
    warning = nextWarning
    muted = named.muted || named.color8 || foreground
  }"""

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    ("shell/Commons/Color.qml",
     OLD_PALETTE, NEW_PALETTE,
     "Color palette: name the defaults as _paletteDefaults (PR #20353)"),
    ("shell/Commons/Color.qml",
     OLD_LOADCOLORS, NEW_LOADCOLORS,
     "Color loadColors: resolve every role from this file, reset omitted keys (PR #20353)"),
    # Dropdown.qml: the row MouseArea's onClicked used to trust hover to
    # have set currentIndex. Select the clicked row first so a pointer
    # that jumps and clicks in one event applies the row under the click.
    ("shell/Ui/Dropdown.qml",
     "              onClicked: optionList.selectCurrent()",
     "              onClicked: {\n"
     "                optionList.currentIndex = parent.index\n"
     "                optionList.selectCurrent()\n"
     "              }",
     "Dropdown: select clicked row before applying it (PR #20353)"),
    # SearchableDropdown.qml: same fix on resultList.
    ("shell/Ui/SearchableDropdown.qml",
     "                  onClicked: resultList.selectCurrent()",
     "                  onClicked: {\n"
     "                    resultList.currentIndex = parent.index\n"
     "                    resultList.selectCurrent()\n"
     "                  }",
     "SearchableDropdown: select clicked row before applying it (PR #20353)"),
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
print("dropdown-palette patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are QML, not bash, so bash -n
# would fail on all three by construction and is deliberately not used here.
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/Commons/Color.qml shell/Ui/Dropdown.qml shell/Ui/SearchableDropdown.qml; do
    qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (missing Quickshell imports also trip it; see output above)"
  done
else
  warn "qmllint not found, skipping QML parse check"
fi
info "  dropdown-palette: clicked dropdown rows select themselves and partial palettes reset on reload (PR #20353)"
