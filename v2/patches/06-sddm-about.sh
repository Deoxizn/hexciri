#!/usr/bin/env bash
# Hexciri fork patch 06: SDDM fingerprint in setup script, About replacement.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/06-sddm-about.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "06-sddm-about.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Fork-time patches: SDDM fingerprint in setup script, About replacement ---
# 1. hexciri-setup-security-fingerprint: upstream setup_pam_config only
# configures sudo, polkit and the lock screen, so fingerprint worked for
# sudo but SDDM always asked for a password. Prepend pam_unix first, then
# the gate + pam_fprintd, to /etc/pam.d/sddm (ArchWiki either-or order:
# a correct password logs in at once, an empty/wrong one falls through to
# the reader), repairing any earlier Hexciri SDDM lines first, so a later
# Setup > Security > Fingerprint run (e.g. enrolling another finger) keeps
# SDDM working. The installer step above does the same thing at install
# time; this keeps the setup script consistent afterwards.
# 2. hexciri-launch-about: replaced wholesale (2026-11-24) with a floating
# fastfetch window, fixed 2026-11-24 to a two-mode script. No about.txt,
# no fit measurement, no awk locale sizing. The menu row system.about
# still calls it; the Hyprland rule in default/hypr/apps/system.lua floats
# org.hexciri.about (1280x800 start, fitted at launch). Never pass a bash -c '...' string through
# launch-or-focus-tui: it builds LAUNCH_COMMAND with unquoted $@ and
# launch-or-focus re-parses it with eval, so the -c string is split and
# bash -c receives only `export`, prints the env and exits, which is why
# About opened and closed instantly. Single-word args (--render) survive.
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import re
import sys

root = sys.argv[1]
changed = []

fp = root + "/bin/hexciri-setup-security-fingerprint"
with open(fp) as f:
    s = f.read()
s_orig = s
_marker = "# Hexciri: SDDM login unlock"
_tail = "session   include system-auth\nEOF\n  fi\n}"
_sddm = "session   include system-auth\nEOF\n  fi\n\n  # Hexciri: SDDM login unlock (2026-11-23, fixed 2026-11-24). Upstream only\n  # configures sudo, polkit and the lock screen, so fingerprint worked for\n  # sudo but SDDM always asked for a password. SDDM authenticates the user\n  # through /etc/pam.d/sddm. The order matters, ArchWiki SDDM fingerprint:\n  # pam_unix FIRST, so a correct password logs in at once and fingerprint\n  # is never asked for after it; only an empty/wrong password falls through\n  # to the clamshell gate and then pam_fprintd (press Enter on an empty\n  # password field to touch the reader). The old Hexciri order (gate +\n  # pam_fprintd first) demanded a fingerprint AFTER a correct password.\n  # Repair first: strip any earlier Hexciri SDDM lines, so a rerun fixes a\n  # machine that already has the broken order instead of skipping it.\n  if [[ -f /etc/pam.d/sddm ]]; then\n    echo \"Configuring SDDM login for fingerprint authentication...\"\n    _sddm_tmp=\"$(mktemp)\"\n    sudo sed -e '/pam_fprintd\\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm > \"$_sddm_tmp\" 2>/dev/null || cp /etc/pam.d/sddm \"$_sddm_tmp\"\n    _sddm_out=\"$(mktemp)\"\n    {\n      printf 'auth      [success=2 new_authtok_reqd=2 default=ignore] pam_unix.so try_first_pass likeauth nullok\\n'\n      printf '%s\\n' \"$fprintd_gate\"\n      printf 'auth      sufficient pam_fprintd.so\\n'\n      cat \"$_sddm_tmp\"\n    } > \"$_sddm_out\"\n    sudo install -Dm644 \"$_sddm_out\" /etc/pam.d/sddm && echo \"SDDM login fingerprint configured.\"\n    rm -f \"$_sddm_tmp\" \"$_sddm_out\"\n    if [[ -f /usr/share/sddm/themes/hexciri/theme.conf ]]; then\n      sudo sed -i '/^Fingerprint=/d' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null || true\n      printf 'Fingerprint=true\\n' | sudo tee -a /usr/share/sddm/themes/hexciri/theme.conf >/dev/null 2>&1 || true\n    fi\n  fi\n}"
if _marker in s:
    print("setup-security-fingerprint SDDM block already present, skipping")
elif s.count(_tail) == 1:
    s = s.replace(_tail, _sddm, 1)
    changed.append("setup-security-fingerprint: SDDM PAM block in setup_pam_config")
else:
    print("WARN: setup_pam_config polkit tail not found (%d), SDDM block NOT applied" % s.count(_tail))
if s != s_orig:
    with open(fp, "w") as f:
        f.write(s)

# 2. hexciri-launch-about: replace wholesale with a floating fastfetch
#    (2026-11-24). The old script measured the logo with wc/awk, remembered
#    the size in about.fit, and kept breaking (multibyte width, stale fit,
#    blank logo). About is now just a floating Kitty running fastfetch with
#    the Hexciri config at /etc/fastfetch/config.jsonc; the Hyprland rule
#    in default/hypr/apps/system.lua floats org.hexciri.about (1280x800 start, fitted at launch).
#    Also fix that rule's stale comment, which still describes the fit.
# 2. hexciri-launch-about: two-mode script (2026-11-24, fixed same day).
#    The old script measured the logo with wc/awk, remembered the size in
#    about.fit, and kept breaking (multibyte width, stale fit, blank logo).
#    The 2b92c50 replacement passed `bash -c 'export ...; fastfetch; read'`
#    through hexciri-launch-or-focus-tui, whose unquoted $@ + eval in
#    hexciri-launch-or-focus split the -c string, so bash -c got only
#    `export` and the window opened and closed at once. Now the outer call
#    passes only single-word args (hexciri-launch-about --render), which
#    survive that chain intact, and --render runs inside the terminal:
#    fastfetch with the Hexciri config at /etc/fastfetch/config.jsonc,
#    then read blocks until any key. The Hyprland rule in
#    default/hypr/apps/system.lua floats org.hexciri.about (1280x800 start, fitted at launch).
#    Also fix that rule's stale comment, which still describes the fit.
la = root + "/bin/hexciri-launch-about"
_about_lines = [
    "#!/bin/bash",
    "# hexciri-launch-about (2026-11-24): System > About is a floating fastfetch,",
    "# fitted to the rendered content at launch. No about.txt, no fit file.",
    "# Menu row system.about calls this script; it opens a floating terminal",
    "# running fastfetch with the Hexciri config at /etc/fastfetch/config.jsonc.",
    "# Window size starts from the Hyprland rule for org.hexciri.about (1280x800);",
    "# --render measures the real content and resizes the window to hug it",
    "# before painting, so it fits on any font size / DPI instead of wrapping",
    "# at a fixed 920x480 (module lines wrapped to the left margin).",
    "# --render runs INSIDE the terminal. Never pass a bash -c '...' string",
    "# through launch-or-focus-tui: unquoted $@ + eval splits it, bash -c",
    "# gets only `export` and exits, so About opens and closes at once.",
    "_about_cfg=\"/etc/fastfetch/config.jsonc\"",
    "_about_config() { if [ -f \"$_about_cfg\" ]; then fastfetch --config \"$_about_cfg\" \"$@\"; else fastfetch \"$@\"; fi; }",
    "_about_strip() { sed 's/\\x1b\\[[0-9;?]*[a-zA-Z]//g'; }",
    "_about_settle() {",
    "  local current previous=\"\" held=0",
    "  for _ in {1..20}; do",
    "    current=$(stty size 2>/dev/null || echo \"\")",
    "    if [[ $current == \"$previous\" && -n $current ]]; then (( ++held >= 3 )) && return 0; else held=0; previous=$current; fi",
    "    sleep 0.05",
    "  done",
    "  return 0",
    "}",
    "_about_fit() {",
    "  local modules module_w module_r logo_w logo_h logo_src target_c target_r",
    "  modules=$(_about_config --logo none 2>/dev/null | _about_strip; printf X); modules=${modules%X}",
    "  module_w=$(printf '%s' \"$modules\" | LC_ALL=C.UTF-8 wc -L 2>/dev/null || echo 60)",
    "  module_r=$(printf '%s' \"$modules\" | wc -l 2>/dev/null || echo 36)",
    "  logo_w=65; logo_h=35",
    "  logo_src=$(grep -m1 -o '\"source\": *\"[^\"]*\"' \"$_about_cfg\" 2>/dev/null | sed 's/\"source\": *\"//; s/\"$//')",
    "  if [[ $logo_src == *.txt ]]; then",
    "    logo_src=${logo_src/#~/$HOME}",
    "    if [ -f \"$logo_src\" ]; then logo_w=$(LC_ALL=C.UTF-8 wc -L <\"$logo_src\" 2>/dev/null || echo 54); logo_h=$(wc -l <\"$logo_src\" 2>/dev/null || echo 26); fi",
    "  else",
    "    logo_w=$(grep -m1 -o '\"width\": *[0-9]*' \"$_about_cfg\" 2>/dev/null | grep -o '[0-9]*' || echo 65)",
    "    logo_h=$(grep -m1 -o '\"height\": *[0-9]*' \"$_about_cfg\" 2>/dev/null | grep -o '[0-9]*' || echo 35)",
    "  fi",
    "  target_c=$(( logo_w + 6 + module_w + 4 ))",
    "  target_r=$(( module_r > logo_h + 3 ? module_r : logo_h + 3 ))",
    "  target_r=$(( target_r + 2 ))",
    "  local rows cols address width height nudges=0 shift_w shift_h target_w target_h mon_w mon_h",
    "  _about_settle",
    "  while :; do",
    "    read -r rows cols <<<\"$(stty size 2>/dev/null || echo \"0 0\")\"",
    "    read -r address width height <<<\"$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == \"org.hexciri.about\") | \"\\(.address) \\(.size[0]) \\(.size[1])\"' 2>/dev/null || echo \"\")\"",
    "    [[ -n ${address:-} && $cols -gt 0 && $rows -gt 0 && $width -gt 0 && $height -gt 0 ]] || return 0",
    "    if (( cols >= target_c && cols <= target_c + 1 && rows >= target_r && rows <= target_r + 1 )); then return 0; fi",
    "    (( ++nudges <= 2 )) || return 0",
    "    shift_w=$(( (target_c - cols) * width ))",
    "    shift_h=$(( (target_r - rows) * height ))",
    "    target_w=$(( width + (shift_w >= 0 ? (shift_w + cols - 1) / cols : shift_w / cols) ))",
    "    target_h=$(( height + (shift_h >= 0 ? (shift_h + rows - 1) / rows : shift_h / rows) ))",
    "    read -r mon_w mon_h <<<\"$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | \"\\(.width) \\(.height)\"' 2>/dev/null || echo \"\")\"",
    "    if [[ -n ${mon_w:-} && $mon_w -gt 0 ]]; then (( target_w > mon_w * 95 / 100 )) && target_w=$(( mon_w * 95 / 100 )); (( target_h > mon_h * 95 / 100 )) && target_h=$(( mon_h * 95 / 100 )); fi",
    "    hyprctl dispatch resizewindowpixel \"exact $target_w $target_h,address:$address\" >/dev/null 2>&1 || return 0",
    "    hyprctl dispatch centerwindow >/dev/null 2>&1 || true",
    "    _about_settle",
    "  done",
    "}",
    "if [[ ${1:-} == \"--render\" ]]; then",
    "  export LC_ALL=C.UTF-8 LANG=C.UTF-8",
    "  _about_fit",
    "  clear",
    "  _about_config",
    "  echo",
    "  read -n1 -s -r -p \"Press any key to close...\" || true",
    "  exit 0",
    "fi",
    "exec hexciri-launch-or-focus-tui --app-id=org.hexciri.about hexciri-launch-about --render",
]
with open(la, "w") as f:
    f.write("\n".join(_about_lines) + "\n")
os.chmod(la, 0o755)
changed.append("launch-about: two-mode script, --render runs fastfetch + read inside the terminal (bash -c quoting trap fixed)")
sl = root + "/default/hypr/apps/system.lua"
with open(sl) as f:
    _sl = f.read()
_sl_orig = _sl
_sl = _sl.replace("size = { 920, 480 }", "size = { 1280, 800 }", 1)
_sl = _sl.replace("-- The About fastfetch layout needs more columns than the standard float provides.\n-- This size only covers the first launch: hexciri-launch-about measures the\n-- rendered content, remembers the size that hugs it, and applies that as its own\n-- rule before every later launch.", "-- About is a floating fastfetch (hexciri-launch-about): this fixed\n-- 1280x800 starting float; --render fits it to the content at launch.")
if _sl != _sl_orig:
    with open(sl, "w") as f:
        f.write(_sl)
    changed.append("system.lua: About float comment updated (no fit measurement)")
else:
    print("WARN: system.lua About comment not found, comment NOT updated")

# 4. hexciri-install-editor-zed: `omazed` is an Omarchy-repo package that does
#    not exist on Arch, so `pkg-add zed omazed` fails and the Zed row is dead.
#    Install plain zed; theming Zed is out of v2 scope.
zed = root + "/bin/hexciri-install-editor-zed"
if os.path.isfile(zed):
    with open(zed) as f:
        z = f.read()
    z_orig = z
    z = z.replace("hexciri-pkg-add zed omazed", "hexciri-pkg-add zed")
    z = z.replace("omazed setup", "# omazed is Omarchy-repo-only, not installed: skip Zed theme setup")
    if z != z_orig:
        with open(zed, "w") as f:
            f.write(z)
        changed.append("install-editor-zed: dropped omazed (Omarchy-repo-only)")
    else:
        print("install-editor-zed: omazed already gone, skipping")
else:
    print("WARN: hexciri-install-editor-zed not in fork, Zed row will drop")

# 5. lifecycle-dispatch is a no-op on x86 (upstream docs/lifecycle-dispatch.md):
#    only Apple Silicon registers a platform package. The fork never copies
#    it, so the bare calls in install-browser / install-gaming-steam /
#    remove-gaming-steam die under set -e. Guard them.
for _lf in ("hexciri-install-browser", "hexciri-install-gaming-steam", "hexciri-remove-gaming-steam"):
    _lp = root + "/bin/" + _lf
    if os.path.isfile(_lp):
        with open(_lp) as f:
            _lt = f.read()
        _lt_orig = _lt
        _lt = re.sub(r'(?<!command -v hexciri-lifecycle-dispatch >/dev/null 2>&1 && )hexciri-lifecycle-dispatch (post-install|pre-remove) (\S+)', r'command -v hexciri-lifecycle-dispatch >/dev/null 2>&1 && hexciri-lifecycle-dispatch \1 \2 || true', _lt)
        if _lt != _lt_orig:
            with open(_lp, "w") as f:
                f.write(_lt)
            changed.append(_lf + ": lifecycle-dispatch calls guarded (no-op on x86)")
        elif "command -v hexciri-lifecycle-dispatch" in _lt:
            print(_lf + ": lifecycle-dispatch calls already guarded, skipping")
        else:
            print(_lf + ": no lifecycle-dispatch calls found, skipping")

# 6. hexciri-remove-security-fingerprint: upstream removes fingerprint from
#    sudo, polkit and the lock screen, but never from SDDM, so removing the
#    finger would leave /etc/pam.d/sddm demanding a touch after the
#    password. Strip the SDDM lines and the theme.conf Fingerprint key too.
rfp = root + "/bin/hexciri-remove-security-fingerprint"
if os.path.isfile(rfp):
    with open(rfp) as f:
        r = f.read()
    r_orig = r
    _rfp_fn = '\nremove_sddm_fingerprint_pam() {\n  # Hexciri SDDM lines (2026-11-24): removing the finger must also remove\n  # the SDDM fingerprint lines, or SDDM keeps demanding a touch after the\n  # password. Strip the pam_unix-first line too, it belongs to the block.\n  if [[ -f /etc/pam.d/sddm ]] && grep -Eq \'pam_fprintd\\.so|hexciri-hw-laptop-closed|try_first_pass likeauth nullok\' /etc/pam.d/sddm; then\n    echo "Removing fingerprint authentication from SDDM..."\n    sudo sed -i -e \'/pam_fprintd\\.so/d\' -e \'/hexciri-hw-laptop-closed/d\' -e \'/try_first_pass likeauth nullok/d\' /etc/pam.d/sddm\n  fi\n  if [[ -f /usr/share/sddm/themes/hexciri/theme.conf ]]; then\n    sudo sed -i \'/^Fingerprint=/d\' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null || true\n  fi\n}\n'
    if "remove_sddm_fingerprint_pam" in r:
        print("remove-security-fingerprint SDDM strip already present, skipping")
    elif r.count("\n}\n\nremove_lock_fingerprint_pam()") == 1:
        r = r.replace("\n}\n\nremove_lock_fingerprint_pam()", "\n}\n" + _rfp_fn + "\nremove_lock_fingerprint_pam()", 1)
        changed.append("remove-security-fingerprint: SDDM strip function added")
    else:
        print("WARN: remove_lock_fingerprint_pam anchor not found, SDDM strip NOT added")
    if "remove_sddm_fingerprint_pam\nremove_lock_fingerprint_pam" not in r and r.count("remove_pam_config\nremove_lock_fingerprint_pam") == 1:
        r = r.replace("remove_pam_config\nremove_lock_fingerprint_pam", "remove_pam_config\nremove_sddm_fingerprint_pam\nremove_lock_fingerprint_pam", 1)
        changed.append("remove-security-fingerprint: SDDM strip called after remove_pam_config")
    if r != r_orig:
        with open(rfp, "w") as f:
            f.write(r)
else:
    print("WARN: hexciri-remove-security-fingerprint not in fork, fingerprint row will drop")

# 7. Tailscale service unit (2026-11-24, full Install/Remove restore):
#    the fork rename turns the unit's ExecStart into
#    /usr/bin/hexciri-tailscale-receive, which does not exist (bins live
#    in /usr/share/hexciri/bin), and nothing installs the unit to
#    ~/.config/systemd/user, so install-service-tailscale's enable would
#    fail and the Taildrop receiver would never run. Fix the ExecStart
#    (ConditionEnvironment was already renamed OMARCHY_PATH ->
#    HEXCIRI_PATH by the rename pass), and make the install bin place
#    the unit + daemon-reload before enabling it, and the remove bin
#    drop the unit file after disabling it. The tailscale bar plugin
#    (hexciri.tailscale) is already in the forked shell, so the
#    plugin-enable/disable calls in both bins work as renamed.
_unit = root + "/default/systemd/user/hexciri-tailscale-receive.service"
if os.path.isfile(_unit):
    with open(_unit) as f:
        _u = f.read()
    _u_orig = _u
    _u = _u.replace("ExecStart=/usr/bin/hexciri-tailscale-receive", "ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive", 1)
    if _u != _u_orig:
        with open(_unit, "w") as f:
            f.write(_u)
        changed.append("tailscale unit: ExecStart points at /usr/share/hexciri/bin (rename left /usr/bin, which does not exist)")
    else:
        print("tailscale unit ExecStart already fixed, skipping")
else:
    print("WARN: tailscale unit not in fork, install-service-tailscale enable will fail")
_its = root + "/bin/hexciri-install-service-tailscale"
if os.path.isfile(_its):
    with open(_its) as f:
        _t = f.read()
    _t_orig = _t
    _old_enable = "systemctl --user enable --now hexciri-tailscale-receive.service"
    _new_enable = ("mkdir -p ~/.config/systemd/user\n"
        "cp -f \"${HEXCIRI_PATH:-/usr/share/hexciri}/default/systemd/user/hexciri-tailscale-receive.service\" ~/.config/systemd/user/ 2>/dev/null || true\n"
        "systemctl --user daemon-reload 2>/dev/null || true\n" + _old_enable)
    if _old_enable in _t and "default/systemd/user/hexciri-tailscale-receive.service" not in _t:
        _t = _t.replace(_old_enable, _new_enable, 1)
        changed.append("install-service-tailscale: installs the Taildrop unit + daemon-reload before enabling it")
    elif "default/systemd/user/hexciri-tailscale-receive.service" in _t:
        print("install-service-tailscale unit install already present, skipping")
    else:
        print("WARN: install-service-tailscale enable line not found, unit install NOT added")
    if _t != _t_orig:
        with open(_its, "w") as f:
            f.write(_t)
else:
    print("WARN: hexciri-install-service-tailscale not in fork, Tailscale row will drop")
_rts = root + "/bin/hexciri-remove-service-tailscale"
if os.path.isfile(_rts):
    with open(_rts) as f:
        _t = f.read()
    _t_orig = _t
    _old_disable = "systemctl --user disable --now hexciri-tailscale-receive.service 2>/dev/null || true"
    _new_disable = (_old_disable + "\nrm -f ~/.config/systemd/user/hexciri-tailscale-receive.service 2>/dev/null || true\nsystemctl --user daemon-reload 2>/dev/null || true")
    if _old_disable in _t and "rm -f ~/.config/systemd/user/hexciri-tailscale-receive.service" not in _t:
        _t = _t.replace(_old_disable, _new_disable, 1)
        changed.append("remove-service-tailscale: removes the Taildrop unit file after disabling it")
    elif "rm -f ~/.config/systemd/user/hexciri-tailscale-receive.service" in _t:
        print("remove-service-tailscale unit removal already present, skipping")
    else:
        print("WARN: remove-service-tailscale disable line not found, unit removal NOT added")
    if _t != _t_orig:
        with open(_rts, "w") as f:
            f.write(_t)
else:
    print("WARN: hexciri-remove-service-tailscale not in fork, Tailscale remove row will drop")

for c in changed:
    print("  fork patch: " + c)
PY
