#!/usr/bin/env bash
# Hexciri fork patch 61: show tooltips on bar indicator icons (upstream omacom/omarchy #19205).
#
# Upstream #19205 (verified against the live .diff, 2026-11-27): indicator
# tooltips never show, because the Indicators widget's hiddenBlockZone Item
# (the hover area that reveals the inactive icons) is a later sibling of the
# orientation trees, so it stacks ABOVE the icons and its HoverHandler eats
# the hover the icons' own MouseAreas need for WidgetButton.onEntered ->
# bar.showTooltip. The fix drops the zone below the icons (z: -1) and keeps
# the inactive block revealed per hovered icon instead of one shared bool,
# so moving from one icon to the next keeps the reveal, and removing a
# hovered active icon releases its hold (WidgetButton also releases the
# hold on destruction).
#
# Fork notes:
# - Pre-image is the live fork state, NOT the pin: WidgetButton already
#   carries patch 04 (pressed forwards click modifiers) and Indicators
#   already carries patch 23 (indicator-id validation) plus the
#   omarchy -> hexciri moduleName renames. The PR's WidgetButton hunk
#   context includes the onClicked line patch 04 changed, so a bare
#   `git apply` of the .diff onto the live files fails there; the derived
#   post-PR content was produced by applying the .diff onto pin + patches
#   04/23 (onClicked temporarily at its PR-base form), then re-applying
#   patch 04's onClicked line, and the edits below reproduce that derived
#   diff exactly. BarIndicator had no prior fork delta.
# - Upstream test/shell.d/fixtures/indicator-contract/shell.qml hunk NOT
#   ported: test/ is not in FORK_OUT (patch 26 precedent).
# - No install.sh placement step needed: all three files are under shell/,
#   which the installer copies wholesale and places.
# - Nyxiri-bar half: see the batch report. Nyxiri hosts this same stock
#   Indicators widget as a ModuleSlot; Bar.qml has no hover-blocking
#   overlay above slotted widgets (its only hoverEnabled MouseArea is the
#   bat button's own, and modulePointer/CenterGestureArea take no hover),
#   and its tooltip path forwards via PluginBarApi, so the in-widget fix
#   here is the whole fix and no Nyxiri-side change was staged.
#
# Standalone: bash v2/patches/61-bar-tooltips.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "61-bar-tooltips.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "61-bar-tooltips.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. BarIndicator: an icon in the active block keeps the reveal too ---
# Upstream: maintainIndicatorReveal was "inactive" only; a hovered ACTIVE
# icon (the one whose tooltip you are reading) did not hold the reveal, so
# the block could close under the pointer. "single" is the only block that
# must not hold it (a lone indicator has no hidden block to reveal).
step "Showing tooltips on bar indicator icons"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 61 bar-tooltips edit failed"; }
import sys

fork = sys.argv[1]


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _read(rel):
    try:
        with open(fork + "/" + rel, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        _die("%s not found in fork output" % rel)


def _write(rel, text):
    with open(fork + "/" + rel, "w", encoding="utf-8") as f:
        f.write(text)


def _once(text, old, new, what):
    n = text.count(old)
    if n == 0:
        _die("anchor missing for %s: %r" % (what, old[:80]))
    if n != 1:
        _die("anchor for %s occurs %d times, want exactly 1" % (what, n))
    return text.replace(old, new, 1)


# BarIndicator.qml: maintain the reveal for every block but "single".
rel = "shell/Ui/BarIndicator.qml"
s = _read(rel)
if 'maintainIndicatorReveal: indicatorBlock !== "single"' in s:
    print("BarIndicator: tooltip reveal already present, skipping")
else:
    s = _once(s, 'maintainIndicatorReveal: indicatorBlock === "inactive"',
              'maintainIndicatorReveal: indicatorBlock !== "single"',
              "BarIndicator maintainIndicatorReveal")
    _write(rel, s)
    print("patched: BarIndicator keeps the reveal for active/inactive blocks")

# WidgetButton.qml: per-item hover reporting + release the hold on destruction.
# Anchors are the live fork forms (patch 04's modifiers forwarding survives:
# the onClicked line is not touched by this patch).
rel = "shell/Ui/WidgetButton.qml"
s = _read(rel)
if "setIndicatorItemHovered(true, root)" in s and "setIndicatorItemHovered(false, root)" in s:
    print("WidgetButton: per-item hover reporting already present, skipping")
else:
    s = _once(s,
              "  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)",
              "  Component.onDestruction: {\n"
              "    if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)\n"
              "      root.revealHost.setIndicatorItemHovered(false, root)\n"
              "    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)\n"
              "  }",
              "WidgetButton onDestruction")
    s = _once(s, "root.revealHost.setIndicatorItemHovered(true)",
              "root.revealHost.setIndicatorItemHovered(true, root)",
              "WidgetButton onEntered hover report")
    s = _once(s, "root.revealHost.setIndicatorItemHovered(false)",
              "root.revealHost.setIndicatorItemHovered(false, root)",
              "WidgetButton onExited hover report")
    _write(rel, s)
    print("patched: WidgetButton reports hover per item and releases it on destruction")

# Indicators.qml: track hovered items (not one shared bool) and drop the
# hidden-block hover zone below the icons so their mouse areas get hover.
rel = "shell/plugins/bar/widgets/Indicators.qml"
s = _read(rel)
if "hoveredIndicatorItems" in s and "    z: -1" in s:
    print("Indicators: per-item hover tracking + zone below icons already present, skipping")
else:
    s = _once(s, "  property bool indicatorItemHovered: false",
              "  property var hoveredIndicatorItems: []\n"
              "  readonly property bool indicatorItemHovered: hoveredIndicatorItems.length > 0",
              "Indicators hoveredIndicatorItems")
    s = _once(s,
              "  function setIndicatorItemHovered(hovered) {\n"
              "    indicatorItemHovered = hovered\n"
              "    syncHoverReveal()\n"
              "  }",
              "  function setIndicatorItemHovered(hovered, item) {\n"
              "    var items = hoveredIndicatorItems.filter(function(hoveredItem) { return hoveredItem !== item })\n"
              "    if (hovered) items.push(item)\n"
              "    hoveredIndicatorItems = items\n"
              "    syncHoverReveal()\n"
              "  }",
              "Indicators setIndicatorItemHovered(item)")
    s = _once(s,
              "  // reopening in a loop. Above the icons, which a hover handler doesn't block.",
              "  // reopening in a loop. Below the icons so their mouse areas receive hover;\n"
              "  // the icons themselves keep the inactive block revealed while hovered.",
              "Indicators hiddenBlockZone comment")
    s = _once(s,
              '  Item {\n    objectName: "hiddenBlockZone"\n',
              '  Item {\n    objectName: "hiddenBlockZone"\n    z: -1\n',
              "Indicators hiddenBlockZone z")
    _write(rel, s)
    print("patched: Indicators tracks hovered items and hides its zone below the icons")

# --- validation: the new forms are present exactly once, the old forms gone.
for rel, new, old in [
    ("shell/Ui/BarIndicator.qml",
     'maintainIndicatorReveal: indicatorBlock !== "single"',
     'maintainIndicatorReveal: indicatorBlock === "inactive"'),
    ("shell/Ui/WidgetButton.qml",
     "setIndicatorItemHovered(true, root)", "setIndicatorItemHovered(true)"),
    ("shell/Ui/WidgetButton.qml",
     "setIndicatorItemHovered(false, root)", "setIndicatorItemHovered(false)"),
    ("shell/plugins/bar/widgets/Indicators.qml",
     "property var hoveredIndicatorItems: []", "property bool indicatorItemHovered: false"),
    ("shell/plugins/bar/widgets/Indicators.qml",
     "function setIndicatorItemHovered(hovered, item)",
     "function setIndicatorItemHovered(hovered) {"),
    ("shell/plugins/bar/widgets/Indicators.qml",
     "    z: -1", "Above the icons, which a hover handler doesn't block."),
]:
    text = _read(rel)
    # (false, root) is expected twice: onDestruction releases the hold AND
    # onExited reports leaving; (true, root) only once, onEntered.
    want = 2 if new == "setIndicatorItemHovered(false, root)" else 1
    if text.count(new) != want:
        _die("%s: %r occurs %d times after edit, want exactly %d" % (rel, new[:60], text.count(new), want))
    if old in text:
        _die("%s: old form still present after edit: %r" % (rel, old[:60]))
# Patch 04's modifiers forwarding and patch 23's id validation must survive.
wb = _read("shell/Ui/WidgetButton.qml")
if "signal pressed(int button, int modifiers)" not in wb:
    _die("patch 04 modifiers forwarding lost in WidgetButton.qml")
if "triggerPress(mouse.button, mouse.modifiers)" not in wb:
    _die("patch 04 onClicked modifiers lost in WidgetButton.qml")
ind = _read("shell/plugins/bar/widgets/Indicators.qml")
if "/^[A-Za-z0-9_-]+$/.test(indicatorSlot.indicatorId)" not in ind:
    _die("patch 23 indicator-id validation lost in Indicators.qml")
if 'moduleName: "hexciri.indicators"' not in ind:
    _die("hexciri moduleName rename lost in Indicators.qml")
print("bar tooltips validate (3 files, prior patch 04/23 deltas intact)")
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'bar tooltips patch: %d file edit(s) applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 61: bar indicator icons show tooltips (hover zone below the icons)"
