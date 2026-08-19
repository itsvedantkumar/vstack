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

PER_CASE_TIMEOUT=120   # seconds; macOS has no `timeout(1)`, see run_with_timeout()
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

# ---------------------------------------------------------------------------
# Preflight: skip (exit 0) rather than fail if claude isn't usable here.
# CI cannot authenticate headlessly, so absence of `claude` or a session is
# an expected, non-failing condition -- not a broken test.
# ---------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: 'claude' CLI not found on PATH. Cannot run auto-trigger regression test."
  exit 0
fi

AUTH_JSON="$(claude auth status 2>/dev/null)"
if [[ -z "$AUTH_JSON" ]] || ! echo "$AUTH_JSON" | grep -q '"loggedIn": *true'; then
  echo "SKIP: 'claude' CLI is not authenticated (claude auth status did not report loggedIn: true)."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: 'jq' not found on PATH; required to parse stream-json output."
  exit 0
fi

# ---------------------------------------------------------------------------
# run_with_timeout SECONDS -- CMD...
# macOS ships no timeout(1). Background the command, race it against a
# sleeping watcher, kill whichever loses. Returns the command's exit status,
# or 124 if the watcher won (timeout).
# ---------------------------------------------------------------------------
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local cmd_pid=$!
  (
    sleep "$secs"
    kill -9 "$cmd_pid" 2>/dev/null
  ) &
  local watcher_pid=$!

  local status
  if wait "$cmd_pid" 2>/dev/null; then
    status=0
  else
    status=$?
  fi

  # Watcher is still around unless it already fired; either way, reap it.
  kill "$watcher_pid" 2>/dev/null
  wait "$watcher_pid" 2>/dev/null

  return "$status"
}

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

    (
      cd "$workdir" && \
      env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        claude -p "$prompt" \
          --output-format stream-json --verbose \
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
      PASS_COUNT=$((PASS_COUNT + 1))
      return
    fi

    (( attempt < ATTEMPTS )) && echo "  retry $name (attempt $attempt fired: [$fired_csv])"
  done

  echo "FAIL $name -> expected $expected_regex, never fired in $ATTEMPTS attempts (last: [$fired_csv])"
  RESULT_LINES+=("FAIL $name -> expected $expected_regex, $ATTEMPTS attempts")
  FAIL_COUNT=$((FAIL_COUNT + 1))
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
  "technical-writing|unslop" \
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
  "blast-radius|interrogate" \
  ""

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

run_case \
  "idempotent-cron" \
  "Write a cron job that syncs this directory to S3 every hour, with retries on failure." \
  "principle-make-operations-idempotent" \
  ""

echo "---"
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
