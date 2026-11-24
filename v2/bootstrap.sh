#!/usr/bin/env bash
# Hexiri 2.0 bootstrap, thin wrapper, deliberately NOT a second installer.
# There is one installer: v2/install.sh on branch nyx.
#
# Download this file first, then run it. Do NOT pipe curl into bash, so
# stdin stays on the terminal for the installer's prompts and sudo.
#
#   curl -LO https://raw.githubusercontent.com/Deoxizn/hexciri/nyx/v2/bootstrap.sh
#   bash bootstrap.sh
#
# It downloads the nyx branch as a public codeload tarball, no git, no
# username or password prompt, extracts it to a temp dir, verifies it
# contains v2/install.sh, then execs that installer. The whole chain is
# git-auth free: this bootstrap uses curl only, and v2/install.sh fetches
# its Omarchy source as a codeload tarball too.
#
# Extract location is a temp dir, NOT ~/.local/opt/hexciri. That path holds
# the Hexciri v1 checkout, do not clobber it with the v2.0 test branch.

set -euo pipefail

# No git credential prompts anywhere in this chain. This script never
# invokes git at all. GIT_TERMINAL_PROMPT=0 is set as a belt-and-braces
# guard in case a child process ever does.
export GIT_TERMINAL_PROMPT=0

HEXCIRI_TARBALL_URL="https://codeload.github.com/Deoxizn/hexciri/tar.gz/refs/heads/nyx"
EXPECTED_TOP_DIR="hexciri-nyx"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
info() { printf '[hexciri-bootstrap] %s\n' "$1"; }

if [ "$EUID" -eq 0 ]; then
  die "Do not run as root. Run as your normal user with sudo available."
fi

for cmd in curl tar mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done

WORKDIR="$(mktemp -d /tmp/hexciri-bootstrap.XXXXXX)"
TARBALL="$WORKDIR/hexciri-nyx.tar.gz"
info "Work dir: $WORKDIR"

info "Downloading Hexiri 2.0, branch nyx, as a public tarball (no git, no auth)"
curl -fsSL --max-time 300 -o "$TARBALL" "$HEXCIRI_TARBALL_URL" || die "curl download of Hexiri nyx tarball failed. Fix networking, then rerun."
[ -s "$TARBALL" ] || die "Downloaded Hexiri tarball is empty: $TARBALL"
# Validate it is really a gzip tarball, not an HTML error page.
tar -tzf "$TARBALL" >/dev/null || die "Downloaded file is not a valid gzip tarball: $TARBALL. Check the URL and networking, then rerun."

TOP_DIR="$(tar -tzf "$TARBALL" | head -1 | cut -d/ -f1)"
if [ "$TOP_DIR" != "$EXPECTED_TOP_DIR" ]; then
  die "tarball top dir is '$TOP_DIR', expected '$EXPECTED_TOP_DIR'. Refusing to continue."
fi

tar -xzf "$TARBALL" -C "$WORKDIR" || die "Failed to extract Hexiri tarball."
EXTRACTED="$WORKDIR/$TOP_DIR"
[ -d "$EXTRACTED" ] || die "Extracted Hexiri tree not found: $EXTRACTED"
[ -f "$EXTRACTED/v2/install.sh" ] || die "Extracted Hexiri tree is missing v2/install.sh: $EXTRACTED"
info "Verified: $EXTRACTED/v2/install.sh present"

# Exec replaces this process, so the temp dir is left in /tmp for
# debugging if the installer fails. That is intentional.
info "Running the real installer: bash $EXTRACTED/v2/install.sh"
exec bash "$EXTRACTED/v2/install.sh" "$@"
