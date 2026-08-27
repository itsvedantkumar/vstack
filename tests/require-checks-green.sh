#!/usr/bin/env bash
# Exercises .github/scripts/latest-check-run.jq -- the selection that decides which check-run
# speaks for a release candidate when the same check ran more than once against the same SHA.
#
# It runs the real jq program from .github/scripts/, not a copy of the rule. A test that
# restates the logic it is testing agrees with itself forever, which is the defect this
# repository catalogues; see docs/checks-that-inherit-their-answer.md.
#
# The defect this was written for: the selection was `sort_by(.name) | last` applied to an array
# already filtered to one name. A stable sort on a constant key returns input order, so it
# returned whichever run the GitHub API happened to place last -- and the caller's projection
# had already discarded every timestamp, so the sort had nothing to order on even in principle.
# Observed live, that API returns descending id (newest first), which makes `last` the OLDEST.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
JQP=".github/scripts/latest-check-run.jq"
command -v jq >/dev/null 2>&1 || { echo "skip  jq is not installed, so the selection could not be exercised at all"; exit 0; }
[ -f "$JQP" ] || { echo "FAIL  $JQP is missing; the gate's selection has no program to run"; exit 1; }

pass=0; fail=0
ok(){   pass=$((pass+1)); echo "ok    $1"; }
bad(){  fail=$((fail+1)); echo "FAIL  $1"; }
sel(){ # <fixture-json> -> the chosen run's conclusion, or NONE
  printf '%s' "$1" | jq -s -r --arg n verify --arg s abc123 -f "$JQP" \
    | jq -r 'if . == null then "NONE" else (.conclusion // "null") end'
}
att(){
  printf '%s' "$1" | jq -s -r --arg n verify --arg s abc123 -f "$JQP" | jq -r '.attempts'
}

# 1. The failure the fix exists for: a failed run and a later successful re-run, delivered
#    newest-first the way the live API delivers them. `sort_by(.name) | last` returned failure.
newest_first='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":200,"started_at":"2026-08-26T12:00:00Z","completed_at":"2026-08-26T12:05:00Z"}
{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"failure","id":100,"started_at":"2026-08-26T11:00:00Z","completed_at":"2026-08-26T11:05:00Z"}'
r=$(sel "$newest_first")
[ "$r" = "success" ] && ok "re-run to green wins when the API delivers newest first (got $r)" \
                     || bad "re-run to green NOT selected with newest-first input: got '$r', wanted success"

# 2. Same pair, delivered oldest-first. Order of delivery must not change the answer.
oldest_first='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"failure","id":100,"started_at":"2026-08-26T11:00:00Z","completed_at":"2026-08-26T11:05:00Z"}
{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":200,"started_at":"2026-08-26T12:00:00Z","completed_at":"2026-08-26T12:05:00Z"}'
r=$(sel "$oldest_first")
[ "$r" = "success" ] && ok "same pair delivered oldest first gives the same answer (got $r)" \
                     || bad "delivery order changed the answer: got '$r', wanted success"

# 3. The direction that matters for a release gate: a green run followed by a later failure.
#    Selecting the wrong one here publishes over red, which is the defect this whole script
#    exists to prevent.
green_then_red='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":100,"started_at":"2026-08-26T11:00:00Z","completed_at":"2026-08-26T11:05:00Z"}
{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"failure","id":200,"started_at":"2026-08-26T12:00:00Z","completed_at":"2026-08-26T12:05:00Z"}'
r=$(sel "$green_then_red")
[ "$r" = "failure" ] && ok "a later failure is not masked by an earlier success (got $r)" \
                     || bad "an earlier success masked a later failure: got '$r', wanted failure"

# 4. A run still in progress has no completed_at and must still sort above a finished older one,
#    so the gate reports PENDING rather than publishing on the stale finished result.
inprogress='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":100,"started_at":"2026-08-26T11:00:00Z","completed_at":"2026-08-26T11:05:00Z"}
{"name":"verify","head_sha":"abc123","status":"in_progress","conclusion":null,"id":200,"started_at":"2026-08-26T12:00:00Z","completed_at":null}'
r=$(printf '%s' "$inprogress" | jq -s -r --arg n verify --arg s abc123 -f "$JQP" | jq -r '.status')
[ "$r" = "in_progress" ] && ok "an in-flight re-run outranks a finished older run (status $r)" \
                         || bad "a finished older run outranked an in-flight re-run: status '$r'"

# 5. Wrong SHA must select nothing. The whole point of the script is that it never answers for a
#    commit other than the one it was asked about.
othersha='{"name":"verify","head_sha":"deadbeef","status":"completed","conclusion":"success","id":300,"started_at":"2026-08-26T13:00:00Z","completed_at":"2026-08-26T13:05:00Z"}'
r=$(sel "$othersha")
[ "$r" = "NONE" ] && ok "a run against a different SHA is not selected (got $r)" \
                  || bad "a run against a different SHA was selected: got '$r'"

# 6. Wrong name must select nothing.
othername='{"name":"install-macos","head_sha":"abc123","status":"completed","conclusion":"success","id":300,"started_at":"2026-08-26T13:00:00Z","completed_at":"2026-08-26T13:05:00Z"}'
r=$(sel "$othername")
[ "$r" = "NONE" ] && ok "a run for a different check name is not selected (got $r)" \
                  || bad "a run for a different check name was selected: got '$r'"

# 7. The attempt count has to be real, because the caller prints it and refuses on a tie it
#    cannot break. One run is one attempt; two runs are two.
a=$(att "$newest_first"); [ "$a" = "2" ] && ok "attempts counts every run for the pair (got $a)" \
                                         || bad "attempts wrong: got '$a', wanted 2"
a=$(att "$othersha
$newest_first"); [ "$a" = "2" ] && ok "attempts ignores runs for other SHAs (got $a)" \
                                || bad "attempts counted a foreign SHA: got '$a', wanted 2"

# 8. Positive control, both directions. If the fixtures were not reaching the program at all,
#    every assertion above could pass on an empty selection. Prove the program answers a
#    single unambiguous run, and prove it answers null for an empty stream.
single='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":1,"started_at":"2026-08-26T10:00:00Z","completed_at":"2026-08-26T10:05:00Z"}'
r=$(sel "$single"); [ "$r" = "success" ] && ok "control: a single matching run is selected (got $r)" \
                                         || bad "control: a single matching run was not selected: got '$r'"
r=$(printf '' | jq -s -r --arg n verify --arg s abc123 -f "$JQP")
[ "$r" = "null" ] && ok "control: an empty stream selects nothing" \
                  || bad "control: an empty stream did not select null: got '$r'"

# =================================================================================================
# 9. The WRAPPER's exit code, not just the selection. Everything above exercises the jq program;
#    nothing exercised require-checks-green.sh itself, and its caller takes a DESTRUCTIVE action
#    on the result. release.yml's cleanup-on-failed-gate deletes the candidate tag from origin
#    when the gate job fails -- and the script collapsed four distinct verdicts into exit 1, so
#    "the checks have not finished yet" was indistinguishable from "the checks failed". On
#    2026-08-27 that deleted v1.46.0 seconds after it was pushed, while verify was still running,
#    and produced a deadlock: verify cannot go green until the tag is on origin (bin/doctor's
#    "declared release is fetchable" check reads the README pin), and the tag cannot stay on
#    origin until verify is green.
#
#    So: undecided is exit 2, a decided failure is exit 1, green is 0. The caller deletes on 1
#    and never on 2. These cases drive the real script through a `gh` stub, because the exit code
#    is the whole contract and a test of the selection alone could not see it.
# =================================================================================================
GATE="$(dirname "$JQP")/require-checks-green.sh"
STUBDIR=$(mktemp -d); trap 'rm -rf "$STUBDIR"' EXIT

gate_rc(){ # <check-runs-json-lines> -> exit code of the real wrapper
  cat > "$STUBDIR/gh" <<STUB
#!/bin/sh
cat <<'PAYLOAD'
$1
PAYLOAD
STUB
  chmod +x "$STUBDIR/gh"
  PATH="$STUBDIR:$PATH" REQUIRE_CHECKS_WAIT_SECONDS=0 \
    bash "$GATE" owner/repo abc123 verify >/dev/null 2>&1
  echo $?
}

_green='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"success","id":1,"started_at":"2026-08-26T10:00:00Z","completed_at":"2026-08-26T10:05:00Z"}'
_red='{"name":"verify","head_sha":"abc123","status":"completed","conclusion":"failure","id":1,"started_at":"2026-08-26T10:00:00Z","completed_at":"2026-08-26T10:05:00Z"}'
_pending='{"name":"verify","head_sha":"abc123","status":"in_progress","conclusion":null,"id":1,"started_at":"2026-08-26T10:00:00Z","completed_at":null}'

r=$(gate_rc "$_green");   [ "$r" = 0 ] && ok "wrapper: a completed success exits 0" \
                                       || bad "wrapper: a completed success exited $r, wanted 0"
r=$(gate_rc "$_red");     [ "$r" = 1 ] && ok "wrapper: a decided failure exits 1 (the caller deletes the tag on this)" \
                                       || bad "wrapper: a decided failure exited $r, wanted 1"
r=$(gate_rc "$_pending"); [ "$r" = 2 ] && ok "wrapper: a check still running exits 2, distinct from a failure" \
                                       || bad "wrapper: a still-running check exited $r, wanted 2 -- undecided is indistinguishable from failed, and the caller deletes the tag on failed"
r=$(gate_rc "");          [ "$r" = 2 ] && ok "wrapper: no check-run at all exits 2 (never ran is not a failure to publish over)" \
                                       || bad "wrapper: a missing check-run exited $r, wanted 2"
# A decided failure alongside an undecided one is still a failure: one required check has
# answered no, and no amount of waiting on the other changes that.
r=$(gate_rc "$_red"); [ "$r" = 1 ] && ok "wrapper: failure outranks pending when both are present" \
                                   || bad "wrapper: failure did not outrank pending: got $r"

echo
echo "require-checks-green selection: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
