#!/bin/bash
# hexciri dotfiles bring-up — CachyOS + a WM, then this.
#
#   curl -LO https://hexciri.dirty.pizza/install.sh
#   sh install.sh
#
# or: git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
#     ~/.local/opt/hexciri/install.sh
#
# Clones (if curled), symlinks bin/* into ~/.local/bin, then delegates to
# bin/hexciri-sync to re-apply the layer. Idempotent; safe to re-run.
# Never touches the installer, kernel, GPU stack, or package manager.
set -euo pipefail

REPO_URL="https://github.com/Deoxizn/hexciri.git"
DEFAULT_REPO="$HOME/.local/opt/hexciri"

info() { echo "hexciri: $*"; }

# Resolve repo: script's dir if it holds bin/, else clone/default.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bin" && -x "$SCRIPT_DIR/bin/hexciri-sync" ]]; then
  REPO="$SCRIPT_DIR"
else
  REPO="${HEXCIRI_REPO:-$DEFAULT_REPO}"
  if [[ ! -x "$REPO/bin/hexciri-sync" ]]; then
    info "cloning into $REPO"
    mkdir -p "$(dirname "$REPO")"
    git clone "$REPO_URL" "$REPO"
  fi
fi

# Link sweep (same step hexciri-sync owns) so sync itself is on PATH first.
mkdir -p "$HOME/.local/bin"
for f in "$REPO"/bin/*; do
  [[ -f $f && -x $f ]] || continue
  ln -sfn "$f" "$HOME/.local/bin/$(basename "$f")"
done
info "linked controllers into ~/.local/bin"

# Delegate the re-apply; best-effort (sync may need interactive/root steps).
if [[ -x "$REPO/bin/hexciri-sync" ]]; then
  info "re-applying layer via hexciri-sync"
  HEXCIRI_REPO="$REPO" "$REPO/bin/hexciri-sync" || info "sync returned non-zero; re-run after reboot"
fi
# Per-user Strata file manager (GitHub release; sets itself default for
# inode/directory + file chooser). Best-effort: offline boxes still finish.
if [[ -x "$REPO/bin/hexciri-setup" ]]; then
  info "installing Strata file manager (default)"
  "$REPO/bin/hexciri-setup" strata 2>&1 | sed 's/^/  /' || info "Strata skipped (offline?) — run 'hexciri-setup strata' later"
fi
info "done — menu + theme hook live. Update: git -C $REPO pull && sh $REPO/install.sh"
