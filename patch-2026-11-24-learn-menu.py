#!/usr/bin/env python3
"""Learn menu cleanup/rework, 2026-11-24 (Devi: tmux not installed?, no
kitty link, QS missing, who knows what else).

Audit of all 9 upstream Learn rows against Hexciri v2 (live nyx 74fe03b3):
- learn.keybindings: cheatsheet, works. Kept.
- learn.hexciri (was learn.omarchy): opens the repo via
  hexciri-launch-manual. Works. Kept.
- learn.hyprland / learn.arch / learn.bash: webapp doc links, live. Kept.
- learn.neovim: LazyVim keymaps, but neovim is TRIMMED in v2 (nano is the
  fallback, Zed is the default editor). Dead. Replaced with learn.zed.
- learn.tmux-keybindings: calls hexciri-menu-tmux-keybindings, which needs
  tmux AND a tmux.conf. tmux IS in APP_PKGS, but config/tmux/tmux.conf
  was never copied into the fork, and no user config is placed either, so
  the bin dies with "Tmux config not found". Fixed by copying config/tmux.
- learn.herdr-keybindings: already dropped (Herdr out).
- learn.community: hexciri-launch-discord-community still points at the
  OMARCHY Discord invite (discord.gg/tXFUdasqhY); Hexciri has no Discord
  (Devi 2026-11-24). Dropped.
- Missing entirely: kitty (default terminal), quickshell (QS, the shell
  itself), fish (interactive shell; bash stays for sysadmin). Added.

Works on /tmp/learn-live/v2/install.sh (live nyx 74fe03b3 copy), NOT the
shared ~/workspace/hexiri-2.0/v2/install.sh, which a sibling agent (AI/Foot
restore) may be editing concurrently.
"""
import sys

P = "/tmp/learn-live/v2/install.sh"
s = open(P, encoding="utf-8").read()
orig = s

def rep(old, new, what):
    global s
    assert s.count(old) == 1, f"anchor not unique/found: {what} (count={s.count(old)})"
    s = s.replace(old, new)
    print("patched:", what)

# 1. Copy config/tmux into the fork, next to the kitty copy.
rep(
    '''  copy_subset "$OMARCHY_SRC/config/kitty" "$FORK_OUT/config/kitty" "config/kitty/"
''',
    '''  copy_subset "$OMARCHY_SRC/config/kitty" "$FORK_OUT/config/kitty" "config/kitty/"

  # Tmux config: hexciri-menu-tmux-keybindings (Learn > Tmux) falls back
  # to $HEXCIRI_PATH/config/tmux/tmux.conf when ~/.config/tmux/tmux.conf
  # is absent, and Super+Alt+Return opens tmux in Kitty. This copy was
  # missing, so Learn > Tmux died with "Tmux config not found" even
  # though tmux itself is in APP_PKGS (2026-11-24).
  copy_subset "$OMARCHY_SRC/config/tmux" "$FORK_OUT/config/tmux" "config/tmux/"
''',
    "config/tmux copy into fork",
)

# 2. Learn menu rework, inserted after the Menu Apps row patch (#2) in the
# same fork-patch python block (reuses menu, _row_key, changed).
rep(
    """if m != m_orig:
    with open(menu, "w") as f:
        f.write(m)

# 3. hexciri-shell: default HEXCIRI_PATH instead of failing when unset.""",
    r"""if m != m_orig:
    with open(menu, "w") as f:
        f.write(m)

# 2b. Learn menu rework (2026-11-24, Devi: tmux not installed?, no kitty
# link, QS missing). Audit of all 9 upstream Learn rows: keybindings /
# hexciri / hyprland / arch / bash kept (all live); neovim -> zed (neovim
# is trimmed in v2, Zed is the default editor); community dropped (Omarchy
# Discord invite, Hexciri has no Discord); fish + kitty + quickshell added
# (interactive shell, default terminal, the shell itself). Tmux row kept,
# its backing config is copied into the fork above.
with open(menu) as f:
    _llines = f.read().splitlines()
_learn_out = []
_learn_changed = []
for _line in _llines:
    _k = _row_key(_line)
    if _k == "learn.neovim":
        _learn_out.append("  \"learn.zed\": {\"icon\":\"\uf15c\",\"label\":\"Zed\",\"action\":\"hexciri-launch-webapp 'https://zed.dev/docs'\"},")
        _learn_changed.append("learn.neovim -> learn.zed (neovim trimmed in v2)")
        continue
    if _k == "learn.community":
        _learn_changed.append("learn.community dropped (Omarchy Discord invite, Hexciri has none)")
        continue
    _learn_out.append(_line)
    if _k == "learn.bash" and not any('"learn.fish"' in _l for _l in _llines):
        _learn_out.append("  \"learn.fish\": {\"icon\":\"\U000f1183\",\"label\":\"Fish\",\"action\":\"hexciri-launch-webapp 'https://fishshell.com/docs/current/'\"},")
        _learn_out.append("  \"learn.kitty\": {\"icon\":\"\ue795\",\"label\":\"Kitty\",\"action\":\"hexciri-launch-webapp 'https://sw.kovidgoyal.net/kitty/'\"},")
        _learn_out.append("  \"learn.quickshell\": {\"icon\":\"\U000f09d1\",\"label\":\"Quickshell\",\"action\":\"hexciri-launch-webapp 'https://quickshell.org/docs/'\"},")
        _learn_changed.append("learn.fish + learn.kitty + learn.quickshell added")
with open(menu, "w") as f:
    f.write("\n".join(_learn_out) + "\n")
if _learn_changed:
    changed.append("menu learn rework: " + "; ".join(_learn_changed))

# 3. hexciri-shell: default HEXCIRI_PATH instead of failing when unset.""",
    "Learn menu rework block",
)

# 3. Placement verification: tmux config present, new Learn rows present.
rep(
    '''grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"''',
    '''grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"
# Learn menu rework 2026-11-24: tmux config must be in the fork (Learn >
# Tmux falls back to it), new Learn rows must be present.
[ -f "$HEXCIRI_PATH/config/tmux/tmux.conf" ] || die "missing: config/tmux/tmux.conf, Learn > Tmux dies with 'Tmux config not found' (2026-11-24)"
for _lrow in '"learn.zed"' '"learn.fish"' '"learn.kitty"' '"learn.quickshell"' '"learn.tmux-keybindings"'; do
  grep -q "$_lrow" "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "Learn row missing from hexciri-menu.jsonc: $_lrow (2026-11-24)"
done
unset _lrow''',
    "placement verification for Learn rows + tmux config",
)

# 4. Dead-row list: learn.neovim / learn.community must be gone.
rep(
    '\'"learn.herdr-keybindings"\'',
    '\'"learn.herdr-keybindings"\' \'"learn.neovim"\' \'"learn.community"\'',
    "dead-row list gains learn.neovim + learn.community",
)

# 5. Health check: tmux binary present (Learn > Tmux + Super+Alt+Return
# both need it; Devi believed it was not installed).
rep(
    '''command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"''',
    '''command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
command -v tmux >/dev/null 2>&1 && hc_info "  tmux: present" || warn "  tmux: NOT installed, Learn > Tmux and Super+Alt+Return will fail"''',
    "health check tmux line",
)

assert s != orig
open(P, "w", encoding="utf-8").write(s)
print("OK, patched", P)
