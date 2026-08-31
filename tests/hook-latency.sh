#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154  # REFERENCE_MEAN_*/REFERENCE_P95_*/BUDGET_UNITS_MEAN_*/
# BUDGET_UNITS_P95_* (the tables below) and their readers (rmean/rp95/bumean/bup95) are
# connected by `eval "x=\$PREFIX_$varname"`, one variable per hook rather than an associative
# array -- bash 3.2 on macOS (this repo's own floor) has no `declare -A`. shellcheck cannot trace
# an indirect reference through eval, so all four warn on every table line and on every read; a
# true positive from either would be a hook whose name does not survive `tr '-' '_'` unchanged,
# which none of the eight do.
# hook-latency.sh — latency regression test for claude/hooks/*.sh, with a verdict independent of
# how busy the machine running it happens to be.
#
# claude/hooks/dispatch-counter.sh:151-158 documents a "~25ms p95 budget this hook is held to"
# and a real regression against it (72.8ms mean / 74.9ms p95, n=30, fixed by folding three jq
# calls into one). Nothing in tests/ ever timed a hook -- `git grep -n "25ms"` before this file
# existed matched only that prose. A budget nothing measures is not a budget, it is a comment.
#
# WHY THIS DOES NOT BUDGET IN MILLISECONDS. The first version of this file did, and it measured
# its own defect while proving it: `skill-mandate.sh` moved from 171ms mean to 858ms mean between
# two runs with zero code change in between, because seven concurrent `gate-falsifiability.sh`
# shards were contending for the same CPU on the same machine. .claude/verify.sh's own founding
# subject is a check that is correct about the question it actually asked -- and "does this hook
# finish in under N absolute milliseconds" is a question scoped to the machine, moment and
# concurrent load it ran under, not to the hook. A red verdict from that question teaches whoever
# sees it to ignore the suite, which is worse than not having it.
#
# So every budget below is expressed in FORK-COST UNITS, not milliseconds: how many multiples of
# "one small process fork+exec" (`jq -nr now`, timed the identical way every hook is) a hook cost,
# at the same moment its own sample was taken. The floor these hooks share is fork+exec overhead
# -- every one of them forks jq 1-3 times plus some mix of stat/grep/sed/mkdir/cat -- and that
# floor moves with machine load exactly as much as the hook itself does, so dividing one by the
# other cancels the load term that made the ms version noisy. The baseline is measured INTERLEAVED
# with every single hook sample (immediately before it, not once up front), specifically so a load
# spike mid-run raises both numbers together instead of only the numerator.
#
# Raw milliseconds are still measured and reported (Table A below) -- a reader needs to see the
# machine, not just the verdict -- but they no longer gate pass/fail. The old ms budgets are kept
# as REFERENCE_* constants purely to show, per hook, whether the normalized verdict and the old
# ms-budget verdict agree; where they disagree, this script says so and says why, because that
# disagreement is the actual evidence the normalization is doing something (see the run report
# this file's commit/handback carries for a worked example: under a loaded machine, several hooks
# that fail their old ms budget pass comfortably in fork-cost units).
#
# THIS FILE MUST NOT BE A FAKE GREEN. Every failure mode below is a hard FAIL naming the reason,
# never a silent pass and never a skip that lets the accounting line paper over it:
#   - a hook cannot be executed (missing / not executable)
#   - a hook exits nonzero
#   - a hook's stdout does not carry the success signal that specific payload is supposed to
#     produce (proof the hook did its real work on the input, not that it bailed out early and
#     happened to be fast because of it)
#   - the baseline fork-cost unit cannot be measured for a sample (jq itself fails, or returns a
#     non-positive duration) -- that sample is discarded rather than divided by zero or by garbage
#   - zero valid (baseline + hook) sample pairs were collected for a declared hook
# The accounting line at the end matches .claude/verify.sh's own ending ("checks: N declared, N
# ran, N skipped") and tests/gate-falsifiability.sh's ("N declared, N passed, N failed, N
# skipped"): `ran + skipped` must equal `declared`, or the run itself failed, not just a hook.
#
# THE TIMER IS PROVEN BEFORE IT IS TRUSTED, and that is a different claim from the baseline being
# calibrated. A positive control times `sleep 0.2` with the exact function every hook and every
# baseline sample is timed with, before any measurement below is trusted -- a timer that reports
# 0ms for everything would otherwise pass every budget forever, in ms OR in fork-cost units (a
# broken timer divides 0 by 0 just as readily as it reports 0ms). The baseline itself is the
# second, separate claim: that the unit budgets below are calibrated against a real fork+exec
# cost, not an arbitrary constant. Both are checked; neither substitutes for the other.
#
# `date +%s%N` is the usual portable-looking timer and is exactly the trap: it is a GNU-date-ism,
# and BSD/macOS date's behaviour with %N is not a constant to build a portable script on. jq's
# `now` builtin is used instead -- see the timer section below for what was actually verified on
# this machine.
#
# Every hook is fed the real stdin JSON shape it reads (per that hook's own header/body, not a
# guess), and every sample asserts the hook's documented success signal in addition to timing it
# -- a hook that bails early on malformed input is fast for the wrong reason, and this would
# otherwise reward exactly that.
#
# Isolation: this repo is worked on by several concurrent agent sessions sharing /tmp and $HOME
# (tests/README.md, "this checkout may not be yours alone" -- not hypothetical: this file's
# budgets were calibrated while seven concurrent tests/gate-falsifiability.sh shards were running
# on this same machine, deliberately not waited out). The hooks under test write to
# ${TMPDIR:-/tmp}/vstack-*, ~/.claude/vstack-replay-log.jsonl and
# ~/.claude/vstack-compat-canary.json unless redirected, so this script exports its own TMPDIR
# and points every hook-specific override (VSTACK_REPLAY_LOG, VSTACK_COMPAT_CANARY_LOG,
# VSTACK_NO_DELEGATION_LOG, CLAUDE_PROJECT_DIR) at a private mktemp -d for the whole run. Nothing
# here touches a real counter, log or trust store on this machine.
#
# Offline, no model calls, no network. n=30 per hook (8 hooks, ~240 hook invocations plus ~240
# interleaved baseline forks) completes in well under 60s on this machine even under the loaded
# conditions above -- see the timing report printed at the end.
set -uo pipefail

# --- prerequisites: loud, not silent ------------------------------------------------------------
fail_hard() { # <reason> -- a condition that makes every number this run would produce meaningless
  printf 'FATAL: %s\n' "$1" >&2
  exit 1
}

command -v jq   >/dev/null 2>&1 || fail_hard "jq is required (it is the timer's clock source, the baseline fork-cost unit, and how every hook payload/output below is built and read) and is not on PATH"
command -v awk  >/dev/null 2>&1 || fail_hard "awk is required for the timer's float subtraction and for computing mean/p95 and is not on PATH"
command -v bash >/dev/null 2>&1 || fail_hard "bash is required to invoke the hooks under test"

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || fail_hard "could not resolve repo root from \$0"
HOOKS_DIR="$ROOT/claude/hooks"
[ -d "$HOOKS_DIR" ] || fail_hard "$HOOKS_DIR does not exist"

N="${HOOK_LATENCY_SAMPLES:-30}"
case "$N" in ''|*[!0-9]*|0) fail_hard "HOOK_LATENCY_SAMPLES must be a positive integer, got '$N'" ;; esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hook-latency.XXXXXX") || fail_hard "mktemp -d failed"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

# Every hook invocation below runs under this TMPDIR, not the real one -- see the isolation
# paragraph above.
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

# --- the timer -----------------------------------------------------------------------------------
# jq's `now` builtin returns epoch seconds as a float (gettimeofday()-class wall clock,
# microsecond-order resolution) -- the same primitive `date +%s.%N`/bash's EPOCHREALTIME give on
# Linux, without needing GNU date (`date +%s%N` is a GNU-date-ism this script does not lean on;
# BSD/macOS date's %N support is not something to build a portable script around) or bash>=4
# (EPOCHREALTIME is a bash-4+ builtin; macOS ships bash 3.2.57, confirmed: `bash --version` on
# this machine reports 3.2.57(1)-release). jq is already a hard dependency of every hook this
# script drives -- each one resolves /usr/bin/jq or PATH jq before doing anything and is
# deliberately silent-by-design without it -- so requiring it here is not a new dependency.
#
# Verified on this machine (Darwin 25.4.0, jq-1.7.1-apple, awk 20200816 /usr/bin/awk): `t0=$(jq -nr
# now); sleep 0.2; t1=$(jq -nr now)` through the exact elapsed_ms() function below measured
# 211-237ms across several checks for a 200ms sleep. The positive control just below re-proves
# this on every run rather than trusting those manual checks to still hold.
_now() { jq -nr 'now'; }
elapsed_ms() { # <t0> <t1> -> milliseconds, 3 decimal places
  awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", (b-a)*1000}'
}
ms_ge() { awk -v m="$1" -v f="$2" 'BEGIN{print (m>=f)?1:0}'; }   # 1 if $1 >= $2
ms_le() { awk -v m="$1" -v c="$2" 'BEGIN{print (m<=c)?1:0}'; }   # 1 if $1 <= $2

# mean and nearest-rank p95 of a space-separated list of decimal numbers, via awk (no `sort -V`
# -- these are plain decimals, not dotted version strings, and this needs numeric order only).
# Same nearest-rank definition dispatch-counter.sh's own header comment uses for its own p95.
stats_of() { # <space-separated numbers> -> "mean p95" on stdout, or "" if the list is empty
  printf '%s\n' "$1" | awk '
    { for (i=1;i<=NF;i++) { n++; a[n]=$i; sum+=$i } }
    END {
      if (n==0) { print ""; exit }
      for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) if (a[j]<a[i]) { t=a[i]; a[i]=a[j]; a[j]=t }
      mean = sum/n
      p95_idx = int((0.95*n) + 0.9999999)
      if (p95_idx < 1) p95_idx = 1
      if (p95_idx > n) p95_idx = n
      printf "%.3f %.3f", mean, a[p95_idx]
    }'
}

# --- positive control: prove the timer before trusting it on anything else ----------------------
# This proves the CLOCK runs. It says nothing about whether the fork-cost baseline below is
# calibrated -- that is a separate claim, checked separately, right after this.
ctrl_t0=$(_now)
sleep 0.2
ctrl_t1=$(_now)
ctrl_ms=$(elapsed_ms "$ctrl_t0" "$ctrl_t1")
# Floor at 195ms (5ms under the 200ms sleep, absorbing the timer's own read overhead) rather than
# exactly 200: sleep is a guaranteed minimum, never a ceiling, so the only way this reads low is a
# broken timer. Ceiling at 2000ms catches a timer reading garbage the other way (e.g. two calls
# returning the same frozen value would show 0ms, not a giant number, which is why the floor is
# the check that actually matters -- the ceiling is a sanity backstop, generous even under load).
if [ "$(ms_ge "$ctrl_ms" 195)" != 1 ] || [ "$(ms_le "$ctrl_ms" 2000)" != 1 ]; then
  fail_hard "positive control failed: timed 'sleep 0.2' at ${ctrl_ms}ms via jq-now/awk, expected 195-2000ms -- the timer cannot be trusted, so no measurement below means anything"
fi
printf 'positive control: sleep 0.2 measured %sms (timer verified)\n' "$ctrl_ms"

# --- the baseline fork-cost unit ------------------------------------------------------------------
# One unit = the time to fork+exec `jq -nr now` and get an answer back -- literally the same
# command the timer itself uses to take a reading, chosen for that reason: whatever this machine's
# jq startup cost is doing to the timer's own two reads around a hook, it is doing the identical
# thing here, so the ratio below is hook-cost-relative-to-one-of-its-own-timer-ticks, not relative
# to some unrelated reference command.
#
# Measured INSIDE the per-hook sampling loop below, immediately adjacent to that sample's hook
# invocation -- never once up front -- so a load spike mid-run moves the baseline and the hook
# sample together. A baseline measured once at the top of this script would be exactly the
# absolute-ms mistake this file exists to not repeat, just moved one line earlier.
baseline_sample() { # -> prints milliseconds on stdout, or nothing + returns 1 on failure
  local bt0 bt1 bms
  bt0=$(_now)
  jq -nr 'now' >/dev/null 2>&1
  if [ $? -ne 0 ]; then return 1; fi
  bt1=$(_now)
  bms=$(elapsed_ms "$bt0" "$bt1")
  # A non-positive reading is not a valid unit to divide by -- report failure rather than let a
  # hook's ratio come back as a divide-by-zero or a negative number.
  [ "$(awk -v v="$bms" 'BEGIN{print (v>0.001)?1:0}')" = 1 ] || return 1
  printf '%s' "$bms"
}

# --- budgets ---------------------------------------------------------------------------------------
# TWO tables. REFERENCE_* (milliseconds) is what this file used to gate on; it no longer gates
# anything and is kept only so each hook's line below can say whether the ms-budget verdict and
# the fork-cost verdict AGREE. BUDGET_UNITS_* (fork-cost units, mean-hook-ms / mean-baseline-ms
# per sample, then meaned/p95'd across samples) is what actually gates pass/fail now.
#
# dispatch-counter.sh is the one hook with a pre-existing, sourced ms budget: its own header
# (claude/hooks/dispatch-counter.sh:151-158) states "~25ms p95 budget this hook is held to" and a
# measured baseline of "mean=24.8ms/p95=25.9ms" -- reused verbatim in REFERENCE_* below, not
# re-derived. Its BUDGET_UNITS_* row is a genuine re-derivation: normalized, that claim is "about
# one fork-cost unit, since one folded jq call plus a couple of tiny builtins is roughly what one
# `jq -nr now` costs" -- see the handback text (this commit/PR description) for the exact
# replacement wording proposed for that header comment, since the raw-ms figure it currently
# states does not hold on this machine and nothing before this file re-derived it.
#
# No other hook in this directory has ever had a documented budget anywhere in this repo. The
# BUDGET_UNITS_* rows for the remaining seven are first recorded fork-cost baselines, derived by
# running THIS interleaved harness (not the old ms-only one, which never measured a baseline to
# divide by) twice back to back while seven concurrent gate-falsifiability.sh shards were running
# on this machine -- deliberately loaded, not waited out, per the run conditions this file's
# commit records. Budget = ceil(worst observed mean or p95 ratio across those two runs, x1.3),
# the same "measure, then set a ceiling with headroom, tighten later" move .claude/verify.sh's own
# check 58 makes of its own FIXED constant. A hook that blows through its unit budget here is a
# real finding to report, not a reason to raise the number.
REFERENCE_MEAN_compat_canary=115;            REFERENCE_P95_compat_canary=200
REFERENCE_MEAN_dispatch_counter=25;          REFERENCE_P95_dispatch_counter=25
REFERENCE_MEAN_failure_diagnose=55;          REFERENCE_P95_failure_diagnose=85
REFERENCE_MEAN_format=55;                    REFERENCE_P95_format=75
REFERENCE_MEAN_guard_destructive=60;         REFERENCE_P95_guard_destructive=75
REFERENCE_MEAN_inject_session_context=150;   REFERENCE_P95_inject_session_context=400
REFERENCE_MEAN_skill_mandate=300;            REFERENCE_P95_skill_mandate=475
REFERENCE_MEAN_verify_gate=90;               REFERENCE_P95_verify_gate=110

# Fork-cost units (hook_ms / baseline_ms per sample, meaned/p95'd). See the derivation paragraph
# above for how these eight numbers were set.
BUDGET_UNITS_MEAN_compat_canary=8.1;          BUDGET_UNITS_P95_compat_canary=9.8
BUDGET_UNITS_MEAN_dispatch_counter=5.2;       BUDGET_UNITS_P95_dispatch_counter=6.2
BUDGET_UNITS_MEAN_failure_diagnose=4.3;       BUDGET_UNITS_P95_failure_diagnose=5.3
BUDGET_UNITS_MEAN_format=5.3;                 BUDGET_UNITS_P95_format=6.1
BUDGET_UNITS_MEAN_guard_destructive=6.1;      BUDGET_UNITS_P95_guard_destructive=7.4
BUDGET_UNITS_MEAN_inject_session_context=9.8; BUDGET_UNITS_P95_inject_session_context=11.7
BUDGET_UNITS_MEAN_skill_mandate=24.6;         BUDGET_UNITS_P95_skill_mandate=35.3
BUDGET_UNITS_MEAN_verify_gate=6.6;            BUDGET_UNITS_P95_verify_gate=7.4

HOOKS="compat-canary dispatch-counter failure-diagnose format guard-destructive inject-session-context skill-mandate verify-gate"

# --- fixtures, built once (outside every timed sample) -------------------------------------------
mkdir -p "$WORK/fmt-project"
cat > "$WORK/fmt-project/.prettierrc.json" <<'EOF'
{"plugins": ["prettier-plugin-does-not-need-to-exist"]}
EOF
printf 'const x=1;\n' > "$WORK/fmt-project/x.js"

mkdir -p "$WORK/vg-project/.claude"
printf '#!/bin/sh\nexit 0\n' > "$WORK/vg-project/.claude/verify.sh"
chmod +x "$WORK/vg-project/.claude/verify.sh"

cat > "$WORK/sm-transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}}]}}
EOF

# --- per-hook payload / env / success-signal --------------------------------------------------
# Each function prints the JSON payload for sample $1 on stdout. Unique per-sample ids where the
# hook keys state off session_id (dispatch-counter's counter file, skill-mandate's 2-strike latch)
# so 30 samples each exercise a cold path instead of the 3rd+ sample silently hitting the hook's
# own by-design latch and going quiet for reasons that have nothing to do with latency.
payload_compat_canary()            { printf '{"hook_event_name":"SessionStart","session_id":"cc-%s"}' "$1"; }
payload_dispatch_counter()         { printf '{"tool_name":"Agent","session_id":"dc-%s","tool_input":{"subagent_type":"worker","description":"lat"},"tool_response":{"success":true},"tool_use_id":"tu-%s"}' "$1" "$1"; }
# Assembled at runtime, never written whole. check 3 of .claude/verify.sh scans the tree for
# sk-ant-[A-Za-z0-9_-]{16,} and cannot tell a fixture from a leak -- correctly, since a scanner
# that trusted a nearby comment saying "this one is fake" would be no scanner at all. Same shape
# .claude/verify.sh:1877 and tests/vstack-cli.sh:547 already use.
_fd_kp="sk-ant-"; _fd_kv="1234567890abcdef"; FAKE_KEY="${_fd_kp}${_fd_kv}"
payload_failure_diagnose()         { printf '{"tool_name":"Bash","tool_response":{"stderr":"api_key: %s error #%s"}}' "$FAKE_KEY" "$1"; }
payload_format()                   { printf '{"tool_input":{"file_path":"%s/fmt-project/x.js"}}' "$WORK"; }
payload_guard_destructive()        { printf '{"tool_input":{"command":"ls -la #%s"},"permission_mode":"default"}' "$1"; }
payload_inject_session_context()   { printf '{"hook_event_name":"UserPromptSubmit","session_id":"isc-%s","prompt":"fix the bug in the parser"}' "$1"; }
payload_skill_mandate()            { printf '{"session_id":"sm-%s","transcript_path":"%s/sm-transcript.jsonl","stop_hook_active":false}' "$1" "$WORK"; }
payload_verify_gate()              { printf '{"session_id":"vg-%s"}' "$1"; }

# Runs the hook under test for sample $2 of hook $1, INSIDE the timed region only -- fixture setup
# above and verification below both happen outside it. Sets $OUT and $RC as side effects.
run_hook() {
  hook="$1"; i="$2"
  script="$HOOKS_DIR/$hook.sh"
  case "$hook" in
    compat-canary)
      OUT=$(payload_compat_canary "$i" | env VSTACK_CLAUDE_VERSION_OVERRIDE=2.1.243 VSTACK_COMPAT_CANARY_LOG="$WORK/canary-$i.json" bash "$script" 2>/dev/null); RC=$? ;;
    dispatch-counter)
      OUT=$(payload_dispatch_counter "$i" | env VSTACK_REPLAY_LOG="$WORK/replay.jsonl" bash "$script" 2>/dev/null); RC=$? ;;
    failure-diagnose)
      OUT=$(payload_failure_diagnose "$i" | bash "$script" 2>/dev/null); RC=$? ;;
    format)
      OUT=$(payload_format "$i" | env CLAUDE_PROJECT_DIR="$WORK/fmt-project" bash "$script" 2>/dev/null); RC=$? ;;
    guard-destructive)
      OUT=$(payload_guard_destructive "$i" | bash "$script" 2>/dev/null); RC=$? ;;
    inject-session-context)
      OUT=$(payload_inject_session_context "$i" | bash "$script" 2>/dev/null); RC=$? ;;
    skill-mandate)
      OUT=$(payload_skill_mandate "$i" | env VSTACK_NO_DELEGATION_LOG=1 bash "$script" 2>/dev/null); RC=$? ;;
    verify-gate)
      OUT=$(payload_verify_gate "$i" | env CLAUDE_PROJECT_DIR="$WORK/vg-project" bash "$script" 2>/dev/null); RC=$? ;;
    *)
      OUT=""; RC=127 ;;
  esac
}

# Success signal per hook: proof the hook did its real work on this payload, not that it exited
# early. Returns 0/prints nothing on success, or a reason on failure via $VERIFY_ERR.
verify_sample() {
  hook="$1"; i="$2"
  VERIFY_ERR=""
  case "$hook" in
    compat-canary)
      # Silent stdout + exit 0 is the documented KNOWN contract; the real assertion is the state
      # file it wrote, which must show status:KNOWN for the version/event this sample fed it --
      # proof it parsed the payload and resolved the version, not just fell through silently.
      [ -z "$OUT" ] || VERIFY_ERR="expected silent stdout on a KNOWN payload, got: $OUT"
      [ -n "$VERIFY_ERR" ] && return 1
      st=$(jq -r '.status // empty' "$WORK/canary-$i.json" 2>/dev/null)
      [ "$st" = "KNOWN" ] || VERIFY_ERR="state file status is '$st', not KNOWN (file: $WORK/canary-$i.json)" ;;
    dispatch-counter)
      cf="$TMPDIR/vstack-dispatch-count-dc-$i"
      cv=$(cat "$cf" 2>/dev/null || echo "")
      [ "$cv" = "1" ] || VERIFY_ERR="counter file $cf reads '$cv', expected '1' (fresh session_id per sample)"
      if [ -z "$VERIFY_ERR" ]; then
        grep -q "\"session_id\":\"dc-$i\"" "$WORK/replay.jsonl" 2>/dev/null \
          || VERIFY_ERR="replay log has no row for session dc-$i"
      fi ;;
    failure-diagnose)
      case "$OUT" in
        *SELF-HEAL*'[REDACTED]'*) : ;;
        *) VERIFY_ERR="stdout missing SELF-HEAL context or the redacted secret marker: $OUT" ;;
      esac
      case "$OUT" in *"$FAKE_KEY"*) VERIFY_ERR="the raw secret leaked through unredacted" ;; esac ;;
    format)
      case "$OUT" in
        *systemMessage*plugins*) : ;;
        *) VERIFY_ERR="stdout missing the plugins-skip systemMessage: $OUT" ;;
      esac ;;
    guard-destructive)
      case "$OUT" in
        *'"permissionDecision":"allow"'*) : ;;
        *) VERIFY_ERR="stdout missing an allow decision for a harmless command: $OUT" ;;
      esac ;;
    inject-session-context)
      case "$OUT" in
        *additionalContext*TOKENS:*) : ;;
        *) VERIFY_ERR="stdout missing the per-prompt TOKENS digest: $OUT" ;;
      esac ;;
    skill-mandate)
      case "$OUT" in
        *'"decision":"block"'*unslop*) : ;;
        *) VERIFY_ERR="stdout missing an unslop block decision for an unmandated Write: $OUT" ;;
      esac ;;
    verify-gate)
      case "$OUT" in
        *systemMessage*untrusted*) : ;;
        *) VERIFY_ERR="stdout missing the untrusted-verify.sh systemMessage: $OUT" ;;
      esac ;;
  esac
  [ -z "$VERIFY_ERR" ]
}

# --- run ------------------------------------------------------------------------------------------
DECLARED=0
RAN=0
SKIPPED=0
FAIL=0
TABLE_A=""   # raw ms, informational
TABLE_B=""   # fork-cost units, authoritative
DIVERGENCE=""

for hook in $HOOKS; do
  DECLARED=$((DECLARED + 1))
  script="$HOOKS_DIR/$hook.sh"
  varname=$(printf '%s' "$hook" | tr '-' '_')

  if [ ! -f "$script" ]; then
    SKIPPED=$((SKIPPED + 1))
    printf 'FAIL  %-24s script not found: %s\n' "$hook.sh" "$script"
    FAIL=$((FAIL + 1))
    continue
  fi

  ms_samples=""
  ratio_samples=""
  baseline_samples=""
  bad=0
  bad_reason=""
  baseline_bad=0
  s=1
  while [ "$s" -le "$N" ]; do
    # Baseline first, immediately adjacent to the hook sample below -- both see the same instant
    # of machine load. A baseline that cannot be measured discards this sample entirely (neither
    # side is timed): dividing a hook's ms by a failed/garbage baseline would be worse than not
    # having a sample at all.
    bms=$(baseline_sample)
    if [ -z "$bms" ]; then
      baseline_bad=$((baseline_bad + 1))
      s=$((s + 1))
      continue
    fi

    t0=$(_now)
    run_hook "$hook" "$s"
    t1=$(_now)
    if [ "$RC" -ne 0 ]; then
      bad=$((bad + 1))
      bad_reason="sample $s: exit $RC"
      s=$((s + 1))
      continue
    fi
    if ! verify_sample "$hook" "$s"; then
      bad=$((bad + 1))
      bad_reason="sample $s: $VERIFY_ERR"
      s=$((s + 1))
      continue
    fi

    ms=$(elapsed_ms "$t0" "$t1")
    ratio=$(awk -v h="$ms" -v b="$bms" 'BEGIN{printf "%.4f", h/b}')
    ms_samples="$ms_samples $ms"
    ratio_samples="$ratio_samples $ratio"
    baseline_samples="$baseline_samples $bms"
    s=$((s + 1))
  done

  n_ok=$(printf '%s\n' $ratio_samples | grep -c '[0-9]')
  if [ "$n_ok" -eq 0 ]; then
    SKIPPED=$((SKIPPED + 1))
    if [ "$baseline_bad" -ge "$N" ]; then
      reason="baseline fork-cost unit could not be measured ($baseline_bad/$N attempts failed) -- see jq's own exit status, this is not about the hook"
    else
      reason="zero samples collected (${bad}/${N} hook attempts failed; last: ${bad_reason:-unknown})"
    fi
    printf 'FAIL  %-24s %s\n' "$hook.sh" "$reason"
    FAIL=$((FAIL + 1))
    continue
  fi

  RAN=$((RAN + 1))

  ms_stats=$(stats_of "$ms_samples"); mean_ms=$(printf '%s' "$ms_stats" | awk '{print $1}'); p95_ms=$(printf '%s' "$ms_stats" | awk '{print $2}')
  ratio_stats=$(stats_of "$ratio_samples"); mean_u=$(printf '%s' "$ratio_stats" | awk '{print $1}'); p95_u=$(printf '%s' "$ratio_stats" | awk '{print $2}')
  base_stats=$(stats_of "$baseline_samples"); mean_b=$(printf '%s' "$base_stats" | awk '{print $1}'); p95_b=$(printf '%s' "$base_stats" | awk '{print $2}')

  rmean_var="REFERENCE_MEAN_$varname"; rp95_var="REFERENCE_P95_$varname"
  bumean_var="BUDGET_UNITS_MEAN_$varname"; bup95_var="BUDGET_UNITS_P95_$varname"
  eval "rmean=\$$rmean_var"; eval "rp95=\$$rp95_var"
  eval "bumean=\$$bumean_var"; eval "bup95=\$$bup95_var"

  # Authoritative verdict: fork-cost units against BUDGET_UNITS_*.
  over=""
  [ "$(ms_le "$mean_u" "$bumean")" = 1 ] || over="mean ${mean_u}u > ${bumean}u budget"
  if [ "$(ms_le "$p95_u" "$bup95")" = 1 ]; then :; else
    over="${over:+$over; }p95 ${p95_u}u > ${bup95}u budget"
  fi

  # Reference (informational only): what the old ms budget would have said about this same run.
  ref_over=""
  [ "$(ms_le "$mean_ms" "$rmean")" = 1 ] || ref_over="mean ${mean_ms}ms > ${rmean}ms"
  if [ "$(ms_le "$p95_ms" "$rp95")" = 1 ]; then :; else
    ref_over="${ref_over:+$ref_over; }p95 ${p95_ms}ms > ${rp95}ms"
  fi

  if [ -n "$bad_reason" ] && [ "$bad" -gt 0 ]; then
    note=" (${bad}/${N} hook attempts failed and were excluded, e.g. $bad_reason)"
  else
    note=""
  fi
  if [ "$baseline_bad" -gt 0 ]; then
    note="$note (${baseline_bad}/${N} baseline attempts failed and were excluded)"
  fi

  if [ -n "$over" ]; then
    printf 'FAIL  %-24s units mean=%su p95=%su  (raw mean=%sms p95=%sms)  n=%s  BUDGET EXCEEDED: %s%s\n' \
      "$hook.sh" "$mean_u" "$p95_u" "$mean_ms" "$p95_ms" "$n_ok" "$over" "$note"
    FAIL=$((FAIL + 1))
  else
    printf 'ok    %-24s units mean=%su p95=%su  (raw mean=%sms p95=%sms)  n=%s  (budget mean<=%su p95<=%su)%s\n' \
      "$hook.sh" "$mean_u" "$p95_u" "$mean_ms" "$p95_ms" "$n_ok" "$bumean" "$bup95" "$note"
  fi

  # The divergence check item 5 asks for: does the OLD ms-budget verdict (informational, not
  # gating) disagree with the NEW authoritative units verdict, on this same set of samples? That
  # disagreement -- not the raw numbers alone -- is the evidence normalization changed anything.
  if [ -n "$ref_over" ] && [ -z "$over" ]; then
    DIVERGENCE="$DIVERGENCE\n  $hook.sh: ms-budget would FAIL ($ref_over) but the units budget PASSES -- the ms failure was the machine, not the hook"
  elif [ -z "$ref_over" ] && [ -n "$over" ]; then
    DIVERGENCE="$DIVERGENCE\n  $hook.sh: ms-budget would PASS but the units budget FAILS ($over) -- this hook is genuinely slow relative to a fork, not just measured on a loaded moment"
  fi

  a_line=$(printf '  %-24s mean=%9sms  p95=%9sms' "$hook.sh" "$mean_ms" "$p95_ms")
  TABLE_A="$TABLE_A
$a_line"
  b_line=$(printf '  %-24s mean=%7su  p95=%7su   (baseline this window: mean=%sms p95=%sms)' "$hook.sh" "$mean_u" "$p95_u" "$mean_b" "$p95_b")
  TABLE_B="$TABLE_B
$b_line"

  # Every sample that failed the RC/success-signal check inside the loop above still counts
  # against this hook's own reliability, independent of latency: n_ok < N is itself a failure,
  # not something the accounting line is allowed to quietly absorb into "ran".
  if [ "$n_ok" -lt "$N" ]; then
    printf 'FAIL  %-24s only %s/%s samples produced a verified baseline+success-signal pair (last failure: %s)\n' \
      "$hook.sh" "$n_ok" "$N" "${bad_reason:-baseline attempts failed}"
    FAIL=$((FAIL + 1))
  fi
done

echo
echo "Table A -- raw milliseconds (informational; does not gate pass/fail)"
printf '%s\n' "$TABLE_A"
echo
echo "Table B -- fork-cost units (authoritative; hook_ms / interleaved-baseline_ms per sample)"
printf '%s\n' "$TABLE_B"

if [ -n "$DIVERGENCE" ]; then
  echo
  echo "Verdict divergence (old ms budget vs new units budget, same samples):"
  printf '%b\n' "$DIVERGENCE"
fi

echo
printf 'hooks: %d declared, %d ran, %d skipped\n' "$DECLARED" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$DECLARED" ]; then
  printf 'FAIL  hook accounting: %d declared hook(s) reported nothing\n' "$((DECLARED - RAN - SKIPPED))"
  FAIL=$((FAIL + 1))
fi
# Belt and suspenders against the shape tests/README.md's vstack-cli.sh section warns about: N
# declared, N skipped, 0 ran satisfies ran+skipped==declared while proving nothing measured
# anything. That must fail on its own, not pass because the arithmetic above balanced.
if [ "$RAN" -eq 0 ]; then
  printf 'FAIL  every declared hook was skipped -- this run measured nothing\n'
  FAIL=$((FAIL + 1))
fi

[ "$FAIL" -eq 0 ] && echo "HOOK LATENCY OK" || echo "HOOK LATENCY FAILED"
exit "$FAIL"
