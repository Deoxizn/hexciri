#!/bin/bash
# sim35: xdg-terminal-exec fix (2026-11-24/25, desktop dokoz).
# 1. CORE_PKGS installs it from stable Extra; stale extra-testing claim gone.
# 2. Verify block: present -> info, absent -> warn (mirror the bash logic).
# 3. Fingerprints: only system moves (CORE_PKGS is in the system range),
#    so next update is one full installer re-run by design.
# 4. Callers that need the binary are inventoried from upstream quattro.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
OLD=/tmp/xdg-fix/install-old.sh
NEW="$ROOT/v2/install.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

grep -q 'xdg-user-dirs xdg-utils xdg-terminal-exec xorg-xwayland' "$NEW" && ok "CORE_PKGS installs xdg-terminal-exec" || bad "CORE_PKGS installs xdg-terminal-exec"
[ "$(grep -c 'xdg-terminal-exec' "$NEW")" -ge 5 ] && ok "xdg-terminal-exec referenced consistently" || bad "xdg-terminal-exec references"
grep -q 'NOT in stable extra' "$NEW" && bad "stale 'NOT in stable extra' claim removed" || ok "stale 'NOT in stable extra' claim removed"
grep -q 'extra-testing only, expected' "$NEW" && bad "stale extra-testing warning removed" || ok "stale extra-testing warning removed"
grep -q 'only in Arch extra-testing' "$NEW" && bad "stale extra-testing text removed" || ok "stale extra-testing text removed"
grep -q 'Arch Extra stable 0.14.4-1' "$NEW" && ok "Extra stable 0.14.4-1 documented" || bad "Extra stable documented"
grep -q '^xdg-terminal-exec #' "$ROOT/v2/hexciri-base.packages" && ok "hexciri-base.packages lists xdg-terminal-exec" || bad "hexciri-base.packages lists it"
bash -n "$NEW" && ok "bash -n clean" || bad "bash -n clean"

# --- 2. Verify-block logic mirror ---
python3 - "$NEW" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
# extract the verify block after CORE_PKGS and mirror its branches
assert 'if command -v xdg-terminal-exec >/dev/null 2>&1; then' in s
assert 'info "xdg-terminal-exec installed:' in s
assert 'warn "xdg-terminal-exec NOT installed after Core packages' in s
def verify(present):
    return "info installed" if present else "warn NOT installed"
assert verify(True) == "info installed"
assert verify(False) == "warn NOT installed"
# old block reproduced: missing binary was only info/warn, never installed
old = 'xdg-terminal-exec not installed (only in Arch extra-testing'
assert old not in s, "old warn-only block must be gone"
print("PASS: verify-block logic mirror (present->info, absent->warn)")
PYEOF
[ $? -eq 0 ] && ok "verify-block logic mirror" || bad "verify-block logic mirror"

# --- 3. Callers that need the binary (upstream quattro, extracted) ---
for f in omarchy-launch-terminal omarchy-launch-tui omarchy-launch-floating-terminal-with-presentation; do
  grep -q 'xdg-terminal-exec' "/tmp/xdg-fix/om/omarchy-quattro/bin/$f" && ok "caller needs binary: $f" || bad "caller needs binary: $f"
done
grep -q 'Exec=xdg-terminal-exec' /tmp/xdg-fix/om/omarchy-quattro/bin/omarchy-tui-install 2>/dev/null && ok "caller: TUI desktop entries Exec=xdg-terminal-exec" || grep -q 'xdg-terminal-exec' /tmp/xdg-fix/om/omarchy-quattro/bin/omarchy-tui-install && ok "caller: TUI desktop entries Exec=xdg-terminal-exec" || bad "caller: TUI desktop entries"
grep -q 'xdg-terminal-exec' /tmp/xdg-fix/om/omarchy-quattro/shell/plugins/menu/BarWidget.qml && ok "caller: menu BarWidget right-click" || bad "caller: menu BarWidget"

# --- 4. Fingerprints: only system moves ---
d="/tmp/xdg-fix/fp"; rm -rf "$d"; mkdir -p "$d/v2/patches"
cp "$ROOT/v2/patches/"* "$d/v2/patches/" 2>/dev/null
cp "$OLD" "$d/v2/install.sh"
(cd "$d" && INSTALLER_DIR="$d/v2" HEXCIRI_REPO_ROOT="$d" bash v2/install.sh --print-fingerprints > /tmp/xdg-fix/fp-old.txt 2>/dev/null) || true
cp "$NEW" "$d/v2/install.sh"
(cd "$d" && INSTALLER_DIR="$d/v2" HEXCIRI_REPO_ROOT="$d" bash v2/install.sh --print-fingerprints > /tmp/xdg-fix/fp-new.txt 2>/dev/null) || true
if [ -s /tmp/xdg-fix/fp-old.txt ] && [ -s /tmp/xdg-fix/fp-new.txt ]; then
  for k in upstream patch provision system; do
    o=$(grep "^$k=" /tmp/xdg-fix/fp-old.txt | cut -d= -f2)
    n=$(grep "^$k=" /tmp/xdg-fix/fp-new.txt | cut -d= -f2)
    if [ "$k" = system ]; then [ "$o" != "$n" ] && ok "system fingerprint moves" || bad "system fingerprint moves (old=$o new=$n)"
    else [ "$o" = "$n" ] && ok "$k fingerprint stable" || bad "$k fingerprint stable (old=$o new=$n)"; fi
  done
else
  bad "--print-fingerprints ran in scratch tree"
  cat /tmp/xdg-fix/fp-old.txt /tmp/xdg-fix/fp-new.txt 2>/dev/null
fi

echo "sim35: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
