#!/usr/bin/env bash

# Hexciri fork patch 73: port the Omarchy screensaver (native Wayland
# overlay) + ttfx, built from source. Forward-port of upstream
# omarchy-screensaver 1.3.1 (omacom/omarchy-screensaver, tag v1.3.1) and
# ttfx 0.5.1 (omacom/ttfx, tag v0.5.1), the versions omarchy-pkgs builds
# (PKGBUILD sha256s verified live 2026-11-27 against the codeload
# tarballs this patch downloads; see below).
#
# What it is upstream: since upstream commit fdbe182d39 (Oct 27 2026)
# the screensaver is a native Wayland layer-shell overlay on every
# display, rendering ttfx terminal-text effects in-process over the
# branding text. It runs at --frame-rate 120 with --random-effect; any
# key/click/scroll/mouse movement dismisses it. `omarchy-launch-screensaver`
# just execs /usr/lib/omarchy-screensaver/omarchy-screensaver, which is
# the omarchy-screensaver package installed from Omarchy's own pacman
# repo (install/omarchy-base.packages:110) -- the repo Hexciri cannot
# use, which is why this was never ported. PR #6670 swapped
# python-terminaltexteffects for ttfx (omacom/omarchy-pkgs#127).
#
# Install design (THPM precedent: build from GitHub source, not AUR):
#  - Sources arrive as codeload tarballs (install.sh precedent: curl, never
#    git clone), SHA-256 verified against the omarchy-pkgs PKGBUILD sums
#    before anything is extracted. A mismatch dies loudly, never builds.
#  - Both are cargo builds, PKGBUILD parity: `cargo fetch --locked` then
#    `cargo build --frozen --release` (screensaver also runs its own
#    `cargo test`, which needs no compositor per upstream README).
#  - Build deps are installed by this patch when missing: the Arch `rust`
#    package (cargo + rustc), `pkgconf` (pkg-config), `libxkbcommon` and
#    `fontconfig` (screensaver runtime deps per its PKGBUILD). All four
#    are installed with `sudo pacman -S --needed --noconfirm`, so a
#    machine that already has them pays nothing.
#  - Binaries land at the fork-renamed paths the launcher already execs:
#    /usr/lib/hexciri-screensaver/hexciri-screensaver (the Rust binary,
#    built as omarchy-launch-screensaver and installed under the fork
#    name) and /usr/local/bin/ttfx (unmanaged local PATH; upstream puts
#    it in /usr/bin via pacman, which the fork cannot do). Shell
#    completions go to /usr/share/bash-completion/completions/ttfx and
#    /usr/share/zsh/site-functions/_ttfx, LICENSE/NOTICE/README to
#    /usr/share/licenses/{hexciri-screensaver,ttfx}/, PKGBUILD parity.
#  - A stamp file ($SRC_DIR/.hexciri-built, "1.3.1 0.5.1") makes re-runs
#    a no-op when both binaries exist at the pinned versions, so
#    `hexciri update` does not rebuild Rust on every run. Sources and
#    cargo target dirs live under $SRC_DIR (default
#    ~/.cache/hexciri/screensaver-src) so incremental rebuilds are cheap
#    when a pin changes; never /tmp (tmpfs, too small for a cargo target
#    dir). HEXCIRI_SCREENSAVER_REBUILD=1 forces a rebuild.
#
# Is a standalone ttfx needed? For the screensaver itself, NO: the
# binary drives ttfx in-process as a library (src/engine.rs uses
# ttfx::{...}, Cargo.toml pins ttfx git tag v0.5.1; its own help text
# says "No terminal, Qt, C++, or ttfx child"). It is still installed
# because hexciri-provision-owner (first-boot greeter, renamed from
# upstream) calls bare `ttfx` for the colorshift logo animation, with no
# existence guard; without it the forked provision-owner is broken.
# Provisioning only runs at first boot, but the script must not be
# broken. Bonus: `ttfx` on PATH makes the 37 stock effects usable from
# the terminal too (PR #62's 13 community effects are NOT included:
# open PR, not merged, needs omarchy-screensaver#12 first; this patch
# ports the current stock version only).
#
# Source rename (the fork rule, applied to the Rust source before
# building -- the install.sh rename map only rewrites FORK_OUT files,
# never a binary built from source):
#  - org.omarchy.screensaver -> org.hexciri.screensaver (layer namespace
#    in wayland.rs, APP_ID in launch.rs). The rename map already rewrites
#    the same namespace in FORK_OUT (hexciri-debug-idle's layer selector,
#    had it been copied -- it is not allowlisted, but any future tooling
#    expects the fork namespace), so the binary must agree.
#  - ~/.config/omarchy/branding/screensaver.txt ->
#    ~/.config/hexciri/branding/screensaver.txt (options.rs; the fork
#    writes branding to ~/.config/hexciri/branding/).
#  - omarchy-toggle-enabled / omarchy-shell ->
#    hexciri-toggle-enabled / hexciri-shell, and the toggle fallback path
#    ~/.local/state/omarchy/toggles/ -> ~/.local/state/hexciri/toggles/
#    (launch.rs). The binary only calls these by bare name, so it relies
#    on /usr/share/hexciri/bin being on PATH, exactly like upstream
#    relies on /usr/share/omarchy/bin.
#  - omarchy-screensaver.lock -> hexciri-screensaver.lock, help text
#    omarchy-launch-screensaver -> hexciri-launch-screensaver.
#  - Bundled fallback art (assets/screensaver.txt, compiled in via
#    include_str!) is the OMARCHY logo upstream; replaced with
#    FORK_OUT/logo.txt (HEXCIRI art -- the same art
#    hexciri-branding-screensaver reset copies to the branding file).
#  - The crate name omarchy_launch_screensaver is deliberately NOT
#    renamed: the lib target and the tests/cli.rs CARGO_BIN_EXE_ env var
#    depend on it, and only the installed filename matters.
#  Every replacement must match at least once or the build dies: a
#  silent no-op would ship a binary that reads omarchy paths and calls
#  omarchy commands that do not exist on Hexciri.
#
# FORK_OUT half (runs after patch 02, which deletes the row):
#  - Restores the "system.screensaver" menu row between system.about and
#    system.lock (its upstream position), action
#    "hexciri-launch-screensaver force". The icon glyph is copied from
#    the existing trigger.toggle.screensaver-on row, never retyped: raw
#    PUA glyphs must not be retyped in this patch.
#  - Asserts (dies if wrong) that the rename map already produced the
#    hexciri paths in FORK_OUT/bin/hexciri-launch-screensaver
#    (exec /usr/lib/hexciri-screensaver/hexciri-screensaver) and
#    FORK_OUT/bin/hexciri-system-lock (pkill pattern for the same path).
#    The idle service needs no edit: the renamed Service.qml already
#    runs `hexciri-launch-screensaver`, and the Appearance > Branding
#    screensaver rows + Trigger toggle rows already exist in the fork
#    menu (they only lacked the binary behind them).
#  - hexciri-debug-idle is NOT allowlisted in install.sh, so it is not
#    in FORK_OUT and is not asserted here; its pgrep pattern would have
#    been rewritten by the same generic rule had it been copied.
#
# Companion install.sh edit (REQUIRED, staged alongside this patch --
# a patch cannot edit the installer that is currently running it, and
# install.sh would kill the install otherwise): remove
# '"system.screensaver"' from the _dead list in the placement
# verification (~line 3105). Without that edit the install dies with
# "dead menu row still present in hexciri-menu.jsonc:
# "system.screensaver"". No other install.sh change is needed: the
# _dead check is the only functional screensaver reference in
# install.sh (the rest are comments), and no new bin/ is added, so the
# allowlist is untouched -- launch/toggle/branding-screensaver and
# system-lock are all allowlisted already (launch-*, toggle-*,
# branding-*, system-*).
#
# Offline behavior: if the tarballs cannot be downloaded (no network)
# or the toolchain cannot be installed, the patch warns, skips the
# build AND the menu row (a row with no binary behind it is a dead
# row), and exits 0 -- the next `hexciri update` with network retries.
# A SHA mismatch, compile error, test failure, or post-install
# verification failure dies loudly instead: those are real breakage,
# not offline. If a previous build's binaries already exist, a failed
# download keeps them and the menu row is still restored.
#
# Standalone: bash v2/patches/73-screensaver.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Env overrides (sims/tests):
#   HEXCIRI_SCREENSAVER_SRC_DIR, HEXCIRI_SCREENSAVER_LIB_DIR,
#   HEXCIRI_SCREENSAVER_TTFX_BIN, HEXCIRI_SCREENSAVER_TARBALL,
#   HEXCIRI_TTFX_TARBALL (local file path or URL; curl handles both),
#   HEXCIRI_SCREENSAVER_REBUILD=1 to force a rebuild. Idempotent:
#   re-running with the stamp + both binaries present prints "already
#   current" and changes nothing; re-running on the same FORK_OUT finds
#   the menu row already present and makes zero menu edits.
#
# Syntax check note: the end of the patch verifies the installed
# binaries (screensaver --help names Hexciri, headless render produces
# frames, ttfx --version is 0.5.1) and dies if any check fails. bash -n
# applies to this script itself.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "73-screensaver.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "73-screensaver.sh: $1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}
CHANGED=0

SS_VER="1.3.1"
TTFX_VER="0.5.1"
SS_SHA="7bd9b75abc4fea072f63dec3a8fc339eee282bd1aca148a27a979766b657ff61"
TTFX_SHA="3f10b987b7690aa3caa2fa4f1749d8c7904e177380eff3e000d3422da8eb0134"
SS_TARBALL="${HEXCIRI_SCREENSAVER_TARBALL:-https://codeload.github.com/omacom/omarchy-screensaver/tar.gz/refs/tags/v${SS_VER}}"
TTFX_TARBALL="${HEXCIRI_TTFX_TARBALL:-https://codeload.github.com/omacom/ttfx/tar.gz/refs/tags/v${TTFX_VER}}"
SRC_DIR="${HEXCIRI_SCREENSAVER_SRC_DIR:-${HOME:?HOME is not set, cannot build the screensaver}/.cache/hexciri/screensaver-src}"
LIB_DIR="${HEXCIRI_SCREENSAVER_LIB_DIR:-/usr/lib/hexciri-screensaver}"
TTFX_BIN="${HEXCIRI_SCREENSAVER_TTFX_BIN:-/usr/local/bin/ttfx}"
SS_BIN="$LIB_DIR/hexciri-screensaver"
STAMP="$SRC_DIR/.hexciri-built"

step "Restoring the Hexciri screensaver (omarchy-screensaver $SS_VER + ttfx $TTFX_VER, built from source)"

# --- FORK_OUT anchors: the rename map must already have produced the
# hexciri paths. A patch that silently rewrote these would hide a
# rename-map regression; die instead. ---
LAUNCHER="$FORK_OUT/bin/hexciri-launch-screensaver"
LOCK_BIN="$FORK_OUT/bin/hexciri-system-lock"
[ -f "$LAUNCHER" ] || die "missing FORK_OUT file: bin/hexciri-launch-screensaver (launch-* not allowlisted?)"
grep -qF 'exec /usr/lib/hexciri-screensaver/hexciri-screensaver "$@"' "$LAUNCHER" \
  || die "bin/hexciri-launch-screensaver does not exec /usr/lib/hexciri-screensaver/hexciri-screensaver (rename map did not rewrite the /usr/lib path)"
[ -f "$LOCK_BIN" ] || die "missing FORK_OUT file: bin/hexciri-system-lock (system-* not allowlisted?)"
grep -qF "[/]usr/lib/hexciri-screensaver/hexciri-screensaver" "$LOCK_BIN" \
  || die "bin/hexciri-system-lock does not pkill /usr/lib/hexciri-screensaver/hexciri-screensaver (rename map did not rewrite the /usr/lib path)"

# --- Build decision: stamp + both binaries present at the pinned
# versions means nothing to do. ---
NEED_BUILD=1
if [ "${HEXCIRI_SCREENSAVER_REBUILD:-0}" != "1" ] \
  && [ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$SS_VER $TTFX_VER" ] \
  && [ -x "$SS_BIN" ] && [ -x "$TTFX_BIN" ]; then
  NEED_BUILD=0
  printf 'screensaver: already current (screensaver %s, ttfx %s), skipping build\n' "$SS_VER" "$TTFX_VER" >>"$_patch_log"
  info "  patch 73: screensaver already current (screensaver $SS_VER, ttfx $TTFX_VER), build skipped"
fi

if [ "$NEED_BUILD" = "1" ]; then
  BUILD_OK=0
  # Toolchain first. A failed pacman run means offline (or not Arch):
  # warn and fall through to the "binaries exist?" check below, which
  # decides whether the menu row may be restored. A pacman run that
  # claims success but leaves cargo missing is genuinely broken: die.
  if ! command -v cargo >/dev/null 2>&1 || ! command -v pkg-config >/dev/null 2>&1; then
    info "  patch 73: cargo or pkg-config missing, installing build deps (rust pkgconf libxkbcommon fontconfig)"
    if sudo pacman -S --needed --noconfirm rust pkgconf libxkbcommon fontconfig >/tmp/hexciri-screensaver-pacman.log 2>&1; then
      command -v cargo >/dev/null 2>&1 || die "pacman installed the build deps but cargo is still missing"
      command -v pkg-config >/dev/null 2>&1 || die "pacman installed the build deps but pkg-config is still missing"
    else
      warn "could not install the screensaver build deps (no network or no pacman; see /tmp/hexciri-screensaver-pacman.log), skipping the screensaver build this run"
    fi
  fi

  if command -v cargo >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1; then
    mkdir -p "$SRC_DIR/dl"
    SS_DL="$SRC_DIR/dl/omarchy-screensaver-$SS_VER.tar.gz"
    TTFX_DL="$SRC_DIR/dl/ttfx-$TTFX_VER.tar.gz"
    DOWNLOAD_OK=1
    curl -fsSL "$SS_TARBALL" -o "$SS_DL" 2>/tmp/hexciri-screensaver-curl.log || DOWNLOAD_OK=0
    if [ "$DOWNLOAD_OK" = "1" ]; then
      curl -fsSL "$TTFX_TARBALL" -o "$TTFX_DL" 2>>/tmp/hexciri-screensaver-curl.log || DOWNLOAD_OK=0
    fi
    if [ "$DOWNLOAD_OK" = "0" ]; then
      warn "could not download the screensaver sources (no network; see /tmp/hexciri-screensaver-curl.log), skipping the screensaver build this run"
    else
      # SHA-256 before extraction: a mismatch is a trust failure, die.
      echo "$SS_SHA  $SS_DL" | sha256sum -c - >/dev/null 2>&1 \
        || die "screensaver tarball SHA-256 mismatch (expected $SS_SHA)"
      echo "$TTFX_SHA  $TTFX_DL" | sha256sum -c - >/dev/null 2>&1 \
        || die "ttfx tarball SHA-256 mismatch (expected $TTFX_SHA)"
      SS_SRC="$SRC_DIR/omarchy-screensaver-$SS_VER"
      TTFX_SRC="$SRC_DIR/ttfx-$TTFX_VER"
      rm -rf "$SS_SRC" "$TTFX_SRC"
      tar xzf "$SS_DL" -C "$SRC_DIR" || die "could not extract the screensaver tarball"
      tar xzf "$TTFX_DL" -C "$SRC_DIR" || die "could not extract the ttfx tarball"
      # Codeload tarballs extract to omarchy-screensaver-<ver> / ttfx-<ver>.
      [ -d "$SS_SRC" ] || die "screensaver tarball did not extract to $SS_SRC"
      [ -d "$TTFX_SRC" ] || die "ttfx tarball did not extract to $TTFX_SRC"

      # Fork rename of the Rust source (see header). Every replacement
      # must match or the build dies -- a silent no-op ships a binary
      # that reads omarchy paths and calls omarchy commands.
      [ -s "$FORK_OUT/logo.txt" ] || die "FORK_OUT/logo.txt is missing or empty, cannot set the bundled fallback art"
      python3 - "$SS_SRC" "$FORK_OUT/logo.txt" <<'PY' || die "screensaver source rename failed (anchor missing -- upstream moved the string)"
import sys

src, logo = sys.argv[1], sys.argv[2]
replacements = [
    ("src/wayland.rs", "org.omarchy.screensaver", "org.hexciri.screensaver"),
    ("src/launch.rs", "org.omarchy.screensaver", "org.hexciri.screensaver"),
    ("src/launch.rs", "omarchy-toggle-enabled", "hexciri-toggle-enabled"),
    ("src/launch.rs", ".local/state/omarchy/toggles/screensaver-off",
     ".local/state/hexciri/toggles/screensaver-off"),
    ("src/launch.rs", "omarchy-shell", "hexciri-shell"),
    ("src/launch.rs", "omarchy-screensaver.lock", "hexciri-screensaver.lock"),
    ("src/options.rs", ".config/omarchy/branding/screensaver.txt",
     ".config/hexciri/branding/screensaver.txt"),
    ("src/options.rs", "omarchy-launch-screensaver", "hexciri-launch-screensaver"),
    ("src/options.rs", "Omarchy screensaver", "Hexciri screensaver"),
    ("src/main.rs", "omarchy-launch-screensaver", "hexciri-launch-screensaver"),
]
for rel, old, new in replacements:
    path = "%s/%s" % (src, rel)
    with open(path, encoding="utf-8") as f:
        data = f.read()
    count = data.count(old)
    if count == 0:
        sys.exit("anchor not found: %s in %s" % (old, rel))
    with open(path, "w", encoding="utf-8") as f:
        f.write(data.replace(old, new))
    print("  screensaver source: %s: %d x %r" % (rel, count, old))
with open(logo, encoding="utf-8") as f:
    art = f.read()
assert art.strip(), "fork logo.txt is empty"
with open("%s/assets/screensaver.txt" % src, "w", encoding="utf-8") as f:
    f.write(art)
print("  screensaver source: assets/screensaver.txt: fork logo art")
PY

      # PKGBUILD parity: fetch locked, build frozen. The screensaver's
      # Cargo.toml pins ttfx as a git dependency (tag v0.5.1), so fetch
      # needs git + network; the build itself is offline (--frozen).
      TARGET="$(uname -m)-unknown-linux-gnu"
      info "  patch 73: building ttfx $TTFX_VER (cargo fetch + build)"
      (cd "$TTFX_SRC" && cargo fetch --locked --target "$TARGET" \
        && CARGO_TARGET_DIR="$SRC_DIR/target-ttfx" cargo build --frozen --release) \
        > /tmp/hexciri-ttfx-build.log 2>&1 \
        || { tail -20 /tmp/hexciri-ttfx-build.log >&2; die "ttfx build failed (see /tmp/hexciri-ttfx-build.log)"; }
      info "  patch 73: building screensaver $SS_VER (cargo fetch + build + test)"
      (cd "$SS_SRC" && cargo fetch --locked --target "$TARGET" \
        && CARGO_TARGET_DIR="$SRC_DIR/target-ss" cargo build --frozen --release) \
        > /tmp/hexciri-screensaver-build.log 2>&1 \
        || { tail -20 /tmp/hexciri-screensaver-build.log >&2; die "screensaver build failed (see /tmp/hexciri-screensaver-build.log)"; }
      (cd "$SS_SRC" && CARGO_TARGET_DIR="$SRC_DIR/target-ss" cargo test --frozen) \
        > /tmp/hexciri-screensaver-test.log 2>&1 \
        || { tail -20 /tmp/hexciri-screensaver-test.log >&2; die "screensaver test suite failed (see /tmp/hexciri-screensaver-test.log)"; }

      SS_BUILD="$SRC_DIR/target-ss/release/omarchy-launch-screensaver"
      TTFX_BUILD="$SRC_DIR/target-ttfx/release/ttfx"
      [ -x "$SS_BUILD" ] || die "screensaver build produced no binary at $SS_BUILD"
      [ -x "$TTFX_BUILD" ] || die "ttfx build produced no binary at $TTFX_BUILD"

      # Install (sudo: /usr/lib and /usr/local are root-owned).
      sudo install -Dm755 "$SS_BUILD" "$SS_BIN" || die "could not install $SS_BIN"
      sudo install -Dm755 "$TTFX_BUILD" "$TTFX_BIN" || die "could not install $TTFX_BIN"
      "$TTFX_BUILD" --print-completion bash | sudo install -Dm644 /dev/stdin /usr/share/bash-completion/completions/ttfx \
        || die "could not install the ttfx bash completion"
      "$TTFX_BUILD" --print-completion zsh | sudo install -Dm644 /dev/stdin /usr/share/zsh/site-functions/_ttfx \
        || die "could not install the ttfx zsh completion"
      sudo install -Dm644 "$SS_SRC/LICENSE" /usr/share/licenses/hexciri-screensaver/LICENSE 2>/dev/null || true
      sudo install -Dm644 "$SS_SRC/README.md" /usr/share/doc/hexciri-screensaver/README.md 2>/dev/null || true
      sudo install -Dm644 "$TTFX_SRC/LICENSE" /usr/share/licenses/ttfx/LICENSE 2>/dev/null || true
      sudo install -Dm644 "$TTFX_SRC/NOTICE" /usr/share/licenses/ttfx/NOTICE 2>/dev/null || true
      sudo install -Dm644 "$TTFX_SRC/README.md" /usr/share/doc/ttfx/README.md 2>/dev/null || true

      # Post-install verification: the installed binaries must prove
      # they are the renamed fork builds, not upstream bytes. --help
      # names Hexciri, the headless render produces frames through the
      # in-process ttfx engine (no compositor needed), ttfx reports
      # the pinned version.
      "$SS_BIN" --help 2>&1 | grep -q "Hexciri screensaver" \
        || die "installed screensaver --help does not name Hexciri (source rename did not reach the installed binary)"
      "$SS_BIN" --headless --frames 5 --effect print --cols 40 --rows 12 --seed 1 2>/dev/null \
        | grep -q "frames=5" \
        || die "installed screensaver headless render produced no frames"
      "$TTFX_BIN" --version 2>&1 | grep -q "$TTFX_VER" \
        || die "installed ttfx --version is not $TTFX_VER"
      printf '%s %s\n' "$SS_VER" "$TTFX_VER" > "$STAMP"
      BUILD_OK=1
      printf 'screensaver: built + installed screensaver %s, ttfx %s\n' "$SS_VER" "$TTFX_VER" >>"$_patch_log"
      info "  patch 73: screensaver $SS_VER + ttfx $TTFX_VER built and installed ($SS_BIN, $TTFX_BIN)"
    fi
  fi

  # No binary, no menu row: without the binary behind it the row is
  # dead. (Offline first run lands here; the next update retries.)
  if [ "$BUILD_OK" != "1" ] && { [ ! -x "$SS_BIN" ] || [ ! -x "$TTFX_BIN" ]; }; then
    warn "screensaver binary not installed (build skipped offline), leaving System > Screensaver out of the menu this run"
    printf 'screensaver patch: %d menu edits applied (build skipped, no binary)\n' "$CHANGED" >>"$_patch_log"
    info "  patch 73: screensaver build skipped (offline), menu row not restored"
    exit 0
  fi
fi

# --- Restore the System > Screensaver menu row (patch 02 deleted it) ---
# Anchored on system.about / system.lock; the icon glyph is copied from
# the trigger.toggle.screensaver-on row already in the fork menu, never
# retyped. Validates the edited file still parses as JSONC.
MENU="$FORK_OUT/default/hexciri/hexciri-menu.jsonc"
if grep -q '"system.screensaver"' "$MENU"; then
  printf 'menu: system.screensaver already present, skipping\n' >>"$_patch_log"
else
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log" || die "menu row restore failed"
import json
import re
import sys

root = sys.argv[1]
menu = root + "/default/hexciri/hexciri-menu.jsonc"
with open(menu, encoding="utf-8") as f:
    text = f.read()
lines = text.splitlines()

def key_of(line):
    m = re.match(r'\s*"([^"]+)"\s*:', line)
    return m.group(1) if m else None

keys = [key_of(l) for l in lines]
if "system.screensaver" in keys:
    sys.exit("system.screensaver appeared between the bash check and this edit")
if "system.about" not in keys:
    sys.exit("menu anchor missing: system.about")
if "system.lock" not in keys:
    sys.exit("menu anchor missing: system.lock")
about_i = keys.index("system.about")
lock_i = keys.index("system.lock")
if lock_i != about_i + 1:
    sys.exit("menu anchors not adjacent: system.about at %d, system.lock at %d" % (about_i, lock_i))

icon = None
for line in lines:
    if key_of(line) == "trigger.toggle.screensaver-on":
        m = re.search(r'"icon"\s*:\s*"([^"]+)"', line)
        icon = m.group(1) if m else None
        break
if not icon:
    sys.exit("menu icon source missing: trigger.toggle.screensaver-on has no icon to copy")

row = '  "system.screensaver": {"icon":"%s","label":"Screensaver","action":"hexciri-launch-screensaver force"},' % icon
lines.insert(lock_i, row)
new_text = "\n".join(lines) + "\n"

# JSONC validation: strip full-line // comments and the file's one
# trailing comma (last entry before the closing brace -- valid JSONC,
# invalid strict JSON), then parse. This validates only; the file
# written above keeps its original bytes otherwise.
body = [l for l in new_text.splitlines() if not l.strip().startswith("//")]
for i in range(len(body) - 1, -1, -1):
    if body[i].strip() == "}":
        j = i - 1
        while j >= 0 and body[j].strip() == "":
            j -= 1
        if j >= 0 and body[j].rstrip().endswith(","):
            body[j] = body[j].rstrip()[:-1]
        break
try:
    json.loads("\n".join(body))
except ValueError as e:
    sys.exit("menu jsonc does not parse after the edit: %s" % e)

with open(menu, "w", encoding="utf-8") as f:
    f.write(new_text)
print("menu: restored system.screensaver (icon copied from trigger.toggle.screensaver-on)")
PY
CHANGED=1
fi

printf 'screensaver patch: %d menu edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 73: System > Screensaver restored (hexciri-launch-screensaver force; screensaver $SS_VER + ttfx $TTFX_VER)"
