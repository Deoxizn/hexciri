#!/usr/bin/env bash
# Hexciri fork patch 19: preserve user backups across config refreshes.
# Forward-port of omarchy PR #20342 (grainfire, open,
# "Preserve user backups across config refreshes") into bin/.
#
# What it does (PR behavior, unchanged): refreshing a config twice within
# the same second reused the same `*.bak.<epoch>` name, so the second run
# overwrote the first backup and then deleted it as "identical," destroying
# the only copy of the user's edits. The fix skips the copy entirely when
# the live file already matches the default, gives each backup a unique
# name via mktemp (also mode 0600, mktemp's default), and aborts with an
# error, leaving the live file and any completed backup intact, if the
# backup copy or the replacement copy fails.
#
# Fork adaptation: the file lands as bin/hexciri-refresh-config (it is in
# the installer's renamed-bin list, v2/install.sh:2958), with omarchy ->
# hexciri in the summary/usage strings, $OMARCHY_PATH -> $HEXCIRI_PATH,
# and "new Omarchy default" -> "new Hexciri default" in the replace
# message (all three follow the installer's rewrite_contents map).
# Upstream's test/shell.d/refresh-config-test.sh hunk is NOT carried: the
# fork does not ship upstream tests, so this patch carries the bin change
# alone. Unrelated to the fork's own 2026-11-24 installer re-run
# preservation work (different mechanism, user-invoked command).
#
# Indent note: the .diff render was inconsistent on one line (the `fi`
# closing the backup-failure block showed as 4-space in one fetch and
# 2-space in another). Ported at 2 spaces, matching the sibling `fi`
# above it and the file's 2-space style; whitespace only, no behavior
# change. bash -n passes on the result either way.
#
# Standalone: bash v2/patches/19-refresh-config-backups.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is shell script, so bash -n DOES
# apply here, on the patched file and on this patch itself (unlike the
# JS/QML patches, where it is deliberately not used).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "19-refresh-config-backups.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}

# --- Preserve user backups across config refreshes, omarchy PR #20342 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label, present-marker). old must occur exactly once;
# present-marker already in the file means this edit is done (idempotent
# re-run). present defaults to new when the new text itself is a unique
# marker; hunk 1 needs its own marker because its new text (the
# default_config_file line alone) is also a substring of the unpatched
# file, so its marker is the post-removal shape instead: default line,
# one blank line, then the shipped-config guard.
REPLACEMENTS = [
    # Hunk 1: drop the shared `*.bak.<epoch>` name. Two refreshes in the
    # same second reused it, so the second overwrote the first backup.
    ("bin/hexciri-refresh-config",
     'default_config_file="$HEXCIRI_PATH/config/$config_file"\n'
     'backup_config_file="$user_config_file.bak.$(date +%s)"\n',
     'default_config_file="$HEXCIRI_PATH/config/$config_file"\n',
     "Drop the shared epoch backup name (PR #20342 hunk 1)",
     'default_config_file="$HEXCIRI_PATH/config/$config_file"\n'
     '\n'
     'if [[ ! -e $default_config_file ]]; then'),
    # Hunk 2: the refresh block itself. No copy at all when the live file
    # already matches the default (old code copied, then deleted the
    # backup as "identical"); unique backup name via mktemp; abort with
    # an error, live file and completed backup intact, if either copy
    # fails. "Hexciri default" is the fork rename of the PR's "Omarchy
    # default" (installer's Omarchy -> Hexciri rule).
    ("bin/hexciri-refresh-config",
     'if [[ -f $user_config_file ]]; then\n'
     '  cp -f "$user_config_file" "$backup_config_file"\n'
     '  cp -f "$default_config_file" "$user_config_file"\n'
     '\n'
     '  if cmp -s "$user_config_file" "$backup_config_file"; then\n'
     '    rm "$backup_config_file"\n'
     '  else\n'
     '    echo -e "\\e[31mReplaced $user_config_file with new Hexciri default.\\nSaved backup as ${backup_config_file}.\\n\\n\\e[32mChanges:\\e[0m"\n'
     '    diff "$user_config_file" "$backup_config_file" || true\n'
     '  fi\n'
     'else\n',
     'if [[ -f $user_config_file ]]; then\n'
     '  if cmp -s "$default_config_file" "$user_config_file"; then\n'
     '    exit 0\n'
     '  fi\n'
     '\n'
     '  backup_config_file=$(mktemp "$user_config_file.bak.$(date +%s).XXXXXX") || exit 1\n'
     '  if ! cp "$user_config_file" "$backup_config_file"; then\n'
     '    rm -f "$backup_config_file"\n'
     '    exit 1\n'
     '  fi\n'
     '  cp -f "$default_config_file" "$user_config_file" || exit 1\n'
     '\n'
     '  echo -e "\\e[31mReplaced $user_config_file with new Hexciri default.\\nSaved backup as ${backup_config_file}.\\n\\n\\e[32mChanges:\\e[0m"\n'
     '  diff "$user_config_file" "$backup_config_file" || true\n'
     'else\n',
     "Refresh block: skip-if-identical, mktemp backup, abort on copy failure (PR #20342 hunk 2)",
     None),
]

for rel, old, new, label, present in REPLACEMENTS:
    if present is None:
        present = new
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if present in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

for label in changed:
    print("patched: %s" % label)
print("refresh-config-backups patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited file. It is shell script, so bash -n applies.
# Guarded: a tree without the file warns and skips above (partial sim
# trees), and must exit 0 rather than die here on the missing file.
if [[ -f "$FORK_OUT/bin/hexciri-refresh-config" ]]; then
  bash -n "$FORK_OUT/bin/hexciri-refresh-config" || die "bash -n failed on patched hexciri-refresh-config"
fi
info "  refresh-config-backups: refreshes no longer clobber same-second backups (PR #20342)"
