#!/usr/bin/env python3
"""Correction to the 74fe03b3 full Install/Remove restore (2026-11-24, Devi 14:46 MST).

Two drops in that restore were wrong:
1. AI install/remove: the restore report said "agents out of scope,
   standing decision, Herdr out" and dropped install.ai. / remove.ai.
   WRONG. Devi never said to not give people Agent options, he just
   prefers opencode, hence the static about how it installs. Restore AI
   install/remove agent options (opencode default / preferred, other
   agents as options). Herdr still out.
2. Foot: the restore report said "Omarchy default terminal, Kitty is
   Hexciri equivalent" and dropped install.terminal.foot. WRONG as a
   drop. If someone else wants a different terminal fine, he just
   defaults to kitty. Restore Foot as a terminal install option, Kitty
   stays default, Foot is just an option.

What upstream 94a8c3c actually has (verified via the GitHub connector,
default/omarchy/omarchy-menu.jsonc at the pinned SHA):
- install.ai: amp, antigravity, chatgpt, claude, grok-bot, herdr,
  hermes, lm-studio, ollama, openclaw, perplexity, t3-code (12).
  These are desktop apps / agent platforms, NOT the coding-agent
  picker (claude/codex/opencode/pi/gemini/grok/copilot/crush), which
  lives in hexciri-default-agent and was never dropped.
- remove.ai: the same 11 minus herdr (upstream has no remove.ai.herdr).
- install.terminal.foot, backed by install-terminal (already in the
  fork) + config/foot/foot.ini + applications/foot.desktop.
  Upstream has NO remove.terminal.* subtree at all, so Foot removes
  via the already-restored Remove > Package row (pkg-remove); no
  remove-terminal row is invented.
- setup.default.terminal.foot was never dropped (the audit only drops
  install/remove rows), so picking Foot as default stays available;
  the installer default stays Kitty.

Backing bins restored (explicit list, NOT a wildcard: a wildcard
install-ai-* / remove-ai-* would also copy install-ai-herdr):
- install-ai-chatgpt, install-ai-claude, install-ai-hermes,
  install-ai-openclaw, install-ai-t3-code (amp/antigravity/grok-bot/
  lm-studio/ollama/perplexity rows use install-and-launch / install-app,
  already allowed).
- remove-ai-amp, remove-ai-antigravity, remove-ai-chatgpt,
  remove-ai-claude, remove-ai-grok-bot, remove-ai-hermes,
  remove-ai-lm-studio, remove-ai-ollama, remove-ai-openclaw,
  remove-ai-perplexity, remove-ai-t3-code.
- Helpers those bins call: install-hermes-cli, install-openclaw-cli,
  install-t3code-app, openclaw-onboard (launch-openclaw already matches
  launch-*, theme-set-hermes already matches theme-*).
  Transitive calls checked against upstream 94a8c3c: agent, cmd-missing,
  hw-aarch64, pkg-add/present/drop, i18n, theme-refresh,
  theme-set-t3code, webapp-install, launch-floating-terminal,
  launch-webapp, show-done are all already allowed; hermes-theme is a
  systemd unit name, not a bin.
Hard defaults combed: none of the restored bins calls folio, nautilus,
herdr, docker or windows-vm (checked upstream text for every bin).

Foot trim trap (found while writing this patch, NOT in the task text):
hexciri-trim-bloat removes foot at install time AND from the
post-update hook after every hexciri-update, so a Foot installed via
the restored menu row would be uninstalled again on the next update.
Foot leaves the trim list (step title, for loop, info line, comment,
summary item 17). Foot is still NOT installed by default: it is in no
package list (CORE_PKGS / APP_PKGS / hexciri-base.packages), so it
only ever arrives when someone picks Install > Terminal > Foot.
Kitty stays default everywhere: default terminal, dock pin, keybinds,
setup default. install-terminal foot writes xdg-terminals.list for
foot, exactly as upstream does for any terminal the user picks; that
is the user's choice at install time, not an installer default.

Opencode stays the preferred/default agent install path: v2 already
installs opencode via pacman, no account/code prompt (opencode fix
353d59c, cited in the task). Nothing in this patch touches
default-agent, the agents panel, APP_PKGS opencode, or tools.toml.

Base: live nyx HEAD 2cdc33c797cda4a6bc43af227e0465696b0c7daf (Learn
menu fix, rebased 2026-11-24 after the race warning; earlier base
74fe03b3, install.sh sha256
7fa2d11993c1fb2bd08866e83706cd429a22dfd411cf4512df8aa58c7c6b98d4).
install.sh sha256
994f2d45919669fda90a6d20323cee1c964d4d70db06480cd8c776e01c6a2a25.
The Learn fix is preserved untouched: config/tmux copy, Learn rework
2b (learn.zed/fish/kitty/quickshell, community dropped), Learn
placement checks, dead-list learn.neovim/learn.community, tmux health
line. Works on MENU_INSTALL_PATH (default /tmp/ai-foot-live/install.sh).
"""
import hashlib
import os

P = os.environ.get("MENU_INSTALL_PATH", "/tmp/ai-foot-live/install.sh")
BASE_SHA = "994f2d45919669fda90a6d20323cee1c964d4d70db06480cd8c776e01c6a2a25"

data = open(P, "rb").read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, \
    f"install.sh is not live nyx HEAD 2cdc33c7 ({hashlib.sha256(data).hexdigest()}), refusing to patch"
s = data.decode()
orig = s

NEW_BINS = (
    "install-ai-chatgpt | install-ai-claude | install-ai-hermes | "
    "install-ai-openclaw | install-ai-t3-code | remove-ai-amp | "
    "remove-ai-antigravity | remove-ai-chatgpt | remove-ai-claude | "
    "remove-ai-grok-bot | remove-ai-hermes | remove-ai-lm-studio | "
    "remove-ai-ollama | remove-ai-openclaw | remove-ai-perplexity | "
    "remove-ai-t3-code | install-hermes-cli | install-openclaw-cli | "
    "install-t3code-app | openclaw-onboard | launch-openclaw"
)

def rep(old, new, count=1):
    global s
    assert s.count(old) == count, f"anchor not found exactly {count}x: {old[:100]!r} (found {s.count(old)})"
    s = s.replace(old, new, 1)

# 1. Allowlist: restored AI bins + their helpers in. Explicit list, NOT
# install-ai-* / remove-ai-* wildcards: a wildcard would also copy
# install-ai-herdr, and Herdr stays out.
rep("chromium-copy-url-host | chromium-ytdlp-host | tailscale-receive | tailscale-send)",
    "chromium-copy-url-host | chromium-ytdlp-host | tailscale-receive | tailscale-send | " + NEW_BINS + ")")

# 1b. "Deliberately still NOT included" comment: AI is back, Herdr only out.
rep("""      # Deliberately still NOT included: install-ai-* (AI agents are out
      # of scope, Herdr stays removed), install-windows-vm, install-preinstalls,""",
"""      # Deliberately still NOT included: install-ai-herdr (Herdr stays
      # removed, standing decision: its installer curls
      # releases.herdr.dev and its theme/autostart bits are Omarchy-side),
      # install-windows-vm, install-preinstalls,""")

# 1c. copy_subsets "Skipped:" line: AI agents are no longer skipped.
rep('Docker, AI agents, omarchy-upgrade-to-quattro,',
    'Docker, Herdr (AI agents are options now, Herdr stays out), omarchy-upgrade-to-quattro,')

# 2. Data copies: Foot's tree for install-terminal, next to alacritty/ghostty.
rep("""  copy_optional_file "$OMARCHY_SRC/default/alacritty/Alacritty.desktop" "$FORK_OUT/default/alacritty/Alacritty.desktop" "default/alacritty/Alacritty.desktop" || warn "default/alacritty/Alacritty.desktop not found in source, install-terminal alacritty installs without its desktop entry."
""",
"""  copy_optional_file "$OMARCHY_SRC/default/alacritty/Alacritty.desktop" "$FORK_OUT/default/alacritty/Alacritty.desktop" "default/alacritty/Alacritty.desktop" || warn "default/alacritty/Alacritty.desktop not found in source, install-terminal alacritty installs without its desktop entry."
  # AI/Foot correction (2026-11-24, Devi: Foot is an option, Kitty stays
  # default): install-terminal foot copies config/foot when ~/.config/foot
  # is missing and installs applications/foot.desktop, exactly like
  # alacritty above. Upstream has no remove.terminal.* subtree, so Foot
  # removes via Remove > Package (pkg-remove, already restored).
  copy_subset "$OMARCHY_SRC/config/foot" "$FORK_OUT/config/foot" "config/foot/"
  copy_optional_file "$OMARCHY_SRC/applications/foot.desktop" "$FORK_OUT/applications/foot.desktop" "applications/foot.desktop" || warn "applications/foot.desktop not found in source, install-terminal foot installs without its desktop entry."
""")
rep("config/ghostty (kitty config already copied above) + the Alacritty",
    "config/ghostty + config/foot (kitty config already copied above) + the Alacritty")

# 3. Menu audit header comment: AI + Foot are back, Herdr only out.
rep("""#     AI (agents out of scope), Windows + preinstalls (Omarchy-specific),
#     Docker rows (Docker out), factory reset (btrfs-only), Foot (Omarchy
#     default terminal, Kitty is the Hexciri equivalent), Emacs (dead
#     upstream: install-editor-emacs calls a bin that does not exist).""",
"""#     Herdr (install.ai.herdr only: Herdr stays out, its installer curls
#     releases.herdr.dev and its theme/autostart bits are Omarchy-side),
#     Windows + preinstalls (Omarchy-specific), Docker rows (Docker out),
#     factory reset (btrfs-only), Emacs (dead upstream:
#     install-editor-emacs calls a bin that does not exist). AI install/
#     remove and Foot are BACK 2026-11-24 (correction to the 74fe03b3
#     restore, which wrongly dropped both): AI rows except Herdr, and
#     install.terminal.foot as an option only, Kitty stays the default.""")

# 3b. Drop sets: prefix drop is Herdr only now; foot leaves exact drops.
rep("""# Out of scope even when the action's helper exists: generic helpers
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
)""",
"""# Out of scope even when the action's helper exists: generic helpers
# (install-and-launch, install-app, launch-floating-terminal) make AI
# rows look valid, but Herdr is out (standing decision, 2026-11-24
# correction: AI agents ARE options, Devi just prefers opencode; only
# Herdr stays out). The prefix drop is Herdr only now; the exact drops
# are the Omarchy-specific / Docker / dead rows (windows, preinstalls,
# factory reset is btrfs-only, sudoless-docker needs Docker, docker-dbs
# needs Docker, Emacs is dead upstream). Foot is back as an Install >
# Terminal option only (Kitty stays default); there is no upstream
# remove.terminal.* subtree, Foot removes via Remove > Package.
_drop_prefix = (
    "install.ai.herdr",
    "remove.ai.herdr",
)""")
rep("""    "install.development.docker-dbs", "install.terminal.foot",
    "install.editor.emacs",""",
"""    "install.development.docker-dbs",
    "install.editor.emacs",""")

rep("""    changed.append("menu: removed %d dead rows (full Install/Remove restored 2026-11-24, dropped only AI, windows, preinstalls, docker rows, factory-reset, foot, emacs + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))""",
"""    changed.append("menu: removed %d dead rows (full Install/Remove restored 2026-11-24 + AI/Foot correction, dropped only Herdr, windows, preinstalls, docker rows, factory-reset, emacs + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))""")

# 4. Foot leaves the bloat trim (2026-11-24 correction): trim-bloat runs
# at install time AND from the post-update hook after every
# hexciri-update, so trimming foot would uninstall a Foot the user just
# picked from Install > Terminal. Foot is still not installed by
# default (in no package list), it only arrives via that menu row.
rep("""# never installed again. foot and btop were never installed by this
# installer (Kitty over Foot, bottom over btop) but were left over from the
# EndeavourOS base / an earlier install, so they are removed here too.""",
"""# foot was in the trim list until 2026-11-24: it is NOT installed by
# default (Kitty is the default terminal) but it IS an Install > Terminal
# option now, so trimming it on every update would uninstall a terminal
# the user just chose. btop is still trimmed (bottom over btop, and it
# was only ever left over from the EndeavourOS base / an earlier install).""")
rep('step "Trimming bloat: foot, btop, apostrophe,',
    'step "Trimming bloat: btop, apostrophe,')
rep("for _pkg in foot btop apostrophe pandoc-cli ghostwriter meld ncspot neovim obsidian pinta xterm; do",
    "for _pkg in btop apostrophe pandoc-cli ghostwriter meld ncspot neovim obsidian pinta xterm; do")
rep("(foot/btop/apostrophe/pandoc-cli/ghostwriter/meld/ncspot/neovim/obsidian/pinta/xterm stay removed;",
    "(btop/apostrophe/pandoc-cli/ghostwriter/meld/ncspot/neovim/obsidian/pinta/xterm stay removed; foot is an Install > Terminal option now, not trimmed;")
rep("foot, btop, apostrophe, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm and the Haskell tree are removed and stay removed (post-update hook re-trims on every update).",
    "btop, apostrophe, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm and the Haskell tree are removed and stay removed (post-update hook re-trims on every update). Foot is NOT trimmed anymore: it is an Install > Terminal option, Kitty stays default.")

# 5. Placement verification: restored bins, Foot data, restored rows,
# hard-default comb, Herdr absence.
rep("hexciri-install-camera hexciri-pkg-aur-add hexciri-chromium-add-feature hexciri-chromium-copy-url-host hexciri-chromium-ytdlp-host hexciri-tailscale-receive hexciri-tailscale-send; do",
    "hexciri-install-camera hexciri-pkg-aur-add hexciri-chromium-add-feature hexciri-chromium-copy-url-host hexciri-chromium-ytdlp-host hexciri-tailscale-receive hexciri-tailscale-send hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-amp hexciri-remove-ai-antigravity hexciri-remove-ai-chatgpt hexciri-remove-ai-claude hexciri-remove-ai-grok-bot hexciri-remove-ai-hermes hexciri-remove-ai-lm-studio hexciri-remove-ai-ollama hexciri-remove-ai-openclaw hexciri-remove-ai-perplexity hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-openclaw-onboard hexciri-launch-openclaw; do")
rep("""[ -f "$HEXCIRI_PATH/default/alacritty/Alacritty.desktop" ] || die "missing: default/alacritty/Alacritty.desktop, install-terminal alacritty installs without its desktop entry"
""",
"""[ -f "$HEXCIRI_PATH/default/alacritty/Alacritty.desktop" ] || die "missing: default/alacritty/Alacritty.desktop, install-terminal alacritty installs without its desktop entry"
[ -f "$HEXCIRI_PATH/config/foot/foot.ini" ] || die "missing: config/foot/foot.ini, install-terminal foot has no config to install"
[ -f "$HEXCIRI_PATH/applications/foot.desktop" ] || die "missing: applications/foot.desktop, install-terminal foot installs without its desktop entry"
# Herdr stays out (2026-11-24 correction): no Herdr bin in the fork, no
# Herdr row in the menu. The Learn > Herdr keybindings row is already
# dead-listed below; this is the Install > AI Herdr row + bin.
[ -x "$HEXCIRI_PATH/bin/hexciri-install-ai-herdr" ] && die "herdr bin in fork, Herdr stays out (2026-11-24 correction)"
grep -q '"install.ai.herdr"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "install.ai.herdr row present, Herdr stays out (2026-11-24 correction)"
# Foot is an option, Kitty stays default: the default-terminal getter
# must still report kitty for kitty.desktop (checked below), and the
# trim must not remove a user-installed Foot. The trim list lives in
# this installer, not the fork, so sim24 checks it on the patched file.
""")
rep("""for _row in '"install.browser"' '"install.terminal"' '"install.editor"' '"install.service"' '"install.development"' '"install.gaming.vibes"' '"install.gaming.xbox-cloud"' '"install.gaming.retro-launcher"' '"remove.service"' '"remove.development"' '"remove.dictation"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.gaming.battlenet"' '"remove.gaming.heroic"' '"remove.gaming.lutris"' '"remove.gaming.moonlight"' '"remove.gaming.vibes"'; do""",
"""for _row in '"install.browser"' '"install.terminal"' '"install.terminal.foot"' '"install.ai"' '"install.ai.amp"' '"install.ai.antigravity"' '"install.ai.chatgpt"' '"install.ai.claude"' '"install.ai.grok-bot"' '"install.ai.hermes"' '"install.ai.lm-studio"' '"install.ai.ollama"' '"install.ai.openclaw"' '"install.ai.perplexity"' '"install.ai.t3-code"' '"install.editor"' '"install.service"' '"install.development"' '"install.gaming.vibes"' '"install.gaming.xbox-cloud"' '"install.gaming.retro-launcher"' '"remove.ai"' '"remove.ai.amp"' '"remove.ai.antigravity"' '"remove.ai.chatgpt"' '"remove.ai.claude"' '"remove.ai.grok-bot"' '"remove.ai.hermes"' '"remove.ai.lm-studio"' '"remove.ai.ollama"' '"remove.ai.openclaw"' '"remove.ai.perplexity"' '"remove.ai.t3-code"' '"remove.service"' '"remove.development"' '"remove.dictation"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.gaming.battlenet"' '"remove.gaming.heroic"' '"remove.gaming.lutris"' '"remove.gaming.moonlight"' '"remove.gaming.vibes"' '"setup.default.terminal.foot"'; do""")
rep("for _rb in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-retro-install; do",
    "for _rb in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-retro-install hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-amp hexciri-remove-ai-antigravity hexciri-remove-ai-chatgpt hexciri-remove-ai-claude hexciri-remove-ai-grok-bot hexciri-remove-ai-hermes hexciri-remove-ai-lm-studio hexciri-remove-ai-ollama hexciri-remove-ai-openclaw hexciri-remove-ai-perplexity hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-launch-openclaw hexciri-openclaw-onboard; do")

# 5b. Dead-row list: AI + Foot are live now, Herdr only is dead.
rep("""# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (AI, windows,
# preinstalls, factory-reset, sudoless-docker, docker-dbs, foot, emacs).
# The full restore 2026-11-24 took services, development, terminals,
# browsers and dictation OUT of this list: those rows are live now.""",
"""# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (Herdr, windows,
# preinstalls, factory-reset, sudoless-docker, docker-dbs, emacs).
# The full restore 2026-11-24 took services, development, terminals,
# browsers and dictation OUT of this list, and the AI/Foot correction
# took AI (except Herdr) and install.terminal.foot out too: those rows
# are live now.""")
rep("""for _dead in '"install.ai.' '"install.windows"' '"install.preinstalls"' '"install.development.docker-dbs"' '"install.terminal.foot"' '"install.editor.emacs"' '"remove.ai.' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"learn.neovim"' '"learn.community"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do""",
"""for _dead in '"install.ai.herdr"' '"install.windows"' '"install.preinstalls"' '"install.development.docker-dbs"' '"install.editor.emacs"' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"learn.neovim"' '"learn.community"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do""")

# 6. Summary items 18 and 21.
rep("Still out: AI (agents out of scope), Windows + preinstalls (Omarchy-specific), Docker rows, factory reset (btrfs-only), Foot (Kitty is the Hexciri equivalent), Emacs (dead upstream).",
    "Still out: Herdr only (AI agents are options now, Devi prefers opencode), Windows + preinstalls (Omarchy-specific), Docker rows, factory reset (btrfs-only), Emacs (dead upstream). Foot is back as an Install > Terminal option only, Kitty stays default; foot is out of the trim list so an update cannot uninstall a Foot the user chose, and it removes via Remove > Package (upstream has no Remove > Terminal subtree).")
rep("AI menu options are still out on purpose (AI agents are out of scope, Herdr stays removed; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh).",
    "AI menu options are back 2026-11-24 (correction: Devi never said no agent options, he prefers opencode; Herdr stays removed; opencode stays the pacman default, no account prompt; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh).")
rep("AI, Windows, preinstalls, Docker rows, factory reset, Foot and Emacs stay out, see item 18).",
    "Herdr, Windows, preinstalls, Docker rows, factory reset and Emacs stay out, see item 18; Foot and the AI rows are back (2026-11-24 correction).")
rep("the chromium flags file's extension paths resolve to /usr/share/hexciri/default/chromium/ (copied whole), and the Tailscale Taildrop unit is installed by its install bin (ExecStart fixed to /usr/share/hexciri/bin).",
    "the chromium flags file's extension paths resolve to /usr/share/hexciri/default/chromium/ (copied whole), and the Tailscale Taildrop unit is installed by its install bin (ExecStart fixed to /usr/share/hexciri/bin). The restored AI bins were combed too: no folio/nautilus/herdr/docker calls in any of them; install-terminal foot copies config/foot + applications/foot.desktop.")

assert s != orig
with open(P, "w") as f:
    f.write(s)
print("patched", P)
print("new sha256:", hashlib.sha256(s.encode()).hexdigest())
print("lines:", s.count("\n"))
