#!/usr/bin/env bash
# Hexciri fork patch 13: AUR packages must go through pkg-aur-add, not pkg-add.
# Trigger (2026-11-25, Devi): Install > Gaming > Heroic failed with
#   "error: target not found: heroic-games-launcher-bin"
# because hexciri-pkg-add is pacman-only (pacman -S --noconfirm --needed),
# and heroic-games-launcher-bin is AUR-only. Omarchy never hit this: the
# same packages shipped in Omarchy's own pacman repo (pkgs.omarchy.org),
# so pkg-add worked there. Hexciri on EndeavourOS does not use that repo,
# so every pkg-add call for a package that lives only in the AUR fails
# the same way. Full audit (2026-11-25, subagent + spot checks): 32 named
# packages switch to hexciri-pkg-aur-add (yay), and the three generic
#
# Switched, one call each (repo packages in the same scripts stay put):
#   heroic-games-launcher-bin, 1password + 1password-cli, cursor-bin,
#   sublime-text-4, visual-studio-code-bin, nordvpn-bin, hex-bin,
#   openai-codex-desktop, claude-desktop, google-chrome, symfony-cli,
#   supergfxctl, xpadneo-dkms
# Split, one call per source:
#   dropbox: libappindicator + python-gpgme stay pkg-add, dropbox +
#     dropbox-cli move to pkg-aur-add
#   voxtype: wtype stays pkg-add, voxtype-bin moves to pkg-aur-add
#   retroarch: repo cores stay pkg-add, the 15 -git cores
#     (cap32, fbneo, uae, vice x128/x64/x64dtv/x64sc/xcbm2/xcbm5x0/xpet/
#     xplus4/xscpu64/xvic, database, joypad-autoconfig) move to pkg-aur-add
# Fallback (try pacman first, yay second; yay also installs repo
# packages, so a mixed or misjudged list still lands whole):
#   install-app, install-and-launch, install-font
#
# Deliberately NOT changed here:
#   * install-preinstalls: not in the fork at all (is_allowed_bin in
#     install.sh deliberately excludes it), so its list is moot on Hexciri.
#   * install-editor-zed / omazed: patch 06 already dropped omazed
#     (Omarchy-repo-only) and the Zed row is pkg-add zed alone.
#   * update-keyring / omarchy-keyring: patch 08 already rewrote
#     hexciri-update-keyring to Arch + EndeavourOS keyrings only.
#   * hermes-desktop, openclaw, superwhisper-bin, once-bin, plain,
#     lib32-nvidia-580xx-utils: in NEITHER Arch nor the AUR, so
#     pkg-aur-add would fail exactly like pkg-add. They need a repack,
#     an upstream installer, or dropping, each a separate decision, not
#     a source switch. Their menu rows still fail as before; this patch
#     does not make them worse and does not claim to fix them.
#
# Standalone: bash v2/patches/13-pkg-aur.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "13-pkg-aur.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- AUR packages through pkg-aur-add (2026-11-25, Heroic audit) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    ("bin/hexciri-install-gaming-heroic",
     "hexciri-pkg-add heroic-games-launcher-bin",
     "hexciri-pkg-aur-add heroic-games-launcher-bin",
     "heroic: heroic-games-launcher-bin -> pkg-aur-add"),
    ("bin/hexciri-install-service-1password",
     "hexciri-pkg-add 1password 1password-cli",
     "hexciri-pkg-aur-add 1password 1password-cli",
     "1password: 1password + 1password-cli -> pkg-aur-add"),
    ("bin/hexciri-default-editor",
     "cursor) hexciri-pkg-add cursor-bin ;;",
     "cursor) hexciri-pkg-aur-add cursor-bin ;;",
     "default-editor: cursor-bin -> pkg-aur-add"),
    ("bin/hexciri-default-editor",
     "sublime_text) hexciri-pkg-add sublime-text-4 ;;",
     "sublime_text) hexciri-pkg-aur-add sublime-text-4 ;;",
     "default-editor: sublime-text-4 -> pkg-aur-add"),
    ("bin/hexciri-install-editor-vscode",
     "hexciri-pkg-add visual-studio-code-bin",
     "hexciri-pkg-aur-add visual-studio-code-bin",
     "vscode: visual-studio-code-bin -> pkg-aur-add"),
    ("bin/hexciri-install-service-nordvpn",
     "hexciri-pkg-add nordvpn-bin",
     "hexciri-pkg-aur-add nordvpn-bin",
     "nordvpn: nordvpn-bin -> pkg-aur-add"),
    ("bin/hexciri-install-dictation-hex",
     "hexciri-pkg-add hex-bin",
     "hexciri-pkg-aur-add hex-bin",
     "dictation-hex: hex-bin -> pkg-aur-add"),
    ("bin/hexciri-install-ai-chatgpt",
     "hexciri-pkg-add openai-codex-desktop",
     "hexciri-pkg-aur-add openai-codex-desktop",
     "ai-chatgpt: openai-codex-desktop -> pkg-aur-add"),
    ("bin/hexciri-install-ai-claude",
     "hexciri-pkg-add claude-desktop",
     "hexciri-pkg-aur-add claude-desktop",
     "ai-claude: claude-desktop -> pkg-aur-add"),
    ("bin/hexciri-install-browser",
     "  hexciri-pkg-add google-chrome",
     "  hexciri-pkg-aur-add google-chrome",
     "browser: google-chrome -> pkg-aur-add (Edge/Brave/Zen already aur)"),
    ("bin/hexciri-install-dev-env",
     "  hexciri-pkg-add symfony-cli",
     "  hexciri-pkg-aur-add symfony-cli",
     "dev-env: symfony-cli -> pkg-aur-add"),
    ("bin/hexciri-device-gpu-hybrid",
     "  hexciri-pkg-add supergfxctl",
     "  hexciri-pkg-aur-add supergfxctl",
     "gpu-hybrid: supergfxctl -> pkg-aur-add"),
    ("bin/hexciri-install-gaming-xbox-controllers",
     "hexciri-pkg-add xpadneo-dkms",
     "hexciri-pkg-aur-add xpadneo-dkms",
     "xbox-controllers: xpadneo-dkms -> pkg-aur-add"),
    # Split: repo half stays, AUR half moves.
    ("bin/hexciri-install-service-dropbox",
     "hexciri-pkg-add dropbox dropbox-cli libappindicator python-gpgme",
     "hexciri-pkg-add libappindicator python-gpgme\nhexciri-pkg-aur-add dropbox dropbox-cli",
     "dropbox: repo deps stay pkg-add, dropbox + dropbox-cli -> pkg-aur-add"),
    ("bin/hexciri-install-dictation-voxtype",
     "    hexciri-pkg-add wtype voxtype-bin",
     "    hexciri-pkg-add wtype\n    hexciri-pkg-aur-add voxtype-bin",
     "voxtype: wtype stays pkg-add, voxtype-bin -> pkg-aur-add"),
    # RetroArch: the -git cores are AUR-only, so they leave the pacman
    # call entirely; the repo cores keep the original call.
    ("bin/hexciri-install-gaming-retroarch",
     r"""  libretro-yabause \
  libretro-cap32-git libretro-fbneo-git libretro-uae-git \
  libretro-vice-x128-git libretro-vice-x64-git libretro-vice-x64dtv-git libretro-vice-x64sc-git \
  libretro-vice-xcbm2-git libretro-vice-xcbm5x0-git libretro-vice-xpet-git \
  libretro-vice-xplus4-git libretro-vice-xscpu64-git libretro-vice-xvic-git \
  libretro-database-git \
  retroarch-joypad-autoconfig-git""",
     r"""  libretro-yabause

# The -git cores live only in the AUR (pacman repos carry no -git
# packages), so they get their own yay call instead of failing the
# whole pacman transaction the way the single mixed call did.
hexciri-pkg-aur-add \
  libretro-cap32-git libretro-fbneo-git libretro-uae-git \
  libretro-vice-x128-git libretro-vice-x64-git libretro-vice-x64dtv-git libretro-vice-x64sc-git \
  libretro-vice-xcbm2-git libretro-vice-xcbm5x0-git libretro-vice-xpet-git \
  libretro-vice-xplus4-git libretro-vice-xscpu64-git libretro-vice-xvic-git \
  libretro-database-git \
  retroarch-joypad-autoconfig-git""",
     "retroarch: 15 -git cores -> pkg-aur-add, repo cores stay pkg-add"),
    # Generic installers: package names come from callers, so try the
    # repo first and fall back to the AUR. yay installs repo packages
    # too, so a mixed list still lands whole on the fallback.
    ("bin/hexciri-install-and-launch",
     '"echo ${install_message}; hexciri-pkg-add ${packages_arg} && (setsid uwsm-app -- gtk-launch ${desktop_id_arg} >/dev/null 2>&1 &)"',
     '"echo ${install_message}; (hexciri-pkg-add ${packages_arg} || hexciri-pkg-aur-add ${packages_arg}) && (setsid uwsm-app -- gtk-launch ${desktop_id_arg} >/dev/null 2>&1 &)"',
     "install-and-launch: repo-then-AUR fallback (caller-supplied names)"),
    ("bin/hexciri-install-app",
     '"echo ${install_message}; hexciri-pkg-add ${packages_arg}"',
     '"echo ${install_message}; hexciri-pkg-add ${packages_arg} || hexciri-pkg-aur-add ${packages_arg}"',
     "install-app: repo-then-AUR fallback (caller-supplied names)"),
    ("bin/hexciri-install-font",
     '"echo ${install_message}; hexciri-pkg-add ${package_arg} && sleep 2 && hexciri-font-set ${family_arg}"',
     '"echo ${install_message}; (hexciri-pkg-add ${package_arg} || hexciri-pkg-aur-add ${package_arg}) && sleep 2 && hexciri-font-set ${family_arg}"',
     "install-font: repo-then-AUR fallback (caller-supplied names)"),
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
print("pkg-aur patch: %d file edits applied" % len(changed))
PY

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
for _f in hexciri-install-gaming-heroic hexciri-install-service-1password hexciri-default-editor hexciri-install-editor-vscode hexciri-install-service-nordvpn hexciri-install-dictation-hex hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-browser hexciri-install-dev-env hexciri-device-gpu-hybrid hexciri-install-gaming-xbox-controllers hexciri-install-service-dropbox hexciri-install-dictation-voxtype hexciri-install-gaming-retroarch hexciri-install-and-launch hexciri-install-app hexciri-install-font; do
  if [ -f "$FORK_OUT/bin/$_f" ]; then
    bash -n "$FORK_OUT/bin/$_f" || die "bash -n failed on patched $_f"
  fi
done
unset _f
info "  pkg-aur: AUR-only installers now use pkg-aur-add (Heroic + 31 more), generic installers fall back repo -> AUR"
