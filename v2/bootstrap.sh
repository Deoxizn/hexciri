#!/usr/bin/env bash
# Hexiri 2.0 bootstrap, thin wrapper, deliberately NOT a second installer.
# There is one installer: v2/install.sh on branch nyx.
#
# Download this file first, then run it. Do NOT pipe curl into bash, so
# stdin stays on the terminal for the installer's prompts and sudo.
#
#   curl -LO https://hexciri.dirty.pizza/v2/bootstrap.sh
#   bash bootstrap.sh
#
# Fallback, if the short URL is not live yet (it goes live only when
# docs/v2/bootstrap.sh lands on main, see v2/README.md):
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
# Never exit silently again: if any command fails, print where it failed.
# (2026-11-23: the script used to die silently after "Validation passed"
# with exit 141 and no error, see the top-dir fix below.)
trap 'printf "ERROR: [hexciri-bootstrap] failed at line %s, exit %s, command: %s\n" "$LINENO" "$?" "$BASH_COMMAND" >&2' ERR

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

for cmd in curl tar mktemp wc; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done

WORKDIR="$(mktemp -d /tmp/hexciri-bootstrap.XXXXXX)"
TARBALL="$WORKDIR/hexciri-nyx.tar.gz"
info "Work dir: $WORKDIR"

info "Downloading Hexiri 2.0, branch nyx, as a public tarball (no git, no auth)"
info "URL: $HEXCIRI_TARBALL_URL"
info "Expected size: about 43 MB, this can take a minute on a slow connection"
curl --progress-bar -fSL --max-time 300 -o "$TARBALL" "$HEXCIRI_TARBALL_URL" || die "curl download of Hexiri nyx tarball failed. Fix networking, then rerun."
[ -s "$TARBALL" ] || die "Downloaded Hexiri tarball is empty: $TARBALL"
SIZE_BYTES="$(wc -c < "$TARBALL" | tr -d ' ')"
info "Downloaded: $SIZE_BYTES bytes (~$((SIZE_BYTES / 1024 / 1024)) MB): $TARBALL"
info "Validating tarball (gzip, top dir $EXPECTED_TOP_DIR)..."
# Validate it is really a gzip tarball, not an HTML error page.
# Write the listing to a file first: the old code did
#   TOP_DIR="$(tar -tzf "$TARBALL" | head -1 | cut -d/ -f1)"
# With set -euo pipefail, head exits after the first line, tar then gets
# SIGPIPE (exit 141) on any tarball whose listing is bigger than the pipe
# buffer, and the script exits silently right after "Validation passed",
# back to the prompt, no error. That was the 2026-11-23 stall.
# A file listing has no pipe to close early, so this cannot happen again.
tar -tzf "$TARBALL" > "$WORKDIR/tar-list.txt" || die "Downloaded file is not a valid gzip tarball: $TARBALL. Check the URL and networking, then rerun."
info "Validation passed: valid gzip tarball"
info "Reading tarball top dir from the saved listing..."
TOP_DIR="$(head -1 "$WORKDIR/tar-list.txt" | cut -d/ -f1)"
[ -n "$TOP_DIR" ] || die "Could not read a top dir from the tarball listing: $WORKDIR/tar-list.txt"
if [ "$TOP_DIR" != "$EXPECTED_TOP_DIR" ]; then
  die "tarball top dir is '$TOP_DIR', expected '$EXPECTED_TOP_DIR'. Refusing to continue."
fi
info "Top dir: $TOP_DIR"

info "Extracting tarball (this can take a minute, no output while tar runs)..."
tar -xzf "$TARBALL" -C "$WORKDIR" || die "Failed to extract Hexiri tarball."
info "Extraction done."
EXTRACTED="$WORKDIR/$TOP_DIR"
[ -d "$EXTRACTED" ] || die "Extracted Hexiri tree not found: $EXTRACTED"
[ -f "$EXTRACTED/v2/install.sh" ] || die "Extracted Hexiri tree is missing v2/install.sh: $EXTRACTED"
info "Extracted to: $EXTRACTED"
info "Verified: $EXTRACTED/v2/install.sh present"

# Exec replaces this process, so the temp dir is left in /tmp for
# debugging if the installer fails. That is intentional.
info "Running the real installer: bash $EXTRACTED/v2/install.sh"
exec bash "$EXTRACTED/v2/install.sh" "$@"
