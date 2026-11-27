#!/usr/bin/env bash
# Hexciri fork patch 18: fullscreen options in the Screenrecord menu.
# Forward-port of omarchy PR #20303 ("fullscreen options in the Screenrecord
# menu") into the fork's menu data.
#
# What it does (PR behavior, unchanged): the Screenrecord submenu gains two
# rows that skip the region picker and record the monitor you are on, whole,
# bar included: "Full screen with no audio" and "Full screen with desktop
# audio". The four existing region-picker rows (no audio, desktop audio,
# desktop + microphone, desktop + microphone + webcam) are untouched.
#
# Fork adaptation: upstream default/omarchy/omarchy-menu.jsonc is
# default/hexciri/hexciri-menu.jsonc in the fork, and the actions become
# hexciri-capture-screenrecording --fullscreen (and --fullscreen
# --with-desktop-audio). Labels go in default/i18n/en/menu.json, same path
# in the fork. No bin/ change: --fullscreen already exists in
# bin/hexciri-capture-screenrecording (FULLSCREEN flag, honored where the
# capture target is chosen). No new aliases: upstream AGENTS.md reserves
# aliases for established alternate names, and the PR adds none. No QML
# change: Menu.qml already sizes the trigger.capture.screenrecord card at
# 520, and the PR adds flat rows, it does not restructure the submenu.
# The PR also touches manual/12-screenshots-recording.md; that is repo
# documentation, not part of the installed fork tree, so this patch does
# not edit it (same category as test/ in patch 14).
#
# Icon note: the PR's fullscreen rows use the monitor glyph. Its codepoint
# is U+F0379 (mdi-monitor), the same icon the existing mirror-display rows
# in this file already use; the patch builds it with chr(0xF0379) so the
# source carries no raw private-use glyph.
#
# Diff source: anonymous clone of omacom/omarchy succeeded, but fetching
# the PR head tripped an execution-risk check and stalled, so the verified
# source is the .diff fetched with browser.open from
# https://github.com/omacom/omarchy/pull/20303.diff (three files, two
# data hunks plus the manual sentence; the port covers the two data hunks).
#
# Standalone: bash v2/patches/18-screenrecord-fullscreen.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Validation: the edited files are JSON/JSONC data, not code, so the
# end-of-patch check parses them (the jsonc check mirrors patch 02: the
# shell's stripJsonc rules, then JSON parse, then the 9 named root
# entries must still be present) and asserts the two new rows carry
# exactly icon + label + action, the hexciri action, and no aliases.
# bash -n on this patch script itself is a manual pre-flight check, not
# a runtime step: the patch edits data files, never shell code.
set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "18-screenrecord-fullscreen.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Fullscreen screenrecord rows, omarchy PR #20303 (2026-11-26) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import json
import sys

root = sys.argv[1]
changed = []

ICON_CAM = chr(0xF03D)    # video camera, the existing screenrecord rows
ICON_FS = chr(0xF0379)    # monitor (mdi-monitor), as the mirror-display rows

MENU = "default/hexciri/hexciri-menu.jsonc"
I18N = "default/i18n/en/menu.json"

# Rows are built by concatenation (no escapes in this file): the anchor is
# the existing webcam row, fork-renamed; the new rows sit directly after
# it, before trigger.transcode, exactly where the PR puts them upstream.
menu_anchor = '  "trigger.capture.screenrecord.webcam": {"icon":"' + ICON_CAM + '","label":"With desktop + microphone audio + webcam","when":"hexciri-hw-webcam","action":"hexciri-capture-screenrecording-with-webcam"},'
menu_row1 = '  "trigger.capture.screenrecord.fullscreen-no-audio": {"icon":"' + ICON_FS + '","label":"Full screen with no audio","action":"hexciri-capture-screenrecording --fullscreen"},'
menu_row2 = '  "trigger.capture.screenrecord.fullscreen-desktop-audio": {"icon":"' + ICON_FS + '","label":"Full screen with desktop audio","action":"hexciri-capture-screenrecording --fullscreen --with-desktop-audio"},'
i18n_anchor = chr(10).join([
    '  "trigger.capture.screenrecord.webcam": {',
    '    "label": "With desktop + microphone audio + webcam"',
    '  },',
])
i18n_new = i18n_anchor + chr(10) + chr(10).join([
    '  "trigger.capture.screenrecord.fullscreen-no-audio": {',
    '    "label": "Full screen with no audio"',
    '  },',
    '  "trigger.capture.screenrecord.fullscreen-desktop-audio": {',
    '    "label": "Full screen with desktop audio"',
    '  },',
])

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    (MENU, menu_anchor, menu_anchor + chr(10) + menu_row1 + chr(10) + menu_row2,
     "menu: fullscreen screenrecord rows"),
    (I18N, i18n_anchor, i18n_new,
     "i18n: fullscreen screenrecord labels"),
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


def strip_jsonc(text):
    # MenuModel.js stripJsonc, without regex (this file carries no escapes):
    # drop full-line // comments, drop commas that only whitespace
    # separates from a closing } or ]. String-aware, so // and commas
    # inside quoted values are untouched.
    kept = [ln for ln in text.splitlines() if not ln.strip().startswith("//")]
    s = chr(10).join(kept)
    out = []
    i = 0
    in_str = False
    esc = False
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == chr(92):
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == ',':
            j = i + 1
            while j < len(s) and s[j].isspace():
                j += 1
            if j < len(s) and s[j] in "}]":
                i += 1
                continue
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


# The forked menu jsonc must still parse exactly like the shell parses it
# (patch 02): ONE bad row makes the WHOLE file unparseable and the menu
# opens empty. Same 9 named root entries, plus the two new rows with
# exactly icon + label + action, the hexciri action, and no aliases.
menu_fp = root + "/" + MENU
try:
    with open(menu_fp) as f:
        menu_raw = f.read()
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping menu validation" % MENU)
    menu_raw = None
if menu_raw is not None:
    try:
        menu_parsed = json.loads(strip_jsonc(menu_raw))
    except Exception as e:
        _die("menu jsonc does not parse, shell would show an empty menu: %s" % e)
    for r in ("apps", "appearance", "trigger", "setup", "install", "remove", "update", "learn", "system"):
        if r not in menu_parsed:
            _die("menu jsonc missing root entry %s, shell would show an empty menu" % r)
    for key, label, action in (
        ("trigger.capture.screenrecord.fullscreen-no-audio", "Full screen with no audio",
         "hexciri-capture-screenrecording --fullscreen"),
        ("trigger.capture.screenrecord.fullscreen-desktop-audio", "Full screen with desktop audio",
         "hexciri-capture-screenrecording --fullscreen --with-desktop-audio"),
    ):
        row = menu_parsed.get(key)
        if row is None:
            _die("menu jsonc missing new row %s" % key)
        if set(row.keys()) != {"icon", "label", "action"}:
            _die("menu row %s has unexpected keys %s (want exactly icon, label, action)" % (key, sorted(row.keys())))
        if row["icon"] != ICON_FS:
            _die("menu row %s has the wrong icon" % key)
        if row["label"] != label:
            _die("menu row %s has the wrong label" % key)
        if row["action"] != action:
            _die("menu row %s has the wrong action" % key)
    print("menu jsonc parses (%d entries, 9 root entries)" % len(menu_parsed))

# The i18n catalog is strict JSON: it must parse, and both new keys must
# carry exactly the PR's labels.
i18n_fp = root + "/" + I18N
try:
    with open(i18n_fp) as f:
        i18n_parsed = json.load(f)
except FileNotFoundError:
    print("WARN: %s not in fork output, skipping i18n validation" % I18N)
    i18n_parsed = None
if i18n_parsed is not None:
    for key, label in (
        ("trigger.capture.screenrecord.fullscreen-no-audio", "Full screen with no audio"),
        ("trigger.capture.screenrecord.fullscreen-desktop-audio", "Full screen with desktop audio"),
    ):
        entry = i18n_parsed.get(key)
        if entry is None or entry.get("label") != label:
            _die("i18n label missing or wrong for %s" % key)
    print("i18n menu.json parses (%d entries)" % len(i18n_parsed))

for c in changed:
    print("patched: " + c)
print("screenrecord-fullscreen patch: %d file edits applied" % len(changed))
PY

info "  screenrecord-fullscreen: Screenrecord menu now offers full-screen recording (PR #20303)"
