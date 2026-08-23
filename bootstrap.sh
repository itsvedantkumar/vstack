#!/usr/bin/env bash
# bootstrap.sh — install vstack on a machine that does not have it yet.
#
# Designed for Conductor cloud workspaces, fresh Macs, and CI: it clones (or updates) vstack
# into ~/.vstack and runs the installer. Idempotent — running it twice converges to the same
# state instead of failing or duplicating work.
#
#   curl -fsSL https://raw.githubusercontent.com/itsvedantkumar/vstack/main/bootstrap.sh | bash
#
# Any arguments are passed straight to install.sh. Pin a different checkout location with
# VSTACK_DIR, or a fork with VSTACK_REPO.
set -euo pipefail

DIR="${VSTACK_DIR:-$HOME/.vstack}"
REPO="${VSTACK_REPO:-https://github.com/itsvedantkumar/vstack.git}"

REF="${VSTACK_REF:-main}"

# The README calls this the lane for "a machine with nothing on it", and it used to exit here
# when git was absent — on a fresh Mac git arrives with the Xcode command line tools, which is
# precisely the prerequisite this is supposed to remove. Requiring git before it can install
# git made the headline command fail for its stated audience.
#
# So fall back to the source tarball, which needs only curl and tar. The checkout it leaves is
# not a git repo, which is a real limitation: `vstack update` needs one. Say so rather than
# leaving someone to discover it.
if command -v git >/dev/null 2>&1; then
  # git is back and the existing install came from the tarball path: convert it rather than
  # failing. Only a directory carrying our own marker is replaced, and it is moved aside rather
  # than deleted, because "recognised as ours" is a weaker claim than "safe to destroy".
  if [ -d "$DIR" ] && [ ! -d "$DIR/.git" ] && [ -f "$DIR/.vstack-tarball" ]; then
    echo "bootstrap: converting the tarball install at $DIR into a git checkout"
    mv "$DIR" "$DIR.tarball-$(date +%Y%m%d-%H%M%S)"
  elif [ -d "$DIR" ] && [ ! -d "$DIR/.git" ]; then
    echo "bootstrap: $DIR exists, is not a git checkout, and was not created by this script." >&2
    echo "           move it aside and re-run, or point VSTACK_DIR somewhere else." >&2
    exit 1
  fi
  if [ -d "$DIR/.git" ]; then
    echo "bootstrap: updating $DIR"
    # Never discard work that is not ours. A hard reset on a dirty checkout silently deleted
    # tracked edits, and the documented rerun bypassed the review that `vstack update` does.
    if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
      if [ "${VSTACK_FORCE:-0}" = 1 ]; then
        echo "bootstrap: $DIR has local changes — discarding them because VSTACK_FORCE=1" >&2
      else
        echo "bootstrap: $DIR has local changes; refusing to reset over them." >&2
        echo "           commit or stash them, or re-run with VSTACK_FORCE=1 to discard." >&2
        git -C "$DIR" status --short >&2
        exit 1
      fi
    fi
    git -C "$DIR" fetch -q --depth 1 origin "$REF"
    git -C "$DIR" reset -q --hard FETCH_HEAD
  else
    echo "bootstrap: cloning into $DIR"
    git clone -q --depth 1 --branch "$REF" "$REPO" "$DIR" 2>/dev/null \
      || git clone -q --depth 1 "$REPO" "$DIR"
  fi
elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
  # A previous tarball install leaves a directory that is not a git checkout. Re-running once
  # git exists then tried to clone into it and died with "already exists and is not an empty
  # directory" — the recovery the no-git path itself recommends could not run. Recognising our
  # own tarball marker is what makes replacing it safe; anything else is left alone.
  # /archive/<ref>.tar.gz resolves a tag or a branch. The refs/heads/ form only resolves a
  # branch, so the fallback 404'd for exactly the value the README tells people to pin —
  # VSTACK_REF=v1.4.0 — which is the case it most needed to serve.
  TARBALL="${REPO%.git}/archive/$REF.tar.gz"
  echo "bootstrap: git not found — fetching the source tarball instead"
  echo "           (\`vstack update\` needs git; install it and re-run to get a real checkout)"
  tmp=$(mktemp -d)
  curl -fsSL "$TARBALL" -o "$tmp/vstack.tar.gz" \
    || { echo "bootstrap: could not download $TARBALL" >&2; rm -rf "$tmp"; exit 1; }
  mkdir -p "$DIR"
  tar -xzf "$tmp/vstack.tar.gz" -C "$tmp"
  src=$(find "$tmp" -maxdepth 1 -type d -name 'vstack-*' | head -1)
  [ -n "$src" ] || { echo "bootstrap: unexpected tarball layout" >&2; rm -rf "$tmp"; exit 1; }
  # cp the CONTENTS, and keep dotfiles: .claude/ carries the gate this repo verifies itself with.
  (cd "$src" && tar -cf - .) | (cd "$DIR" && tar -xf -)
  # The marker is what lets a later run with git recognise this as ours and convert it.
  printf 'installed by bootstrap.sh from %s because git was unavailable\n' "$TARBALL" > "$DIR/.vstack-tarball"
  rm -rf "$tmp"
else
  echo "bootstrap: needs either git, or curl and tar, and this machine has none of them." >&2
  echo "           macOS: xcode-select --install     Debian/Ubuntu: apt install -y git" >&2
  echo "           Alpine: apk add git               Fedora: dnf install -y git" >&2
  exit 1
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
  # VSTACK_CHAINED tells setup-machine.sh its own "done. Next: ./install.sh" is about to happen
  # automatically one line below, not left for the operator to remember. VSTACK_PLUGINS is not
  # set here -- setup-machine.sh's claude-mem/frontend-design/typescript-lsp installs stay
  # opt-in through this one-liner exactly as they are run directly; set VSTACK_PLUGINS=1 before
  # this command, or pass --with-plugins to setup-machine.sh yourself, to pull them in.
  VSTACK_CHAINED=1 "$DIR/setup-machine.sh" \
    || { echo "bootstrap: required tools are missing, stopping" >&2; exit 1; }
  echo
fi

# shellcheck disable=SC2086  # $ARGS is a caller-supplied flag list and has to word-split here;
                              # quoting it would hand install.sh one argument containing spaces
exec "$DIR/install.sh" $ARGS
