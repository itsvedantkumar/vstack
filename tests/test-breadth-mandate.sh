#!/usr/bin/env bash
# test-breadth-mandate.sh — the hand-runnable reproduction of the breadth mandate inside
# claude/hooks/skill-mandate.sh (multi-directory, multi-type work with zero subagents).
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
# subject is the breadth mandate specifically, so every assertion below matches the literal
# "multi-directory work --" line inside .reason rather than treating any block as proof --
# a block from an unrelated mandate in the same fixture is not evidence about this one.
# Where that confound is unavoidable (PROOF 2's doc/HOOK.md also triggers `unslop`, PROOF 4's
# six .md files do too) the comment beside the fixture says so and the assertion is scoped to
# ignore it.
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
# skill-mandate.sh's 2-strike latch (a session that hits 2 blocks stops blocking, so the
# gate cannot trap someone it cannot get through to) persists in a file keyed by session_id
# under $TMPDIR, not under $WORK -- it has to survive across the hook's own separate
# invocations within one real session. This suite reuses fixed session ids (proof1..proof4)
# on every run, so without cleanup a 3rd consecutive run (exactly the "run it by hand while
# iterating on the mandate" workflow tests/README.md documents) would find PROOF 2's counter
# already at 2 and see the hook abstain on a genuinely unmet mandate -- a false FAIL with the
# code untouched. Sweep any stale counters before running and after, so every run starts and
# ends from the same state the hook sees on a session it has never met.
sweep_latch_(){
  rm -f "${TMPDIR:-/tmp}"/vstack-mandate-proof[1-6] 2>/dev/null
  rm -rf "${TMPDIR:-/tmp}"/vstack-mandate-proof[1-6].lock 2>/dev/null
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

# --- PROOF 3: same file spread as PROOF 2, plus one attributed Task call -----------------------
# Negative direction, and the exact defect SCARY-TERRY found: the original fixture added a
# bare Task call with no call-sign text, which trips the *agent naming* mandate (Task
# dispatched, nobody attributed) and makes the hook block for a reason that has nothing to do
# with breadth counting. The Task call here carries a roster call sign in assistant text
# (BIRDPERSON) specifically so agent naming is satisfied and cannot confound this proof.
# doc/HOOK.md still trips `unslop`, same as PROOF 2, and is ignored the same way -- what must
# hold is that task_count>=1 (one delegated subagent) suppresses the breadth line, even though
# the file spread by itself would have earned it per PROOF 2.
say_ '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"Write","input":{"file_path":"hook.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"2","name":"Write","input":{"file_path":"test/hook.test.sh","content":"#!/bin/bash"}},{"type":"tool_use","id":"3","name":"Write","input":{"file_path":"doc/HOOK.md","content":"# Hook"}},{"type":"tool_use","id":"4","name":"Write","input":{"file_path":"manifest.json","content":"{}"}},{"type":"tool_use","id":"5","name":"Task","input":{"skill":"code-reviewer"}},{"type":"text","text":"Dispatching BIRDPERSON B-1 to review."}]}}'
run_hook_ proof3
if ! names_breadth_; then
  ok "PROOF 3: same spread as PROOF 2, attributed Task call -> breadth mandate silent"
else
  bad "PROOF 3: same spread as PROOF 2, attributed Task call -> breadth mandate silent" \
      "expected no 'multi-directory work --' line once a Task call is present, got: reason=[$HOOK_REASON]"
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

echo
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"
  FAIL=1
fi
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ]
exit $?
