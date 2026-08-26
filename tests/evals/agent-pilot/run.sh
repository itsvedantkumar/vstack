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
# result would count as which answer, before any of the 27 calls exist.
#
# 24 SCORED CELLS + 3 CANARY CELLS = 27. The canary grew from 1 to 3 on 2026-08-26: a single-arm
# canary only proves that ONE arm's plumbing works (fixture delivery, capture, scoring). It says
# nothing about whether the *other* two arms' distinct dispatch mechanisms -- Task ->
# subagent_type="general-purpose" for generic, Task -> subagent_type=<role> plus a copied agent
# file for specialist -- actually work, because each is a genuinely different code path. See
# PREREGISTRATION.md, "The canary", for the full reasoning. The canary is never pooled into the
# 24-cell comparison regardless of how many cells it costs.
#
# EXECUTING THIS IS FORBIDDEN WITHOUT THE OPERATOR'S EXPLICIT OPT-IN, IN TWO SEPARATE WAYS.
#
# Run with no arguments, or anything short of both an action gate and a confirmation gate being
# satisfied, and this prints the plan and exits without calling a model:
#
#   --canary-only     the cheap path: 3 calls (one per arm, all on the canary fixture), needs
#                     AGENT_PILOT_CONFIRM="RUN THE CANARY"
#   --go              the full instrument: 27 calls, needs
#                     AGENT_PILOT_CONFIRM="RUN THE 27 CALLS"
#
# The two confirmation strings are deliberately different so that approving one cannot be mistaken
# for approving the other -- a copy-pasted "RUN THE 27 CALLS" does not authorize --canary-only and
# vice versa.
#
# A THIRD gate exists and is not optional either: AGENT_PILOT_AUTH_MODE. See "AUTHENTICATION" below
# -- this one exists because a reassigned HOME does not authenticate on this machine, confirmed
# without spending a call, and there is no default this file is willing to pick silently.
#
# Usage:
#   tests/evals/agent-pilot/run.sh                                    print the plan; exit 0
#   tests/evals/agent-pilot/run.sh --plan                             same, explicit
#   AGENT_PILOT_AUTH_MODE=api-key AGENT_PILOT_CONFIRM="RUN THE CANARY" \
#     tests/evals/agent-pilot/run.sh --canary-only                    spend 3 calls
#   AGENT_PILOT_AUTH_MODE=api-key AGENT_PILOT_CONFIRM="RUN THE 27 CALLS" \
#     tests/evals/agent-pilot/run.sh --go                             spend 27 calls
#
# SANDBOXING. Every cell gets its own PILOT_HOME=$(mktemp -d), and `claude` runs with
# HOME="$PILOT_HOME". The real $HOME/.claude is never WRITTEN to by this file -- not by any arm,
# not for activation, not for cleanup. That is a deliberate difference from
# tests/evals/run-pathways.sh and tests/evals/false-done/run.sh, both of which mutate $HOME/.claude
# in place and restore it afterward; that restore-on-EXIT pattern is exactly what
# harnesses-clobber-concurrent-edits.md in this project's own history describes going wrong. This
# instrument does not need that risk: none of its three arms are a vstack-vs-competitor
# installation comparison, so there is nothing to install into the real machine at all.
#
# Per-arm state, stated precisely because the brief that authorized this file requires it:
#   direct        PILOT_HOME/.claude is empty except for whatever AGENT_PILOT_AUTH_MODE requires
#                 (below). No agents, no skills, no commands, no hooks. Task is denied outright
#                 via --allowedTools, so this arm cannot delegate even if it wanted to.
#   generic       Same PILOT_HOME. --allowedTools is Task only, forcing delegation. The dispatched
#                 subagent_type is "general-purpose", which ships with Claude Code itself and needs
#                 no file in this repository or in PILOT_HOME to exist.
#   specialist    Same PILOT_HOME, plus exactly one extra file:
#                 PILOT_HOME/.claude/agents/<role>.md, copied verbatim from
#                 claude/agents/<role>.md in this repository. --allowedTools is Task only, same as
#                 generic. The dispatched subagent_type is the role name.
#
# AUTHENTICATION -- resolved in this file, not discovered at run time. Established without
# spending a call, using only `security find-generic-password` (metadata, never the secret) and
# the CLI's own `claude auth status` (no model call):
#
#   `claude auth status` reports {"loggedIn": true, ...} under the real $HOME and
#   {"loggedIn": false, "authMethod": "none"} under a bare `HOME=$(mktemp -d)`. Root cause: on
#   this machine Claude Code's credential lives in the macOS login Keychain under service
#   "Claude Code-credentials", and Keychain Services resolves the default keychain via
#   $HOME/Library/Keychains/, which a fresh sandbox does not have. This is not the same failure
#   this repository's memory already recorded for CLAUDE_CONFIG_DIR isolation (a missing
#   ~/.claude.json makes the CLI report "not logged in" without even trying the keychain) --
#   it is a second, independent failure with the same symptom: a bare HOME reassignment breaks
#   login here for two separate reasons, not one.
#
#   A technical fix was found and verified the same way (`claude auth status` -> loggedIn: true):
#   symlink PILOT_HOME/Library/Keychains -> the real $HOME/Library/Keychains, read-only, created
#   only inside the throwaway sandbox, never writing to or copying the real Keychains directory.
#
#   THAT FIX IS NOT THE DEFAULT, because it is not free. Every arm in this design carries Bash
#   (all four roles' tool lists), so a symlinked Keychains directory hands every dispatched
#   subagent -- including the unaudited built-in general-purpose one -- filesystem access to the
#   operator's ENTIRE real login keychain, not just Claude Code's own entry. That is a larger and
#   different risk than "the pilot cannot authenticate", and it is exactly the class of exposure
#   this instrument's own brief exists to keep out. AGENT_PILOT_AUTH_MODE makes the operator choose
#   this knowingly rather than have it happen as a side effect of HOME sandboxing:
#
#   AGENT_PILOT_AUTH_MODE=api-key             (recommended) requires ANTHROPIC_API_KEY already set
#                                              in the invoking shell. No file or keychain access is
#                                              carried into PILOT_HOME at all -- the emptiest,
#                                              safest sandbox this design can produce. Changes the
#                                              cost model from the operator's unbilled Max-plan
#                                              session to pay-per-token API billing; that is a
#                                              separate spend this file does not authorize on its
#                                              own (see this operator's standing "no paid
#                                              benchmarks without an explicit ask" policy).
#   AGENT_PILOT_AUTH_MODE=keychain-symlink    accepts the risk above. Prints a loud warning naming
#                                              it every time a cell activates under this mode.
#
#   Neither mode is silently chosen. AGENT_PILOT_AUTH_MODE unset or invalid refuses to run, for
#   either --go or --canary-only, with this explanation printed again at the point of refusal.
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
CELL_TIMEOUT="${AGENT_PILOT_TIMEOUT:-240}"   # seconds, per call, identical for every cell
ROLES="code-reviewer security-auditor qa test-writer"
ARMS="direct generic specialist"

# role -> the tool list claude/agents/<role>.md itself declares, DERIVED at run time from the
# file's own `tools:` frontmatter line -- never hand-copied. A hand-copied table next to a
# machine-readable source is exactly the shape this repository's own
# docs/checks-that-inherit-their-answer.md catalogues: a value that can drift from what it claims
# to represent without anything noticing. This function fails loudly (nonzero return, message on
# stderr) if the file is missing or the frontmatter line is absent or empty, and
# check_design_matches_ground_truth() calls it for every role before any plan is even printed.
#
# Space-separated on output, matching tests/team-gating.sh's demonstrated-working
# `--allowedTools A B C` form -- not the comma-joined single string
# tests/evals/build-the-lever/run.sh uses for --disallowedTools. The two flags are not proven
# interchangeable in their argument shape in this repository and this file does not guess: it
# copies the form already shown to work for the flag it actually calls.
role_tools() {
  local role="$1"
  local f="$SRC/claude/agents/$role.md" line
  [ -f "$f" ] || { echo "role_tools: no such agent file: $f" >&2; return 1; }
  line=$(sed -n 's/^tools:[[:space:]]*//p' "$f" | head -1)
  [ -n "$line" ] || { echo "role_tools: $f has no 'tools:' frontmatter line" >&2; return 1; }
  printf '%s' "$line" | tr -d ',' | tr -s '[:space:]' ' '
}

# --- structural self-check: does the design on disk still match the design in this file's own
# comments? Zero cost, no model call. Refuses even to print a plan if ground-truth.json has drifted
# from the 4 roles x 2 fixtures + 1 canary shape this file was built against, or if any role's
# agent file cannot supply a tool list.
check_design_matches_ground_truth() {
  local errs="" r n t
  for r in $ROLES; do
    n=$(jq -r --arg r "$r" '[.fixtures[] | select(.role==$r)] | length' "$GT")
    [ "$n" = "2" ] || errs="$errs\n  role $r has $n fixture(s) in ground-truth.json, expected 2"
    t=$(role_tools "$r" 2>&1)
    case "$t" in
      *" "*|Read|Grep|Glob|Bash|Edit|Write) : ;;
      *) errs="$errs\n  role_tools($r) did not resolve to a plausible tool list: $t" ;;
    esac
  done
  n=$(jq -r '.fixtures | length' "$GT")
  [ "$n" = "8" ] || errs="$errs\n  ground-truth.json has $n fixture(s) total, expected 8"
  jq -e '.canary.id and .canary.detect_all and .canary.role' "$GT" >/dev/null 2>&1 \
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

# --- the 24 scored cells: role \t fixture_id \t arm \t cell_id ----------------------------------
enumerate_cells() {
  local r a fid
  for r in $ROLES; do
    for fid in $(jq -r --arg r "$r" '.fixtures[] | select(.role==$r) | .id' "$GT"); do
      for a in $ARMS; do
        printf '%s\t%s\t%s\t%s-%s\n' "$r" "$fid" "$a" "$fid" "$a"
      done
    done
  done
}

# --- the 3 canary cells: the same fixture, all three arms, never pooled into the 24 above -------
enumerate_canary_cells() {
  local a cid crole
  cid=$(jq -r '.canary.id' "$GT")
  crole=$(jq -r '.canary.role' "$GT")
  for a in $ARMS; do
    printf '%s\t%s\t%s\t%s\n' "$crole" "$cid" "$a" "canary-$a"
  done
}

print_plan() {
  local n_scored n_canary n_roles
  n_scored=$(enumerate_cells | grep -c .)
  n_canary=$(enumerate_canary_cells | grep -c .)
  n_roles=$(printf '%s\n' "$ROLES" | tr ' ' '\n' | grep -c .)
  cat <<PLAN
agent-pilot -- PLAN ONLY. No model call has been made. Nothing below has executed.

Question: does routing work to a shipped specialist subagent beat doing it inline, or beat
routing to a generic subagent with no specialist prompt? Full pre-registration:
tests/evals/agent-pilot/PREREGISTRATION.md -- read it before opting in.

Design: $n_roles roles x 2 fixtures x 3 arms = $n_scored scored cells, plus a $n_canary-cell canary
(the same fixture on all three arms -- one arm's canary does not prove another arm's dispatch
mechanism works; see PREREGISTRATION.md, "The canary") = $((n_scored + n_canary)) calls total.
  roles:  $ROLES
  arms:   direct (inline, Task denied) | generic (Task -> subagent_type=general-purpose)
          | specialist (Task -> subagent_type=<role>, that role's own claude/agents/<role>.md)
  held equal per cell: model=$MODEL, --max-turns=$MAX_TURNS, per-call timeout=${CELL_TIMEOUT}s,
  and the working tool list (direct arm's --allowedTools is DERIVED at run time from the
  dispatched-to worker's own claude/agents/<role>.md, never hand-copied; see role_tools() and
  PREREGISTRATION.md's limitation on the generic arm's toolset, which cannot be pinned the same
  way).

Two ways to run this, priced separately:
  --canary-only   3 calls only. Answers "is the harness wired correctly" without spending the
                  other 24. ~30-45k tokens, ~3-8 minutes wall-clock.
  --go            all $((n_scored + n_canary)) calls. ~270k-540k tokens, ~20-65 minutes wall-clock
                  (stated estimates, not measurements -- see PREREGISTRATION.md).

Three gates, all required, none defaulted:
  1. the action flag: --canary-only or --go
  2. AGENT_PILOT_CONFIRM, the exact literal string "RUN THE CANARY" (for --canary-only) or
     "RUN THE 27 CALLS" (for --go) -- deliberately different strings so approving one cannot be
     mistaken for approving the other
  3. AGENT_PILOT_AUTH_MODE=api-key or AGENT_PILOT_AUTH_MODE=keychain-symlink -- see this file's
     "AUTHENTICATION" header comment. A reassigned HOME does not authenticate on this machine
     (confirmed via \`claude auth status\`, no model call); there is no default this file will
     pick silently, because the working fix (keychain-symlink) hands every Bash-capable arm
     filesystem access to the operator's real login keychain, not just Claude Code's own entry.

None of the three is satisfied. Nothing has been called. Exiting.
PLAN
}

print_matrix() {
  printf '\n%-18s %-28s %-11s %-30s\n' "role" "fixture" "arm" "cell_id"
  printf '%-18s %-28s %-11s %-30s\n' "------------------" "----------------------------" "-----------" "------------------------------"
  { enumerate_cells; enumerate_canary_cells; } | while IFS=$'\t' read -r r f a c; do
    printf '%-18s %-28s %-11s %-30s\n' "$r" "$f" "$a" "$c"
  done
}

ACTION=""
for arg in "$@"; do
  case "$arg" in
    --go) [ -z "$ACTION" ] || { echo "--go and --canary-only are mutually exclusive" >&2; exit 2; }
          ACTION=go ;;
    --canary-only) [ -z "$ACTION" ] || { echo "--go and --canary-only are mutually exclusive" >&2; exit 2; }
          ACTION=canary ;;
    --plan|-h|--help) : ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

check_design_matches_ground_truth || exit 2

CONFIRM="${AGENT_PILOT_CONFIRM:-}"
AUTH_MODE="${AGENT_PILOT_AUTH_MODE:-}"
NEED_CONFIRM=""
[ "$ACTION" = go ] && NEED_CONFIRM="RUN THE 27 CALLS"
[ "$ACTION" = canary ] && NEED_CONFIRM="RUN THE CANARY"

case "$AUTH_MODE" in
  api-key|keychain-symlink) AUTH_OK=1 ;;
  *) AUTH_OK=0 ;;
esac

if [ -z "$ACTION" ] || [ "$CONFIRM" != "$NEED_CONFIRM" ] || [ "$AUTH_OK" -ne 1 ]; then
  print_plan
  print_matrix
  if [ -n "$ACTION" ]; then
    echo
    [ "$CONFIRM" = "$NEED_CONFIRM" ] || echo "REFUSED: AGENT_PILOT_CONFIRM is not set to the exact literal string \"$NEED_CONFIRM\"." >&2
    [ "$AUTH_OK" -eq 1 ] || echo "REFUSED: AGENT_PILOT_AUTH_MODE must be api-key or keychain-symlink; see this file's AUTHENTICATION header comment." >&2
    echo "Nothing has been called." >&2
  fi
  exit 0
fi

if [ "$AUTH_MODE" = api-key ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "REFUSED: AGENT_PILOT_AUTH_MODE=api-key but ANTHROPIC_API_KEY is not set in this shell." >&2
  echo "Nothing has been called." >&2
  exit 2
fi
if [ "$AUTH_MODE" = keychain-symlink ]; then
  echo "WARNING: AGENT_PILOT_AUTH_MODE=keychain-symlink -- every cell's PILOT_HOME/Library/Keychains" >&2
  echo "will be a read-only symlink to your real $HOME/Library/Keychains. Every arm in this run has" >&2
  echo "Bash, including the unaudited general-purpose subagent, so this is real, understood, exposure" >&2
  echo "to your entire login keychain for the duration of the run, not just Claude Code's entry." >&2
fi

# --- everything below this line spends model calls and only runs after all three gates are open --

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-pilot.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
RUNLOG="${RUNLOG:-$ROOT/runs.tsv}"
. "$SRC/tests/evals/lib/runlog.sh"
open_runlog "$RUNLOG" "$(printf 'role\tfixture_id\tarm\tcell_id\texit\tverdict\tinput_tokens\toutput_tokens\tseconds')" || exit 2
echo "log: $RUNLOG" >&2

# One PILOT_HOME per cell. Never the real $HOME. What each mode carries into it is exactly what
# this file's AUTHENTICATION header comment says and no more.
new_pilot_home() {
  local h; h=$(mktemp -d "${TMPDIR:-/tmp}/agent-pilot-home.XXXXXX")
  mkdir -p "$h/.claude"
  if [ "$AUTH_MODE" = keychain-symlink ]; then
    mkdir -p "$h/Library"
    ln -s "$HOME/Library/Keychains" "$h/Library/Keychains"
    [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$h/.claude.json" 2>/dev/null
  fi
  # api-key mode carries nothing: ANTHROPIC_API_KEY travels with the process environment, not
  # with a file, and needs no path inside PILOT_HOME at all.
  printf '%s' "$h"
}

# task_for <fixture-or-canary-id> -> the task text from ground-truth.json
task_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].task)' "$GT"; }
file_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].file)' "$GT"; }
delivered_as_for() { jq -r --arg id "$1" '([.fixtures[]?, .canary?] | map(select(.id==$id)) | .[0].delivered_as)' "$GT"; }

run_cell() { # <role> <fixture-id> <arm> <cell-id>
  local role="$1" fid="$2" arm="$3" cid="$4"
  local task tools src_file dst_name wd ph cap exitf t0 secs ec verdictline verdict tokens_in tokens_out prompt

  task=$(task_for "$fid")
  tools=$(role_tools "$role") || { echo "run_cell $cid: role_tools failed, skipping" >&2; return 1; }
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
    # shellcheck disable=SC2086  # intentional word-split: $tools is role_tools()'s derived
    # space-separated list, and --allowedTools takes multiple argv tokens (tests/team-gating.sh's
    # demonstrated form), not one comma-joined string; quoting it would pass one invalid tool name.
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

if [ "$ACTION" = canary ]; then
  echo "agent-pilot -- spending up to $(enumerate_canary_cells | grep -c .) calls now (canary only)." >&2
  enumerate_canary_cells | while IFS=$'\t' read -r r f a c; do
    run_cell "$r" "$f" "$a" "$c"
  done
  echo >&2
  echo "done. Raw rows: $RUNLOG" >&2
  echo "All three rows should read FOUND. Anything else: see PREREGISTRATION.md, 'The canary', for" >&2
  echo "what each other verdict on each arm means before running --go." >&2
else
  echo "agent-pilot -- spending up to $(( $(enumerate_cells | grep -c .) + $(enumerate_canary_cells | grep -c .) )) calls now." >&2
  { enumerate_canary_cells; enumerate_cells; } | while IFS=$'\t' read -r r f a c; do
    run_cell "$r" "$f" "$a" "$c"
  done
  echo >&2
  echo "done. Raw rows: $RUNLOG" >&2
  echo "Score the three canary-* rows first -- PREREGISTRATION.md says what a non-FOUND canary" >&2
  echo "verdict on any arm means for the other 24 rows before interpreting them as a result." >&2
fi
