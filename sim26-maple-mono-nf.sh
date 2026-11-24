#!/bin/bash
# sim26: Maple Mono NF as a usable menu font (2026-11-24).
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/maple-live, then functionally proves the fix with real fontconfig:
#  - patched forked hexciri-font-set "Maple Mono NF" makes
#    fc-match monospace return Maple Mono NF even with a 50-omarchy.conf
#    style assign rule (monospace -> DejaVu Sans Mono) present. DejaVu
#    stands in for JetBrainsMono Nerd Font, which is not installed on
#    this VM; the mechanism (assign eats the alias before the user rule)
#    is identical, and the patched rule's second block names the real
#    target, JetBrainsMono Nerd Font.
#  - regression: the UNPATCHED font-set (upstream 94a8c3c, renamed the
#    way the fork renames it) leaves fc-match monospace on the assigned
#    default. Same harness, same fonts, only the bin differs.
#  - repair: the repair block extracted from the patched install.sh
#    rewrites an old single-block fonts.conf (Maple already chosen) to
#    the fixed two-block form, and fc-match monospace then returns Maple.
#    Second run is a no-op (sha-identical).
set -u
LIVE="/tmp/maple-live"
SIMROOT="/tmp/maple-simwork"
OUT="$SIMROOT/sim7out"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n "$LIVE/v2/install.sh" || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"

mkdir -p "$SIMROOT"
[ -e "$SIMROOT/up" ] || ln -s "$HOME/workspace/hexiri-2.0/simwork/up" "$SIMROOT/up"
sed 's|$HOME/workspace/hexiri-2.0/simwork|/tmp/maple-simwork|g; s|$HOME/workspace/hexiri-2.0|/tmp/maple-live|g' \
  "$HOME/workspace/hexiri-2.0/simwork/sim7.sh" > /tmp/maple-sim7.sh
bash /tmp/maple-sim7.sh >/tmp/sim26-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim26-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# --- static checks on the fork output ---
check "fork font-set has second match block" grep -q '<string>JetBrainsMono Nerd Font</string>' "$OUT/bin/hexciri-font-set"
check "fork font-set has second-match marker comment" grep -q 'Hexciri font-set second match' "$OUT/bin/hexciri-font-set"
check "fork font-set still has monospace block" grep -q '<string>monospace</string>' "$OUT/bin/hexciri-font-set"
check "fork font-set still writes fonts.conf" grep -q 'fontconfig/fonts.conf' "$OUT/bin/hexciri-font-set"
check "fork font-list queries spacing 100" grep -q 'fc-list :spacing=100' "$OUT/bin/hexciri-font-list"
check "fork font-list queries spacing 90 (PR 16025)" grep -q 'fc-list :spacing=90' "$OUT/bin/hexciri-font-list"
check "fork font-list keeps the emoji/signwriting/hexciri filter" grep -q "grep -v -i -E 'emoji|signwriting|hexciri'" "$OUT/bin/hexciri-font-list"
check "fork font-list has the dual-width comment" grep -q 'Dual-width fonts (spacing 90) are monospace too' "$OUT/bin/hexciri-font-list"
check "menu jsonc has maple row" grep -q '"install.style.font.maple"' "$OUT/default/hexciri/hexciri-menu.jsonc"
check "menu maple row is Maple Mono CN" grep -q '"label":"Maple Mono CN"' "$OUT/default/hexciri/hexciri-menu.jsonc"
check "menu maple row is disabled when the package is present" grep -q '"disabled":"hexciri-pkg-present maplemono-nf-cn"' "$OUT/default/hexciri/hexciri-menu.jsonc"
check "menu maple row installs maplemono-nf-cn via yay" grep -q "yay -S --needed --noconfirm maplemono-nf-cn" "$OUT/default/hexciri/hexciri-menu.jsonc"
check "menu maple row switches to Maple Mono NF CN" grep -q "hexciri-font-set" "$OUT/default/hexciri/hexciri-menu.jsonc"
check "i18n has maple label" grep -q '"install.style.font.maple"' "$OUT/default/i18n/en/menu.json"
check "i18n maple label is Maple Mono CN" bash -c "grep -A1 'install.style.font.maple' \"$OUT/default/i18n/en/menu.json\" | grep -q 'Maple Mono CN'"
check "menu maple row icon is the font glyph" grep -q '"install.style.font.maple": {"icon":"' "$OUT/default/hexciri/hexciri-menu.jsonc"
check "fork log records font-set patch" grep -q 'font-set: second fonts.conf match block' "$SIMROOT/sim7-fork.log"
check "fork log records maple menu row" grep -q 'Maple Mono CN row added' "$SIMROOT/sim7-fork.log"
check "fork log records font-list dual-width patch" grep -q 'font-list: also list dual-width' "$SIMROOT/sim7-fork.log"
check "fork log records i18n label" grep -q 'i18n: Maple Mono CN label added' "$SIMROOT/sim7-fork.log"
check "installer documents the 320 MiB no-auto-install reason" grep -q '320 MiB' "$LIVE/v2/install.sh"
check "installer does not auto-install maplemono-nf-cn" bash -c "! grep '^elif yay -S --needed --noconfirm maplemono-nf-cn' \"$LIVE/v2/install.sh\""
check "installer has maplemono-nf AUR step" grep -q 'yay -S --needed --noconfirm maplemono-nf' "$LIVE/v2/install.sh"
check "installer AUR step names the right package (no code line uses ttf-maple-mono-nf)" bash -c "! grep -v '^[[:space:]]*#' \"$LIVE/v2/install.sh\" | grep -q 'ttf-maple-mono-nf'"
check "installer has fonts.conf repair block" grep -q 'Repair font-set fonts.conf' "$LIVE/v2/install.sh"
check "installer has maple verify greps" grep -q 'install.style.font.maple' "$LIVE/v2/install.sh"
bash -n "$OUT/bin/hexciri-font-set" || { echo "FAIL: bash -n forked hexciri-font-set"; fail=$((fail+1)); }

# --- idempotency: second fork run, no duplicated rows/blocks ---
cp "$OUT/bin/hexciri-font-set" /tmp/sim26-fontset-1
cp "$OUT/default/hexciri/hexciri-menu.jsonc" /tmp/sim26-menu-1.jsonc
bash /tmp/maple-sim7.sh >/tmp/sim26-sim7-2.log 2>&1 || { echo "sim7 2nd run FAILED"; tail -20 /tmp/sim26-sim7-2.log; exit 1; }
check "2nd fork run idempotent (font-set identical)" cmp -s "$OUT/bin/hexciri-font-set" /tmp/sim26-fontset-1
check "2nd fork run idempotent (menu jsonc identical)" cmp -s "$OUT/default/hexciri/hexciri-menu.jsonc" /tmp/sim26-menu-1.jsonc
check "maple row appears exactly once" bash -c "[[ \$(grep -c 'install.style.font.maple' \"$OUT/default/hexciri/hexciri-menu.jsonc\") -eq 1 ]]"
check "second match block appears exactly once" bash -c "[[ \$(grep -c 'JetBrainsMono Nerd Font</string>' \"$OUT/bin/hexciri-font-set\") -eq 1 ]]"

# --- functional fontconfig harness ---
# Fonts: real Maple Mono NF v7.9 files in /tmp/maple-fc (Regular+Bold),
# plus this VM's system fonts. The 50-test.conf assign rule stands in
# for 50-omarchy.conf's monospace -> JetBrainsMono Nerd Font assign,
# with DejaVu Sans Mono as the installed stand-in target.
FUNC="/tmp/maple-func"
rm -rf "$FUNC"; mkdir -p "$FUNC/conf.d" "$FUNC/stubbin" "$FUNC/cache"
cat > "$FUNC/conf.d/50-test.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any"><string>monospace</string></test>
    <edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
  </match>
</fontconfig>
EOF
# Fallback after the assign: JetBrainsMono is not installed on this VM, so
# without an appended installed family fc-match falls through to whichever
# mono font coverage picks (Maple, non-discriminating). Appending DejaVu
# makes the no-user-rule result deterministic: DejaVu Sans Mono.
cat > "$FUNC/conf.d/51-fallback.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any"><string>JetBrainsMono Nerd Font</string></test>
    <edit name="family" mode="append" binding="strong"><string>DejaVu Sans Mono</string></edit>
  </match>
</fontconfig>
EOF
for s in hexciri-restart-shell hexciri-notification-send hexciri-hook; do
  printf '#!/bin/bash\nexit 0\n' > "$FUNC/stubbin/$s"; chmod +x "$FUNC/stubbin/$s"
done
printf '#!/bin/bash\necho ""\n' > "$FUNC/stubbin/hexciri-i18n"; chmod +x "$FUNC/stubbin/hexciri-i18n"
printf '#!/bin/bash\nexit 1\n' > "$FUNC/stubbin/hexciri-cmd-present"; chmod +x "$FUNC/stubbin/hexciri-cmd-present"
mkfcconf() { # $1 = stub home dir, $2 = out fonts.conf
  cat > "$2" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/tmp/maple-fc</dir>
  <dir>/usr/share/fonts</dir>
  <cachedir>$FUNC/cache</cachedir>
  <include ignore_missing="yes">$FUNC/conf.d</include>
  <include ignore_missing="yes">$1/.config/fontconfig/fonts.conf</include>
</fontconfig>
EOF
}
fcmatch_mono() { FONTCONFIG_FILE="$1" fc-match monospace -f '%{family}\n' 2>/dev/null | head -n1 | cut -d, -f1; }
export -f fcmatch_mono

# Baseline: assign rule present, no user fonts.conf yet -> assigned default.
H1="$FUNC/home1"; mkdir -p "$H1/.config/fontconfig"
mkfcconf "$H1" "$FUNC/fc1.conf"
check "baseline (assign, no user rule): fc-match monospace is the assigned default" bash -c "[[ \"\$(fcmatch_mono \"$FUNC/fc1.conf\")\" == 'DejaVu Sans Mono' ]]"
# Patched font-set.
HOME="$H1" FONTCONFIG_FILE="$FUNC/fc1.conf" PATH="$FUNC/stubbin:$PATH" bash "$OUT/bin/hexciri-font-set" "Maple Mono NF" >/tmp/sim26-set.log 2>&1 || { echo "FAIL: patched font-set exited non-zero"; cat /tmp/sim26-set.log; fail=$((fail+1)); }
check "patched font-set wrote fonts.conf" test -f "$H1/.config/fontconfig/fonts.conf"
check "patched fonts.conf has two match blocks" bash -c "[[ \$(grep -c '<match target=\"pattern\">' \"$H1/.config/fontconfig/fonts.conf\") -eq 2 ]]"
check "patched font-set: fc-match monospace is Maple Mono NF (assign present)" bash -c "[[ \"\$(fcmatch_mono \"$FUNC/fc1.conf\")\" == 'Maple Mono NF' ]]"
check "patched font-set: font-list includes Maple Mono NF" bash -c "FONTCONFIG_FILE=\"$FUNC/fc1.conf\" fc-list :spacing=100 -f \"%{family[0]}\\n\" 2>/dev/null | grep -qx 'Maple Mono NF'"
check "patched font-set: no fontconfig warnings" bash -c "! FONTCONFIG_FILE=\"$FUNC/fc1.conf\" fc-match monospace 2>&1 >/dev/null | grep -qi warning"

# Regression: unpatched font-set, same harness, same fonts.
sed 's/omarchy-/hexciri-/g' /tmp/maple-upstream/omarchy-font-set > "$FUNC/unpatched-font-set"
bash -n "$FUNC/unpatched-font-set"
H2="$FUNC/home2"; mkdir -p "$H2/.config/fontconfig"
mkfcconf "$H2" "$FUNC/fc2.conf"
HOME="$H2" FONTCONFIG_FILE="$FUNC/fc2.conf" PATH="$FUNC/stubbin:$PATH" bash "$FUNC/unpatched-font-set" "Maple Mono NF" >/tmp/sim26-set-unpatched.log 2>&1 || { echo "FAIL: unpatched font-set exited non-zero"; cat /tmp/sim26-set-unpatched.log; fail=$((fail+1)); }
check "regression: unpatched fonts.conf has one match block" bash -c "[[ \$(grep -c '<match target=\"pattern\">' \"$H2/.config/fontconfig/fonts.conf\") -eq 1 ]]"
check "regression: unpatched font-set leaves fc-match monospace on the assigned default" bash -c "[[ \"\$(fcmatch_mono \"$FUNC/fc2.conf\")\" == 'DejaVu Sans Mono' ]]"

# --- CN font-list functional test (PR #16025, the reported bug) ---
# Real Maple Mono NF CN v7.9 files (Regular+Bold) in /tmp/maple-fc-cn.
# The forked list must offer Maple Mono NF CN; the unpatched upstream
# list (spacing=100 only) must not, even with the files installed.
CNFC="$FUNC/cn.conf"
cat > "$CNFC" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/tmp/maple-fc-cn</dir>
  <dir>/tmp/maple-fc</dir>
  <dir>/usr/share/fonts</dir>
  <cachedir>$FUNC/cache</cachedir>
</fontconfig>
EOF
check "CN files really are spacing 90" bash -c "fc-scan --format '%{spacing}\\n' /tmp/maple-fc-cn/MapleMono-NF-CN-Regular.ttf 2>/dev/null | grep -qx 90"
check "CN files really are family Maple Mono NF CN" bash -c "fc-scan --format '%{family[0]}\\n' /tmp/maple-fc-cn/MapleMono-NF-CN-Regular.ttf 2>/dev/null | grep -qx 'Maple Mono NF CN'"
check "patched font-list offers Maple Mono NF CN" bash -c "FONTCONFIG_FILE=\"$CNFC\" bash \"$OUT/bin/hexciri-font-list\" | grep -qx 'Maple Mono NF CN'"
check "patched font-list still offers Maple Mono NF" bash -c "FONTCONFIG_FILE=\"$CNFC\" bash \"$OUT/bin/hexciri-font-list\" | grep -qx 'Maple Mono NF'"
check "patched font-list offers CN exactly once (dedup)" bash -c "[[ \$(FONTCONFIG_FILE=\"$CNFC\" bash \"$OUT/bin/hexciri-font-list\" | grep -c '^Maple Mono NF CN$') -eq 1 ]]"
check "patched font-list is sorted and unique" bash -c "FONTCONFIG_FILE=\"$CNFC\" bash \"$OUT/bin/hexciri-font-list\" | sort -c -u"
cp /tmp/maple-upstream/omarchy-font-list "$FUNC/unpatched-font-list"
bash -n "$FUNC/unpatched-font-list"
check "regression: unpatched font-list omits Maple Mono NF CN" bash -c "! FONTCONFIG_FILE=\"$CNFC\" bash \"$FUNC/unpatched-font-list\" | grep -qx 'Maple Mono NF CN'"
check "regression: unpatched font-list still offers Maple Mono NF" bash -c "FONTCONFIG_FILE=\"$CNFC\" bash \"$FUNC/unpatched-font-list\" | grep -qx 'Maple Mono NF'"

# Repair block: old single-block fonts.conf (Maple already chosen), extracted
# verbatim from the patched install.sh and run with a stub HOME.
H3="$FUNC/home3"; mkdir -p "$H3/.config/fontconfig"
cat > "$H3/.config/fontconfig/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>Maple Mono NF</string>
    </edit>
  </match>
</fontconfig>
EOF
mkfcconf "$H3" "$FUNC/fc3.conf"
check "repair pre-check: old file leaves fc-match monospace on the assigned default" bash -c "[[ \"\$(fcmatch_mono \"$FUNC/fc3.conf\")\" == 'DejaVu Sans Mono' ]]"
START=$(grep -n '^# --- Repair font-set fonts.conf' "$LIVE/v2/install.sh" | cut -d: -f1)
END=$(grep -n '^# --- end Maple Mono NF fonts.conf repair ---' "$LIVE/v2/install.sh" | cut -d: -f1)
[ -n "$START" ] && [ -n "$END" ] || { echo "FAIL: repair block markers not found"; exit 1; }
sed -n "${START},${END}p" "$LIVE/v2/install.sh" > /tmp/sim26-repair.sh
cat > /tmp/sim26-repair-run.sh <<'EOF'
info() { printf '[hexciri] %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
EOF
cat /tmp/sim26-repair.sh >> /tmp/sim26-repair-run.sh
bash -n /tmp/sim26-repair-run.sh || { echo "FAIL: bash -n repair block"; fail=$((fail+1)); }
cp "$H3/.config/fontconfig/fonts.conf" /tmp/sim26-repair-before.conf
HOME="$H3" FONTCONFIG_FILE="$FUNC/fc3.conf" bash /tmp/sim26-repair-run.sh >/tmp/sim26-repair.log 2>&1
cat /tmp/sim26-repair.log
check "repair rewrote the file with the second block" grep -q 'Hexciri font-set second match' "$H3/.config/fontconfig/fonts.conf"
check "repair kept the chosen family" grep -q '<string>Maple Mono NF</string>' "$H3/.config/fontconfig/fonts.conf"
check "repair: fc-match monospace is Maple Mono NF" bash -c "[[ \"\$(fcmatch_mono \"$FUNC/fc3.conf\")\" == 'Maple Mono NF' ]]"
cp "$H3/.config/fontconfig/fonts.conf" /tmp/sim26-repair-after1.conf
HOME="$H3" FONTCONFIG_FILE="$FUNC/fc3.conf" bash /tmp/sim26-repair-run.sh >/tmp/sim26-repair2.log 2>&1
check "repair 2nd run is a no-op (file identical)" cmp -s /tmp/sim26-repair-after1.conf "$H3/.config/fontconfig/fonts.conf"
# Hand-written file (no prepend_first) must be untouched by the repair.
H4="$FUNC/home4"; mkdir -p "$H4/.config/fontconfig"
printf '<fontconfig><match target="pattern"><test name="family"><string>monospace</string></test><edit name="family" mode="append"><string>DejaVu Sans Mono</string></edit></match></fontconfig>\n' > "$H4/.config/fontconfig/fonts.conf"
cp "$H4/.config/fontconfig/fonts.conf" /tmp/sim26-hand.conf
HOME="$H4" FONTCONFIG_FILE="$FUNC/fc3.conf" bash /tmp/sim26-repair-run.sh >/dev/null 2>&1
check "repair leaves a hand-written fonts.conf alone" cmp -s /tmp/sim26-hand.conf "$H4/.config/fontconfig/fonts.conf"

echo "---- sim26: $pass passed, $fail failed ----"
[ "$fail" -eq 0 ] || exit 1
