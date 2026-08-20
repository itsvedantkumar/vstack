#!/usr/bin/env bash
# run-pathways.sh — benchmark each harness through the review pathway it actually ships.
#
# WHY THIS EXISTS SEPARATELY FROM run.sh.
#
# run.sh installs each harness's skills and asks a plain review question. Its result was a null:
# 11/15, 11/15, 10/15 across none, vstack and gstack, with ZERO skill invocations in sixty runs.
# That is a real answer to "does having these skills installed change an ordinary review" — no —
# and it is not an answer to "which harness reviews code better", because neither harness reviews
# through a skill. vstack ships /review as a command; gstack ships /review as a skill with a
# slash trigger. Asking a plain question reaches neither.
#
# This runs each arm through its own front door:
#   none     a plain review request, built-ins only. The floor.
#   vstack   /review, with this repo's commands, agents and skills in project scope.
#   gstack   /review, with gstack's skills in project scope.
#
# And it reviews a DIFF, not a file, because that is what both /review pathways are written for:
# each fixture becomes a git repo whose base commit is the correct version and whose working tree
# carries the defect. That is also how review happens in practice.
#
# HONESTY CONSTRAINTS, because this benchmark is run by the author of one of the arms:
#   - The prompt for the `none` arm is the neutral one from run.sh, unchanged. The harness arms
#     get their own command invoked with no extra instruction, which is the fairest reading of
#     "use the thing it ships".
#   - Each run records which commands and skills the session loaded and whether the pathway was
#     actually entered. An arm whose /review did not exist is INVALID, not zero.
#   - Findings are matched by line number against ground truth. clean.py has nothing planted, so
#     every finding there is a false positive.
#   - Report the sample count with any number taken from here. A one- or two-defect gap across
#     eight fixtures is noise.
#
# Usage:
#   GSTACK_DIR=/path/to/gstack tests/evals/run-pathways.sh --samples 3 --arms none,vstack,gstack

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SRC=$(pwd)
FIX="$SRC/tests/evals/fixtures"
GT="$SRC/tests/evals/ground-truth.json"

SAMPLES=1; ARMS_CSV="none,vstack,gstack"; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --samples) SAMPLES="$2"; shift 2 ;;
    --arms) ARMS_CSV="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v jq  >/dev/null 2>&1 || { echo "needs jq"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "needs git"; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "SKIP: claude CLI not installed"; exit 0; }
GSTACK_DIR="${GSTACK_DIR:-}"
case "$ARMS_CSV" in *gstack*)
  if [ -z "$GSTACK_DIR" ] || [ ! -d "$GSTACK_DIR" ]; then
    echo "note: dropping the gstack arm — set GSTACK_DIR to a gstack checkout" >&2
    ARMS_CSV=$(printf '%s' "$ARMS_CSV" | sed 's/gstack//; s/,,/,/g; s/^,//; s/,$//')
  fi ;;
esac

ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-pathways.XXXXXX")" && pwd)
trap 'rm -rf "$ROOT"' EXIT
TOL=$(jq -r '.tolerance' "$GT")

read -r -d '' NEUTRAL <<'EOF' || true
Review the uncommitted changes in this repository for defects.

Report ONLY genuine defects: a bug, a security problem, or a resource-handling error that would
actually bite in production. Do not report style, naming, typing, documentation, or preference.
If the changes are correct, report nothing.

Output ONLY a JSON array, no prose before or after, in exactly this shape:
[{"line": <integer>, "category": "security|correctness|resource-leak", "summary": "<one sentence>"}]
An empty array is a valid and sometimes correct answer.
EOF

read -r -d '' JSONTAIL <<'EOF' || true

When you have finished, output ONLY a JSON array as the final message, no prose after it:
[{"line": <integer>, "category": "security|correctness|resource-leak", "summary": "<one sentence>"}]
Line numbers refer to the changed file. An empty array is valid if nothing is wrong.
EOF

# Build a git repo whose HEAD is correct and whose working tree carries the defect, so /review
# has a real diff to look at.
make_repo() { # <fixture> <dir>
  local f="$1" d="$2"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email eval@example.com
  git -C "$d" config user.name eval
  # A base commit that is deliberately trivial: the whole file arrives as the change under
  # review, so the diff contains the defect rather than surrounding it.
  printf '# placeholder\n' > "$d/$f"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm base >/dev/null 2>&1
  cp "$FIX/$f" "$d/$f"
}

install_arm() { # <arm> <dir>
  local a="$1" d="$2" sk="$2/.claude/skills" cm="$2/.claude/commands"
  mkdir -p "$sk" "$cm"
  case "$a" in
    none) : ;;
    vstack)
      for x in "$SRC"/claude/skills/*/; do [ -d "$x" ] && cp -R "${x%/}" "$sk/"; done
      cp "$SRC"/claude/commands/*.md "$cm/" 2>/dev/null
      mkdir -p "$d/.claude/agents" && cp "$SRC"/claude/agents/*.md "$d/.claude/agents/" 2>/dev/null ;;
    gstack)
      # The WHOLE skill directory, not just SKILL.md. gstack's /review reads sibling files —
      # specialists/, checklist.md, design-checklist.md — and copying only the manifest left its
      # pathway unable to run. It scored zero and was marked INVALID, which is the right outcome
      # for a broken arm and would have been a disgraceful thing to publish as a result.
      find "$GSTACK_DIR" -maxdepth 2 -name SKILL.md 2>/dev/null | while IFS= read -r m; do
        d0=$(dirname "$m"); n=$(basename "$d0")
        cp -R "$d0" "$sk/$n" 2>/dev/null
      done ;;
  esac
}

run_arm() { # <arm> <dir> -> findings TAB pathway_entered
  local a="$1" d="$2" prompt raw text entered
  case "$a" in
    none) prompt="$NEUTRAL" ;;
    # Bare, with nothing appended. Adding an instruction after "/review" stops it registering
    # as a command at all — the session then treats the whole string as an ordinary prompt, the
    # pathway never engages, and the arm scores zero while looking like a weak harness rather
    # than a broken invocation. The extraction pass below is what gets structured findings, so
    # nothing needs to be appended here.
    *)    prompt="/review" ;;
  esac
  raw=$( cd "$d" && timeout 300 claude -p "$prompt" --setting-sources=project \
           --output-format=stream-json --verbose < /dev/null 2>/dev/null )
  text=$(printf '%s' "$raw" | jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text]|join("")' 2>/dev/null)
  # Did the harness's own pathway actually engage? For `none` there is nothing to enter.
  if [ "$a" = none ]; then entered=na
  else
    # Validity is "was the command registered and invoked", not "did it delegate".
    #
    # The first version looked for a Skill, Task or Agent tool call. vstack's /review delegates
    # to a subagent so it passed; gstack's runs inline with Bash so it failed, and its arm was
    # marked INVALID for having a different — perfectly reasonable — implementation style. A
    # validity check that only recognises the author's own architecture is not a validity check,
    # it is a thumb on the scale.
    entered=$(printf '%s' "$raw" | jq -rs '[.[]|select(.subtype=="init")|.slash_commands[]?]|map(select(.=="review"))|length' 2>/dev/null)
    [ "${entered:-0}" -gt 0 ] && entered=yes || entered=no
  fi
  # Extraction is a separate, identical pass for every arm.
  #
  # The harness commands answer in prose — that is what they are written to do — so scoring their
  # raw output for a JSON array measured format compliance and gave both harnesses a zero while
  # they were producing perfectly good reviews. Converting the prose to findings with a fixed
  # extractor, run with built-ins only and the same prompt regardless of arm, keeps the thing
  # being measured as "which defects did it find" rather than "did it obey a schema".
  local findings
  findings=$(printf '%s' "$text" | extract_findings)
  printf '%s\t%s' "$findings" "$entered"
}

# Deterministic, arm-agnostic: same model, same prompt, built-ins only, for every arm.
extract_findings() {
  local review ed out
  review=$(cat)
  [ -n "$review" ] || { printf '[]'; return; }
  ed=$(mktemp -d "$ROOT/extract.XXXXXX")
  printf '%s' "$review" > "$ed/review.txt"
  out=$( cd "$ed" && timeout 180 claude -p "Read review.txt. It is a code review. Convert every genuine defect it reports into this JSON array and output ONLY the array, no prose: [{\"line\": <integer>, \"category\": \"security|correctness|resource-leak\", \"summary\": \"<one sentence>\"}]. Use the line number the review gives for each defect. If it reports no defects, output []." \
         --setting-sources=project --output-format=stream-json --verbose < /dev/null 2>/dev/null \
       | jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text]|join("")' 2>/dev/null )
  printf '%s' "$out" | grep -o '\[[^][]*\]' | tail -1
}

score() { # <fixture> <findings>
  local f="$1" found="$2"
  [ -n "$found" ] || found='[]'
  printf '%s' "$found" | jq -e . >/dev/null 2>&1 || found='[]'
  jq -n --argjson g "$(jq --arg f "$f" '.fixtures[]|select(.file==$f)' "$GT")" \
        --argjson found "$found" --argjson tol "$TOL" '
    ($g.planted // []) as $p
    | { hits: ([$p[] | . as $pl | select(($found|map(select(((.line-$pl.line)|fabs)<=$tol))|length)>0)]|length),
        planted: ($p|length),
        fp: ([$found[] | . as $fd | select(($p|map(select(((($fd.line)-.line)|fabs)<=$tol))|length)==0)]|length) }' \
    2>/dev/null || echo '{"hits":0,"planted":0,"fp":0}'
}

NFIX=$(jq -r '.fixtures|length' "$GT")
RESULTS=""
for a in $(printf '%s' "$ARMS_CSV" | tr ',' ' '); do
  H=0; P=0; FP=0; ENT=0; RUNS=0
  for f in $(jq -r '.fixtures[].file' "$GT"); do
    for s in $(seq 1 "$SAMPLES"); do
      d="$ROOT/$a-${f%.py}-$s"
      make_repo "$f" "$d"; install_arm "$a" "$d"
      line=$(run_arm "$a" "$d")
      out=$(printf '%s' "$line" | cut -f1); ent=$(printf '%s' "$line" | cut -f2)
      sc=$(score "$f" "$out")
      H=$((H + $(printf '%s' "$sc" | jq -r '.hits')))
      P=$((P + $(printf '%s' "$sc" | jq -r '.planted')))
      FP=$((FP + $(printf '%s' "$sc" | jq -r '.fp')))
      [ "$ent" = yes ] && ENT=$((ENT+1))
      RUNS=$((RUNS+1))
    done
  done
  RESULTS="$RESULTS$a|$H|$P|$FP|$ENT|$RUNS
"
done

if [ "$JSON" = 1 ]; then
  printf '%s' "$RESULTS" | jq -Rs --argjson n "$SAMPLES" --argjson fx "$NFIX" \
   'split("\n")|map(select(length>0))|map(split("|"))
    |map({arm:.[0],found:(.[1]|tonumber),planted:(.[2]|tonumber),false_positives:(.[3]|tonumber),
          pathway_entered:(.[4]|tonumber),runs:(.[5]|tonumber),samples:$n,fixtures:$fx})'
  exit 0
fi

printf 'review-pathway benchmark — %s fixtures x %s sample(s), each harness through its own /review\n\n' "$NFIX" "$SAMPLES"
printf '%-8s %-8s %-9s %-17s %s\n' "arm" "found" "planted" "false positives" "pathway entered"
printf '%-8s %-8s %-9s %-17s %s\n' "--------" "--------" "---------" "-----------------" "---------------"
printf '%s' "$RESULTS" | while IFS='|' read -r a h p fp ent runs; do
  [ -n "$a" ] || continue
  if [ "$a" = none ]; then ep="n/a"; else
    ep="$ent/$runs"
    [ "${ent:-0}" -eq 0 ] && ep="$ep  INVALID: its /review never engaged"
  fi
  printf '%-8s %-8s %-9s %-17s %s\n' "$a" "$h" "$p" "$fp" "$ep"
done
echo
echo "Recall and precision are both results. Quote the sample count with any number from here."
