#!/bin/bash
# sim27: Maple Mono NF CN reinstall on update (2026-11-24, Devi).
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/maple-reinstall, then functionally proves the guard:
#  - the AUR step skips yay when ANY Maple NF package is installed
#    (pacman -Q), for both AUR namings, plain + CN + unhinted;
#  - it still skips on the fc-list guard alone (hand-installed fonts);
#  - it only runs yay (for maplemono-nf, never maplemono-nf-cn) when
#    nothing is installed and fc-list has no Maple family;
#  - regression: the UNPATCHED cf3bb1a3 step runs yay when
#    maplemono-nf-cn is installed but fc-list does not list it (the
#    stale-cache hole the old fc-list-only guard had);
#  - the new hexciri-font-maple-cn-present bin exits 0 for any CN
#    package name and 1 otherwise.
# No pacman, no yay, no network: pacman/fc-list/yay are stubs.
set -u
LIVE="/tmp/maple-reinstall"
SIMROOT="/tmp/maple-reinstall-simwork"
OUT="$SIMROOT/sim7out"
UNPATCHED="/tmp/maple-reinstall-live-install.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n "$LIVE/v2/install.sh" || { echo "bash -n install.sh FAILED"; exit 1; }
bash -n "$LIVE/v2/hexciri-font-maple-cn-present" || { echo "bash -n new bin FAILED"; exit 1; }
echo "bash -n clean"

mkdir -p "$SIMROOT"
[ -e "$SIMROOT/up" ] || ln -s "$HOME/workspace/hexiri-2.0/simwork/up" "$SIMROOT/up"
sed 's|$HOME/workspace/hexiri-2.0/simwork|/tmp/maple-reinstall-simwork|g; s|$HOME/workspace/hexiri-2.0|/tmp/maple-reinstall|g' \
  "$HOME/workspace/hexiri-2.0/simwork/sim7.sh" > /tmp/maple-reinstall-sim7.sh
bash /tmp/maple-reinstall-sim7.sh >/tmp/sim27-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim27-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# --- static checks on the fork output ---
check "fork has hexciri-font-maple-cn-present" test -x "$OUT/bin/hexciri-font-maple-cn-present"
check "fork bin checks both CN package names" grep -q 'maple-mono-nf-cn' "$OUT/bin/hexciri-font-maple-cn-present"
check "fork bin checks maplemono-nf-cn" grep -q 'maplemono-nf-cn' "$OUT/bin/hexciri-font-maple-cn-present"
check "menu maple row uses new disabled bin" grep -q '"disabled":"hexciri-font-maple-cn-present"' "$OUT/default/hexciri/hexciri-menu.jsonc"
check "menu maple row no longer uses pkg-present for CN" bash -c "! grep 'install.style.font.maple' \"$OUT/default/hexciri/hexciri-menu.jsonc\" | grep -q 'hexciri-pkg-present maplemono-nf-cn'"
check "menu maple row still installs CN via yay on click" grep -q "yay -S --needed --noconfirm maplemono-nf-cn" "$OUT/default/hexciri/hexciri-menu.jsonc"
check "sim7 output records new bin copy" grep -q 'hexciri-font-maple-cn-present installed' /tmp/sim27-sim7.log
check "installer AUR step has pacman -Q guard" grep -q 'pacman -Q maplemono-nf maplemono-nf-cn' "$LIVE/v2/install.sh"
check "installer AUR step keeps fc-list as second guard" grep -q 'info "Maple Mono NF already installed (fontconfig)"' "$LIVE/v2/install.sh"
check "installer AUR step never installs cn as a step" bash -c "! grep -E '^elif yay -S --needed --noconfirm maplemono-nf-cn' \"$LIVE/v2/install.sh\""
check "installer placement verify greps new disabled bin" grep -q "hexciri-font-maple-cn-present' \"\$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc\"" "$LIVE/v2/install.sh"
check "installer documents split-base CN download" grep -q 'downloads ALL 11 source zips' "$LIVE/v2/install.sh"
check "patch fingerprint hashes new bin" grep -q 'hexciri-font-maple-cn-present' "$LIVE/v2/install.sh"

# --- idempotency: second fork run ---
cp "$OUT/bin/hexciri-font-maple-cn-present" /tmp/sim27-bin-1
cp "$OUT/default/hexciri/hexciri-menu.jsonc" /tmp/sim27-menu-1.jsonc
bash /tmp/maple-reinstall-sim7.sh >/tmp/sim27-sim7-2.log 2>&1 || { echo "sim7 2nd run FAILED"; tail -20 /tmp/sim27-sim7-2.log; exit 1; }
check "2nd fork run idempotent (new bin identical)" cmp -s "$OUT/bin/hexciri-font-maple-cn-present" /tmp/sim27-bin-1
check "2nd fork run idempotent (menu jsonc identical)" cmp -s "$OUT/default/hexciri/hexciri-menu.jsonc" /tmp/sim27-menu-1.jsonc
check "maple row appears exactly once" bash -c "[[ \$(grep -c 'install.style.font.maple' \"$OUT/default/hexciri/hexciri-menu.jsonc\") -eq 1 ]]"

# --- functional guard harness: stub pacman / fc-list / yay ---
FUNC="/tmp/maple-reinstall-func"; mkdir -p "$FUNC/stubbin"
cat > "$FUNC/stubbin/pacman" <<'EOF'
#!/bin/bash
# stub: pacman -Q <names...>; prints installed ones from $MAPLE_INSTALLED
[ "$1" = "-Q" ] || exit 1; shift
found=0
for pkg in "$@"; do
  case " $MAPLE_INSTALLED " in *" $pkg "*) echo "$pkg 7.9-1"; found=1;; esac
done
[ "$found" -eq 1 ]
EOF
cat > "$FUNC/stubbin/fc-list" <<'EOF'
#!/bin/bash
printf '%s' "$FC_LIST_OUTPUT"
EOF
cat > "$FUNC/stubbin/yay" <<'EOF'
#!/bin/bash
echo "$*" >> "$YAY_LOG"
exit 0
EOF
chmod +x "$FUNC/stubbin/pacman" "$FUNC/stubbin/fc-list" "$FUNC/stubbin/yay"

# Extract the AUR step block verbatim from a given install.sh.
extract_step() {
  local src="$1" dst="$2"
  local start end
  start=$(grep -n '^# --- Maple Mono NF' "$src" | cut -d: -f1)
  end=$(awk -v s="$start" 'NR>s && /^fi$/ {print NR; exit}' "$src")
  [ -n "$start" ] && [ -n "$end" ] || { echo "FAIL: step markers not found in $src"; return 1; }
  sed -n "${start},${end}p" "$src" > "$dst"
}
run_step() {
  # $1 = install.sh source, $2 = MAPLE_INSTALLED, $3 = FC_LIST_OUTPUT
  local src="$1" installed="$2" fclist="$3"
  : > "$FUNC/yay.log"
  cat > "$FUNC/run.sh" <<'EOF'
step() { printf '\n==> %s\n' "$1"; }
info() { printf '[hexciri] %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
EOF
  extract_step "$src" "$FUNC/step.sh" || return 1
  cat "$FUNC/step.sh" >> "$FUNC/run.sh"
  MAPLE_INSTALLED="$installed" FC_LIST_OUTPUT="$fclist" YAY_LOG="$FUNC/yay.log" \
    PATH="$FUNC/stubbin:/usr/bin:/bin" bash "$FUNC/run.sh" >"$FUNC/run.log" 2>&1
}
cat > "$FUNC/yay_calls.sh" <<'EOF'
#!/bin/bash
grep -c . "$FUNC/yay.log" 2>/dev/null || echo 0
EOF
chmod +x "$FUNC/yay_calls.sh"
yay_calls() { "$FUNC/yay_calls.sh"; }

run_step "$LIVE/v2/install.sh" "maplemono-nf-cn" "" >/dev/null 2>&1
check "guard: maplemono-nf-cn installed -> yay NOT called" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 0 ]]"
check "guard: maplemono-nf-cn installed -> pacman skip logged" grep -q 'already installed (pacman:' "$FUNC/run.log"
run_step "$LIVE/v2/install.sh" "maple-mono-nf-cn" "" >/dev/null 2>&1
check "guard: maple-mono-nf-cn (hyphenated) installed -> yay NOT called" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 0 ]]"
run_step "$LIVE/v2/install.sh" "maplemono-nf" "" >/dev/null 2>&1
check "guard: plain maplemono-nf installed -> yay NOT called" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 0 ]]"
run_step "$LIVE/v2/install.sh" "maplemono-nf-cn-unhinted" "" >/dev/null 2>&1
check "guard: maplemono-nf-cn-unhinted installed -> yay NOT called" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 0 ]]"
run_step "$LIVE/v2/install.sh" "" "Maple Mono NF CN" >/dev/null 2>&1
check "guard: nothing in pacman, fc-list has CN -> yay NOT called" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 0 ]]"
check "guard: fc-list path logs fontconfig skip" grep -q 'already installed (fontconfig)' "$FUNC/run.log"
run_step "$LIVE/v2/install.sh" "" "" >/dev/null 2>&1
check "guard: nothing installed anywhere -> yay called once" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 1 ]]"
check "guard: yay installs plain maplemono-nf only" grep -qx -- '-S --needed --noconfirm maplemono-nf' "$FUNC/yay.log"
check "guard: yay never asked for maplemono-nf-cn" bash -c "! grep -q 'maplemono-nf-cn' \"$FUNC/yay.log\""

# Regression: unpatched cf3bb1a3 step, CN installed in pacman but
# fc-list empty (stale cache hole) -> old code runs yay.
run_step "$UNPATCHED" "maplemono-nf-cn" "" >/dev/null 2>&1
check "regression: unpatched step runs yay despite CN installed (fc-list empty)" bash -c "[[ $(grep -c . "$FUNC/yay.log" 2>/dev/null || true) -eq 1 ]]"
check "regression: unpatched step installs plain maplemono-nf" grep -qx -- '-S --needed --noconfirm maplemono-nf' "$FUNC/yay.log"

# --- new bin functional test (same pacman stub) ---
cat > "$FUNC/run_bin.sh" <<'EOF'
#!/bin/bash
MAPLE_INSTALLED="$1" PATH="$FUNC/stubbin:/usr/bin:/bin" bash "$OUT/bin/hexciri-font-maple-cn-present"
EOF
chmod +x "$FUNC/run_bin.sh"
run_bin() { "$FUNC/run_bin.sh" "$1"; }
check "bin: maplemono-nf-cn installed -> exit 0" env MAPLE_INSTALLED=maplemono-nf-cn PATH="$FUNC/stubbin:/usr/bin:/bin" bash "$OUT/bin/hexciri-font-maple-cn-present"
check "bin: maple-mono-nf-cn installed -> exit 0" env MAPLE_INSTALLED=maple-mono-nf-cn PATH="$FUNC/stubbin:/usr/bin:/bin" bash "$OUT/bin/hexciri-font-maple-cn-present"
check "bin: maplemono-nf-cn-unhinted installed -> exit 0" env MAPLE_INSTALLED=maplemono-nf-cn-unhinted PATH="$FUNC/stubbin:/usr/bin:/bin" bash "$OUT/bin/hexciri-font-maple-cn-present"
check "bin: plain maplemono-nf only -> exit 1" bash -c "! MAPLE_INSTALLED=maplemono-nf PATH=\"$FUNC/stubbin:/usr/bin:/bin\" bash \"$OUT/bin/hexciri-font-maple-cn-present\""
check "bin: nothing installed -> exit 1" bash -c "! MAPLE_INSTALLED= PATH=\"$FUNC/stubbin:/usr/bin:/bin\" bash \"$OUT/bin/hexciri-font-maple-cn-present\""

echo "---- sim27: $pass passed, $fail failed ----"
[ "$fail" -eq 0 ] || exit 1
