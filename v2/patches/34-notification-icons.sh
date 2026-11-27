#!/usr/bin/env bash
# Hexciri fork patch 34: notification icons resolve through the app index.
# Forward-port of omarchy PR #20038 (commit a19d38d0a,
# "Notification icons resolve through the app index") into
# shell/plugins/notifications/Icons.js, shell/plugins/notifications/Toast.qml
# and docs/notifications.md.
#
# What it does (PR behavior, unchanged): when Qt's themed icon lookup
# misses a name, a notification card now falls back to the app library's
# file index (refreshed on desktop-entry changes), so newly installed app
# icons appear without a shell restart, including names whose earlier
# lookup failed. The index is checked only when the active theme misses;
# a missing name still falls through to the glyph or letter. The
# `firstOf(want.themed, ...)` lookup in Toast.qml now goes through the
# same entryIcon() fallback instead of calling Quickshell.iconPath
# directly, so themed candidates get the index fallback too.
#
# Fork adaptation: none in the code hunks (no `omarchy` strings in the
# changed lines). The landing files are the stock notification plugin,
# which the fork still ships: Nyxiri replaces the bar and the clock, not
# notifications. The prerequisite already exists at the pin:
# shell/services/AppLibrary.qml has `iconIndex` and `iconSource()`.
# The docs hunk anchors on the "4. The glyph ..." line and accepts both
# the upstream wording ("Omarchy sender") and the fork-renamed wording
# ("Hexciri sender"); docs/ may not be in FORK_OUT, in which case that
# hunk warns and skips like any other missing file.
#
# Tests: upstream's test/shell.d/notifications/logic.cjs is NOT in
# FORK_OUT (fork-shell.sh extracts only listed subsets; test/ is not
# one), and no existing patch touches tests, so this patch does not edit
# a test file. Verification is the upstream test's new entryIcon block
# replayed in sim (cached themed miss resolves via the index, active
# theme still wins, missing names keep the letter/glyph fallback,
# prototype-polluting names return "", absolute paths and "" unchanged,
# absent library / absent scene degrade to "") plus a diff of patched vs
# unpatched proving only the intended changes. See the coordinator's
# sim notes.
#
# Standalone: bash v2/patches/34-notification-icons.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are QML and QML-JS (Toast.qml,
# Icons.js). Icons.js is a QML library module: its `.pragma library` /
# `.import` lines are valid QML-JS but not valid plain JS, so node
# --check runs on a temp copy with those two lines stripped (the
# pristine file fails node --check the same way, by construction).
# qmllint runs on the QML file when present, warning only (it fails on
# missing Quickshell imports even for valid files). bash -n would fail
# on both by construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "34-notification-icons.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Notification icons via app index, omarchy PR #20038 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

DOCS_NEW = (
    "When Qt's themed lookup misses a name, the card also checks the app library's file index, which refreshes when desktop entries change. "
    "This picks up newly installed app icons without restarting the shell, including names whose earlier lookup failed. "
    "The index contains app and device icons across installed themes and `/usr/share/pixmaps`; it is checked only when the active theme misses. "
    "Copying an icon file alone does not trigger a rescan. A missing name still falls through to the glyph or letter.\n"
)

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run). A list of olds
# means: try each in order, first exact-once match wins (used for the
# docs anchor, whose sender name the rename map may have changed).
REPLACEMENTS = [
    # Icons.js: comment wording, "icon-theme names" -> "icon names".
    ("shell/plugins/notifications/Icons.js",
     "// site's names only as exact icon-theme names: a fuzzy desktop-entry match on",
     "// site's names only as exact icon names: a fuzzy desktop-entry match on",
     "Icons.js: comment wording (exact icon names)"),
    # Toast.qml: entryIcon() falls back to the app library's file index
    # when Qt's themed lookup misses.
    ("shell/plugins/notifications/Toast.qml",
     "        function entryIcon(icon) {\n"
     "          var value = String(icon || \"\")\n"
     "          return value.charAt(0) === \"/\" ? Util.fileUrl(value) : value ? Quickshell.iconPath(value, true) : \"\"\n"
     "        }",
     "        function entryIcon(icon) {\n"
     "          var value = String(icon || \"\")\n"
     "          if (value.charAt(0) === \"/\") return Util.fileUrl(value)\n"
     "          if (!value) return \"\"\n"
     "          var themed = Quickshell.iconPath(value, true)\n"
     "          if (themed) return themed\n"
     "          // Qt can keep missing an installed icon; the app library's index\n"
     "          // refreshes on app changes and keeps these icons available live.\n"
     "          var library = card.scene && card.scene.shell ? card.scene.shell.appLibrary : null\n"
     "          if (!library || !library.iconIndex || !Object.prototype.hasOwnProperty.call(library.iconIndex, value)) return \"\"\n"
     "          return library.iconSource(value)\n"
     "        }",
     "Toast.qml entryIcon(): fall back to the app library icon index"),
    # Toast.qml: themed candidates go through entryIcon() too.
    ("shell/plugins/notifications/Toast.qml",
     "            firstOf(want.themed, function(name) { return Quickshell.iconPath(name, true) }),",
     "            firstOf(want.themed, function(name) { return thumb.entryIcon(name) }),",
     "Toast.qml sources: themed candidates via entryIcon()"),
    # docs/notifications.md: document the index fallback. The rename map
    # may already have turned "Omarchy sender" into "Hexciri sender".
    ("docs/notifications.md",
     ["4. The glyph an Omarchy sender asked for, else the first letter of the source.\n",
      "4. The glyph an Hexciri sender asked for, else the first letter of the source.\n"],
     None,  # new text is built from the matched old below
     "docs/notifications.md: document the app-index fallback"),
]

for rel, old, new, label in REPLACEMENTS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if label.startswith("docs/") and DOCS_NEW.strip().split("\n")[0] in s:
        print("%s: already present, skipping" % label)
        continue
    if new is not None and new in s:
        print("%s: already present, skipping" % label)
        continue
    olds = old if isinstance(old, list) else [old]
    matched = None
    for cand in olds:
        if s.count(cand) == 1:
            matched = cand
            break
    if matched is None:
        print("ERROR: anchor not found exactly once in %s (counts %s): %s" % (rel, [s.count(c) for c in olds], label), file=sys.stderr)
        sys.exit(1)
    replacement = (matched + "\n" + DOCS_NEW) if new is None else new
    s = s.replace(matched, replacement, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

for label in changed:
    print("patched: %s" % label)
print("notification-icons patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. Icons.js is a QML-JS library module,
# so node --check runs on a temp copy with its `.pragma library` /
# `.import` lines stripped (valid QML-JS, invalid plain JS); Toast.qml
# is QML (qmllint when present, warning only). bash -n would fail on
# both by construction and is deliberately not used here.
_tmp_icons="$(mktemp --suffix=.js)"
trap 'rm -f "$_tmp_icons"' EXIT
sed '/^\.pragma/d;/^\.import/d' "$FORK_OUT/shell/plugins/notifications/Icons.js" > "$_tmp_icons"
node --check "$_tmp_icons" || die "node --check failed on patched Icons.js (QML pragma lines stripped)"
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/notifications/Toast.qml" || warn "qmllint reported issues on patched Toast.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping QML parse checks"
fi
info "  notification-icons: newly installed app icons appear without a shell restart (PR #20038)"
