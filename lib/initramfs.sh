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
#   initramfs.sh ensure [--plymouth] [--encrypt] [conf]
#   initramfs.sh repair [conf]
#   initramfs.sh line [conf]
#
# When it modifies the config it creates "<conf>.hexciri-changed"; the caller
# uses that sentinel to decide on `mkinitcpio -P` (and removes it after).
set -euo pipefail

CONF=/etc/mkinitcpio.conf
ACTION=ensure
WANT_PLYMOUTH=false
WANT_ENCRYPT=false

args=("$@")
while [[ $# -gt 0 ]]; do
  case $1 in
    ensure|repair|line) ACTION=$1 ;;
    --plymouth) WANT_PLYMOUTH=true ;;
    --encrypt)  WANT_ENCRYPT=true ;;
    /*) CONF=$1 ;;
  esac
  shift
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

normalize() { # words... -> canonical ORIGINAL ORDER pagination-safe list
  local seen=() out=() baselisted=false moved=()
  for w in "$@"; do
    [[ -n ${w//[[:space:]]/} ]] || continue
    local have=false
    for x in "${seen[@]}"; do [[ $x == "$w" ]] && have=true && break; done
    $have && continue
    seen+=("$w")
    [[ $w == base ]] && { baselisted=true; continue; }
    out+=("$w")
  done
  { $baselisted && echo base; printf '%s\n' "${out[@]}"; }
}

insert_after() { # value anchor -> list where value sits right after anchor's first use
  local value=$1 anchor=$2
  shift 2
  local out=() placed=false w have=false
  for w in "$@"; do [[ $w == "$value" ]] && have=true; done
  $have && { printf '%s\n' "$@"; return 0; }
  for w in "$@"; do
    if [[ $w == "$anchor" && $placed == false ]]; then
      out+=("$w" "$value")
      placed=true
    else
      out+=("$w")
    fi
  done
  $placed || out+=("$value")
  printf '%s\n' "${out[@]}"
}

insert_before() { # value anchor -> list where value sits right before anchor
  local value=$1 anchor=$2
  shift 2
  local out=() added=false have=false w
  for w in "$@"; do [[ $w == "$value" ]] && have=true; done
  $have && { printf '%s\n' "$@"; return 0; }
  for w in "$@"; do
    if [[ $added == false && $w == "$anchor" ]]; then
      out+=("$value")
      added=true
    fi
    out+=("$w")
  done
  $added || out+=("$value")
  printf '%s\n' "${out[@]}"
}

canonical_line() { # words... -> single "HOOKS=(w1 w2 ...)" string
  local words=()
  while IFS= read -r w; do words+=("$w"); done < <(normalize "$@")
  (( ${#words[@]} )) || words=("${DEFAULT_HOOKS[@]}")
  printf 'HOOKS=(%s)\n' "${words[*]}"
}

replace_line() { # conf newline
  local tmp="$CONF.hxc.$$"
  {
    local seen=false
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

ensure_apply() { # ensure the config holds one canonical line with wanted words
  local words=()
  while IFS= read -r w; do words+=("$w"); done < <(active_words)
  if (( ${#words[@]} == 0 )); then
    if panel_is_udev; then
      mapfile -t words < <(printf '%s\n' "${UDEV_HOOKS[@]}")
    else
      mapfile -t words < <(printf '%s\n' "${DEFAULT_HOOKS[@]}")
    fi
    log "no parseable HOOKS line (${CONF}) — seeding canonical default"
  fi
  $WANT_PLYMOUTH && {
    local anchor=systemd have_systemd=false w
    for w in "${words[@]}"; do [[ $w == systemd ]] && have_systemd=true; done
    $have_systemd || anchor=udev
    mapfile -t words < <(insert_after plymouth "$anchor" "${words[@]}")
  }
  $WANT_ENCRYPT && {
    mapfile -t words < <(insert_before encrypt filesystems "${words[@]}")
  }

  local want existing
  want=$(canonical_line "${words[@]}")
  existing=$(canonical_line $(active_words))

  if [[ $want == "$existing" ]]; then
    return 0
  fi
  cp -f "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  replace_line "$want"
  : > "$CONF.hexciri-changed"
  log "wrote ${CONF}: $want"
}

case $ACTION in
  ensure) ensure_apply ;;
  repair) WANT_PLYMOUTH=false WANT_ENCRYPT=false; ensure_apply ;;
  line) canonical_line $(active_words) ;;
esac