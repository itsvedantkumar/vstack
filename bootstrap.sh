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
#
# VSTACK_REF pins what gets installed. Set it explicitly (a tag, e.g. VSTACK_REF=v1.64.0, or a
# branch) to install exactly that. Leave it unset and this script resolves the latest release
# tag and installs that — never main — so `curl | bash` with no VSTACK_REF does not install
# whatever happens to be on main at that instant with no human review. Resolution tries
# `git ls-remote` first (the git protocol has no per-IP rate limit, unlike the GitHub API), then
# falls back to the GitHub releases API. If both fail (no network, no git, rate limited, no
# releases), this refuses rather than silently falling back to main; set VSTACK_REF yourself to
# proceed.
set -euo pipefail

DIR="${VSTACK_DIR:-$HOME/.vstack}"
REPO="${VSTACK_REPO:-https://github.com/itsvedantkumar/vstack.git}"

if [ -n "${VSTACK_REF:-}" ]; then
  REF="$VSTACK_REF"
else
  REF=""
  route=""
  if command -v git >/dev/null 2>&1; then
    echo "bootstrap: VSTACK_REF not set — resolving the latest release tag via git ls-remote"
    # Only exact vX.Y.Z tags are candidates; anything else (v1.2.0-rc1, non-version tags) is
    # ignored. sort -V is not used because the Alpine lane in the container matrix runs busybox,
    # which lacks it; numeric field sort after stripping the leading "v" is portable to busybox.
    tags="$(git ls-remote --tags --refs "$REPO" 'refs/tags/v*' 2>/dev/null \
      | awk '{print $2}' \
      | sed 's#^refs/tags/##' \
      | grep '^v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' \
      || true)"
    REF="$(printf '%s\n' "$tags" \
      | sed 's/^v//' \
      | sort -t. -k1,1n -k2,2n -k3,3n \
      | tail -1)"
    if [ -n "$REF" ]; then
      REF="v$REF"
      route="ls-remote"
    fi
  fi
  if [ -z "$REF" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "bootstrap: VSTACK_REF is not set, git ls-remote did not resolve a tag (or git is unavailable), and curl is unavailable to try the GitHub API." >&2
      echo "           set VSTACK_REF explicitly, e.g.: VSTACK_REF=v1.64.0 curl -fsSL ... | bash" >&2
      exit 1
    fi
    echo "bootstrap: falling back to the GitHub API to resolve the latest release tag"
    tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "$tok" ]; then
      latest_json="$(curl -fsSL --max-time 10 -H "Authorization: Bearer $tok" "https://api.github.com/repos/itsvedantkumar/vstack/releases/latest" 2>/dev/null || true)"
    else
      latest_json="$(curl -fsSL --max-time 10 "https://api.github.com/repos/itsvedantkumar/vstack/releases/latest" 2>/dev/null || true)"
    fi
    REF="$(printf '%s' "$latest_json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "$REF" ]; then
      echo "bootstrap: could not resolve the latest release tag — tried git ls-remote and the GitHub API (api.github.com unreachable, rate limited, no git, or no releases exist)." >&2
      echo "           refusing to fall back to main — set VSTACK_REF explicitly, e.g.: VSTACK_REF=v1.64.0 curl -fsSL ... | bash" >&2
      exit 1
    fi
    route="api"
  fi
  if [ "$route" = "ls-remote" ]; then
    echo "bootstrap: resolved latest release tag: $REF (via ls-remote)"
  else
    echo "bootstrap: resolved latest release tag: $REF (via GitHub API)"
  fi
fi

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
    # --no-tags/--no-prune: a bare fetch here would otherwise obey the machine-wide
    # fetch.prune/fetch.pruneTags and delete any local tag no longer on the remote.
    git -C "$DIR" fetch -q --no-tags --no-prune --depth 1 origin "$REF"
    # Same principle as the dirty-tree guard above, extended to a clean-but-diverged branch:
    # a HEAD that carries a commit origin/$REF does not have is exactly as unsafe to reset
    # over as a dirty tree, just quieter about it. Fast-forward-only resets are safe without
    # asking; anything else needs either a refusal or a durable backup ref first.
    #
    # The check is against refs/vstack/synced-$REF, a watermark this script plants on its own
    # every time it leaves the checkout in a known-good state (clone, or a safe reset below) --
    # not `merge-base --is-ancestor HEAD FETCH_HEAD`. Every checkout this script makes is
    # shallow (--depth 1), and each depth-1 fetch grafts its new tip with the real parent cut
    # off, so on a clean, untouched checkout that is legitimately just behind, ordinary
    # ancestry can no longer see past that graft to prove it safe. HEAD == our own watermark
    # answers the actual question -- "has anything been added since bootstrap last touched
    # this checkout" -- without depending on how much history git kept. A checkout from before
    # this watermark existed falls back to that ancestry check once; every run after this one
    # carries its own watermark.
    watermark_ref="refs/vstack/synced-$REF"
    watermark="$(git -C "$DIR" rev-parse -q --verify "$watermark_ref" 2>/dev/null || true)"
    head_sha="$(git -C "$DIR" rev-parse HEAD)"
    if [ -n "$watermark" ]; then
      [ "$head_sha" = "$watermark" ] && safe=1 || safe=0
    elif git -C "$DIR" merge-base --is-ancestor HEAD FETCH_HEAD 2>/dev/null; then
      safe=1
    else
      safe=0
    fi
    if [ "$safe" = 1 ]; then
      git -C "$DIR" reset -q --hard FETCH_HEAD
    elif [ "${VSTACK_FORCE:-0}" = 1 ]; then
      backup="vstack-backup-$(date +%Y%m%d-%H%M%S)"
      git -C "$DIR" branch -f "$backup" HEAD >/dev/null
      echo "bootstrap: $DIR has commits origin/$REF does not have — preserved under branch '$backup' before resetting (VSTACK_FORCE=1)" >&2
      git -C "$DIR" reset -q --hard FETCH_HEAD
    else
      echo "bootstrap: $DIR has commits not on origin/$REF; refusing to reset over them." >&2
      echo "           push them, or re-run with VSTACK_FORCE=1 to back them up under a branch and discard." >&2
      exit 1
    fi
    git -C "$DIR" update-ref "$watermark_ref" HEAD
  else
    echo "bootstrap: cloning into $DIR"
    # No fallback to the default branch. `git clone --branch` resolves a tag as readily as a
    # branch, and $REF is either an explicit VSTACK_REF or the resolved latest release tag, so
    # this only ever failed when $REF genuinely did not exist -- and substituting another ref
    # there is the one answer nobody asked for. It exited
    # 0, then planted refs/vstack/synced-$REF on a commit that is not $REF, so every later run
    # compared HEAD against a watermark that never described $REF. The tarball lane below has
    # 404'd on this same input since 1.5.0; this lane kept guessing.
    clone_err=$(mktemp)
    if ! git clone -q --depth 1 --branch "$REF" "$REPO" "$DIR" 2>"$clone_err"; then
      echo "bootstrap: could not clone $REPO at $REF" >&2
      sed 's/^/           /' "$clone_err" >&2
      echo "           VSTACK_REF must name a branch or a tag that exists on the remote." >&2
      rm -f "$clone_err"
      exit 1
    fi
    rm -f "$clone_err"
    # Plant the same watermark a fresh clone would end an update at, so the very next
    # `bootstrap.sh` run already has one to compare HEAD against instead of falling back to
    # ancestry.
    git -C "$DIR" update-ref "refs/vstack/synced-$REF" HEAD
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
