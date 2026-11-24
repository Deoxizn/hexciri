#!/bin/bash
# sim20: WidgetButton forwards click modifiers (Shift+right-click).
# Runs the sim7 fork pipeline verbatim against pristine upstream 94a8c3c,
# then checks the forked shell/Ui/WidgetButton.qml, plus the stock
# clock/weather right-click actions that the modifiers make possible.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n "$ROOT/v2/install.sh" || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
bash "$ROOT/simwork/sim7.sh" >/tmp/sim20-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim20-sim7.log; exit 1; }
WB="$ROOT/simwork/sim7out/shell/Ui/WidgetButton.qml"
check "WidgetButton exists" test -f "$WB"
check "signal carries modifiers" grep -q 'signal pressed(int button, int modifiers)' "$WB"
check "triggerPress takes modifiers" grep -q 'function triggerPress(button, modifiers)' "$WB"
check "triggerPress defaults to NoModifier" grep -q 'modifiers !== undefined ? modifiers : Qt.NoModifier' "$WB"
check "onClicked passes mouse.modifiers" grep -q 'root.triggerPress(mouse.button, mouse.modifiers)' "$WB"
check "old signal gone" bash -c "! grep -q 'signal pressed(int button)$' \"$WB\""
check "old triggerPress gone" bash -c "! grep -q 'function triggerPress(button) {' \"$WB\""
# Existing one-arg handlers are unaffected: stock clock still cycles
# format on plain right-click, stock weather still notifies.
check "stock clock right-click cycles format" grep -q 'if (b === Qt.RightButton) root.cycleFormat()' "$ROOT/simwork/sim7out/shell/plugins/panels/clock/BarWidget.qml"
check "stock weather right-click notifies" grep -q 'hexciri-notification-send' "$ROOT/simwork/sim7out/shell/plugins/panels/weather/BarWidget.qml"
check "stock one-arg onPressed handlers intact" grep -q 'onPressed: function(b)' "$ROOT/simwork/sim7out/shell/plugins/panels/clock/BarWidget.qml"
# Idempotency: run the fork pipeline a second time (sim7 wipes and
# re-forks from pristine upstream), same result.
bash "$ROOT/simwork/sim7.sh" >/tmp/sim20-sim7b.log 2>&1 || { echo "sim7 2nd run FAILED"; exit 1; }
check "2nd fork run: modifiers still forwarded" grep -q 'signal pressed(int button, int modifiers)' "$WB"
# Menu row removal (sim19) still holds after this patch.
check "menu still has no Settings row" bash -c "! grep -q '\"settings\".*hexciri-launch-settings' \"$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc\""
echo "sim20: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
