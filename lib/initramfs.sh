#!/bin/bash
# hexciri shared: deterministic, self-healing mkinitcpio.conf HOOKS management.
#
# Replaces the old chain-sed approach. Seds were fragile, and once a run mangled
# /etc/mkinitcpio.conf, every later install re-inherited the broken file (pacman
# never overwrites a modified config on reinstall) — surfacing as
# "mkinitcpio.conf: line 55: syntax error / failed to read configuration" and
# "failed to generate ramfs" even on otherwise clean full installs.
#
# This module always produces exactly ONE canonical HOOKS=( ... ) line and
# repairs any malformed line in place. Idempotent, safe to run repeatedly.
#
# CLI:
#   initramfs.sh repair [conf]
#   initramfs.sh line [conf]
#
# When it modifies the config it creates "<conf>.hexciri-changed"; the caller
# uses that sentinel to decide on `mkinitcpio -P` (and removes it after).
set -euo pipefail

CONF=/etc/mkinitcpio.conf
ACTION=repair

for a in "$@"; do
  case $a in
    repair|line) ACTION=$a ;;
    /*) CONF=$a ;;
  esac
done

DEFAULT_HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
UDEV_HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)

log() { echo "initramfs: $*"; }

active_words() { # conf -> one word per line (empty if none parseable)
  local line
  line=$(grep -m1 '^[[:space:]]*HOOKS=(' "$CONF" 2>/dev/null || true)
  if [[ -n $line && $line =~ ^[[:space:]]*HOOKS=\((.*)\)[[:space:]]*$ ]]; then
    local w
    for w in ${BASH_REMATCH[1]}; do echo "$w"; done
  fi
}

panel_is_udev() { grep -qm1 -E 'keymap|consolefont' "$CONF" 2>/dev/null; }

canonical_line() { # words... -> single "HOOKS=(w1 w2 ...)" string
  local seen=() out=() baselisted=false w have
  for w in "$@"; do
    [[ -n ${w//[[:space:]]/} ]] || continue
    have=false
    for x in "${seen[@]}"; do [[ $x == "$w" ]] && have=true && break; done
    $have && continue
    seen+=("$w")
    [[ $w == base ]] && { baselisted=true; continue; }
    out+=("$w")
  done
  local words=()
  while IFS= read -r w; do words+=("$w"); done < <({ $baselisted && echo base; printf '%s\n' "${out[@]}"; })
  (( ${#words[@]} )) || words=("${DEFAULT_HOOKS[@]}")
  printf 'HOOKS=(%s)\n' "${words[*]}"
}

replace_line() { # conf newline
  local tmp="$CONF.hxc.$$" seen=false
  {
    while IFS= read -r l || [[ -n $l ]]; do
      if [[ $seen == false && $l =~ ^[[:space:]]*HOOKS= ]]; then
        echo "$1"
        seen=true
      else
        echo "$l"
      fi
    done < "$CONF"
    [[ $seen == true ]] || echo "$1"
  } > "$tmp"
  chmod --reference="$CONF" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$CONF"
}

repair() { # only ever rewrites a malformed/non-canonical HOOKS line in place
  local words=() want existing
  while IFS= read -r w; do words+=("$w"); done < <(active_words)
  if (( ${#words[@]} == 0 )); then
    if panel_is_udev; then
      mapfile -t words < <(printf '%s\n' "${UDEV_HOOKS[@]}")
    else
      mapfile -t words < <(printf '%s\n' "${DEFAULT_HOOKS[@]}")
    fi
    log "no parseable HOOKS line (${CONF}) — seeding canonical default"
  fi
  want=$(canonical_line "${words[@]}")
  existing=$(canonical_line $(active_words))
  [[ $want == "$existing" ]] && return 0
  cp -f "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  replace_line "$want"
  : > "$CONF.hexciri-changed"
  log "repaired ${CONF}: $want"
}

case $ACTION in
  repair) repair ;;
  line) canonical_line $(active_words) ;;
esac