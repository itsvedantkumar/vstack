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
#   GSTACK_DIR=/path/to/gstack tests/evals/run-pathways.sh --samples 3 --arms vstack,gstack

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SRC=$(pwd)
# FIXTURES selects the set. `holdout` is the set the optimisation loop never tunes against, so
# a change that helps the dev fixtures can be checked against something it has not seen.
case "${FIXTURES:-dev}" in
  holdout) FIX="$SRC/tests/evals/holdout"; GT="$SRC/tests/evals/holdout/ground-truth.json" ;;
  *)       FIX="$SRC/tests/evals/fixtures"; GT="$SRC/tests/evals/ground-truth.json" ;;
esac

SAMPLES=1; ARMS_CSV="vstack,gstack"; JSON=0
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

# The plain-request arm. It has to be the closest thing to `/review` that a person without any
# harness would type, and nothing more.
#
# It used to carry three extra sentences: report only genuine defects, do not report style or
# preference, report nothing if the changes are correct. The harness arms are invoked as a bare
# `/review` and receive no such coaching, because appending anything to a slash command stops it
# dispatching. So the baseline was being told to be restrained and then scored on its restraint,
# and the retracted run in RESULTS.md is what that produced: a baseline at 100% precision against
# two harnesses in the sixties.
#
# The extractor below drops nits, style notes and suggestions identically for every arm, so that
# filtering already happens in one place. Doing it twice for one arm and once for the others is
# the asymmetry. This prompt is now what it claims to be.
read -r -d '' NEUTRAL <<'EOF' || true
Review the uncommitted changes in this repository.
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

# --- arm activation: global, one at a time, in the real home ---------------------------------
#
# Lifted from tests/evals/swebench/run.sh so the two harnesses cannot drift apart on the thing
# that matters most. The reasoning is there in full; the short version is that gstack refers to
# its own helpers by absolute path about eighty-five times, its own setup calls --local
# deprecated, and directory isolation loses authentication, so arms are isolated by time.
MACHINE_BK="$ROOT/machine-backup"

# Only the directories an arm can occupy, not the whole config dir. Backing up ~/.claude wholesale
# copied 1.6 GB of plugin cache and session history, per run.
ARM_DIRS="skills agents commands hooks"

restore_machine() {
  [ -d "$MACHINE_BK" ] || return 0
  for _d in $ARM_DIRS; do
    rm -rf "$HOME/.claude/$_d"
    [ -d "$MACHINE_BK/$_d" ] && cp -R "$MACHINE_BK/$_d" "$HOME/.claude/$_d"
  done
  [ -f "$MACHINE_BK/settings.json" ] && cp "$MACHINE_BK/settings.json" "$HOME/.claude/settings.json"
  # Reinstall rather than trusting the copy: the wrappers under ~/.config/agents are outside the
  # backed-up set, and a restore that only put ~/.claude back left doctor reporting drift.
  ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || true
  printf 'machine restored\n' >&2
}

backup_machine() {
  mkdir -p "$MACHINE_BK"
  for _d in $ARM_DIRS; do
    [ -d "$HOME/.claude/$_d" ] && cp -R "$HOME/.claude/$_d" "$MACHINE_BK/$_d"
  done
  cp "$HOME/.claude/settings.json" "$MACHINE_BK/settings.json" 2>/dev/null
  trap restore_machine EXIT INT TERM
}

# Not ./uninstall.sh. That restores from the newest install backup, and because install.sh runs
# constantly here the newest backup contains vstack's own files -- measured: 28 skills before,
# 28 after. A deactivation that silently does nothing would have put vstack's skills on the
# gstack arm and produced a comparison of vstack against itself.
deactivate_all() {
  for _d in $ARM_DIRS; do rm -rf "$HOME/.claude/$_d"; mkdir -p "$HOME/.claude/$_d"; done
  if command -v jq >/dev/null 2>&1 && [ -f "$MACHINE_BK/settings.json" ]; then
    jq 'del(.hooks) | del(.skillOverrides) | del(.statusLine)' \
      "$MACHINE_BK/settings.json" > "$HOME/.claude/settings.json" 2>/dev/null || true
  fi
}

nskills() { find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

activate_arm() { # <arm>
  deactivate_all
  case "$1" in
    none) : ;;
    vstack) ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || return 1 ;;
    # Same install as vstack, with outputStyle forced back to Default. vstack ships Concise, so
    # the only variable between these two arms is the register the model writes in.
    vstack-default) ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || return 1
                    jq '.outputStyle = "Default"' "$HOME/.claude/settings.json" > "$ROOT/s.json" \
                      && mv "$ROOT/s.json" "$HOME/.claude/settings.json" ;;
    gstack) ( cd "$GSTACK_DIR" && ./setup --quiet >/dev/null 2>&1 ) || return 1 ;;
  esac
  
  # Positive control. Every arm asserts that what it installed is actually there and that the
  # other arm is not, because a benchmark whose arms silently share a config dir compares one
  # harness against itself and prints a number anyway.
  local n; n=$(nskills)
  case "$1" in
    none)
      [ "$n" -eq 0 ] || { printf 'INVALID none: %s skill(s) still present after deactivation\n' "$n" >&2; return 1; } ;;
    vstack|vstack-default)
      local want; want=$(find "$SRC/claude/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
      [ "$n" -eq "$want" ] || { printf 'INVALID %s: %s skills installed, expected %s\n' "$1" "$n" "$want" >&2; return 1; }
      [ -d "$HOME/.claude/skills/gstack" ] && { printf 'INVALID %s: gstack is still installed\n' "$1" >&2; return 1; } ;;
    gstack)
      [ -d "$HOME/.claude/skills/gstack" ] || { printf 'INVALID gstack: its skills directory is absent after setup\n' >&2; return 1; }
      # The check whose absence let sixty gstack reviews be scored on a pathway with no helpers.
      local missing=0 q
      for q in bin/gstack-config bin/gstack-telemetry-log review/SKILL.md; do
        [ -e "$HOME/.claude/skills/gstack/$q" ] || missing=$((missing+1))
      done
      [ "$missing" -eq 0 ] || { printf 'INVALID gstack: %s declared helper path(s) missing\n' "$missing" >&2; return 1; } ;;
  esac
  printf 'arm %s active (%s user-scope skills)\n' "$1" "$n" >&2
  return 0
}

# Project scope still carries vstack's skills for the fixture repo, because /review is invoked
# from inside it. The user-scope activation above is what makes the gstack arm real.
install_arm() { # <arm> <dir>
  local a="$1" d="$2" sk="$2/.claude/skills" cm="$2/.claude/commands"
  mkdir -p "$sk" "$cm"
  case "$a" in
    none|gstack) : ;;
    vstack)
      for x in "$SRC"/claude/skills/*/; do [ -d "$x" ] && cp -R "${x%/}" "$sk/"; done
      cp "$SRC"/claude/commands/*.md "$cm/" 2>/dev/null
      mkdir -p "$d/.claude/agents" && cp "$SRC"/claude/agents/*.md "$d/.claude/agents/" 2>/dev/null
      mkdir -p "$d/.claude/hooks" && cp "$SRC"/claude/hooks/*.sh "$d/.claude/hooks/" 2>/dev/null
      chmod 755 "$d"/.claude/hooks/*.sh 2>/dev/null
      [ -x "$SRC/overlay.sh" ] && "$SRC/overlay.sh" "$d" >/dev/null 2>&1
      ;;
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
  # 300s per review let one slow pathway stall the whole suite: gstack's /review reads a large
  # tree and its arm was averaging minutes per run, which turned a 120-review benchmark into
  # hours. A shorter ceiling loses the occasional slow run — recorded as a miss, which is the
  # honest treatment of a review that did not finish — rather than losing the whole suite.
  # user,project, not project alone. Arms install globally now, and --setting-sources=project
  # hides user scope: measured on this machine, project-only sees 48 commands and 16 skills with
  # no /review at all, while user,project sees 113 and 68 with /review present. The harness was
  # invoking a slash command that did not exist in the session, so both harness arms were unable
  # to run their pathway and the unconfigured baseline won by default. The INVALID flag caught it;
  # the numbers under it were meaningless.
  raw=$( cd "$d" && timeout "${REVIEW_TIMEOUT:-150}" claude -p "$prompt" --setting-sources=user,project \
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
    #
    # And it is not "was the command registered" either, which is all the previous version
    # measured. `.slash_commands` in the init event lists what the session REGISTERED, not what
    # it invoked. Measured directly: a project with a /probe command that the prompt never
    # mentions still reports probe in slash_commands, count 1. So this gate returned yes for
    # every arm in every run and could not fail -- a validity check that cannot fail is the same
    # thing as no validity check, which is the defect this whole file exists to avoid.
    #
    # Three signals, any one of which counts, and none of which privileges a particular
    # architecture: a Skill or Task call naming something the arm installed, a file read under
    # the arm's own .claude tree, or a Bash command that runs something out of it. The first
    # covers vstack's subagent style, the second and third cover gstack's inline style.
    # Both install roots. Arms are installed at user scope, so a detector that only looked under
    # the project directory could never fire on signals 2 and 3 and reported every arm INVALID.
    entered=$(printf '%s' "$raw" | jq -rs --arg d "$d" --arg h "$HOME/.claude" '
      def hits($t): ($t | contains($d + "/.claude")) or ($t | contains($h));
      [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") ]
      | map(
          if   (.name=="Skill" or .name=="Task") then 1
          elif ((.name=="Read" or .name=="Grep" or .name=="Glob")
                and hits(.input.path // .input.file_path // .input.pattern // "")) then 1
          elif (.name=="Bash" and hits(.input.command // "")) then 1
          else 0 end)
      | add // 0' 2>/dev/null)
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
  # The extractor decides what counts as a defect claim, and it must apply the same bar to every
  # arm. The first version asked only for "defects" and let the reviewer's own framing through,
  # which made this benchmark unfair in a way that took an outsider's disbelief to catch.
  #
  # The `none` arm was told "do not report style, naming, typing, documentation, or preference",
  # so it stayed silent on those. The harness arms were given their own /review, which is written
  # to produce a thorough multi-section report — and it duly reported things like "inconsistent
  # parameter typing (nit)", "no tests (low)" and "no call sites (info)". Those are not false
  # claims about defects. They are correct observations that the baseline had been instructed not
  # to make, and counting them as false positives scored the harnesses for answering a question
  # nobody asked them to skip.
  #
  # So the extractor now drops anything the review itself frames as a nit, a suggestion, a
  # missing test, a style or typing preference, or an informational note, and keeps only what it
  # presents as an actual bug. Same instruction, same model, every arm.
  out=$( cd "$ed" && timeout "${EXTRACT_TIMEOUT:-90}" claude -p "Read review.txt. It is a code review. Extract ONLY findings that the review presents as a genuine BUG, security problem, or resource-handling error in the code — something that would misbehave at runtime. EXCLUDE anything the review frames as a nit, style, naming, typing or annotation preference, a missing test, missing documentation, a suggestion, or an informational note, however it is labelled. Output ONLY a JSON array and no prose: [{\"line\": <integer>, \"category\": \"security|correctness|resource-leak\", \"summary\": \"<one sentence>\"}]. Use the line number the review gives. If it reports no genuine bug, output []." \
         --setting-sources=project --output-format=stream-json --verbose < /dev/null 2>/dev/null \
       | jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text]|join("")' 2>/dev/null )
  printf '%s' "$out" | grep -o '\[[^][]*\]' | tail -1
}

score() { # <fixture> <findings>
  local f="$1" found="$2" planted
  [ -n "$found" ] || found='[]'
  printf '%s' "$found" | jq -e . >/dev/null 2>&1 || found='[]'
  # The denominator comes from ground truth and never from the scoring path.
  #
  # It used to fall back to {"hits":0,"planted":0,"fp":0} whenever the jq scoring failed, so a
  # review that errored or timed out removed its own planted defect from the total instead of
  # counting as a miss. That silently inflates recall for whichever arm fails more often, and it
  # is why one arm reported 34 planted where the others reported 35 — a difference that read as a
  # rounding detail and was actually four swallowed failures.
  planted=$(jq --arg f "$f" '[.fixtures[]|select(.file==$f)|.planted[]?]|length' "$GT" 2>/dev/null)
  [ -n "$planted" ] || planted=0
  jq -n --argjson g "$(jq --arg f "$f" '.fixtures[]|select(.file==$f)' "$GT")" \
        --argjson found "$found" --argjson tol "$TOL" '
    ($g.planted // []) as $p
    | { hits: ([$p[] | . as $pl | select(($found|map(select(((.line-$pl.line)|fabs)<=$tol))|length)>0)]|length),
        planted: ($p|length),
        fp: ([$found[] | . as $fd | select(($p|map(select(((($fd.line)-.line)|fabs)<=$tol))|length)==0)]|length) }' \
    2>/dev/null || printf '{"hits":0,"planted":%s,"fp":0}' "$planted"
}

NFIX=$(jq -r '.fixtures|length' "$GT")
RESULTS=""

# Per-run results are appended to a log as they complete, and progress goes to stderr.
#
# The first version accumulated everything in a shell variable and printed one table at the very
# end. A 120-review run then produced a zero-byte output file for ninety minutes with no way to
# tell progress from a hang, and killing it — which is what eventually happened — threw away 83
# completed reviews. Anything that takes hours has to be observable while it runs and survivable
# when it does not.
RUNLOG="${RUNLOG:-$ROOT/runs.tsv}"
. "$SRC/tests/evals/lib/runlog.sh"
open_runlog "$RUNLOG" "$(printf 'arm\tfixture\tsample\thits\tplanted\tfp\tentered')" || exit 2
TOTAL_RUNS=$(( $(printf '%s' "$ARMS_CSV" | tr ',' ' ' | wc -w) * NFIX * SAMPLES ))
DONE_RUNS=0
# Does this arm's command pathway dispatch at all?
#
# The previous gate asked whether a run left a Skill, Task or .claude file-read behind, and
# reported every arm INVALID for two runs straight. It was never decidable that way. A dispatched
# slash command leaves no marker in the transcript -- /probe produces the same event shape as a
# plain prompt -- and whether /review delegates to a subagent is a decision the model makes, not
# a fact about dispatch. Measuring a model's choice and calling it validity is how the first
# version of this gate came to fail gstack for having a different architecture.
#
# What is decidable: install a command that prints a token, invoke it, and see whether the token
# comes back. That proves the arm's command pathway works, in the arm's own install location,
# without privileging any architecture. One call per arm.
canary_ok() { # <arm> <dir> -> 0 if the arm's slash commands dispatch
  local d="$1" tok="PATHWAY-OK-4417" out
  mkdir -p "$d/.claude/commands"
  printf -- '---\ndescription: canary\n---\nOutput exactly %s and nothing else.\n' "$tok" \
    > "$d/.claude/commands/zz-canary.md"
  out=$( cd "$d" && timeout 120 claude -p "/zz-canary" --setting-sources=user,project \
           < /dev/null 2>/dev/null )
  rm -f "$d/.claude/commands/zz-canary.md"
  case "$out" in *"$tok"*) return 0 ;; *) return 1 ;; esac
}

backup_machine
for a in $(printf '%s' "$ARMS_CSV" | tr ',' ' '); do
  H=0; P=0; FP=0; ENT=0; RUNS=0

  if ! activate_arm "$a"; then
    printf 'INVALID  %s: not installable on this machine; not run, not scored\n' "$a" >&2
    continue
  fi
  cdir="$ROOT/canary-$a"; make_repo "$(jq -r '.fixtures[0].file' "$GT")" "$cdir"; install_arm "$a" "$cdir"
  if canary_ok "$cdir"; then
    printf 'ok       %s: slash commands dispatch in this arm\n' "$a" >&2
  else
    printf 'INVALID  %s: slash commands do not dispatch here; not run, not scored\n' "$a" >&2
    continue
  fi

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
      DONE_RUNS=$((DONE_RUNS+1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$a" "$f" "$s" \
        "$(printf '%s' "$sc" | jq -r '.hits')" "$(printf '%s' "$sc" | jq -r '.planted')" \
        "$(printf '%s' "$sc" | jq -r '.fp')" "$ent" >> "$RUNLOG"
      printf '\r  %s/%s  %-8s %-18s sample %s   ' "$DONE_RUNS" "$TOTAL_RUNS" "$a" "$f" "$s" >&2
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

printf '\n' >&2
printf 'review-pathway benchmark — %s fixtures x %s sample(s), each harness through its own /review\n\n' "$NFIX" "$SAMPLES"
printf '%-8s %-8s %-9s %-17s %s\n' "arm" "found" "planted" "false positives" "delegation trace"
printf '%-8s %-8s %-9s %-17s %s\n' "--------" "--------" "---------" "-----------------" "---------------"
printf '%s' "$RESULTS" | while IFS='|' read -r a h p fp ent runs; do
  [ -n "$a" ] || continue
  if [ "$a" = none ]; then ep="n/a"; else
    ep="$ent/$runs"
    [ "${ent:-0}" -eq 0 ] && ep="$ep  (no subagent or skill-file trace; the command still ran)"
  fi
  printf '%-8s %-8s %-9s %-17s %s\n' "$a" "$h" "$p" "$fp" "$ep"
done
echo
echo "Recall and precision are both results. Quote the sample count with any number from here."
