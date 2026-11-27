#!/usr/bin/env bash
# Hexciri fork patch 69: cache mise hook-env for 5s (upstream omacom/omarchy #20395).
#
# Upstream #20395 (verified against the live .diff, 2026-11-27): one line in
# etc/mise/conf.d/omarchy.toml, `hook_env.cache_ttl = "5s"` under [settings].
# Skips re-evaluating hook-env on rapid idle prompts (prompt hook latency
# ~8-12 ms down to ~3-4 ms); directory changes and MISE_ENV changes still
# refresh immediately, and out-of-process updates (like omarchy-update-mise)
# are picked up once the TTL expires.
#
# Fork notes:
# - Upstream's etc/mise/conf.d/omarchy.toml is NOT in FORK_OUT: the
#   installer's fork step never copies etc/mise/ (it copies only
#   etc/sudoers.d/omarchy-theme-browser and
#   etc/tmpfiles.d/omarchy-nopasswd-sudo.conf from etc/). So there is no
#   fork file to patch. Hexciri's equivalent of that file is the repo file
#   v2/hexciri-tools.toml, installed by install.sh to
#   /etc/mise/conf.d/hexciri-tools.toml: it is the trimmed copy of the same
#   upstream settings file (same [settings] block, same
#   `upgrade.auto_prune = false` line the PR sits next to), and this patch
#   adds the cache line there, next to that line. The "omarchy-update-mise"
#   name in the upstream comment is adapted to "hexciri-update-mise".
# - The rest of upstream omarchy.toml is NOT ported: its [tool_alias]
#   cursor-agent entry and [hooks] postinstall herdr entry are agent/Herdr
#   wiring, out of scope for Hexciri (agents and Herdr are removed).
# - Repo file, not a fork file (patch 51 precedent: bin/hexciri-search-
#   provider): the edit targets $HEXCIRI_REPO_ROOT/v2/hexciri-tools.toml.
#   FORK_OUT is still required by the patch runner's calling convention.
# - No install.sh placement step needed: install.sh already installs this
#   file (line ~2327, `sudo install -Dm644 ... /etc/mise/conf.d/
#   hexciri-tools.toml`), and that mise step carries no REAPPLY guard (the
#   guards are at the system-provisioning block and later sections), so a
#   patch-only update (--re-apply: fork + placement) re-runs it and the new
#   setting lands on the next `hexciri update`.
#
# Standalone: bash v2/patches/69-mise-hookenv-cache.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "69-mise-hookenv-cache.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  if [ "${IS_RERUN:-0}" = "1" ]; then
    case "$1" in
      Kept*|*already\ present*|*already\ correct*|*already\ current*|Theme\ already\ applied:*|*already\ enabled*)
        printf '[hexciri] %s\n' "$1" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
        return 0
        ;;
    esac
  fi
  printf '[hexciri] %s\n' "$1"
}
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "69-mise-hookenv-cache.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. hook_env.cache_ttl in the installed mise settings (repo file) ---
step "Caching mise hook-env for 5s"
_TOML="$HEXCIRI_REPO_ROOT/v2/hexciri-tools.toml"
[ -f "$_TOML" ] || die "v2/hexciri-tools.toml not found in the installer tree"
_PY_OUT="$(mktemp)"
python3 - "$_TOML" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 69 mise hook-env edit failed"; }
import sys
import tomllib

path = sys.argv[1]


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


with open(path, encoding="utf-8") as f:
    s = f.read()

if "hook_env.cache_ttl" in s:
    try:
        cfg = tomllib.loads(s)
        ttl = cfg["settings"]["hook_env"]["cache_ttl"]
    except Exception as e:
        _die("hook_env.cache_ttl present but the file does not parse: %s" % e)
    if ttl != "5s":
        _die("hook_env.cache_ttl is %r, want \"5s\"" % (ttl,))
    print("mise: hook_env.cache_ttl already present, skipping")
else:
    anchor = "upgrade.auto_prune = false"
    if s.count(anchor) != 1:
        _die("anchor %r occurs %d times, want exactly 1" % (anchor, s.count(anchor)))
    if "[settings]" not in s:
        _die("[settings] section missing, the cache line has nowhere to go")
    block = (
        anchor + "\n"
        "#\n"
        "# Skip re-evaluating hook-env on rapid idle prompts; directory changes and\n"
        "# MISE_ENV changes still refresh immediately, and out-of-process updates\n"
        "# (like hexciri-update-mise) are picked up once the TTL expires.\n"
        'hook_env.cache_ttl = "5s"'
    )
    s = s.replace(anchor, block, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    print("patched: hook_env.cache_ttl = \"5s\" in v2/hexciri-tools.toml")

with open(path, encoding="utf-8") as f:
    raw = f.read()
try:
    cfg = tomllib.loads(raw)
except Exception as e:
    _die("v2/hexciri-tools.toml does not parse as TOML after edit: %s" % e)
if cfg.get("settings", {}).get("hook_env", {}).get("cache_ttl") != "5s":
    _die("settings.hook_env.cache_ttl is not \"5s\" after edit")
if cfg.get("settings", {}).get("upgrade", {}).get("auto_prune") is not False:
    _die("settings.upgrade.auto_prune lost in edit")
# No agent/Herdr wiring: the file's own header comments already name Herdr
# (to say it is NOT declared), so check the parsed tables, not the words.
if "hooks" in cfg or "tool_alias" in cfg:
    _die("agent/Herdr wiring leaked into hexciri-tools.toml")
print("mise hook-env cache validates (cache_ttl 5s, auto_prune false intact)")
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'mise hook-env cache patch: %d edit(s) applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 69: mise hook-env cached for 5s (prompt hook ~8-12ms down to ~3-4ms)"
