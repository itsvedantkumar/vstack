#!/usr/bin/env bash
# build-the-lever/run.sh -- why does principle-build-the-lever not dispatch?
#
# Metric, arms, thresholds and invalidation conditions were registered in PREREGISTRATION.md
# before the first call. Read that first. Nothing here may be tuned after seeing a number; if a
# threshold needs to change, the run restarts.
#
# One SAMPLE is one raw, non-retrying `claude -p` invocation. There is no ATTEMPTS-style retry
# loop, for the reason tests/auto-trigger.sh's header derives at length: a stop-at-first-hit loop
# measures "did it ever fire", not a rate.
#
# Per sample this records the FULL set of Skill names fired (not a boolean -- that is what settles
# H10 for free and captures a miss mode this repo has not recorded since the 1.35.0 prefix fix),
# every ToolSearch call (Stage 0 found this build defers tools behind it and auto-trigger.sh does
# not deny it), result.subtype, num_turns, prompt char count, and any fence violation.
set -uo pipefail
N=${N:-10}
ARMS=${ARMS:-"A0 A1 A5"}
TIMEOUT=120
OUT=${OUT:-/tmp/btl-stage1}
mkdir -p "$OUT"
TSV="$OUT/samples.tsv"
[ -s "$TSV" ] || printf 'arm\tsample\tsubtype\tnum_turns\tprompt_chars\ttoolsearch\tfired\tfence\n' > "$TSV"

DEFAULT_DENY="Write,Edit,MultiEdit,NotebookEdit,Bash,Agent"
A5_DENY="Edit,MultiEdit,NotebookEdit,Bash,Agent"   # Write permitted: that IS the manipulation
# A2R: the H8 re-run. Same prompt and fixture as A2, budget 3->20 (A2 peaked at num_turns=24) and
# ToolSearch denied. Two variables move together on purpose -- this is a re-read of a void arm
# under conditions that remove the documented cause of the void, not a clean single-variable
# ablation of ToolSearch, and the pre-registration says so.
A2R_DENY="ToolSearch,Write,Edit,MultiEdit,NotebookEdit,Bash,Agent"

P_A0="This script crashes sometimes. Add a try/except around the main call so it stops failing."
P_A1="Every file in modules/ needs the same license header pasted at the top. I'll go through and add it to each one by hand."
P_A2="Add the same license header to the top of every file in modules/."
P_A3="What's the best way to get the same license header onto every file in modules/?"

setup_flaky() {
  local d="$1"
  cat > "$d/sync.py" <<'PY'
import json, urllib.request

def fetch_stats():
    with urllib.request.urlopen("https://api.example.com/stats") as r:
        return json.load(r)

print(fetch_stats()["total"])
PY
}
setup_bulk() {
  # Every variable here is local and prefixed. The outer sample loop owns `arm` and `i`; a
  # setup function that reuses either silently renames its own output. That is not a
  # hypothetical: `setup_bulk60`'s `for i in $(seq 1 60)` clobbered the sample counter on the
  # first Stage 1 run and overwrote 9 of 10 A4 transcripts into one filename. The k/n survived
  # because it is written to the TSV before the copy, but the evidence did not.
  local _d="$1" _bf
  mkdir -p "$_d/modules"
  for _bf in auth billing search reports export inventory users notifications; do
    printf 'export function %s() { return "%s"; }\n' "$_bf" "$_bf" > "$_d/modules/$_bf.js"
  done
}
setup_bulk60() {
  local _d="$1" _n
  mkdir -p "$_d/modules"
  for _n in $(seq 1 60); do
    printf 'export function mod%02d() { return "mod%02d"; }\n' "$_n" "$_n" \
      > "$_d/modules/mod$(printf '%02d' "$_n").js"
  done
}

arm_cfg() { # arm -> prompt|setup|deny|turns
  case "$1" in
    A0) printf '%s\t%s\t%s\t%s' "$P_A0" setup_flaky   "$DEFAULT_DENY" 3  ;;
    A1) printf '%s\t%s\t%s\t%s' "$P_A1" setup_bulk    "$DEFAULT_DENY" 10 ;;
    A2) printf '%s\t%s\t%s\t%s' "$P_A2" setup_bulk    "$DEFAULT_DENY" 10 ;;
    A3) printf '%s\t%s\t%s\t%s' "$P_A3" setup_bulk    "$DEFAULT_DENY" 10 ;;
    A4) printf '%s\t%s\t%s\t%s' "$P_A1" setup_bulk60  "$DEFAULT_DENY" 10 ;;
    A5)  printf '%s\t%s\t%s\t%s' "$P_A1" setup_bulk    "$A5_DENY"      10 ;;
    A2R) printf '%s\t%s\t%s\t%s' "$P_A2" setup_bulk    "$A2R_DENY"     20 ;;
  esac
}

for arm in $ARMS; do
  IFS=$'\t' read -r prompt setup deny turns <<< "$(arm_cfg "$arm")"
  for i in $(seq 1 "$N"); do
    wd="$(mktemp -d "/tmp/btl.$arm.XXXXXX")"
    "$setup" "$wd"
    base="$(find "$wd" -mindepth 1 2>/dev/null | sort)"
    oj="$wd/.out.jsonl"; el="$wd/.err.log"
    (
      cd "$wd" || exit 1
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        claude -p "$prompt" --output-format stream-json --verbose \
          --disallowedTools "$deny" --model sonnet --max-turns "$turns" \
          < /dev/null > "$oj" 2> "$el"
    ) &
    pid=$!; w=0
    while kill -0 "$pid" 2>/dev/null; do sleep 1; w=$((w+1)); [ "$w" -ge "$TIMEOUT" ] && { kill -9 "$pid" 2>/dev/null; break; }; done
    wait "$pid" 2>/dev/null

    fired="$(jq -r 'select(.type=="assistant")|(.message.content//[])[]|select(.type=="tool_use" and .name=="Skill")|(.input.skill // "unknown")' "$oj" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')"
    [ -z "$fired" ] && fired="(none)"
    ts="$(jq -r 'select(.type=="assistant")|(.message.content//[])[]|select(.type=="tool_use" and .name=="ToolSearch")|.name' "$oj" 2>/dev/null | wc -l | tr -d ' ')"
    sub="$(jq -r 'select(.type=="result" and (.origin==null))|.subtype' "$oj" 2>/dev/null | tail -1)"
    nt="$(jq -r 'select(.type=="result" and (.origin==null))|.num_turns' "$oj" 2>/dev/null | tail -1)"
    now="$(find "$wd" -mindepth 1 2>/dev/null | sort)"
    fence="$(diff <(printf '%s\n' "$base") <(printf '%s\n' "$now") 2>/dev/null | sed -n 's/^> //p' | grep -v -F -x -e "$oj" -e "$el" | grep -v '^$' | tr '\n' ';' | sed 's/;$//')"
    [ -z "$fence" ] && fence="-"
    cp "$oj" "$OUT/$arm.$i.jsonl" 2>/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$arm" "$i" "${sub:-unknown}" "${nt:-?}" "${#prompt}" "$ts" "$fired" "$fence" >> "$TSV"
    rm -rf "$wd"
  done
done
echo "DONE $ARMS"
