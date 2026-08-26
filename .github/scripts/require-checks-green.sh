#!/usr/bin/env bash
# require-checks-green.sh — reads the conclusion of every required check-run for one exact
# commit SHA, never a branch's current tip. This is the fix for the defect this repo has
# already shipped once: six releases went out over red CI because every gate asked the machine
# it happened to be running on, not the remote's own record for the commit being released. This
# reads gh's `conclusion` field for the candidate SHA and nothing else.
#
# A moving branch ref (main, HEAD) answers "is the newest thing on this branch green", which
# silently drifts to a different commit than the one about to be tagged the instant someone
# pushes again. This takes a SHA as an argument for exactly that reason: called against a fixed
# commit, its answer cannot change out from under the caller between two calls unless a check
# was re-run for that same SHA -- which is the one case release.yml calls this script twice to
# catch (once on entry, once immediately before publication).
#
# Usage: require-checks-green.sh <repo:owner/name> <sha> <required-check-name> [<name> ...]
set -uo pipefail

repo="${1:?usage: require-checks-green.sh <owner/repo> <sha> <required-check-name> [...]}"
sha="${2:?missing sha}"
shift 2
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 0 ]; then
  echo "require-checks-green: no required check names given -- refusing to declare an empty gate satisfied"
  exit 1
fi

# id, started_at and completed_at are in the projection because the selection below orders on
# them. They were absent, and their absence was invisible: the selection sorted on .name, which
# is constant across the set it sorts, so nothing ever noticed the ordering keys were not there.
runs_json=$(gh api "repos/${repo}/commits/${sha}/check-runs" --paginate \
  --jq '.check_runs[] | {name, head_sha, status, conclusion, id, started_at, completed_at}' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "require-checks-green: gh api check-runs failed for ${sha}:"
  echo "$runs_json"
  exit 1
fi

fail=0
for name in "$@"; do
  # jq -s reduces the (possibly repeated, e.g. a manual re-run) check-runs for this exact name
  # and this exact SHA to the single latest one, keyed on nothing but what the remote reports
  # right now -- never a locally cached exit code. The selection lives in latest-check-run.jq so
  # the test can exercise this exact program rather than a copy of it.
  match=$(printf '%s\n' "$runs_json" \
    | jq -s --arg n "$name" --arg s "$sha" -f "$SCRIPT_DIR/latest-check-run.jq")
  if [ "$match" = "null" ] || [ -z "$match" ]; then
    echo "MISSING  $name: no check-run recorded against ${sha} -- verify.yml has never run for this exact commit"
    fail=1
    continue
  fi
  status=$(printf '%s' "$match" | jq -r '.status')
  conclusion=$(printf '%s' "$match" | jq -r '.conclusion')
  attempts=$(printf '%s' "$match" | jq -r '.attempts')
  earlier=$(printf '%s' "$match" | jq -r '.earlier_conclusions | join(",")')
  # A re-run to green is legitimate and GitHub's own semantics make the latest run
  # authoritative, so this does not fail the gate. It is printed because "green" and "green on
  # the third attempt" are different facts about a release candidate, and the second one should
  # not have to be reconstructed from the Actions tab afterwards.
  if [ "$attempts" != "1" ]; then
    echo "note     $name: $attempts run(s) recorded for this SHA; earlier conclusions: $earlier"
  fi
  # No ordering key on any run means the latest could not be identified. Say so and refuse
  # rather than publish on whichever one the API happened to return last.
  if [ "$attempts" != "1" ] \
     && [ "$(printf '%s' "$match" | jq -r '.started_at // ""')" = "" ]; then
    echo "UNKNOWN  $name: $attempts runs for ${sha} and none carries a timestamp, so the latest cannot be identified"
    fail=1
    continue
  fi
  if [ "$status" != "completed" ]; then
    echo "PENDING  $name: status=$status on ${sha} -- not safe to publish while a required check is still running"
    fail=1
  elif [ "$conclusion" != "success" ]; then
    echo "FAILED   $name: conclusion=$conclusion on ${sha}"
    fail=1
  else
    echo "green    $name: conclusion=success on ${sha}"
  fi
done

exit "$fail"
