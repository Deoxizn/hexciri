#!/usr/bin/env python3
"""Patch hexciri-update-system-pkgs for the checkupdates/pacman DB race
(2026-11-24, Devi 13:57 MST).

Symptom: after `hexciri update`, the arch-updates badge still showed 1:
check_updates.py (checkupdates, its own temp DB) listed
  zxing-cpp 3.1.1-1 -> 3.2.0-1
while the update log said
  :: Starting full system upgrade...
   there is nothing to do
  System packages are up to date
and a re-run of the scanner still counted zxing-cpp, total 1,
hexciriPending false.

Root cause, two parts:
1. Two different sync databases. checkupdates syncs its own temp DB
   (/tmp/checkup-db-$UID, fakeroot pacman -Sy) and pacman -Su uses the
   main DB (/var/lib/pacman/sync), synced seconds earlier by
   hexciri-update-pacman -Sy. The two syncs can hit different
   geo-mirror backends, and a package built ~90 min earlier
   (zxing-cpp 3.2.0-1, built 2026-11-24 19:24 UTC, on archlinux.org
   19:28 UTC, Devi's update 20:57 UTC) can be on one mirror and not
   the other. So checkupdates counts it, -Su (main DB) finds nothing.
   The scanner was right; the updater was reading the stale DB.
2. The updater then lied about it. When -Su said "there is nothing
   to do" while _pending > 0, the code printed "System packages are
   up to date" anyway, hiding a real pending package behind a stale
   badge. The old comment even anticipated this ("pacman can still
   find nothing to do (db race ...)") and then claimed up to date.

Fix, in the system-pkgs heredoc in v2/install.sh:
- Keep the checkupdates pending list (_pending_list) for reporting.
- After a -Su that upgraded 0 while _pending > 0: one forced
  re-sync (pacman -Syy, which re-downloads the DBs instead of
  trusting the "already up to date" shortcut and can land on a
  fresher geo-mirror backend), re-count with pacman -Qu against the
  main DB (the DB -Su actually uses), and if that counts > 0 run
  -Su again. -Syy here is safe: -Su runs immediately after, in
  this same script, so there is no -Sy-without--Su window.
- If it still upgrades 0: print an honest warning naming the
  pending packages and "mirror DB lag?", and tell Devi to re-run
  later. Never print "System packages are up to date" when
  _pending > 0.
- Placement verification greps for the new warning and the -Syy
  retry.

No change to the scanner (check_updates.py): it was correct.
No change to Arch-Updates.
"""
import sys

P = "/home/hatch/workspace/hexiri-2.0/v2/install.sh"
s = open(P).read()
orig = s

# 1. Keep the pending list for the warning.
old = '''_pending="$(wc -l < "$_pending_file" | tr -d ' ')"
if [[ "$_checkupdates_status" == "1" ]]; then
  _pending="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
fi
rm -f "$_pending_file"'''
new = '''_pending="$(wc -l < "$_pending_file" | tr -d ' ')"
if [[ "$_checkupdates_status" == "1" ]]; then
  _pending="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
fi
_pending_list="$(cat "$_pending_file" 2>/dev/null || true)"
rm -f "$_pending_file"'''
assert s.count(old) == 1, "pending-list anchor not found exactly once"
s = s.replace(old, new, 1)

# 2. Forced re-sync retry after a -Su that upgraded 0 while _pending > 0.
old = '''  if [[ "$_upgraded" == "0" ]] && ! grep -q 'there is nothing to do' "$_su_log" 2>/dev/null; then
    _upgraded="$_pending"
  fi
  rm -f "$_su_log"'''
new = '''  if [[ "$_upgraded" == "0" ]] && ! grep -q 'there is nothing to do' "$_su_log" 2>/dev/null; then
    _upgraded="$_pending"
  fi
  # DB race / mirror lag retry (2026-11-24, Devi: zxing-cpp 3.2.0-1
  # listed by checkupdates, pacman -Su said "there is nothing to do").
  # checkupdates syncs its own temp DB, pacman -Su uses the main DB
  # synced seconds earlier: the two syncs can hit different geo-mirror
  # backends, and a package built ~90 min earlier can be on one and
  # not the other. One forced re-sync (-Syy, which re-downloads the
  # DBs instead of trusting the "already up to date" shortcut and can
  # land on a fresher mirror) + a re-count against the main DB (the DB
  # -Su actually uses), then a second -Su, before giving up. -Syy
  # here is safe: -Su runs immediately after, in this same script,
  # so there is no -Sy-without--Su window.
  if [[ "$_upgraded" == "0" ]] && [[ "$_pending" != "0" ]]; then
    _retry_log="$(mktemp /tmp/hexciri-syspkgs-retry.XXXXXX)"
    if LC_ALL=C hexciri-update-pacman -Syy --noconfirm >"$_retry_log" 2>&1; then
      _requ="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$_requ" != "0" ]]; then
        _su_log2="$(mktemp /tmp/hexciri-syspkgs-su2.XXXXXX)"
        LC_ALL=C hexciri-update-pacman -Su --noconfirm \\
          --overwrite '/usr/share/hexciri/*' 2>"$errors" | tee "$_su_log2"
        _su2_status="${PIPESTATUS[0]}"
        if [[ "$_su2_status" == "0" ]]; then
          _upgraded="$(grep -cE '(\\\\([0-9]+/[0-9]+\\\\) )?upgrading ' "$_su_log2" 2>/dev/null || true)"
          _upgraded="$(echo "$_upgraded" | tr -d ' ')"
          if [[ "$_upgraded" == "0" ]] && ! grep -q 'there is nothing to do' "$_su_log2" 2>/dev/null; then
            _upgraded="$_requ"
          fi
        fi
        rm -f "$_su_log2"
      fi
    fi
    rm -f "$_retry_log"
  fi
  rm -f "$_su_log"'''
assert s.count(old) == 1, "retry anchor not found exactly once"
s = s.replace(old, new, 1)

# 3. Never claim up to date when _pending > 0 and nothing upgraded.
old = '''  if [[ "$_upgraded" == "0" ]]; then
    echo "System packages are up to date"
  else
    echo "System packages updated ($_upgraded package(s))"
  fi
  exit 0
fi
rm -f "$_su_log"
cat "$errors" >&2'''
new = '''  if [[ "$_upgraded" == "0" ]]; then
    # Never claim up to date when checkupdates counted something and
    # pacman upgraded nothing: that is the zxing-cpp case above, and
    # "up to date" hides a real pending package behind a stale badge.
    if [[ "$_pending" != "0" ]]; then
      echo "Note: checkupdates listed $_pending update(s) but pacman found nothing to upgrade (mirror DB lag?)"
      if [[ -n "$_pending_list" ]]; then
        printf '%s\\n' "$_pending_list"
      fi
      echo "Re-run hexciri update later; the badge clears once the mirror catches up."
    else
      echo "System packages are up to date"
    fi
  else
    echo "System packages updated ($_upgraded package(s))"
  fi
  exit 0
fi
rm -f "$_su_log"
cat "$errors" >&2'''
assert s.count(old) == 1, "final-branch anchor not found exactly once"
s = s.replace(old, new, 1)

# 4. Placement verification greps.
old = '''grep -q '_upgraded' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs does not count real upgrades (it claimed updated (1) after nothing to do)"'''
new = '''grep -q '_upgraded' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs does not count real upgrades (it claimed updated (1) after nothing to do)"
grep -q 'mirror DB lag' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs still claims up to date when checkupdates counted updates pacman skipped (zxing-cpp 3.2.0-1, 2026-11-24)"
grep -q 'hexciri-update-pacman -Syy' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs has no forced re-sync retry for the checkupdates/pacman DB race (zxing-cpp, 2026-11-24)"'''
assert s.count(old) == 1, "verification anchor not found exactly once"
s = s.replace(old, new, 1)

assert s != orig
open(P, "w").write(s)
print("OK patched v2/install.sh")
