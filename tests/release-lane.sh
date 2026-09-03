#!/usr/bin/env bash
# release-lane.sh — every lane the two GitHub workflows run, on this machine, against a tag.
#
# Written 2026-09-04, the day GitHub Actions stopped starting jobs for this account ("locked due
# to a billing issue", every job, 3 seconds in). The gates did not change; only the machine that
# ran them did. So this runs the same scripts verify.yml and release.yml run, in the same order,
# in a worktree checked out at the tag, and writes what each one printed into
# releases/<tag>.md next to the commit and tree hashes. `--publish` then creates the GitHub
# Release object through the API with notes from CHANGELOG.md, exactly as release.yml's publish
# job does, and attaches the evidence file.
#
# What is lost against CI, stated so nobody mistakes this for the same thing: the verdict is
# recorded by the machine that produced it. docs/checks-that-inherit-their-answer.md and the
# "gates must read the remote" lesson both exist because a gate that asks itself is a gate that
# can be wrong without anyone noticing. The mitigations here are mechanical: the lane refuses a
# dirty tree and a HEAD that is not the tag, every lane's accounting line is copied verbatim into
# the evidence file (not a summary), and the file names the tree hash so a reader can re-run the
# same lanes on the same bytes.
#
# Usage:
#   tests/release-lane.sh v1.71.0             # run every lane, write releases/v1.71.0.md
#   tests/release-lane.sh v1.71.0 --publish   # same, then gh release create if every lane is green
#
# Exit: 0 every lane green (and published, if asked); 1 a lane went red; 2 could not start.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:-}; PUBLISH=0; [ "${2:-}" = "--publish" ] && PUBLISH=1
[ -n "$TAG" ] || { echo "usage: tests/release-lane.sh <tag> [--publish]" >&2; exit 2; }
cd "$SRC" || exit 2
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "REFUSING: no local tag $TAG" >&2; exit 2; }
git ls-remote --tags origin "refs/tags/$TAG" | grep -q . || { echo "REFUSING: $TAG is not on origin; push it first (--no-follow-tags, atomic with main)" >&2; exit 2; }
SHA=$(git rev-parse "$TAG^{commit}"); TREE=$(git rev-parse "$TAG^{tree}")
W=${RELEASE_LANE_DIR:-/tmp/release-lane}/$TAG
EV=$SRC/releases/$TAG.md
mkdir -p "$SRC/releases"
rm -rf "$W"; git worktree prune
git worktree add -q --detach "$W" "$SHA" || { echo "REFUSING: could not create a worktree at $TAG" >&2; exit 2; }
cleanup() { git -C "$SRC" worktree remove --force "$W" 2>/dev/null; git -C "$SRC" worktree prune; }
trap cleanup EXIT

# Docker Desktop stores registry credentials behind docker-credential-desktop, which is not on
# PATH in a non-login shell; the pull then fails on credentials, not on the image. A copy of
# ~/.docker with the helper removed pulls public images fine (contexts/ must come along).
if [ -f "$HOME/.docker/config.json" ] && grep -q credsStore "$HOME/.docker/config.json" 2>/dev/null; then
  helper=$(jq -r '.credsStore // ""' "$HOME/.docker/config.json" 2>/dev/null)
  if [ -n "$helper" ] && ! command -v "docker-credential-$helper" >/dev/null 2>&1; then
    DC=${TMPDIR:-/tmp}/docker-nocreds.$$; rm -rf "$DC"; cp -R "$HOME/.docker" "$DC" 2>/dev/null
    jq 'del(.credsStore, .credHelpers)' "$HOME/.docker/config.json" > "$DC/config.json"
    export DOCKER_CONFIG="$DC"
  fi
fi

{
  printf '# %s release lane\n\n' "$TAG"
  printf -- '- commit `%s`, tree `%s`\n- run %s on %s (%s), lane script `%s`\n\n' \
    "$SHA" "$TREE" "$(date '+%Y-%m-%d %H:%M %Z')" "$(hostname -s)" "$(uname -sm)" \
    "$(git rev-parse --short HEAD):tests/release-lane.sh"
  printf '| lane | verdict | what it printed | s |\n|---|---|---|---|\n'
} > "$EV"

RED=0
lane() { # <name> <success-predicate: rc|last:STRING|acct> <command...>
  local name=$1 pred=$2; shift 2
  local t0 t1 out rc last acct verdict line
  t0=$(date +%s)
  out=$( cd "$W" && "$@" 2>&1 ); rc=$?
  t1=$(date +%s)
  last=$(printf '%s\n' "$out" | grep -vE '^\s*$' | tail -1)
  acct=$(printf '%s\n' "$out" | grep -E '^checks: ' | tail -1)
  case $pred in
    rc)      [ "$rc" -eq 0 ] && verdict=ok || verdict=RED; line=$last ;;
    acct)    if [ "$rc" -eq 0 ] && printf '%s' "$acct" | grep -qE ' 0 skipped' && [ "$last" = VERIFIED ]; then verdict=ok; else verdict=RED; fi
             line="$acct / $last" ;;
    last:*)  if [ "$rc" -eq 0 ] && printf '%s' "$last" | grep -qF "${pred#last:}"; then verdict=ok; else verdict=RED; fi; line=$last ;;
  esac
  [ "$verdict" = ok ] || RED=$((RED+1))
  line=$(printf '%s' "$line" | tr '|' '/' | cut -c1-200)
  printf '| %s | %s | %s | %d |\n' "$name" "$verdict" "$line" $((t1-t0)) >> "$EV"
  printf '%-6s %-20s %s (%ds)\n' "$verdict" "$name" "$line" $((t1-t0))
  printf '%s\n' "$out" > "$W.$name.log"
}

echo "release lane for $TAG at $SHA (worktree $W)"
lane gate               acct ./.claude/verify.sh
lane compare-baseline   rc   ./tests/compare-baseline.sh
lane breadth-mandate    rc   ./tests/test-breadth-mandate.sh
lane dispatch-static    rc   ./tests/dispatch-static.sh
lane require-checks     rc   ./tests/require-checks-green.sh
lane bin-scripts        rc   ./tests/bin-scripts.sh
lane tree-restored      rc   git diff --exit-code
lane install-matrix     rc   ./tests/install-matrix.sh
lane falsify            "last:FALSIFIABLE (" env FALSIFY_TIMEOUT_S="${FALSIFY_TIMEOUT_S:-7200}" ./tests/falsify-parallel.sh
lane container-matrix   rc   env VSTACK_REF="$TAG" ./tests/container-matrix.sh

if [ "$RED" -eq 0 ]; then
  printf '\nRELEASE LANE OK: every lane green for %s\n' "$TAG" | tee -a "$EV"
else
  printf '\nRELEASE LANE FAILED: %d lane(s) red for %s\n' "$RED" "$TAG" | tee -a "$EV"
fi

# The index the release doc links to, one row per tag, newest first, replaced in place on a rerun.
IDX=$SRC/releases/README.md
[ -f "$IDX" ] || printf '# Release evidence\n\nOne file per tag, written by `tests/release-lane.sh`. Rows are replaced on a rerun.\n\n| tag | commit | run | verdict | evidence |\n|---|---|---|---|---|\n' > "$IDX"
row=$(printf '| %s | `%s` | %s | %s | [`%s.md`](%s.md) |' "$TAG" "$(git rev-parse --short "$SHA")" "$(date +%F)" "$([ "$RED" -eq 0 ] && echo green || echo "$RED red")" "$TAG" "$TAG")
grep -vF "| $TAG |" "$IDX" > "$IDX.new"; { head -6 "$IDX.new"; printf '%s\n' "$row"; tail -n +7 "$IDX.new"; } > "$IDX"; rm -f "$IDX.new"

[ "$RED" -eq 0 ] || exit 1
[ "$PUBLISH" -eq 1 ] || exit 0

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "release $TAG already exists; not recreating"; exit 0
fi
VER=${TAG#v}
awk -v ver="$VER" '
  /^## / { if (found) exit; if ($0 ~ "^## \\[?" ver "([^0-9.]|$)") { found=1; print; next } }
  found { print }
' "$SRC/CHANGELOG.md" > "$W.notes.md"
[ -s "$W.notes.md" ] || { echo "no CHANGELOG.md section for $VER; refusing to publish without notes" >&2; exit 1; }
gh release create "$TAG" --verify-tag --title "$TAG" --notes-file "$W.notes.md" "$EV#release-lane-evidence" \
  && gh release view "$TAG" --json url,tagName,isDraft
