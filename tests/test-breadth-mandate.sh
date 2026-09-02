#!/usr/bin/env bash
# test-breadth-mandate.sh — the hand-runnable reproduction of two mandates inside
# claude/hooks/skill-mandate.sh: the breadth mandate (multi-directory, multi-type work with
# zero subagents, PROOFs 1-6 and 10-12) and the prove-it-works mandate (a completion claim
# closing a turn that edited a file and produced zero verifying evidence, PROOFs 7-9). The name
# is now narrower than the file's scope; it stayed rather than churn every call site over a
# rename. PROOFs 10-12 cover the dispatch-tool-name defect (task_count only ever recognized
# "Task", never the "Agent" name the Claude Agent SDK build actually uses) and the Bash
# write-extraction over-match defect ($VAR-containing paths and heredoc-body content read as
# real writes) found by dogfooding this hook against a real 15MB transcript.
# PROOFs 22-24 cover the serial-tail mandate; the per-prompt digest's own tests live in tests/test-session-context-mandate.sh.
#
# The hook's contract (Claude Code Stop-hook protocol, not exit code): a met mandate prints
# nothing to stdout and exits 0; an unmet one prints one JSON object on stdout --
# {"decision":"block","reason":"..."} -- and STILL exits 0. Reading $? tells you nothing:
# it is 0 in both cases. The verdict has to come from parsing stdout as JSON and reading
# .decision, same as check 27 in .claude/verify.sh does with grep.
#
# The hook can report several unmet mandates in one .reason string (one line each, prefixed
# "<mandate name> -- "). A fixture that writes a .md file alongside a multi-directory sweep
# will legitimately trip both `unslop` and `multi-directory work` at once. This suite's
# subject is the breadth and prove-it-works mandates specifically, so every assertion below
# matches the literal "multi-directory work --" or "prove-it-works --" line inside .reason
# rather than treating any block as proof -- a block from an unrelated mandate in the same
# fixture is not evidence about the one under test. Where that confound is unavoidable
# (PROOF 2's doc/HOOK.md also triggers `unslop`, PROOF 4's six .md files do too) the comment
# beside the fixture says so and the assertion is scoped to ignore it.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/claude/hooks/skill-mandate.sh"
SELF="$repo_root/tests/test-breadth-mandate.sh"

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(grep -c '^# --- PROOF [0-9]' "$SELF")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

if ! command -v jq >/dev/null 2>&1; then
  skip "PROOF 1: one dir, one extension, zero Task -> breadth mandate silent" "jq not installed"
  skip "PROOF 2: three dirs, three extensions, zero Task -> breadth mandate blocks" "jq not installed"
  skip "PROOF 3: same spread as PROOF 2, attributed Task call -> breadth mandate silent" "jq not installed"
  skip "PROOF 4: six dirs, one extension, zero Task -> breadth mandate silent" "jq not installed"
  skip "PROOF 5: Bash-only sed/heredoc writes, three dirs, three extensions -> breadth mandate blocks" "jq not installed"
  skip "PROOF 6: Bash-only reads (grep/cat/git add/find/ls) across five dirs -> breadth mandate silent" "jq not installed"
  skip "PROOF 7: edit + closing completion claim, zero evidence -> prove-it-works blocks" "jq not installed"
  skip "PROOF 8: edit + real Bash command + closing completion claim -> prove-it-works silent" "jq not installed"
  skip "PROOF 9: closing completion claim with no edit in the turn -> prove-it-works silent" "jq not installed"
  skip "PROOF 10: three-dir/three-ext spread dispatched via the Agent tool -> breadth mandate silent" "jq not installed"
  skip "PROOF 11: Bash-only breadth writes, zero Task AND zero Agent calls -> breadth mandate blocks" "jq not installed"
  skip "PROOF 12: Bash write target containing an unexpanded \$VAR -> not counted as a write" "jq not installed"
  skip "PROOF 13: Task dispatch with is_error:true tool_result -> logged row's task_fail_count is 1" "jq not installed"
  skip "PROOF 14: Task dispatch with a clean (non-error) tool_result -> logged row's task_fail_count is 0" "jq not installed"
  skip "PROOF 15: three-dir/three-ext spread, two dispatches in ONE message -> breadth mandate silent (real fan-out)" "jq not installed"
  skip "PROOF 16: three-dir/three-ext spread, two dispatches in SEPARATE messages -> breadth mandate still blocks (serial, not fan-out)" "jq not installed"
  skip "PROOF 17: Task dispatch with no swarm call -> swarm mandate blocks" "jq not installed"
  skip "PROOF 18: Task dispatch preceded by a swarm Skill call -> swarm mandate silent" "jq not installed"
  skip "PROOF 19 (setup 1/3): lone prose write trips unslop" "jq not installed"
  skip "PROOF 19 (setup 2/3): lone TypeScript edit trips typescript-best-practices (unrelated 2nd strike)" "jq not installed"
  skip "PROOF 19 (the bleed): a THIRD, never-tried mandate still fires after two UNRELATED strikes" "jq not installed"
  skip "PROOF 22: three singleton dispatches, no batch -> serial-tail mandate blocks" "jq not installed"
  skip "PROOF 23: two singleton dispatches -> serial-tail mandate silent (below threshold)" "jq not installed"
  skip "PROOF 24: early 2-in-one-message batch, then three singletons -> serial-tail mandate still blocks (amnesty closed)" "jq not installed"
  skip "PROOF 25: turn text opening with a banned register phrase -> register mandate blocks" "jq not installed"
  skip "PROOF 26: banned words mid-line or without a boundary char -> register mandate silent" "jq not installed"
  skip "PROOF 27: two dirs, two extensions, zero Task -> breadth mandate blocks (1.66.0 threshold)" "jq not installed"
  skip "PROOF 28: one dir, two extensions, zero Task -> breadth mandate silent (dir floor holds)" "jq not installed"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  [ "$((RAN + SKIPPED))" -eq "$TOTAL" ] || { printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"; FAIL=1; }
  [ "$FAIL" -eq 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
  exit "$FAIL"
fi

if [ ! -x "$hook" ]; then
  bad "breadth mandate proofs" "$hook is missing or not executable"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vstack-mandate-breadth.XXXXXX")"

# skill-mandate.sh's delegation-drift logger (see the "delegation-drift logger" comment in the
# hook) writes one line per evaluated Stop to $VSTACK_DELEGATION_LOG, defaulting to the
# operator's real ~/.claude/vstack-delegation-log.jsonl when that var is unset. Every run_hook_
# call below is a synthetic fixture, not a real session, so it must never land there -- pointed
# at a file under $WORK instead, which the EXIT trap below already removes with everything else.
# Without this, a plain run of this suite writes ~12 synthetic lines into the real analysis log.
export VSTACK_DELEGATION_LOG="$WORK/delegation-log.jsonl"
# skill-mandate.sh's 2-strike latch (a session that hits 2 blocks stops blocking, so the
# gate cannot trap someone it cannot get through to) persists in a file keyed by session_id
# under $TMPDIR, not under $WORK -- it has to survive across the hook's own separate
# invocations within one real session. This suite reuses fixed session ids (proof1..proof9)
# on every run, so without cleanup a 3rd consecutive run (exactly the "run it by hand while
# iterating on the mandate" workflow tests/README.md documents) would find PROOF 2's counter
# already at 2 and see the hook abstain on a genuinely unmet mandate -- a false FAIL with the
# code untouched. Sweep any stale counters before running and after, so every run starts and
# ends from the same state the hook sees on a session it has never met.
sweep_latch_(){
  rm -f "${TMPDIR:-/tmp}"/vstack-mandate-*proof[0-9]* 2>/dev/null
  rm -rf "${TMPDIR:-/tmp}"/vstack-mandate-*proof[0-9]*.lock 2>/dev/null
}
sweep_latch_
trap 'sweep_latch_; rm -rf "$WORK"' EXIT

say_(){ printf '%s\n' "$1" > "$WORK/t.jsonl"; }

# Runs the hook against $WORK/t.jsonl and leaves the raw stdout in $HOOK_OUT, the parsed
# .decision in $HOOK_DECISION and the parsed .reason in $HOOK_REASON. Empty stdout (the
# "mandate met, say nothing" case) is handled before jq ever sees it -- feeding jq an empty
# string is a parse error, not a false negative, and that error must never read as a pass.
run_hook_(){
  HOOK_OUT=$(printf '{"transcript_path":"%s/t.jsonl","session_id":"%s","stop_hook_active":false}' \
             "$WORK" "$1" | bash "$hook" 2>/dev/null)
  if [ -z "$HOOK_OUT" ]; then
    HOOK_DECISION=""
    HOOK_REASON=""
  else
    HOOK_DECISION=$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)
    HOOK_REASON=$(printf '%s' "$HOOK_OUT" | jq -r '.reason // empty' 2>/dev/null)
  fi
}

names_breadth_(){ printf '%s' "$HOOK_REASON" | grep -qF 'multi-directory work --'; }
names_piw_(){ printf '%s' "$HOOK_REASON" | grep -qF 'prove-it-works --'; }
names_swarm_(){ printf '%s' "$HOOK_REASON" | grep -qF 'swarm --'; }
names_unslop_(){ printf '%s' "$HOOK_REASON" | grep -qF 'unslop --'; }
names_ts_(){ printf '%s' "$HOOK_REASON" | grep -qF 'typescript-best-practices --'; }
names_serial_(){ printf '%s' "$HOOK_REASON" | grep -qF 'serial dispatch tail --'; }
names_register_(){ printf '%s' "$HOOK_REASON" | grep -qF 'register -- banned opener'; }

# --- PROOF 1: 5 fixture writes, 1 directory, 1 extension, 0 Task calls ------------------------
# Negative direction. Mechanical repetition (fixtures/case1.json .. case5.json) must not read
# as multi-part work: 1 directory fails the >=3 threshold outright. No .md/.ts files and no
# Task calls are present, so this fixture has no other mandate to confound the read -- the hook
# must stay completely silent (empty stdout, exit 0), not merely "not the breadth message".
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"fixtures/case1.json","content":"{}"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"fixtures/case2.json","content":"{}"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"fixtures/case3.json","content":"{}"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"fixtures/case4.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Write","input":{"file_path":"fixtures/case5.json","content":"{}"}}]}}'
run_hook_ proof1
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 1: one dir, one extension, zero Task -> breadth mandate silent"
else
  bad "PROOF 1: one dir, one extension, zero Task -> breadth mandate silent" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 2: 4 files, 3 directories, 3 extensions, 0 Task calls -------------------------------
# Positive direction. hook.sh + manifest.json share the repo root (1 dir), test/hook.test.sh
# and doc/HOOK.md add 2 more (3 dirs total); extensions sh/json/md give 3 types. Both
# thresholds clear, zero delegation -> the breadth mandate must name itself in .reason.
# Confound, expected and ignored here: doc/HOOK.md also trips `unslop` (prose written,
# unslop never ran) in the same .reason string. That is a fact about a different mandate;
# this proof only asserts on the "multi-directory work --" line.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}}]}}'
run_hook_ proof2
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 2: three dirs, three extensions, zero Task -> breadth mandate blocks"
else
  bad "PROOF 2: three dirs, three extensions, zero Task -> breadth mandate blocks" \
      "expected decision=block naming 'multi-directory work --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 3: same file spread as PROOF 2, plus ONE attributed Task call (serial, not fanned) ---
# Negative direction for fan-out, positive direction for the bug this round fixes. Before the
# fan-out contract, the original fixture here asserted that ANY task_count>=1 silenced the
# breadth line -- which was the defect: one Task dispatch is not "work split into parts", it is
# a single delegation, and the mandate must still block on it. The Task call carries a roster
# call sign in assistant text (BIRDPERSON) specifically so *agent naming* is satisfied and
# cannot confound this proof -- a block here can only be about breadth. doc/HOOK.md still trips
# `unslop`, same as PROOF 2, ignored the same way. What must hold now: a single Task/Agent call,
# however attributed, is a fanout_batches of 0 (one dispatch is not a batch of 2+), so the
# breadth line still names itself.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Task","input":{"skill":"code-reviewer"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}'
run_hook_ proof3
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 3: same spread as PROOF 2, ONE attributed Task call -> breadth mandate still blocks (not a fan-out)"
else
  bad "PROOF 3: same spread as PROOF 2, ONE attributed Task call -> breadth mandate still blocks (not a fan-out)" \
      "expected decision=block naming 'multi-directory work --' (a single dispatch is not a fan-out), got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 4: 6 writes, 6 directories, 1 extension (.md), 0 Task calls -------------------------
# Negative direction, the other boundary: breadth alone (many directories) is not enough --
# ext_count must also be >=2, and a wide sweep of one file type is treated as focused work,
# not fan-out. Confound, expected and ignored: all six files are .md and unslop never ran, so
# `unslop` fires in the same .reason string. This proof only asserts the breadth line is absent.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"docs1/README.md","content":"# README"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"docs2/CONFIG.md","content":"# Config"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"docs3/API.md","content":"# API"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"docs4/SETUP.md","content":"# Setup"}},{"type":"tool_use","id":"5","name":"Write","input":{"file_path":"docs5/GUIDE.md","content":"# Guide"}},{"type":"tool_use","id":"6","name":"Write","input":{"file_path":"docs6/NOTES.md","content":"# Notes"}}]}}'
run_hook_ proof4
if ! names_breadth_; then
  ok "PROOF 4: six dirs, one extension, zero Task -> breadth mandate silent"
else
  bad "PROOF 4: six dirs, one extension, zero Task -> breadth mandate silent" \
      "expected no 'multi-directory work --' line for a single-extension sweep, got: reason=[$HOOK_REASON]"
fi

# --- PROOF 5: 3 Bash-only writes (sed -i, sed -i "", python heredoc open(w)), 0 Task calls -----
# Positive direction, and the exact defect this suite exists to catch: every edit made through
# Bash instead of Write/Edit/NotebookEdit was invisible to the breadth counter until now. This
# fixture is the v1.35.0 release shape that motivated the fix -- `sed -i.bak` on hooks/a.sh,
# `sed -i ""` (BSD empty-backup form) on lib/b.py, and a `python3 - <<PY` heredoc whose body calls
# `open("config/c.json", "w")` -- three tool_use blocks, all name="Bash", zero name="Write" or
# "Edit" anywhere in the transcript. 3 directories (hooks, lib, config), 3 extensions (sh, py,
# json), 0 Task calls: both thresholds clear on Bash-extracted paths alone. No .md or .ts path is
# produced by any rule, so there is no confound here -- an empty stdout would mean the extraction
# found nothing, not that a different mandate ate the block.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Bash","input":{"command":"sed -i.bak -e s/x/y/ hooks/a.sh"}},{"type":"tool_use","id":"2","name":"Bash","input":{"command":"sed -i \"\" -e s/a/b/ lib/b.py"}},{"type":"tool_use","id":"3","name":"Bash","input":{"command":"python3 - <<PY\nwith open(\"config/c.json\", \"w\") as f:\n    f.write(\"{}\")\nPY"}}]}}'
run_hook_ proof5
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 5: Bash-only sed/heredoc writes, three dirs, three extensions -> breadth mandate blocks"
else
  bad "PROOF 5: Bash-only sed/heredoc writes, three dirs, three extensions -> breadth mandate blocks" \
      "expected decision=block naming 'multi-directory work --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 6: 5 Bash-only reads (grep/cat/git add/find/ls) across five directories --------------
# Negative direction, and the false-positive risk the extraction has to stay clear of: a session
# that only reads and lists files -- across as many directories as PROOF 5's writes touched --
# must not read as multi-part work just because its arguments happen to span src/, docs/,
# config/, test/unit/ and web/app/. None of grep, cat, git add, find or ls is a recognized write
# shape, so the hook's own $paths (Bash-derived or otherwise) stays empty and there is nothing to
# count. This is the strict form of PROOF 1 -- not merely "no breadth line" but completely silent
# stdout, since this fixture has no prose or TypeScript write either to trip a different mandate.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Bash","input":{"command":"grep -rn TODO src/lib.py src/util.py"}},{"type":"tool_use","id":"2","name":"Bash","input":{"command":"cat docs/README.md docs/guide.md"}},{"type":"tool_use","id":"3","name":"Bash","input":{"command":"git add config/settings.json docs/README.md src/lib.py"}},{"type":"tool_use","id":"4","name":"Bash","input":{"command":"find test/unit -name *.sh"}},{"type":"tool_use","id":"5","name":"Bash","input":{"command":"ls -la web/app/index.ts"}}]}}'
run_hook_ proof6
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 6: Bash-only reads (grep/cat/git add/find/ls) across five dirs -> breadth mandate silent"
else
  bad "PROOF 6: Bash-only reads (grep/cat/git add/find/ls) across five dirs -> breadth mandate silent" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 7: one Edit, closing text claims completion, zero Bash/Read/Task in the turn --------
# Positive direction for the prove-it-works mandate: the turn edited src/parser.py and the last
# assistant text block in it is a completion claim ("it works now" matches the mandate's
# "\bworks now\b" alternative) with nothing in the turn that could have produced the evidence for
# that claim. Single file, single directory, single extension, zero Task calls -- none of the
# other mandates in this hook have anything to say about this fixture, so a block here can only
# be prove-it-works, but the assertion still names the specific line rather than trusting that.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Edit","input":{"file_path":"src/parser.py"}},{"type":"text","text":"Done. It works now."}]}}'
run_hook_ proof7
if [ "$HOOK_DECISION" = "block" ] && names_piw_; then
  ok "PROOF 7: edit + closing completion claim, zero evidence -> prove-it-works blocks"
else
  bad "PROOF 7: edit + closing completion claim, zero evidence -> prove-it-works blocks" \
      "expected decision=block naming 'prove-it-works --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 8: same edit, a real Bash call in between, then the same closing claim --------------
# Negative direction, the case the mandate exists not to block: the turn still edits
# src/parser.py and still closes with a completion claim ("all tests pass"), but a Bash tool_use
# now sits between the edit and the claim. The mandate treats any Bash call in the turn as
# evidence regardless of what it ran (see the comment above turn_json in skill-mandate.sh for
# why), so this must stay completely silent -- not merely lacking the prove-it-works line, since
# nothing else in this fixture (one .py file, no Task, no breadth) has grounds to block either.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Edit","input":{"file_path":"src/parser.py"}},{"type":"tool_use","id":"2","name":"Bash","input":{"command":"python3 -m pytest tests/test_parser.py -q"}},{"type":"text","text":"Done. All tests pass."}]}}'
run_hook_ proof8
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 8: edit + real Bash command + closing completion claim -> prove-it-works silent"
else
  bad "PROOF 8: edit + real Bash command + closing completion claim -> prove-it-works silent" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 9: a completion claim with no tool_use at all in the turn ----------------------------
# Negative direction, the false-positive shape the mandate exists to avoid: ordinary
# conversational closure ("we're all done for today" matches the mandate's "\ball done\b"
# alternative) with no file edit anywhere in the turn. The mandate requires an edit AND a claim
# AND zero evidence, all three -- a claim alone, however completion-shaped the wording, must
# never be enough on its own, or every ordinary end-of-turn "done" in every install would block.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sounds good — we are all done for today, thanks!"}]}}'
run_hook_ proof9
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 9: closing completion claim with no edit in the turn -> prove-it-works silent"
else
  bad "PROOF 9: closing completion claim with no edit in the turn -> prove-it-works silent" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 10: same file spread as PROOF 2/3, ONE Agent-named call (serial, not fanned) ---------
# Same fan-out semantics as PROOF 3, over the "Agent" dispatch-tool name (the Claude Agent SDK
# build's name for the same tool, see the "Dispatch-tool name" comment in the hook): the
# task_count OR-condition ("Task" or "Agent") is still exercised here, but fanout_batches is
# what decides the outcome now -- ONE Agent call, however attributed, is not a batch of 2+, so
# this must still block, not silence, the breadth line. Same 3-dir/3-ext spread, same roster
# call sign (BIRDPERSON) so agent naming cannot confound the read.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Agent","input":{"subagent_type":"code-reviewer","prompt":"review","description":"review"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}'
run_hook_ proof10
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 10: three-dir/three-ext spread, ONE Agent call -> breadth mandate still blocks (not a fan-out)"
else
  bad "PROOF 10: three-dir/three-ext spread, ONE Agent call -> breadth mandate still blocks (not a fan-out)" \
      "expected decision=block naming 'multi-directory work --' (a single dispatch is not a fan-out), got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 11: Bash-only breadth writes, zero Task AND zero Agent calls -------------------------
# Positive direction, guarding the dual-name OR condition itself rather than either name alone:
# three real sed -i / heredoc writes across hooks/, lib/ and config/ (the same shape PROOF 5
# already covers) with no tool_use named "Task" and none named "Agent" anywhere in the
# transcript. A fix that special-cased one name and silently dropped the other (or that always
# evaluated the OR as true) would pass PROOF 5 or PROOF 10 alone; this is the case where both
# names are genuinely absent and task_count must land on exactly 0, not on a stale true/false
# from whichever name was checked last.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Bash","input":{"command":"sed -i.bak -e s/x/y/ hooks/a.sh"}},{"type":"tool_use","id":"2","name":"Bash","input":{"command":"sed -i \"\" -e s/a/b/ lib/b.py"}},{"type":"tool_use","id":"3","name":"Bash","input":{"command":"python3 - <<PY\nwith open(\"config/c.json\", \"w\") as f:\n    f.write(\"{}\")\nPY"}}]}}'
run_hook_ proof11
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 11: Bash-only breadth writes, zero Task AND zero Agent calls -> breadth mandate blocks"
else
  bad "PROOF 11: Bash-only breadth writes, zero Task AND zero Agent calls -> breadth mandate blocks" \
      "expected decision=block naming 'multi-directory work --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 12: a Bash write target containing an unexpanded $VAR is not counted ------------------
# Negative direction for the second defect this round closes: three Bash redirects that, read
# literally, span 3 directories and 3 extensions ($OUT/app/src/a.ts, $OUT/lib/b.py,
# $OUT/doc/c.md) -- enough to clear both breadth thresholds if taken at face value. Every one of
# them writes to a path containing a literal, unexpanded shell variable, which was never a real
# file: it is a template the model quoted, not a location anything landed on. This is the exact
# shape a real session hit -- `$g_empty/app/src/C.tsx`, a fixture literal grep'd out of a test
# script -- read as three genuine files across three genuine directories. None of the three
# should survive extraction, so $paths stays empty and the hook must be completely silent, the
# same strict bar PROOF 1 and PROOF 6 hold.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Bash","input":{"command":"printf x > \"$OUT/app/src/a.ts\""}},{"type":"tool_use","id":"2","name":"Bash","input":{"command":"printf y > \"$OUT/lib/b.py\""}},{"type":"tool_use","id":"3","name":"Bash","input":{"command":"printf z > \"$OUT/doc/c.md\""}}]}}'
run_hook_ proof12
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 12: Bash write target containing an unexpanded \$VAR -> not counted as a write"
else
  bad "PROOF 12: Bash write target containing an unexpanded \$VAR -> not counted as a write" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 13: a Task dispatch whose tool_result carries is_error:true -> logged row's
#     task_fail_count is 1, not 0 ------------------------------------------------------------
# Positive direction for the delegation-drift ledger's failure-awareness field. Before this, the
# logged row recorded task_count (a dispatch happened) with nothing to say whether it succeeded --
# task_fail_count is the field that closes that gap, correlating the Task/Agent tool_use's own
# id against a LATER "user"-type transcript entry carrying {type:"tool_result",
# tool_use_id:<id>, is_error:true}, the same correlation tests/compaction-effect.py already
# relies on for its own is_error rate (confirmed there against real transcripts). BIRDPERSON is
# named in assistant text so the agent-naming mandate is satisfied and cannot confound this
# proof; the assertion is on the LOGGED ROW, not on decision/reason.
last_log_row_(){ tail -n 1 "$VSTACK_DELEGATION_LOG" 2>/dev/null; }
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review this"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}\n{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"1","is_error":true,"content":"agent errored"}]}}'
run_hook_ proof13
row13=$(last_log_row_)
tfc13=$(printf '%s' "$row13" | jq -r '.task_fail_count // "MISSING"' 2>/dev/null)
tc13=$(printf '%s' "$row13" | jq -r '.task_count // "MISSING"' 2>/dev/null)
if [ "$tc13" = "1" ] && [ "$tfc13" = "1" ]; then
  ok "PROOF 13: Task dispatch with is_error:true tool_result -> logged row's task_fail_count is 1"
else
  bad "PROOF 13: Task dispatch with is_error:true tool_result -> logged row's task_fail_count is 1" \
      "expected task_count=1 task_fail_count=1 in the logged row, got: $row13"
fi

# --- PROOF 14: a Task dispatch that resolves cleanly (no is_error) -> task_fail_count is 0,
#     never null or missing -----------------------------------------------------------------
# Negative direction, same shape as PROOF 3's positive/negative pairing: a successful dispatch
# must not be counted as a failure, and the field itself must always be a real 0, not an absent
# key that a downstream reader could misread as "field not supported" -- distinguishing "zero
# failures measured" from "failure-awareness is not present in this row" is the whole point.
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review this"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}\n{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"1","content":"looks good"}]}}'
run_hook_ proof14
row14=$(last_log_row_)
tfc14=$(printf '%s' "$row14" | jq -r '.task_fail_count // "MISSING"' 2>/dev/null)
tc14=$(printf '%s' "$row14" | jq -r '.task_count // "MISSING"' 2>/dev/null)
if [ "$tc14" = "1" ] && [ "$tfc14" = "0" ]; then
  ok "PROOF 14: Task dispatch with a clean (non-error) tool_result -> logged row's task_fail_count is 0"
else
  bad "PROOF 14: Task dispatch with a clean (non-error) tool_result -> logged row's task_fail_count is 0" \
      "expected task_count=1 task_fail_count=0 in the logged row, got: $row14"
fi

# --- PROOF 15: breadth-eligible spread, TWO Task/Agent calls in ONE message -> fan-out, satisfied
# Positive control for the fan-out contract itself: the same 3-dir/3-ext file spread as PROOF
# 2/3/10, but this time TWO dispatch tool_use blocks (one "Task", one "Agent") sit in the SAME
# message's content array, alongside the roster call sign so agent naming cannot confound the
# read. This is what Claude Code actually runs concurrently -- every tool_use block inside one
# assistant message executes together, results land in the next turn. fanout_batches must see
# this as one batch of 2 and the breadth line must go silent, same outcome PROOF 3/10 used to
# assert for a single dispatch (now correctly denied there) and correctly grants here.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Task","input":{"skill":"code-reviewer"}},{"type":"tool_use","id":"6","name":"Agent","input":{"subagent_type":"qa","prompt":"verify","description":"verify"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 and JAGUAR J-1 together to review and verify."}]}}'
run_hook_ proof15
if ! names_breadth_; then
  ok "PROOF 15: three-dir/three-ext spread, two dispatches in ONE message -> breadth mandate silent (real fan-out)"
else
  bad "PROOF 15: three-dir/three-ext spread, two dispatches in ONE message -> breadth mandate silent (real fan-out)" \
      "expected no 'multi-directory work --' line for a same-message 2-way dispatch, got: reason=[$HOOK_REASON]"
fi

# --- PROOF 16: breadth-eligible spread, TWO Task/Agent calls in SEPARATE messages -> serial, unmet
# Negative control, and the exact serial-loop shape the old `task_count -eq 0` gate could not
# see: same 3-dir/3-ext spread as PROOF 15, but the two dispatches land in TWO SEPARATE assistant
# JSONL lines (no shared message.id -- the same shape a fixture, or a real transcript with no id
# set, produces for two genuinely sequential turns) instead of one. task_count is 2 either way,
# identical to PROOF 15's total -- the only difference between "satisfied" and "unmet" here is
# whether those 2 dispatches ever shared a message, not how many there were. Confirmed against
# the pre-fix hook (git HEAD's committed version, before this round's changes): with the old
# `task_count -eq 0` condition, task_count=2 made this fixture read as satisfied (silent) exactly
# like PROOF 15, unable to tell a real batch from two serial ones. The roster call sign sits in
# the first message so agent naming cannot confound the read.
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Task","input":{"skill":"code-reviewer"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"6","name":"Agent","input":{"subagent_type":"qa","prompt":"verify","description":"verify"}}]}}'
run_hook_ proof16
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 16: three-dir/three-ext spread, two dispatches in SEPARATE messages -> breadth mandate still blocks (serial, not fan-out)"
else
  bad "PROOF 16: three-dir/three-ext spread, two dispatches in SEPARATE messages -> breadth mandate still blocks (serial, not fan-out)" \
      "expected decision=block naming 'multi-directory work --' (2 serial dispatches are not a fan-out), got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 17: one Task dispatch, swarm skill never called -> swarm mandate blocks ---------------
# Positive direction for the new swarm mandate (TASK 1, coordinator-directed): the operator rule
# is "every dispatch goes through the swarm skill first". One Task call, no Write/Edit anywhere
# (so breadth/prose/TS cannot confound the read), a roster call sign (BIRDPERSON) so agent naming
# is satisfied and cannot confound either -- a block here can only be the swarm line. No Skill
# tool_use named "swarm" appears anywhere in the transcript, so this must block.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review this"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}'
run_hook_ proof17
if [ "$HOOK_DECISION" = "block" ] && names_swarm_; then
  ok "PROOF 17: Task dispatch with no swarm call -> swarm mandate blocks"
else
  bad "PROOF 17: Task dispatch with no swarm call -> swarm mandate blocks" \
      "expected decision=block naming 'swarm --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 18: one Task dispatch, swarm skill called first -> swarm mandate silent ---------------
# Negative direction, the same fixture as PROOF 17 with one addition: a Skill tool_use naming
# "swarm" ahead of the Task call in the same message. $skills (used by fired(), the same function
# the unslop/typescript-best-practices mandates already use) is a session-wide set, not order-
# sensitive, so where in the message the Skill call sits does not matter here -- only that it is
# present. This must not name the swarm line.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Skill","input":{"skill":"swarm"}},{"type":"tool_use","id":"2","name":"Task","input":{"prompt":"review this"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}'
run_hook_ proof18
if ! names_swarm_; then
  ok "PROOF 18: Task dispatch preceded by a swarm Skill call -> swarm mandate silent"
else
  bad "PROOF 18: Task dispatch preceded by a swarm Skill call -> swarm mandate silent" \
      "expected no 'swarm --' line once the swarm skill was called, got: reason=[$HOOK_REASON]"
fi

# --- PROOF 19: setup 1/2 for the bleed test -- a lone prose write trips unslop -----------------
# First of a three-Stop sequence sharing ONE session_id (proof19b below), the bleed itself
# (coordinator-directed): f4f5468 already proved a SHARED counter across unrelated mandates is a
# real, measured defect at the family level (skill strikes disarming the delegation breadth
# mandate for 7 Stops of a real session). The same shape survived one level down, inside the
# skill family itself, where unslop/typescript-best-practices/prove-it-works shared one counter
# -- so two strikes on ANY MIX of those three, not necessarily the same one twice, reached the
# shared cap and silenced whichever of the three had never even been tried. This Stop trips ONLY
# unslop (a lone .md write) -- strike 1 of 2 on the SHARED counter the old code used, strike 1 of
# 2 on unslop's own counter under the fix.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"/x/README.md"}}]}}'
run_hook_ proof19b
if [ "$HOOK_DECISION" = "block" ] && names_unslop_; then
  ok "PROOF 19: lone prose write trips unslop (bleed setup 1/3)"
else
  bad "PROOF 19: lone prose write trips unslop (bleed setup 1/3)" \
      "expected decision=block naming 'unslop --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 20: setup 2/2 for the bleed test -- a lone, UNRELATED TypeScript edit, same session --
# Same session_id as PROOF 19 (proof19b), a FRESH transcript (nothing carries over between Stops
# except the on-disk counters, so this cannot be confused with PROOF 19's own file). Trips ONLY
# typescript-best-practices. That is two strikes total across the sequence so far, on two
# DIFFERENT mandates, neither one hit twice -- exactly what the old SHARED counter could not
# distinguish from "one mandate hit twice", because it was one integer either way.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Edit","input":{"file_path":"/x/App.tsx"}}]}}'
run_hook_ proof19b
if [ "$HOOK_DECISION" = "block" ] && names_ts_; then
  ok "PROOF 20: lone TypeScript edit trips typescript-best-practices, unrelated 2nd strike (bleed setup 2/3)"
else
  bad "PROOF 20: lone TypeScript edit trips typescript-best-practices, unrelated 2nd strike (bleed setup 2/3)" \
      "expected decision=block naming 'typescript-best-practices --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 21: the bleed itself -- a THIRD, never-tried mandate must still fire ------------------
# Same session_id again (proof19b), swapped to a THIRD, independent mandate's own trigger
# (prove-it-works's PROOF-7 shape: an Edit plus a closing completion claim, zero Bash/Read/
# Task/Agent in the turn), never itself unmet before this Stop. Under the OLD shared-counter code
# this must NOT fire -- silenced by the two unrelated prior strikes on unslop and
# typescript-best-practices, neither of which is prove-it-works. Under the per-mandate latch it
# must fire normally, because prove-it-works's own counter is still at 0: this is the assertion
# f4f5468 was missing one level up, and the one the coordinator asked to see red before green.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Edit","input":{"file_path":"src/parser.py"}},{"type":"text","text":"Done. It works now."}]}}'
run_hook_ proof19b
if [ "$HOOK_DECISION" = "block" ] && names_piw_; then
  ok "PROOF 21: a THIRD, never-tried mandate still fires after two UNRELATED strikes (the bleed)"
else
  bad "PROOF 21: a THIRD, never-tried mandate still fires after two UNRELATED strikes (the bleed)" \
      "expected decision=block naming 'prove-it-works --' -- two strikes on unslop+typescript must not silence a mandate neither of them is, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 22: three singleton Task/Agent dispatches, zero batches -> serial-tail blocks --------
# Positive direction for the serial-tail mandate: three dispatches, each alone in its own
# assistant line (no shared message.id), is the serial loop measured in real transcripts
# (e0cd5a40: 12 singleton dispatches, never a batch). Swarm called and RICK named so no other
# delegation mandate can confound; zero writes so no skill mandate can either.
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"0","name":"Skill","input":{"skill":"swarm"}},{"type":"text","text":"RICK: routing three reviews."}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review a"}}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"2","name":"Task","input":{"prompt":"review b"}}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"3","name":"Agent","input":{"subagent_type":"qa","prompt":"review c","description":"review c"}}]}}'
run_hook_ proof22
if [ "$HOOK_DECISION" = "block" ] && names_serial_; then
  ok "PROOF 22: three singleton dispatches, no batch -> serial-tail mandate blocks"
else
  bad "PROOF 22: three singleton dispatches, no batch -> serial-tail mandate blocks" \
      "expected decision=block naming 'serial dispatch tail --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 23: two singleton dispatches -> below the tail-3 threshold, strictly silent ----------
# Negative direction: two serial dispatches are the shape a session legitimately produces when
# two unrelated asks arrive in two turns (416fb382's post-block tail of 2). Nothing else in the
# fixture can block, so the bar is strict empty stdout, not merely "no serial-tail line".
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"0","name":"Skill","input":{"skill":"swarm"}},{"type":"text","text":"RICK: routing two reviews."}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review a"}}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"2","name":"Task","input":{"prompt":"review b"}}]}}'
run_hook_ proof23
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 23: two singleton dispatches -> serial-tail mandate silent (below threshold)"
else
  bad "PROOF 23: two singleton dispatches -> serial-tail mandate silent (below threshold)" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 24: an early real batch, then three singletons -> still blocks (amnesty closed) ------
# The whole-transcript amnesty itself: fanout_batches=1 from the 2-in-one-message batch, so the
# breadth mandate's own condition (fanout_batches == 0) can never be true again this session --
# measured in real transcripts (3ce9f899: 3 early batches then 25 serial dispatches unblocked;
# 8959d943: 2 batches of 2 then 9 serial). The serial-tail mandate reads only the dispatches
# AFTER the last batch: three singletons -> block, early batch or not.
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"0","name":"Skill","input":{"skill":"swarm"}},{"type":"text","text":"RICK: batch first."}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Task","input":{"prompt":"review a"}},{"type":"tool_use","id":"2","name":"Agent","input":{"subagent_type":"qa","prompt":"verify","description":"verify"}},{"type":"text","text":"ZEEP and GLOOTIE together."}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"3","name":"Task","input":{"prompt":"review b"}}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"4","name":"Task","input":{"prompt":"review c"}}]}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"5","name":"Agent","input":{"subagent_type":"qa","prompt":"review d","description":"review d"}}]}}'
run_hook_ proof24
if [ "$HOOK_DECISION" = "block" ] && names_serial_; then
  ok "PROOF 24: early 2-in-one-message batch, then three singletons -> serial-tail mandate still blocks (amnesty closed)"
else
  bad "PROOF 24: early 2-in-one-message batch, then three singletons -> serial-tail mandate still blocks (amnesty closed)" \
      "expected decision=block naming 'serial dispatch tail --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 25: turn text opening with a banned register phrase -> register blocks ---------------
# Positive direction for the register mandate: an assistant text block whose line starts with a
# banned CLAUDE.md REGISTER opener ("Let me ..."). Zero writes, zero dispatches, so no other
# mandate can confound; the block must name the phrase it matched so the reader knows what to
# delete, not just that something tripped.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me look at the failing lane before touching anything."}]}}'
run_hook_ proof25
if [ "$HOOK_DECISION" = "block" ] && names_register_; then
  ok "PROOF 25: turn text opening with a banned register phrase -> register mandate blocks"
else
  bad "PROOF 25: turn text opening with a banned register phrase -> register mandate blocks" \
      "expected decision=block naming 'register -- banned opener', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 26: banned words mid-line or without a boundary char -> register stays silent --------
# Negative direction, both anchors in one fixture: "Right-sizing" starts a line but "-" is not in
# the [,! .] boundary class (vocabulary, not an acknowledgement token), and "Great," appears only
# mid-line, which the ^ anchor must ignore. Nothing else in the fixture can block, so the bar is
# strict empty stdout.
say_ $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Right-sizing the buffer comes later.\\nThe run passed twice. Great, both agree."}]}}'
run_hook_ proof26
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 26: banned words mid-line or without a boundary char -> register mandate silent"
else
  bad "PROOF 26: banned words mid-line or without a boundary char -> register mandate silent" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 27: 2 files, 2 directories, 2 extensions, 0 Task calls -----------------------------
# Positive direction for the 1.66.0 threshold. src/a.sh and lib/b.py span 2 directories and 2
# extensions -- below the old dir>=3 floor, so this exact shape was NEVER gated before and is the
# common cross-cutting edit the lowered threshold now catches. No .md/.ts and no Task calls, so
# nothing else can confound the read; the breadth mandate must name itself.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"src/a.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"lib/b.py","content":"x=1"}}]}}'
run_hook_ proof27
if [ "$HOOK_DECISION" = "block" ] && names_breadth_; then
  ok "PROOF 27: two dirs, two extensions, zero Task -> breadth mandate blocks (1.66.0 threshold)"
else
  bad "PROOF 27: two dirs, two extensions, zero Task -> breadth mandate blocks (1.66.0 threshold)" \
      "expected decision=block naming 'multi-directory work --', got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

# --- PROOF 28: 2 files, 1 directory, 2 extensions, 0 Task calls --------------------------------
# Negative direction. src/a.sh and src/b.py are 2 extensions but one directory, so dir_count is 1
# and the >=2 floor is not met even after the lowering. The AND with the dir floor must still
# hold -- two file types inside a single directory is not multi-directory work -- so the hook
# stays completely silent.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"src/a.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"src/b.py","content":"x=1"}}]}}'
run_hook_ proof28
if [ -z "$HOOK_OUT" ]; then
  ok "PROOF 28: one dir, two extensions, zero Task -> breadth mandate silent (dir floor holds)"
else
  bad "PROOF 28: one dir, two extensions, zero Task -> breadth mandate silent (dir floor holds)" \
      "expected empty stdout, got: decision=$HOOK_DECISION reason=[$HOOK_REASON]"
fi

echo
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"
  FAIL=1
fi
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ]
exit $?
