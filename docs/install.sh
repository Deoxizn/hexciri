#!/bin/bash
# hexciri bootstrap — thin wrapper, deliberately NOT a second installer.
# (docs/install.sh once held a full copy of the bring-up and drifted behind
# the real install.sh — which is exactly how fresh boxes lost Niri to an
# unguarded meta removal. There is one installer now: REPO/install.sh.)
#
#   curl -LO https://hexciri.dirty.pizza/install.sh
#   sh install.sh [--yes] [--reboot]
#
# Clones (or fast-forwards) ~/.local/opt/hexciri, then execs its install.sh
# with your args, so this path always runs the newest bring-up.
set -euo pipefail

UPDATE_YES=""
AUTO_REBOOT=""
for _a in "$@"; do
  case "$_a" in
    --yes|-y) UPDATE_YES="--yes" ;;
    --reboot) AUTO_REBOOT="--reboot" ;;
    -h|--help) echo "usage: install.sh [--yes] [--reboot]"; exit 0 ;;
    *) echo "install.sh: unknown arg: $_a (usage: install.sh [--yes] [--reboot])" >&2; exit 1 ;;
  esac
done
unset _a

REPO_URL="https://github.com/Deoxizn/hexciri.git"
REPO="${HEXCIRI_REPO:-$HOME/.local/opt/hexciri}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bin" && -x "$SCRIPT_DIR/bin/hexciri-sync" ]]; then
  REPO="$SCRIPT_DIR"
else
  if [[ -x "$REPO/bin/hexciri-sync" ]]; then
    echo "hexciri: updating $REPO"
    git -C "$REPO" pull --ff-only 2>/dev/null || echo "hexciri: pull skipped — running local checkout"
  else
    echo "hexciri: cloning into $REPO"
    mkdir -p "$(dirname "$REPO")"
    git clone "$REPO_URL" "$REPO"
  fi
fi

if [[ ! -x "$REPO/install.sh" ]]; then
  echo "hexciri: checkout broken ($REPO/install.sh missing)" >&2
  exit 1
fi
# shellcheck disable=SC2086
exec bash "$REPO/install.sh" $UPDATE_YES $AUTO_REBOOT
