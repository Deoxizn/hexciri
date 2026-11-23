#!/usr/bin/env bash
# Hexiri 2.0 Phase 1 fork and rename script
# Source: omacom/omarchy, branch quattro, pinned commit 94a8c3c3321129fae87a329947711355897e69fd (2026-11-23)
# Target: Deoxizn/hexciri, branch nyx. Forked files live under v2/ in that repo.
# Install targets after this fork: /usr/share/hexciri, ~/.config/hexciri, ~/.local/state/hexciri
#
# Hard rule: no file named omarchy in the Hexiri repo. Files, paths, and CLI are renamed to hexciri.
# Theme format (colors.toml + shell.toml) stays Omarchy compatible.
# Plugin format (manifest.json + BarWidget.qml + scripts/ + shell.json layout) stays Omarchy compatible.
# Compatibility is by runtime alias in code, not by a file named omarchy.
# A plugin asking for omarchy.bar gets hexciri.bar, omarchy-shell IPC gets hexciri-shell,
# and OMARCHY_PATH is a runtime alias variable set to the same value as HEXCIRI_PATH.
# Do NOT create a file named omarchy as a shim.
# This alias is the compatibility layer. A breaking rename with no alias would break plugin support,
# including upstream Omarchy plugins and Nyxiri pizza.dirty.* plugins.
#
# Phase 1 only: extract the listed subsets verbatim, then rename. No Phase 2 Hexciri edits.
# Stock Lua only for Phase 1. Lua double backslashes are preserved byte-safe:
# a regex dot is \\. in Lua, and this script never collapses \\ to \.
# It uses Python byte replacement, not sed, for content rewrites.
#
# Inventory corrections, verified 2026-11-23 at pinned commit:
# - No shell/plugins/launcher/ directory. Launcher code lives in shell/plugins/menu/ and shell/plugins/dock/.
# - No bare bin/omarchy-plugin. Subcommands are omarchy-plugin-add, -catalog, -clone, -disable, -enable, -list, -remove, -update, -validate.
# - No bin/omarchy-qmlcache-purge.
# - Shell config is config/omarchy/shell.json, not config/shell.json.
# - themes/ has 23 directories at this commit.
# - default/hypr/ has 29 top-level Lua files, plus apps/, bindings/, toggles/ subdirs.
#
# Usage:
#   v2/fork-shell.sh [SOURCE_DIR_OR_TARBALL] [OUTPUT_DIR]
#   v2/fork-shell.sh ./omarchy ./v2
#   v2/fork-shell.sh /tmp/omarchy-94a8c3c3321129fae87a329947711355897e69fd.tar.gz ./v2
# SOURCE defaults to ./omarchy. OUTPUT defaults to ./v2.
# The script is idempotent: it wipes and rebuilds OUTPUT on every run.

set -euo pipefail

PINNED_SHA="94a8c3c3321129fae87a329947711355897e69fd"
PINNED_BRANCH="quattro"
PINNED_DATE="2026-11-23"
SOURCE="${1:-./omarchy}"
OUTPUT="${2:-./v2}"

WORKDIR=""
SRC_RESOLVED=""

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[fork-shell] %s\n' "$*" >&2
}

warn() {
  printf '[fork-shell] WARNING: %s\n' "$*" >&2
}

cleanup() {
  if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

check_deps() {
  info "[1/9] Checking dependencies"
  for cmd in git python3 tar grep find cp mkdir rm; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
  info "Dependencies OK: git, python3, tar, grep, find, cp"
}

resolve_source() {
  info "[2/9] Resolving source: $SOURCE"
  if [ -f "$SOURCE" ]; then
    case "$SOURCE" in
      *.tar.gz | *.tgz | *.tar)
        WORKDIR="$(mktemp -d)"
        info "Extracting tarball to $WORKDIR"
        tar -xf "$SOURCE" -C "$WORKDIR"
        SRC_RESOLVED="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        if [ -z "$SRC_RESOLVED" ]; then
          SRC_RESOLVED="$WORKDIR"
        fi
        ;;
      *)
        die "SOURCE is a file but not a .tar, .tar.gz, or .tgz tarball: $SOURCE"
        ;;
    esac
  elif [ -d "$SOURCE" ]; then
    SRC_RESOLVED="$SOURCE"
  else
    die "SOURCE not found as a directory or tarball: $SOURCE"
  fi
  info "Source resolved to: $SRC_RESOLVED"
}

verify_sha() {
  info "[3/9] Verifying pinned commit $PINNED_SHA ($PINNED_BRANCH, $PINNED_DATE)"
  if [ -d "$SRC_RESOLVED/.git" ]; then
    local actual branch
    actual="$(git -C "$SRC_RESOLVED" rev-parse HEAD)"
    branch="$(git -C "$SRC_RESOLVED" rev-parse --abbrev-ref HEAD || true)"
    if [ "$actual" != "$PINNED_SHA" ]; then
      die "commit mismatch: expected $PINNED_SHA, got $actual (branch $branch)"
    fi
    if [ "$branch" != "$PINNED_BRANCH" ]; then
      warn "branch is $branch, expected $PINNED_BRANCH, but commit SHA matches, continuing"
    fi
    info "Commit verified by git: $actual"
  elif [ -f "$SRC_RESOLVED/COMMIT_SHA" ]; then
    local actual
    actual="$(tr -d '[:space:]' < "$SRC_RESOLVED/COMMIT_SHA")"
    if [ "$actual" != "$PINNED_SHA" ]; then
      die "COMMIT_SHA mismatch: expected $PINNED_SHA, got $actual"
    fi
    info "Commit verified by COMMIT_SHA file: $actual"
  elif [[ "$SOURCE" == *"$PINNED_SHA"* ]]; then
    info "Tarball filename contains pinned SHA, accepting as verified tarball source"
  else
    die "cannot verify commit SHA: no .git dir, no COMMIT_SHA file, and tarball name does not contain $PINNED_SHA. Clone omacom/omarchy branch $PINNED_BRANCH at $PINNED_SHA and rerun."
  fi
}

copy_subset() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    info "Copied: $label ($src -> $dest)"
  else
    die "required subset missing in source: $label ($src)"
  fi
}

copy_optional_file() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    info "Copied: $label ($src -> $dest)"
    return 0
  fi
  return 1
}

copy_optional_path() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    info "Copied: $label ($src -> $dest)"
    return 0
  fi
  return 1
}

is_allowed_bin() {
  local name="$1"
  case "$name" in
    launch-shell | theme-set | theme-set-templates | plugin-add | plugin-catalog | plugin-clone | plugin-disable | plugin-enable | plugin-list | plugin-remove | plugin-update | plugin-validate | bar | bar-text-color | shell | shell-config | migrate | migrate-notify | hook | hook-install | \
      refresh-hyprland | hyprland-reload-guard | notification-send | menu | menu-clipboard | menu-emoji | menu-emoji-insert | menu-file | menu-herdr-keybindings | menu-images | menu-input | menu-keybindings | menu-plugin | menu-region-formats | menu-select | menu-share | menu-timezone | menu-tmux-keybindings | \
      provision-user | provision-first-run | provision-hardware | provision-owner | reinstall-configs | reinstall | reinstall-pkgs | version | version-branch | version-channel | version-pkgs | update | update-* | launch-*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_subsets() {
  info "[4/9] Copying only the listed Phase 1 subsets (everything else is skipped by design)"
  info "Skipped: apps/GUI preinstalls, Limine/UKI, snapper/btrfs, Plymouth, LUKS scripts, Docker, AI agents, omarchy-upgrade-to-quattro, channel/keyring/mirror scripts, pacman guard hook, upstream migrations (migration runner mechanism only, no upstream migrations)"
  rm -rf "$OUTPUT"
  mkdir -p "$OUTPUT"

  # Whole Quickshell shell: bar, menu, dock, notifications, osd, lock, polkit, clipboard, background, services, panels
  # Note: there is no shell/plugins/launcher/ at this commit. Launcher code lives in menu/ and dock/.
  copy_subset "$SRC_RESOLVED/shell" "$OUTPUT/shell" "shell/"

  # All Lua for Hyprland, and user Hyprland templates
  copy_subset "$SRC_RESOLVED/default/hypr" "$OUTPUT/default/hypr" "default/hypr/"
  copy_subset "$SRC_RESOLVED/config/hypr" "$OUTPUT/config/hypr" "config/hypr/"

  # Shell layout config: verified location is config/omarchy/shell.json
  if ! copy_optional_file "$SRC_RESOLVED/config/omarchy/shell.json" "$OUTPUT/config/shell.json" "config/omarchy/shell.json"; then
    if ! copy_optional_file "$SRC_RESOLVED/config/shell.json" "$OUTPUT/config/shell.json" "config/shell.json"; then
      copy_optional_file "$SRC_RESOLVED/default/shell.json" "$OUTPUT/config/shell.json" "default/shell.json" || die "required subset missing in source: config/omarchy/shell.json"
    fi
  fi

  # Menu config, renamed to hexciri names
  mkdir -p "$OUTPUT/default/hexciri"
  if ! copy_optional_file "$SRC_RESOLVED/default/omarchy/omarchy-menu.jsonc" "$OUTPUT/default/hexciri/hexciri-menu.jsonc" "default/omarchy/omarchy-menu.jsonc"; then
    copy_optional_file "$SRC_RESOLVED/default/hexciri-menu.jsonc" "$OUTPUT/default/hexciri/hexciri-menu.jsonc" "default/hexciri-menu.jsonc" || warn "omarchy-menu.jsonc not found in source, continuing without it"
  fi
  if ! copy_optional_file "$SRC_RESOLVED/default/omarchy/launcher.hides" "$OUTPUT/default/hexciri/launcher.hides" "default/omarchy/launcher.hides"; then
    if ! copy_optional_file "$SRC_RESOLVED/default/launcher.hides" "$OUTPUT/default/hexciri/launcher.hides" "default/launcher.hides"; then
      copy_optional_file "$SRC_RESOLVED/launcher.hides" "$OUTPUT/default/hexciri/launcher.hides" "launcher.hides" || warn "launcher.hides not found in source, continuing without it"
    fi
  fi

  # All themes, colors.toml + shell.toml, verbatim except path renames applied later. 23 themes at pinned commit.
  copy_subset "$SRC_RESOLVED/themes" "$OUTPUT/themes" "themes/"

  # Bash env bootstrap and envs, renamed by the rename step below
  if ! copy_optional_path "$SRC_RESOLVED/default/bash/env-bootstrap" "$OUTPUT/default/bash/env-bootstrap" "default/bash/env-bootstrap"; then
    warn "default/bash/env-bootstrap not found in source, continuing without it"
  fi
  if ! copy_optional_path "$SRC_RESOLVED/default/bash/envs" "$OUTPUT/default/bash/envs" "default/bash/envs"; then
    warn "default/bash/envs not found in source, continuing without it"
  fi

  # Only the bin/ scripts the shell actually calls
  info "Copying allowed bin/ scripts only"
  mkdir -p "$OUTPUT/bin"
  local copied_bin=0
  local skipped_bin=0
  local src_file base stripped dest_name
  for src_file in "$SRC_RESOLVED"/bin/*; do
    [ -e "$src_file" ] || continue
    [ -f "$src_file" ] || continue
    base="$(basename "$src_file")"
    stripped="${base#omarchy-}"
    stripped="${stripped#omarchy_}"
    if is_allowed_bin "$stripped"; then
      dest_name="hexciri-$stripped"
      cp -a "$src_file" "$OUTPUT/bin/$dest_name"
      copied_bin=$((copied_bin + 1))
      info "Copied bin: $base -> bin/$dest_name"
    else
      skipped_bin=$((skipped_bin + 1))
      info "Skipped bin (not called by shell): $base"
    fi
  done
  info "Bin copy done: $copied_bin copied, $skipped_bin skipped"
  if [ "$copied_bin" -eq 0 ]; then
    die "no allowed bin/ scripts found in source bin/, refusing to continue with an empty bin/"
  fi
  chmod +x "$OUTPUT"/bin/* 2>/dev/null || true

  for banned in apps limine snapper plymouth docker; do
    if [ -e "$OUTPUT/$banned" ]; then
      die "banned subset leaked into output: $OUTPUT/$banned"
    fi
  done
  info "Subset copy complete"
}

rename_files() {
  info "[5/9] Renaming files and directories: omarchy -> hexciri"
  python3 - "$OUTPUT" <<'PY'
import os
import sys

root = sys.argv[1]
renamed = 0
for dirpath, dirnames, filenames in os.walk(root, topdown=False):
    for name in filenames + dirnames:
        if "omarchy" in name.lower():
            old = os.path.join(dirpath, name)
            new_name = name.replace("omarchy", "hexciri").replace("Omarchy", "Hexciri").replace("OMARCHY", "HEXCIRI")
            new = os.path.join(dirpath, new_name)
            if old != new:
                os.rename(old, new)
                renamed += 1
                print("Renamed: %s -> %s" % (old, new))
print("Files and dirs renamed: %d" % renamed)
PY
  info "File and directory rename complete"
}

rewrite_contents() {
  info "[6/9] Rewriting contents with rename map (Python byte replacement, Lua safe)"
  info "Lua safety: replacements are exact byte matches only, so \\\\ in Lua stays \\\\ and is never collapsed to \\"
  python3 - "$OUTPUT" <<'PY'
import os
import sys

root = sys.argv[1]

replacements = [
    (b"/usr/share/omarchy", b"/usr/share/hexciri"),
    (b"$HOME/.config/omarchy", b"$HOME/.config/hexciri"),
    (b"${HOME}/.config/omarchy", b"${HOME}/.config/hexciri"),
    (b"~/.config/omarchy", b"~/.config/hexciri"),
    (b"~/.local/state/omarchy", b"~/.local/state/hexciri"),
    (b"~/.local/share/omarchy", b"~/.local/share/hexciri"),
    (b".config/omarchy", b".config/hexciri"),
    (b".local/state/omarchy", b".local/state/hexciri"),
    (b".local/share/omarchy", b".local/share/hexciri"),
    (b"omarchy-shell", b"hexciri-shell"),
    (b"omarchy-theme-set", b"hexciri-theme-set"),
    (b"omarchy-launch-", b"hexciri-launch-"),
    (b"omarchy-menu", b"hexciri-menu"),
    (b"omarchy.lua", b"hexciri.lua"),
    (b"omarchy/", b"hexciri/"),
    (b'"omarchy"', b'"hexciri"'),
    (b"'omarchy'", b"'hexciri'"),
    (b"OMARCHY_PATH", b"HEXCIRI_PATH"),
    (b"OMARCHY_", b"HEXCIRI_"),
    (b"omarchy.bar", b"hexciri.bar"),
    (b"omarchy.menu", b"hexciri.menu"),
    (b"omarchy.workspaces", b"hexciri.workspaces"),
    (b"omarchy.clock", b"hexciri.clock"),
    (b"omarchy.power", b"hexciri.power"),
    (b"omarchy.audio", b"hexciri.audio"),
    (b"omarchy.network", b"hexciri.network"),
    (b"omarchy.bluetooth", b"hexciri.bluetooth"),
    (b"omarchy.weather", b"hexciri.weather"),
    (b"omarchy.notifications", b"hexciri.notifications"),
    (b"omarchy.launcher", b"hexciri.launcher"),
    (b"omarchy.lock", b"hexciri.lock"),
    (b"omarchy.osd", b"hexciri.osd"),
    (b"omarchy.clipboard", b"hexciri.clipboard"),
    (b"omarchy.background", b"hexciri.background"),
    (b"omarchy.", b"hexciri."),
]

skip_exts = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".ttf", ".otf", ".woff", ".woff2", ".mp4", ".zip", ".gz"}
changed_files = 0
total_files = 0
for dirpath, dirnames, filenames in os.walk(root):
    for name in filenames:
        path = os.path.join(dirpath, name)
        ext = os.path.splitext(name)[1].lower()
        if ext in skip_exts:
            continue
        with open(path, "rb") as f:
            data = f.read()
        total_files += 1
        if b"\x00" in data:
            continue
        new_data = data
        for old, new in replacements:
            if old in new_data:
                new_data = new_data.replace(old, new)
        if new_data != data:
            with open(path, "wb") as f:
                f.write(new_data)
            changed_files += 1
print("Content rewrite: %d files scanned, %d files changed" % (total_files, changed_files))
PY
  info "Content rewrite complete"
  info "Renames applied: /usr/share/omarchy -> /usr/share/hexciri, ~/.config/omarchy -> ~/.config/hexciri, ~/.local/state/omarchy -> ~/.local/state/hexciri, ~/.local/share/omarchy -> ~/.local/share/hexciri, OMARCHY_PATH -> HEXCIRI_PATH, omarchy.bar etc -> hexciri.bar etc, omarchy-shell -> hexciri-shell, omarchy-theme-set -> hexciri-theme-set, omarchy-launch-* -> hexciri-launch-*, default/hypr/omarchy.lua -> default/hypr/hexciri.lua, config/hypr/hyprland.lua env fallback updated by the same map"
}

generate_compat() {
  info "[7/9] Generating compatibility alias files (no file named omarchy is created)"
  mkdir -p "$OUTPUT/default/hypr" "$OUTPUT/bin"

  cat > "$OUTPUT/default/hypr/hexciri-compat.lua" <<'EOF'
-- hexciri-compat.lua
-- Compatibility layer for Hexiri 2.0 Phase 1.
-- Legacy paths /usr/share/omarchy and ~/.config/omarchy resolve to /usr/share/hexciri and ~/.config/hexciri.
-- This alias table is the compatibility layer. A breaking rename with no alias would break plugin support,
-- including upstream Omarchy plugins and Nyxiri pizza.dirty.* plugins, so keep this table.
-- Plugin ids below are the built-in ids. Nyxiri ids (pizza.dirty.*) are not renamed and pass through unchanged.
local aliases = {
  ["omarchy.bar"] = "hexciri.bar",
  ["omarchy.menu"] = "hexciri.menu",
  ["omarchy.workspaces"] = "hexciri.workspaces",
  ["omarchy.clock"] = "hexciri.clock",
  ["omarchy.power"] = "hexciri.power",
  ["omarchy.audio"] = "hexciri.audio",
  ["omarchy.network"] = "hexciri.network",
  ["omarchy.bluetooth"] = "hexciri.bluetooth",
  ["omarchy.weather"] = "hexciri.weather",
  ["omarchy.notifications"] = "hexciri.notifications",
  ["omarchy.launcher"] = "hexciri.launcher",
  ["omarchy.lock"] = "hexciri.lock",
  ["omarchy.osd"] = "hexciri.osd",
  ["omarchy.clipboard"] = "hexciri.clipboard",
  ["omarchy.background"] = "hexciri.background",
  ["omarchy-shell"] = "hexciri-shell",
}

local function resolve_plugin(id)
  return aliases[id] or id
end

local function resolve_shell(name)
  if name == "omarchy-shell" then
    return "hexciri-shell"
  end
  return name
end

return {
  aliases = aliases,
  resolve_plugin = resolve_plugin,
  resolve_shell = resolve_shell,
}
EOF

  cat > "$OUTPUT/bin/hexciri-compat.sh" <<'EOF'
#!/usr/bin/env bash
# hexciri-compat.sh
# Compatibility layer for Hexiri 2.0 Phase 1. Source this file from hexciri-launch-shell and env-bootstrap.
# Legacy paths /usr/share/omarchy and ~/.config/omarchy resolve to /usr/share/hexciri and ~/.config/hexciri.
# This alias table is the compatibility layer. A breaking rename with no alias would break plugin support,
# including upstream Omarchy plugins and Nyxiri pizza.dirty.* plugins, so keep this table.
# OMARCHY_PATH below is a runtime alias variable set to the same value as HEXCIRI_PATH, not a file.
# Do not create a file named omarchy as a shim.
if [ -z "${HEXCIRI_PATH:-}" ]; then
  HEXCIRI_PATH="/usr/share/hexciri"
fi
export HEXCIRI_PATH
export OMARCHY_PATH="$HEXCIRI_PATH"

declare -A HEXCIRI_PLUGIN_ALIASES=(
  [omarchy.bar]=hexciri.bar
  [omarchy.menu]=hexciri.menu
  [omarchy.workspaces]=hexciri.workspaces
  [omarchy.clock]=hexciri.clock
  [omarchy.power]=hexciri.power
  [omarchy.audio]=hexciri.audio
  [omarchy.network]=hexciri.network
  [omarchy.bluetooth]=hexciri.bluetooth
  [omarchy.weather]=hexciri.weather
  [omarchy.notifications]=hexciri.notifications
  [omarchy.launcher]=hexciri.launcher
  [omarchy.lock]=hexciri.lock
  [omarchy.osd]=hexciri.osd
  [omarchy.clipboard]=hexciri.clipboard
  [omarchy.background]=hexciri.background
  [omarchy-shell]=hexciri-shell
)

hexciri_resolve_plugin() {
  local id="$1"
  printf '%s\n' "${HEXCIRI_PLUGIN_ALIASES[$id]:-$id}"
}

hexciri_resolve_shell() {
  if [ "${1:-}" = "omarchy-shell" ]; then
    printf '%s\n' "hexciri-shell"
  else
    printf '%s\n' "${1:-}"
  fi
}
EOF
  chmod +x "$OUTPUT/bin/hexciri-compat.sh"
  info "Generated: default/hypr/hexciri-compat.lua"
  info "Generated: bin/hexciri-compat.sh"
}

verify_no_omarchy_files() {
  info "[8/9] Verifying no file under the output tree is named omarchy"
  local bad
  bad="$(find "$OUTPUT" -iname '*omarchy*' -print || true)"
  if [ -n "$bad" ]; then
    printf 'ERROR: files or dirs still named omarchy remain:\n%s\n' "$bad" >&2
    exit 1
  fi
  info "PASS: no file or dir named omarchy under $OUTPUT"
}

verify_no_omarchy_paths() {
  info "[8/9] Verifying no legacy install paths remain outside alias map comments"
  local bad_paths compat_bad non_comment
  bad_paths="$(grep -R -n -I -e '/usr/share/omarchy' -e '\.config/omarchy' -e '\.local/state/omarchy' -e '\.local/share/omarchy' "$OUTPUT" --exclude='hexciri-compat.*' || true)"
  if [ -n "$bad_paths" ]; then
    printf 'ERROR: legacy Omarchy paths remain outside alias files:\n%s\n' "$bad_paths" >&2
    exit 1
  fi
  compat_bad="$(grep -R -n -I -e '/usr/share/omarchy' -e '\.config/omarchy' -e '\.local/state/omarchy' -e '\.local/share/omarchy' "$OUTPUT" --include='hexciri-compat.*' || true)"
  if [ -n "$compat_bad" ]; then
    non_comment="$(printf '%s\n' "$compat_bad" | grep -v -E ':[[:space:]]*(#|--)' || true)"
    if [ -n "$non_comment" ]; then
      printf 'ERROR: legacy Omarchy paths in alias files outside comments:\n%s\n' "$non_comment" >&2
      exit 1
    fi
    info "Legacy paths found only inside alias map comments, allowed"
  fi
  info "PASS: no /usr/share/omarchy, ~/.config/omarchy, ~/.local/state/omarchy, or ~/.local/share/omarchy paths remain outside alias comments"
}

print_summary() {
  info "[9/9] Summary"
  local file_count dir_count theme_count bin_count
  file_count="$(find "$OUTPUT" -type f | wc -l | tr -d ' ')"
  dir_count="$(find "$OUTPUT" -type d | wc -l | tr -d ' ')"
  theme_count="0"
  if [ -d "$OUTPUT/themes" ]; then
    theme_count="$(find "$OUTPUT/themes" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  fi
  bin_count="0"
  if [ -d "$OUTPUT/bin" ]; then
    bin_count="$(find "$OUTPUT/bin" -type f | wc -l | tr -d ' ')"
  fi
  printf '[fork-shell] Source: %s\n' "$SRC_RESOLVED"
  printf '[fork-shell] Pinned commit: %s (%s, %s)\n' "$PINNED_SHA" "$PINNED_BRANCH" "$PINNED_DATE"
  printf '[fork-shell] Output: %s\n' "$OUTPUT"
  printf '[fork-shell] Files: %s, dirs: %s, themes: %s, bin scripts: %s\n' "$file_count" "$dir_count" "$theme_count" "$bin_count"
  printf '[fork-shell] Top level of output:\n'
  find "$OUTPUT" -mindepth 1 -maxdepth 2 -print | sort
  printf '[fork-shell] Compat files: default/hypr/hexciri-compat.lua, bin/hexciri-compat.sh\n'
  printf '[fork-shell] Next step for Phase 2: source bin/hexciri-compat.sh from hexciri-launch-shell and env-bootstrap, and require default/hypr/hexciri-compat.lua from default/hypr/hexciri.lua. Do not create a file named omarchy.\n'
  info "Phase 1 fork complete"
}

main() {
  check_deps
  resolve_source
  verify_sha
  copy_subsets
  rename_files
  rewrite_contents
  generate_compat
  verify_no_omarchy_files
  verify_no_omarchy_paths
  print_summary
}

main "$@"
