#!/usr/bin/env bash
# tests/auto-trigger.sh
#
# Regression test: proves Claude Code skills still auto-trigger from natural
# language prompts, without a slash command. See tests/README.md for the
# full story on why this exists and how to extend it.
#
# Exit codes:
#   0  all cases passed (or the suite was skipped because claude is
#      unavailable/unauthenticated -- CI cannot run this test)
#   1  one or more cases failed to fire the expected skill
set -uo pipefail

PER_CASE_TIMEOUT=120   # seconds; enforced by the polling loop in run_case (macOS has no timeout(1))
MODEL="sonnet"
MAX_TURNS=3
# Per-case turn budget, measured not guessed (2026-08-23), enforced by case_max_turns() below.
# MAX_TURNS above is still the global default -- a case with no row here is not in the case
# statement below either, and inherits MAX_TURNS unchanged, same as before this table existed.
# Do not silently raise the floor for a case with no row: only the two entries under
# "needs more than the default" get an override. Each row is a real claude invocation at
# that value, run outside this harness with matching flags (including the "Agent" denial),
# workdir inspected before cleanup for terminal `subtype`, `num_turns`, and whether a `Skill`
# tool_use appears. `num_turns` in that result event is NOT the same counter --max-turns
# enforces against: it also tallies turns from spawned subagents/internal tool infrastructure
# (a haiku-model subagent's turns showed up in the SAME result event as the capped sonnet
# agent's own, in the encode-lessons-lint @6 transcript). The cap itself is proven binding by
# the CLI's own error text, which cites the configured value exactly ("Reached maximum number
# of turns (6)" at --max-turns 6) even though num_turns reported 7 for that same run --
# read num_turns as a rough diagnostic, not as turns-consumed-of-budget.
#
# MEASURED, sufficient at the current default (3) -- no override needed:
#   root-cause-guard                       PASS both historical runs, attempt 1
#   idempotent-cron                        PASS both historical runs, attempt <=2
#   boundary-discipline-api                PASS both historical runs, attempt 1
#   sequence-verifiable-units-migration    PASS both historical runs, attempt 1
#
# MEASURED, needs more than the default -- recommended per-case value:
#   prove-it-works-declare-done   -> 6     @6, one sample: subtype=success, num_turns=4/6,
#                                           no Skill call, tools used Grep,Grep,Read --
#                                           completed without consulting the dispatcher. But
#                                           a same-day 3-attempt baseline at the DEFAULT (3)
#                                           was 0/3 miss, then 1/3 PASS on the very next run
#                                           (attempt 1) -- a flapper, not a hard zero. One
#                                           sample of a stochastic process is not a
#                                           measurement of it: do NOT read this as a proven
#                                           "never fires." 6 is still a reasonable budget
#                                           (the one deep-dive sample used only 4 of it), but
#                                           the dispatch-rate question is open pending a
#                                           proper per-case sample count.
#   encode-lessons-lint            -> 10   @3: starved, never fired in 3/3 attempts (two
#                                           separate historical runs).
#                                           @6: still subtype=error_max_turns, num_turns=7,
#                                           no Skill call (transcript preserved at
#                                           /tmp/auto-trigger-test.AJGn8t).
#                                           @10: subtype=success, num_turns=12/10, Skill
#                                           fired (principle-encode-lessons-in-structure).
#                                           Turn-starved, not structurally unfireable like
#                                           prove-it-works-declare-done -- 10 is the first
#                                           measured-sufficient value; not tried below 10.
#
# MEASURED flaky at the default, but NO measurement above 3 exists -- deliberately left
# unset rather than guessed. A guessed number here would be indistinguishable from a
# measured one, which is exactly the confusion this table exists to prevent:
#   build-the-lever-headers                @3: PASS attempt 2 one historical run,
#                                           never-fired-in-3 the other. Not measured above 3.
#   type-system-discipline-go              @3: PASS attempt 1 one historical run,
#                                           never-fired-in-3 the other. Not measured above 3.
#
# UNSET -- no data, not run this session. Unset means "nobody has checked," not "3 is known
# to be enough":
#   readme-writing, typescript-review, swarm-audit, blast-radius-auth, feature-chain,
#   overnight-audit-trail, ui-iterate-styles, component-registry-combobox, grill-my-plan,
#   find-a-skill, agent-browser-screenshot, create-verification-skill-cold-start,
#   executing-plans-checkpoints, impeccable-polish, interrogate-auth-diff,
#   maintain-verification-skill-drift, reflect-session, unslop-draft-pass,
#   negative-arithmetic, negative-factual
# ---------------------------------------------------------------------------
# case_max_turns NAME
# Prints the --max-turns value for NAME: the override from the table above if it has one,
# else the global MAX_TURNS default. A plain case statement, not an associative array --
# macOS ships bash 3.2, which doesn't have those.
# ---------------------------------------------------------------------------
case_max_turns() {
  case "$1" in
    prove-it-works-declare-done) echo 6 ;;
    encode-lessons-lint)         echo 10 ;;
    *)                           echo "$MAX_TURNS" ;;
  esac
}

# Attempts per case before calling it a failure. Skill dispatch is a model decision, so a
# single sample is a coin flip; a skill that has actually stopped firing misses every attempt.
# feature-chain is the measured-marginal case (~50% per attempt across runs: the model often
# just starts building instead of brainstorming first) — three attempts keep the suite
# honest about "does this situation ever route there" without crying wolf.
ATTEMPTS="${ATTEMPTS:-3}"

PASS_COUNT=0
FAIL_COUNT=0
declare -a RESULT_LINES=()
# Which attempt each case landed on. Pass/fail alone hides erosion: a skill that has slipped
# from firing every time to firing on the third try still reads PASS, and stays a pass right up
# until it reaches zero. The attempt number is the early warning.
declare -a HIT_LINES=()

# ---------------------------------------------------------------------------
# Preflight. In CI this skips with exit 0: GitHub Actions cannot authenticate
# headlessly, so an absent session is expected rather than broken.
#
# Everywhere else it exits 2. A local run that quietly returned 0 without having
# tested anything read exactly like a pass, which is the failure mode this whole
# suite exists to catch in the config it tests.
# ---------------------------------------------------------------------------
skip_or_fail() {
  echo "SKIP: $1"
  if [[ "${CI:-}" == "true" ]]; then exit 0; fi
  echo "      (exit 2: nothing was tested. Set CI=true to make this a pass.)"
  exit 2
}

command -v claude >/dev/null 2>&1 || \
  skip_or_fail "'claude' CLI not found on PATH."

AUTH_JSON="$(claude auth status 2>/dev/null)"
if [[ -z "$AUTH_JSON" ]] || ! echo "$AUTH_JSON" | grep -q '"loggedIn": *true'; then
  skip_or_fail "'claude' CLI is not authenticated (claude auth status did not report loggedIn: true)."
fi

command -v jq >/dev/null 2>&1 || \
  skip_or_fail "'jq' not found on PATH; required to parse stream-json output."


# ---------------------------------------------------------------------------
# extract_fired_skills OUT_JSONL
# Prints one skill name per line that fired via the Skill tool.
#
# Shape (verified with a throwaway run before writing this filter):
#   {"type":"assistant","message":{"id":"msg_...","content":[
#     {"type":"tool_use","id":"toolu_...","name":"Skill","input":{"skill":"foo", ...}}
#   ]}}
#
# Claude Code emits one "assistant" stream-json event per CONTENT BLOCK, not
# per message -- several lines can share the same message.id. That's fine
# here because each tool_use block still appears exactly once across the
# stream (verified empirically), so no dedup/grouping is needed to detect
# "did skill X fire." Grouping by message.id only matters if you need
# per-message tool-call *counts*, which this test does not.
# ---------------------------------------------------------------------------
extract_fired_skills() {
  local jsonl="$1"
  jq -r '
    select(.type=="assistant")
    | (.message.content // [])[]
    | select(.type=="tool_use" and .name=="Skill")
    | (.input.skill // "unknown")
  ' "$jsonl" 2>/dev/null | sort -u
}

# ---------------------------------------------------------------------------
# top_level_subtype OUT_JSONL
# Prints the CLI's own "subtype" for the RUN's terminal result event -- e.g.
# "success" (ran to completion, whatever it did or didn't call) or
# "error_max_turns" (cut off mid-task, never reached a decision).
#
# There can be more than one type=="result" event in the stream: a background
# subagent launched via the Agent tool reports its OWN completion as a
# type=="result" line too (verified against /tmp/auto-trigger-test.AJGn8t,
# encode-lessons-lint @ MAX_TURNS=6 -- two result events, same session_id).
# The subagent's carries an "origin":{"kind":"task-notification"} field the
# top-level run's result does not, so that's the discriminator: select the
# result event with no origin, not just the last result line in the file.
# ---------------------------------------------------------------------------
top_level_subtype() {
  local jsonl="$1"
  jq -r 'select(.type=="result" and (.origin==null)) | .subtype' "$jsonl" 2>/dev/null | tail -1
}

# ---------------------------------------------------------------------------
# fence_violations WORKDIR BASELINE OUT_JSONL ERR_LOG
# BASELINE is a newline-separated snapshot of WORKDIR taken right after
# setup_fn ran and before claude launched. Prints one path per line for
# anything in WORKDIR now that wasn't in BASELINE and isn't one of the
# harness's own two artifacts. Empty output means the fence held.
#
# This exists as a second, independent layer behind --disallowedTools: a
# subagent launched via the Agent tool is not guaranteed to inherit the
# parent's disallowed-tools list on every code path, and it can run detached
# in the background past this process's own kill -9 (see the "Agent" denial
# added to --disallowedTools below, and its comment, for the full story).
# Trusting the flag alone is trusting a single point of failure; this catches
# whatever gets through it, by tool name or by mechanism, no matter which.
# ---------------------------------------------------------------------------
fence_violations() {
  local workdir="$1" baseline="$2" out_jsonl="$3" err_log="$4"
  local now
  now="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
  diff <(printf '%s\n' "$baseline") <(printf '%s\n' "$now") 2>/dev/null \
    | sed -n 's/^> //p' \
    | grep -v -F -x -e "$out_jsonl" -e "$err_log" \
    | grep -v '^$'
}

# ---------------------------------------------------------------------------
# run_case NAME PROMPT EXPECTED_REGEX SETUP_FN
# SETUP_FN is a function name invoked with the temp dir as $1, or "" for none.
# ---------------------------------------------------------------------------
# Case selection. Without it, proving one fix means re-running all 28 cases and spending the
# whole allowance to learn about eight of them. Matches install-matrix.sh's convention:
# no arguments runs everything, arguments name the cases to run.
#   tests/auto-trigger.sh                       # all cases
#   tests/auto-trigger.sh prove-it-works-declare-done encode-lessons-lint
SELECTED=("$@")
selected_() {
  [ ${#SELECTED[@]} -eq 0 ] && return 0
  local want
  for want in "${SELECTED[@]}"; do [ "$want" = "$1" ] && return 0; done
  return 1
}

run_case() {
  local name="$1" prompt="$2" expected_regex="$3" setup_fn="$4"
  selected_ "$name" || return 0
  local attempt fired fired_csv matched workdir out_jsonl err_log runner_pid waited
  local baseline violations term_subtype last_fired_csv=""
  local case_turns; case_turns="$(case_max_turns "$name")"

  # Skill dispatch is a model decision, not a deterministic branch, so one sample is a coin
  # flip and a single-shot assertion makes this suite cry wolf. Retry a miss up to $ATTEMPTS
  # times: the property worth protecting is that the situation routes here, not that it does
  # so on the first try. A skill that has genuinely stopped firing misses every attempt.
  for attempt in $(seq 1 "$ATTEMPTS"); do
    workdir="$(mktemp -d "/tmp/auto-trigger-test.XXXXXX")"
    [[ -n "$setup_fn" ]] && "$setup_fn" "$workdir"
    baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
    out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"

    # exec is load-bearing: without it the subshell forks claude as a child, and the
    # timeout's kill -9 hits only the empty parent — leaking a live, billed claude session
    # per timed-out attempt. exec makes $runner_pid BE the claude process.
    (
      cd "$workdir" || exit 1
      # Mutation tools are denied: with bypassPermissions inherited from user settings, a
      # test prompt once wrote a real script into ~/.config/agents/bin. Detection only needs
      # the Skill tool call, which still happens. Agent is denied alongside them: --disallowedTools
      # is not guaranteed to propagate to a subagent spawned via the Agent tool on every code path
      # (see tests/README.md), and a subagent can run detached in the background past this
      # process's own kill -9 -- the only reliable fence is not letting Agent be called at all.
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        claude -p "$prompt" \
          --output-format stream-json --verbose \
          --disallowedTools "Write,Edit,MultiEdit,NotebookEdit,Bash,Agent" \
          --model "$MODEL" --max-turns "$case_turns" \
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
      fired=""; fired_csv="(no output: timeout or crash)"
    else
      fired="$(extract_fired_skills "$out_jsonl")"
      fired_csv="$(echo "$fired" | tr '\n' ',' | sed 's/,$//')"
      if [[ -z "$fired_csv" ]]; then
        # A miss is not one thing. "error_max_turns" means the run was cut off before it
        # ever reached a decision point -- that's a starved case, not a routing failure.
        # Anything else that still didn't fire actually ran to completion and chose not to
        # call Skill, which IS a dispatch signal. Printing both as "(none)" makes the suite
        # report a turn-budget problem as if it were a skill-routing problem.
        term_subtype="$(top_level_subtype "$out_jsonl")"
        if [[ "$term_subtype" == "error_max_turns" ]]; then
          fired_csv="(none: cut off by error_max_turns, never reached a decision)"
        else
          fired_csv="(none: ran to completion, subtype=${term_subtype:-unknown})"
        fi
      fi
    fi

    violations="$(fence_violations "$workdir" "$baseline" "$out_jsonl" "$err_log")"
    rm -rf "$workdir"

    if [[ -n "$violations" ]]; then
      echo "FAIL $name -> fence breach (max-turns=$case_turns): run wrote outside its allowed tools:"
      while IFS= read -r v; do printf '    %s\n' "$v"; done <<< "$violations"
      RESULT_LINES+=("FAIL $name -> fence breach, max-turns=$case_turns (wrote: $(echo "$violations" | tr '\n' ';' | sed 's/;$//'))")
      HIT_LINES+=("$(printf '%-22s FENCE BREACH  -> max-turns=%s, wrote %s' "$name" "$case_turns" "$(echo "$violations" | wc -l | tr -d ' ')file(s)")")
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi

    last_fired_csv="$fired_csv"

    if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($expected_regex)$"; then
      matched="$(echo "$fired" | grep -E "^($expected_regex)$" | head -1)"
      if (( attempt > 1 )); then
        echo "PASS $name -> $matched (on attempt $attempt of $ATTEMPTS, max-turns=$case_turns)"
        RESULT_LINES+=("PASS $name -> $matched (attempt $attempt, max-turns=$case_turns)")
      else
        echo "PASS $name -> $matched (max-turns=$case_turns)"
        RESULT_LINES+=("PASS $name -> $matched (max-turns=$case_turns)")
      fi
      HIT_LINES+=("$(printf '%-22s attempt %s/%s  -> %s (max-turns=%s)' "$name" "$attempt" "$ATTEMPTS" "$matched" "$case_turns")")
      PASS_COUNT=$((PASS_COUNT + 1))
      return
    fi

    (( attempt < ATTEMPTS )) && echo "  retry $name (attempt $attempt, max-turns=$case_turns, fired: [$fired_csv])"
  done

  echo "FAIL $name -> expected $expected_regex, never fired in $ATTEMPTS attempts at max-turns=$case_turns (last: [$last_fired_csv])"
  RESULT_LINES+=("FAIL $name -> expected $expected_regex, $ATTEMPTS attempts, max-turns=$case_turns (last: $last_fired_csv)")
  HIT_LINES+=("$(printf '%-22s never in %s   -> %s (max-turns=%s)' "$name" "$ATTEMPTS" "$last_fired_csv" "$case_turns")")
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Negative control. Every other case asks "did the right skill fire", which cannot see a skill
# that fires on everything — and an over-eager skill actively helps the positive cases pass. One
# sample, no retries: the question is whether it fires at all on a prompt that is plainly not
# its situation.
run_negative_case() {
  local name="$1" prompt="$2" forbidden_regex="$3"
  selected_ "$name" || return 0
  local workdir out_jsonl err_log runner_pid waited fired fired_csv baseline violations
  local case_turns; case_turns="$(case_max_turns "$name")"

  workdir="$(mktemp -d "/tmp/auto-trigger-neg.XXXXXX")"
  baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
  out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"
  (
    cd "$workdir" || exit 1
    exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
      claude -p "$prompt" \
        --output-format stream-json --verbose \
        --disallowedTools "Write,Edit,MultiEdit,NotebookEdit,Bash,Agent" \
        --model "$MODEL" --max-turns "$case_turns" \
        < /dev/null > "$out_jsonl" 2> "$err_log"
  ) &
  runner_pid=$!
  waited=0
  while kill -0 "$runner_pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
  done
  wait "$runner_pid" 2>/dev/null

  fired=""
  [[ -s "$out_jsonl" ]] && fired="$(extract_fired_skills "$out_jsonl")"
  fired_csv="$(echo "$fired" | tr '\n' ',' | sed 's/,$//')"; [[ -z "$fired_csv" ]] && fired_csv="(none)"
  violations="$(fence_violations "$workdir" "$baseline" "$out_jsonl" "$err_log")"
  rm -rf "$workdir"

  if [[ -n "$violations" ]]; then
    echo "FAIL $name -> fence breach (max-turns=$case_turns): run wrote outside its allowed tools:"
    while IFS= read -r v; do printf '    %s\n' "$v"; done <<< "$violations"
    RESULT_LINES+=("FAIL $name -> fence breach, max-turns=$case_turns (wrote: $(echo "$violations" | tr '\n' ';' | sed 's/;$//'))")
    HIT_LINES+=("$(printf '%-22s FENCE BREACH  -> max-turns=%s, wrote %s' "$name" "$case_turns" "$(echo "$violations" | wc -l | tr -d ' ')file(s)")")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($forbidden_regex)$"; then
    echo "FAIL $name -> $forbidden_regex fired on a prompt that is not its situation (max-turns=$case_turns) [$fired_csv]"
    RESULT_LINES+=("FAIL $name -> over-triggered, max-turns=$case_turns")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> fired: %s (max-turns=%s)' "$name" "$fired_csv" "$case_turns")")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS $name -> did not over-trigger (max-turns=$case_turns) [$fired_csv]"
    RESULT_LINES+=("PASS $name -> no over-trigger, max-turns=$case_turns")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> clean (%s) (max-turns=%s)' "$name" "$fired_csv" "$case_turns")")
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup functions: seed the temp working dir so the prompt has something
# concrete to react to (an empty dir gives the model nothing to review).
# ---------------------------------------------------------------------------
setup_readme() {
  local dir="$1"
  cat > "$dir/deploy.sh" <<'EOF'
#!/usr/bin/env bash
# deploy.sh - builds the project and uploads the dist folder to S3
set -euo pipefail
npm run build
aws s3 sync ./dist s3://my-bucket/app --delete
echo "Deploy complete"
EOF
  chmod +x "$dir/deploy.sh"
}

setup_typescript() {
  local dir="$1"
  cat > "$dir/sample.ts" <<'EOF'
export function processData(input: any): any {
  const result: any = input.map((x: any) => x.value);
  return result;
}
EOF
}

setup_webapp() {
  local dir="$1"
  cat > "$dir/package.json" <<'EOF'
{ "name": "notes-app", "version": "1.0.0", "scripts": { "test": "node --test" } }
EOF
  cat > "$dir/app.js" <<'EOF'
const notes = [];
export function addNote(text) { notes.push({ text, at: Date.now() }); }
export function listNotes() { return notes; }
EOF
  cat > "$dir/index.html" <<'EOF'
<!doctype html><html><head><title>Notes</title></head>
<body><ul id="notes"></ul><script type="module" src="app.js"></script></body></html>
EOF
}

setup_messy() {
  local dir="$1"
  mkdir -p "$dir/old" "$dir/tmp"
  for f in draft1 draft2 final final-v2 final-FINAL; do echo "$f" > "$dir/$f.txt"; done
  echo "log" > "$dir/tmp/build.log"; echo "bak" > "$dir/old/app.js.bak"
}

setup_styled() {
  local dir="$1"
  setup_webapp "$dir"
  cat > "$dir/styles.css" <<'EOF'
.hero { padding: 12px 80px 3px 7px; font-size: 15px; color: #888; }
.hero h1 { font-size: 16px; margin: 0 0 2px; }
EOF
}

setup_flaky() {
  local dir="$1"
  cat > "$dir/sync.py" <<'EOF'
import json, urllib.request

def fetch_stats():
    with urllib.request.urlopen("https://api.example.com/stats") as r:
        return json.load(r)

print(fetch_stats()["total"])
EOF
}

# --- Setup functions added for the 14 previously-uncovered skills below. ---

setup_plan() {
  local dir="$1"
  cat > "$dir/PLAN.md" <<'EOF'
# Implementation Plan: Add search to notes app

## Phase 1 - Search index
- Add an in-memory index over note text
- Unit test the index lookup

## Phase 2 - Search UI
- Add a search box to index.html
- Wire it to the index from Phase 1

## Phase 3 - Persistence
- Persist notes and index to localStorage
EOF
}

setup_authdiff() {
  local dir="$1"
  cat > "$dir/auth_middleware.py" <<'EOF'
# auth_middleware.py - verifies a bearer token before allowing a request through
import hmac

SECRET = "dev-secret"

def verify_token(token: str) -> bool:
    expected = hmac.new(SECRET.encode(), b"user", "sha256").hexdigest()
    return token == expected

def handle_request(headers: dict):
    token = headers.get("Authorization", "").replace("Bearer ", "")
    if verify_token(token):
        return {"status": 200}
    return {"status": 401}
EOF
}

setup_stale_verify() {
  local dir="$1"
  setup_webapp "$dir"
  # A feature the verification setup below does not know about -- the drift under test.
  cat > "$dir/search.js" <<'EOF'
export function searchNotes(notes, query) {
  return notes.filter((n) => n.text.includes(query));
}
EOF
  mkdir -p "$dir/.claude/skills/verify-notes-app"
  cat > "$dir/.claude/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
node --test
echo "verify: add-note flow OK"
EOF
  chmod +x "$dir/.claude/verify.sh"
  cat > "$dir/.claude/skills/verify-notes-app/SKILL.md" <<'EOF'
---
name: verify-notes-app
description: Drives the notes app and proves the add-note feature works.
---
# Feature map
- add-note: covered, see verify.sh
EOF
}

setup_draft() {
  local dir="$1"
  cat > "$dir/draft.md" <<'EOF'
In today's fast-paced digital landscape, it is important to note that our new
onboarding flow leverages cutting-edge best practices to seamlessly delight
users. Furthermore, it's worth noting that this represents a significant step
forward in our ongoing journey towards excellence.
EOF
}

setup_bulk() {
  local dir="$1"
  mkdir -p "$dir/modules"
  for f in auth billing search reports export inventory users notifications; do
    cat > "$dir/modules/$f.js" <<EOF
export function $f() { return "$f"; }
EOF
  done
}

setup_gostruct() {
  local dir="$1"
  cat > "$dir/order.go" <<'EOF'
package main

type Order struct {
	Status       string
	TrackingCode string
	CancelReason string
}
EOF
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
echo "Running skill auto-trigger regression suite (model=$MODEL, default max-turns=$MAX_TURNS, per-case timeout=${PER_CASE_TIMEOUT}s)"
echo "Per-case max-turns overrides: prove-it-works-declare-done=$(case_max_turns prove-it-works-declare-done), encode-lessons-lint=$(case_max_turns encode-lessons-lint) (every other case uses the default)"
echo "---"

run_case \
  "readme-writing" \
  "Write a README section explaining what this script does." \
  "technical-writing" \
  "setup_readme"

run_case \
  "typescript-review" \
  "Review this TypeScript file for type safety." \
  "typescript-best-practices" \
  "setup_typescript"

run_case \
  "swarm-audit" \
  "Audit this directory three different ways at once and report back." \
  "swarm" \
  ""

run_case \
  "blast-radius-auth" \
  "I need to ship a risky change to auth, review the blast radius." \
  "blast-radius" \
  ""

# The three-way match is deliberate and stays. This case protects "a feature request routes
# into the planning chain", and any of the three IS the chain — narrowing it to brainstorming
# alone would assert a specific entry point that measures ~50% per attempt, which makes the
# suite flaky rather than strict. A flaky gate gets ignored, and an ignored gate is worse than
# a wide one. The hit-rate table below is what makes erosion here visible instead.
run_case \
  "feature-chain" \
  "I want a dark-mode toggle feature in this notes app. Build it." \
  "brainstorming|writing-plans|test-driven-development" \
  "setup_webapp"

run_case \
  "root-cause-guard" \
  "This script crashes sometimes. Add a try/except around the main call so it stops failing." \
  "principle-fix-root-causes" \
  "setup_flaky"

run_case \
  "overnight-audit-trail" \
  "Clean up and reorganize the files in this directory. You are running unattended overnight - I will step away now and review everything you did tomorrow morning." \
  "show-me-your-work" \
  "setup_messy"

run_case \
  "ui-iterate-styles" \
  "I just edited the hero styles in styles.css and the dev server is running on port 3000. Make sure it actually looks right before we call this done." \
  "ui-iterate" \
  "setup_styled"

# The prompt states the plan is already approved so the planning chain has no reason to fire;
# what is under test is the narrower reflex "about to hand-write a UI component -> check the
# registries first".
run_case \
  "component-registry-combobox" \
  "The plan is approved: this React + Tailwind app gets an accessible multi-select combobox. Write the component now." \
  "component-registry" \
  "setup_webapp"

run_case \
  "idempotent-cron" \
  "Write a cron job that syncs this directory to S3 every hour, with retries on failure." \
  "principle-make-operations-idempotent" \
  ""

run_case \
  "grill-my-plan" \
  "Here is my plan: migrate the whole database in one cutover this Saturday. Poke holes in it before I start — what am I missing?" \
  "grill-me" \
  ""

# Terraform on purpose, and it is worth saying why rather than leaving a bland prompt behind.
#
# The obvious case to write was "Find a skill for reviewing pull requests." It fires 3 of 3 on
# opus and 0 of 3 on sonnet, which is the model this suite pins: sonnet routes it to review-pr,
# because "reviewing pull requests" names a skill that is installed and the request reads as
# asking for the work rather than for the search. Terraform has no competing skill installed, so
# the sentence can only be read as discovery, and it lands 3 of 3 on both.
#
# That is a real limit of description-based dispatch and not one to paper over: where the domain
# in the request collides with an installed skill, the weaker model picks the domain. The
# description leads with DISCOVER or INSTALL for exactly this reason.
run_case \
  "find-a-skill" \
  "What skills exist for working with Terraform? Search for one I can install." \
  "find-skills" \
  ""

# --- Cases added for the 14 skills that previously had zero coverage. ---

run_case \
  "agent-browser-screenshot" \
  "I'm working in a Conductor workspace and need to screenshot this app's dev server on localhost:3000, but the shared Chrome window is already busy with another workspace's session." \
  "agent-browser" \
  "setup_webapp"

# Discriminator: "no automated way to prove it works ... from scratch" states nothing exists
# yet, which is create-verification-skill's situation, not maintain-verification-skill's
# (something exists and has drifted) or principle-prove-it-works' (verify one already-done task).
run_case \
  "create-verification-skill-cold-start" \
  "This webapp has no automated way to prove it works end-to-end -- no test script, no smoke test, nothing that actually launches it and checks a real feature. Set that up from scratch." \
  "create-verification-skill" \
  "setup_webapp"

run_case \
  "executing-plans-checkpoints" \
  "PLAN.md is the implementation plan we approved last session. Execute it, and pause for my review after each phase." \
  "executing-plans" \
  "setup_plan"

run_case \
  "impeccable-polish" \
  "This notes app UI already works and renders fine, but visually it looks like generic default styling. Push the typography, spacing, and motion to a genuinely production, award-winning level." \
  "impeccable" \
  "setup_styled"

# Discriminator: the diff already exists ("already written", "nobody else has reviewed it") and
# the prompt uses interrogate's own trigger phrase "tear this apart" -- grill-me is for a plan or
# design the user is still forming, before anything exists to review.
run_case \
  "interrogate-auth-diff" \
  "This auth middleware change is already written and nobody else has reviewed it. Tear this apart -- find every way it can be broken before we merge." \
  "interrogate" \
  "setup_authdiff"

# Discriminator: verify.sh and a feature map already exist and have drifted from the app
# (a feature was added that the gate/map don't know about) -- maintain-verification-skill's
# situation, not create-verification-skill's "nothing exists yet".
run_case \
  "maintain-verification-skill-drift" \
  "verify.sh here still exits 0, but I added a search feature to this app last week and I don't think the verification skill's feature map or the gate actually exercises it anymore. Bring it back in sync." \
  "maintain-verification-skill" \
  "setup_stale_verify"

run_case \
  "reflect-session" \
  "Before we wrap up -- reflect on this session. I corrected your approach twice today; what should turn into a skill edit so it doesn't happen a third time?" \
  "reflect" \
  ""

run_case \
  "unslop-draft-pass" \
  "The draft in draft.md is done. Do the final pass to cut the AI-sounding phrasing and make it read like a human wrote it." \
  "unslop" \
  "setup_draft"

run_case \
  "boundary-discipline-api" \
  "Wire up input validation and error handling for this API's incoming request body, and make sure the business logic underneath never has to re-check any of it." \
  "principle-boundary-discipline" \
  "setup_webapp"

run_case \
  "build-the-lever-headers" \
  "Every file in modules/ needs the same license header pasted at the top. I'll go through and add it to each one by hand." \
  "principle-build-the-lever" \
  "setup_bulk"

# Discriminator: asks for a structural fix to the repo's own CI (a lint/check), for a correction
# that has already repeated once -- principle-encode-lessons-in-structure's situation. This is
# not "reflect on this session": nothing here asks to mine the transcript or edit a Claude skill.
run_case \
  "encode-lessons-lint" \
  "This is the second time a PR has shipped without a trailing newline at end of file. Add something to CI that catches this automatically -- I don't want to keep telling people by hand." \
  "principle-encode-lessons-in-structure" \
  "setup_webapp"

# Discriminator: declaring one specific, already-attempted fix done on the strength of "it
# compiles" -- principle-prove-it-works' exact situation. Unlike create-verification-skill, this
# is not a request to generate any verify.sh/skill infrastructure, just the habit of checking a
# concrete claim before it's made.
run_case \
  "prove-it-works-declare-done" \
  "I fixed the crash in fetch_stats by adding a retry, and the code compiles cleanly -- this task is done." \
  "principle-prove-it-works" \
  "setup_flaky"

run_case \
  "sequence-verifiable-units-migration" \
  "We're migrating all 12 API endpoints in this service to the new auth middleware across a stack of PRs. How should we order the steps so each one lands in a known-good state before the next starts?" \
  "principle-sequence-verifiable-units" \
  ""

# Go, not TypeScript, on purpose: a .ts file here would compete with typescript-best-practices,
# which also covers type design and is the broader match on that extension. Go has no such
# competing skill installed, so the prompt can only land on the general type-system principle.
run_case \
  "type-system-discipline-go" \
  "Redesign this Go Order struct so an invalid combination like a cancelled order with a tracking code can't compile -- model pending, shipped, and cancelled as separate cases." \
  "principle-type-system-discipline" \
  "setup_gostruct"

run_negative_case \
  "negative-arithmetic" \
  "What is 17 times 23? Just the number." \
  "ui-iterate|impeccable|blast-radius|show-me-your-work|swarm"

run_negative_case \
  "negative-factual" \
  "Which HTTP status code means Payment Required?" \
  "ui-iterate|impeccable|blast-radius|brainstorming|writing-plans"

echo "---"

# A selector that matches no case would otherwise print "0 passed, 0 failed" and exit 0,
# which is the same shape as a clean run. A typo'd case name must not read as a pass.
# This sits above the hit-rate loop because HIT_LINES is unset when nothing ran, and
# `set -u` turns that into a stack trace rather than an answer.
if (( PASS_COUNT + FAIL_COUNT == 0 )); then
  echo "no case ran. ${#SELECTED[@]} selector(s) given, none matched a case name."
  exit 2
fi

echo "Hit rates (which attempt each case landed on):"
for l in "${HIT_LINES[@]}"; do echo "  $l"; done
echo
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
