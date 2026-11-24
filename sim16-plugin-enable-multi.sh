#!/bin/bash
# sim16: hexciri-plugin-enable multi-id patch.
# Applies the fork patch block extracted from v2/install.sh to a pristine
# forked bin/hexciri-plugin-enable (sim7out copy), then runs the patched
# script against stubbed hexciri-plugin-catalog / hexciri-shell / hexciri.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FORK_OUT="$WORK/fork-out"
export FORK_OUT
mkdir -p "$FORK_OUT/bin"
cp "$ROOT/simwork/sim7out/bin/hexciri-plugin-enable" "$FORK_OUT/bin/hexciri-plugin-enable"
export _patch_log="$WORK/patch.log"
: > "$_patch_log"
warn() { echo "warn: $*" >>"$_patch_log"; }
info() { echo "info: $*" >>"$_patch_log"; }
die() { echo "die: $*" >&2; exit 1; }
export -f warn info die

# Extract the patch block from install.sh and run it (twice: idempotency).
python3 - "$ROOT/v2/install.sh" "$WORK/block.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index("# --- hexciri-plugin-enable accepts multiple ids")
end = s.index("# Save the fully patched fork for the next re-run (fork cache,")
open(sys.argv[2], "w").write(s[start:end])
PY
bash "$WORK/block.sh" >>"$_patch_log" 2>&1 || { echo "PATCH BLOCK FAILED"; cat "$_patch_log"; exit 1; }
cp "$FORK_OUT/bin/hexciri-plugin-enable" "$WORK/patched-once"
bash "$WORK/block.sh" >>"$_patch_log" 2>&1 || { echo "PATCH BLOCK 2ND RUN FAILED"; cat "$_patch_log"; exit 1; }
bash -n "$FORK_OUT/bin/hexciri-plugin-enable" || { echo "bash -n FAILED"; exit 1; }
cmp -s "$WORK/patched-once" "$FORK_OUT/bin/hexciri-plugin-enable" || { echo "NOT IDEMPOTENT"; exit 1; }
grep -q "Hexciri: enable multiple plugins" "$FORK_OUT/bin/hexciri-plugin-enable" || { echo "MARKER MISSING"; exit 1; }
echo "patch: applied, idempotent, bash -n clean"
cat "$_patch_log"

# Stubs.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/hexciri-plugin-catalog" <<'SH'
#!/bin/bash
cat <<'JSON'
[{"id":"pizza.dirty.nyxiri","kinds":["bar"]},{"id":"pizza.dirty.nyxiri-menu","kinds":["menu","bar-widget"]},{"id":"pizza.dirty.nyxiri-workspaces","kinds":["bar-widget"]},{"id":"pizza.dirty.clock","kinds":["bar-widget"]},{"id":"pizza.dirty.weather","kinds":["bar-widget"]},{"id":"pizza.dirty.arch-updates","kinds":["bar-widget"]},{"id":"hexciri.active-window","kinds":["bar-widget"]},{"id":"hexciri.clock","kinds":["bar-widget"]},{"id":"hexciri.dropbox","kinds":["bar-widget"]},{"id":"hexciri.bar","kinds":["bar"]}]
JSON
SH
cat >"$WORK/bin/hexciri-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$HEX_TEST_CALLS"
case "$*" in
  *unknown*) printf 'unknown\n' ;;
  *) printf 'ok\n' ;;
esac
SH
cat >"$WORK/bin/hexciri" <<'SH'
#!/bin/bash
printf 'hexciri %s\n' "$*" >>"$HEX_TEST_CALLS"
echo "Using $3 as the active bar"
SH
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
export HEX_TEST_CALLS="$WORK/calls"
BIN="$FORK_OUT/bin/hexciri-plugin-enable"

pass=0; fail=0
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "ok: $name"; else fail=$((fail+1)); echo "FAIL: $name"; fi
}

# 1. Devi's second command (bar already switched): 5 ids, all enabled.
: > "$WORK/calls"
out="$("$BIN" pizza.dirty.nyxiri-menu pizza.dirty.nyxiri-workspaces pizza.dirty.clock pizza.dirty.weather pizza.dirty.arch-updates 2>&1)"; rc=$?
check "devi cmd2 exit 0" test "$rc" -eq 0
check "devi cmd2 all Enabled" test "$(printf '%s' "$out" | grep -c '^Enabled ')" -eq 5
check "devi cmd2 5 enablePlugin {} calls" test "$(grep -c 'shell enablePlugin .* {}' "$WORK/calls")" -eq 5
check "devi cmd2 no bar use" test "$(grep -c 'hexciri bar use' "$WORK/calls")" -eq 0

# 2. Devi's first command (bar first): bar switches, rest enabled.
: > "$WORK/calls"
out="$("$BIN" pizza.dirty.nyxiri pizza.dirty.nyxiri-menu pizza.dirty.nyxiri-workspaces pizza.dirty.clock pizza.dirty.weather pizza.dirty.arch-updates 2>&1)"; rc=$?
check "devi cmd1 exit 0" test "$rc" -eq 0
check "devi cmd1 bar switched" test "$(printf '%s' "$out" | grep -c 'Now using pizza.dirty.nyxiri as the bar')" -eq 1
check "devi cmd1 bar use called once" test "$(grep -c 'hexciri bar use pizza.dirty.nyxiri' "$WORK/calls")" -eq 1
check "devi cmd1 other 5 enabled" test "$(printf '%s' "$out" | grep -c '^Enabled ')" -eq 5

# 3. Single id + --section right (upstream behaviour).
: > "$WORK/calls"
out="$("$BIN" hexciri.active-window --section right 2>&1)"; rc=$?
check "single --section exit 0" test "$rc" -eq 0
check "single --section call" grep -Fqx 'shell enablePlugin hexciri.active-window {"section":"right"}' "$WORK/calls"
check "single --section msg" test "$(printf '%s' "$out" | grep -c 'Enabled and moved hexciri.active-window')" -eq 1

# 4. Single id + positional section.
: > "$WORK/calls"
out="$("$BIN" hexciri.clock --before hexciri.weather 2>&1)"; rc=$?
check "single --before call" grep -Fqx 'shell enablePlugin hexciri.clock {"before":"hexciri.weather"}' "$WORK/calls"

# 5. Bare single id, default placement.
: > "$WORK/calls"
"$BIN" hexciri.dropbox >/dev/null 2>&1; rc=$?
check "bare single call {}" grep -Fqx 'shell enablePlugin hexciri.dropbox {}' "$WORK/calls"

# 6. Bar + placement still rejected (upstream test).
: > "$WORK/calls"
"$BIN" pizza.dirty.nyxiri --section right >/dev/null 2>&1; rc=$?
check "bar + placement fails" test "$rc" -ne 0
check "bar + placement no calls" test "$(wc -l < "$WORK/calls")" -eq 0

# 7. Unknown id in multi: others still enabled, exit non-zero.
: > "$WORK/calls"
out="$("$BIN" pizza.dirty.clock pizza.dirty.unknown pizza.dirty.weather 2>&1)"; rc=$?
check "unknown in multi exit 1" test "$rc" -eq 1
check "unknown in multi others enabled" test "$(printf '%s' "$out" | grep -c '^Enabled ')" -eq 2
check "unknown in multi error named" test "$(printf '%s' "$out" | grep -c "not known")" -eq 1

# 8. No args.
"$BIN" >/dev/null 2>&1; rc=$?
check "no args fails" test "$rc" -ne 0

# 9. Single bare bar id delegates to bar use.
: > "$WORK/calls"
out="$("$BIN" pizza.dirty.nyxiri 2>&1)"; rc=$?
check "bare bar exit 0" test "$rc" -eq 0
check "bare bar via bar use" test "$(grep -c 'hexciri bar use pizza.dirty.nyxiri' "$WORK/calls")" -eq 1
check "bare bar msg" test "$(printf '%s' "$out" | grep -c 'Now using pizza.dirty.nyxiri as the bar')" -eq 1

# 10. Help mentions multi-id.
out="$("$BIN" --help 2>&1)"
check "help shows <id>..." test "$(printf '%s' "$out" | grep -c 'enable <id>\.\.\.')" -eq 1

echo "sim16: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
