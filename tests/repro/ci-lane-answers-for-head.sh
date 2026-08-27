#!/usr/bin/env bash
# ci-lane-answers-for-head.sh — regression test: does bin/doctor's CI check answer for the commit
# you are standing on, or for whatever ran most recently on main?
#
# The defect, confirmed 2026-08-27:
#
#   gh run list --branch main --limit 1 --json conclusion,status,displayTitle,databaseId
#
# `--branch main` is a MOVING reference and `--limit 1` takes whatever is newest under it. The
# projection has no `headSha` in it at all, so nothing downstream could have filtered by commit
# even if it wanted to. Stand on a commit whose CI has not run, or has failed, and doctor prints
#
#   CI (main: an OLDER commit that passed)   ✔
#
# which is a true statement about a different commit. `--limit 1` also picks one workflow
# arbitrarily when several run per commit -- this repo runs `verify` and `release`, and on
# 2026-08-27 `release` completed first with a failure while `verify` was still going.
#
# This is the exact defect .github/workflows/release.yml's own header describes and warns
# against ("a moving branch ref answers 'is the newest thing on this branch green', which
# silently drifts to a different commit"), reproduced in the one check whose job is to stop a
# release going out over red CI.
#
# Drives the real bin/doctor through a `gh` stub. No network, no model calls.
# Usage: bash tests/repro/ci-lane-answers-for-head.sh   -- exit 0 clean, 1 while the defect is live.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SRC" || exit 1
HEADSHA=$(git rev-parse HEAD)
OTHERSHA=0000000000000000000000000000000000000000
FAIL=0
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT

# <rows-json> -> the CI line doctor printed, verdict glyph and all
ci_line(){
  cat > "$S/gh" <<STUB
#!/bin/sh
case "\$*" in
  *"run list"*) printf '%s\n' '$1' ;;
  *"api"*)      printf '%s\n' '$1' ;;
  *)            exit 0 ;;
esac
STUB
  chmod +x "$S/gh"
  PATH="$S:$PATH" bash "$SRC/bin/doctor" 2>&1 | grep -E '^CI' | head -1
}

check(){ # <name> <ok?> <detail>
  if [ "$2" = 0 ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s\n      %s\n' "$1" "$3"; FAIL=$((FAIL + 1)); fi
}

row(){ # <sha> <status> <conclusion> <title>
  printf '[{"headSha":"%s","name":"verify","status":"%s","conclusion":"%s","displayTitle":"%s","databaseId":111}]' \
    "$1" "$2" "$3" "$4"
}

# 1. The defect proper. A green run belonging to some other commit must not read as this
#    commit's CI being green.
l=$(ci_line "$(row "$OTHERSHA" completed success 'an OLDER commit that passed')")
check "a success for a different commit is not reported as green" \
      "$(case "$l" in (*'✔'*) echo 1 ;; (*) echo 0 ;; esac)" \
      "doctor printed: $l -- that run belongs to $OTHERSHA, not to HEAD"

# 2. A green run for THIS commit is green. Without this the check above passes by doctor
#    never saying ✔ at all.
l=$(ci_line "$(row "$HEADSHA" completed success 'this very commit')")
check "a success for this exact commit is reported as green" \
      "$(case "$l" in (*'✔'*) echo 0 ;; (*) echo 1 ;; esac)" \
      "doctor printed: $l -- the run is for HEAD and completed successfully"

# 3. A failure for this commit is a failure, not a note and not silence.
l=$(ci_line "$(row "$HEADSHA" completed failure 'this very commit, red')")
check "a failure for this exact commit is reported as a failure" \
      "$(case "$l" in (*'✖'*) echo 0 ;; (*) echo 1 ;; esac)" \
      "doctor printed: $l"

# 4. Still running is UNKNOWN. Not green, and not a failure either -- the repository's own rule
#    for an answer that does not exist yet, and the half that cost v1.46.0 its tag.
l=$(ci_line "$(row "$HEADSHA" in_progress '' 'this very commit, still going')")
check "a run still in progress for this commit is neither green nor a failure" \
      "$(case "$l" in (*'✔'*|*'✖'*) echo 1 ;; (*) echo 0 ;; esac)" \
      "doctor printed: $l"

# 5. No run at all for this commit is UNKNOWN, not green. A commit that has never been pushed
#    has no CI verdict, and the newest run on main is not a stand-in for one.
l=$(ci_line "$(row "$OTHERSHA" completed success 'someone else entirely')")
check "no run for this commit means no verdict, never a green one" \
      "$(case "$l" in (*'✔'*) echo 1 ;; (*) echo 0 ;; esac)" \
      "doctor printed: $l"

printf '\n%s check(s) failed\n' "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
