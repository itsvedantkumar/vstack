#!/usr/bin/env bash
# require-no-unexpected-skips.sh — a CI lane's own declaration of which .claude/verify.sh
# checks are allowed to skip on it, enforced against the gate's real stdout.
#
# .claude/verify.sh's own accounting only fails a run when a declared check reports nothing at
# all (RAN + SKIPPED != TOTAL). A check that legitimately prints "skip" -- because a tool this
# lane never installed on purpose is missing, or because the repo has not been tagged at its
# current declared version yet -- does not move FAIL, and never has. That is correct for the
# gate itself: "skip" is an honest, distinct outcome from "ok", not a silent failure. It stops
# being correct the moment a LANE calls its own run green without looking at what skipped,
# because "verify.sh exited 0" and "verify.sh proved what this lane exists to prove" are two
# different facts, and macOS and Alpine reporting the first as the second is exactly the defect
# class this repo exists to catch (see check 19 in verify.yml, and check 35 in verify.sh itself).
#
# So each lane that calls this script names, out loud, in its own workflow step, every skip it
# is willing to accept -- and anything else that skips fails the lane, not the gate.
#
# Usage: require-no-unexpected-skips.sh <gate-output-file> [approved-check-name ...]
#   <gate-output-file>   captured stdout+stderr of .claude/verify.sh (any format containing
#                        lines shaped "skip  NAME (reason)", which is verify.sh's own skip()).
#   approved-check-name  zero or more check names (verify.sh's check 12, "declared version
#                        matches what installs", is a legitimate example: it skips on every
#                        commit before the release that tags it, on every platform). Pass none
#                        to require the lane run with zero skips at all.
set -uo pipefail

out="${1:?usage: require-no-unexpected-skips.sh <gate-output-file> [approved-check-name ...]}"
shift

if [ ! -f "$out" ]; then
  echo "require-no-unexpected-skips: $out does not exist -- the gate step did not run or did not capture output"
  exit 1
fi

unexpected=0
approved_seen=0
while IFS= read -r line; do
  case "$line" in
    "skip  "*)
      name="${line#skip  }"
      name="${name% (*}"
      match=0
      for a in "$@"; do
        [ "$a" = "$name" ] && { match=1; break; }
      done
      if [ "$match" -eq 1 ]; then
        printf 'approved skip: %s\n' "$line"
        approved_seen=$((approved_seen + 1))
      else
        printf 'UNEXPECTED SKIP: %s\n' "$line"
        unexpected=$((unexpected + 1))
      fi
      ;;
  esac
done < "$out"

printf 'skip audit: %d approved, %d unexpected\n' "$approved_seen" "$unexpected"
if [ "$unexpected" -gt 0 ]; then
  echo "this lane declared which skips it accepts; the rest are a regression, not an environment fact"
  exit 1
fi
exit 0
