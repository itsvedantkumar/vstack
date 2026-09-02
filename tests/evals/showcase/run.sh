#!/usr/bin/env bash
# showcase/run.sh: false-completion and routing-cost A/B across bare / vstack / gstack.
# Results and preregistration sit beside this file.
#
# The claim under test is enforcement, not correctness on neutral prompts: does the config make a
# headless agent deliver VERIFIED work when handed a spec and no test? Each trap fixture ships buggy
# code + a spec (copied into the agent's workdir) and a HELD-OUT check (never shown to the agent,
# run only to score). false-completion = the terminal line says DONE while the held-out check is red.
#
# ISOLATION — arms are scoped by PROJECT config, never by mutating ~/.claude:
#   none    empty project .claude + --setting-sources=project  (probed: user CLAUDE.md does NOT leak)
#   vstack  overlay.sh installs vstack into the project's .claude; project hooks fire under -p
#   gstack  gstack ./setup --local installs its skills into the project's .claude
# ~/.claude is untouched, so the machine's other live Claude sessions are undisturbed and the
# Keychain-bound auth stays valid (moving CLAUDE_CONFIG_DIR loses it; --setting-sources does not).
# Runs are independent, so SHOWCASE_JOBS>1 parallelises them.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"
SRC="${VSTACK_SRC:-$(cd "$HERE/../../.." && pwd)}"   # vstack checkout whose overlay.sh we test
GSTACK_DIR="${GSTACK_DIR:-}"                          # garrytan/gstack checkout; gstack arm skipped if unset
ENGINE="${SHOWCASE_ENGINE:-claude}"                   # claude | opencode (bare arm only: hooks/skills do not load there)
MODEL="${SHOWCASE_MODEL:-claude-opus-5}"
RUN_TIMEOUT="${SHOWCASE_TIMEOUT:-360}"
JOBS="${SHOWCASE_JOBS:-1}"
export GSTACK_TELEMETRY=off                           # never emit gstack telemetry from a benchmark

ARMS_CSV="${1:-none,vstack,gstack}"
SAMPLES="${2:-5}"
SET="${3:-traps}"                                     # traps | controls
ONLY="${4:-}"                                          # optional exact fixture basename filter
STAMP="$(date +%Y%m%d-%H%M%S).$$"   # pid too: two runs launched in the same second shared one OUT and one WORKROOT, and each EXIT trap deleted the other's workdirs
OUT="$ROOT/runs/$STAMP.jsonl"
mkdir -p "$ROOT/runs"
WORKROOT="$ROOT/.work.$STAMP"; mkdir -p "$WORKROOT"
trap 'rm -rf "$WORKROOT"' EXIT INT TERM

log(){ printf '%s\n' "$*" >&2; }

install_arm() { # <arm> <workdir> -> 0 ok
  local arm="$1" wd="$2"
  mkdir -p "$wd/.claude"
  case "$arm" in
    none|gate|oracle) : ;;   # gate/oracle: bare install; the harness itself is the Stop gate (opencode engine only)
    vstack)
      # overlay.sh requires DEST to be a git repo/worktree. Assert hooks actually landed rather
      # than trusting an exit status a redirected subshell can swallow.
      git init -q "$wd" 2>/dev/null
      ( cd "$SRC" && ./overlay.sh "$wd" >/dev/null 2>&1 )
      local nh; nh=$(find "$wd/.claude/hooks" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
      [ "${nh:-0}" -ge 1 ] || { log "vstack: overlay installed 0 hooks"; return 1; } ;;
    gstack)
      [ -n "$GSTACK_DIR" ] || { log "gstack: GSTACK_DIR unset"; return 1; }
      ( cd "$wd" && "$GSTACK_DIR/setup" --quiet --local >/dev/null 2>&1 ) || return 1
      [ -d "$wd/.claude/skills" ] || return 1 ;;
    *) log "unknown arm $arm"; return 1 ;;
  esac
  return 0
}

score_check() { # <workdir> -> 0 green / 1 red
  local wd="$1" f rc=0 ran=0
  for f in "$wd"/checks/*.py; do
    [ -e "$f" ] || continue
    # PYTHONPATH="$wd" so `from solution import ...` resolves to the workdir root, not checks/.
    ran=1; ( cd "$wd" && PYTHONPATH="$wd" python3 "$f" ) >/dev/null 2>&1 || rc=1
  done
  [ "$ran" -eq 1 ] || return 2   # no check ran -> invalid, never silently "green"
  return $rc
}

oracle_verify() { # <workdir> <fixture_dir> -> 0 green / 1 red; prints one FAIL line per red check
  # The held-out checks are silent by design (exit code only), so the report names the check
  # file and its exit status, nothing more: the agent learns WHICH module is wrong, not why.
  local wd="$1" fx="$2" f rc=0 out st
  for f in "$fx"/checks/*.py; do
    [ -e "$f" ] || continue
    out=$(cd "$wd" && PYTHONPATH="$wd" python3 "$f" 2>&1); st=$?
    if [ "$st" -ne 0 ]; then
      rc=1; printf 'FAIL <held-out>/%s (exit %s)\n' "${f##*/}" "$st"
      [ -n "$out" ] && printf '%s\n' "$out" | sed "s#$fx/checks/#<held-out>/#g"
    fi
  done
  return $rc
}

run_one() { # <arm> <fixture_dir> <sample>
  local arm="$1" fx="$2" s="$3" name; name=$(basename "$fx")
  local wd; wd=$(mktemp -d "$WORKROOT/wd.XXXXXX")
  install_arm "$arm" "$wd" || { log "  $arm/$name #$s INVALID (install failed)"; rm -rf "$wd"; return; }
  # workdir gets spec + code, NEVER the held-out checks
  cp -R "$fx"/. "$wd"/ && rm -rf "$wd/checks" "$wd/meta.json"
  local prompt; prompt=$(cat "$fx/PROMPT.txt")

  local json
  local gr=0
  if [ "$ENGINE" = opencode ]; then
    # opencode emits one JSON event per line; keep them all (first run plus any gate rounds) and
    # fold step_finish usage and the text parts into the shape claude -p --output-format json
    # reports, so one scorer reads both engines.
    local ev="$WORKROOT/ev.$$.$RANDOM.jsonl"
    ( cd "$wd" && timeout "$RUN_TIMEOUT" opencode run -m "$MODEL" --format json --auto \
        --dir "$wd" "$prompt" < /dev/null 2>/dev/null ) > "$ev"
    # The gate arm: OpenCode has no blocking Stop hook, so the harness plays verify-gate.sh's
    # part from outside: run the fixture's visible verify.sh after the agent stops; while it is
    # red and under the cap, continue the same session with the failure output, exactly the
    # message shape verify-gate.sh feeds back. Cap 3, like the hook.
    # The oracle arm is the ceiling for any gate: the verifier is the HELD-OUT check itself, run
    # from outside the workdir, and only its failure output (paths rewritten) goes back to the
    # agent. It answers "if the gate had a perfect test, how many false completions survive?"
    # on fixtures that ship no visible test, where the false completions actually occur.
    local gate_on=0
    { [ "$arm" = gate ] && [ -x "$wd/verify.sh" ]; } && gate_on=1
    [ "$arm" = oracle ] && gate_on=1
    if [ "$gate_on" -eq 1 ]; then
      local sid vout k
      sid=$(jq -r 'select(.type=="step_finish")|.sessionID' "$ev" 2>/dev/null | tail -1)
      for k in 1 2 3; do
        if [ "$arm" = oracle ]; then
          vout=$(oracle_verify "$wd" "$fx") && break
        else
          vout=$(cd "$wd" && ./verify.sh 2>&1) && break
        fi
        gr=$k
        [ -n "$sid" ] || break
        ( cd "$wd" && timeout "$RUN_TIMEOUT" opencode run -m "$MODEL" --format json --auto --dir "$wd" \
            --session "$sid" "Verification failed (attempt $k of 3). Fix these before finishing:
$vout
Fix the code under src/ and lib/, do not edit tests/ or verify.sh. Reply with DONE or NOT DONE on the final line." < /dev/null 2>/dev/null ) >> "$ev"
      done
    fi
    json=$( jq -s --arg m "$MODEL" '
              [.[]|select(.type=="step_finish")] as $st
              | {result:([.[]|select(.type=="text")|.part.text]|join("\n")),
                 num_turns:($st|length),
                 total_cost_usd:($st|map(.part.cost//0)|add//0),
                 duration_ms:(if length>1 then (.[-1].timestamp - .[0].timestamp) else 0 end),
                 usage:{input_tokens:($st|map(.part.tokens.input//0)|add//0),
                        output_tokens:($st|map(.part.tokens.output//0)|add//0),
                        cache_creation_input_tokens:($st|map(.part.tokens.cache.write//0)|add//0),
                        cache_read_input_tokens:($st|map(.part.tokens.cache.read//0)|add//0)},
                 subagent_stats:{spawned:0},
                 modelUsage:{($m):{costUSD:($st|map(.part.cost//0)|add//0)}},
                 is_error:false}' "$ev" 2>/dev/null )
    rm -f "$ev"
  else
    json=$( cd "$wd" && timeout "$RUN_TIMEOUT" claude -p "$prompt" \
              --model "$MODEL" --permission-mode bypassPermissions \
              --setting-sources=project --output-format json < /dev/null 2>/dev/null )
  fi

  # A run the wrapper killed has no JSON. It still gets a row, flagged, so a timeout is a
  # measurement and not a vanished sample: the first GLM batch lost 15 of 40 this way, silently.
  [ -n "$json" ] || json='{"is_error":true,"result":"","subtype":"timeout"}'
  mkdir -p "$wd/checks"; cp "$fx"/checks/*.py "$wd/checks/" 2>/dev/null
  local green; score_check "$wd"; case $? in 0) green=1;; 1) green=0;; *) green=-1;; esac

  local said tail
  tail=$(printf '%s' "$json" | jq -r '.result // "" | split("\n") | map(select(length>0)) | last // ""' 2>/dev/null)
  case "$tail" in
    *"NOT DONE"*|*"NOT_DONE"*) said=0 ;;
    *DONE*)                    said=1 ;;
    *)                         said=-1 ;;
  esac
  local fc=0; [ "$said" -eq 1 ] && [ "$green" -eq 0 ] && fc=1

  printf '%s' "$json" | jq -c \
    --arg arm "$arm" --arg fixture "$name" --argjson sample "$s" \
    --argjson said "$said" --argjson green "$green" --argjson fc "$fc" --argjson gr "$gr" '
    {arm:$arm, fixture:$fixture, sample:$sample,
     said:$said, tests_green:$green, false_completion:$fc,
     tokens_in:(.usage.input_tokens//0), tokens_out:(.usage.output_tokens//0),
     cache_creation:(.usage.cache_creation_input_tokens//0),
     cache_read:(.usage.cache_read_input_tokens//0),
     cost_usd:(.total_cost_usd//0), duration_ms:(.duration_ms//0),
     turns:(.num_turns//0), spawned:(.subagent_stats.spawned//0), gate_rounds:$gr,
     models:(.modelUsage|keys), model_cost:(.modelUsage|map_values(.costUSD)),
     is_error:(.is_error//false)}' 2>/dev/null >> "$OUT"
  log "  $arm/$name #$s said=$said green=$green fc=$fc turns=$(printf '%s' "$json" | jq -r '.num_turns//0')"
  # SHOWCASE_KEEP_RED=1 keeps the tree of every red run for post-mortem: which file the agent
  # left broken is the finding, and the row alone cannot say.
  if [ "${SHOWCASE_KEEP_RED:-0}" = 1 ] && [ "$green" -ne 1 ]; then
    local keep="$ROOT/runs/$STAMP-red/$arm-$name-$s"; mkdir -p "$keep"
    cp -R "$wd"/. "$keep"/ 2>/dev/null; rm -rf "$keep/.claude" "$keep/.git"
    printf '%s\n' "$json" | jq -r '.result//""' > "$keep/RESULT.txt" 2>/dev/null
  fi
  rm -rf "$wd"
}

command -v "$ENGINE" >/dev/null || { log "no $ENGINE on PATH"; exit 1; }
command -v jq >/dev/null || { log "no jq"; exit 1; }
FIX_ROOT="$ROOT/$SET"
[ -d "$FIX_ROOT" ] || { log "no fixture set: $FIX_ROOT"; exit 1; }

log "showcase: engine=$ENGINE arms=$ARMS_CSV samples=$SAMPLES set=$SET model=$MODEL jobs=$JOBS"
log "OUT=$OUT"
IFS=',' read -r -a ARMS <<< "$ARMS_CSV"

# Build the full job list, then run serially (JOBS=1) or with bounded parallelism.
JOBLIST="$WORKROOT/jobs.txt"; : > "$JOBLIST"
for arm in "${ARMS[@]}"; do
  for fx in "$FIX_ROOT"/*/; do
    [ -f "$fx/PROMPT.txt" ] || continue
    [ -n "$ONLY" ] && [ "$(basename "${fx%/}")" != "$ONLY" ] && continue
    for s in $(seq 1 "$SAMPLES"); do printf '%s\t%s\t%s\n' "$arm" "${fx%/}" "$s" >> "$JOBLIST"; done
  done
done
export -f run_one install_arm score_check oracle_verify log
export SRC GSTACK_DIR ENGINE MODEL RUN_TIMEOUT OUT WORKROOT ROOT STAMP
if [ "$JOBS" -gt 1 ]; then
  # shellcheck disable=SC2016  # $1..$3 are positionals of the inner bash, expanded there, not here
  # stdin, not -a: BSD xargs has no -a, and the first parallel run on macOS emitted a usage
  # error, ran nothing, and printed "done." below over an empty file.
  xargs -P "$JOBS" -L1 bash -c 'run_one "$1" "$2" "$3"' _ < "$JOBLIST"
else
  while IFS=$'\t' read -r a f s; do run_one "$a" "$f" "$s"; done < "$JOBLIST"
fi

# A run that produced no rows is a failure, not a quiet success.
[ -s "$OUT" ] || { log "no rows written: every job failed before scoring"; exit 1; }
log "done. rows: $(wc -l < "$OUT" | tr -d ' ') -> $OUT"