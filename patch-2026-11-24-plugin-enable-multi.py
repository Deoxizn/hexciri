#!/usr/bin/env python3
"""Patch hexciri-plugin-enable to accept multiple plugin ids (2026-11-24).

Root cause (Devi 13:35 MST): `hexciri plugin enable a b c` takes exactly
one id upstream; a second argument is placement. So the Nyxiri enable
command died with "unknown placement option: pizza.dirty.clock" (and a
bar as first id died with the bar guard) and enabled NOTHING.
`hexciri bar use pizza.dirty.nyxiri` worked, so the bar was active but
menu/workspaces/clock/weather/arch-updates stayed disabled.

Fix: fork patch in v2/install.sh, right after the plugin-update patch
block. Rewrites bin/hexciri-plugin-enable (full-file rewrite, guarded by
an anchor assert on the upstream metadata line + a Hexciri marker for
idempotency):
- multiple ids, no placement: enable each in turn; a bar id switches
  via `hexciri bar use` (edits shell.json directly, works from tty3,
  unlike enablePlugin IPC); unknown ids error but do not stop the rest;
  exit non-zero if any failed.
- any placement option present (or a positional section name as 2nd
  arg): single-plugin mode, upstream behaviour verbatim, including the
  bar-placement guard.
- single bare bar id also delegates to `hexciri bar use`.
- metadata updated: args <id>... [placement], multi-id example.
Patch fingerprint covers this region, so one patch-only re-apply.
"""
import hashlib
import sys

ROOT = "/home/hatch/workspace/hexiri-2.0"
PATH = ROOT + "/v2/install.sh"

with open(PATH, "rb") as f:
    data = f.read()
blob = b"blob " + str(len(data)).encode() + b"\0" + data
assert hashlib.sha1(blob).hexdigest() == "539fb06325f6a1345e325b1448d31aad8bb08228", \
    "base is not live HEAD 53b6d68, refusing to patch"
s = data.decode()

ANCHOR = """  warn "  plugin-update: bin/hexciri-plugin-update not in fork output, Nyxiri plugins will update from main until it is patched"
fi

# Save the fully patched fork for the next re-run (fork cache,"""

assert s.count(ANCHOR) == 1, "plugin-update block anchor not found exactly once"
assert "Hexciri: enable multiple plugins" not in s, "patch already applied"

NEW_SCRIPT = r'''#!/bin/bash

# omarchy:summary=Enable a shell plugin
# omarchy:group=plugin
# omarchy:args=<id>... [placement]
# omarchy:examples=hexciri plugin enable acme.weather --section right | hexciri plugin enable acme.clock acme.weather

set -euo pipefail

fail() {
  echo "hexciri-plugin-enable: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: hexciri plugin enable <id>... [placement]"
  echo "  Enable one or more plugins. Placement (--section, --index,"
  echo "  --before, --after, or a positional section) applies to a"
  echo "  single plugin only. A bar plugin switches the active bar:"
  echo "  hexciri bar use <id>"
  exit 0
fi

[[ -n ${1:-} ]] || fail "plugin id is required"

is_bar() {
  hexciri-plugin-catalog | jq -e --arg id "$1" '
    any(.[]; .id == $id and (.kinds | index("bar")))
  ' >/dev/null
}

enable_one() {
  local id="$1" placement="$2" result=""
  if is_bar "$id"; then
    # Hexciri: a bar is enabled by switching to it. `hexciri bar use`
    # edits shell.json directly, so this works even when the shell is
    # not running (tty3), unlike enablePlugin over shell IPC.
    if hexciri bar use "$id" >/dev/null; then
      echo "Now using $id as the bar"
      return 0
    fi
    echo "hexciri-plugin-enable: could not switch to bar '$id'" >&2
    return 1
  fi
  result=$(hexciri-shell shell enablePlugin "$id" "$placement")
  if [[ $result == "unknown" ]]; then
    echo "hexciri-plugin-enable: plugin '$id' is not known; run: hexciri-shell shell rescanPlugins" >&2
    return 1
  elif [[ $result != "ok" ]]; then
    echo "hexciri-plugin-enable: $result" >&2
    return 1
  fi
  if [[ $placement != "{}" ]]; then
    echo "Enabled and moved $id"
  else
    echo "Enabled $id"
  fi
  return 0
}

# Hexciri: enable multiple plugins (2026-11-24). Upstream takes exactly
# one id and treats any second argument as placement, so
# `plugin enable a b c` died with "unknown placement option: c" (and a
# bar as first id died with the bar guard) and enabled nothing at all.
# A placement option (--section/--index/--before/--after, or a positional
# section name as the second argument) still means single-plugin mode,
# with upstream behaviour unchanged.
has_placement=0
for arg in "$@"; do
  case "$arg" in
    --section|--index|--before|--after) has_placement=1 ;;
  esac
done
if (( has_placement == 0 )) && (( $# >= 2 )) && [[ $2 != left && $2 != centerBegin && $2 != center && $2 != centerEnd && $2 != tray && $2 != right ]]; then
  failed=0
  for id in "$@"; do
    enable_one "$id" "{}" || failed=1
  done
  exit "$failed"
fi

# Single-plugin mode: upstream behaviour, verbatim.
id="$1"
shift

if (( $# > 0 )) && is_bar "$id"; then
  fail "'$id' is a bar; it replaces the bar in use rather than taking a place in one"
fi

section=""
index=""
before=""
after=""
if (( $# > 0 )) && [[ $1 != --* ]]; then
  section="$1"
  shift
fi
while (( $# > 0 )); do
  case "$1" in
    --section)
      [[ -z $section ]] || fail "specify a section positionally or with --section, not both"
      section="${2:-}"
      [[ -n $section ]] || fail "--section requires a section"
      shift 2
      ;;
    --index)
      index="${2:-}"
      [[ -n $index ]] || fail "--index requires an index"
      shift 2
      ;;
    --before)
      before="${2:-}"
      [[ -n $before ]] || fail "--before requires a widget id"
      shift 2
      ;;
    --after)
      after="${2:-}"
      [[ -n $after ]] || fail "--after requires a widget id"
      shift 2
      ;;
    *)
      fail "unknown placement option: $1"
      ;;
  esac
done

[[ -z $section || $section =~ ^(left|centerBegin|center|centerEnd|tray|right)$ ]] ||
  fail "section must be left, centerBegin, center, centerEnd, tray, or right"
[[ -z $index || $index =~ ^[0-9]+$ ]] ||
  fail "index must be a non-negative integer"
[[ -z $before || -z $after ]] || fail "use only one of --before or --after"

placement=$(jq -cn \
  --arg section "$section" \
  --arg index "$index" \
  --arg before "$before" \
  --arg after "$after" '
    {}
    + (if $section == "" then {} else {section: $section} end)
    + (if $index == "" then {} else {index: ($index | tonumber)} end)
    + (if $before == "" then {} else {before: $before} end)
    + (if $after == "" then {} else {after: $after} end)
  ')

enable_one "$id" "$placement"
'''

BLOCK = """  warn "  plugin-update: bin/hexciri-plugin-update not in fork output, Nyxiri plugins will update from main until it is patched"
fi

# --- hexciri-plugin-enable accepts multiple ids (2026-11-24, Nyxiri bar enable bug) ---
# Upstream `plugin enable` takes exactly one id; any second argument is
# placement. Devi ran `hexciri plugin enable pizza.dirty.nyxiri
# pizza.dirty.nyxiri-menu ...` and got "unknown placement option:
# pizza.dirty.clock" (bar first id: the bar guard) and nothing was
# enabled at all. This patch rewrites bin/hexciri-plugin-enable in the
# fork output: several ids with no placement are enabled one by one (a
# bar id switches via `hexciri bar use`, which edits shell.json directly
# and works from tty3; unknown ids error but do not stop the rest), while
# any placement option keeps single-plugin upstream behaviour verbatim.
# Idempotent: the Hexciri marker inside the new script; the anchor
# asserts the file still looks like the renamed upstream script.
PLUGIN_ENABLE_BIN="$FORK_OUT/bin/hexciri-plugin-enable"
if [ -f "$PLUGIN_ENABLE_BIN" ]; then
  python3 - "$PLUGIN_ENABLE_BIN" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
new_script = r'''__NEW_SCRIPT__'''
if "Hexciri: enable multiple plugins" in s:
    print("plugin-enable: multi-id already present, skipping")
else:
    assert s.count("# omarchy:args=<id> [placement]") == 1, "plugin-enable upstream anchor not found exactly once"
    assert "hexciri-plugin-catalog" in s, "plugin-enable does not look like the renamed upstream script"
    with open(path, "w") as f:
        f.write(new_script)
    print("plugin-enable: rewritten for multiple ids (bar ids via hexciri bar use)")
PY
  bash -n "$PLUGIN_ENABLE_BIN" || die "bash -n failed on patched $PLUGIN_ENABLE_BIN"
  info "  plugin-enable: accepts multiple ids (bar ids switch via hexciri bar use)"
else
  warn "  plugin-enable: bin/hexciri-plugin-enable not in fork output, multi-id enable not patched"
fi

# Save the fully patched fork for the next re-run (fork cache,"""

BLOCK = BLOCK.replace("__NEW_SCRIPT__", NEW_SCRIPT.rstrip("\n"))
s = s.replace(ANCHOR, BLOCK, 1)

with open(PATH, "w") as f:
    f.write(s)
print("patched, new lines:", s.count("\n"))
print("sha256:", hashlib.sha256(s.encode()).hexdigest())
