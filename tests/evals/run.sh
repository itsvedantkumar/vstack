#!/usr/bin/env bash
# run.sh — a head-to-head review benchmark across Claude Code skill configurations.
#
# Everything else in this repo measures mechanisms: does the gate block, does the guard deny,
# does the right skill fire. All of that can be true while the review a configuration produces is
# no better than the one you get without it. This is the test that can embarrass the project,
# which is the only reason it is worth writing.
#
# DESIGN. Each fixture has defects deliberately planted in it and decoys that look suspicious and
# are correct. The identical prompt is sent under each arm. Every arm runs
# `--setting-sources=project` and receives its skills the same way — copied into the fixture's
# own `.claude/skills/` — so the only variable between arms is WHICH skills are present, not how
# they are loaded, and not whether the CLI is authenticated.
#
#   none    Claude Code and its built-in skills. What you have before installing anything.
#   vstack  this repository's skills, on top of the built-ins.
#   gstack  github.com/garrytan/gstack's skills, on top of the built-ins. Set GSTACK_DIR.
#
# Findings come back as JSON with line numbers, so scoring is arithmetic rather than judgement.
#
# BOTH NUMBERS MATTER.
#   recall     planted defects found. A reviewer that misses the injection is useless.
#   precision  decoys and clean files left alone. A reviewer that flags everything has perfect
#              recall and is also useless, and over-eagerness is the likelier failure of a
#              capable model. clean.py has nothing planted, so any finding there is a false
#              positive — the only unambiguous precision measurement in the set.
#
# VALIDITY. Each run records which skills the session actually loaded, from the CLI's own init
# event, and how many times a Skill tool was invoked. An arm that was supposed to load a harness
# and did not is reported as INVALID rather than scored, because a broken arm always fails in the
# author's favour and does it silently: a zero looks like a finding.
#
# Two real examples from building this, both of which produced flattering nonsense before being
# caught. Pointing CLAUDE_CONFIG_DIR at an empty directory removes authentication along with the
# config, so every baseline run returned "Not logged in" and scored zero against a vstack arm
# that worked. And omitting `< /dev/null` makes the CLI wait for stdin, warn, and truncate.
#
# WHAT THIS CANNOT SHOW. That one configuration is better in general. A handful of small Python
# files and a few samples is a pilot, not a result. Quote the sample count with any number taken
# from here, and do not read a one- or two-defect gap as a difference.
#
# Usage:
#   tests/evals/run.sh [--samples N] [--arms none,vstack,gstack] [--json]
#   GSTACK_DIR=/path/to/gstack tests/evals/run.sh --arms none,vstack,gstack --samples 5

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SRC=$(pwd)
FIX="$SRC/tests/evals/fixtures"
GT="$SRC/tests/evals/ground-truth.json"

SAMPLES=1
ARMS_CSV="none,vstack"
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --samples) SAMPLES="$2"; shift 2 ;;
    --arms)    ARMS_CSV="$2"; shift 2 ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "evals need jq"; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "SKIP: the claude CLI is not installed"; exit 0; }

GSTACK_DIR="${GSTACK_DIR:-}"
case "$ARMS_CSV" in
  *gstack*)
    if [ -z "$GSTACK_DIR" ] || [ ! -d "$GSTACK_DIR" ]; then
      echo "note: dropping the gstack arm — set GSTACK_DIR to a gstack checkout to include it" >&2
      ARMS_CSV=$(printf '%s' "$ARMS_CSV" | sed 's/gstack//; s/,,/,/g; s/^,//; s/,$//')
    fi ;;
esac

ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-evals.XXXXXX")" && pwd)
trap 'rm -rf "$ROOT"' EXIT
TOL=$(jq -r '.tolerance' "$GT")

# Identical for every arm, and deliberately neutral: it does not name a skill, a defect class, or
# hint that anything is wrong. "Find the SQL injection" would measure instruction-following.
read -r -d '' PROMPT <<'EOF' || true
Review the Python file in this directory for defects.

Report ONLY genuine defects: a bug, a security problem, or a resource-handling error that would
actually bite in production. Do not report style, naming, typing, documentation, or preference.
If the file is correct, report nothing.

Output ONLY a JSON array, no prose before or after, in exactly this shape:
[{"line": <integer>, "category": "security|correctness|resource-leak", "summary": "<one sentence>"}]
An empty array is a valid and sometimes correct answer.
EOF

# Populate a workdir with the fixture and the arm's skills, then run one review.
# Emits: <findings-json>TAB<loaded-skill-count>TAB<skill-invocations>
review() { # <fixture> <arm> <workdir>
  local f="$1" arm="$2" wd="$3" sk
  sk="$wd/.claude/skills"
  mkdir -p "$sk"
  cp "$FIX/$f" "$wd/"
  case "$arm" in
    none) : ;;
    vstack)
      for d in "$SRC"/claude/skills/*/; do [ -d "$d" ] && cp -R "${d%/}" "$sk/"; done ;;
    gstack)
      # gstack keeps one skill per top-level directory, each with its own SKILL.md.
      find "$GSTACK_DIR" -maxdepth 2 -name SKILL.md 2>/dev/null | while IFS= read -r m; do
        n=$(basename "$(dirname "$m")")
        mkdir -p "$sk/$n" && cp "$m" "$sk/$n/SKILL.md"
      done ;;
  esac
  local raw text loaded fired
  raw=$( cd "$wd" && timeout 240 claude -p "$PROMPT" --setting-sources=project \
           --output-format=stream-json --verbose < /dev/null 2>/dev/null )
  text=$(printf '%s' "$raw" | jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text]|join("")' 2>/dev/null)
  loaded=$(printf '%s' "$raw" | jq -rs '[.[]|select(.subtype=="init")|.skills[]?]|length' 2>/dev/null)
  fired=$(printf '%s' "$raw" | jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="tool_use" and .name=="Skill")]|length' 2>/dev/null)
  printf '%s\t%s\t%s' "$(printf '%s' "$text" | sed -n 's/.*\(\[.*\]\).*/\1/p' | head -1)" "${loaded:-0}" "${fired:-0}"
}

score() { # <fixture> <findings-json> -> {hits,planted,fp}
  local f="$1" found="$2"
  [ -n "$found" ] || found='[]'
  printf '%s' "$found" | jq -e . >/dev/null 2>&1 || found='[]'
  jq -n --argjson g "$(jq --arg f "$f" '.fixtures[]|select(.file==$f)' "$GT")" \
        --argjson found "$found" --argjson tol "$TOL" '
    ($g.planted // []) as $p
    | { hits:    ([ $p[] | . as $pl | select(($found|map(select(((.line-$pl.line)|fabs)<=$tol))|length)>0) ]|length),
        planted: ($p|length),
        fp:      ([ $found[] | . as $fd | select(($p|map(select(((($fd.line)-.line)|fabs)<=$tol))|length)==0) ]|length) }' \
    2>/dev/null || echo '{"hits":0,"planted":0,"fp":0}'
}

ARMS=$(printf '%s' "$ARMS_CSV" | tr ',' ' ')
RESULTS=""
NFIX=$(jq -r '.fixtures|length' "$GT")

for a in $ARMS; do
  ah=0; ap=0; afp=0; aload=0; afire=0; runs=0
  for f in $(jq -r '.fixtures[].file' "$GT"); do
    for s in $(seq 1 "$SAMPLES"); do
      line=$(review "$f" "$a" "$ROOT/$a-${f%.py}-$s")
      out=$(printf '%s' "$line" | cut -f1)
      loaded=$(printf '%s' "$line" | cut -f2)
      fired=$(printf '%s' "$line" | cut -f3)
      sc=$(score "$f" "$out")
      ah=$((ah + $(printf '%s' "$sc" | jq -r '.hits')))
      ap=$((ap + $(printf '%s' "$sc" | jq -r '.planted')))
      afp=$((afp + $(printf '%s' "$sc" | jq -r '.fp')))
      aload=$((aload + ${loaded:-0})); afire=$((afire + ${fired:-0})); runs=$((runs+1))
    done
  done
  [ "$runs" -gt 0 ] || runs=1
  RESULTS="$RESULTS$a|$ah|$ap|$afp|$((aload / runs))|$afire
"
done

if [ "$JSON" = 1 ]; then
  printf '%s' "$RESULTS" | jq -Rs --argjson n "$SAMPLES" --argjson fx "$NFIX" \
    'split("\n")|map(select(length>0))|map(split("|"))
     |map({arm:.[0],found:(.[1]|tonumber),planted:(.[2]|tonumber),false_positives:(.[3]|tonumber),
           skills_loaded_avg:(.[4]|tonumber),skill_invocations:(.[5]|tonumber),
           samples_per_fixture:$n,fixtures:$fx})'
  exit 0
fi

printf 'review benchmark — %s fixture(s), %s sample(s) each, real model calls\n\n' "$NFIX" "$SAMPLES"
printf '%-8s %-8s %-9s %-17s %-15s %s\n' "arm" "found" "planted" "false positives" "skills loaded" "skill calls"
printf '%-8s %-8s %-9s %-17s %-15s %s\n' "--------" "--------" "---------" "-----------------" "---------------" "-----------"
printf '%s' "$RESULTS" | while IFS='|' read -r a h p fp ld fr; do
  [ -n "$a" ] || continue
  note=""
  # A harness arm that loaded no more skills than the built-ins never actually ran. Saying so is
  # the whole point: an arm that silently did nothing scores zero and looks like a weak result.
  if [ "$a" != none ] && [ "${ld:-0}" -le 20 ]; then note="   INVALID: harness skills did not load"; fi
  printf '%-8s %-8s %-9s %-17s %-15s %s%s\n' "$a" "$h" "$p" "$fp" "$ld" "$fr" "$note"
done

echo
echo "Recall and precision are both results. A configuration that finds every planted defect and"
echo "also flags the clean file has not won anything."
echo "Sample size is small by design. Quote it with any number taken from here, and do not read a"
echo "one- or two-defect gap as a difference."
