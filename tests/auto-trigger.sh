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
# run_case NAME PROMPT EXPECTED_REGEX SETUP_FN
# SETUP_FN is a function name invoked with the temp dir as $1, or "" for none.
# ---------------------------------------------------------------------------
run_case() {
  local name="$1" prompt="$2" expected_regex="$3" setup_fn="$4"
  local attempt fired fired_csv matched workdir out_jsonl err_log runner_pid waited

  # Skill dispatch is a model decision, not a deterministic branch, so one sample is a coin
  # flip and a single-shot assertion makes this suite cry wolf. Retry a miss up to $ATTEMPTS
  # times: the property worth protecting is that the situation routes here, not that it does
  # so on the first try. A skill that has genuinely stopped firing misses every attempt.
  for attempt in $(seq 1 "$ATTEMPTS"); do
    workdir="$(mktemp -d "/tmp/auto-trigger-test.XXXXXX")"
    [[ -n "$setup_fn" ]] && "$setup_fn" "$workdir"
    out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"

    # exec is load-bearing: without it the subshell forks claude as a child, and the
    # timeout's kill -9 hits only the empty parent — leaking a live, billed claude session
    # per timed-out attempt. exec makes $runner_pid BE the claude process.
    (
      cd "$workdir" || exit 1
      # Mutation tools are denied: with bypassPermissions inherited from user settings, a
      # test prompt once wrote a real script into ~/.config/agents/bin. Detection only needs
      # the Skill tool call, which still happens.
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
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
      fired=""; fired_csv="(no output: timeout or crash)"
    else
      fired="$(extract_fired_skills "$out_jsonl")"
      fired_csv="$(echo "$fired" | tr '\n' ',' | sed 's/,$//')"
      [[ -z "$fired_csv" ]] && fired_csv="(none)"
    fi
    rm -rf "$workdir"

    if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($expected_regex)$"; then
      matched="$(echo "$fired" | grep -E "^($expected_regex)$" | head -1)"
      if (( attempt > 1 )); then
        echo "PASS $name -> $matched (on attempt $attempt of $ATTEMPTS)"
        RESULT_LINES+=("PASS $name -> $matched (attempt $attempt)")
      else
        echo "PASS $name -> $matched"
        RESULT_LINES+=("PASS $name -> $matched")
      fi
      HIT_LINES+=("$(printf '%-22s attempt %s/%s  -> %s' "$name" "$attempt" "$ATTEMPTS" "$matched")")
      PASS_COUNT=$((PASS_COUNT + 1))
      return
    fi

    (( attempt < ATTEMPTS )) && echo "  retry $name (attempt $attempt fired: [$fired_csv])"
  done

  echo "FAIL $name -> expected $expected_regex, never fired in $ATTEMPTS attempts (last: [$fired_csv])"
  RESULT_LINES+=("FAIL $name -> expected $expected_regex, $ATTEMPTS attempts")
  HIT_LINES+=("$(printf '%-22s never in %s   -> (none)' "$name" "$ATTEMPTS")")
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Negative control. Every other case asks "did the right skill fire", which cannot see a skill
# that fires on everything — and an over-eager skill actively helps the positive cases pass. One
# sample, no retries: the question is whether it fires at all on a prompt that is plainly not
# its situation.
run_negative_case() {
  local name="$1" prompt="$2" forbidden_regex="$3"
  local workdir out_jsonl err_log runner_pid waited fired fired_csv

  workdir="$(mktemp -d "/tmp/auto-trigger-neg.XXXXXX")"
  out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"
  (
    cd "$workdir" || exit 1
    exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
      claude -p "$prompt" \
        --output-format stream-json --verbose \
        --disallowedTools "Write,Edit,MultiEdit,NotebookEdit,Bash" \
        --model "$MODEL" --max-turns "$MAX_TURNS" \
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
  rm -rf "$workdir"

  if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($forbidden_regex)$"; then
    echo "FAIL $name -> $forbidden_regex fired on a prompt that is not its situation [$fired_csv]"
    RESULT_LINES+=("FAIL $name -> over-triggered")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> fired: %s' "$name" "$fired_csv")")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS $name -> did not over-trigger [$fired_csv]"
    RESULT_LINES+=("PASS $name -> no over-trigger")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> clean (%s)' "$name" "$fired_csv")")
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

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
echo "Running skill auto-trigger regression suite (model=$MODEL, max-turns=$MAX_TURNS, per-case timeout=${PER_CASE_TIMEOUT}s)"
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

run_negative_case \
  "negative-arithmetic" \
  "What is 17 times 23? Just the number." \
  "ui-iterate|impeccable|blast-radius|show-me-your-work|swarm"

run_negative_case \
  "negative-factual" \
  "Which HTTP status code means Payment Required?" \
  "ui-iterate|impeccable|blast-radius|brainstorming|writing-plans"

echo "---"
echo "Hit rates (which attempt each case landed on):"
for l in "${HIT_LINES[@]}"; do echo "  $l"; done
echo
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
