#!/usr/bin/env bash
# scorer.sh -- deterministic, offline scoring for the agent-pilot instrument.
#
# No model calls happen in this file. It reads a captured transcript (the JSON-lines a
# `claude -p ... --output-format=stream-json --verbose` invocation writes to stdout) and an
# exit-status marker, and returns one of four verdicts. No LLM judge, no rubric: every verdict
# is a grep against ground truth committed in ground-truth.json before any of the 25 calls run.
#
# THE FOUR VERDICTS, and why there are four and not two.
#
# tests/evals/optimize.sh's own header records the defect this file exists to not repeat: a
# crashed run and a run that genuinely found nothing both used to collapse to the same "0", and a
# 0 that means "no data" was then read as a 0 that means "measured and absent" -- which is how a
# harness bug gets reported as a finding. Four states here, not two:
#
#   FOUND         every pattern in the fixture's detect_all list matched. A positive result.
#   NOT_FOUND     the call completed, produced real output, and the pattern(s) are absent.
#                 A negative result -- also a finding, not a defect in the harness.
#   NOT_RUN       the call did not complete: no exit-status marker, or a nonzero/timeout exit.
#                 Nothing was measured. Not a zero.
#   NOT_CAPTURED  the call reported success but what we have is unusable: zero bytes, invalid
#                 JSON (a truncated stream), or valid JSON with no assistant-authored content at
#                 all. Nothing was measured, for a different reason than NOT_RUN, and the two
#                 are kept apart because they point at different bugs -- NOT_RUN means "look at
#                 the arm/CLI invocation", NOT_CAPTURED means "look at the redirection/capture
#                 plumbing".
#
# ASSISTANT-AUTHORED CONTENT ONLY, NEVER tool_result. This is the load-bearing design decision in
# this file. A tool_result can contain the fixture's own source text -- a Read of the file under
# review lands its full contents in a tool_result block -- so scoring against the whole transcript
# would call an arm's transcript a "FOUND" the instant it reads the file, regardless of whether
# the model said anything about the defect at all. That is exactly the class of bug
# docs/checks-that-inherit-their-answer.md catalogues: a check that inherits its answer from state
# it did not assert. The haystack below is built only from `.type=="assistant"` content -- the
# text the model wrote and the tool_use inputs it constructed -- never from `.type=="user"`
# tool_result blocks. selftest/found-nothing.jsonl is the proof: its tool_result contains both
# required tokens verbatim (it IS the source file) and its assistant text explicitly denies
# finding anything; a scorer that read tool_result would score it FOUND, and this one must not.
#
# Matching is AND-of-substrings (extended regex, grep -Eqi, case-insensitive), not a single
# complex pattern and not a model judging semantic equivalence. This is deliberately blunter than
# an LLM judge -- see PREREGISTRATION.md for why that trade is the point, and for the specific
# false-positive/false-negative risk it carries on each fixture.
#
# Usage:
#   scorer.sh score <capture.jsonl> <exit-status-file> <ground-truth.json> <fixture-id>
#   scorer.sh selftest
#
# Bash 3.2 / Linux / Alpine. No arrays, no associative arrays, no mapfile.

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v jq >/dev/null 2>&1 || { echo "scorer.sh needs jq" >&2; exit 2; }

# score_one <capture> <exit-file> <patterns-file, one ERE per line>
#   -> line 1 is the VERDICT alone; line 2+ (if any) is the detail, which may itself span
#      several lines (a NOT_FOUND detail lists every missing pattern). Callers must take line 1
#      with `head -1` and treat the rest as detail -- never `cut -f1` on the whole multi-line
#      blob, which silently reprocesses every later line and was wrong here once already.
score_one() {
  local capture="$1" exitfile="$2" patterns="$3" ec haystack missing pat

  if [ ! -f "$exitfile" ]; then
    printf 'NOT_RUN\n no exit-status marker at %s -- the call was never recorded as finishing\n' "$exitfile"
    return 0
  fi
  ec=$(tr -d '[:space:]' < "$exitfile" 2>/dev/null)
  if [ -z "$ec" ]; then
    printf 'NOT_RUN\n exit-status marker %s is empty\n' "$exitfile"
    return 0
  fi
  case "$ec" in
    0) : ;;
    *[!0-9]*)
      printf 'NOT_RUN\n exit-status marker %s is not numeric: %s\n' "$exitfile" "$ec"
      return 0 ;;
    *)
      printf 'NOT_RUN\n exit status %s (nonzero -- 124 means the per-call timeout fired)\n' "$ec"
      return 0 ;;
  esac

  if [ ! -f "$capture" ]; then
    printf 'NOT_RUN\n capture file %s does not exist despite a zero exit status\n' "$capture"
    return 0
  fi
  if [ ! -s "$capture" ]; then
    printf 'NOT_CAPTURED\n capture file %s is zero bytes despite a zero exit status\n' "$capture"
    return 0
  fi
  if ! jq -rs '.' "$capture" >/dev/null 2>&1; then
    printf 'NOT_CAPTURED\n capture file %s is not valid JSON-lines (truncated or corrupt mid-stream)\n' "$capture"
    return 0
  fi

  haystack=$(jq -rs '
    [ .[] | select(.type=="assistant") | .message.content[]?
      | if .type=="text" then .text
        elif .type=="tool_use" then (.input | tostring)
        else empty end
    ] | join("\n")' "$capture" 2>/dev/null)

  if [ -z "$haystack" ]; then
    printf 'NOT_CAPTURED\n %s parses but has no assistant-authored text or tool_use content\n' "$capture"
    return 0
  fi

  missing=""
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$haystack" | grep -Eqi -- "$pat" || missing="$missing\n  MISSING: $pat"
  done < "$patterns"

  if [ -z "$missing" ]; then
    printf 'FOUND\n all detect_all pattern(s) matched in assistant-authored output\n'
  else
    printf 'NOT_FOUND\n call completed and produced output, but not every required pattern matched:%b\n' "$missing"
  fi
  return 0
}

# score <capture> <exit-file> <ground-truth.json> <fixture-id>
cmd_score() {
  local capture="$1" exitfile="$2" gt="$3" fid="$4" patfile detect_all
  [ -f "$gt" ] || { echo "no such ground-truth file: $gt" >&2; return 2; }
  detect_all=$(jq -r --arg id "$fid" \
    '([.fixtures[]?, .canary?] | map(select(.id == $id)) | .[0].detect_all // empty) | .[]?' \
    "$gt" 2>/dev/null)
  if [ -z "$detect_all" ]; then
    echo "no fixture or canary with id '$fid' in $gt" >&2
    return 2
  fi
  patfile=$(mktemp)
  printf '%s\n' "$detect_all" > "$patfile"
  local line verdict detail
  line=$(score_one "$capture" "$exitfile" "$patfile")
  rm -f "$patfile"
  verdict=$(printf '%s\n' "$line" | head -1)
  detail=$(printf '%s\n' "$line" | tail -n +2)
  printf '%s\t%s\t%s\n' "$fid" "$verdict" "$detail"
}

# selftest -- the only execution this instrument performs before the operator opts in. Proves the
# four verdicts against hand-made transcripts, zero model calls, offline, reproducible by anyone.
cmd_selftest() {
  local t patfile fails=0
  t=$(mktemp -d "${TMPDIR:-/tmp}/agent-pilot-selftest.XXXXXX")
  patfile="$t/patterns.txt"
  printf 'FOO\nBAR\n' > "$patfile"

  printf 'agent-pilot scorer self-test -- four hand-made transcripts, zero model calls\n\n'

  # 1. FOUND
  cp "$HERE/selftest/found-everything.jsonl" "$t/found.jsonl"
  printf '0' > "$t/found.exit"
  _check "FOUND" "$(score_one "$t/found.jsonl" "$t/found.exit" "$patfile")" "found-everything.jsonl" || fails=$((fails+1))

  # 2. NOT_FOUND -- the adversarial case: tool_result contains both tokens, assistant text does not.
  cp "$HERE/selftest/found-nothing.jsonl" "$t/nothing.jsonl"
  printf '0' > "$t/nothing.exit"
  _check "NOT_FOUND" "$(score_one "$t/nothing.jsonl" "$t/nothing.exit" "$patfile")" "found-nothing.jsonl" || fails=$((fails+1))

  # 3. NOT_CAPTURED -- non-empty, exit 0, but the JSON is cut off mid-stream.
  cp "$HERE/selftest/truncated.jsonl" "$t/trunc.jsonl"
  printf '0' > "$t/trunc.exit"
  _check "NOT_CAPTURED" "$(score_one "$t/trunc.jsonl" "$t/trunc.exit" "$patfile")" "truncated.jsonl" || fails=$((fails+1))

  # 4. NOT_RUN -- zero-byte capture AND no exit-status marker was ever written (the call never
  #    finished; the harness has no record of it, not even a bad one).
  cp "$HERE/selftest/empty.jsonl" "$t/empty.jsonl"
  _check "NOT_RUN" "$(score_one "$t/empty.jsonl" "$t/empty.exit" "$patfile")" "empty.jsonl (no .exit file created)" || fails=$((fails+1))

  rm -rf "$t"
  printf '\n'
  if [ "$fails" -eq 0 ]; then
    printf 'PASS -- all four verdicts reproduced from hand-made transcripts.\n'
    return 0
  fi
  printf 'FAIL -- %s of 4 verdict(s) did not match. The scorer, not a model, is broken; fix before spending any call.\n' "$fails"
  return 1
}

_check() { # <expected-verdict> <actual "verdict\ndetail" block> <label>
  local expected="$1" line="$2" label="$3" actual detail
  actual=$(printf '%s\n' "$line" | head -1)
  detail=$(printf '%s\n' "$line" | tail -n +2)
  if [ "$actual" = "$expected" ]; then
    printf '  ok    %-13s %-28s -> %s\n' "$expected" "$label" "$detail"
    return 0
  fi
  printf '  FAIL  expected %-13s got %-13s %-28s -> %s\n' "$expected" "$actual" "$label" "$detail"
  return 1
}

case "${1:-}" in
  score)
    shift
    [ $# -eq 4 ] || { echo "usage: scorer.sh score <capture.jsonl> <exit-status-file> <ground-truth.json> <fixture-id>" >&2; exit 2; }
    cmd_score "$1" "$2" "$3" "$4"
    ;;
  selftest)
    cmd_selftest
    ;;
  *)
    sed -n '2,40p' "$0"
    exit 2
    ;;
esac
