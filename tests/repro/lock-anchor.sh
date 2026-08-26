#!/usr/bin/env bash
# lock-anchor.sh — standalone assertion for P0 item 2's third finding: the falsifiability lock is
# keyed on `git rev-parse --git-dir`, which is PER-WORKTREE (verified empirically: differs between
# a linked worktree and the main checkout of the same repo, while `--git-common-dir` and
# `git worktree list` are identical from every worktree -- see
# docs/worktree-collision-detection.md). A lock written under one worktree's --git-dir is
# invisible to a peer working in a different worktree of the same repo, or to .claude/verify.sh's
# own read of it if the read and write sides ever drift onto different anchors.
#
# This does not touch tests/gate-falsifiability.sh or .claude/verify.sh (both outside this
# session's file ownership) -- it only asserts what they currently contain, against the sandbox
# harness function below, so the assertion is provably both-directions and not just "grep found
# the old string".
#
# Direction 1 (known-bad, today's real files): FAILS, naming exactly which line still uses the
# per-worktree anchor.
# Direction 2 (a corrected copy, git-common-dir): PASSES.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

# assert_anchor(file, line-regex, label): fails if the matched line uses `--git-dir` (bare, not
# `--git-common-dir`) to build the falsifiability lock path.
assert_anchor(){
  local f="$1" pat="$2" label="$3" line
  line=$(grep -nE "$pat" "$f" 2>/dev/null | head -1)
  if [ -z "$line" ]; then
    bad "$label: pattern not found in $f (file moved or rewritten -- update this test's pattern)"
    return
  fi
  case "$line" in
    *git-common-dir*) ok "$label uses --git-common-dir (shared across worktrees): $line" ;;
    *) bad "$label still anchors the lock on --git-dir (per-worktree, invisible to a peer worktree): $line" ;;
  esac
}

echo "=== today's real files (expected to fail until patched -- see docs/worktree-collision-detection.md) ==="
assert_anchor "$REPO/tests/gate-falsifiability.sh" 'LOCK=.*rev-parse --git-(common-)?dir' \
  "tests/gate-falsifiability.sh:LOCK="
assert_anchor "$REPO/.claude/verify.sh" '_lk=.*rev-parse --git-(common-)?dir' \
  ".claude/verify.sh:_lk="
assert_anchor "$REPO/.claude/verify.sh" '_gd=.*rev-parse --git-(common-)?dir' \
  ".claude/verify.sh:_gd= (check 14b's own probe helper)"

echo
echo "=== control: a corrected copy of the same line passes ==="
TMPFILE=$(mktemp)
printf 'LOCK="$(git rev-parse --git-common-dir 2>/dev/null)/vstack-falsifiability.lock"\n' > "$TMPFILE"
assert_anchor "$TMPFILE" 'LOCK=.*rev-parse --git-(common-)?dir' "control (corrected)"
rm -f "$TMPFILE"

echo
echo "$PASS passed, $FAIL failed"
echo "(3 FAILs on today's files is the expected, honest red state -- this script proves the"
echo " assertion is real by also passing on a corrected copy, not by asserting nothing.)"
[ "$FAIL" -eq 0 ]
