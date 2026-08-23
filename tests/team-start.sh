#!/usr/bin/env bash
# tests/team-start.sh
#
# Measures two properties the routing config only asserts in prose: does a session that
# plainly warrants delegation actually issue an Agent tool_use (the delegation mandate's
# situation in claude/hooks/skill-mandate.sh), and does the assistant's own visible text name
# a roster call sign when it does (the "NAME THE AGENT" policy in CLAUDE.md and team.md).
#
# WHAT THIS DOES NOT PROVE. One model (sonnet), one day (2026-08-23), n=5 per fixture. That is
# enough to separate "never happens" from "happens at least sometimes" (see auto-trigger.sh's
# own Wilson-interval note: n=5 cannot separate a 90% behavior from a 60% one, only a ~0% one
# from a non-zero one). Report raw k/5, never a percentage -- a point estimate here implies
# precision this sample size does not have. This is not a fleet measurement and must not be
# read as one. It also proves nothing about any commit but the one the installed hooks were
# built from at run time -- there is no version pinning inside the CLI call itself, only in
# what happens to be materialized under ~/.claude when you run this. Know that before you read
# a number: `diff -r claude/hooks ~/.claude/hooks` (or the drift preflight below, which refuses
# to spend a call when that diff is non-empty) is what tells you which program you measured.
#
# Referrer: tests/README.md (added by the file's owner, not this script).
#
# Exit codes:
#   0  the suite ran to completion, regardless of what the rates turned out to be -- this is a
#      MEASUREMENT tool, not a pass/fail gate. A low rate is a finding, not a failure to report.
#   1  no case ran (bad selector, or every case was skipped) -- this must never look like 0.
#   2  claude/jq unavailable -- same "cannot silently look like a clean run" contract as
#      auto-trigger.sh's skip_or_fail.
set -uo pipefail

PER_CASE_TIMEOUT=120   # seconds, same budget auto-trigger.sh uses; macOS has no timeout(1)
MODEL="sonnet"
# Not measured against a lower value for these specific fixtures. Set above auto-trigger.sh's
# default (3) on purpose: these prompts need the model to read multiple files before a
# delegate-or-not decision is even reachable, and a run cut off by error_max_turns before that
# point would misreport as "chose not to delegate" when it was actually turn-starved -- the
# exact confound auto-trigger.sh's case_max_turns() table documents for encode-lessons-lint.
# 6 was a judgment call, not a measurement, and the first real run proved it insufficient for
# delegation-a specifically: 5/5 samples hit error_max_turns at 6, the same shape
# encode-lessons-lint showed at 3 and 6 before passing cleanly at 10 -- precedent that the
# budget, not the fixture, was the variable. Override via MAX_TURNS=N; a run that still hits
# error_max_turns is reported as starved below, never folded into the miss count.
MAX_TURNS="${MAX_TURNS:-6}"
SAMPLES="${SAMPLES:-5}"   # n per fixture; override for a cheaper smoke run, e.g. SAMPLES=1

# ---------------------------------------------------------------------------
# Preflight -- identical contract to auto-trigger.sh: CI gets a silent 0 (no auth there by
# design), everywhere else a local run that tested nothing exits 2 rather than reading as a pass.
# ---------------------------------------------------------------------------
skip_or_fail() {
  echo "SKIP: $1"
  if [[ "${CI:-}" == "true" ]]; then exit 0; fi
  echo "      (exit 2: nothing was tested. Set CI=true to make this a pass.)"
  exit 2
}

# ---------------------------------------------------------------------------
# Hook-drift preflight. 2026-08-23: this suite's first real run measured 9 samples against a
# stale ~/.claude/hooks/ before anyone noticed install.sh had not been re-run since before
# v1.35.0 -- every one of those samples was testing an old build of exactly the mandate this
# script measures the effect of, and got discarded. A harness that silently measures stale
# code produces a number that looks like an answer and is about a different program, same
# defect class as a gate that goes green on nothing. Refuse to spend a single `claude` call
# until the installed hooks match this checkout, byte for byte.
#
# Override: VSTACK_ALLOW_HOOK_DRIFT=1, for the deliberate case of measuring an old installed
# version on purpose. It prints loudly rather than silently proceeding, so a stale run can
# never be mistaken for a fresh one in the log.
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
check_hook_drift() {
  local repo_hooks="$REPO_ROOT/claude/hooks"
  local installed_hooks="$CDIR/hooks"
  local drifted="" f base
  [[ -d "$repo_hooks" ]] || return 0
  [[ -d "$installed_hooks" ]] || { echo "PREFLIGHT: $installed_hooks does not exist -- nothing installed. Run install.sh first."; return 1; }
  for f in "$repo_hooks"/*.sh; do
    base="$(basename "$f")"
    if [[ ! -f "$installed_hooks/$base" ]]; then
      drifted="$drifted
  $base -- not installed at all"
    elif ! diff -q "$f" "$installed_hooks/$base" >/dev/null 2>&1; then
      drifted="$drifted
  $base -- installed copy differs from this checkout"
    fi
  done
  if [[ -n "$drifted" ]]; then
    if [[ "${VSTACK_ALLOW_HOOK_DRIFT:-0}" == "1" ]]; then
      echo "PREFLIGHT: hook drift detected, proceeding anyway because VSTACK_ALLOW_HOOK_DRIFT=1:$drifted"
      echo "PREFLIGHT: every sample below is measuring the INSTALLED hooks in $installed_hooks, which are NOT this checkout ($REPO_ROOT). Read the numbers as about that version, not this one."
      return 0
    fi
    echo "PREFLIGHT FAILED: installed hooks in $installed_hooks drift from $repo_hooks:$drifted"
    echo "      This suite measures the effect of claude/hooks/skill-mandate.sh and"
    echo "      claude/hooks/inject-session-context.sh. A drifted install means every sample"
    echo "      would test a different program than the one in this checkout."
    echo "      Fix: re-run install.sh from a clean checkout of the commit you want to measure."
    echo "      Override (measure the stale install on purpose): VSTACK_ALLOW_HOOK_DRIFT=1"
    return 1
  fi
  return 0
}
check_hook_drift || exit 2

command -v claude >/dev/null 2>&1 || skip_or_fail "'claude' CLI not found on PATH."
AUTH_JSON="$(claude auth status 2>/dev/null)"
if [[ -z "$AUTH_JSON" ]] || ! echo "$AUTH_JSON" | grep -q '"loggedIn": *true'; then
  skip_or_fail "'claude' CLI is not authenticated (claude auth status did not report loggedIn: true)."
fi
command -v jq >/dev/null 2>&1 || skip_or_fail "'jq' not found on PATH; required to parse stream-json output."

# ---------------------------------------------------------------------------
# extract_delegated OUT_JSONL
# Prints "1" if the transcript contains at least one tool_use named "Agent" or "Task",
# else "0".
#
# Both names are checked because the two live docs in this repo disagree on which one the
# runtime actually uses: team.md instructs "Delegate ... with the Task tool" and
# claude/hooks/skill-mandate.sh's task_count keys off .name=="Task", but a calibration call
# made while building this script (tests/team-start.sh, 2026-08-23: prompt "Use the Task tool
# right now to launch a subagent") shows the CLI emits tool_use name "Agent" with an
# input.subagent_type field, never "Task", on this build of the claude CLI. That calibration
# transcript is not preserved (throwaway /tmp workdir, deleted same session) -- reproduce with:
#   claude -p 'Use the Task tool right now to launch a subagent that just says hello.' \
#     --output-format stream-json --verbose --model sonnet --max-turns 3 \
#     | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use")|.name'
# Practical effect at the time this script's n=5 measurement ran (installed hooks pinned to
# commit 1b257ee): skill-mandate.sh's task_count was measured 0 on every real transcript this
# script produced, including the ones that plainly delegated -- its delegation-suppression
# branch and its naming mandate (gated on task_count>=1) were dead code against the live CLI,
# not merely undertested. Independently confirmed after this run, in commit a2d7f46 ("skill-
# mandate: count Agent alongside Task"), against a real 15MB transcript with 70 Agent
# tool_use dispatches and task_count reading 0 throughout -- same root cause, found twice by
# two different methods. a2d7f46 fixes it (counts Task or Agent) and lands after the SHA this
# script's own measurement is pinned to; a rerun against current HEAD would no longer show
# this specific defect, only whatever the naming/breadth rates look like post-fix.
# ---------------------------------------------------------------------------
extract_delegated() {
  local jsonl="$1"
  local n
  n=$(jq -r '
    select(.type=="assistant")
    | (.message.content // [])[]
    | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
    | .name
  ' "$jsonl" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$n" -ge 1 ]]; then echo 1; else echo 0; fi
}

# ---------------------------------------------------------------------------
# extract_named OUT_JSONL
# Prints "1" if any assistant-visible text block contains a roster call sign, else "0".
# Same roster and same \b-bounded regex as skill-mandate.sh's agent-naming mandate, so this
# measures against the identical definition of "named" the gate itself enforces.
# ---------------------------------------------------------------------------
extract_named() {
  local jsonl="$1"
  local text
  text=$(jq -r '
    select(.type=="assistant")
    | (.message.content // [])[]
    | select(.type=="text")
    | .text
  ' "$jsonl" 2>/dev/null | tr '\n' ' ')
  if printf '%s' "$text" | grep -qiE '\b(RICK|MEESEEKS|MORTY|SUMMER|ZEEP|GLOOTIE|JAGUAR|BETH|BIRDPERSON|EVIL-MORTY|NOOBNOOB|PICKLE-RICK|SCARY-TERRY|POOPYBUTTHOLE|UNITY)\b'; then
    echo 1
  else
    echo 0
  fi
}

# ---------------------------------------------------------------------------
# top_level_subtype OUT_JSONL -- same discriminator as auto-trigger.sh: the top-level run's
# result event has no "origin" field, a subagent's task-notification result does.
# ---------------------------------------------------------------------------
top_level_subtype() {
  local jsonl="$1"
  jq -r 'select(.type=="result" and (.origin==null)) | .subtype' "$jsonl" 2>/dev/null | tail -1
}

# ---------------------------------------------------------------------------
# Fixture setup functions. Each seeds a throwaway dir the prompt reacts to.
# ---------------------------------------------------------------------------

# Positive fixture A: bug duplicated across two service directories plus a docs file --
# 3 parent dirs (services/auth, services/billing, docs), 3 extensions (js, py, md). This is
# exactly the shape claude/hooks/skill-mandate.sh's own breadth mandate treats as work with
# parts (dir_count>=3 and ext_count>=2), i.e. the shipped policy's own definition of
# "plainly warrants delegation," not a definition invented for this test.
setup_multi_service_fix() {
  local dir="$1"
  mkdir -p "$dir/services/auth" "$dir/services/billing" "$dir/docs"
  cat > "$dir/services/auth/handler.js" <<'EOF'
// handler.js -- auth service request handler
function handleLogin(req, res) {
  const user = req.body.username;
  console.log("login attempt: " + user); // logs the raw field verbatim, unescaped
  res.status(200).send("ok");
}
module.exports = { handleLogin };
EOF
  cat > "$dir/services/billing/handler.py" <<'EOF'
# handler.py -- billing service request handler
def handle_charge(req):
    account = req["account_id"]
    print(f"charge attempt: {account}")  # logs the raw field verbatim, unescaped
    return {"status": 200}
EOF
  cat > "$dir/docs/CHANGES.md" <<'EOF'
# Changes

(nothing recorded yet)
EOF
}

# Positive fixture B: structured logging added across frontend, backend, and infra config,
# documented in a fourth directory -- 4 parent dirs, 4 extensions (js, py, yaml, md).
setup_stack_wide_logging() {
  local dir="$1"
  mkdir -p "$dir/frontend" "$dir/backend" "$dir/infra" "$dir/docs"
  cat > "$dir/frontend/app.js" <<'EOF'
// app.js -- entry point
function main() { console.log("started"); }
main();
EOF
  cat > "$dir/backend/server.py" <<'EOF'
# server.py -- entry point
def start():
    print("started")

start()
EOF
  cat > "$dir/infra/deploy.yaml" <<'EOF'
service: notes-app
replicas: 2
EOF
  cat > "$dir/docs/RUNBOOK.md" <<'EOF'
# Runbook

(no logging section yet)
EOF
}

# Positive fixture C: security audit across three module directories plus a report written
# at the repo root -- 4 parent dirs (modules/auth, modules/payments, modules/search, .),
# 4 extensions (js, py, go, md).
setup_module_audit() {
  local dir="$1"
  mkdir -p "$dir/modules/auth" "$dir/modules/payments" "$dir/modules/search"
  cat > "$dir/modules/auth/index.js" <<'EOF'
function checkPassword(input, stored) { return input == stored; } // loose equality
module.exports = { checkPassword };
EOF
  cat > "$dir/modules/payments/index.py" <<'EOF'
def charge(card_number, amount):
    log = open("/tmp/payments.log", "a")
    log.write(f"{card_number}:{amount}\n")  # writes the raw card number to a log file
    log.close()
EOF
  cat > "$dir/modules/search/index.go" <<'EOF'
package search

import "fmt"

func Query(raw string) string {
	return fmt.Sprintf("SELECT * FROM notes WHERE text LIKE '%%%s%%'", raw) // string-built query
}
EOF
}

# Negative fixture: one file, one line, one obvious fix. team.md states the policy directly --
# "A one-file change does not need an architecture round; say so and skip it rather than
# performing the ceremony." A session that spins up a subagent to fix a one-line typo is a
# config that earns being turned off, which is exactly why this arm matters as much as the
# three positives.
setup_trivial_typo() {
  local dir="$1"
  cat > "$dir/hello.py" <<'EOF'
def greet(name):
    retrun f"hello, {name}"  # line 2: typo, should be 'return'

print(greet("world"))
EOF
}

# ---------------------------------------------------------------------------
# run_fixture NAME PROMPT SETUP_FN
# Runs SAMPLES independent, non-retrying `claude -p` invocations. Each sample is a fresh
# workdir and a fresh process -- there is no early-stopping loop here, unlike
# auto-trigger.sh's run_case ATTEMPTS retry: a retry-to-first-hit loop measures "did it ever
# happen," not a rate, which is the bias auto-trigger.sh's own header warns against
# reproducing.
# ---------------------------------------------------------------------------
declare -a FIXTURE_NAMES=()
declare -a DELEGATE_HITS=()
declare -a NAME_HITS=()
declare -a STARVED_COUNTS=()
declare -a SAMPLES_RUN=()
CASES_DECLARED=4
CASES_RAN=0
CASES_SKIPPED=0

run_fixture() {
  local name="$1" prompt="$2" setup_fn="$3"
  local i workdir out_jsonl err_log runner_pid waited
  local d_hits=0 n_hits=0 starved=0 ran=0

  for i in $(seq 1 "$SAMPLES"); do
    workdir="$(mktemp -d "/tmp/team-start-test.XXXXXX")"
    "$setup_fn" "$workdir"
    out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"

    # exec is load-bearing, same reason as auto-trigger.sh: without it the timeout's kill -9
    # hits an empty subshell wrapper instead of the claude process, leaking a live billed run.
    #
    # Mutation tools stay denied for the TOP-LEVEL process (Write/Edit/MultiEdit/NotebookEdit/
    # Bash) so a sample cannot leave real damage in the throwaway workdir. "Agent" is
    # deliberately NOT in this list -- it is the exact tool_use this script exists to detect,
    # denying it would make delegation structurally impossible and the delegation rate would
    # read as 0/5 by construction rather than by measurement.
    (
      cd "$workdir" || exit 1
      # This is a real claude -p session, so the installed Stop hook's delegation-drift logger
      # (claude/hooks/skill-mandate.sh, default ~/.claude/vstack-delegation-log.jsonl) fires
      # against it same as any genuine session. Pointed at a file under $workdir instead: these
      # samples are throwaway harness runs, not operator work, and the log exists to measure the
      # latter. $workdir is rm -rf'd right after this sample is scored, taking the log with it.
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        VSTACK_DELEGATION_LOG="$workdir/.delegation-log.jsonl" \
        claude -p "$prompt" \
          --output-format stream-json --verbose \
          --disallowedTools "Write,Edit,MultiEdit,NotebookEdit,Bash" \
          --model "$MODEL" --max-turns "$MAX_TURNS" \
          < /dev/null > "$out_jsonl" 2> "$err_log"
    ) &
    runner_pid=$!

    waited=0
    while kill -0 "$runner_pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
      if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
    done
    wait "$runner_pid" 2>/dev/null

    if [[ ! -s "$out_jsonl" ]]; then
      echo "  $name sample $i/$SAMPLES: no output (timeout or crash)"
      rm -rf "$workdir"
      ran=$((ran + 1))
      continue
    fi

    local subtype delegated named
    subtype="$(top_level_subtype "$out_jsonl")"
    delegated="$(extract_delegated "$out_jsonl")"
    named="$(extract_named "$out_jsonl")"

    if [[ "$subtype" == "error_max_turns" ]]; then
      starved=$((starved + 1))
    fi
    [[ "$delegated" == "1" ]] && d_hits=$((d_hits + 1))
    [[ "$named" == "1" ]] && n_hits=$((n_hits + 1))
    ran=$((ran + 1))

    echo "  $name sample $i/$SAMPLES: subtype=${subtype:-unknown} delegated=$delegated named=$named"
    rm -rf "$workdir"
  done

  FIXTURE_NAMES+=("$name")
  DELEGATE_HITS+=("$d_hits")
  NAME_HITS+=("$n_hits")
  STARVED_COUNTS+=("$starved")
  SAMPLES_RUN+=("$ran")
  CASES_RAN=$((CASES_RAN + 1))
}

# Selector, same convention as auto-trigger.sh: no args runs all four fixtures, args name
# which ones to run (delegation-a, delegation-b, delegation-c, negative-typo).
SELECTED=("$@")
selected_() {
  [ ${#SELECTED[@]} -eq 0 ] && return 0
  local want
  for want in "${SELECTED[@]}"; do [ "$want" = "$1" ] && return 0; done
  return 1
}

echo "Measuring delegation + agent-naming rates (model=$MODEL, max-turns=$MAX_TURNS, n=$SAMPLES per fixture, per-sample timeout=${PER_CASE_TIMEOUT}s)"
echo "---"

if selected_ "delegation-a"; then
  run_fixture "delegation-a" \
    "There's the same input-validation bug duplicated in services/auth/handler.js and services/billing/handler.py -- an unescaped user-supplied field gets logged verbatim in both. Fix it in both files, and add a line to docs/CHANGES.md describing the fix and why it recurred." \
    "setup_multi_service_fix"
else
  CASES_SKIPPED=$((CASES_SKIPPED + 1))
fi

if selected_ "delegation-b"; then
  run_fixture "delegation-b" \
    "Add structured request-id logging across frontend/app.js, backend/server.py, and infra/deploy.yaml, and document the new log format in docs/RUNBOOK.md. This spans the whole stack -- frontend, backend, and infra config all need the change." \
    "setup_stack_wide_logging"
else
  CASES_SKIPPED=$((CASES_SKIPPED + 1))
fi

if selected_ "delegation-c"; then
  run_fixture "delegation-c" \
    "Audit modules/auth, modules/payments, and modules/search for security issues, then write a REPORT.md at the repo root summarizing findings across all three." \
    "setup_module_audit"
else
  CASES_SKIPPED=$((CASES_SKIPPED + 1))
fi

if selected_ "negative-typo"; then
  run_fixture "negative-typo" \
    "Line 2 of hello.py has a typo: 'retrun' should be 'return'. Fix that one line." \
    "setup_trivial_typo"
else
  CASES_SKIPPED=$((CASES_SKIPPED + 1))
fi

echo "---"

if (( CASES_RAN == 0 )); then
  echo "no fixture ran. ${#SELECTED[@]} selector(s) given, none matched a fixture name."
  echo "checks: $CASES_DECLARED declared / 0 ran / $CASES_SKIPPED skipped"
  exit 1
fi

echo "Results (raw k/n, not a percentage -- see header for why):"
idx=0
while [[ $idx -lt ${#FIXTURE_NAMES[@]} ]]; do
  printf '  %-16s delegated %s/%-2s  named %s/%-2s  turn-starved %s/%s\n' \
    "${FIXTURE_NAMES[$idx]}" "${DELEGATE_HITS[$idx]}" "${SAMPLES_RUN[$idx]}" \
    "${NAME_HITS[$idx]}" "${SAMPLES_RUN[$idx]}" "${STARVED_COUNTS[$idx]}" "${SAMPLES_RUN[$idx]}"
  idx=$((idx + 1))
done

echo
echo "checks: $CASES_DECLARED declared / $CASES_RAN ran / $CASES_SKIPPED skipped"
exit 0
