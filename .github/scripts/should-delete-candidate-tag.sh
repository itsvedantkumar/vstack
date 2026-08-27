#!/usr/bin/env bash
# should-delete-candidate-tag.sh — decides whether a candidate release tag has earned deletion.
#
# This decision used to live entirely in a GitHub Actions `if:` expression on the
# cleanup-on-failed-gate job. An `if:` expression cannot be run, so the one piece of this
# workflow that destroys something -- it force-deletes a tag from origin -- was the only piece
# with no test. It has already been wrong once in production: on 2026-08-27 it deleted the tag
# for a gate that was UNDECIDED rather than failed, which deadlocked releases, because verify
# cannot go green until the tag is on origin and the tag could not survive long enough for
# verify to finish.
#
# The rule, stated once so both the workflow and its test read the same sentence:
#
#   Delete when a required job has DECIDED against this tag. Keep when nothing has decided yet.
#
# "Undecided" is the only carve-out and it is deliberately narrow. Every other refusal -- a
# decided failure, a bad tag name, a commit that is not an ancestor of main, a gate step that
# died before it could set its verdict -- still deletes, so "a failed required job cannot
# produce a published tag" holds exactly as it did before the carve-out existed.
#
# Usage: should-delete-candidate-tag.sh <resolve-result> <gate-verdict> <matrix-result>
#   resolve-result  the `needs.resolve.result` string: success | failure | cancelled | skipped
#   gate-verdict    the `needs.resolve.outputs.gate` string: green | failed | undecided | ""
#   matrix-result   the `needs.container-matrix.result` string
#
# Exit codes, distinct on purpose. 1 is reserved for "this script broke", so a crash can never
# be mistaken for either verdict:
#   0   DELETE  -- something decided against this tag
#   10  KEEP    -- nothing has decided against it yet
#   2   usage error
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: should-delete-candidate-tag.sh <resolve-result> <gate-verdict> <matrix-result>" >&2
  exit 2
fi

resolve="$1"
gate="$2"
matrix="$3"

# The container matrix has no undecided state to carve out: it either ran the images or it did
# not, and a failure there is a decision. Checked first because it is unconditional.
if [ "$matrix" = failure ]; then
  echo "DELETE  container-matrix failed -- the images this tag claims to support did not build"
  exit 0
fi

if [ "$resolve" = failure ]; then
  if [ "$gate" = undecided ]; then
    # The whole reason this script exists. A gate that has not been answered has not answered NO.
    echo "KEEP    resolve failed but the gate is undecided -- nothing has decided against this tag, and deleting on 'not yet' deadlocks the release"
    exit 10
  fi
  # Includes gate=failed, gate=green-but-a-later-step-failed, and gate="" for a job that died
  # before the gate step ran. Conservative direction: anything that is not specifically "not
  # yet" is treated as a decision.
  echo "DELETE  resolve failed with gate='${gate:-<unset>}' -- a required check decided against this tag, or the job died before it could say otherwise"
  exit 0
fi

echo "KEEP    resolve=${resolve} matrix=${matrix} -- no required job failed"
exit 10
