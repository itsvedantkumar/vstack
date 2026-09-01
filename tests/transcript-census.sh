#!/usr/bin/env bash
# transcript-census.sh -- recompute the corpus figures CHANGELOG 1.57.0 published as prose, and
# prove the arithmetic that produces them against fixtures with hand-computed answers.
#
# WHAT THIS FIXES. CHANGELOG 1.57.0 states six numbers about this machine's transcript corpus --
# 2536 transcripts, 20508 assistant tool-using messages, 516 Skill invocations, 2.52 per 100,
# 1008 dispatches, 0.0 fan-out per record against 53.0% per run -- and `git grep` for any of them
# returned CHANGELOG.md and nothing else. No instrument, no fixture, no command a reader could
# run. Those numbers were a recollection wearing a measurement's clothes, in a repository whose
# entire subject is that distinction.
#
# TWO MODES, AND WHY THEY ARE SEPARATE:
#   (default)     census over a real corpus. Prints JSON. Cannot run on CI -- there are no
#                 transcripts there -- and prints INCONCLUSIVE with exit 3 rather than a rate
#                 when the corpus is empty. An empty census is not 0%, it is nothing.
#   --self-test   fixtures with hand-computed answers, zero real transcripts, zero model calls.
#                 This is the half that is checkable everywhere and the half check 63 runs. An
#                 instrument whose only evidence is the corpus it measured cannot be falsified.
#
# THE FIXTURES ARE THE POINT. Each PROOF below pins one arithmetic decision that a plausible
# alternative implementation gets wrong in a way that still prints a number:
#   PROOF 1  a batch streamed as N consecutive same-id records is ONE batch, not N solo dispatches
#   PROOF 2  N distinct ids in a row is N serial dispatches, not one batch
#   PROOF 3  an id reappearing after an intervening turn does NOT rejoin its earlier run
#            (this is the compaction hazard: ids repeat thousands of lines apart)
#   PROOF 4  the per-100 rate divides by tool-using messages, the denominator the CHANGELOG names
#   PROOF 5  */subagents/*.jsonl leaves are excluded, or every delegation is counted twice
#   PROOF 6  an empty corpus reports INCONCLUSIVE and exits non-zero, never 0.0%
#   PROOF 7  records with a null message.id are not silently merged into one another's runs
#
# Usage: tests/transcript-census.sh [--self-test] [corpus-root]
#   corpus-root defaults to ~/.claude/projects.
#
# Zero model calls. Read-only: this script never writes outside its own mktemp -d.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)
PY="$SRC/tests/transcript-census.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not on PATH; this census needs stdlib json/os/sys."
  exit 0
fi

if [ "${1:-}" != "--self-test" ]; then
  exec python3 "$PY" "${1:-$HOME/.claude/projects}"
fi

RAN=0
FAIL=0
TOTAL=$(grep -c '^# --- PROOF [0-9]' "$SRC/tests/transcript-census.sh")

ok(){  printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){ printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vstack-transcript-census.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# asst <message-id-or-null> <tool-name>...  -> one assistant JSONL record carrying those tool_use
# blocks. Real Claude Code streams one block per record; the fixtures below stream them the same
# way on purpose, because a fixture that packs four blocks into one record proves an input shape
# that never occurs and would let the per-record metric pass.
asst(){
  _id=$1; shift
  _blocks=""
  for _n in "$@"; do
    _in='{}'
    [ "$_n" = "Skill" ] && _in='{"skill":"swarm"}'
    _blocks="$_blocks{\"type\":\"tool_use\",\"name\":\"$_n\",\"input\":$_in},"
  done
  _blocks=${_blocks%,}
  if [ "$_id" = "null" ]; then
    printf '{"type":"assistant","message":{"id":null,"content":[%s]}}\n' "$_blocks"
  else
    printf '{"type":"assistant","message":{"id":"%s","content":[%s]}}\n' "$_id" "$_blocks"
  fi
}
usr(){ printf '{"type":"user","message":{"content":"go"}}\n'; }

# field <json> <key> -- read one top-level key out of the engine's output.
field(){ printf '%s' "$1" | python3 -c 'import json,sys;print(json.load(sys.stdin)[sys.argv[1]])' "$2" 2>/dev/null; }

run_census(){ python3 "$PY" "$1" 2>/dev/null; }

expect(){ # <label> <got> <want>
  if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1" "got $2, want $3"; fi
}

# --- PROOF 1: a batch of 3, streamed as 3 consecutive same-id records, is ONE batch.
C1="$WORK/p1/proj"; mkdir -p "$C1"
{ asst m1 Agent; asst m1 Agent; asst m1 Agent; } > "$C1/s.jsonl"
J=$(run_census "$WORK/p1")
expect "P1 dispatches"            "$(field "$J" dispatches)"                 "3"
expect "P1 records_with_2plus"    "$(field "$J" records_with_2plus_dispatches)" "0"
expect "P1 fanout_per_record_pct" "$(field "$J" fanout_per_record_pct)"      "0.0"
expect "P1 runs_with_dispatch"    "$(field "$J" runs_with_dispatch)"         "1"
expect "P1 fanout_per_run_pct"    "$(field "$J" fanout_per_run_pct)"         "100.0"

# --- PROOF 2: 3 distinct ids in a row is 3 serial dispatches, not a batch.
C2="$WORK/p2/proj"; mkdir -p "$C2"
{ asst m1 Agent; asst m2 Agent; asst m3 Agent; } > "$C2/s.jsonl"
J=$(run_census "$WORK/p2")
expect "P2 runs_with_dispatch"  "$(field "$J" runs_with_dispatch)"  "3"
expect "P2 batched_runs"        "$(field "$J" batched_runs)"        "0"
expect "P2 fanout_per_run_pct"  "$(field "$J" fanout_per_run_pct)"  "0.0"

# --- PROOF 3: an id reappearing after an intervening user turn does NOT rejoin its earlier run.
# Global grouping by id -- the obvious implementation -- reports 1 batch of 2 here and inflates
# every corpus containing a compaction boundary.
C3="$WORK/p3/proj"; mkdir -p "$C3"
{ asst m1 Agent; usr; asst m1 Agent; } > "$C3/s.jsonl"
J=$(run_census "$WORK/p3")
expect "P3 runs_with_dispatch" "$(field "$J" runs_with_dispatch)" "2"
expect "P3 batched_runs"       "$(field "$J" batched_runs)"       "0"

# --- PROOF 4: the per-100 rate divides by tool-using messages, not by records or by transcripts.
C4="$WORK/p4/proj"; mkdir -p "$C4"
{ asst m1 Skill; asst m2 Read; asst m3 Read; asst m4 Read; } > "$C4/s.jsonl"
J=$(run_census "$WORK/p4")
expect "P4 tool_using_messages" "$(field "$J" tool_using_messages)"                  "4"
expect "P4 skill_invocations"   "$(field "$J" skill_invocations)"                    "1"
expect "P4 per_100"             "$(field "$J" skill_per_100_tool_using_messages)"    "25.0"

# --- PROOF 5: */subagents/*.jsonl leaves are excluded, or every delegation counts twice.
C5="$WORK/p5/proj"; mkdir -p "$C5/subagents"
asst m1 Agent > "$C5/s.jsonl"
{ asst m9 Agent; asst m9 Agent; } > "$C5/subagents/leaf.jsonl"
J=$(run_census "$WORK/p5")
expect "P5 transcripts" "$(field "$J" transcripts)" "1"
expect "P5 dispatches"  "$(field "$J" dispatches)"  "1"

# --- PROOF 6: an empty corpus reports INCONCLUSIVE and exits non-zero, never 0.0%.
C6="$WORK/p6"; mkdir -p "$C6/proj"
OUT=$(python3 "$PY" "$C6" 2>&1); RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'INCONCLUSIVE'; then
  ok "P6 empty corpus is INCONCLUSIVE, rc=$RC"
else
  bad "P6 empty corpus" "rc=$RC, output: $(printf '%s' "$OUT" | head -1)"
fi

# --- PROOF 7: records with a null message.id are not merged into one another's runs.
C7="$WORK/p7/proj"; mkdir -p "$C7"
{ asst null Agent; asst null Agent; } > "$C7/s.jsonl"
J=$(run_census "$WORK/p7")
expect "P7 runs_with_dispatch" "$(field "$J" runs_with_dispatch)" "2"
expect "P7 batched_runs"       "$(field "$J" batched_runs)"       "0"

echo
printf 'proofs: %s declared, %s assertion(s) ran\n' "$TOTAL" "$RAN"
if [ "$RAN" -lt "$TOTAL" ]; then
  echo "ACCOUNTING FAILED: fewer assertions ran than proofs declared."
  exit 1
fi
if [ "$FAIL" -ne 0 ]; then echo "CENSUS ARITHMETIC UNPROVEN"; exit 1; fi
echo "CENSUS ARITHMETIC PROVEN"
