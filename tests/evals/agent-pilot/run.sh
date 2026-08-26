#!/usr/bin/env bash
# run.sh -- the agent-pilot instrument. Refuses to spend a single model call by default.
#
# THE QUESTION: does routing work to a shipped specialist subagent (code-reviewer,
# security-auditor, qa, test-writer) produce better output than doing it inline, or than routing
# it to a generic subagent with no specialist prompt? Full design and the honest prior in
# PREREGISTRATION.md -- read that before reading this file's --plan output.
#
# THIS REPOSITORY'S OWN NULLS SAY THE ANSWER IS PROBABLY "NO". tests/evals/RESULTS.md measured
# 11/15, 11/15, 10/15 across no harness, vstack and a competitor, zero skill invocations in sixty
# runs. docs/research/harness-value-literature-2026-08.md's single most decision-relevant finding
# is that prose instructions telling an agent to be careful measured *worse* than no intervention.
# Nothing here is designed to find a positive result; PREREGISTRATION.md states in advance what
# result would count as which answer, before any of the 25 calls exist.
#
# EXECUTING THIS IS FORBIDDEN WITHOUT THE OPERATOR'S EXPLICIT OPT-IN. Run with no arguments, or
# anything short of the two gates below both being satisfied, and this prints the plan and the
# cost estimate and exits without calling a model.
#
#   1. the flag --go
#   2. the environment variable AGENT_PILOT_CONFIRM set to the literal string
#      "RUN THE 25 CALLS" (copy it exactly; anything else is treated as unset)
#
# Usage:
#   tests/evals/agent-pilot/run.sh                    print the plan and the cost estimate; exit 0
#   tests/evals/agent-pilot/run.sh --plan              same, explicit
#   AGENT_PILOT_CONFIRM="RUN THE 25 CALLS" \
#     tests/evals/agent-pilot/run.sh --go              spend the 25 calls
#
# SANDBOXING. Every cell gets its own PILOT_HOME=$(mktemp -d), and `claude` runs with
# HOME="$PILOT_HOME". The real $HOME/.claude is never written to by this file -- not by any arm,
# not for activation, not for cleanup. That is a deliberate difference from
# tests/evals/run-pathways.sh and tests/evals/false-done/run.sh, both of which mutate
# $HOME/.claude in place and restore it afterward; that restore-on-EXIT pattern is exactly what
# harnesses-clobber-concurrent-edits.md in this project's own history describes going wrong. This
# instrument does not need that risk: none of its three arms are a vstack-vs-competitor
# installation comparison, so there is nothing to install into the real machine at all.
#
# Per-arm state, stated precisely because the brief that authorized this file requires it:
#   direct        PILOT_HOME/.claude is empty except for carried-over credentials (below). No
#                 agents, no skills, no commands, no hooks. Read/Grep/Glob/Bash-Task is denied
#                 outright via --allowedTools, so this arm cannot delegate even if it wanted to.
#   generic       Same empty PILOT_HOME. --allowedTools is Task only, forcing delegation. The
#                 dispatched subagent_type is "general-purpose", which ships with Claude Code
#                 itself and needs no file in this repository or in PILOT_HOME to exist.
#   specialist    Same empty PILOT_HOME, plus exactly one file:
#                 PILOT_HOME/.claude/agents/<role>.md, copied verbatim from
#                 claude/agents/<role>.md in this repository. --allowedTools is Task only, same
#                 as generic. The dispatched subagent_type is the role name.
#
# CREDENTIAL CARRY-OVER, best-effort and unverified -- see PREREGISTRATION.md, "what I could not
# verify". Reassigning HOME is known in this repository's own memory to break `claude -p` login
# when done via CLAUDE_CONFIG_DIR pointed at an empty directory (RESULTS.md's first documented
# benchmark defect: every baseline run returned "Not logged in" and scored a false zero). HOME
# reassignment is what the operator's brief requires regardless, so this file copies (read-only,
# from the real $HOME, never written to) the two files Claude Code is known to read credentials
# from -- $HOME/.claude.json and $HOME/.claude/.credentials.json, if present -- into each
# PILOT_HOME before the first cell runs. This has not been exercised, because exercising it means
# spending a call. If it does not work, every one of the 25 cells reads NOT_RUN with an
# authentication error in its capture, not a false measurement of "the specialist arm found
# nothing" -- which is the entire reason the scorer has four verdicts and not two.
#
# Bash 3.2 / Linux / Alpine. No arrays, no associative arrays, no mapfile, no sort -V.

set -uo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HERE="$SRC/tests/evals/agent-pilot"
GT="$HERE/ground-truth.json"

command -v jq >/dev/null 2>&1 || { echo "run.sh needs jq" >&2; exit 2; }
[ -f "$GT" ] || { echo "missing $GT" >&2; exit 2; }

# --- fixed design, held equal across every arm -------------------------------------------------
MODEL="sonnet"
MAX_TURNS="${AGENT_PILOT_MAX_TURNS:-8}"
CELL_TIMEOUT="${AGENT_PILOT_TIMEOUT:-240}"   # seconds, per call, identical for all 25
ROLES="code-reviewer security-auditor qa test-writer"
ARMS="direct generic specialist"

# role -> the tool list claude/agents/<role>.md itself declares in its `tools:` frontmatter line,
# read by hand on 2026-08-26. If that line changes upstream this table goes stale silently --
# named as a limitation in PREREGISTRATION.md rather than solved here, because deriving it at
# runtime would mean parsing YAML frontmatter with grep/sed for a value that is asserted exactly
# once per role and is cheap to eyeball against the five lines above each claude/agents/*.md file.
# Space-separated, matching tests/team-gating.sh's demonstrated-working `--allowedTools A B C`
# form -- not the comma-joined single string tests/evals/build-the-lever/run.sh uses for
# --disallowedTools. The two flags are not proven interchangeable in their argument shape in this
# repository and this file does not guess: it copies the form already shown to work for the flag
# it actually calls.
role_tools() {
  case "$1" in
    code-reviewer)     printf 'Read Grep Glob Bash' ;;
    security-auditor)  printf 'Read Grep Glob Bash' ;;
    qa)                printf 'Read Grep Glob Bash Edit' ;;
    test-writer)       printf 'Read Grep Glob Bash Edit Write' ;;
    *) return 1 ;;
  esac
}

# --- structural self-check: does the design on disk still match the design in this file's own
# comments? Zero cost, no model call. Refuses even to print a plan if ground-truth.json has drifted
# from the 4 roles x 2 fixtures + 1 canary shape this file was built against.
check_design_matches_ground_truth() {
  local errs="" r n
  for r in $ROLES; do
    n=$(jq -r --arg r "$r" '[.fixtures[] | select(.role==$r)] | length' "$GT")
    [ "$n" = "2" ] || errs="$errs\n  role $r has $n fixture(s) in ground-truth.json, expected 2"
    role_tools "$r" >/dev/null || errs="$errs\n  role $r has no entry in role_tools()"
  done
  n=$(jq -r '.fixtures | length' "$GT")
  [ "$n" = "8" ] || errs="$errs\n  ground-truth.json has $n fixture(s) total, expected 8"
  jq -e '.canary.id and .canary.detect_all and .canary.arm=="specialist"' "$GT" >/dev/null 2>&1 \
    || errs="$errs\n  ground-truth.json's .canary entry is missing or malformed"
  for r in $ROLES; do
    [ -f "$SRC/claude/agents/$r.md" ] || errs="$errs\n  claude/agents/$r.md does not exist -- the specialist arm for $r has nothing to install"
  done
  if [ -n "$errs" ]; then
    printf 'REFUSED: the design on disk does not match this file'"'"'s assumptions:%b\n' "$errs" >&2
    return 1
  fi
  return 0
}

# --- the 25-cell matrix, printed and later iterated from the same function -----------------------
# One line per cell: role \t fixture_id \t arm \t cell_id
enumerate_cells() {
  local r f a fid
  for r in $ROLES; do
    for fid in $(jq -r --arg r "$r" '.fixtures[] | select(.role==$r) | .id' "$GT"); do
      for a in $ARMS; do
        printf '%s\t%s\t%s\t%s-%s\n' "$r" "$fid" "$a" "$fid" "$a"
      done
    done
  done
  # The canary. Its arm is fixed by ground-truth.json's .canary.arm, not looped.
  local cid crole carm
  cid=$(jq -r '.canary.id' "$GT")
  crole=$(jq -r '.canary.role' "$GT")
  carm=$(jq -r '.canary.arm' "$GT")
  printf '%s\t%s\t%s\t%s\n' "$crole" "$cid" "$carm" "canary"
}

print_plan() {
  local n_cells n_roles
  n_cells=$(enumerate_cells | grep -c .)
  n_roles=$(printf '%s\n' "$ROLES" | tr ' ' '\n' | grep -c .)
  cat <<PLAN
agent-pilot -- PLAN ONLY. No model call has been made. Nothing below has executed.

Question: does routing work to a shipped specialist subagent beat doing it inline, or beat
routing to a generic subagent with no specialist prompt? Full pre-registration:
tests/evals/agent-pilot/PREREGISTRATION.md -- read it before opting in.

Design: $n_roles roles x 2 fixtures x 3 arms = 24 scored cells, plus 1 canary = $n_cells calls.
  roles:  $ROLES
  arms:   direct (inline, Task denied) | generic (Task -> subagent_type=general-purpose)
          | specialist (Task -> subagent_type=<role>, that role's own claude/agents/<role>.md)
  held equal per cell: model=$MODEL, --max-turns=$MAX_TURNS, per-call timeout=${CELL_TIMEOUT}s,
  and the working tool list (direct arm's --allowedTools mirrors the dispatched-to worker's own
  declared tools; see role_tools() and PREREGISTRATION.md's limitation on the generic arm's
  toolset, which cannot be pinned the same way).

Cost estimate (stated, not measured -- see PREREGISTRATION.md for the derivation):
  ~$n_cells calls, ~10k-20k tokens each depending on role, ~250k-500k tokens total.
  ~45-150s wall-clock per call (subagent-dispatch cells run two nested agent loops and are the
  slower half), serial execution, ~20-60 minutes wall-clock for the full run.

This instrument refuses to spend any of that without an explicit opt-in:
  1. the flag --go
  2. AGENT_PILOT_CONFIRM set to the literal string "RUN THE 25 CALLS"

Neither is set. Nothing has been called. Exiting.
PLAN
}

print_matrix() {
  printf '\n%-18s %-28s %-11s %-30s\n' "role" "fixture" "arm" "cell_id"
  printf '%-18s %-28s %-11s %-30s\n' "------------------" "----------------------------" "-----------" "------------------------------"
  enumerate_cells | while IFS=$'\t' read -r r f a c; do
    printf '%-18s %-28s %-11s %-30s\n' "$r" "$f" "$a" "$c"
  done
}

GO=0
for arg in "$@"; do
  case "$arg" in
    --go) GO=1 ;;
    --plan|-h|--help) GO=0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

check_design_matches_ground_truth || exit 2

CONFIRM="${AGENT_PILOT_CONFIRM:-}"
if [ "$GO" -ne 1 ] || [ "$CONFIRM" != "RUN THE 25 CALLS" ]; then
  print_plan
  print_matrix
  if [ "$GO" -eq 1 ]; then
    echo
    echo "REFUSED: --go was given but AGENT_PILOT_CONFIRM is not set to the exact literal" >&2
    echo "string \"RUN THE 25 CALLS\". Nothing has been called." >&2
  fi
  exit 0
fi

# --- everything below this line spends model calls and only runs after both gates are open ------

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-pilot.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
RUNLOG="${RUNLOG:-$ROOT/runs.tsv}"
. "$SRC/tests/evals/lib/runlog.sh"
open_runlog "$RUNLOG" "$(printf 'role\tfixture_id\tarm\tcell_id\texit\tverdict\tinput_tokens\toutput_tokens\tseconds')" || exit 2
echo "log: $RUNLOG" >&2

# One PILOT_HOME per cell. Never $HOME. Credential carry-over is read-only from the real $HOME;
# see the header comment for what this does and does not solve.
new_pilot_home() {
  local h; h=$(mktemp -d "${TMPDIR:-/tmp}/agent-pilot-home.XXXXXX")
  mkdir -p "$h/.claude"
  [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$h/.claude.json" 2>/dev/null
  [ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$h/.claude/.credentials.json" 2>/dev/null
  printf '%s' "$h"
}

# task_for <fixture-or-canary-id> -> the task text from ground-truth.json
task_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].task)' "$GT"; }
role_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].role)' "$GT"; }
file_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].file)' "$GT"; }
delivered_as_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].delivered_as)' "$GT"; }

run_cell() { # <role> <fixture-id> <arm> <cell-id>
  local role="$1" fid="$2" arm="$3" cid="$4"
  local task tools src_file dst_name wd ph cap exitf t0 secs ec verdictline verdict tokens_in tokens_out prompt

  task=$(task_for "$fid")
  tools=$(role_tools "$role")
  src_file="$HERE/$(file_for "$fid")"
  dst_name=$(delivered_as_for "$fid")

  wd="$ROOT/wd-$cid"; mkdir -p "$wd"
  cp "$src_file" "$wd/$dst_name"

  ph=$(new_pilot_home)

  case "$arm" in
    direct)
      prompt="$task

Answer directly yourself. Do not delegate this to a subagent."
      ;;
    generic)
      prompt="Use the Task tool with subagent_type=\"general-purpose\" and model=\"$MODEL\" to do the following, then report its findings back to me verbatim:

$task"
      ;;
    specialist)
      mkdir -p "$ph/.claude/agents"
      cp "$SRC/claude/agents/$role.md" "$ph/.claude/agents/$role.md"
      prompt="Use the Task tool with subagent_type=\"$role\" and model=\"$MODEL\" to do the following, then report its findings back to me verbatim:

$task"
      ;;
  esac

  cap="$ROOT/capture-$cid.jsonl"; exitf="$ROOT/capture-$cid.exit"
  t0=$(date +%s)
  if [ "$arm" = direct ]; then
    ( cd "$wd" && env HOME="$ph" timeout "$CELL_TIMEOUT" claude -p "$prompt" \
        --model "$MODEL" --max-turns "$MAX_TURNS" --allowedTools $tools \
        --setting-sources=user,project --output-format=stream-json --verbose \
        < /dev/null > "$cap" 2>/dev/null )
  else
    ( cd "$wd" && env HOME="$ph" timeout "$CELL_TIMEOUT" claude -p "$prompt" \
        --model "$MODEL" --max-turns "$MAX_TURNS" --allowedTools Task \
        --setting-sources=user,project --output-format=stream-json --verbose \
        < /dev/null > "$cap" 2>/dev/null )
  fi
  ec=$?
  secs=$(( $(date +%s) - t0 ))
  printf '%s' "$ec" > "$exitf"

  verdictline=$(bash "$HERE/scorer.sh" score "$cap" "$exitf" "$GT" "$fid")
  verdict=$(printf '%s' "$verdictline" | cut -f2)

  tokens_in=$(jq -rs '[.[] | select(.type=="result") | .usage.input_tokens // 0] | add // 0' "$cap" 2>/dev/null)
  tokens_out=$(jq -rs '[.[] | select(.type=="result") | .usage.output_tokens // 0] | add // 0' "$cap" 2>/dev/null)
  [ -n "$tokens_in" ] || tokens_in=0
  [ -n "$tokens_out" ] || tokens_out=0

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$role" "$fid" "$arm" "$cid" "$ec" "$verdict" "$tokens_in" "$tokens_out" "$secs" >> "$RUNLOG"

  rm -rf "$ph"
  printf '  %-30s %s\n' "$cid" "$verdict" >&2
}

echo "agent-pilot -- spending up to $(enumerate_cells | grep -c .) calls now." >&2
enumerate_cells | while IFS=$'\t' read -r r f a c; do
  run_cell "$r" "$f" "$a" "$c"
done

echo >&2
echo "done. Raw rows: $RUNLOG" >&2
echo "Score the canary first -- PREREGISTRATION.md says what a non-FOUND canary means for the" >&2
echo "other 24 rows before reading them as a result." >&2
