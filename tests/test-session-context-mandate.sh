#!/usr/bin/env bash
# test-session-context-mandate.sh — the hand-runnable reproduction of the MANDATE escalation
# in claude/hooks/inject-session-context.sh's UserPromptSubmit digest. The hook's current code
# (lines ~155-168) reads $TMPDIR/vstack-mandate-$sid and $TMPDIR/vstack-mandate-$sid.delegate
# — files skill-mandate.sh never writes. skill-mandate.sh writes per-mandate suffixes only:
# .unslop .typescript .proveitworks .delegate-breadth .delegate-naming .delegate-swarm
# .delegate-serial. So the escalation line was dead code in production; these tests were written
# RED against that defect and go green once the hook reads the max of each family's real
# per-mandate counter files (CASE 1/2/3 below).
#
# Real-transcript evidence: the MANDATE line never rendered in any real session because the
# counters read from non-existent files always stayed 0.
#
# Hook contract, current shape: the digest is $grill$mandate, TWO independent conditional lines
# and nothing unconditional. TOKENS/DELEGATE/FANOUT lines that used to render on every prompt are
# gone -- unmeasured cost paid on every turn of every session (see
# inject-session-context.sh:182-188). GRILL fires on a long prompt (>= VSTACK_GRILL_CHARS, 320)
# or a session's first prompt (>= 120 chars); MANDATE fires on a seeded skill-mandate.sh counter
# file. Neither firing means an empty digest: a JSON line with no additionalContext key at all
# (CASE 5), not an empty string. On UserPromptSubmit the hook emits a JSON object whose
# .hookSpecificOutput.additionalContext, when present, carries this digest and must stay under
# 512 bytes total (the grill worst-case in .claude/verify.sh's check 18 budget, CASE 6). The
# tests below parse additionalContext via jq and grep it for expected lines, except CASE 5 which
# greps the hook's raw stdout to tell "empty string" apart from "key absent".
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/claude/hooks/inject-session-context.sh"
SELF="$repo_root/tests/test-session-context-mandate.sh"

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(grep -c '^# --- CASE [0-9]' "$SELF")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

if ! command -v jq >/dev/null 2>&1; then
  skip "CASE 1: seeded delegate-family counter renders the MANDATE line" "jq not installed"
  skip "CASE 2: seeded skill-family counter renders the MANDATE line" "jq not installed"
  skip "CASE 3: no counter files -> MANDATE line absent" "jq not installed"
  skip "CASE 4: digest pins the fan-out rule every prompt" "jq not installed"
  skip "CASE 5: unconditional digest stays under 512-byte budget" "jq not installed"
  skip "CASE 6: worst case (grill + both families at cap) stays under budget" "jq not installed"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  [ "$((RAN + SKIPPED))" -eq "$TOTAL" ] || { printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"; FAIL=1; }
  [ "$FAIL" -eq 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
  exit "$FAIL"
fi

if [ ! -x "$hook" ]; then
  bad "session-context-mandate proofs" "$hook is missing or not executable"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vstack-ctx-mandate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Invocation helper: runs the hook with a UserPromptSubmit event, reads the digest context.
# The hook reads counter files under ${TMPDIR:-/tmp}, so we set TMPDIR="$WORK" for isolation.
# Takes two invocations in some cases: the hook is stateless apart from the grill first-seen
# marker, which the SECOND call sees as already-marked. Call order therefore matters only for
# grill cases.
run_ctx_(){  # <session_id> <prompt>
  _payload=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":"%s"}' "$1" "$2")
  printf '%s' "$_payload" | TMPDIR="$WORK" bash "$hook" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

run_ctx_bytes_(){  # <session_id> <prompt> — return byte count of raw stdout
  _payload=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":"%s"}' "$1" "$2")
  printf '%s' "$_payload" | TMPDIR="$WORK" bash "$hook" 2>/dev/null | wc -c | tr -d ' '
}

# --- CASE 1: seeded delegate-family counter renders the MANDATE line -------------------------
# Dead-code defect: the hook reads vstack-mandate-scm1.delegate (non-existent) instead of the
# real per-mandate files like vstack-mandate-scm1.delegate-breadth that skill-mandate.sh writes.
# When fixed to read the max of real counter files, a seeded delegate-breadth file must render
# the MANDATE line showing the escalation counters. Direction: positive, guard against silent
# zero-read on wrong filenames.
printf '2\n' > "$WORK/vstack-mandate-scm1.delegate-naming"
CTX=$(run_ctx_ scm1 "hi")
if printf '%s' "$CTX" | grep -qF 'MANDATE skill=0/2 delegate=2/2'; then
  ok "CASE 1: seeded delegate-family counter renders the MANDATE line"
else
  bad "CASE 1: seeded delegate-family counter renders the MANDATE line" \
      "expected CTX to contain 'MANDATE skill=0/2 delegate=2/2', got: [$CTX]"
fi

# --- CASE 2: seeded skill-family counter renders the MANDATE line ----------------------------
# Same dead-code defect: the hook reads vstack-mandate-scm2 (non-existent generic file) instead
# of real per-mandate skill counters (.unslop, .typescript, .proveitworks). When fixed, a seeded
# skill-family counter must render the MANDATE line showing the escalation counters. Direction:
# positive, guard against silent zero-read on wrong filenames.
printf '1\n' > "$WORK/vstack-mandate-scm2.unslop"
CTX=$(run_ctx_ scm2 "hi")
if printf '%s' "$CTX" | grep -qF 'MANDATE skill=1/2 delegate=0/2'; then
  ok "CASE 2: seeded skill-family counter renders the MANDATE line"
else
  bad "CASE 2: seeded skill-family counter renders the MANDATE line" \
      "expected CTX to contain 'MANDATE skill=1/2 delegate=0/2', got: [$CTX]"
fi

# --- CASE 3: no counter files -> MANDATE line absent ----------------------------------------
# Negative direction: the common case in most sessions. No counter files seeded, so both
# families read as 0/0. The digest must stay silent (MANDATE line absent) — most prompts in most
# sessions never tripped either mandate, and the byte budget (check 18) is a hard cap on every
# prompt, so a line that always rendered would blow the budget for the common case.
CTX=$(run_ctx_ scm3 "hi")
if ! printf '%s' "$CTX" | grep -qF MANDATE; then
  ok "CASE 3: no counter files -> MANDATE line absent"
else
  bad "CASE 3: no counter files -> MANDATE line absent" \
      "expected CTX to NOT contain MANDATE, got: [$CTX]"
fi

# --- CASE 4: the two conditional lines each fire under their own trigger, together -----------
# Post-fix shape: TOKENS/DELEGATE/FANOUT are gone. The digest is $grill$mandate -- two
# independent conditional lines, GRILL (a prompt >= VSTACK_GRILL_CHARS, 320, or a session's first
# prompt >= 120 chars) and MANDATE (a seeded skill-mandate.sh counter file). CASE 1/2 already
# prove MANDATE fires alone on a short prompt; this proves BOTH fire together when both
# conditions hold at once, which is the realistic worst case a real long-planning prompt with an
# outstanding mandate strike actually hits. Direction: positive, guard both triggers and their
# co-occurrence.
printf '1\n' > "$WORK/vstack-mandate-scm4.unslop"
_p4=""
_i4=0
while [ $_i4 -lt 400 ]; do
  _p4="${_p4}x"
  _i4=$((_i4+1))
done
CTX=$(run_ctx_ scm4 "$_p4")
has_grill=$(printf '%s' "$CTX" | grep -qF 'GRILL: run the grill-me skill' && echo 1 || echo 0)
has_mandate=$(printf '%s' "$CTX" | grep -qF 'MANDATE skill=1/2 delegate=0/2' && echo 1 || echo 0)
if [ "$has_grill" = 1 ] && [ "$has_mandate" = 1 ]; then
  ok "CASE 4: the two conditional lines each fire under their own trigger, together"
else
  bad "CASE 4: the two conditional lines each fire under their own trigger, together" \
      "expected GRILL (got $has_grill) and MANDATE skill=1/2 delegate=0/2 (got $has_mandate) in digest: [$CTX]"
fi

# --- CASE 5: digest is empty (no additionalContext) when neither condition holds --------------
# Boundary test, the opposite of CASE 4: TOKENS/DELEGATE/FANOUT used to render unconditionally on
# every prompt; now the digest is $grill$mandate and legitimately renders nothing when neither
# fires. A short prompt on a fresh session with no counter files must produce a JSON line with NO
# additionalContext key at all -- not an empty string, the key itself absent -- so this is
# checked on the raw hook stdout, not through run_ctx_'s jq extraction (which would report "" for
# either shape and could not tell them apart). Direction: negative, the steady state most prompts
# in most sessions actually hit, and the one check 18 in .claude/verify.sh relies on to floor its
# fired-digest probe as the FIRED case rather than the default.
RAW_5=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"scm5","prompt":"hi"}' \
        | TMPDIR="$WORK" bash "$hook" 2>/dev/null)
if printf '%s' "$RAW_5" | grep -qF 'additionalContext'; then
  bad "CASE 5: digest is empty (no additionalContext) when neither condition holds" \
      "expected no additionalContext key in stdout, got: [$RAW_5]"
elif ! printf '%s' "$RAW_5" | grep -qF '"hookEventName":"UserPromptSubmit"'; then
  bad "CASE 5: digest is empty (no additionalContext) when neither condition holds" \
      "hook produced no valid UserPromptSubmit output at all -- silence cannot be told apart from a crash: [$RAW_5]"
else
  ok "CASE 5: digest is empty (no additionalContext) when neither condition holds"
fi

# --- CASE 6: worst case (grill + both MANDATE families at cap) stays under 512 ----------------
# Boundary test, the worst case: grill fires + both mandate families at 2/2 (the cap). The hook
# must stay under 512 bytes even with all three pieces armed. Seed both families at max
# (2 counters each), build a 400-char prompt to arm the grill (>= 320 chars), measure the FIRST
# invocation's raw byte count (to catch the grill armed, not cached). Also assert the output
# contains 'GRILL: run the grill-me skill' to prove grill actually fired (worst case is real).
# Direction: positive boundary, guard against budget overflow under worst-case load.
# NOTE: measure bytes on FIRST invocation when grill fires; grill marker is cached so second
# call would see it as already-marked. Fresh session id, one invocation only.
printf '2\n' > "$WORK/vstack-mandate-scm6.delegate-naming"
printf '2\n' > "$WORK/vstack-mandate-scm6.unslop"
_p=""
_i=0
while [ $_i -lt 400 ]; do
  _p="${_p}x"
  _i=$((_i+1))
done
_payload_6=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"scm6","prompt":"%s"}' "$_p")
_out_6=$(printf '%s' "$_payload_6" | TMPDIR="$WORK" bash "$hook" 2>/dev/null)
_bytes_out=$(printf '%s' "$_out_6" | wc -c | tr -d ' ')
_ctx=$(printf '%s' "$_out_6" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
has_grill=$(printf '%s' "$_ctx" | grep -qF 'GRILL: run the grill-me skill' && echo 1 || echo 0)
if [ "$_bytes_out" -le 512 ] && [ "$has_grill" = 1 ]; then
  ok "CASE 6: worst case (grill + both MANDATE families at cap) stays under budget"
else
  bad "CASE 6: worst case (grill + both MANDATE families at cap) stays under budget" \
      "expected bytes <= 512 (got $_bytes_out) and GRILL present (got $has_grill)"
fi

echo
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"
  FAIL=1
fi
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ]
exit $?
