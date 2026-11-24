#!/usr/bin/env bash
# Hexciri fork patch 08: hexciri-update for EndeavourOS (Phase 2).
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/08-update-eos.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "08-update-eos.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  # Re-run quiet (2026-11-24, Devi: a plain `hexciri update` printed
  # ~500 lines of installer re-run spam, most of them "Kept: ... (already
  # current)" / "already present" / "already correct"). On a re-run those
  # go to the detail log only; changed / failed steps still print, and
  # the one-line "already up to date" status lines (run_pacman) stay on
  # screen, they are the per-step result.
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
# Fork-integrity helpers, verbatim from install.sh (00-compat-alias.sh
# calls bootstrap_ok; hyprlua_ok is here for any patch that needs it).
bootstrap_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 500 ] || return 1
  grep -q 'package.path' "$_f" 2>/dev/null || return 1
  grep -q 'HEXCIRI_PATH' "$_f" 2>/dev/null || return 1
  return 0
}
hyprlua_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 1000 ] || return 1
  grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1
  return 0
}

# --- Fork-time patch: hexciri-update for EndeavourOS (Phase 2, 2026-11-24) ---
# Rework upstream omarchy-update into the Hexciri update pipeline. Do NOT
# call eos-update directly and do NOT build a new updater: the forked
# hexciri-update stays the orchestrator (lock, transcript, confirm, sudo
# keepalive, stay-awake, status refresh, restart prompt, shell restart),
# only its steps are swapped for EndeavourOS:
#   * No snapshot. Devi 2026-11-24: systemd-boot + ext4, no GRUB/btrfs, so
#     snapshots are not a thing; eos-update --aur + Hexciri sync is enough.
#   * System packages: pacman directly, unattended. The start confirm
#     in hexciri-update is the one approval; after it
#     HEXCIRI_UPDATE_UNATTENDED=1, so the pacman --noconfirm path runs
#     and eos-update --aur does not (eos-update has NO --noconfirm
#     flag, and yay inside it prompts [Y/n] for e.g. mise). Db sync
#     runs captured (no "is up to date" lines), checkupdates counts
#     pending updates, pacman -Su runs live so the ILoveCandy bar
#     shows, then one status line. A .pacnew in /etc gets one line.
#   * AUR: yay output is captured, one status line instead ("AUR
#     packages are up to date" / "AUR packages updated"). The EOS
#     marker branch prints the same one line, never "skipping".
#   * Hexciri self-update: the dev-checkout step is a no-op on an installed
#     machine (HEXCIRI_PATH is /usr/share/hexciri, not a checkout), so
#     hexciri-update-hexciri (repo file v2/hexciri-update-hexciri) syncs
#     nyx with git like v1 (clone/pull ~/.local/opt/hexciri-nyx, no
#     auth, tarball fallback) and re-runs this installer when the
#     installer sha changed, judged by /usr/share/hexciri/.installer-sha.
#     Output is quiet (2026-11-24, Devi): one themed 'Updating Hexciri'
#     header and one short status line on screen; full shas, paths and
#     reasons go to /tmp/hexciri-update-hexciri.log (or to the screen
#     with HEXCIRI_UPDATE_VERBOSE=1). Real errors still print clearly.
#     The installer re-places /usr/share/hexciri/bin while hexciri-update
#     is running, so if hexciri-update itself changed it re-execs the new
#     copy (same PID, so the sudo keepalive and the update lock survive).
#   * Keyring: Arch + EndeavourOS keyrings only. There is no Hexciri
#     keyring package, no WKD key, no Hexciri package repo, no Omarchy repo.
#   * Boot: no lifecycle-dispatch package is registered (it is a no-op on
#     x86 and is deliberately not copied), so boot verification runs
#     bootctl status directly instead of failing with 127.
#   * Available: the upstream check only counted the omarchy package, which
#     Hexciri does not ship, so it always reported up to date. Now any
#     pending checkupdates entry counts.
#   * Analyze-logs: dracut failure strings added (EndeavourOS default,
#     not mkinitcpio).
#   * Pacman guard: replaced by a no-op. The guard as shipped blocks any
#     direct pacman call, which is exactly what eos-update and yay do.
#   * mise: hexciri-mise-install / hexciri-mise-default-tools are now
#     copied (allowlist above), /etc/mise/conf.d/hexciri-tools.toml is
#     installed below, shims are on PATH in profile.d and uwsm env.
step "Patching hexciri-update for EndeavourOS (eos-update --aur, no snapshot, Hexciri self-update, mise)"
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" "$FORK_OUT/bin/hexciri-update-hexciri"
  chmod +x "$FORK_OUT/bin/hexciri-update-hexciri"
  info "  update: hexciri-update-hexciri installed (nyx git sync self-update, tarball fallback, re-runs installer when it changed)"
else
  die "v2/hexciri-update-hexciri not in the installer tree, hexciri update cannot pull Hexciri updates"
fi
# hexciri-theme-ansi (repo file v2/hexciri-theme-ansi): prints the ANSI
# truecolor escape for a named color from the ACTIVE theme, so update
# output follows the theme instead of stock Omarchy green. Copied here
# like hexciri-update-hexciri, same step as the update fork patch below.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi" "$FORK_OUT/bin/hexciri-theme-ansi"
  chmod +x "$FORK_OUT/bin/hexciri-theme-ansi"
  info "  update: hexciri-theme-ansi installed (theme-matched green/red for update output)"
else
  die "v2/hexciri-theme-ansi not in the installer tree, update output falls back to stock green"
fi
# hexciri-theme-link (repo file v2/hexciri-theme-link): `hexciri theme
# link <url>` wrapper over theme-link (ministry-of-taste/theme-link).
# The dispatcher routes hexciri-theme-* bins, so this lands as the
# theme link command. Copied here like hexciri-theme-ansi; the
# upstream tool itself is installed by the theme-link step below.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-link" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-link" "$FORK_OUT/bin/hexciri-theme-link"
  chmod +x "$FORK_OUT/bin/hexciri-theme-link"
  info "  theme link: hexciri-theme-link installed (hexciri theme link <git-url>)"
else
  die "v2/hexciri-theme-link not in the installer tree, hexciri theme link will not exist"
fi
# hexciri-theme-sync (repo file v2/hexciri-theme-sync): `hexciri theme
# sync` bulk git-theme sync from ~/.config/hexciri/themes.list
# (clone missing, pull present --ff-only, declarative removal guarded
# to ~/.config/hexciri/themes/, never stock/symlinks/current theme).
# The dispatcher already allows theme-* bins, so this lands as the
# theme sync command with no allowlist change. Copied here like
# hexciri-theme-link; the list file itself is seeded by the theme-link
# step below, never overwritten.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-sync" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-sync" "$FORK_OUT/bin/hexciri-theme-sync"
  chmod +x "$FORK_OUT/bin/hexciri-theme-sync"
  info "  theme sync: hexciri-theme-sync installed (hexciri theme sync [--dry-run] [--no-remove])"
else
  die "v2/hexciri-theme-sync not in the installer tree, hexciri theme sync will not exist"
fi
# hexciri-web-search (repo file v2/hexciri-web-search): Super+Shift+S
# web search. v1 web search without fuzzel: prompt via
# hexciri-menu-input (QS menu), provider table + state file kept from
# v1, result opened in Brave Origin via hexciri-launch-browser.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-web-search" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-web-search" "$FORK_OUT/bin/hexciri-web-search"
  chmod +x "$FORK_OUT/bin/hexciri-web-search"
  info "  web search: hexciri-web-search installed (Super+Shift+S, QS prompt, Brave Origin)"
else
  die "v2/hexciri-web-search not in the installer tree, Super+Shift+S web search will not exist"
fi
# hexciri-font-maple-cn-present (repo file v2/hexciri-font-maple-cn-present):
# exit 0 if any Maple Mono NF CN package is installed (either AUR name).
# Disabled check for Install > Style > Font > Maple Mono CN, so the row
# is greyed out when the CN variant is already there, whichever package
# name it was installed under (reinstall fix 2026-11-24).
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-font-maple-cn-present" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-font-maple-cn-present" "$FORK_OUT/bin/hexciri-font-maple-cn-present"
  chmod +x "$FORK_OUT/bin/hexciri-font-maple-cn-present"
  info "  font: hexciri-font-maple-cn-present installed (Maple Mono CN disabled check)"
else
  die "v2/hexciri-font-maple-cn-present not in the installer tree, Maple Mono CN menu row cannot be disabled when installed"
fi
# hexciri-settings-tabs (repo file v2/hexciri-settings-tabs): extra-pane
# registry for Hexciri Settings (Nyxiri tab hook). Dispatcher bin, so
# `hexciri-settings-tabs add nyxiri ...` works from any terminal.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-settings-tabs" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-settings-tabs" "$FORK_OUT/bin/hexciri-settings-tabs"
  chmod +x "$FORK_OUT/bin/hexciri-settings-tabs"
  info "  settings tabs: hexciri-settings-tabs installed (extra panes: Nyxiri tab hook)"
else
  die "v2/hexciri-settings-tabs not in the installer tree, Hexciri Settings extra panes cannot be registered"
fi
# hexciri-launch-settings (repo file v2/hexciri-launch-settings):
# Super+Ctrl+S Settings launcher. Opens hexciri-settings
# when built; when the binary is missing it notifies with the
# rebuild command instead of silently doing nothing (2026-11-24).
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-launch-settings" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-launch-settings" "$FORK_OUT/bin/hexciri-launch-settings"
  chmod +x "$FORK_OUT/bin/hexciri-launch-settings"
  info "  settings launcher: hexciri-launch-settings installed (Super+Ctrl+S, notifies when the app is not built yet)"
else
  die "v2/hexciri-launch-settings not in the installer tree, Super+Ctrl+S Settings will fail silently"
fi
# Hexciri custom Lua, 2026-11-24 (Devi: Hexciri Lua, custom parts only).
# v1 binds.lua / windowrules.lua mostly mimic Omarchy, so only the
# Hexciri-only binds/rules live here; everything Omarchy already
# has is NOT duplicated, or binds would double-register. Copied into
# the fork as default/hypr/bindings/hexciri.lua (monocle stack cycle
# Super+[ / ], Brave incognito Super+Ctrl+B, Messenger Super+Ctrl+M,
# screen record Alt+Print) and default/hypr/apps/hexciri.lua
# (TUI.float 1000x720, app.hexciri.ff 1210x720, mpv float + 1.0
# override opacity with PiP excluded, imv 1.0 override opacity).
for _lua in "hexciri-custom-binds.lua:default/hypr/bindings/hexciri.lua" "hexciri-custom-apps.lua:default/hypr/apps/hexciri.lua"; do
  _lua_src="${_lua%%:*}"; _lua_dst="${_lua##*:}"
  if [ -f "$HEXCIRI_REPO_ROOT/v2/$_lua_src" ]; then
    mkdir -p "$FORK_OUT/$(dirname "$_lua_dst")"
    cp -a "$HEXCIRI_REPO_ROOT/v2/$_lua_src" "$FORK_OUT/$_lua_dst"
    if command -v luac5.1 >/dev/null 2>&1; then luac5.1 -p "$FORK_OUT/$_lua_dst" || die "Lua syntax check failed on $_lua_dst"; elif command -v luac >/dev/null 2>&1; then luac -p "$FORK_OUT/$_lua_dst" || die "Lua syntax check failed on $_lua_dst"; fi
    info "  hexciri lua: $_lua_src -> $_lua_dst (custom-only, explicitly required from hexciri.lua; require_all never loads bindings/)"
  else
    die "v2/$_lua_src not in the installer tree, Hexciri custom Lua ($_lua_dst) cannot be installed"
  fi
done
unset _lua _lua_src _lua_dst
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
fork = sys.argv[1]

def read(p):
    with open(p) as f:
        return f.read()

def write(p, text):
    with open(p, "w") as f:
        f.write(text)

def must_replace(path, old, new, what, marker=None):
    text = read(path)
    if (marker if marker is not None else new) in text:
        print("  update: %s (already applied, skipping)" % what)
        return
    assert text.count(old) == 1, "%s: anchor not unique in %s (count %d)" % (what, path, text.count(old))
    write(path, text.replace(old, new, 1))
    print("  update: %s" % what)

upd = fork + "/bin/hexciri-update"

# 1. Drop the snapshot step. BUG (2026-11-24, Devi: Prune package cache
# missing): upstream called hexciri-update-pkg-prune BEFORE the snapshot,
# with the "Before the snapshot:" comment above it, so the prune CALL was
# inside the deleted lines[start:end+1] range and got dropped with the
# snapshot. The replacement comment then claimed "the cache prune above
# stays", which was false: nothing called pkg-prune any more (sim6out
# had the call, sim7out has zero). Restore the call here, in the same
# place upstream had it: after authorize, before stay-awake / self-update
# / system-pkgs. No snapshot on Hexciri (systemd-boot + ext4), so there
# is no snapshot for the prune to precede; it just runs before any update.
lines = read(upd).splitlines(keepends=True)
_snap_done = any("No snapshot: Devi 2026-11-24" in l for l in lines)
start = next((i for i, l in enumerate(lines) if "Before the snapshot:" in l), None)
end = next((i for i, l in enumerate(lines) if "update.noSnapshot" in l), None)
assert _snap_done or (start is not None and end is not None and end > start), "snapshot block bounds wrong"
if not _snap_done:
    lines[start:end + 1] = [
        "  # No snapshot: Devi 2026-11-24, systemd-boot + ext4, no GRUB/btrfs,\n",
        "  # so snapshots are not a thing. eos-update --aur + Hexciri sync is\n",
        "  # enough. No snapshot, so the prune runs here, before any update.\n",
        "  hexciri-update-pkg-prune\n",
    ]
    write(upd, "".join(lines))
    print("  update: snapshot step dropped from hexciri-update")
else:
    print("  update: snapshot step already dropped from hexciri-update")

# 2. Hexciri self-update before update-dev, with a re-exec guard: the
# installer re-places /usr/share/hexciri/bin while this script runs.
must_replace(upd, "  hexciri-update-dev\n", "\n".join([
    "  # Hexciri self-update first: pull nyx and re-run the installer when it",
    "  # changed. On an installed machine update-dev is a no-op (HEXCIRI_PATH is",
    "  # /usr/share/hexciri, not a checkout), so it cannot pull Hexciri updates.",
    "  if [[ ${HEXCIRI_UPDATE_SELF_DONE:-0} != \"1\" ]]; then",
    "    _hexciri_update_self_before=\"$(sha256sum \"$0\" 2>/dev/null || true)\"",
    "    _hexciri_update_self_before=\"${_hexciri_update_self_before%% *}\"",
    "    HEXCIRI_UPDATE_CONTINUE_ON_SYNC_FAIL=1 hexciri-update-hexciri",
    "    _hexciri_update_self_after=\"$(sha256sum \"$0\" 2>/dev/null || true)\"",
    "    _hexciri_update_self_after=\"${_hexciri_update_self_after%% *}\"",
    "    # If this script itself changed, re-exec the new copy so the rest of",
    "    # the pipeline runs new code. Same PID after exec, so the sudo",
    "    # keepalive and the update lock survive.",
    "    if [[ -n \"$_hexciri_update_self_before\" && -n \"$_hexciri_update_self_after\" && \"$_hexciri_update_self_before\" != \"$_hexciri_update_self_after\" ]]; then",
    "      exec env HEXCIRI_UPDATE_REEXECED=1 HEXCIRI_UPDATE_SELF_DONE=1 HEXCIRI_UPDATE_LOGGED=1 \"$0\" \"$@\"",
    "    fi",
    "    export HEXCIRI_UPDATE_SELF_DONE=1",
    "  fi",
    "",
    "  hexciri-update-dev",
]) + "\n", "hexciri-update calls hexciri-update-hexciri before update-dev")

# 2b. No second Ready box after a self-update re-exec (2026-11-24, Devi:
# the confirm box showed again after "Hexciri updated to ..."). When the
# installer re-placed hexciri-update, it re-execs the new copy with
# HEXCIRI_UPDATE_REEXECED=1 (same PID, sudo keepalive and lock survive).
# The first pass already confirmed and authorized, so the re-exec must
# skip the confirm box. authorize_update itself is made a no-op on a
# re-exec (next must_replace) instead of nesting the call: the marker /
# UNATTENDED exports inserted after the call still have to run on the
# re-exec pass.
must_replace(upd, "if [[ ${1:-} == \"-y\" ]] || hexciri-update-confirm; then\n  authorize_update\n",
    "if [[ ${1:-} == \"-y\" || ${HEXCIRI_UPDATE_REEXECED:-0} == \"1\" ]] || hexciri-update-confirm; then\n  authorize_update\n",
    "hexciri-update skips the second confirm on a self-update re-exec")
must_replace(upd, "authorize_update() {\n  sudo true || return 1\n",
    "authorize_update() {\n  # Re-exec after self-update: the first pass already authorized\n  # and its sudo keepalive is still running (same PID after exec).\n  # Do not start a second keepalive the cleanup never kills.\n  if [[ ${HEXCIRI_UPDATE_REEXECED:-0} == \"1\" ]]; then\n    return 0\n  fi\n  sudo true || return 1\n",
    "authorize_update is a no-op on a self-update re-exec")

# 3. Marker path for this run only: system-pkgs sets it when eos-update --aur
# already updated the AUR, so the aur-pkgs step skips its duplicate yay run.
must_replace(upd, "  authorize_update\n",
    "  authorize_update\n  # Marker file for this run only (underscores, not hyphens, so the\n  # fork scan does not read it as a hexciri-* command name).\n  export HEXCIRI_UPDATE_EOS_MARKER=\"/tmp/hexciri_update_eos_aur_$$.marker\"\n",
    "hexciri-update exports the eos-update AUR marker path",
    marker="# Marker file for this run only")

# 3b. Unattended after the single start confirm (2026-11-24, Devi:
# once it finds an update it should all just be -y, no more Y/n
# prompts). The confirm above is the one approval; after it the run
# is unattended, so system-pkgs takes the pacman --noconfirm path
# instead of eos-update (whose yay prompts [Y/n]), the reboot step
# prints "reboot later" instead of prompting, and a real package
# conflict fails with "run interactively" instead of sitting on a
# prompt nobody answers.
must_replace(upd, "  authorize_update\n",
    "  authorize_update\n  export HEXCIRI_UPDATE_UNATTENDED=1\n",
    "hexciri-update is unattended after the single start confirm",
    marker="export HEXCIRI_UPDATE_UNATTENDED=1")

# 4. Cleanup removes the marker (cleanup_update calls end_update_authorization;
# the same call also appears in the main flow after boot verification, so
# anchor on the cleanup_update function header, not on the call alone).
must_replace(upd, "cleanup_update() {\n  local status=$?\n  trap - EXIT HUP INT TERM\n  end_update_authorization\n",
    "cleanup_update() {\n  local status=$?\n  trap - EXIT HUP INT TERM\n  end_update_authorization\n  rm -f \"${HEXCIRI_UPDATE_EOS_MARKER:-}\" 2>/dev/null || true\n",
    "hexciri-update cleanup removes the eos-update AUR marker")

# 5. aur-pkgs: whole-file rewrite (2026-11-24, Devi: quiet AUR step).
# The EOS-marker branch prints one line ("AUR packages are up to
# date"), never "already updated by eos-update --aur, skipping".
# Otherwise yay output is captured and one status line is shown.
_aur = fork + "/bin/hexciri-update-aur-pkgs"
with open(_aur, "w") as f:
    f.write(r'''#!/bin/bash

# omarchy:summary=Update AUR packages if any are installed

# mise exports GOROOT and GOBIN for its own Go. hexciri update runs
# this with the system PATH but the caller's environment, so /usr/bin/go would
# compile with mise's toolchain and every Go PKGBUILD fails with
# "compile: version ... does not match go tool version". With both unset,
# whichever go is on PATH uses its own root.
unset GOROOT GOBIN

# eos-update --aur already did the AUR in the system-pkgs step; the marker
# file is set by hexciri-update for this run only. One line, no "skipping",
# no duplicate yay run. In a normal `hexciri update` this branch is not
# reached (system-pkgs takes the pacman path and leaves the marker unset);
# it is kept for a standalone interactive run.
if [[ -n ${HEXCIRI_UPDATE_EOS_MARKER:-} && -f $HEXCIRI_UPDATE_EOS_MARKER ]]; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.aur)\e[0m"
  echo "AUR packages are up to date"
  exit 0
fi

if pacman -Qem >/dev/null; then
  # Header FIRST, before the accessibility check (2026-11-24, Devi: the
  # AUR error appeared right under "Update mise tools" with no AUR header
  # at all, so it read as a mise error). mise never calls the AUR helper;
  # the next step after mise is this one, and its old else branch only
  # printed the red "AUR is unavailable" line, never the step header.
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.aur)\e[0m"
  # Is the AUR reachable? Prefer the helper, but do NOT fail with
  # "command not found" if it is missing from the fork (2026-11-24: it
  # was not in the bin allowlist, so the fork never copied it and every
  # update reported "AUR is unavailable"). Fall back to the same curl
  # check the helper does, inline.
  _aur_accessible=0
  if command -v hexciri-pkg-aur-accessible >/dev/null 2>&1; then
    hexciri-pkg-aur-accessible && _aur_accessible=1 || _aur_accessible=0
  elif curl -sf --connect-timeout 10 --retry 1 --retry-delay 2 -A "hexciri-update" "https://aur.archlinux.org/rpc/?v=5&type=info&arg=base" >/dev/null 2>&1; then
    _aur_accessible=1
  fi
  if [[ "$_aur_accessible" == "1" ]]; then
    # Quiet on purpose (2026-11-24, Devi): yay prints "Searching AUR for
    # updates... there is nothing to do" and build logs. Capture it, show
    # one status line instead. Real failures print the captured output.
    _aur_log="$(mktemp /tmp/hexciri-aur.XXXXXX)"
    if yay -Sua --noconfirm --cleanafter --ignore gcc14,gcc14-libs >"$_aur_log" 2>&1; then
      _aur_ok=1
    else
      _aur_ok=0
    fi
    # thpm (2026-11-24, Devi): kicked off AUR, installed via GitHub
    # (OldJobobo/thpm) source script, not yay/pacman, so yay's
    # "Packages not in AUR: thpm" warning is expected noise. Strip it
    # from the log before judging success, and never report AUR as
    # failing / unavailable because of thpm alone: if the filtered log
    # says "there is nothing to do", it is up to date even if yay
    # exited non-zero over thpm. Failure output shows the filtered
    # log, never the thpm line.
    grep -v "Packages not in AUR: thpm" "$_aur_log" >"$_aur_log.filtered" 2>/dev/null || true
    if grep -q "there is nothing to do" "$_aur_log.filtered"; then
      echo "AUR packages are up to date"
      rm -f "$_aur_log" "$_aur_log.filtered"
    elif [[ "$_aur_ok" == "1" ]]; then
      _aur_n="$(grep -cE '(\\([0-9]+/[0-9]+\\) )?upgrading ' "$_aur_log.filtered" 2>/dev/null || true)"
      _aur_n="$(echo "$_aur_n" | tr -d ' ')"
      if [[ "$_aur_n" -gt 0 ]]; then
        echo "AUR packages updated ($_aur_n package(s))"
      else
        echo "AUR packages updated"
      fi
      grep -E "upgrading" "$_aur_log.filtered" | sed 's/^/  /' || true
      rm -f "$_aur_log" "$_aur_log.filtered"
    else
      echo "ERROR: AUR update failed, output:" >&2
      cat "$_aur_log.filtered" >&2
      rm -f "$_aur_log" "$_aur_log.filtered"
      exit 1
    fi
  else
    echo "AUR is unavailable, skipping AUR updates (aur.archlinux.org not reachable)"
  fi
fi
''')
print("  update: hexciri-update-aur-pkgs rewritten (quiet: one status line, no duplicate yay output)")

# 6. boot: verify systemd-boot directly when lifecycle-dispatch is absent.
must_replace(fork + "/bin/hexciri-update-boot", "set -e\n",
    "set -e\n\n# x86 / systemd-boot: no lifecycle-dispatch package is registered (it is a\n# no-op on x86 and is deliberately not copied), so verify the boot chain\n# directly instead of failing with 127 on a missing command.\nif ! command -v hexciri-lifecycle-dispatch >/dev/null 2>&1; then\n  if bootctl status >/dev/null 2>&1 || sudo bootctl status >/dev/null 2>&1; then\n    exit 0\n  fi\n  echo \"Warning: bootctl status failed, boot chain not verified\" >&2\n  exit 1\nfi\n",
    "hexciri-update-boot verifies systemd-boot directly when lifecycle-dispatch is absent")

# 7. confirm: the whats-new link pointed at omacom/hexciri, which is not a repo.
# 2026-11-24: repo root, not releases/latest -- Devi does no releases/ISOs.
must_replace(fork + "/bin/hexciri-update-confirm",
    "https://github.com/omacom/hexciri/releases/latest",
    "https://github.com/Deoxizn/hexciri",
    "hexciri-update-confirm points at Deoxizn/hexciri (repo root, no releases)")

# 7b. Dead-domain cleanup (2026-11-24, Devi: no hexciri.org, no discord).
# The rename turns omarchy.org/discord into hexciri.org/discord, and
# omarchy.org/manual + omarchy.org/themes into hexciri.org/* too. None
# of those domains are Devi's, so every user-visible one points at the
# GitHub issues page / repo instead, the only help destination that
# actually exists. (geo.hexciri.org in hexciri-weather-location and
# pkgs.hexciri.org in hexciri-version-channel are left alone: the first
# needs a geo-service decision, the second is dead channel code that
# just reports "unknown".)
must_replace(fork + "/bin/hexciri-update",
    "https://hexciri.org/discord",
    "https://github.com/Deoxizn/hexciri/issues",
    "hexciri-update error footer points at Deoxizn/hexciri/issues, not hexciri.org/discord")
must_replace(fork + "/bin/hexciri-theme-install",
    "https://hexciri.org/themes/",
    "https://github.com/Deoxizn/hexciri",
    "hexciri-theme-install hint points at the repo, not hexciri.org/themes")
must_replace(fork + "/bin/hexciri-theme-set-obsidian",
    '"authorUrl": "https://hexciri.org"',
    '"authorUrl": "https://github.com/Deoxizn/hexciri"',
    "hexciri-theme-set-obsidian manifest authorUrl points at the repo, not hexciri.org")
must_replace(fork + "/bin/hexciri-launch-manual",
    'exec hexciri-launch-webapp "${site:-https://hexciri.org/}manual/"',
    'exec hexciri-launch-webapp "${site:-https://github.com/Deoxizn/hexciri/}"',
    "hexciri-launch-manual opens the repo, not hexciri.org/manual")
import re as _re7b
_loc = fork + "/default/i18n/locales.json"
_t7b = read(_loc)
_n7b = len(_re7b.findall(r'"site": "https://[^"]*hexciri[^"]*"', _t7b))
_t7b = _re7b.sub(r'"site": "https://[^"]*hexciri[^"]*"', '"site": "https://github.com/Deoxizn/hexciri/"', _t7b)
write(_loc, _t7b)
print("  update: locales.json manual sites (%d) point at the repo, not hexciri.org" % _n7b)

# 8. Theme-matched green/red in update output, 2026-11-24: upstream prints
# section headers with hardcoded \e[32m (stock Omarchy green) and errors
# with \e[31m. Replace both with hexciri-theme-ansi, which reads the green /
# red of the ACTIVE theme (current/theme/colors.toml), falling back to the
# theme accent, then dirty.pizza #33ff99 / #ff3333 with no theme set. The
# helper prints a truecolor escape, which echo -e / printf interpret.
# Scope is the update presentation path only: update-* bins, show-logo,
# show-done. Other bins keep their own colours.
for _name in ["hexciri-update", "hexciri-update-system-pkgs", "hexciri-update-keyring", "hexciri-update-aur-pkgs", "hexciri-update-mise", "hexciri-update-dev", "hexciri-update-firmware", "hexciri-update-orphan-pkgs", "hexciri-update-pkg-prune", "hexciri-update-restart", "hexciri-update-analyze-logs", "hexciri-show-logo", "hexciri-show-done"]:
    _p = fork + "/bin/" + _name
    _t = read(_p)
    _t = _t.replace("\\e[32m", "$(hexciri-theme-ansi green)")
    _t = _t.replace("\\033[32m", "$(hexciri-theme-ansi green)")
    _t = _t.replace("\\033[0;31m", "$(hexciri-theme-ansi red)")
    _t = _t.replace("\\e[31m", "$(hexciri-theme-ansi red)")
    _t = _t.replace("\\033[31m", "$(hexciri-theme-ansi red)")
    write(_p, _t)
    print("  update: theme-matched green/red in %s" % _name)
PY

# 8b. Single-quote fix, 2026-11-24: step 8 above replaced \e[32m / \e[31m
# with $(hexciri-theme-ansi ...) even inside single-quoted strings, where
# bash never expands $(). hexciri-show-done printed the literal
# "$(hexciri-theme-ansi green)● Done!" and hexciri-update-analyze-logs
# would print the literal on an initramfs failure. Capture the escape in
# a variable first (show-done) and switch the analyze-logs line to
# double quotes. The trap line in hexciri-update is NOT fixed here: a
# trap string is evaluated when it fires, so $() inside it DOES expand.
python3 - "$FORK_OUT" <<'PYEOF8B' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
SQ = chr(39)
# show-done: two printf lines, green and red.
_p = fork + "/bin/hexciri-show-done"
_t = read(_p)
_old_g = "  printf " + SQ + "\\n$(hexciri-theme-ansi green)\u25cf \\033[0m%s" + SQ + ' "$(hexciri-i18n done.success)" >/dev/tty'
_new_g = '  _show_done_color="$(hexciri-theme-ansi green)"\n  printf ' + SQ + "\\n%s\u25cf \\033[0m%s" + SQ + ' "$_show_done_color" "$(hexciri-i18n done.success)" >/dev/tty'
assert _new_g in _t or _old_g in _t, "show-done green line not found: " + repr(_t[-600:])
_t = _t.replace(_old_g, _new_g, 1)
_old_r = "  printf " + SQ + "\\n$(hexciri-theme-ansi red)\u25cf \\033[0m%s" + SQ + ' "$(hexciri-i18n done.failed "$code")" >/dev/tty'
_new_r = '  _show_done_color="$(hexciri-theme-ansi red)"\n  printf ' + SQ + "\\n%s\u25cf \\033[0m%s" + SQ + ' "$_show_done_color" "$(hexciri-i18n done.failed "$code")" >/dev/tty'
assert _new_r in _t or _old_r in _t, "show-done red line not found"
_t = _t.replace(_old_r, _new_r, 1)
write(_p, _t)
print("  update: show-done captures theme colour in a variable (no more literal)")
# analyze-logs: the initramfs line was echo -e '...' (single quotes).
_p = fork + "/bin/hexciri-update-analyze-logs"
_t = read(_p)
_old = "echo -e " + SQ + "$(hexciri-theme-ansi red)Error: Initramfs generation may have failed. Review logs before restart.\\e[0m" + SQ
_new = 'echo -e "$(hexciri-theme-ansi red)Error: Initramfs generation may have failed. Review logs before restart.\\e[0m"'
assert _new in _t or _old in _t, "analyze-logs initramfs line not found"
_t = _t.replace(_old, _new, 1)
write(_p, _t)
print("  update: analyze-logs initramfs line uses double quotes (no more literal)")
PYEOF8B

# 8c. Update section spacing (2026-11-24, Devi: inconsistent blank lines
# between update sections in the 0bbabdb log: 2 blanks after Prune, 3 after
# Orphan, 2 after Mise, 1 everywhere else, 1 trailing at the end). Root
# cause: every section header already prints one leading blank via its
# `\n`, but prune/orphan/mise/aur-pkgs also printed a trailing bare
# `echo`, and hexciri-update-restart printed an unconditional `echo` at
# the top on top of its header's `\n`. Rule: the header's leading `\n`
# is the only separator. The trailing echoes are removed in the rewrites
# above/below; this block fixes restart, the one upstream file in the
# chain: its top blank is now conditional on a service-restart line
# following it, and confirm_reboot prints its own leading blank only
# when it actually prints the reboot-later line (unattended mode), so a
# --reboot-only run with no reboot needed prints nothing at all, no
# trailing blank line at the end of the update.
python3 - "$FORK_OUT" <<'PYEOF8C' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
def must_replace(path, old, new, what, marker=None):
    t = read(path)
    if (marker if marker is not None else new) in t:
        print("  update spacing: " + what + " (already applied, skipping)")
        return
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update spacing: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    "esac\n\necho\nconfirm_reboot() {",
    "esac\n\n# Section spacing (2026-11-24): the old unconditional `echo` here\n"
    "# plus the \"Restarting shell\" header's leading \\n printed two blanks\n"
    "# before it (three after a step that also trailed a blank). A blank is\n"
    "# printed only when a line without its own header follows it: a\n"
    "# service-restart line below, or a reboot prompt from confirm_reboot\n"
    "# (which prints its own leading blank when it speaks).\n"
    "_restart_needs_blank=0\n"
    "for _restart_file in \"$HOME\"/.local/state/hexciri/restart-*-required; do\n"
    "  if [[ -f $_restart_file ]]; then _restart_needs_blank=1; break; fi\n"
    "done\n"
    "if [[ $_restart_needs_blank == \"1\" ]]; then echo; fi\n"
    "confirm_reboot() {",
    "restart top echo is conditional on a service line following")
must_replace(_p,
    "confirm_reboot() {\n  if [[ ${HEXCIRI_UPDATE_UNATTENDED:-0} == \"1\" ]]; then\n    echo \"$(hexciri-i18n update.rebootLater \"$1\" \"hexciri-system reboot\")\"",
    "confirm_reboot() {\n  if [[ ${HEXCIRI_UPDATE_UNATTENDED:-0} == \"1\" ]]; then\n    echo\n    echo \"$(hexciri-i18n update.rebootLater \"$1\" \"hexciri-system reboot\")\"",
    "confirm_reboot prints its own leading blank in unattended mode")
PYEOF8C

# 8d. Restart reloads Hyprland config after the shell restart
# (2026-11-24, Devi 11:07 MST: after the e80264a2 update bootstrap.lua
# emergency came back and a manual hyprctl reload fixed it again. The
# installer reloads Hyprland after placement, but only when the
# installer re-runs; this step runs on EVERY update, even a light-sync
# or up-to-date one, so the running Hyprland always picks up the
# current Lua tree. Best-effort, never fails the update; no-op when
# Hyprland is not running (tty3).)
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
def must_replace(path, old, new, what, marker=None):
    t = read(path)
    if (marker if marker is not None else new) in t:
        print("  update: " + what + " (already applied, skipping)")
        return
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    "  hexciri-restart-shell || true\nfi",
    "  hexciri-restart-shell || true\n"
    "\n"
    "  # Hexciri: reload Hyprland config after the shell restart (2026-11-24,\n"
    "  # Devi: emergency mode kept coming back after every update because\n"
    "  # nothing reloaded Hyprland after the installer replaced\n"
    "  # default/hypr/*.lua; this step only restarted Quickshell, and\n"
    "  # theme-set reloads Hyprland only on a real theme change. Reload\n"
    "  # here too, so EVERY update reloads it, even when the installer\n"
    "  # does not re-run. Best-effort, never fails the update; no-op\n"
    "  # when Hyprland is not running (tty3).\n"
    "  if pgrep -x Hyprland >/dev/null 2>&1 && command -v hexciri-restart-hyprctl >/dev/null 2>&1; then\n"
    "    hexciri-restart-hyprctl && echo \"Hyprland config reloaded (hyprctl reload)\"\n"
    "  fi\nfi",
    "restart reloads Hyprland config after the shell restart",
    marker="# Hexciri: reload Hyprland config after the shell restart")
PY

# 8e. Restart refreshes the stock system-update widget (2026-11-24, Devi:
# its icon stayed on after an update because it only rechecks every 6h /
# on network-online and nothing ever told it to refresh. Its own ShellIpc
# refresh, same pattern as `hexciri-shell hexciri.dock refresh`.
# Best-effort: the widget may not be in the active bar (Nyxiri bar uses
# arch-updates).)
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
def must_replace(path, old, new, what, marker=None):
    t = read(path)
    if (marker if marker is not None else new) in t:
        print("  update: " + what + " (already applied, skipping)")
        return
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    '    hexciri-restart-hyprctl && echo "Hyprland config reloaded (hyprctl reload)"\n  fi\nfi',
    '    hexciri-restart-hyprctl && echo "Hyprland config reloaded (hyprctl reload)"\n  fi\n\n  # Hexciri: tell the stock system-update widget to recheck now\n  # (2026-11-24, Devi: its icon stayed on after an update because it\n  # only rechecks every 6h / on network-online and nothing ever told\n  # it to refresh. Its own ShellIpc refresh, same pattern as\n  # `hexciri-shell hexciri.dock refresh`. Best-effort: the widget may\n  # not be in the active bar (Nyxiri bar uses arch-updates).)\n  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\nfi',
    "restart refreshes the system-update widget after an update",
    marker="# Hexciri: tell the stock system-update widget to recheck now")
PY

# 8f. Restart re-registers GlobalShortcuts after the last Hyprland reload
# (2026-11-24, Devi: Super+Space / Super+Alt+Space were still dead
# after the 6e48f01 update, with the installer smoke check warning
# about it. Root cause is ordering: hexciri-update-restart restarted
# the shell FIRST, then reloaded Hyprland AFTER it, and a Hyprland
# reload drops the shell's GlobalShortcut registrations until the
# shell re-registers them. The update ended with the shell restarted
# before the last reload, so omarchy:menu.root and
# omarchy:ipc.hexciri.dock.apps stayed unregistered until the next
# shell restart or login. Poll for both after the reload; if either
# is still missing, restart the shell once more AFTER the last reload
# and poll again. Polling is the only signal here: Hyprland gives no
# event when a shortcut registers. Best-effort, never fails the update;
# no-op when Hyprland is not running.)
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
def must_replace(path, old, new, what, marker=None):
    t = read(path)
    if (marker if marker is not None else new) in t:
        print("  update: " + what + " (already applied, skipping)")
        return
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    '  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\nfi',
    '  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\n\n  # Hexciri: GlobalShortcuts must be registered AFTER the last Hyprland\n  # reload (2026-11-24, Devi: shell restarted before the reload, reload\n  # dropped omarchy:menu.root / omarchy:ipc.hexciri.dock.apps, update\n  # ended with Super+Space / Super+Alt+Space dead). Poll, restart the\n  # shell once more if either is missing, poll again. Best-effort.\n  if pgrep -x Hyprland >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then\n    _gs_ok=0\n    for _gs_try in 1 2 3 4 5 6 7 8 9 10; do\n      if hyprctl globalshortcuts 2>/dev/null | grep -q \'omarchy:menu.root\' && hyprctl globalshortcuts 2>/dev/null | grep -q \'omarchy:ipc.hexciri.dock.apps\'; then _gs_ok=1; break; fi\n      sleep 0.5\n    done\n    if [[ $_gs_ok == "0" ]]; then\n      hexciri-restart-shell || true\n      for _gs_try in 1 2 3 4 5 6 7 8 9 10; do\n        if hyprctl globalshortcuts 2>/dev/null | grep -q \'omarchy:menu.root\' && hyprctl globalshortcuts 2>/dev/null | grep -q \'omarchy:ipc.hexciri.dock.apps\'; then _gs_ok=1; break; fi\n        sleep 0.5\n      done\n    fi\n    if [[ $_gs_ok == "1" ]]; then echo "GlobalShortcuts registered: Super+Space apps / Super+Alt+Space menu"; else echo "GlobalShortcuts still missing after shell restart (omarchy:menu.root / omarchy:ipc.hexciri.dock.apps; run: hexciri-restart-shell)"; fi\n    unset _gs_ok _gs_try\n  fi\nfi',
    "restart re-registers GlobalShortcuts after the last Hyprland reload")
PY

# 9. pkg-prune: whole-file rewrite (2026-11-24, Devi: Prune package
# cache was missing from hexciri update, see Fix 1 above). Upstream bin
# printed the themed header then ran `sudo paccache -rk2` live, whose
# output is the Omarchy line Devi quoted:
#   Prune package cache
#   ==> finished: 3 packages removed (disk space saved: 83.23 MiB)
# Quiet version: capture paccache, show ONE status line only (the
# finished line, or "Package cache is clean" when it finds no
# candidates). paccache -rk2 keeps 2 versions, the only offline
# downgrade path, and is non-interactive, so no Y/n prompt. A paccache
# failure prints the pruneFailed warning and the update continues.
cat > "$FORK_OUT/bin/hexciri-update-pkg-prune" <<'PRUNE_EOF'
#!/bin/bash

# omarchy:summary=Prune superseded versions from the pacman package cache
# omarchy:requires-sudo=true

set -e

# The cache is the only offline downgrade path, so keep two. Run before the
# packages update and the installed version survives with a spare. paccache
# retains by version order, never by what is installed.
echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.pruneCache)\e[0m"
_prune_log="$(mktemp /tmp/hexciri-pkg-prune.XXXXXX)"
if sudo paccache -rk2 >"$_prune_log" 2>&1; then
  _finished="$(grep -E 'finished:' "$_prune_log" | tail -1 || true)"
  if [[ -n "$_finished" ]]; then
    # "==> finished: 3 packages removed (disk space saved: 83.23 MiB)"
    echo "${_finished#==> }"
  elif grep -qi 'no candidate' "$_prune_log"; then
    echo "Package cache is clean"
  else
    echo "Package cache pruned"
  fi
else
  echo -e "\e[33m$(hexciri-i18n update.pruneFailed)\e[0m" >&2
  cat "$_prune_log" >&2 || true
fi
rm -f "$_prune_log"
PRUNE_EOF
info "  update: hexciri-update-pkg-prune rewritten (quiet: one status line, paccache -rk2)"

# 10. Section consistency (2026-11-24, Devi: Omarchy style, every step
# its own little section with themed header + one-line status).
#   a. orphan-pkgs: was silent when no orphans existed, so the step had
#      no section at all. Now always prints the themed header, then
#      "No orphaned packages" when none. Removal behaviour unchanged:
#      called with -y by hexciri-update, so orphans are removed without
#      a gum prompt; standalone non-tty use still reports and exits.
#   b. mise: ran `mise up` live. Now captured, one status line only.
cat > "$FORK_OUT/bin/hexciri-update-orphan-pkgs" <<'ORPHAN_EOF'
#!/bin/bash

# omarchy:summary=Review and optionally remove orphaned system packages after updates
# omarchy:args=[-y]
# omarchy:examples=hexciri update orphan-pkgs | hexciri update orphan-pkgs -y
# omarchy:requires-sudo=true

set -e

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.orphans)\e[0m"
mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
if (( ${#orphans[@]} == 0 )); then
  echo "No orphaned packages"
  exit 0
fi
printf '  %s\n' "${orphans[@]}"

if [[ ${1:-} != "-y" && ( ! -t 0 || ! -t 1 ) ]]; then
  echo -e "\n$(hexciri-i18n --count "${#orphans[@]}" update.orphansFound "${#orphans[@]}" hexciri-update-orphan-pkgs)"
  exit 0
fi

if [[ ${1:-} != "-y" ]] && ! gum confirm --default=false --affirmative "$(hexciri-i18n common.yes)" --negative "$(hexciri-i18n common.no)" "$(hexciri-i18n --count "${#orphans[@]}" update.removeOrphans "${#orphans[@]}")"; then
  echo -e "\n$(hexciri-i18n update.keepingOrphans)"
  exit 0
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.removingOrphans)\e[0m"
hexciri-pkg-drop "${orphans[@]}"
ORPHAN_EOF
info "  update: hexciri-update-orphan-pkgs rewritten (always a section, one line when none)"

cat > "$FORK_OUT/bin/hexciri-update-mise" <<'MISE_EOF'
#!/bin/bash

# omarchy:summary=Update mise-managed tools

if hexciri-cmd-present mise; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.mise)\e[0m"

  # mise withholds releases younger than its cooldown, so tools stay behind for
  # days after they ship. Running hexciri update is the user asking for current
  # versions now, which is the same call the mup alias makes by hand.
  # Quiet (2026-11-24, Devi): capture `mise up`, show one status line only,
  # like the other sections. Failure still exits non-zero so hexciri-update
  # sets mise_updated=0 and prints the retry hint at the end.
  _mise_log="$(mktemp /tmp/hexciri-mise.XXXXXX)"
  if MISE_MINIMUM_RELEASE_AGE=0 mise up >"$_mise_log" 2>&1; then
    if grep -qi "up to date" "$_mise_log"; then
      echo "All tools are up to date"
    else
      echo "Mise tools updated"
      grep -iE "updated|installed" "$_mise_log" | sed 's/^/  /' || true
    fi
    rm -f "$_mise_log"
  else
    echo "ERROR: mise update failed, output:" >&2
    cat "$_mise_log" >&2
    rm -f "$_mise_log"
    exit 1
  fi
fi
MISE_EOF
info "  update: hexciri-update-mise rewritten (quiet: one status line)"

# Whole-file rewrites: keyring, system-pkgs, pacman guard, available.
# The keyring file: Arch + EndeavourOS keyrings only. No Hexciri keyring
# package, no WKD key, no Hexciri package repo, no Omarchy repo. ARM handling
# dropped: Hexciri machines are x86_64.
cat > "$FORK_OUT/bin/hexciri-update-keyring" <<'KEYRING_EOF'
#!/bin/bash
# Hexciri: refresh Arch + EndeavourOS keyrings only. There is no Hexciri
# keyring package, no WKD key, no Hexciri package repo, no Omarchy repo, so the
# upstream keyring step (which tries to install a Hexciri keyring package
# from the Omarchy repo) cannot work here. ARM keyring handling is dropped
# too: Hexciri machines are x86_64.
set -euo pipefail

keyrings=(archlinux-keyring)
if pacman -Qq endeavouros-keyring >/dev/null 2>&1; then
  keyrings+=(endeavouros-keyring)
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.signingKeys)\e[0m"
# Quiet on purpose (2026-11-24, Devi): pacman-key --populate prints
# "Appending keys..." / "Updating trust database..." and `pacman -Sy
# --needed` prints the db sync lines plus "warning: <keyring> is up to
# date -- skipping" twice and "there is nothing to do". All of that
# reads as errors to a new person when it is really nothing. Capture
# everything, show it only if something actually fails.
sudo pacman-key --populate archlinux endeavouros >/dev/null 2>&1 || sudo pacman-key --populate archlinux >/dev/null 2>&1 || true
_keyring_log="$(mktemp /tmp/hexciri-keyring.XXXXXX)"
if sudo pacman -Sy --needed --noconfirm "${keyrings[@]}" >"$_keyring_log" 2>&1; then
  if grep -qE "upgrading|installing|reinstalling" "$_keyring_log"; then
    echo "Keys updated"
  else
    echo "$(hexciri-i18n update.keysCorrect)"
  fi
else
  echo "ERROR: keyring update failed, output:" >&2
  cat "$_keyring_log" >&2
  rm -f "$_keyring_log"
  exit 1
fi
rm -f "$_keyring_log"
KEYRING_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-keyring"

# The system-pkgs file: pacman directly is the package engine (2026-11-24:
# eos-update --aur is kept only for a standalone interactive run, it has
# no --noconfirm and its yay prompts [Y/n]). pacman -Sy/-Su sync and
# upgrade every repo in /etc/pacman.conf, including [endeavouros], so EOS
# packages update here like any other repo package. The conflict handler
# below is unchanged: it takes over on a failed pacman run.
cat > "$FORK_OUT/bin/hexciri-update-system-pkgs" <<'SYSPKGS_EOF'
#!/bin/bash
# omarchy:summary=Update system packages with pacman
# omarchy:requires-sudo=true
# Hexciri (2026-11-24): the package engine is pacman directly, unattended.
# The start confirm in hexciri-update is the one approval; after it
# HEXCIRI_UPDATE_UNATTENDED=1, so this file never runs eos-update in a
# normal update (eos-update has no --noconfirm flag, and yay inside it
# prompts [Y/n] for e.g. mise). eos-update --aur is kept only for a
# standalone interactive run of this file.
# Flow: db sync quietly (captured, no "is up to date" lines), then
# checkupdates counts pending repo updates; if none, one line
# "System packages are up to date" and no upgrade run at all. If there
# are updates, pacman -Su runs live so the ILoveCandy Pac-Man bar shows,
# then one closing line. A .pacnew in /etc gets one warning line.
set -e

# The conflict handler's last resort: pacman puts its questions to the person
# running the update instead of answering them itself. Nothing here may capture
# a stream, because an upgrade without --noconfirm prompts on stderr. The
# handler has already said why, so no heading here either.
if [[ ${HEXCIRI_UPDATE_CONFLICT:-} == 1 && ${HEXCIRI_UPDATE_INTERACTIVE:-} == 1 ]]; then
  exec hexciri-update-pacman -Syu --overwrite '/usr/share/hexciri/*'
fi

# Standalone interactive run only: eos-update --aur. In a normal
# `hexciri update` UNATTENDED is already 1 (set after the start confirm),
# so this branch never runs there and its banner never prints.
if [[ ${HEXCIRI_UPDATE_UNATTENDED:-0} != "1" ]] && command -v eos-update >/dev/null 2>&1; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.systemPackages) (eos-update --aur)\e[0m"
  if eos-update --aur; then
    # Tell the aur-pkgs step the AUR is already done, for this run only.
    [[ -n ${HEXCIRI_UPDATE_EOS_MARKER:-} ]] && : > "$HEXCIRI_UPDATE_EOS_MARKER"
    exit 0
  fi
  echo "eos-update --aur failed, falling back to pacman (review /tmp/hexciri-update.log for details)." >&2
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.systemPackages)\e[0m"

# Db sync, quiet: capture it, the "is up to date" lines are not shown.
_sync_log="$(mktemp /tmp/hexciri-syspkgs-sync.XXXXXX)"
if ! LC_ALL=C hexciri-update-pacman -Sy --noconfirm >"$_sync_log" 2>&1; then
  echo "ERROR: package database sync failed, output:" >&2
  cat "$_sync_log" >&2
  rm -f "$_sync_log"
  exit 1
fi
rm -f "$_sync_log"

# Nothing pending: one line, no upgrade run, no "there is nothing to do".
# checkupdates reads the just-synced db. Its exit codes (pacman-contrib):
# 0 = up to date, 2 = updates available, 1 = error. The old code treated
# ANY non-zero exit as "assume 1 pending", so an exit-2 run was reported
# as 1, and an exit-1 error run was reported as 1 even when pacman then
# found nothing to do ("System packages updated (1 package(s))" after
# "there is nothing to do", 2026-11-24). Count the lines whatever the
# exit code is; only on a real error fall back to pacman -Qu.
_pending_file="$(mktemp /tmp/hexciri-syspkgs-pending.XXXXXX)"
_checkupdates_status=0
checkupdates >"$_pending_file" 2>/dev/null || _checkupdates_status=$?
_pending="$(wc -l < "$_pending_file" | tr -d ' ')"
if [[ "$_checkupdates_status" == "1" ]]; then
  _pending="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
fi
_pending_list="$(cat "$_pending_file" 2>/dev/null || true)"
rm -f "$_pending_file"
if [[ "$_pending" == "0" ]]; then
  echo "System packages are up to date"
  exit 0
fi

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT

# EOS packages (2026-11-24, Devi: does dropping eos-update skip EOS
# pkgs?): no. pacman -Sy / -Su sync and upgrade EVERY repo in
# /etc/pacman.conf, and on EndeavourOS that includes [endeavouros]
# (eos-update, eos-hooks, endeavouros-keyring, welcome, ...). checkupdates
# counts those entries too, so an EOS package update is a pending update
# like any other. eos-update's other steps are covered elsewhere in this
# pipeline: keyring refresh (hexciri-update-keyring), free-space check
# (hexciri-update-requires-free-space), .pacnew check (below), AUR
# (hexciri-update-aur-pkgs). If the EOS repo is ever missing from
# pacman.conf, say so instead of silently skipping EOS pkgs.
if ! pacman -Sl endeavouros >/dev/null 2>&1; then
  echo "Warning: endeavouros repo not found in pacman config, EOS packages will not update" >&2
fi

# /usr/share/hexciri is wholly Hexciri's; files can land there unowned and would
# otherwise abort the upgrade. Packaged content wins there.
#
# Progress bars stay on stdout (ILoveCandy Pac-Man bar). Errors are on stderr,
# kept for the conflict handler below; LC_ALL=C is what keeps them parseable
# in any locale. stdout is tee'd to a log so the real upgrade count can be
# read back: _pending is only a pre-flight count, and pacman can still find
# nothing to do (db race, IgnorePkg, a package checkupdates counted but
# pacman skips). Never claim "updated (1)" when nothing was upgraded.
_su_log="$(mktemp /tmp/hexciri-syspkgs-su.XXXXXX)"
LC_ALL=C hexciri-update-pacman -Su --noconfirm \
  --overwrite '/usr/share/hexciri/*' 2>"$errors" | tee "$_su_log"
_su_status="${PIPESTATUS[0]}"
if [[ "$_su_status" == "0" ]]; then
  cat "$errors" >&2
  _upgraded="$(grep -cE '(\\([0-9]+/[0-9]+\\) )?upgrading ' "$_su_log" 2>/dev/null || true)"
  _upgraded="$(echo "$_upgraded" | tr -d ' ')"
  # The 2026-11-24 log showed the upgrade line without a (n/n) prefix
  # ("upgrading flex..."), so the old ^(n/n) pattern counted 0 and
  # the update claimed "System packages are up to date" after a real
  # upgrade (flex 2.7.1 -> 2.7.6). If the count is still 0 but pacman
  # did not say "there is nothing to do", trust the pre-flight pending
  # count instead of claiming up to date.
  if [[ "$_upgraded" == "0" ]] && ! grep -q 'there is nothing to do' "$_su_log" 2>/dev/null; then
    _upgraded="$_pending"
  fi
  # DB race / mirror lag retry (2026-11-24, Devi: zxing-cpp 3.2.0-1
  # listed by checkupdates, pacman -Su said "there is nothing to do").
  # checkupdates syncs its own temp DB, pacman -Su uses the main DB
  # synced seconds earlier: the two syncs can hit different geo-mirror
  # backends, and a package built ~90 min earlier can be on one and
  # not the other. One forced re-sync (-Syy, which re-downloads the
  # DBs instead of trusting the "already up to date" shortcut and can
  # land on a fresher mirror) + a re-count against the main DB (the DB
  # -Su actually uses), then a second -Su, before giving up. -Syy
  # here is safe: -Su runs immediately after, in this same script,
  # so there is no -Sy-without--Su window.
  if [[ "$_upgraded" == "0" ]] && [[ "$_pending" != "0" ]]; then
    _retry_log="$(mktemp /tmp/hexciri-syspkgs-retry.XXXXXX)"
    if LC_ALL=C hexciri-update-pacman -Syy --noconfirm >"$_retry_log" 2>&1; then
      _requ="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$_requ" != "0" ]]; then
        _su_log2="$(mktemp /tmp/hexciri-syspkgs-su2.XXXXXX)"
        LC_ALL=C hexciri-update-pacman -Su --noconfirm \
          --overwrite '/usr/share/hexciri/*' 2>"$errors" | tee "$_su_log2"
        _su2_status="${PIPESTATUS[0]}"
        if [[ "$_su2_status" == "0" ]]; then
          _upgraded="$(grep -cE '(\\([0-9]+/[0-9]+\\) )?upgrading ' "$_su_log2" 2>/dev/null || true)"
          _upgraded="$(echo "$_upgraded" | tr -d ' ')"
          if [[ "$_upgraded" == "0" ]] && ! grep -q 'there is nothing to do' "$_su_log2" 2>/dev/null; then
            _upgraded="$_requ"
          fi
        fi
        rm -f "$_su_log2"
      fi
    fi
    rm -f "$_retry_log"
  fi
  rm -f "$_su_log"
  _pacnew="$(find /etc -name '*.pacnew' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$_pacnew" != "0" ]]; then
    echo "Note: $_pacnew .pacnew file(s) in /etc need review (run pacdiff)" >&2
  fi
  if [[ "$_upgraded" == "0" ]]; then
    # Never claim up to date when checkupdates counted something and
    # pacman upgraded nothing: that is the zxing-cpp case above, and
    # "up to date" hides a real pending package behind a stale badge.
    if [[ "$_pending" != "0" ]]; then
      echo "Note: checkupdates listed $_pending update(s) but pacman found nothing to upgrade (mirror DB lag?)"
      if [[ -n "$_pending_list" ]]; then
        printf '%s\n' "$_pending_list"
      fi
      echo "Re-run hexciri update later; the badge clears once the mirror catches up."
    else
      echo "System packages are up to date"
    fi
  else
    echo "System packages updated ($_upgraded package(s))"
  fi
  exit 0
fi
rm -f "$_su_log"
cat "$errors" >&2

# The handler takes it from here: it clears files pacman doesn't own yet and
# runs this again, and puts a package conflict to whoever started the update.
# Anything else, including a second failure, is for a human.
[[ ${HEXCIRI_UPDATE_RETRY:-} != 1 ]] || exit 1
# exec, so the EXIT trap above does not fire and the handler can still read the
# report. It takes over deleting it.
exec env HEXCIRI_UPDATE_CONFLICT=1 hexciri-update-system-pkgs-when-conflicted "$errors"

SYSPKGS_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-system-pkgs"

# The pacman guard file: no-op. The guard as shipped blocks any direct
# pacman call, which is exactly what eos-update and yay do, so it would
# break every update. There is no Hexciri repo to protect, no
# linux-omarchy kernel, no keyring pinning to defend.
cat > "$FORK_OUT/bin/hexciri-update-pacman-guard" <<'GUARD_EOF'
#!/bin/bash
# hexciri-update-pacman-guard: no-op in Hexciri. The guard as shipped blocks
# any direct pacman call, which is exactly what eos-update and yay do, so
# it would break every update. There is no Hexciri repo to protect, no
# linux-omarchy kernel, no keyring pinning to defend.
exit 0
GUARD_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-pacman-guard"

# The available file: upstream only counted the omarchy package after
# first-update, which Hexciri does not ship, so it always reported up to
# date. Now any pending checkupdates entry counts, plus a git checkout
# behind count when a dev checkout exists at ~/.local/opt/hexciri (v1 dev
# path) or ~/.local/opt/hexciri-nyx (v2 git sync); the installer sha
# check lives in hexciri-update-hexciri, not here).
cat > "$FORK_OUT/bin/hexciri-update-available" <<'AVAIL_EOF'
#!/bin/bash
# hexciri-update-available: check whether Hexciri / system updates are available.
# Exit 0 when updates exist (and list them), exit 1 when up to date.
# Used by the bar update indicator and by hexciri-update-status.
set -euo pipefail

updates=()
# Hexciri (2026-11-24, Devi: stock system-update icon stayed on after an
# update): upstream omarchy-update-available fetched before rev-list, this
# rewrite did not, so behind was counted against a stale upstream ref.
# Fetch first (best-effort, timeout 10), and only count the v1 dev
# checkout (~/.local/opt/hexciri) when the v2 nyx checkout does not
# exist: a stale v1 checkout behind its upstream lit the icon forever.
_checkouts=("$HOME/.local/opt/hexciri-nyx" "$HOME/.local/opt/hexciri")
if [[ ! -d ${_checkouts[0]}/.git ]]; then
  _checkouts=("${_checkouts[1]}")
else
  _checkouts=("${_checkouts[0]}")
fi
for _checkout in "${_checkouts[@]}"; do
  if [[ -d $_checkout/.git ]]; then
    upstream="$(git -C "$_checkout" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n $upstream ]]; then
      GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$_checkout" fetch --quiet 2>/dev/null || true
      behind="$(git -C "$_checkout" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
      if (( behind > 0 )); then
        commit_label=commits
        (( behind == 1 )) && commit_label=commit
        updates+=("hexciri-dev-checkout $behind new $commit_label on $upstream")
      fi
    fi
  fi
done
unset _checkout _checkouts

mapfile -t _pending < <(checkupdates --nocolor 2>/dev/null || true)
updates+=("${_pending[@]}")

if (( ${#updates[@]} > 0 )); then
  printf '%s\n' "${updates[@]}"
  exit 0
else
  echo "Hexciri is up to date"
  exit 1
fi
AVAIL_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-available"

# Analyze-logs: dracut (EndeavourOS default, not mkinitcpio) plus a failed
# transaction, in the same plain-echo style as the existing checks.
# Guarded: an unconditional append would duplicate the block on re-run.
if ! grep -qF 'dracut: (failed|error)' "$FORK_OUT/bin/hexciri-update-analyze-logs" 2>/dev/null; then
cat >> "$FORK_OUT/bin/hexciri-update-analyze-logs" <<'ANALYZE_EOF'

# dracut (EndeavourOS default, not mkinitcpio): a failed initramfs rebuild
# shows as dracut errors in the log. Also surface a failed transaction.
if grep -qiE "dracut: (failed|error)|dracut:.*failed" "$update_log"; then
  echo -e "$(hexciri-theme-ansi red)Error: dracut reported errors during the update. Review logs before restart.\e[0m"
  echo
fi
if grep -q "error: failed to commit transaction" "$update_log"; then
  echo -e "$(hexciri-theme-ansi red)Error: pacman transaction failed. Review /tmp/hexciri-update.log before retrying.\e[0m"
  echo
fi
ANALYZE_EOF
else
  info "  update: dracut log scan already in hexciri-update-analyze-logs, skipping"
fi

# Every patched update script must still parse.
for _f in hexciri-update hexciri-update-system-pkgs hexciri-update-keyring hexciri-update-aur-pkgs hexciri-update-mise hexciri-update-available hexciri-update-boot hexciri-update-analyze-logs hexciri-update-hexciri hexciri-update-pacman-guard hexciri-update-confirm hexciri-theme-ansi; do
  bash -n "$FORK_OUT/bin/$_f" || die "bash -n failed on patched $_f"
done
unset _f
info "  update: hexciri-update patched (eos-update --aur, no snapshot, Hexciri self-update, mise, dracut log scan)"
