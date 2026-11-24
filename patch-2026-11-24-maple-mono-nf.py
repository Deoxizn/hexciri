#!/usr/bin/env python3
"""Maple Mono NF as a usable menu font (2026-11-24, Devi).

Root cause, verified with real fontconfig runs (not guessed):
- Appearance > Font is a provider over hexciri-font-list /
  hexciri-font-current / hexciri-font-set, the same bins the CLI uses.
  There is no UI-side name validation beyond them.
- Maple Mono NF (AUR maplemono-nf 7.9-1; there is NO ttf-maple-mono-nf)
  was never installed: not in the base packages, not in the Arch repos,
  and Install > Style > Font is a hardcoded 6-font list with no Maple
  row. The menu could never list it; the only route was yay + font-set
  by hand. That is the "use the command line to bypass the bs" part.
- Even after installing + font-set by hand, the menu never shows Maple
  as current. Upstream Omarchy's default/fontconfig/conf.avail/
  50-omarchy.conf (leftover in /etc/fonts/conf.d/ from the Omarchy
  install; Hexciri v2 never ships it, never removes it) assigns
  monospace -> JetBrainsMono Nerd Font with mode="assign" BEFORE the
  user fonts.conf is read, so font-set's rule (test family == monospace,
  prepend_first) never fires. Proved: with the assign rule present
  fc-match monospace returns the assigned default despite the user
  rule; without it, it returns Maple Mono NF.
- Spacing is NOT the problem: fc-scan on the real v7.9 NF files gives
  family "Maple Mono NF", spacing=100, so it passes font-list's
  :spacing=100 filter. Devi's "something about spacing" hunch is
  cleared by measurement.

Fix (4 edits to v2/install.sh, all idempotent, all re-run safe):
1. AUR step installing maplemono-nf (best-effort, yay --needed).
2. Fork patch to hexciri-font-set: the fonts.conf it writes gains a
   second match block for "JetBrainsMono Nerd Font" (the family the
   system assigned monospace to), so the chosen font wins whether or
   not 50-omarchy.conf is present. Accepted side effect: an app asking
   for JetBrainsMono Nerd Font by name also resolves to the chosen
   font; that family IS the system monospace default and font-set's
   job is to replace it. The two-string single-test variant was tried
   and REJECTED: fontconfig warns multiple values in <test> are
   unsupported, and it misfired onto sans-serif.
3. Menu row Install > Style > Font > Maple Mono (hexciri-install-font
   'Maple Mono' maplemono-nf 'Maple Mono NF'), inserted after the
   iosevka row. hexciri-install-font already exists in the fork bin,
   so the audit + post-placement invariant checks pass.
4. Repair step: an existing font-set-shaped fonts.conf (single
   monospace block, no second block yet) is rewritten with the fixed
   two-block template, keeping the family already chosen, then
   fc-match monospace is checked and reported. Hand-written files
   (no prepend_first) are untouched. Fresh installs no-op (no file).
   This is what heals Devi's live box on `hexciri update`: his file
   already names Maple Mono NF, the repair makes it take effect.
5. Placement verification greps for the menu row + font-set block.

PR #16025 (upstream omarchy, open, branch maple-mono-font): the font
picker used fc-list :spacing=100 only; Maple Mono NF CN reports
spacing=90 (dual-width), so it was filtered out even when installed.
The PR makes omarchy-font-list query both spacings and adds Install >
Style > Font > Maple Mono CN. Applied here as a fork patch (the pin
stays 94a8c3c): hexciri-font-list queries both spacings, and the menu
row is the PR's row renamed, except the install runs yay, not
hexciri-pkg-add: pkg-add is pacman-only and maplemono-nf-cn is
AUR-only in Hexciri (the PR depends on omarchy-pkgs#1341 publishing
it to the [omarchy] repo, which Hexciri does not have). The CN
package (16 TTFs, 320 MiB) is NOT auto-installed, per the PR: Devi
already has it, and the menu row installs it on demand.

Fresh-install default is deliberately NOT changed to Maple: the menu
UI font stays JetBrainsMono Nerd Font (Arch glyph U+F303). Maple is
installed and one click away in Appearance > Font, which is what
Devi asked for ("shows up in the font list as a usable font").

Usage: python3 patch-2026-11-24-maple-mono-nf.py [path/to/install.sh]
Default path is the /tmp/maple-live copy used for this push.
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "/tmp/maple-live/v2/install.sh"

with open(PATH) as f:
    src = f.read()

# --- 1. AUR install step, before the LocalSend firewall block ---
old_aur_anchor = "# --- LocalSend firewall (2026-11-24): discovery is multicast UDP\n"
assert src.count(old_aur_anchor) == 1, "AUR anchor not found exactly once"
new_aur = """# --- Maple Mono NF (Devi's default font, 2026-11-24), AUR, best-effort ---
# maplemono-nf (AUR 7.9-1, NOT ttf-maple-mono-nf: no such package) is the
# Nerd Font build of Maple Mono: family "Maple Mono NF", spacing=100, so it
# passes hexciri-font-list's :spacing=100 filter (verified with fc-scan on
# the real v7.9 files). It is not in the Arch repos and was never installed
# by the base packages, so Appearance > Font could never list it and
# Install > Style > Font had no row for it: the only route was yay +
# hexciri-font-set by hand. Installing it here makes it show up in the
# menu font list like any other installed font.
# maplemono-nf-cn (Devi's actual variant) is deliberately NOT auto-installed
# here: 16 TTFs, 320 MiB (PR #16025's reason, and Devi already has it). It
# is one click away in Install > Style > Font > Maple Mono CN instead.
step "Installing Maple Mono NF (AUR maplemono-nf, best-effort)"
if fc-list 2>/dev/null | grep -Fqi "Maple Mono NF"; then
  info "Maple Mono NF already installed"
elif yay -S --needed --noconfirm maplemono-nf 2>/dev/null; then
  info "Maple Mono NF installed via yay (AUR maplemono-nf)"
else
  warn "Maple Mono NF install failed (yay/AUR unreachable), Appearance > Font will not list it until it is installed. Install by hand: yay -S maplemono-nf"
fi

"""
src = src.replace(old_aur_anchor, new_aur + old_aur_anchor, 1)

# --- 2+3. Fork patches inside the menu-audit python block: font-set
# second match block + Install > Style > Font > Maple Mono row.
# Anchor is the end of that block (unique: "menu audit: " prefix).
old_audit_end = """for c in changed:
    print("menu audit: " + c)
"""
assert src.count(old_audit_end) == 1, "menu-audit end anchor not found exactly once"
new_audit_sections = '''# 6. hexciri-font-set: second match block for the system-assigned
# monospace default (2026-11-24, Maple Mono NF). Upstream Omarchy's
# default/fontconfig/conf.avail/50-omarchy.conf assigns monospace to
# JetBrainsMono Nerd Font with mode="assign" before the user fonts.conf
# is read, so the first block's test (family == monospace) never matches
# and fc-match monospace keeps returning JetBrainsMono after font-set
# "succeeds": the menu never shows the chosen font as current. The
# second block matches the family the system assigned monospace to, so
# the chosen font wins either way. A two-string single test was tried
# and rejected: fontconfig warns multiple values in <test> are
# unsupported, and it misfired onto sans-serif. Two blocks, no warning.
fs = root + "/bin/hexciri-font-set"
with open(fs) as f:
    fs_s = f.read()
fs_orig = fs_s
_old_fc = """# fontconfig is the canonical source of truth \\u2014 the hexciri shell, Qt apps,
# and anything resolving "monospace" all read from here. This file is loaded
# after the package-owned default, and prepend_first puts the chosen family at
# the head of the list so it wins over the family that default prefers.
fontconfig_file="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$(dirname "$fontconfig_file")"
cat >"$fontconfig_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
</fontconfig>
XML"""
_new_fc = """# fontconfig is the canonical source of truth \\u2014 the hexciri shell, Qt apps,
# and anything resolving "monospace" all read from here. This file is loaded
# after the package-owned default, and prepend_first puts the chosen family at
# the head of the list so it wins over the family that default prefers.
# Hexciri 2026-11-24 (Maple Mono NF): a second match block is required.
# Upstream Omarchy ships default/fontconfig/conf.avail/50-omarchy.conf,
# whose monospace rule uses mode="assign" to replace the "monospace" alias
# with JetBrainsMono Nerd Font before this file is read, so the first
# block's test (family == monospace) never matches and fc-match monospace
# keeps returning JetBrainsMono even after font-set "succeeds" \\u2014 the menu
# never shows the chosen font as current. The second block matches the
# family the system assigned monospace to, so the chosen font wins either
# way. Side effect, accepted: an app that asks for JetBrainsMono Nerd Font
# by name also resolves to the chosen font \\u2014 that family IS the system
# monospace default, and font-set's job is to replace it.
fontconfig_file="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$(dirname "$fontconfig_file")"
cat >"$fontconfig_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Hexciri font-set second match: catches the system-assigned monospace default (see comment above) -->
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family" qual="any">
      <string>JetBrainsMono Nerd Font</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
</fontconfig>
XML"""
if _old_fc in fs_s:
    fs_s = fs_s.replace(_old_fc, _new_fc, 1)
    changed.append("font-set: second fonts.conf match block for JetBrainsMono Nerd Font (system-assigned monospace default, Maple Mono NF fix)")
elif _new_fc in fs_s:
    print("font-set second match block already present, skipping")
else:
    print("WARN: font-set fonts.conf heredoc not found, second match block NOT applied")
if fs_s != fs_orig:
    with open(fs, "w") as f:
        f.write(fs_s)

# 7. Menu row Install > Style > Font > Maple Mono CN (2026-11-24, PR #16025).
# Inserted after the iosevka row, the last upstream font row. Runs after
# the audit's write above, so the audit never drops it; the action token
# hexciri-install-font already exists in the fork bin, so the audit's
# token check and the post-placement invariant check both pass.
_maple_row = "  \\"install.style.font.maple\\": {\\"icon\\":\\"\\ue659\\",\\"label\\":\\"Maple Mono CN\\",\\"disabled\\":\\"hexciri-pkg-present maplemono-nf-cn\\",\\"action\\":\\"hexciri-launch-floating-terminal-with-presentation 'yay -S --needed --noconfirm maplemono-nf-cn && sleep 2 && hexciri-font-set \\"Maple Mono NF CN\\"'\\"},"
with open(menu) as f:
    _m_lines = f.read().splitlines()
if any('"install.style.font.maple"' in _l for _l in _m_lines):
    print("menu maple row already present, skipping")
else:
    _inserted = False
    _out = []
    for _l in _m_lines:
        _out.append(_l)
        if '"install.style.font.iosevka"' in _l:
            _out.append(_maple_row)
            _inserted = True
    if _inserted:
        with open(menu, "w") as f:
            f.write("\\n".join(_out) + "\\n")
        changed.append("menu: Install > Style > Font > Maple Mono CN row added (maplemono-nf-cn via yay, pkg-add is pacman-only)")
    else:
        print("WARN: install.style.font.iosevka row not found, maple menu row NOT added")

# 8. hexciri-font-list: list dual-width fonts too (2026-11-24, PR #16025).
# omarchy-font-list asked fontconfig only for spacing=100 (pure monospace).
# Maple Mono NF CN reports spacing=90 (dual: Latin one cell, CJK two), so
# it was silently filtered out even when installed. Ask for both, dedup
# with sort -u. Dual width is still a fixed grid, exactly how a terminal
# draws CJK, and a stock install has no other spacing 90 font.
fl = root + "/bin/hexciri-font-list"
with open(fl) as f:
    fl_s = f.read()
fl_orig = fl_s
_bsn = chr(92) + "n"
_sq = chr(39)
_fl_old = 'fc-list :spacing=100 -f "%{family[0]}' + _bsn + '" | grep -v -i -E ' + _sq + 'emoji|signwriting|hexciri' + _sq + ' | sort -u'
_fl_new = chr(10).join([
    "# Dual-width fonts (spacing 90) are monospace too: their Latin glyphs are one",
    "# cell wide and their CJK glyphs exactly two, which is how a terminal draws CJK.",
    "{",
    '  fc-list :spacing=100 -f "%{family[0]}' + _bsn + '"',
    '  fc-list :spacing=90 -f "%{family[0]}' + _bsn + '"',
    "} | grep -v -i -E 'emoji|signwriting|hexciri' | sort -u",
])
if _fl_old in fl_s:
    fl_s = fl_s.replace(_fl_old, _fl_new, 1)
    changed.append("font-list: also list dual-width (spacing 90) fonts (PR #16025, Maple Mono NF CN)")
elif _fl_new in fl_s:
    print("font-list dual-width query already present, skipping")
else:
    print("WARN: font-list single-spacing line not found, dual-width query NOT applied")
if fl_s != fl_orig:
    with open(fl, "w") as f:
        f.write(fl_s)

# 9. i18n label for the Maple row (PR #16025 adds the same key upstream).
# English falls back to the jsonc label without it; this keeps the catalog
# complete for translators. Inserted after the iosevka entry's close.
_i18n = root + "/default/i18n/en/menu.json"
with open(_i18n) as f:
    _i_lines = f.read().splitlines()
if any('"install.style.font.maple"' in _l for _l in _i_lines):
    print("i18n maple label already present, skipping")
else:
    _idx = next((k for k, _l in enumerate(_i_lines) if '"install.style.font.iosevka"' in _l), None)
    if _idx is None:
        print("WARN: i18n iosevka entry not found, maple label NOT added")
    else:
        _close = next((k for k in range(_idx, len(_i_lines)) if _i_lines[k].strip() == "},"), None)
        if _close is None:
            print("WARN: i18n iosevka close not found, maple label NOT added")
        else:
            _i_lines[_close + 1:_close + 1] = ['  "install.style.font.maple": {', '    "label": "Maple Mono CN"', '  },']
            with open(_i18n, "w") as f:
                f.write(chr(10).join(_i_lines) + chr(10))
            changed.append("i18n: Maple Mono CN label added (PR #16025)")

'''
src = src.replace(old_audit_end, new_audit_sections + old_audit_end, 1)

# --- 4. Repair an existing font-set fonts.conf (runs on update too) ---
old_kitty_warn = """  warn "config/kitty/kitty.conf not found in fork, Kitty will not load the theme colours."
fi
"""
assert src.count(old_kitty_warn) == 1, "kitty warn anchor not found exactly once"
new_repair = old_kitty_warn + """
# --- Repair font-set fonts.conf (2026-11-24, Maple Mono NF) ---
# A fonts.conf written by the old hexciri-font-set has a single match block
# testing family == monospace. Upstream Omarchy's
# default/fontconfig/conf.avail/50-omarchy.conf (leftover in
# /etc/fonts/conf.d/ from the Omarchy install) assigns monospace to
# JetBrainsMono Nerd Font before this file is read, so that test never
# matches and fc-match monospace keeps returning JetBrainsMono: the menu
# never shows the chosen font as current. The fixed font-set writes a
# second match block for JetBrainsMono Nerd Font. Rewrite an existing
# font-set-shaped file (prepend_first + monospace test, no second block
# yet) with the fixed template, keeping the family the user already
# chose. Hand-written fonts.conf files (no prepend_first) are untouched.
# Fresh installs no-op (no file yet).
_fc_file="$HOME/.config/fontconfig/fonts.conf"
if [ -f "$_fc_file" ] && grep -q 'prepend_first' "$_fc_file" && grep -q '<string>monospace</string>' "$_fc_file" && ! grep -q 'Hexciri font-set second match' "$_fc_file"; then
  _fc_family="$(python3 - "$_fc_file" <<'PYEOF' 2>/dev/null
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'<edit[^>]*mode="prepend_first"[^>]*>\\s*<string>([^<]+)</string>', src)
print(m.group(1).strip() if m else "")
PYEOF
)"
  if [ -n "$_fc_family" ]; then
    cat >"$_fc_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Hexciri font-set second match: catches the system-assigned monospace default (see hexciri-font-set) -->
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$_fc_family</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family" qual="any">
      <string>JetBrainsMono Nerd Font</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$_fc_family</string>
    </edit>
  </match>
</fontconfig>
XML
    _fc_now="$(fc-match monospace -f '%{family}\\n' 2>/dev/null | head -n1 | cut -d, -f1 || true)"
    if [ "$_fc_now" = "$_fc_family" ]; then
      info "Repaired ~/.config/fontconfig/fonts.conf (font-set second match block): fc-match monospace now returns $_fc_family"
    else
      warn "Repaired ~/.config/fontconfig/fonts.conf, but fc-match monospace still returns '${_fc_now:-unknown}' instead of $_fc_family: check /etc/fonts/conf.d/ for another monospace assign rule"
    fi
    unset _fc_now
  else
    warn "Could not read the chosen family from ~/.config/fontconfig/fonts.conf, leaving it alone (pick the font again in Appearance > Font)"
  fi
  unset _fc_family
fi
unset _fc_file
# --- end Maple Mono NF fonts.conf repair ---
"""
src = src.replace(old_kitty_warn, new_repair, 1)

# --- 5. Placement verification greps ---
old_verify = """grep -q '"settings".*hexciri-launch-settings' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "menu Settings row still present in hexciri-menu.jsonc (removed 2026-11-24, Settings opens via Super+Ctrl+S / launcher only)"
"""
assert src.count(old_verify) == 1, "verify anchor not found exactly once"
new_verify = old_verify + """grep -q '"install.style.font.maple"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Install > Style > Font > Maple Mono CN row missing (2026-11-24)"
grep -q '<string>JetBrainsMono Nerd Font</string>' "$HEXCIRI_PATH/bin/hexciri-font-set" || die "hexciri-font-set missing the system-default second match block (Maple Mono NF fix 2026-11-24)"
grep -q 'fc-list :spacing=90' "$HEXCIRI_PATH/bin/hexciri-font-list" || die "hexciri-font-list missing the dual-width (spacing 90) query (PR #16025)"
"""
src = src.replace(old_verify, new_verify, 1)

with open(PATH, "w") as f:
    f.write(src)
print("patched", PATH)
