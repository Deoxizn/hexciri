#!/usr/bin/env python3
"""Maple Mono NF CN reinstall on update (2026-11-24, Devi).

"update installed maple mono nf cn when i aleady installed it via aur.."

Root cause, proven against live nyx cf3bb1a3 and the real AUR packages:
- The cf3bb1a3 AUR step's ONLY guard was
    fc-list | grep -Fqi "Maple Mono NF"
  a family-name / fontconfig-cache check. It never asked pacman whether
  any Maple package was installed. If fc-list does not list the family
  in the installer's environment (stale cache, tty3 run, fc-list failing
  silently under 2>/dev/null), the guard falls through to yay.
- Even when the guard SHOULD have caught it, `yay -S maplemono-nf`
  cannot be a no-op for the CN variant: maplemono-nf and
  maplemono-nf-cn are split packages of ONE pkgbase, `maplemono`
  (AUR RPC: PackageBase maplemono for both, 7.9-1). makepkg downloads
  ALL 11 source zips of that base whatever split you ask for, including
  MapleMono-NF-CN.zip (the 320 MiB CN download Devi saw). So the step
  re-fetched the CN font on every update where the fc-list guard missed,
  and installed plain maplemono-nf alongside the CN variant Devi
  already had.
- There is a second AUR name for the same font: `maple-mono-nf-cn`
  (own pkgbase, same family "Maple Mono NF CN"). The menu row's
  disabled check only knew `maplemono-nf-cn`, so with the hyphenated
  package installed the row stayed enabled and clicking it would
  install the other-named package (same split-base download again).

Fix:
1. AUR step guard is now package-based first: `pacman -Q` over every
   known Maple NF package name (both AUR namings, plain + CN +
   unhinted). Any one installed -> skip, no yay, no download. The
   fc-list check stays as a second guard for fonts installed by hand
   (not via pacman).
2. New repo bin `v2/hexciri-font-maple-cn-present`: exit 0 if any CN
   package (either AUR name, hinted or unhinted) is installed. The
   Install > Style > Font > Maple Mono CN menu row now uses it as its
   disabled check instead of `hexciri-pkg-present maplemono-nf-cn`
   (which can only test one exact package name).
3. Wiring: bin copied into the fork (web-search pattern), added to the
   patch-fingerprint repo-file list, the light-sync bin list, and the
   placement-verification bin list (dies if missing).

Usage: python3 patch-2026-11-24-maple-reinstall.py [path/to/install.sh]
Default path is /tmp/maple-reinstall/v2/install.sh.
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "/tmp/maple-reinstall/v2/install.sh"
BASE_SHA = "3db01484c9bd479e8003c56ddd3ecc0a743b4c143e1b199f20cd9b09a76cd9bc"

import hashlib
with open(PATH, "rb") as f:
    data = f.read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, (
    "base install.sh sha mismatch, refusing to patch (rebase first)")
text = data.decode()
orig = text
changed = []

# 1. AUR step: package-based guard first, fc-list second.
old_step = '''step "Installing Maple Mono NF (AUR maplemono-nf, best-effort)"
if fc-list 2>/dev/null | grep -Fqi "Maple Mono NF"; then
  info "Maple Mono NF already installed"'''
new_step = '''step "Installing Maple Mono NF (AUR maplemono-nf, best-effort)"
# 2026-11-24 reinstall fix (Devi: update re-installed Maple Mono NF CN
# when he already had it via AUR): the old guard was fc-list only, a
# family-name/fontconfig-cache check, never a pacman check. And
# maplemono-nf / maplemono-nf-cn are split packages of ONE pkgbase
# (maplemono, AUR 7.9-1): makepkg downloads ALL 11 source zips whatever
# split you ask for, including MapleMono-NF-CN.zip (320 MiB), so running
# yay here at all re-fetches CN. Guard on pacman first, over every known
# Maple NF package name (both AUR namings, plain + CN + unhinted): any
# one installed means the font is already there, skip, no yay, no
# download. fc-list stays as second guard for hand-installed fonts.
if pacman -Q maplemono-nf maplemono-nf-cn maplemono-nf-unhinted maplemono-nf-cn-unhinted maple-mono-nf-cn maple-mono-nf-cn-unhinted 2>/dev/null | grep -q .; then
  info "Maple Mono NF already installed (pacman: $(pacman -Q maplemono-nf maplemono-nf-cn maplemono-nf-unhinted maplemono-nf-cn-unhinted maple-mono-nf-cn maple-mono-nf-cn-unhinted 2>/dev/null | tr '\\n' ' ' | sed 's/ *$//'))"
elif fc-list 2>/dev/null | grep -Fqi "Maple Mono NF"; then
  info "Maple Mono NF already installed (fontconfig)"'''
assert text.count(old_step) == 1, "AUR step anchor not found exactly once"
text = text.replace(old_step, new_step)
changed.append("AUR step: pacman -Q guard over all Maple NF package names before fc-list (reinstall fix 2026-11-24)")

# 2. Menu row: disabled check is now the any-CN-present bin.
old_disabled = 'hexciri-pkg-present maplemono-nf-cn'
new_disabled = 'hexciri-font-maple-cn-present'
assert text.count(old_disabled) == 1, "menu maple row disabled anchor not found exactly once"
text = text.replace(old_disabled, new_disabled)
changed.append("menu: Maple Mono CN row disabled check is now hexciri-font-maple-cn-present (either AUR name)")

# 3. patch_fingerprint repo-file list: hash the new bin.
old_ff = '"$HEXCIRI_REPO_ROOT/v2/hexciri-launch-settings"; do'
new_ff = '"$HEXCIRI_REPO_ROOT/v2/hexciri-launch-settings" "$HEXCIRI_REPO_ROOT/v2/hexciri-font-maple-cn-present"; do'
assert text.count(old_ff) == 1, "patch fingerprint repo-file list anchor not found exactly once"
text = text.replace(old_ff, new_ff)
changed.append("patch fingerprint: hexciri-font-maple-cn-present hashed")

# 4. Light-sync bin list: keep the new bin current on light-sync runs.
old_ls = 'for _ls_f in hexciri-update-hexciri hexciri-theme-ansi hexciri-theme-link hexciri-theme-sync hexciri-web-search hexciri-settings-tabs hexciri-launch-settings; do'
new_ls = 'for _ls_f in hexciri-update-hexciri hexciri-theme-ansi hexciri-theme-link hexciri-web-search hexciri-settings-tabs hexciri-launch-settings hexciri-font-maple-cn-present; do'
assert text.count(old_ls) == 1, "light-sync bin list anchor not found exactly once"
text = text.replace(old_ls, new_ls)
changed.append("light-sync: hexciri-font-maple-cn-present synced")

# 5. Copy the new bin into the fork, web-search pattern, right after the
# web-search copy block.
old_ws = '''  die "v2/hexciri-web-search not in the installer tree, Super+Shift+S web search will not exist"
fi'''
new_ws = '''  die "v2/hexciri-web-search not in the installer tree, Super+Shift+S web search will not exist"
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
fi'''
assert text.count(old_ws) == 1, "web-search copy block anchor not found exactly once"
text = text.replace(old_ws, new_ws)
changed.append("fork: hexciri-font-maple-cn-present copied into fork bin/")

# 6. Placement verification: the new bin must exist (menu audit list).
old_binlist = 'hexciri-font-list hexciri-font-current hexciri-font-set hexciri-show-logo'
new_binlist = 'hexciri-font-list hexciri-font-current hexciri-font-set hexciri-font-maple-cn-present hexciri-show-logo'
assert text.count(old_binlist) == 1, "placement bin list anchor not found exactly once"
text = text.replace(old_binlist, new_binlist)
changed.append("placement verification: hexciri-font-maple-cn-present must exist")

# 7. Placement verification: menu row must use the new disabled check.
old_verify = '''grep -q '"install.style.font.maple"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Install > Style > Font > Maple Mono CN row missing (2026-11-24)"'''
new_verify = old_verify + '''
grep -q 'hexciri-font-maple-cn-present' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Maple Mono CN row does not use hexciri-font-maple-cn-present as its disabled check (reinstall fix 2026-11-24)"'''
assert text.count(old_verify) == 1, "placement maple verify anchor not found exactly once"
text = text.replace(old_verify, new_verify)
changed.append("placement verification: menu Maple Mono CN row uses hexciri-font-maple-cn-present")

assert text != orig
with open(PATH, "w") as f:
    f.write(text)
print("patched", PATH)
for c in changed:
    print(" -", c)
print("new sha256:", hashlib.sha256(text.encode()).hexdigest())
print("lines:", text.count("\n") + 1)
