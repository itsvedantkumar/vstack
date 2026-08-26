#!/usr/bin/env bash
# worktree-collision.sh — repro/proof for P0 item 2 (worktree collision detection).
#
# Three properties, each already named as a real defect this repo hit:
#
#  1. "A save/restore EXIT trap in a test harness deleted two agents' uncommitted work, because
#     the restore was unconditional." tests/lib-collision-guard.sh's cg_restore must refuse when
#     the file changed since the harness's own last known write, not silently overwrite it.
#  2. "tests/gate-falsifiability.sh does not [restore on SIGTERM], and a killed sweep left a
#     mutation behind in claude/commands/test.md." cg_install_trap must fire the restore on
#     SIGTERM (and INT/HUP), not only on a clean EXIT.
#  3. tests/gate-falsifiability.sh's collision lock is keyed on `git rev-parse --git-dir`, which
#     is PER-WORKTREE (verified: differs between a linked worktree and the main checkout, while
#     `--git-common-dir` and `git worktree list` are identical from both). cg_worktree_report must
#     name a live lock in ANY worktree of the repo, holding a lock anchored the same way.
#
# Fully sandboxed: a throwaway git repo and its own linked worktree, both under one mktemp -d.
# Never touches this repo's real .git, and HOME/TMPDIR are reassigned so nothing here can reach
# the operator's real ~/.claude either.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LIB="$REPO/tests/lib-collision-guard.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/worktree-collision-repro.XXXXXX")
# Resolved through cd+pwd: macOS's default $TMPDIR commonly carries a trailing slash, which
# mktemp then concatenates into a path with a literal double slash. Git normalizes the path it
# records in worktrees/<name>/gitdir, so a later literal string compare against $WT (direction 4)
# would spuriously fail on the double slash alone rather than on anything this test is about.
SANDBOX=$(cd "$SANDBOX" && pwd)
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM HUP

export HOME="$SANDBOX/home"
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$HOME" "$TMPDIR"
REAL_DELEG="$HOME/.claude/vstack-delegation-log.jsonl"

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

if [ ! -f "$LIB" ]; then
  bad "tests/lib-collision-guard.sh does not exist yet -- this is the red state"
  echo; echo "$PASS passed, $FAIL failed"; exit 1
fi
# shellcheck source=/dev/null
. "$LIB"

echo "=== setup: a throwaway repo with one linked worktree, entirely inside the sandbox ==="
GR="$SANDBOX/repo"
mkdir -p "$GR"
git -C "$GR" init -q -b main
git -C "$GR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
WT="$SANDBOX/wt1"
git -C "$GR" worktree add -q --detach "$WT" HEAD

echo
echo "=== direction 1: restore succeeds when nothing touched the file after the harness's own write ==="
F="$SANDBOX/plain.txt"
printf 'ORIGINAL\n' > "$F"
cg_save "$F"
printf 'MUTATED\n' > "$F"
cg_checkpoint "$F"
cg_restore "$F"; rc=$?
got=$(cat "$F" 2>/dev/null)
[ "$rc" -eq 0 ] && ok "cg_restore returns 0 (restored) when untouched since checkpoint" \
  || bad "cg_restore did not return 0 on the clean case (rc=$rc)"
[ "$got" = "ORIGINAL" ] && ok "file content is back to ORIGINAL" \
  || bad "file content after restore is '$got', expected ORIGINAL"

echo
echo "=== direction 2: restore REFUSES when a peer edited the file after the harness's own write ==="
F2="$SANDBOX/collide.txt"
printf 'ORIGINAL\n' > "$F2"
cg_save "$F2"
printf 'MUTATED\n' > "$F2"
cg_checkpoint "$F2"
printf 'PEER EDIT ON TOP OF THE MUTATION\n' > "$F2"    # simulates another agent's concurrent edit
out=$(cg_restore "$F2" 2>&1); rc=$?
got2=$(cat "$F2" 2>/dev/null)
[ "$rc" -eq 1 ] && ok "cg_restore returns 1 (refused) when the file changed since checkpoint" \
  || bad "cg_restore did not refuse the foreign change (rc=$rc): $out"
[ "$got2" = "PEER EDIT ON TOP OF THE MUTATION" ] && ok "the peer's edit is intact -- not clobbered" \
  || bad "the peer's edit was overwritten: '$got2'"
case "$out" in *"$F2"*) ok "the refusal names the file" ;; *) bad "the refusal did not name the file: $out" ;; esac
[ -f "$F2.cg-orig" ] && ok "the harness's own saved copy is still on disk for manual recovery" \
  || bad "the harness's saved copy was deleted despite refusing to restore"
rm -f "$F2.cg-orig" "$F2.cg-orighash" "$F2.cg-lasthash"

echo
echo "=== direction 3: SIGTERM triggers the restore, not only a clean exit ==="
F3="$SANDBOX/sigterm.txt"
printf 'ORIGINAL\n' > "$F3"
(
  # shellcheck source=/dev/null
  . "$LIB"
  cg_save "$F3"
  printf 'MUTATED\n' > "$F3"
  cg_checkpoint "$F3"
  cg_install_trap "$F3"
  sleep 30
) &
child=$!
sleep 0.3
kill -TERM "$child" 2>/dev/null
wait "$child" 2>/dev/null
sleep 0.2
got3=$(cat "$F3" 2>/dev/null)
[ "$got3" = "ORIGINAL" ] && ok "SIGTERM to the harness restored the file (cg_install_trap covers TERM, not just EXIT)" \
  || bad "file after SIGTERM is '$got3', expected ORIGINAL -- a kill leaves the mutation behind"

echo
echo "=== direction 4: cg_worktree_report names a live lock in a DIFFERENT worktree of the same repo ==="
COMMON=$(cd "$GR" && git rev-parse --git-common-dir)
COMMON=$(cd "$GR" && cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")
sleep 30 & lockpid=$!
mkdir -p "$COMMON/worktrees"
# Find the worktree's own git-dir name (there is exactly one linked worktree here).
wtname=$(basename "$(dirname "$(grep -l "$WT" "$COMMON"/worktrees/*/gitdir 2>/dev/null | head -1)")" 2>/dev/null)
if [ -z "$wtname" ]; then
  for d in "$COMMON"/worktrees/*/; do
    [ -f "${d}gitdir" ] && grep -q "$WT" "${d}gitdir" 2>/dev/null && wtname=$(basename "$d")
  done
fi
if [ -n "$wtname" ]; then
  printf '%s\n' "$lockpid" > "$COMMON/worktrees/$wtname/vstack-falsifiability.lock"
  report=$(cd "$GR" && cg_worktree_report 2>&1); rc=$?
  echo "  report from the MAIN checkout, about a lock held in the linked worktree:"
  echo "$report" | sed 's/^/    /'
  [ "$rc" -eq 0 ] && ok "cg_worktree_report finds the collision from a different checkout of the same repo" \
    || bad "cg_worktree_report returned $rc -- did not find the live lock in the other worktree"
  case "$report" in *"$lockpid"*) ok "report names the PID" ;; *) bad "report did not name the PID" ;; esac
  case "$report" in *"$WT"*) ok "report names the worktree path holding the lock" ;; *) bad "report did not name the worktree path ($WT): $report" ;; esac
else
  bad "test setup could not resolve the linked worktree's own git-dir name -- cannot exercise direction 4"
fi
kill "$lockpid" 2>/dev/null
wait "$lockpid" 2>/dev/null

echo
echo "=== direction 5: no live lock anywhere -> cg_worktree_report reports nothing, returns 1 ==="
report2=$(cd "$GR" && cg_worktree_report 2>&1); rc2=$?
[ "$rc2" -eq 1 ] && [ -z "$report2" ] && ok "clean state: no collision reported, empty output, rc=1" \
  || bad "clean state reported something (rc=$rc2): $report2 -- false positive after the lock's process died"

git -C "$GR" worktree remove --force "$WT" 2>/dev/null

echo
echo "$PASS passed, $FAIL failed"
[ -f "$REAL_DELEG" ] && bad "sandbox wrote to a path shaped like the real delegation log (should be absent here)"
[ "$FAIL" -eq 0 ]
