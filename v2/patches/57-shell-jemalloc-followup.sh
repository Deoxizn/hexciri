#!/usr/bin/env bash
# Hexciri fork patch 57: tune shell jemalloc + unmap idle dock surface
# (follow-up to patch 16). Forward-port of omarchy PR #20409 ("tune shell
# jemalloc + unmap idle dock surface") into bin/hexciri-launch-shell,
# shell/Commons/Util.qml and shell/plugins/dock/DockWindow.qml.
# PR diff verified 2026-11-27 against
# https://github.com/omacom/omarchy/pull/20409.diff (3 files, no test hunks).
#
# What it does (PR behavior, unchanged):
#  - bin/hexciri-launch-shell: MALLOC_CONF becomes
#    "narenas:2,dirty_decay_ms:1000,muzzy_decay_ms:0,thp:never". Upstream
#    measured ~110 MiB of fragmented/idle heap held by jemalloc's default
#    4*ncpu arenas, 10s decay and THP-backed 4 MiB extents on a 16 GiB
#    laptop; constraining arenas, decay and THP keeps idle RSS tight.
#  - shell/Commons/Util.qml: execDetached and execArgv run the target under
#    `env -u MALLOC_CONF`, so launched apps do not inherit the shell's
#    jemalloc arena/THP cap.
#  - shell/plugins/dock/DockWindow.qml: the dock PanelWindow is now
#    `visible: window.shown` (mapped only while its screen is on a floating
#    workspace), so tiled workspaces no longer hold a live layer surface and
#    dmabuf swapchain. The old opacity-hide path (keep textures resident for
#    the first frame back) is removed.
#
# Fork adaptation: upstream #20409 lands on a tree with NO MALLOC_CONF in
# the launcher (upstream PR #20242 never merged there), but the fork HAS one
# from patch 16: MALLOC_CONF="${MALLOC_CONF:-narenas:2,tcache_max:4096,
# background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0}". This patch
# REPLACES patch 16's value and its in-function comment with upstream's new
# value and upstream's comment (moved above run_shell(), as upstream has
# it). That drops tcache_max/background_thread and the ${MALLOC_CONF:-}
# caller override, matching upstream #20409 exactly: the value is now
# hard-set for the shell, and the Util scrub is what keeps launched apps
# clean. The Util.qml and DockWindow.qml hunks port verbatim: the fork
# files match upstream's diff context line for line (rename map only).
#
# Standalone: bash v2/patches/57-shell-jemalloc-followup.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited launcher is shell script, so bash -n DOES
# apply there (and runs on the patched file below). Util.qml and
# DockWindow.qml are QML: qmllint when present, warning only (it fails on
# missing Quickshell imports even for valid files).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "57-shell-jemalloc-followup.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
CHANGED=0

step "Tuning shell jemalloc and unmapping the idle dock surface (PR #20409)"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 57 shell jemalloc edit failed"; }
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
        print("WARN: %s not in fork output, skipping" % rel)
        return None


def _write(rel, s):
    with open(fork + "/" + rel, "w", encoding="utf-8") as f:
        f.write(s)


def _replace_once(s, rel, old, new, what):
    """If new is already there, skip; elif old occurs exactly once, replace;
    else die. Returns (new_s, changed_bool)."""
    if new in s:
        print("%s: already present, skipping" % what)
        return s, False
    if s.count(old) != 1:
        _die("anchor for %s occurs %d times, want exactly 1 in %s"
             % (what, s.count(old), rel))
    return s.replace(old, new, 1), True


# --- 1. bin/hexciri-launch-shell: new MALLOC_CONF value + comment ---
rel = "bin/hexciri-launch-shell"
s = _read(rel)
if s is not None:
    if "thp:never" in s:
        print("launch-shell jemalloc tune: already present, skipping")
    else:
        # Patch 16's in-function comment + MALLOC_CONF line, replaced by
        # upstream's new value. The comment is dropped with the value: it
        # describes tcache_max/background_thread, which the new value drops.
        old16 = (
            "  # Quickshell links jemalloc, which creates 4 * ncpus arenas by default and\n"
            "  # keeps dirty/muzzy pages from startup bursts (QML compilation, icon scanning,\n"
            "  # image decoding, Mesa shaders) resident. Two arenas, a 4 KiB thread cache,\n"
            "  # and a background purge thread return those pages quickly without stalling\n"
            "  # the GUI or render threads.\n"
            '  MALLOC_CONF="${MALLOC_CONF:-narenas:2,tcache_max:4096,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0}" \\\n'
        )
        new57 = '  MALLOC_CONF="narenas:2,dirty_decay_ms:1000,muzzy_decay_ms:0,thp:never" \\\n'
        s, changed = _replace_once(s, rel, old16, new57, "launch-shell MALLOC_CONF value")
        if changed:
            # Upstream's comment, above run_shell() exactly as upstream has
            # it. Fork spelling of the crash-watch line first, upstream as
            # a fallback for a tree the rename has not reached yet.
            comment = (
                "#\n"
                "# Quickshell links libjemalloc.so.2, whose default 4*ncpu arenas, 10s decay,\n"
                "# and THP-backed 4 MiB extents hold ~110 MiB of fragmented/idle heap on a\n"
                "# 16 GiB laptop. Constraining arenas, decay, and THP keeps idle RSS tight;\n"
                "# Util.execDetached/execArgv scrub MALLOC_CONF so launched apps don't inherit it.\n"
            )
            done = False
            for watch in ("hexciri-crash-watch", "omarchy-crash-watch"):
                old = ("# handler did, and systemd-coredump with %s reports the crash.\n"
                       "run_shell() {" % watch)
                if s.count(old) == 1:
                    s = s.replace(old, old.replace("run_shell() {", comment + "run_shell() {"), 1)
                    done = True
                    break
            if not done:
                _die("run_shell() comment anchor not found in %s" % rel)
            _write(rel, s)
            print("patched: launch-shell jemalloc tune in %s (PR #20409)" % rel)
        else:
            # New value already there but the old comment block was also
            # replaced already; nothing to write.
            pass

# --- 2. shell/Commons/Util.qml: scrub MALLOC_CONF from launched apps ---
rel = "shell/Commons/Util.qml"
s = _read(rel)
if s is not None:
    changed_any = False
    s, c = _replace_once(
        s, rel,
        '    Quickshell.execDetached(["bash", "-lc", command])',
        '    Quickshell.execDetached(["env", "-u", "MALLOC_CONF", "bash", "-lc", command])',
        "Util.execDetached MALLOC_CONF scrub")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        "  // xdg-open) need. Prefer this over execDetached for anything built from input.",
        "  // xdg-open) need. Scrub MALLOC_CONF so Quickshell's jemalloc arena/THP cap\n"
        "  // does not propagate into launched apps. Prefer this over execDetached for\n"
        "  // anything built from input.",
        "Util.execArgv MALLOC_CONF comment")
    changed_any = changed_any or c
    s, c = _replace_once(
        s, rel,
        '    Quickshell.execDetached(["bash", "-lc", \'exec "$@"\', "bash"].concat(argv))',
        '    Quickshell.execDetached(["env", "-u", "MALLOC_CONF", "bash", "-lc", \'exec "$@"\', "bash"].concat(argv))',
        "Util.execArgv MALLOC_CONF scrub")
    changed_any = changed_any or c
    if changed_any:
        if s.count('"env", "-u", "MALLOC_CONF"') != 2:
            _die("MALLOC_CONF scrub occurs %d times in %s, want exactly 2"
                 % (s.count('"env", "-u", "MALLOC_CONF"'), rel))
        _write(rel, s)
        print("patched: Util.execDetached/execArgv MALLOC_CONF scrub in %s (PR #20409)" % rel)

# --- 3. shell/plugins/dock/DockWindow.qml: unmap the dock when hidden ---
rel = "shell/plugins/dock/DockWindow.qml"
s = _read(rel)
if s is not None:
    if "visible: window.shown" in s:
        print("dock unmap: already present, skipping")
    else:
        old_head = (
            "// One screen's dock. It stays mapped and only hides its contents, so switching\n"
            "// to a floating workspace does not wait on a fresh layer surface. While hidden the\n"
            "// mask is empty and clicks fall through to the windows below.\n"
            "PanelWindow {\n"
            "  id: window\n"
        )
        new_head = (
            "// One screen's dock. Mapped only while this screen is on a floating workspace\n"
            "// so tiled workspaces do not hold a live layer surface and dmabuf swapchain.\n"
            "PanelWindow {\n"
            "  id: window\n"
            "  visible: window.shown\n"
        )
        s, _ = _replace_once(s, rel, old_head, new_head, "dock header comment + visible")
        old_opacity = (
            "    // Switching between tiled and floating workspaces shows and hides the dock\n"
            "    // at once, with nothing to watch in between. Hidden by opacity rather than\n"
            "    // visibility, so the icons keep their textures and are drawn on the first\n"
            "    // frame back instead of being uploaded again.\n"
            "    opacity: window.shown ? 1 : 0\n"
        )
        if s.count(old_opacity) != 1:
            _die("opacity-hide anchor occurs %d times, want exactly 1 in %s"
                 % (s.count(old_opacity), rel))
        s = s.replace(old_opacity, "", 1)
        if "opacity: window.shown ? 1 : 0" in s:
            _die("opacity-hide line still present after edit in %s" % rel)
        _write(rel, s)
        print("patched: dock unmapped when hidden in %s (PR #20409)" % rel)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on the edited launcher: a bad edit here would break
# the whole shell launch.
if [ -f "$FORK_OUT/bin/hexciri-launch-shell" ]; then
  bash -n "$FORK_OUT/bin/hexciri-launch-shell" || die "bash -n failed on bin/hexciri-launch-shell"
fi

# qmllint when present, warning only (missing Quickshell imports fail it
# even for valid files).
if command -v qmllint >/dev/null 2>&1; then
  for _q in "$FORK_OUT/shell/Commons/Util.qml" "$FORK_OUT/shell/plugins/dock/DockWindow.qml"; do
    [ -f "$_q" ] && qmllint "$_q" 2>&1 | head -5 || warn "qmllint reported on $_q"
  done
else
  warn "qmllint not found, skipping QML parse check"
fi

printf 'shell jemalloc follow-up patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 57: shell jemalloc tune + unmap idle dock (PR #20409)"
