#!/usr/bin/env bash
# delegation-drift.sh -- does the rate at which breadth-eligible work gets delegated fall off
# across a session's own lifetime, as measured by the Stop-hook logger claude/hooks/skill-mandate.sh
# now writes on every evaluated Stop?
#
# CAUSAL LIMIT, stated here because it is the most important line in the file: this is
# correlational, not an experiment. The specific reverse-causality risk (BETH's, and it must
# appear here as loudly as tests/compaction-effect.sh states its own): late-session work may be
# inherently less delegable -- a final review, a one-line wrap-up -- so the TASK SHAPE changes
# with session position, not only the model's behaviour. Pooling only over breadth-eligible
# windows (dir_count>=3, ext_count>=2 already true at the moment measured) holds instantaneous
# task shape roughly constant; it does not control for fatigue or for cumulative compaction
# exposure across the session. Read every number below as "associated with", never as
# "caused by". See tests/delegation-drift.py's own header for the full exposition, including why
# the primary metric is skill-mandate.sh's own breadth threshold rather than an invented one, and
# why replay is a conservative UNDER-count relative to the live hook.
#
# PRE-REGISTRATION (written before this script was run against real data):
#   Primary: breadth-eligible-window delegation rate (hit = task_count>=1, skill-mandate.sh's own
#   definition of "already delegated" -- it is what suppresses that mandate's block), pooled by
#   normalised session position into first-third vs last-third.
#     SIGNAL (decay)   iff last-third <= SIGNAL_DECAY_RATIO(0.7)x first-third, AND
#                       >= MIN_ELIGIBLE_PER_TERTILE(8) eligible windows per tertile, AND
#                       >= MIN_CONTRIBUTING_SESSIONS(5) contributing sessions.
#     "Keeps working"  iff last-third in [KEEPS_WORKING_LOW(0.85), KEEPS_WORKING_HIGH(1.15)]x
#                       first-third, same floors.
#     Gray zone        0.7x-0.85x: reported as-is, no verdict claimed.
#     Below any floor: NOT EVALUATED, not a rate -- exactly tests/compaction-effect.sh's own
#     discipline, which found 8 qualifying sessions in 3,134 for the identical reason (a metric
#     that started measuring after most of the corpus already existed) and reported that
#     truthfully rather than as a false positive or a false negative.
#   Secondary, reported ALONGSIDE and never in place of the primary: call-sign attribution rate
#   among task_count>=1 checkpoints. Rejected as a primary metric on purpose: it only fires when a
#   dispatch already happened, so it is structurally blind to the failure mode that matters most --
#   stopping delegation entirely rather than delegating without naming who.
#   Also rejected, and not to be reintroduced: "work that warranted delegation but was done
#   inline" as the eligibility test. That needs an LLM judge to define "warranted" -- a fourth
#   confound on top of task-shape drift, fatigue, and compaction exposure -- and it would mean
#   this script's own threshold could no longer be defended as reverse-engineering-proof.
#   These thresholds were fixed by reading only claude/hooks/skill-mandate.sh's own already-shipped
#   breadth condition and tests/compaction-effect.sh's already-shipped floor-and-ratio shape --
#   never by looking at a delegation rate first and picking a threshold that flatters it.
#
# INVALIDATES THE RUN: mixed-version pool (a change to skill-mandate.sh's dir/ext counting logic
# straddling the pooled data without a control re-run -- not mechanically detectable from this
# log schema, so treat any pooled number as provisional after such a change until a control
# re-run confirms the harness itself did not move, same discipline tests/README.md's
# "A harness change invalidates its own prior findings" section already states for
# tests/auto-trigger.sh and tests/compaction-effect.sh); identical per-session outcome vectors
# (auto-detected by tests/delegation-drift.py -- extraction broken, not real invariance); any
# floor unmet (the NOT EVALUATED path above, not a separate failure).
#
# Zero model calls. Two sources, one schema (session_id, checkpoint_index, dir_count, ext_count,
# task_count, named): the forward log claude/hooks/skill-mandate.sh writes on every evaluated
# Stop, and a replay pass over ~/.claude/projects/*/*.jsonl that recomputes the same four fields
# from raw tool_use blocks, restricted to transcripts postdating a2d7f46 (the commit that fixed
# task_count to recognize "Agent" alongside "Task" -- anything earlier replays a hook that was
# structurally blind to its own dispatches, a different treatment condition, not the one this
# measures). Expect NOT EVALUATED on day one: the forward log starts empty and the replay window
# is hours old. That is the correct outcome, not a failure -- see tests/README.md's
# compaction-effect.sh note for the precedent.
#
# Usage: tests/delegation-drift.sh
#   Override VSTACK_DELEGATION_LOG to point at a different forward log (claude/hooks/skill-mandate.sh
#   honours the same variable when writing it).
#   Override PROJECTS_DIR to point at a different ~/.claude/projects for testing.
#   Override SIGNAL_DECAY_RATIO / KEEPS_WORKING_LOW / KEEPS_WORKING_HIGH /
#   MIN_ELIGIBLE_PER_TERTILE / MIN_CONTRIBUTING_SESSIONS / CUTOFF_COMMIT_ISO to re-run at
#   different floors -- doing so invalidates comparison against a run at the defaults above.
#
# This file also carries its own fixture proofs (PROOF 1-N below), in the same discipline
# tests/test-breadth-mandate.sh uses for claude/hooks/skill-mandate.sh: ok/bad/skip accounting
# that refuses to report success when a declared check produced neither. They prove the logger
# writes the schema correctly, prove rotation engages at the stated cap, prove the opt-out env
# var actually opts out, and prove the analyser's tertile/verdict logic against synthetic data
# crafted to land on each threshold boundary -- including the zero-session INCONCLUSIVE path and
# the broken-extraction INVALID path, both of which must exit non-zero rather than print a
# success-shaped summary.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)
PY="$SRC/tests/delegation-drift.py"
HOOK="$SRC/claude/hooks/skill-mandate.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not on PATH; this analysis needs stdlib json/math/re/datetime."
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH; claude/hooks/skill-mandate.sh needs it and so do these fixtures."
  exit 0
fi

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(grep -c '^# --- PROOF [0-9]' "$SRC/tests/delegation-drift.sh")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vstack-delegation-drift.XXXXXX")"
# The hook's per-session checkpoint counter and 2-strike latch (both keyed by session_id) live
# under $TMPDIR, not $WORK, because they have to survive across the hook's own separate
# invocations within one session -- same reason tests/test-breadth-mandate.sh sweeps its own
# fixed session ids before AND after every run. Swept here on both sides of the run for the same
# reason: without a pre-sweep, a stray leftover from a manual `bash claude/hooks/skill-mandate.sh`
# debug invocation using session_id "ddproof1" (identical to PROOF 1's fixed id, discovered by
# hand while building this suite) makes checkpoint_index start at 2 instead of 1 on the next run,
# a false FAIL against unchanged code.
sweep_ddstate_(){
  rm -f "${TMPDIR:-/tmp}"/vstack-mandate-ckpt-ddproof[0-9]* 2>/dev/null
  rm -f "${TMPDIR:-/tmp}"/vstack-mandate-ddproof[0-9]* 2>/dev/null
  rm -rf "${TMPDIR:-/tmp}"/vstack-mandate-ddproof[0-9]*.lock 2>/dev/null
}
sweep_ddstate_
trap 'sweep_ddstate_; rm -rf "$WORK"' EXIT

# --- PROOF 1: the hook writes one well-formed schema line per evaluated Stop -------------------
# A fixture with 3 dirs / 2 extensions / zero Task calls is breadth-eligible and unmet -- the
# hook blocks -- but Part 1's contract is "log unconditionally, block conditionally", so this
# proof's subject is the LOG LINE, not the block. VSTACK_DELEGATION_LOG points the write at a
# throwaway file so this never touches the real ~/.claude/vstack-delegation-log.jsonl.
log1="$WORK/log1.jsonl"
fixture1="$WORK/t1.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"a/x.sh","content":""}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"b/y.md","content":""}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"c/z.sh","content":""}}]}}' > "$fixture1"
printf '{"transcript_path":"%s","session_id":"ddproof1","stop_hook_active":false}' "$fixture1" \
  | VSTACK_DELEGATION_LOG="$log1" bash "$HOOK" >/dev/null 2>&1

line1=$(cat "$log1" 2>/dev/null)
sid1=$(printf '%s' "$line1" | jq -r '.session_id // empty' 2>/dev/null)
dc1=$(printf '%s' "$line1" | jq -r '.dir_count // empty' 2>/dev/null)
ec1=$(printf '%s' "$line1" | jq -r '.ext_count // empty' 2>/dev/null)
tc1=$(printf '%s' "$line1" | jq -r '.task_count // empty' 2>/dev/null)
ck1=$(printf '%s' "$line1" | jq -r '.checkpoint_index // empty' 2>/dev/null)
# NOT `.named // empty` -- jq's `//` treats a real JSON `false` as absent, same as null, and
# would silently read a correctly-logged `false` as empty here. `.named` alone is safe because
# the field is always present in what the hook writes.
named1=$(printf '%s' "$line1" | jq -r '.named' 2>/dev/null)
if [ "$sid1" = "ddproof1" ] && [ "$dc1" = "3" ] && [ "$ec1" = "2" ] && [ "$tc1" = "0" ] \
   && [ "$ck1" = "1" ] && [ "$named1" = "false" ]; then
  ok "PROOF 1: hook writes one well-formed schema line to \$VSTACK_DELEGATION_LOG on an evaluated Stop"
else
  bad "PROOF 1: hook writes one well-formed schema line to \$VSTACK_DELEGATION_LOG on an evaluated Stop" \
      "got line: [$line1]"
fi

# --- PROOF 2: checkpoint_index advances across repeated Stops in the same session ---------------
printf '{"transcript_path":"%s","session_id":"ddproof1","stop_hook_active":false}' "$fixture1" \
  | VSTACK_DELEGATION_LOG="$log1" bash "$HOOK" >/dev/null 2>&1
ck2=$(tail -n 1 "$log1" 2>/dev/null | jq -r '.checkpoint_index // empty' 2>/dev/null)
if [ "$ck2" = "2" ]; then
  ok "PROOF 2: checkpoint_index advances (1 then 2) across repeated Stops in the same session"
else
  bad "PROOF 2: checkpoint_index advances (1 then 2) across repeated Stops in the same session" \
      "expected second line's checkpoint_index=2, got: $ck2"
fi

# --- PROOF 3: VSTACK_NO_DELEGATION_LOG=1 suppresses the write entirely --------------------------
log3="$WORK/log3.jsonl"
printf '{"transcript_path":"%s","session_id":"ddproof3","stop_hook_active":false}' "$fixture1" \
  | VSTACK_DELEGATION_LOG="$log3" VSTACK_NO_DELEGATION_LOG=1 bash "$HOOK" >/dev/null 2>&1
if [ ! -s "$log3" ]; then
  ok "PROOF 3: VSTACK_NO_DELEGATION_LOG=1 suppresses the write entirely"
else
  bad "PROOF 3: VSTACK_NO_DELEGATION_LOG=1 suppresses the write entirely" \
      "expected no file or an empty one, got: $(cat "$log3" 2>/dev/null)"
fi

# --- PROOF 4: a met mandate (single dir, zero breadth) still logs -------------------------------
# The unconditional half of "log unconditionally, block conditionally": this fixture trips no
# mandate at all (1 dir, 1 extension) and the hook's stdout must be empty, but the log line must
# still appear -- a log that only captured blocks would measure the gate, not the behaviour.
log4="$WORK/log4.jsonl"
fixture4="$WORK/t4.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"a/x.sh","content":""}}]}}' > "$fixture4"
hook_out4=$(printf '{"transcript_path":"%s","session_id":"ddproof4","stop_hook_active":false}' "$fixture4" \
  | VSTACK_DELEGATION_LOG="$log4" bash "$HOOK" 2>/dev/null)
dc4=$(cat "$log4" 2>/dev/null | jq -r '.dir_count // empty' 2>/dev/null)
if [ -z "$hook_out4" ] && [ "$dc4" = "1" ]; then
  ok "PROOF 4: a Stop with no unmet mandate (silent stdout) still writes a log line"
else
  bad "PROOF 4: a Stop with no unmet mandate (silent stdout) still writes a log line" \
      "expected empty hook stdout and dir_count=1, got stdout=[$hook_out4] dir_count=[$dc4]"
fi

# --- PROOF 5: rotation engages once the log crosses the ~2MB cap, keeping the newest lines -------
log5="$WORK/log5.jsonl"
python3 -c "
import sys
line = '{\"session_id\":\"pad\",\"checkpoint_index\":1,\"dir_count\":0,\"ext_count\":0,\"task_count\":0,\"named\":false,\"ts\":\"pad\"}\n'
target = 2200000
with open(sys.argv[1], 'w') as fh:
    written = 0
    while written < target:
        fh.write(line)
        written += len(line)
" "$log5"
sz_before=$(stat -f%z "$log5" 2>/dev/null || stat -c%s "$log5" 2>/dev/null)
printf '{"transcript_path":"%s","session_id":"ddproof5","stop_hook_active":false}' "$fixture4" \
  | VSTACK_DELEGATION_LOG="$log5" bash "$HOOK" >/dev/null 2>&1
lines_after=$(wc -l < "$log5" | tr -d ' ')
last5=$(tail -n 1 "$log5" 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
if [ "$sz_before" -gt 2097152 ] && [ "$lines_after" -le 5000 ] && [ "$last5" = "ddproof5" ]; then
  ok "PROOF 5: rotation engages past the ~2MB cap, truncates to <=5000 lines, keeps the newest write"
else
  bad "PROOF 5: rotation engages past the ~2MB cap, truncates to <=5000 lines, keeps the newest write" \
      "size_before=$sz_before lines_after=$lines_after last_session=[$last5]"
fi

# --- PROOF 6: the analyser reads a forward log correctly end-to-end -----------------------------
# 5 synthetic sessions, each with 3 checkpoints (positions 0, 0.5, 1). Session s1-s5: eligible
# and delegated (task_count>=1) at position 0; eligible and NOT delegated at position 1. That is
# 5 eligible-and-hit windows in the first tertile and 5 eligible-and-miss windows in the last --
# first-third rate 1.0, last-third rate 0.0, comfortably past both floors at MIN_ELIGIBLE_PER_TERTILE=5.
log6="$WORK/log6.jsonl"
: > "$log6"
for i in 1 2 3 4 5; do
  printf '{"session_id":"s%s","checkpoint_index":1,"dir_count":3,"ext_count":2,"task_count":1,"named":true,"ts":"t"}\n' "$i" >> "$log6"
  printf '{"session_id":"s%s","checkpoint_index":2,"dir_count":1,"ext_count":1,"task_count":1,"named":true,"ts":"t"}\n' "$i" >> "$log6"
  printf '{"session_id":"s%s","checkpoint_index":3,"dir_count":3,"ext_count":2,"task_count":0,"named":false,"ts":"t"}\n' "$i" >> "$log6"
done
empty_candidates="$WORK/empty-candidates.txt"
: > "$empty_candidates"
out6=$(MIN_ELIGIBLE_PER_TERTILE=5 MIN_CONTRIBUTING_SESSIONS=5 python3 "$PY" "$log6" "$empty_candidates")
if printf '%s' "$out6" | grep -qF 'first-third: 5/5 = 1.000' \
   && printf '%s' "$out6" | grep -qF 'last-third : 0/5 = 0.000' \
   && printf '%s' "$out6" | grep -qF 'SIGNAL (decay)'; then
  ok "PROOF 6: analyser reads a forward log and computes first/last tertile rates correctly (SIGNAL case)"
else
  bad "PROOF 6: analyser reads a forward log and computes first/last tertile rates correctly (SIGNAL case)" \
      "$out6"
fi

# --- PROOF 7: "keeps working" verdict when the rate does not meaningfully move ------------------
log7="$WORK/log7.jsonl"
: > "$log7"
for i in 1 2 3 4 5; do
  printf '{"session_id":"k%s","checkpoint_index":1,"dir_count":3,"ext_count":2,"task_count":1,"named":true,"ts":"t"}\n' "$i" >> "$log7"
  printf '{"session_id":"k%s","checkpoint_index":2,"dir_count":1,"ext_count":1,"task_count":1,"named":true,"ts":"t"}\n' "$i" >> "$log7"
  printf '{"session_id":"k%s","checkpoint_index":3,"dir_count":3,"ext_count":2,"task_count":1,"named":true,"ts":"t"}\n' "$i" >> "$log7"
done
out7=$(MIN_ELIGIBLE_PER_TERTILE=5 MIN_CONTRIBUTING_SESSIONS=5 python3 "$PY" "$log7" "$empty_candidates")
if printf '%s' "$out7" | grep -qF 'KEEPS WORKING'; then
  ok "PROOF 7: analyser reports KEEPS WORKING when first- and last-third rates both equal 1.0"
else
  bad "PROOF 7: analyser reports KEEPS WORKING when first- and last-third rates both equal 1.0" "$out7"
fi

# --- PROOF 8: below-floor data reports NOT EVALUATED, never a rate ------------------------------
log8="$WORK/log8.jsonl"
printf '{"session_id":"one","checkpoint_index":1,"dir_count":3,"ext_count":2,"task_count":1,"named":true,"ts":"t"}\n' > "$log8"
printf '{"session_id":"one","checkpoint_index":2,"dir_count":3,"ext_count":2,"task_count":0,"named":false,"ts":"t"}\n' >> "$log8"
out8=$(python3 "$PY" "$log8" "$empty_candidates")
if printf '%s' "$out8" | grep -qF 'NOT EVALUATED'; then
  ok "PROOF 8: below the eligible-window / contributing-session floors -> NOT EVALUATED, not a rate"
else
  bad "PROOF 8: below the eligible-window / contributing-session floors -> NOT EVALUATED, not a rate" "$out8"
fi

# --- PROOF 9: zero sessions from either source -> INCONCLUSIVE, non-zero exit -------------------
missing_log="$WORK/does-not-exist.jsonl"
python3 "$PY" "$missing_log" "$empty_candidates" > "$WORK/out9.txt" 2>&1
rc9=$?
if [ "$rc9" -ne 0 ] && grep -qF 'INCONCLUSIVE' "$WORK/out9.txt"; then
  ok "PROOF 9: zero sessions from either source -> INCONCLUSIVE and a non-zero exit code"
else
  bad "PROOF 9: zero sessions from either source -> INCONCLUSIVE and a non-zero exit code" \
      "rc=$rc9 output=$(cat "$WORK/out9.txt")"
fi

# --- PROOF 10: identical outcome vectors across sessions -> INVALID, not a false SIGNAL ----------
# Every checkpoint in every session reporting the exact same tuple is what a broken extractor
# looks like (e.g. every file_path read as empty, so dir_count/ext_count never move), not
# evidence that delegation behaviour is perfectly stable. Must not be read as KEEPS WORKING.
log10="$WORK/log10.jsonl"
: > "$log10"
for i in 1 2 3; do
  printf '{"session_id":"b%s","checkpoint_index":1,"dir_count":0,"ext_count":0,"task_count":0,"named":false,"ts":"t"}\n' "$i" >> "$log10"
  printf '{"session_id":"b%s","checkpoint_index":2,"dir_count":0,"ext_count":0,"task_count":0,"named":false,"ts":"t"}\n' "$i" >> "$log10"
done
out10=$(python3 "$PY" "$log10" "$empty_candidates")
rc10=$?
if [ "$rc10" -ne 0 ] && printf '%s' "$out10" | grep -qF 'INVALID'; then
  ok "PROOF 10: identical per-session outcome vectors -> INVALID (extraction broken, not invariance), non-zero exit"
else
  bad "PROOF 10: identical per-session outcome vectors -> INVALID (extraction broken, not invariance), non-zero exit" \
      "rc=$rc10 output=$out10"
fi

# --- PROOF 11: the replay path recomputes the same schema from a raw transcript, post-cutoff ----
# A synthetic transcript shaped like a real ~/.claude/projects/*.jsonl file: one real user turn,
# an assistant turn touching 3 dirs / 2 extensions with zero Task/Agent calls, then a second real
# user turn to close the checkpoint. mtime is set to now, which postdates CUTOFF_COMMIT_ISO.
replay_dir="$WORK/replay"
mkdir -p "$replay_dir"
replay_transcript="$replay_dir/ddproof11.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"start"}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"a/x.sh","content":""}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"b/y.md","content":""}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"c/z.sh","content":""}}]}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"next"}}'
} > "$replay_transcript"
replay_candidates="$WORK/replay-candidates.txt"
printf '%s\n' "$replay_transcript" > "$replay_candidates"
out11=$(CUTOFF_COMMIT_ISO="2000-01-01T00:00:00+00:00" python3 "$PY" "$missing_log" "$replay_candidates")
if printf '%s' "$out11" | grep -qF 'distinct sessions in replay: 1'; then
  ok "PROOF 11: replay recomputes dir_count/ext_count/task_count from a raw post-cutoff transcript"
else
  bad "PROOF 11: replay recomputes dir_count/ext_count/task_count from a raw post-cutoff transcript" "$out11"
fi

# --- PROOF 12: replay excludes a transcript older than the cutoff -------------------------------
touch -t 200001010000 "$replay_transcript" 2>/dev/null || touch -d '2000-01-01' "$replay_transcript" 2>/dev/null
out12=$(python3 "$PY" "$missing_log" "$replay_candidates")
if printf '%s' "$out12" | grep -qF 'distinct sessions in replay: 0'; then
  ok "PROOF 12: replay excludes a transcript whose mtime predates CUTOFF_COMMIT_ISO"
else
  bad "PROOF 12: replay excludes a transcript whose mtime predates CUTOFF_COMMIT_ISO" "$out12"
fi

printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
[ "$((RAN + SKIPPED))" -eq "$TOTAL" ] || { printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"; FAIL=1; }
if [ "$FAIL" -ne 0 ]; then
  echo "VERIFICATION FAILED"
  exit 1
fi
echo VERIFIED

echo
echo "=== live run against this machine's real data ==="
FORWARD_LOG_PATH="${VSTACK_DELEGATION_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-delegation-log.jsonl}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/.claude/projects}"

if [ ! -d "$PROJECTS_DIR" ]; then
  echo "note: $PROJECTS_DIR does not exist -- replay pass will find zero candidates."
fi

LIVE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/delegation-drift-live.XXXXXX")
trap 'sweep_ddstate_; rm -rf "$WORK" "$LIVE_TMP"' EXIT
LIVE_CANDIDATES="$LIVE_TMP/candidates.txt"
find "$PROJECTS_DIR" -type f -name '*.jsonl' > "$LIVE_CANDIDATES" 2>/dev/null

python3 "$PY" "$FORWARD_LOG_PATH" "$LIVE_CANDIDATES"
exit $?
