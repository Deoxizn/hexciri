#!/usr/bin/env python3
"""Restore the full Install/Remove menu for Hexciri 2.0 (2026-11-24, Devi 14:23 MST).

Devi: "i want back the full install/remove back... but obviously dont
include omarchy specifics.. like preinstalls... but also comb through it
and fix hard defaults like folio etc..."

Root cause of the lean menu: the 2026-11-23 menu audit restored
Install/Remove only where a backing bin was already in the fork, and
is_allowed_bin deliberately excluded install-service-*, install-terminal-*,
install-browser, install-dev-env and install-dictation-* (Phase 1 scope),
so the audit dropped those whole subtrees. The 2026-11-24 lean patch then
removed ~30 Settings rows, but Install/Remove were already lean from the
audit, not from the lean patch.

Fix, in v2/install.sh only (fork patch + allowlist + data copies):
1. is_allowed_bin: add every bin the restored rows need, including
   install-browser's tree (pkg-aur-add, install-chromium-*, install-
   video-decode, install-camera, chromium-add-feature, chromium-*-host)
   and the games/dictation/service/remove trees.
2. copy_subsets: copy the data those bins read at runtime:
   config/chromium-flags.conf + default/chromium/ whole (extensions the
   flags file loads, native-messaging-hosts templates, policies),
   config/alacritty + config/ghostty + default/alacritty/Alacritty.desktop
   (install-terminal), default/voxtype/config.toml (install-dictation-
   voxtype), default/systemd/user/hexciri-tailscale-receive.service
   (install-service-tailscale enables it; default/systemd/user/ as a
   whole stays out).
3. Menu audit: _drop_prefix keeps only install.ai. / remove.ai.;
   _drop_exact keeps windows, preinstalls, factory-reset, sudoless-docker
   and gains docker-dbs, terminal.foot, editor.emacs. The editor rule
   (only Zed) is gone.
4. Tailscale unit: the fork rename turns ExecStart into
   /usr/bin/hexciri-tailscale-receive, which does not exist (bins live in
   /usr/share/hexciri/bin), and nothing installs the unit to
   ~/.config/systemd/user. Patch the unit's ExecStart, patch
   install-service-tailscale to install it + daemon-reload before
   enabling, patch remove-service-tailscale to remove it after disabling.
5. Placement verification: dead-row grep list matches the new drop sets,
   plus bin/data/menu-row presence checks for every restored subtree.

Restored (upstream 94a8c3c menu vs live HEAD 748c59a):
- Install > Browser (7: chromium, chrome, edge, brave, brave-origin,
  firefox, zen), Terminal (alacritty, ghostty, kitty), Editor (vscode,
  cursor, sublime, helix, vim), Service (12: 1password, bitwarden,
  dropbox, dingtalk, microsoft, nordvpn, notion, once, signal, slack,
  tailscale, wechat), Development (all but docker-dbs: rails, go, php,
  python, elixir, zig, rust, java, dotnet, ocaml, clojure, scala,
  javascript node/bun/deno, php laravel/symfony, elixir phoenix),
  Gaming extras (vibes, xbox-cloud, xbox-controllers, retro-launcher).
- Remove > Service (5), Development (all), Dictation (hex, superwhisper,
  voxtype), Gaming (battlenet, heroic, lutris, moonlight, xbox-cloud,
  xbox-controllers, vibes), Security fido2 + sshd.
Dropped and why:
- AI install/remove: AI agents out of scope, standing decision, Herdr out.
- install/windows + remove/windows: Windows VM needs Docker, Docker out.
- install/preinstalls + remove/preinstalls: Omarchy-specific, Devi explicit.
- install.terminal.foot: Omarchy default terminal; Kitty is the Hexciri
  equivalent and its row exists.
- install.editor.emacs: dead upstream, calls omarchy-install-emacs, a bin
  that does not exist anywhere in upstream.
- install.development.docker-dbs: Docker out.
- remove.factory-reset: btrfs-only; Hexciri is ext4/systemd-boot, no snapshots.
- remove.security.sudoless-docker: Docker out.
Hard defaults combed (every restored bin + row scanned):
- folio: none in any restored bin (only theme-bg-install had it, fixed
  748c59a). nautilus: only nautilus-dropbox in a pkg-drop (correct
  removal, not an install). foot: install-terminal still lists it as an
  arg, but no menu row calls it. chromium-flags.conf loads extensions
  from /usr/share/omarchy/... paths; the rename turns them into
  /usr/share/hexciri/... and default/chromium/ is now copied whole, so
  they resolve. games-vibes-remove's "comes with Omarchy" guard can
  never trigger: default/games/vibes/ (Omarchy-bundled games) is
  deliberately NOT copied. Setup > Defaults > Dictation picking now
  works: default-dictation calls hexciri-install-dictation-$backend,
  and those bins are in the fork now (before this patch picking a
  backend failed with "No installer available").

Base: live nyx HEAD 92a97d86 (rebased 2026-11-24 after the minimal-update
agent pushed it; earlier base 748c59a, install.sh sha256
9a52e40c83bb6c5e22baf77b4616b2d677f2fe36b85f951463cbd53ee8df79c9), install.sh sha256
2f540890512ed091dfc0fb11e9460403c948ab1115d6549c0f748a2401ad1d9f.
Works on MENU_INSTALL_PATH (default /tmp/menu-live/install.sh), NOT on
the shared ~/workspace/hexiri-2.0/v2/install.sh: a sibling agent
(minimal-update) is concurrently editing that file from 91299f9.
"""
import hashlib
import os
import sys

P = os.environ.get("MENU_INSTALL_PATH", "/tmp/menu-live/install.sh")
BASE_SHA = "2f540890512ed091dfc0fb11e9460403c948ab1115d6549c0f748a2401ad1d9f"

data = open(P, "rb").read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, \
    f"install.sh is not live nyx HEAD 748c59a ({hashlib.sha256(data).hexdigest()}), refusing to patch"
s = data.decode()
orig = s

NEW_BINS = (
    "install-browser | install-terminal | install-editor-vscode | install-editor-helix | "
    "install-dev-env | remove-dev-env | install-service-1password | install-service-dropbox | "
    "install-service-microsoft | install-service-nordvpn | install-service-once | "
    "install-service-signal | install-service-tailscale | remove-service-1password | "
    "remove-service-dropbox | remove-service-microsoft | remove-service-ssh-agent | "
    "remove-service-tailscale | remove-security-fido2 | remove-security-sshd | "
    "install-dictation-hex | install-dictation-superwhisper | install-dictation-voxtype | "
    "remove-dictation-hex | remove-dictation-superwhisper | remove-dictation-voxtype | "
    "install-gaming-xbox-cloud | install-gaming-xbox-controllers | remove-gaming-battlenet | "
    "remove-gaming-heroic | remove-gaming-lutris | remove-gaming-moonlight | "
    "remove-gaming-xbox-cloud | remove-gaming-xbox-controllers | games-retro-install | "
    "games-retro-cores | games-vibes-install | games-vibes-remove | games-vibes-launch | "
    "games-vibes-copy | install-chromium-copy-url | install-chromium-ytdlp | "
    "install-video-decode | install-camera | pkg-aur-add | chromium-add-feature | "
    "chromium-copy-url-host | chromium-ytdlp-host | tailscale-receive | tailscale-send"
)

def rep(old, new, count=1):
    global s
    assert s.count(old) == count, f"anchor not found exactly {count}x: {old[:100]!r} (found {s.count(old)})"
    s = s.replace(old, new, 1)

# 1. Allowlist: restored bins in.
rep("install-gaming-geforce-now | install-gaming-gpu-lib32 | remove-browser | remove-security-fingerprint | remove-gaming-steam | remove-gaming-retroarch | remove-gaming-minecraft | remove-gaming-geforce-now)",
    "install-gaming-geforce-now | install-gaming-gpu-lib32 | remove-browser | remove-security-fingerprint | remove-gaming-steam | remove-gaming-retroarch | remove-gaming-minecraft | remove-gaming-geforce-now | " + NEW_BINS + ")")

# 1b. "Deliberately still NOT included" comment: services, terminals,
# browsers, dev-env, dictation are in now.
rep("""      # Deliberately still NOT included: install-ai-*, install-service-*,
      # install-terminal-*, install-dictation-*, install-browser (its tree
      # pulls install-chromium-*, install-video-decode, install-camera and
      # config/chromium-flags.conf, none of which the fork copies; Brave
      # Origin is already installed, so no row needs it), install-windows-vm,
      # install-preinstalls, install-dev-env, channel-*, mirror-*, keyring-*,
      # upgrade-* (Omarchy repo machinery, out of the shell-only Phase 1
      # scope), and windows-vm (Docker/KVM VM manager, needs Docker).
      # The install-*/remove-* scripts that ARE listed are the bounded set
      # the menu restore keeps rows for (pkg-*, font, app, and-launch,
      # editor-zed, gaming, remove-browser/fingerprint/gaming); the menu
      # patch step below drops every other install/remove row whose backing
      # script is not in the fork, so no dead row can be clicked.""",
"""      # Deliberately still NOT included: install-ai-* (AI agents are out
      # of scope, Herdr stays removed), install-windows-vm, install-preinstalls,
      # install-docker-dbs (Docker out), channel-*, mirror-*, keyring-*,
      # upgrade-* (Omarchy repo machinery, out of the shell-only Phase 1
      # scope), and windows-vm (Docker/KVM VM manager, needs Docker).
      # 2026-11-24 full Install/Remove restore (Devi: full menu back):
      # install-service-*, install-terminal-*, install-browser (+ its
      # chromium tree: install-chromium-*, install-video-decode,
      # install-camera, config/chromium-flags.conf, default/chromium/),
      # install-dev-env / remove-dev-env (mise, back in Phase 2) and
      # install/remove-dictation-* are listed now, with the bins the
      # menu patch step below keeps rows for. The menu patch still drops
      # every other install/remove row whose backing script is not in
      # the fork, so no dead row can be clicked.""")

# 2. Data copies in copy_subsets, after the fprintd systemd copies.
rep("""  copy_optional_file "$OMARCHY_SRC/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "$FORK_OUT/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "default/systemd/system/fprintd.service.d/10-stop-timeout.conf" || warn "fprintd stop-timeout override not found in source."
""",
"""  copy_optional_file "$OMARCHY_SRC/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "$FORK_OUT/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "default/systemd/system/fprintd.service.d/10-stop-timeout.conf" || warn "fprintd stop-timeout override not found in source."

  # Full Install/Remove restore (2026-11-24, Devi: full menu back):
  # install-browser's tree: config/chromium-flags.conf (copied to
  # ~/.config/<browser>-flags.conf by install-browser; the rename turns
  # its /usr/share/omarchy/default/chromium/extensions/ paths into
  # /usr/share/hexciri/...) + default/chromium/ whole (extensions the
  # flags file loads, native-messaging-hosts templates the chromium
  # copy-url/ytdlp installers fill in, policies browser-policy.sh
  # reads). 96K total. install-terminal's tree: config/alacritty +
  # config/ghostty (kitty config already copied above) + the Alacritty
  # desktop entry it installs for alacritty. install-dictation-voxtype's
  # tree: default/voxtype/config.toml. Tailscale: the Taildrop receiver
  # unit install-service-tailscale enables; default/systemd/user/ as a
  # whole stays out, only this unit. default/games/vibes/ is deliberately
  # NOT copied: those are Omarchy-bundled games, and games-vibes-remove's
  # "comes with Omarchy" guard degrades gracefully without it (a game
  # under ~/Games/vibes is always removable then).
  copy_optional_file "$OMARCHY_SRC/config/chromium-flags.conf" "$FORK_OUT/config/chromium-flags.conf" "config/chromium-flags.conf" || warn "config/chromium-flags.conf not found in source, install-browser flags files load no extensions."
  copy_optional_path "$OMARCHY_SRC/default/chromium" "$FORK_OUT/default/chromium" "default/chromium/" || warn "default/chromium/ not found in source, install-browser extension flags point at nothing."
  copy_subset "$OMARCHY_SRC/config/alacritty" "$FORK_OUT/config/alacritty" "config/alacritty/"
  copy_subset "$OMARCHY_SRC/config/ghostty" "$FORK_OUT/config/ghostty" "config/ghostty/"
  copy_optional_file "$OMARCHY_SRC/default/alacritty/Alacritty.desktop" "$FORK_OUT/default/alacritty/Alacritty.desktop" "default/alacritty/Alacritty.desktop" || warn "default/alacritty/Alacritty.desktop not found in source, install-terminal alacritty installs without its desktop entry."
  copy_optional_path "$OMARCHY_SRC/default/voxtype" "$FORK_OUT/default/voxtype" "default/voxtype/" || warn "default/voxtype/ not found in source, install-dictation-voxtype has no config to install."
  mkdir -p "$FORK_OUT/default/systemd/user"
  copy_optional_file "$OMARCHY_SRC/default/systemd/user/omarchy-tailscale-receive.service" "$FORK_OUT/default/systemd/user/hexciri-tailscale-receive.service" "default/systemd/user/omarchy-tailscale-receive.service" || warn "default/systemd/user/omarchy-tailscale-receive.service not found in source, install-service-tailscale enables a unit that is never installed."
""")

# 3. Menu audit header comment: full restore, not the 2026-11-24 lean shape.
rep("""#  1. Deletes dead menu rows, and restores Install + Remove where a backing
#     script exists in the fork (2026-11-24, Devi: install/remove exist in
#     Hexciri v1 and should come back). A row stays when every hexciri-*
#     command its action names exists in bin/, so Package / AUR / Web App /
#     TUI / Style / Gaming and their Remove counterparts come back, while
#     rows whose script was never copied (AI, services, terminals, windows,
#     preinstalls, dictation, install-browser) still drop. A when/disabled
#     guard naming a missing command only hides or mis-guards the row, it
#     never runs, so only the action decides. Header rows (no action) stay
#     only while at least one child row under them stays. Still deleted:
#     Update > Channel (Hexciri has no channels), Update > Games /
#     Password (games-*/drive-* out of scope), Update > Config > Plymouth
#     (plymouth out), System > Screensaver (no screensaver binary ships
#     in v2). Update > Hexciri is BACK: hexciri-update is Phase 2, done
#     2026-11-24 (eos-update --aur + Hexciri self-update + mise).
#     Appearance > Unlock (plymouth), Learn > Herdr keybindings (Herdr out),
#     Setup > Default Editor > Neovim (neovim removed), Setup > Security >
#     Sudoless Docker (Docker out). The upstream jsonc is untouched.""",
"""#  1. Deletes dead menu rows, and restores the FULL Install + Remove
#     subtrees (2026-11-24, Devi: full install/remove back, except
#     Omarchy specifics). A row stays when every hexciri-* command its
#     action names exists in bin/, so Package / AUR / Web App / TUI /
#     Style / Gaming / Browser / Terminal / Editor / Service / Development
#     / Dictation and their Remove counterparts come back: their backing
#     bins are in the allowlist now (is_allowed_bin above). A when/disabled
#     guard naming a missing command only hides or mis-guards the row, it
#     never runs, so only the action decides. Header rows (no action) stay
#     only while at least one child row under them stays. Still deleted:
#     AI (agents out of scope), Windows + preinstalls (Omarchy-specific),
#     Docker rows (Docker out), factory reset (btrfs-only), Foot (Omarchy
#     default terminal, Kitty is the Hexciri equivalent), Emacs (dead
#     upstream: install-editor-emacs calls a bin that does not exist).
#     Update > Channel (Hexciri has no channels), Update > Games /
#     Password (games-*/drive-* out of scope), Update > Config > Plymouth
#     (plymouth out), System > Screensaver (no screensaver binary ships
#     in v2). Update > Hexciri is BACK: hexciri-update is Phase 2, done
#     2026-11-24 (eos-update --aur + Hexciri self-update + mise).
#     Appearance > Unlock (plymouth), Learn > Herdr keybindings (Herdr out),
#     Setup > Default Editor > Neovim (neovim removed), Setup > Security >
#     Sudoless Docker (Docker out). The upstream jsonc is untouched.""")

# 3b. Drop sets: only AI prefix now; exact drops are the Omarchy-specific
# / Docker / dead rows. Editor rule (Zed only) is gone.
rep("""# Out of scope even when the action's helper exists: generic helpers
# (install-and-launch, install-app, launch-floating-terminal) make AI,
# service, editor and dev-env rows look valid, but those subtrees are
# Phase 2 / not wanted (vim was removed on purpose, AI agents are out,
# factory reset is destructive and btrfs-only). Zed is the one editor kept.
_drop_prefix = (
    "install.ai.", "install.service.", "install.development.",
    "install.terminal.", "install.browser.", "install.dictation.",
    "remove.ai.", "remove.service.", "remove.development.",
    "remove.dictation.",
)
_drop_exact = {
    "install.windows", "install.preinstalls", "install.dictation",
    "remove.windows", "remove.preinstalls", "remove.factory-reset",
    "remove.security.fido2", "remove.security.sshd",
    "remove.security.sudoless-docker",
}""",
"""# Out of scope even when the action's helper exists: generic helpers
# (install-and-launch, install-app, launch-floating-terminal) make AI
# rows look valid, but AI agents are out (Herdr removed, standing
# decision). Everything else upstream is restored 2026-11-24, so the
# prefix drop is AI only; the exact drops are the Omarchy-specific /
# Docker / dead rows (windows, preinstalls, factory reset is btrfs-only,
# sudoless-docker needs Docker, docker-dbs needs Docker, Foot is the
# Omarchy default terminal, Emacs is dead upstream).
_drop_prefix = (
    "install.ai.",
    "remove.ai.",
)
_drop_exact = {
    "install.windows", "install.preinstalls",
    "install.development.docker-dbs", "install.terminal.foot",
    "install.editor.emacs",
    "remove.windows", "remove.preinstalls", "remove.factory-reset",
    "remove.security.sudoless-docker",
}""")

rep("""    if key in _drop_exact or key.startswith(_drop_prefix) or (key.startswith("install.editor.") and key != "install.editor.zed"):""",
    """    if key in _drop_exact or key.startswith(_drop_prefix):""")

rep("""    changed.append("menu: removed %d dead rows (kept install/remove rows whose backing bin exists, dropped the rest + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))""",
    """    changed.append("menu: removed %d dead rows (full Install/Remove restored 2026-11-24, dropped only AI, windows, preinstalls, docker rows, factory-reset, foot, emacs + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))""")

# 4. Tailscale fork patches, new section 7 before the changed loop.
rep("""for c in changed:
    print("  fork patch: " + c)
PY""",
"""# 7. Tailscale service unit (2026-11-24, full Install/Remove restore):
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
    _new_enable = ("mkdir -p ~/.config/systemd/user\\n"
        "cp -f \\"${HEXCIRI_PATH:-/usr/share/hexciri}/default/systemd/user/hexciri-tailscale-receive.service\\" ~/.config/systemd/user/ 2>/dev/null || true\\n"
        "systemctl --user daemon-reload 2>/dev/null || true\\n" + _old_enable)
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
    _new_disable = (_old_disable + "\\nrm -f ~/.config/systemd/user/hexciri-tailscale-receive.service 2>/dev/null || true\\nsystemctl --user daemon-reload 2>/dev/null || true")
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
PY""")

# 5. Placement verification: dead-row grep list matches the new drop sets.
rep("""# Dead menu rows must be gone from the forked jsonc, not just uncallable.
# NOTE 2026-11-24: '"install.' / '"remove.' must NOT be in this list.
# b0eed823 restored Install/Remove (26 install.* + 20 remove.* rows, all
# with backing bins, verified in sim6), and the broad patterns matched the
# first restored row and killed the install with
#   ERROR: dead menu row still present in hexciri-menu.jsonc: "install.
# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (AI, services,
# development, terminals, browsers, dictation, windows, preinstalls,
# factory-reset, fido2, sshd, sudoless-docker). Non-Zed editors are
# dropped by the menu patch too, but are covered by the action-token
# check below, not by a grep pattern (there is no grep for "not zed").
for _dead in '"install.ai.' '"install.service.' '"install.development.' '"install.terminal.' '"install.browser.' '"install.dictation.' '"install.windows"' '"install.preinstalls"' '"remove.ai.' '"remove.service.' '"remove.development.' '"remove.dictation.' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do""",
"""# Dead menu rows must be gone from the forked jsonc, not just uncallable.
# NOTE 2026-11-24: '"install.' / '"remove.' must NOT be in this list.
# b0eed823 restored Install/Remove (26 install.* + 20 remove.* rows, all
# with backing bins, verified in sim6), and the broad patterns matched the
# first restored row and killed the install with
#   ERROR: dead menu row still present in hexciri-menu.jsonc: "install.
# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (AI, windows,
# preinstalls, factory-reset, sudoless-docker, docker-dbs, foot, emacs).
# The full restore 2026-11-24 took services, development, terminals,
# browsers and dictation OUT of this list: those rows are live now.
for _dead in '"install.ai.' '"install.windows"' '"install.preinstalls"' '"install.development.docker-dbs"' '"install.terminal.foot"' '"install.editor.emacs"' '"remove.ai.' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do""")

# 5b. Placement verification: restored bins, data files, menu rows.
rep("""grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"
grep -q 'strata "$@"' "$HEXCIRI_PATH/bin/hexciri-launch-files" || die "launch-files drops its path argument, background folder opens at Strata home instead of the theme backgrounds folder (2026-11-24)\"""",
"""grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"
grep -q 'strata "$@"' "$HEXCIRI_PATH/bin/hexciri-launch-files" || die "launch-files drops its path argument, background folder opens at Strata home instead of the theme backgrounds folder (2026-11-24)"
# Full Install/Remove restore 2026-11-24: every restored row's backing bin
# must be in the fork, plus the data files those bins read at runtime.
for _bin in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-remove-service-1password hexciri-remove-service-dropbox hexciri-remove-service-microsoft hexciri-remove-service-ssh-agent hexciri-remove-service-tailscale hexciri-remove-security-fido2 hexciri-remove-security-sshd hexciri-install-dictation-hex hexciri-install-dictation-superwhisper hexciri-install-dictation-voxtype hexciri-remove-dictation-hex hexciri-remove-dictation-superwhisper hexciri-remove-dictation-voxtype hexciri-install-gaming-xbox-cloud hexciri-install-gaming-xbox-controllers hexciri-remove-gaming-battlenet hexciri-remove-gaming-heroic hexciri-remove-gaming-lutris hexciri-remove-gaming-moonlight hexciri-remove-gaming-xbox-cloud hexciri-remove-gaming-xbox-controllers hexciri-games-retro-install hexciri-games-retro-cores hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-vibes-launch hexciri-games-vibes-copy hexciri-install-chromium-copy-url hexciri-install-chromium-ytdlp hexciri-install-video-decode hexciri-install-camera hexciri-pkg-aur-add hexciri-chromium-add-feature hexciri-chromium-copy-url-host hexciri-chromium-ytdlp-host hexciri-tailscale-receive hexciri-tailscale-send; do
  [ -x "$HEXCIRI_PATH/bin/$_bin" ] || die "missing bin (full Install/Remove restore 2026-11-24, a restored menu row calls it): $_bin"
done
unset _bin
[ -f "$HEXCIRI_PATH/config/chromium-flags.conf" ] || die "missing: config/chromium-flags.conf, install-browser writes flags files Chromium cannot load extensions from"
[ -f "$HEXCIRI_PATH/default/chromium/extensions/copy-url/manifest.json" ] || die "missing: default/chromium/extensions/copy-url, install-browser flags file loads an extension that is not installed"
[ -f "$HEXCIRI_PATH/default/chromium/native-messaging-hosts/com.hexciri.copy_url.json" ] || die "missing: default/chromium/native-messaging-hosts/com.hexciri.copy_url.json, install-chromium-copy-url has no template to fill in"
[ -f "$HEXCIRI_PATH/default/chromium/native-messaging-hosts/com.hexciri.ytdlp.json" ] || die "missing: default/chromium/native-messaging-hosts/com.hexciri.ytdlp.json, install-chromium-ytdlp has no template to fill in"
[ -f "$HEXCIRI_PATH/config/alacritty/alacritty.toml" ] || die "missing: config/alacritty/alacritty.toml, install-terminal alacritty has no config to install"
[ -f "$HEXCIRI_PATH/config/ghostty/config" ] || die "missing: config/ghostty/config, install-terminal ghostty has no config to install"
[ -f "$HEXCIRI_PATH/default/alacritty/Alacritty.desktop" ] || die "missing: default/alacritty/Alacritty.desktop, install-terminal alacritty installs without its desktop entry"
[ -f "$HEXCIRI_PATH/default/voxtype/config.toml" ] || die "missing: default/voxtype/config.toml, install-dictation-voxtype has no config to install"
[ -f "$HEXCIRI_PATH/default/systemd/user/hexciri-tailscale-receive.service" ] || die "missing: default/systemd/user/hexciri-tailscale-receive.service, install-service-tailscale enables a unit that is never installed"
grep -q 'ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive' "$HEXCIRI_PATH/default/systemd/user/hexciri-tailscale-receive.service" || die "tailscale unit ExecStart is not /usr/share/hexciri/bin/hexciri-tailscale-receive, the Taildrop receiver never starts"
grep -q 'default/systemd/user/hexciri-tailscale-receive.service' "$HEXCIRI_PATH/bin/hexciri-install-service-tailscale" || die "install-service-tailscale does not install the Taildrop unit before enabling it"
grep -q 'rm -f ~/.config/systemd/user/hexciri-tailscale-receive.service' "$HEXCIRI_PATH/bin/hexciri-remove-service-tailscale" || die "remove-service-tailscale does not remove the Taildrop unit file"
for _row in '"install.browser"' '"install.terminal"' '"install.editor"' '"install.service"' '"install.development"' '"install.gaming.vibes"' '"install.gaming.xbox-cloud"' '"install.gaming.retro-launcher"' '"remove.service"' '"remove.development"' '"remove.dictation"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.gaming.battlenet"' '"remove.gaming.heroic"' '"remove.gaming.lutris"' '"remove.gaming.moonlight"' '"remove.gaming.vibes"'; do
  grep -q "$_row" "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "restored menu row missing from hexciri-menu.jsonc: $_row"
done
unset _row
# No hard defaults in the restored rows: folio and nautilus are not
# installed in Hexciri v2, so no restored row or bin may call them.
grep -q 'folio' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "restored menu still references folio, which is not installed in Hexciri v2"
for _rb in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-retro-install; do
  grep -qE '(^|[^a-z-])folio([^a-z-]|$)' "$HEXCIRI_PATH/bin/$_rb" && die "restored bin $_rb still calls folio, which is not installed in Hexciri v2"
done
unset _rb""")

# 6. Summary text: items 18 and 21 describe the menu restore.
rep("""  18. Menu audit 2026-11-23: Install and Remove subtrees were deleted then (install-*/remove-* were never in the fork), restored 2026-11-24 where a backing script exists (see item 21). Update > Channel is gone (Hexciri has no channels), Update > Hexciri is back (Phase 2, 2026-11-24, runs hexciri-update in a floating terminal), System > Screensaver is gone (no screensaver binary in v2). Setup > Security > Fingerprint, Setup > Plugin options, System > Lock, System > Logout/Reboot/Shutdown, Appearance > Dock, Setup > Network > DNS, display scale and network data should all work now; the missing bins that broke them are copied. AI menu options are still out on purpose (AI agents are out of scope, Herdr stays removed; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh). Hide/Show Bar works (bare hexciri-toggle was missing in the sim, now copied). Setup > Defaults > Dictation rows work (no backend installed yet, pick one first). The dock pinned list is Strata, Spotify, Brave Origin, Zed, Kitty (Devi 2026-11-23); hexciri-browser / hexciri-terminal are not pinned, they are wrappers for Brave Origin / Kitty and would duplicate them.""",
"""  18. Menu audit 2026-11-23: Install and Remove subtrees were deleted then (install-*/remove-* were never in the fork), restored 2026-11-24 where a backing script exists (see item 21), then restored in FULL 2026-11-24 (Devi: full install/remove back): Browser, Terminal, Editor, Service, Development, Dictation, Gaming extras and their Remove counterparts are back, with their bins and data files copied. Still out: AI (agents out of scope), Windows + preinstalls (Omarchy-specific), Docker rows, factory reset (btrfs-only), Foot (Kitty is the Hexciri equivalent), Emacs (dead upstream). Update > Channel is gone (Hexciri has no channels), Update > Hexciri is back (Phase 2, 2026-11-24, runs hexciri-update in a floating terminal), System > Screensaver is gone (no screensaver binary in v2). Setup > Security > Fingerprint, Setup > Plugin options, System > Lock, System > Logout/Reboot/Shutdown, Appearance > Dock, Setup > Network > DNS, display scale and network data should all work now; the missing bins that broke them are copied. AI menu options are still out on purpose (AI agents are out of scope, Herdr stays removed; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh). Hide/Show Bar works (bare hexciri-toggle was missing in the sim, now copied). Setup > Defaults > Dictation rows work (pick a backend, its installer is in the fork now). The dock pinned list is Strata, Spotify, Brave Origin, Zed, Kitty (Devi 2026-11-23); hexciri-browser / hexciri-terminal are not pinned, they are wrappers for Brave Origin / Kitty and would duplicate them.""")

rep("""Install and Remove menu entries are back (Package, AUR, Web App, TUI, Style, Gaming and their Remove counterparts, kept only where the backing script exists in the fork; AI, services, terminals, Windows, preinstalls and dictation stay out, and install-browser stays out because its helper tree is not copied).""",
"""Install and Remove menu entries are back in FULL (Package, AUR, Web App, TUI, Style, Gaming, Browser, Terminal, Editor, Service, Development, Dictation and their Remove counterparts, kept only where the backing script exists in the fork; AI, Windows, preinstalls, Docker rows, factory reset, Foot and Emacs stay out, see item 18). Every restored bin was combed for hard defaults: no folio or nautilus calls in any restored row or bin (folio only ever lived in theme-bg-install, fixed 748c59a; nautilus-dropbox appears only as a package removal), the chromium flags file's extension paths resolve to /usr/share/hexciri/default/chromium/ (copied whole), and the Tailscale Taildrop unit is installed by its install bin (ExecStart fixed to /usr/share/hexciri/bin).""")

assert s != orig
with open(P, "w") as f:
    f.write(s)
print("patched", P)
print("new sha256:", hashlib.sha256(s.encode()).hexdigest())
print("lines:", s.count("\n"))
