#!/usr/bin/env bash
# bootstrap.sh — install vstack on a machine that does not have it yet.
#
# Designed for Conductor cloud workspaces, fresh Macs, and CI: it clones (or updates) vstack
# into ~/.vstack and runs the installer. Idempotent — running it twice converges to the same
# state instead of failing or duplicating work.
#
#   curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh | bash
#
# Any arguments are passed straight to install.sh:
#   ... | bash -s -- --with-launchd
#
# Pin a different checkout location with VSTACK_DIR, or a fork with VSTACK_REPO.
set -euo pipefail

DIR="${VSTACK_DIR:-$HOME/.vstack}"
REPO="${VSTACK_REPO:-https://github.com/itsvedantkumar/vstack.git}"

command -v git >/dev/null || { echo "bootstrap: git is required" >&2; exit 1; }

if [ -d "$DIR/.git" ]; then
  echo "bootstrap: updating $DIR"
  git -C "$DIR" fetch -q --depth 1 origin HEAD
  git -C "$DIR" reset -q --hard FETCH_HEAD
else
  echo "bootstrap: cloning into $DIR"
  git clone -q --depth 1 "$REPO" "$DIR"
fi

chmod 755 "$DIR/install.sh"
exec "$DIR/install.sh" "$@"
