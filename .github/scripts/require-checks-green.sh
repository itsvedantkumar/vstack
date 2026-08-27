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
# EXIT CODES. Three, not two, and the difference is load-bearing: release.yml's
# cleanup-on-failed-gate DELETES the candidate tag from origin when this gate says no.
#
#   0  every required check completed with conclusion=success
#   1  a required check has decided against the commit (conclusion != success)
#   2  UNDECIDED -- a required check is still running, has no run recorded yet, or has runs
#      that cannot be ordered. Nothing has been decided, so nothing destructive may follow.
#
# These used to be one code. "Not finished yet" and "failed" both exited 1, the caller deleted
# the tag on either, and on 2026-08-27 that deleted v1.46.0 seconds after it was pushed while
# verify was still running -- then deadlocked, because bin/doctor's "declared release is
# fetchable" check reads the README pin, so verify cannot go green until the tag is on origin
# and the tag could not stay on origin until verify was green. A gate reporting UNKNOWN was
# already this repository's rule; the missing half is that UNKNOWN must not trigger a
# destructive remedy either.
#
# CANDIDATE_CREATED_AT (default empty) is when the candidate tag came into existence, RFC3339.
# When set, a required check whose FAILING conclusion was recorded before that moment is
# reported STALE and counted as undecided rather than as a decision against the commit.
#
# This is the other half of the exit-2 split above, and it cost two deleted tags on 2026-08-27
# to find. bin/doctor's "declared release is fetchable" and verify.sh's check 24 both assert
# that the version the README pins is a tag a stranger can reach. Before the tag is pushed,
# those checks are therefore required to be red -- they are describing the world accurately.
# Push the tag, and three minutes later this script read those pre-tag conclusions, called them
# a decision against the candidate, and cleanup-on-failed-gate deleted the tag that would have
# turned them green. Retrying reproduced it exactly, because the retry starts from the same
# state.
#
# "Undecided" is the honest reading. Those runs did not judge this candidate and could not
# have: the artefact under test did not exist while they ran. Note what this does NOT do -- a
# stale red never becomes green. It becomes exit 2, which still withholds publication. The only
# behaviour that changes is that the destructive remedy stops firing on a verdict about a world
# that did not contain the tag. A red decided after the tag exists still exits 1 and still
# deletes.
#
# Unset, everything below behaves exactly as before. A gate that softens itself when the caller
# forgets to pass a field would be a worse defect than the one this fixes.
#
# REQUIRE_CHECKS_WAIT_SECONDS (default 0) bounds an optional wait for in-progress checks, so the
# common case -- a tag pushed alongside its own commit -- resolves without a manual re-dispatch.
# 0 keeps the single-read behaviour the pre-publish second call wants: by then the answer must
# already exist, and waiting for one would be waiting for a check to change its mind.
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

CANDIDATE_CREATED_AT=${CANDIDATE_CREATED_AT:-}

# Both timestamps come from the GitHub API in the same zero-padded RFC3339 UTC shape
# (2026-08-27T15:59:16Z), which orders correctly as plain text. awk rather than bash's [[ < ]]
# so this keeps working under sh and busybox, per the repo's portability rule.
predates_candidate(){ # <completed_at> -> 0 if it is strictly earlier than the candidate
  [ -n "$CANDIDATE_CREATED_AT" ] || return 1
  # A run with no completed_at cannot be SHOWN to predate the tag. Refuse to assume it does:
  # the conservative direction here is the one that keeps deleting, not the one that grants a
  # reprieve on a missing field.
  [ -n "$1" ] && [ "$1" != "null" ] || return 1
  awk -v a="$1" -v b="$CANDIDATE_CREATED_AT" 'BEGIN{exit !(a < b)}'
}

WAIT_SECONDS=${REQUIRE_CHECKS_WAIT_SECONDS:-0}
POLL_SECONDS=${REQUIRE_CHECKS_POLL_SECONDS:-15}
_deadline_note=""

# id, started_at and completed_at are in the projection because the selection below orders on
# them. They were absent, and their absence was invisible: the selection sorted on .name, which
# is constant across the set it sorts, so nothing ever noticed the ordering keys were not there.
fetch_runs(){
  runs_json=$(gh api "repos/${repo}/commits/${sha}/check-runs" --paginate \
    --jq '.check_runs[] | {name, head_sha, status, conclusion, id, started_at, completed_at}' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "require-checks-green: gh api check-runs failed for ${sha}:"
    echo "$runs_json"
    exit 1
  fi
}
fetch_runs

# Wait only while every required check is undecided-but-alive. A decided failure ends the wait
# immediately: one required check has answered no, and no amount of waiting on the others
# changes that answer. An absent check-run counts as alive, because verify.yml queues a moment
# after the push that triggered this workflow.
if [ "$WAIT_SECONDS" -gt 0 ]; then
  _waited=0
  while [ "$_waited" -lt "$WAIT_SECONDS" ]; do
    _undecided=0; _decided_bad=0
    for name in "$@"; do
      m=$(printf '%s\n' "$runs_json" | jq -s --arg n "$name" --arg s "$sha" -f "$SCRIPT_DIR/latest-check-run.jq")
      if [ "$m" = "null" ] || [ -z "$m" ]; then _undecided=$((_undecided+1)); continue; fi
      if [ "$(printf '%s' "$m" | jq -r '.status')" != "completed" ]; then _undecided=$((_undecided+1))
      elif [ "$(printf '%s' "$m" | jq -r '.conclusion')" != "success" ]; then
        # A stale red keeps the wait alive rather than ending it. Ending here is what made the
        # 5400s budget irrelevant on 2026-08-27: the checks were decided, just decided about a
        # world without the tag, so the gate broke out of the wait in under a second and went
        # straight to the deletion.
        if predates_candidate "$(printf '%s' "$m" | jq -r '.completed_at // ""')"; then
          _undecided=$((_undecided+1))
        else _decided_bad=1; fi
      fi
    done
    [ "$_decided_bad" = 1 ] && break
    [ "$_undecided" -eq 0 ] && break
    echo "waiting  ${_undecided} required check(s) still undecided on ${sha}; ${_waited}s of ${WAIT_SECONDS}s elapsed"
    sleep "$POLL_SECONDS"
    _waited=$((_waited + POLL_SECONDS))
    fetch_runs
  done
  [ "$_waited" -ge "$WAIT_SECONDS" ] && _deadline_note=" (after waiting ${WAIT_SECONDS}s)"
fi

fail=0
undecided=0
for name in "$@"; do
  # jq -s reduces the (possibly repeated, e.g. a manual re-run) check-runs for this exact name
  # and this exact SHA to the single latest one, keyed on nothing but what the remote reports
  # right now -- never a locally cached exit code. The selection lives in latest-check-run.jq so
  # the test can exercise this exact program rather than a copy of it.
  match=$(printf '%s\n' "$runs_json" \
    | jq -s --arg n "$name" --arg s "$sha" -f "$SCRIPT_DIR/latest-check-run.jq")
  if [ "$match" = "null" ] || [ -z "$match" ]; then
    echo "MISSING  $name: no check-run recorded against ${sha}${_deadline_note} -- verify.yml has never run for this exact commit"
    undecided=1
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
    undecided=1
    continue
  fi
  if [ "$status" != "completed" ]; then
    echo "PENDING  $name: status=$status on ${sha}${_deadline_note} -- not safe to publish while a required check is still running"
    undecided=1
  elif [ "$conclusion" != "success" ]; then
    completed=$(printf '%s' "$match" | jq -r '.completed_at // ""')
    if predates_candidate "$completed"; then
      echo "STALE    $name: conclusion=$conclusion decided at ${completed}, before the candidate existed at ${CANDIDATE_CREATED_AT} -- counted as undecided, because a check that ran without the tag was not judging this release. Re-run it against ${sha} to get a verdict that means something."
      undecided=1
    else
      echo "FAILED   $name: conclusion=$conclusion on ${sha}"
      fail=1
    fi
  else
    echo "green    $name: conclusion=success on ${sha}"
  fi
done

# A decided failure outranks any number of undecided checks: one required check has answered no.
if [ "$fail" -ne 0 ]; then exit 1; fi
if [ "$undecided" -ne 0 ]; then
  echo "UNDECIDED  nothing has been decided for ${sha}; exiting 2 so the caller withholds publication WITHOUT deleting anything"
  exit 2
fi
exit 0
