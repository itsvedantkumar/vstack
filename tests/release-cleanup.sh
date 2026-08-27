#!/usr/bin/env bash
# Exercises the one destructive decision in .github/workflows/release.yml: whether a candidate
# release tag gets force-deleted from origin. The decision used to be a GitHub Actions `if:`
# expression, which no test can run; it is now a script, and this is the truth table for it.
#
# Offline. No network, no gh, no repository state. It runs the real script with real arguments.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# RELEASE_CLEANUP_SCRIPT points this table at a copy of the decider. Check 51 uses it to run the
# same table against a deliberately broken copy and require it to FAIL -- a truth table that
# cannot go red is a green measuring nothing, which is the defect this repository is named for.
S="${RELEASE_CLEANUP_SCRIPT:-$SRC/.github/scripts/should-delete-candidate-tag.sh}"
PASS=0; FAIL=0

# <expected: delete|keep> <resolve> <gate> <matrix> <why this case exists>
want(){
  _exp="$1"; shift; _r="$1"; _g="$2"; _m="$3"; _why="$4"
  _out=$(bash "$S" "$_r" "$_g" "$_m" 2>&1); _rc=$?
  case "$_rc" in
    0)  _got=delete ;;
    10) _got=keep ;;
    *)  _got="rc=$_rc" ;;
  esac
  if [ "$_got" = "$_exp" ]; then
    PASS=$((PASS + 1)); printf 'ok    %s\n' "$_why"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n      resolve=%s gate=%s matrix=%s -> wanted %s, got %s (%s)\n' \
      "$_why" "$_r" "$_g" "$_m" "$_exp" "$_got" "$_out"
  fi
}

# The carve-out, and the only reason this script exists. Deleting here deadlocked releases on
# 2026-08-27: verify cannot go green until the tag is on origin, and the tag was deleted before
# verify could finish, so no tag could ever earn the green it needed.
want keep   failure undecided success "a gate that has not answered has not answered no"

# Everything that IS a decision still deletes. "a failed required job cannot produce a published
# tag" is the property the carve-out must not weaken, so each of its shapes is pinned.
want delete failure failed    success "a decided gate failure deletes"
want delete failure ""        success "a gate step that died before setting a verdict deletes"
want delete failure green     success "resolve failing AFTER a green gate still deletes"
want delete success ""        failure "a container-matrix failure deletes on its own"
want delete failure undecided failure "matrix failure outranks an undecided gate"

# Nothing failed: there is nothing to clean up. This case reaches the script at all only because
# the job's `if:` is deliberately broader than the rule.
want keep   success green     success "a fully green run deletes nothing"
want keep   success ""        skipped "a skipped matrix on a green resolve deletes nothing"

# A crash must be distinguishable from both verdicts, or an unhandled error reads as "delete".
_out=$(bash "$S" only-one-arg 2>&1); _rc=$?
if [ "$_rc" = 2 ]; then
  PASS=$((PASS + 1)); printf 'ok    a usage error is neither verdict (rc=2)\n'
else
  FAIL=$((FAIL + 1)); printf 'FAIL  a usage error is neither verdict: rc=%s (%s)\n' "$_rc" "$_out"
fi

# The join, not the halves. A tested script the workflow does not call is a test of nothing, and
# a workflow that still carries part of the rule in its `if:` has two deciders and one test.
_rel="$SRC/.github/workflows/release.yml"
if grep -q 'should-delete-candidate-tag.sh' "$_rel"; then
  PASS=$((PASS + 1)); printf 'ok    release.yml actually calls the script this file tests\n'
else
  FAIL=$((FAIL + 1)); printf 'FAIL  release.yml does not call should-delete-candidate-tag.sh -- this whole file tests code nothing runs\n'
fi
_ifline=$(grep -n 'cleanup-on-failed-gate' -A 20 "$_rel" | grep -m1 '^\s*[0-9]*-\?\s*if:')
if printf '%s' "$_ifline" | grep -q 'gate'; then
  FAIL=$((FAIL + 1)); printf 'FAIL  the cleanup job'"'"'s `if:` still mentions the gate verdict, so the rule lives in two places and only one of them is tested:\n      %s\n' "$_ifline"
else
  PASS=$((PASS + 1)); printf 'ok    the cleanup job'"'"'s `if:` carries no part of the delete rule\n'
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
