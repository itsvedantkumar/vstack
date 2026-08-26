#!/usr/bin/env bash
# bootstrap-safety.sh — regression probe for bootstrap.sh's "update an existing checkout" path.
#
# CLAIM (defect 5): bootstrap.sh's local-changes guard inspects only `git status --porcelain`
# (the WORKING TREE), never the relationship between the local branch and the upstream ref it
# is about to fetch. A clean checkout that is ahead of, or diverged from, origin/<ref> passes
# that check exactly like a checkout that has nothing to lose, and both get
# `git fetch --depth 1 origin "$REF" && git reset --hard FETCH_HEAD`, which moves the branch tip
# off any commit not reachable from FETCH_HEAD. No warning is printed for this case (contrast
# with the dirty-tree case, which prints an explicit refusal) and bootstrap.sh writes no named
# ref of its own to recover from it — the only survivors are git's own generic, single-slot,
# eventually-expiring ORIG_HEAD and reflog, which bootstrap.sh does not mention and which the
# very next `bootstrap.sh` run (or `git gc`) can erase.
#
# Four states, all against local, file-path "origin"s (never the network, never the real
# vstack checkout): dirty, ahead, behind, diverged. Exit non-zero while an unpushed commit
# can vanish from its branch with nothing durable pointing at it; exit zero once bootstrap.sh
# either refuses to reset a checkout carrying unpushed work, or preserves that work under a
# named ref (a branch or tag — not merely ORIG_HEAD/reflog) before moving the branch.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/bootstrap.sh"
[ -f "$BOOTSTRAP" ] || { echo "FATAL: $BOOTSTRAP missing" >&2; exit 2; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-safety.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
note() { printf '%s\n' "$1"; }
ok()   { printf 'PASS: %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fail=1; }

# --- a "surviving under a named ref" check: does any branch or tag OTHER than the current HEAD
# still point at $sha? ORIG_HEAD and the reflog do not count -- they are generic, single-slot
# (ORIG_HEAD is overwritten by the very next reset) or time-limited (reflog expiry), and
# bootstrap.sh does not tell anyone to look at either. ---------------------------------------
sha_has_named_ref() {
  repo="$1"; sha="$2"
  git -C "$repo" for-each-ref --format='%(objectname) %(refname)' refs/heads refs/tags 2>/dev/null \
    | awk -v s="$sha" '$1 == s { found=1 } END { exit !found }'
}

# --- build one fixture "upstream" with a fresh HOME/DIR pair per state ----------------------
new_upstream() {
  up_work="$SANDBOX/$1-upstream-work"
  up_bare="$SANDBOX/$1-upstream.git"
  mkdir -p "$up_work"
  git -C "$up_work" init -q -b main >/dev/null 2>&1 || (cd "$up_work" && git init -q && git checkout -q -b main)
  git -C "$up_work" config user.email up@example.com
  git -C "$up_work" config user.name  "Upstream Fixture"
  printf '#!/bin/sh\necho "fixture install.sh ran"\n' > "$up_work/install.sh"
  chmod 755 "$up_work/install.sh"
  mkdir -p "$up_work/.claude"
  echo '{}' > "$up_work/.claude/settings.json"
  git -C "$up_work" add -A
  git -C "$up_work" commit -q -m "A: initial fixture"
  git clone -q --bare "$up_work" "$up_bare"
  printf '%s %s\n' "$up_work" "$up_bare"
}

run_bootstrap() {
  # $1=DIR $2=REPO
  HOME="$SANDBOX/home-$$-$RANDOM" VSTACK_DIR="$1" VSTACK_REPO="$2" VSTACK_REF="main" \
    bash "$BOOTSTRAP" --skip-deps
}

clone_initial() {
  # $1=DIR $2=REPO -- first run just clones (DIR does not exist yet)
  mkdir -p "$(dirname "$1")"
  run_bootstrap "$1" "$2" >/dev/null 2>&1
}

echo "=== state: dirty (uncommitted change, must be REFUSED) ==="
read -r UPWORK UPBARE <<< "$(new_upstream dirty)"
[ -n "$UPWORK" ] && [ -n "$UPBARE" ] || { echo "FATAL: fixture upstream path capture failed for state=dirty" >&2; exit 2; }
DIR="$SANDBOX/dirty-dir"
clone_initial "$DIR" "$UPBARE"
echo "dirty change" > "$DIR/uncommitted.txt"
before_sha=$(git -C "$DIR" rev-parse HEAD)
set +e
out=$(run_bootstrap "$DIR" "$UPBARE" 2>&1)
rc=$?
set -e
note "$out"
note "exit code: $rc"
after_sha=$(git -C "$DIR" rev-parse HEAD)
if [ "$rc" -ne 0 ] && [ -f "$DIR/uncommitted.txt" ] && [ "$before_sha" = "$after_sha" ]; then
  ok "dirty: bootstrap refused and left the checkout untouched"
else
  bad "dirty: bootstrap did not cleanly refuse (rc=$rc, file present=$([ -f "$DIR/uncommitted.txt" ] && echo yes || echo no), sha unchanged=$([ "$before_sha" = "$after_sha" ] && echo yes || echo no))"
fi
echo

echo "=== state: ahead (clean tree, one unpushed local commit) ==="
read -r UPWORK UPBARE <<< "$(new_upstream ahead)"
[ -n "$UPWORK" ] && [ -n "$UPBARE" ] || { echo "FATAL: fixture upstream path capture failed for state=ahead" >&2; exit 2; }
DIR="$SANDBOX/ahead-dir"
clone_initial "$DIR" "$UPBARE"
echo "local unpushed work" > "$DIR/unpushed.txt"
(cd "$DIR" && git add -A && git commit -q -m "B: unpushed local commit")
B_SHA=$(git -C "$DIR" rev-parse HEAD)
note "local commit B = $B_SHA ; working tree clean: $(git -C "$DIR" status --porcelain | wc -l | tr -d ' ') dirty entries"
set +e
out=$(run_bootstrap "$DIR" "$UPBARE" 2>&1)
rc=$?
set -e
note "$out"
note "bootstrap exit code: $rc"
if git -C "$DIR" merge-base --is-ancestor "$B_SHA" HEAD 2>/dev/null; then
  ok "ahead: unpushed commit B is still on the branch"
elif sha_has_named_ref "$DIR" "$B_SHA"; then
  ok "ahead: unpushed commit B was moved off the branch but preserved under a named ref"
else
  bad "ahead: unpushed commit B vanished from the branch with no warning and no named recovery ref (only ORIG_HEAD=$(git -C "$DIR" rev-parse ORIG_HEAD 2>/dev/null || echo none) / reflog, both ephemeral)"
fi
echo

echo "=== state: behind (clean tree, no local commits, upstream advanced) ==="
read -r UPWORK UPBARE <<< "$(new_upstream behind)"
[ -n "$UPWORK" ] && [ -n "$UPBARE" ] || { echo "FATAL: fixture upstream path capture failed for state=behind" >&2; exit 2; }
DIR="$SANDBOX/behind-dir"
clone_initial "$DIR" "$UPBARE"
echo "server progress" > "$UPWORK/server.txt"
(cd "$UPWORK" && git add -A && git commit -q -m "C: upstream progress")
git -C "$UPWORK" push -q "$UPBARE" main
C_SHA=$(git -C "$UPWORK" rev-parse HEAD)
set +e
out=$(run_bootstrap "$DIR" "$UPBARE" 2>&1)
rc=$?
set -e
note "$out"
note "bootstrap exit code: $rc"
if [ "$(git -C "$DIR" rev-parse HEAD)" = "$C_SHA" ] && [ "$rc" -eq 0 ]; then
  ok "behind: fast-forwarded cleanly to upstream C, nothing local to lose"
else
  bad "behind: did not converge to upstream cleanly (rc=$rc, HEAD=$(git -C "$DIR" rev-parse HEAD), expected $C_SHA)"
fi
echo

echo "=== state: diverged (clean tree, local unpushed commit AND upstream advanced independently) ==="
read -r UPWORK UPBARE <<< "$(new_upstream diverged)"
[ -n "$UPWORK" ] && [ -n "$UPBARE" ] || { echo "FATAL: fixture upstream path capture failed for state=diverged" >&2; exit 2; }
DIR="$SANDBOX/diverged-dir"
clone_initial "$DIR" "$UPBARE"
echo "local diverged work" > "$DIR/diverged.txt"
(cd "$DIR" && git add -A && git commit -q -m "D: local unpushed, diverged")
D_SHA=$(git -C "$DIR" rev-parse HEAD)
echo "more server progress" > "$UPWORK/server2.txt"
(cd "$UPWORK" && git add -A && git commit -q -m "E: more upstream progress")
git -C "$UPWORK" push -q "$UPBARE" main
E_SHA=$(git -C "$UPWORK" rev-parse HEAD)
note "local commit D = $D_SHA ; upstream commit E = $E_SHA ; working tree clean: $(git -C "$DIR" status --porcelain | wc -l | tr -d ' ') dirty entries"
set +e
out=$(run_bootstrap "$DIR" "$UPBARE" 2>&1)
rc=$?
set -e
note "$out"
note "bootstrap exit code: $rc"
if git -C "$DIR" merge-base --is-ancestor "$D_SHA" HEAD 2>/dev/null; then
  ok "diverged: unpushed commit D is still on the branch"
elif sha_has_named_ref "$DIR" "$D_SHA"; then
  ok "diverged: unpushed commit D was moved off the branch but preserved under a named ref"
else
  bad "diverged: unpushed commit D vanished from the branch with no warning and no named recovery ref (only ORIG_HEAD=$(git -C "$DIR" rev-parse ORIG_HEAD 2>/dev/null || echo none) / reflog, both ephemeral)"
fi
echo

if [ "$fail" -eq 0 ]; then
  echo "RESULT: bootstrap.sh never silently drops unpushed commits (fixed)"
else
  echo "RESULT: bootstrap.sh can silently discard unpushed commits on a clean-but-ahead/diverged checkout (defect 5 reproduced)"
fi
exit "$fail"
