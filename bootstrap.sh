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

chmod 755 "$DIR/install.sh" "$DIR/setup-machine.sh" 2>/dev/null || true

# A brand new machine has none of the tools this depends on, so install them first. The
# dependency step is idempotent, so on a machine that already has everything it just prints
# what it found. Pass --skip-deps to go straight to the config install.
DEPS=1
ARGS=""
for a in "$@"; do
  if [ "$a" = "--skip-deps" ]; then DEPS=0; else ARGS="$ARGS $a"; fi
done

if [ "$DEPS" = 1 ] && [ -x "$DIR/setup-machine.sh" ]; then
  "$DIR/setup-machine.sh" || { echo "bootstrap: required tools are missing, stopping" >&2; exit 1; }
  echo
fi

# shellcheck disable=SC2086
exec "$DIR/install.sh" $ARGS
