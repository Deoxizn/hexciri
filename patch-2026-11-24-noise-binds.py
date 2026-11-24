#!/usr/bin/env python3
import pathlib, sys
root = pathlib.Path("/tmp/noise-fix/repro/v2")
inst = root/"install.sh"
upd = root/"hexciri-update-hexciri"
s = inst.read_text()
u = upd.read_text()
def rep(text, old, new, what, count=1):
    assert old in text, f"NOT FOUND: {what}"
    assert text.count(old) == count, f"NOT UNIQUE ({text.count(old)}): {what}"
    return text.replace(old, new, count)

# 1. system_fingerprint: filter guard line out of sys2 range
s = rep(s,
    """    sed -n '/^# --- mise + Hexciri tools config/,/^# --- Place the forked tree to its install targets ---/p' "$INSTALLER_DIR/install.sh"
""",
    """    sed -n '/^# --- mise + Hexciri tools config/,/^# --- Place the forked tree to its install targets ---/p' "$INSTALLER_DIR/install.sh" | grep -vF 'binds_chain_ok "$FORK_OUT"'
""", "system_fingerprint sys2 filter")

# 2. Move pre-placement binds guard from THPM tail to Place section.
guard_old = """# Pre-placement binds guard (2026-11-24, Devi: Super+Space apps and
# Super+Alt+Space menu both died after the 2cdc33c7 update): that update
# replaced /usr/share/hexciri, then placement verification died on
# config/tmux/tmux.conf, so the update aborted with a new, unverified
# tree live, Hyprland reloaded on it by the guard resume, and the shell
# never restarted. Both chords go through GlobalShortcuts, so a reload
# onto a bad tree (or a shell that never re-registers them) kills both
# at once while plain command binds keep working. Check the whole chain
# in the FORK, before anything is replaced: a broken fork dies here
# with the last good tree still live, never after rm -rf.
binds_chain_ok "$FORK_OUT" || die "binds chain broken in fork (Super+Space apps / Super+Alt+Space menu would not register; see above). Refusing to place a broken fork over the working tree."

"""
assert guard_old in s
s = s.replace(guard_old, "", 1)
guard_new = """# Pre-placement binds guard (2026-11-24, Devi: Super+Space apps and
# Super+Alt+Space menu both died after the 2cdc33c7 update): that update
# replaced /usr/share/hexciri, then placement verification died on
# config/tmux/tmux.conf, so the update aborted with a new, unverified
# tree live, Hyprland reloaded on it by the guard resume, and the shell
# never restarted. Both chords go through GlobalShortcuts, so a reload
# onto a bad tree (or a shell that never re-registers them) kills both
# at once while plain command binds keep working. Check the whole chain
# in the FORK, before anything is replaced: a broken fork dies here
# with the last good tree still live, never after rm -rf.
# Moved here 2026-11-24 (noise fix): it used to sit before the Place
# header, inside system_fingerprint()'s range, so this one check line
# moved the system fingerprint and forced a full installer on every
# update after 6e48f01. It now sits after the Place header, outside
# every fingerprint range, so a check can never move a fingerprint.
binds_chain_ok "$FORK_OUT" || die "binds chain broken in fork (Super+Space apps / Super+Alt+Space menu would not register; see above). Refusing to place a broken fork over the working tree."

"""
place_anchor = """hypr_guard_pause

sudo rm -rf "$HEXCIRI_PATH"
"""
s = rep(s, place_anchor, "hypr_guard_pause\n\n" + guard_new + 'sudo rm -rf "$HEXCIRI_PATH"\n', "guard move to Place section")

# 3. Installer smoke check: GlobalShortcut WARNs -> detail log only.
s = rep(s,
    """# Warn only, never die: the shell restart in hexciri-update-restart
# runs after this installer and re-registers the shortcuts, and a tty3
# run has no Hyprland at all. (hyprctl binds is not grepped here: its
# output format varies, globalshortcuts is the authority.)""",
    """# Warn only, never die: the shell restart in hexciri-update-restart
# runs after this installer and re-registers the shortcuts, and a tty3
# run has no Hyprland at all. (hyprctl binds is not grepped here: its
# output format varies, globalshortcuts is the authority.)
# 2026-11-24 noise fix: the two GlobalShortcut lines below used to warn
# here, but at this point the guard-resume reload has just run and the
# shell restart has NOT happened yet, so missing registrations are the
# expected state, not a failure. They now go to the detail log only.
# The real check is patch 8f in hexciri-update-restart, which polls
# after the last reload and restarts the shell again if needed.""",
    "smoke check comment")
s = rep(s,
    """    echo "$_gs" | grep -q 'omarchy:menu.root' || warn "Super+Alt+Space menu shortcut not registered by the shell (omarchy:menu.root missing from hyprctl globalshortcuts; shell restart in hexciri-update-restart should re-register it, or run: hexciri-restart-shell)"
    echo "$_gs" | grep -q 'omarchy:ipc.hexciri.dock.apps' || warn "Super+Space apps shortcut not registered by the shell (omarchy:ipc.hexciri.dock.apps missing from hyprctl globalshortcuts; shell restart in hexciri-update-restart should re-register it, or run: hexciri-restart-shell)"
""",
    """    echo "$_gs" | grep -q 'omarchy:menu.root' || printf '%s\\n' "binds smoke check (expected before shell restart): omarchy:menu.root not yet registered" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
    echo "$_gs" | grep -q 'omarchy:ipc.hexciri.dock.apps' || printf '%s\\n' "binds smoke check (expected before shell restart): omarchy:ipc.hexciri.dock.apps not yet registered" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
""", "smoke check demote")

# 4. Fork patch 8f in hexciri-update-restart, after 8e block.
anchor8e = """    '    hexciri-restart-hyprctl && echo "Hyprland config reloaded (hyprctl reload)"\\n  fi\\n\\n  # Hexciri: tell the stock system-update widget to recheck now\\n  # (2026-11-24, Devi: its icon stayed on after an update because it\\n  # only rechecks every 6h / on network-online and nothing ever told\\n  # it to refresh. Its own ShellIpc refresh, same pattern as\\n  # `hexciri-shell hexciri.dock refresh`. Best-effort: the widget may\\n  # not be in the active bar (Nyxiri bar uses arch-updates).)\\n  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\\nfi',
    "restart refreshes the system-update widget after an update")
PY
"""
patch8f = anchor8e + """
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
def must_replace(path, old, new, what):
    t = read(path)
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    '  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\\nfi',
    '  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\\n\\n  # Hexciri: GlobalShortcuts must be registered AFTER the last Hyprland\\n  # reload (2026-11-24, Devi: shell restarted before the reload, reload\\n  # dropped omarchy:menu.root / omarchy:ipc.hexciri.dock.apps, update\\n  # ended with Super+Space / Super+Alt+Space dead). Poll, restart the\\n  # shell once more if either is missing, poll again. Best-effort.\\n  if pgrep -x Hyprland >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then\\n    _gs_ok=0\\n    for _gs_try in 1 2 3 4 5 6 7 8 9 10; do\\n      if hyprctl globalshortcuts 2>/dev/null | grep -q \\'omarchy:menu.root\\' && hyprctl globalshortcuts 2>/dev/null | grep -q \\'omarchy:ipc.hexciri.dock.apps\\'; then _gs_ok=1; break; fi\\n      sleep 0.5\\n    done\\n    if [[ $_gs_ok == "0" ]]; then\\n      hexciri-restart-shell || true\\n      for _gs_try in 1 2 3 4 5 6 7 8 9 10; do\\n        if hyprctl globalshortcuts 2>/dev/null | grep -q \\'omarchy:menu.root\\' && hyprctl globalshortcuts 2>/dev/null | grep -q \\'omarchy:ipc.hexciri.dock.apps\\'; then _gs_ok=1; break; fi\\n        sleep 0.5\\n      done\\n    fi\\n    if [[ $_gs_ok == "1" ]]; then echo "GlobalShortcuts registered: Super+Space apps / Super+Alt+Space menu"; else echo "GlobalShortcuts still missing after shell restart (omarchy:menu.root / omarchy:ipc.hexciri.dock.apps; run: hexciri-restart-shell)"; fi\\n    unset _gs_ok _gs_try\\n  fi\\nfi',
    "restart re-registers GlobalShortcuts after the last Hyprland reload")
PY
"""
s = rep(s, anchor8e, patch8f, "patch 8f insert")

# Placement verification for patch 8f (next to the 8d/8e checks).
s = rep(s,
    """grep -q 'hexciri-shell hexciri.system-update refresh' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not refresh the system-update widget after an update (stock icon stays on up to 6h, 2026-11-24)"
""",
    """grep -q 'hexciri-shell hexciri.system-update refresh' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not refresh the system-update widget after an update (stock icon stays on up to 6h, 2026-11-24)"
grep -q 'GlobalShortcuts registered' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not re-register GlobalShortcuts after the last Hyprland reload (Super+Space / Super+Alt+Space stay dead after an update, 2026-11-24)"
""", "placement check 8f")

inst.write_text(s)

# 5. hexciri-update-hexciri migration branch: upstream+provision match,
# patch/system differ, but system inputs unchanged -> re-apply, not full.
old_branch = """  elif [[ -n $_new_up && -n $_new_patch && -n $_new_prov && -n $_new_sys && $_new_up == "$INSTALLED_UP" && $_new_patch == "$INSTALLED_PATCH" && $_new_sys == "$INSTALLED_SYS" && $_new_prov != "$INSTALLED_PROV" ]]; then
"""
assert old_branch in u
# Insert new elif AFTER the provision-only branch. Find its closing block:
prov_block_end = """    detail "re-apply-provision failed, falling through to a full installer re-run"
  fi
fi
"""
assert prov_block_end in u
migration = """    detail "re-apply-provision failed, falling through to a full installer re-run"
  elif [[ -n $_new_up && -n $_new_patch && -n $_new_prov && -n $_new_sys && $_new_up == "$INSTALLED_UP" && $_new_prov == "$INSTALLED_PROV" && ( $_new_patch != "$INSTALLED_PATCH" || $_new_sys != "$INSTALLED_SYS" ) ]]; then
    # Migration (2026-11-24, noise fix): patch+system differ, but the
    # system fingerprint moved only because a patch-level check line
    # (binds_chain_ok guard, 6e48f01) sat inside its range, and the
    # upstream fingerprint moved only on fork decisions. If the real
    # system provisioning inputs are unchanged between the old and new
    # installer, a full installer is pure noise: re-apply instead.
    # System inputs = install.sh system ranges (Preflight..Fork cache
    # check, mise..Place, guard line ignored) + base packages + tools.
    _sys_unchanged=0
    if [[ $SYNC_METHOD == "git" && $OLD_COMMIT != "none" && -n $NEW_COMMIT && $NEW_COMMIT != "none" ]]; then
      _mig_tmp="$(mktemp -d /tmp/hexciri-mig.XXXXXX)"
      if git -C "$CHECKOUT" show "$OLD_COMMIT:v2/install.sh" > "$_mig_tmp/old-install.sh" 2>>"$DETAIL_LOG" && git -C "$CHECKOUT" diff --quiet "$OLD_COMMIT" "$NEW_COMMIT" -- v2/hexciri-base.packages v2/hexciri-tools.toml 2>>"$DETAIL_LOG"; then
        _old_sys="$( { sed -n '/^# --- Preflight ---/,/^# --- Fork cache check/p' "$_mig_tmp/old-install.sh"; sed -n '/^# --- mise + Hexciri tools config/,/^# --- Place the forked tree to its install targets ---/p' "$_mig_tmp/old-install.sh"; } | sed '/^# Pre-placement binds guard/,/^binds_chain_ok "\$FORK_OUT" || die/d' | grep -v '^$' | sha256sum | cut -d' ' -f1 )"
        _new_sys_in="$( { sed -n '/^# --- Preflight ---/,/^# --- Fork cache check/p' "$SOURCE_ROOT/v2/install.sh"; sed -n '/^# --- mise + Hexciri tools config/,/^# --- Place the forked tree to its install targets ---/p' "$SOURCE_ROOT/v2/install.sh"; } | sed '/^# Pre-placement binds guard/,/^binds_chain_ok "\$FORK_OUT" || die/d' | grep -v '^$' | sha256sum | cut -d' ' -f1 )"
        if [[ -n $_old_sys && $_old_sys == "$_new_sys_in" ]]; then _sys_unchanged=1; detail "migration: system inputs unchanged between $OLD_COMMIT and $NEW_COMMIT, re-apply instead of full"; else detail "migration: system inputs changed, falling through to full installer"; fi
      else
        detail "migration: could not diff old vs new installer, falling through to full installer"
      fi
      rm -rf "$_mig_tmp"
    else
      detail "migration: no git old commit to diff (tarball sync), falling through to full installer"
    fi
    if [[ $_sys_unchanged == "1" ]]; then
      detail "patch/system differ but system inputs unchanged, re-apply (fork patch only, no packages / GPU / SDDM / theme / PAM / trim)"
      if [[ -n $SHORT ]]; then echo "Updating Hexciri to $SHORT... (re-apply: fork patch only)"; else echo "Updating Hexciri... (re-apply: fork patch only)"; fi
      if bash "$SOURCE_ROOT/v2/install.sh" --yes --no-reboot --re-apply; then
        _rm_after="$(cat "$MARKER" 2>/dev/null || true)"
        if [[ $_rm_after == "$NEW_SHA" ]]; then
          if [[ -n $SHORT ]]; then echo "Hexciri updated to $SHORT"; else echo "Hexciri updated"; fi
          [[ -n ${TARBALL_WORKDIR:-} ]] && rm -rf "$TARBALL_WORKDIR"
          exit 0
        fi
        detail "marker mismatch after re-apply: got '${_rm_after:-none}', expected $NEW_SHA"
      fi
      detail "re-apply failed, falling through to a full installer re-run"
    fi
  fi
fi
"""
u = u.replace(prov_block_end, migration, 1)
upd.write_text(u)
print("patched OK")
print("install lines:", len(s.splitlines()), "updater lines:", len(u.splitlines()))
