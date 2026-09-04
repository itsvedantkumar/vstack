#!/usr/bin/env bash
# verify.sh — proof that this bundle is installable and portable.
#
# Run by the verify-gate.sh Stop hook: a non-zero exit blocks an agent from claiming the
# work is done.
#
# A check that needs a missing tool SKIPs, but check 0 fails when that tool is one this
# gate depends on, and the accounting line at the bottom proves every declared check
# actually reported. That combination is deliberate: three checks used to be wrapped in a
# bare `if command -v jq` with no else, so on a host without jq they printed nothing at all
# and the operator read VERIFIED off a gate that had run eight of thirteen checks.
set -uo pipefail
SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Refuse to measure a tree that something else is deliberately breaking.
#
# tests/gate-falsifiability.sh mutates one payload file at a time and restores it. Anyone running
# the gate inside that window gets a real FAIL naming a defect that does not exist, and it reads
# exactly like a finding. Three sessions sharing this checkout chased three of them. Silence would
# be worse and a plausible wrong answer is worse still, so say what is happening and exit non-zero.
#
# Skipped when the harness is the caller (it exports VSTACK_FALSIFY), and a lock whose process has
# died is ignored rather than honoured -- a killed run must not wedge the gate for everyone.
if [ -z "${VSTACK_FALSIFY:-}" ]; then
  # --git-common-dir, not --git-dir: the latter is PER-WORKTREE, so a lock written by the
  # falsifiability harness in one worktree would be invisible to a verify.sh run in another
  # worktree of the same repo. --git-common-dir is the same path from every worktree.
  _lk="$(git rev-parse --git-common-dir 2>/dev/null)/vstack-falsifiability.lock"
  if [ -f "$_lk" ] && kill -0 "$(head -1 "$_lk" 2>/dev/null)" 2>/dev/null; then
    # The lock is keyed on --git-common-dir on purpose (shared across every worktree of this
    # repo, see the comment above), which means the process holding it is not necessarily
    # working THIS worktree -- a run here once said "this working tree" while the actual
    # mutator was a harness in an unrelated /tmp worktree, which sends whoever reads it looking
    # for a planted defect in a tree that has none. Line 2 of the lock (if the writer recorded
    # one; tests/gate-falsifiability.sh and tests/inventory-fixture.sh both do, verify.sh's own
    # lock self-test at 14b below deliberately does not) is that process's cwd -- name it when
    # known instead of asserting a tree.
    _lk_pid=$(head -1 "$_lk" 2>/dev/null)
    _lk_cwd=$(sed -n 2p "$_lk" 2>/dev/null)
    if [ -n "$_lk_cwd" ]; then
      printf 'REFUSED  a process sharing this repository'"'"'s git directory (pid %s, working %s) is mutating a working tree.
' "$_lk_pid" "$_lk_cwd"
    else
      printf 'REFUSED  a process sharing this repository'"'"'s git directory (pid %s) is mutating a working tree (cwd not recorded).
' "$_lk_pid"
    fi
    printf '         Any result now would name a defect that process planted somewhere. Wait for it to finish.
'
    # A terminator, in the same position a real run puts VERIFIED. Without one, a refusal ends
    # with no verdict line at all, and anyone reading the output the way people actually read it
    # -- tail the last lines, or count FAIL lines -- sees zero failures and calls that green.
    # That is not hypothetical: it happened on 2026-08-27, in this repo, to the person adding
    # this line, in a commit message about labels overstating what they assert. The exit code
    # was always right. Nothing that has to be remembered is a control.
    printf 'NOT RUN  (refused; nothing was measured, so this is neither a pass nor a failure)
'
    exit 2
  fi
fi
# Lets check 14b exercise the three paths above without invoking the whole gate -- and, more to
# the point, without recursing: a nested full run would itself reach check 14b.
if [ -n "${VSTACK_GUARD_PROBE:-}" ]; then echo "GUARD_PASSED"; exit 0; fi

FAIL=0
RAN=0
SKIPPED=0
# Declared checks, counted from this file's own section headers, so adding a check cannot
# leave the accounting behind.
TOTAL=$(grep -c '^# --- [0-9]' "$SELF")
ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

# One selector, four callers. Checks 1, 12, 29 and 30 each need "the shell scripts in this
# repository" and each spelled it separately: a shebang scan, copied. That spelling missed
# ui-gate/rules/browser.sh and ui-gate/rules/tokens.sh -- real bash, sourced by ui-gate.sh,
# carrying `# shellcheck shell=bash` and no shebang because they are never executed directly.
# Nothing here parsed them and nothing linted them, in the subtree that exists to catch a gate
# reporting OK over nothing. That is the second miss for this predicate: bin/cloudflare-mcp
# (#!/bin/sh, no .sh suffix) was the first, and is why the shebang scan replaced a hand-list.
# The fix is not a third spelling, it is one.
#
# Three ways to be a shell script here, because the repo genuinely has all three: the suffix,
# the shebang, or a `# shellcheck shell=` directive for a fragment that has neither. .zsh is
# deliberately out -- shellcheck does not lint zsh and `bash -n` would misread it.
#
# Four callers, one tree walk. This used to re-run `git ls-files` and shebang-test every
# tracked file on every call -- four full sweeps of the repo for the same answer. Memoized:
# the first call pays for the walk, the rest read the cached list. `${_SH_FILES_CACHE+x}`
# distinguishes "never computed" from "computed and the repo genuinely has zero matches",
# which a plain `-z` check on the cache variable would conflate.
sh_files(){
  # bash 3.2 (macOS /bin/bash) fails to parse a `case` statement nested inside a `while` that
  # is itself inside `$(...)` -- confirmed by hand with a four-line reproduction -- so this
  # walk uses `[[ ... ]]` glob tests instead of `case`/`esac` here, unlike checks elsewhere in
  # this file that call `case` at top level, where the same bash parses it without complaint.
  if [ -z "${_SH_FILES_CACHE+x}" ]; then
    _SH_FILES_CACHE=$(git ls-files 2>/dev/null | while IFS= read -r f; do
      [ -f "$f" ] || continue
      if [[ "$f" == *.zsh ]]; then
        continue
      elif [[ "$f" == *.sh || "$f" == *.bash ]]; then
        printf '%s\n' "$f"
        continue
      fi
      if grep -q '^#!.*sh' <<<"$(head -1 "$f" 2>/dev/null)" \
      || grep -q '^#[[:space:]]*shellcheck[[:space:]]\+shell=' <<<"$(head -5 "$f" 2>/dev/null)"; then
        printf '%s\n' "$f"
      fi
    done)
  fi
  printf '%s\n' "$_SH_FILES_CACHE"
}

# --- 0. the toolchain this gate depends on is present -------------------------------------
# jq is core tier (README: install via ./setup-machine.sh). Five checks below need it and
# git. Reporting their absence as a quiet skip let a partial run masquerade as a full pass,
# so a missing dependency is a failure here and the skips below merely say which ones went.
missing=""
for t in jq git; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
[ -z "$missing" ] && ok "toolchain (jq, git)" \
  || bad "toolchain" "missing:$missing — install with ./setup-machine.sh, then re-run"

# --- 1. every shell script parses ----------------------------------------------------------
errs=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  out=$(bash -n "$f" 2>&1) || errs="$errs\n$f: $out"
done <<<"$(sh_files)"   # not a pipe: SIGPIPE + pipefail = 141
[ -z "$errs" ] && ok "shell syntax" || bad "shell syntax" "$(printf '%b' "$errs")"

# --- 2. every JSON file parses --------------------------------------------------------------
# The list used to be five hardcoded paths under a label that said every JSON file. The tree
# carries 12: the two .github protection rulesets, brand.schema.json, claude/inventory.json and
# three ground-truth.json fixtures were all outside it, and a malformed ruleset would have shipped
# green. Derived now, with a floor -- a derived list that silently shrinks to nothing is the exact
# failure this check exists for, so an empty or short selector is itself a failure.
#
# .jsonl is deliberately NOT swept: tests/evals/agent-pilot/selftest/truncated.jsonl is a fixture
# that is invalid on purpose, and a check that forced it to parse would delete the thing it tests.
if command -v jq >/dev/null && command -v git >/dev/null; then
  errs=""; njson=0
  for f in $(git ls-files '*.json'); do
    njson=$((njson + 1))
    [ -f "$f" ] || { errs="$errs\n$f: tracked but not on disk"; continue; }
    jq -e . "$f" >/dev/null 2>&1 || errs="$errs\n$f: invalid JSON"
  done
  # A floor of 10 against a tree of 12 is a coarse instrument and does not pretend otherwise: it
  # catches the selector collapsing, not one file going missing. The named-five loop below is the
  # precise half, and it is the one that would fail if a shipped manifest left the set.
  [ "$njson" -ge 10 ] \
    || errs="$errs\nonly $njson tracked .json file(s) found; the selector has collapsed (12 at 1.46.0)"
  for f in claude/settings.json mcp/servers.json claude/hooks/hooks.json \
           .claude-plugin/marketplace.json claude/.claude-plugin/plugin.json; do
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 \
      || errs="$errs\n$f is not in the derived set; the selector no longer covers what installs"
  done
  [ -z "$errs" ] && ok "json valid ($njson tracked .json files, derived; .jsonl excluded on purpose)" \
                 || bad "json valid" "$(printf '%b' "$errs")"
else
  skip "json valid" "jq or git not installed"
fi

# Frontmatter, parsed rather than grepped. Checks 3 and 10 both used to ask only whether SOME line
# in the file started with name: or description:, which passes a file with no frontmatter, one
# whose block is never closed, and one whose only description: sits in a fenced example halfway
# down. None of those load. The block is what the loader reads, so the block is what this reads.
fm_block(){ # <file>  -> the frontmatter body, empty if the file has no closed block at line 1
  awk 'NR==1 && $0 != "---" { exit 1 }
       NR==1 { next }
       $0 == "---" { closed=1; exit }
       { print }
       END { if (!closed) exit 1 }' "$1" 2>/dev/null
}

# --- 3. skills are loadable ------------------------------------------------------------------
# A skill with no description, or one longer than the configured listing cap, gets truncated
# out of the listing and silently stops auto-triggering. That is the failure this catches.
CAP=200
if command -v jq >/dev/null; then
  CAP=$(jq -r '.skillListingMaxDescChars // 200' claude/settings.json 2>/dev/null || echo 200)
fi
errs=""; n=0
for s in claude/skills/*/SKILL.md; do
  [ -e "$s" ] || continue
  n=$((n+1))
  dir=$(basename "$(dirname "$s")")
  if ! fm=$(fm_block "$s"); then
    errs="$errs\n$dir: no closed YAML frontmatter block at the top of SKILL.md"
    continue
  fi
  name=$(printf '%s\n' "$fm" | awk -F': *' '/^name:/{print $2; exit}' | tr -d '"')
  desc=$(printf '%s\n' "$fm" | awk '/^description:/{sub(/^description: */,""); print; exit}' | tr -d '"')
  [ -n "$name" ] || errs="$errs\n$dir: no name in frontmatter"
  [ "$name" = "$dir" ] || errs="$errs\n$dir: name ($name) does not match directory"
  [ -n "$desc" ] || errs="$errs\n$dir: no description"
  # In the frontmatter only. A skill whose prose DISCUSSES disable-model-invocation -- this repo
  # ships one that does -- is not a skill that sets it.
  printf '%s\n' "$fm" | grep -q 'disable-model-invocation' \
    && errs="$errs\n$dir: disable-model-invocation blocks auto-trigger"
  # The length cap only bites skills whose description actually reaches the listing.
  # skillOverrides "off" hides the skill and "name-only" drops its description, so a long
  # description on those costs nothing and is not a defect.
  mode=on
  if command -v jq >/dev/null; then
    mode=$(jq -r --arg s "$dir" '.skillOverrides[$s] // "on"' claude/settings.json 2>/dev/null || echo on)
  fi
  if [ "$mode" = "on" ] && [ "${#desc}" -gt "$CAP" ]; then
    errs="$errs\n$dir: description ${#desc} chars > cap $CAP (listed, so it gets truncated)"
  fi
done
[ "$n" -gt 0 ] || errs="$errs\nno skills found"
[ -z "$errs" ] && ok "skills ($n) loadable (frontmatter block parsed, not grepped)" || bad "skills loadable" "$(printf '%b' "$errs")"

# Content scanner shared by checks 4-6.
#
# Two deliberate departures from the `grep -rn . 2>/dev/null` form these checks used to
# take. First it searches tracked files via git grep, not the worktree: an ignored scratch
# file under .context/ is not something this repo publishes, and scanning it turned the
# whole gate red over a file git had been told to ignore. Second it reads grep's exit
# status instead of discarding stderr — rc 1 means clean, but rc 2 or more means grep
# itself failed, and the old form turned that into empty output and read it as a pass.
scan(){ # label, ERE pattern, optional exclusion ERE
  label="$1"; pat="$2"; excl="${3:-}"
  if ! command -v git >/dev/null 2>&1; then skip "$label" "git not installed"; return; fi
  hits=$(git grep -InIE -e "$pat" 2>&1); rc=$?
  case "$rc" in
    0) [ -n "$excl" ] && hits=$(printf '%s\n' "$hits" | grep -vE "$excl")
       if [ -z "$hits" ]; then ok "$label"; else bad "$label" "$(printf '%s\n' "$hits" | head -5)"; fi ;;
    1) ok "$label" ;;
    *) bad "$label" "git grep failed (exit $rc), so this check proved nothing: $hits" ;;
  esac
}

# --- 4. nothing is pinned to the author machine ----------------------------------------------
# The bracket class keeps this pattern from matching its own source line. Generic
# placeholders in docs (/Users/you) are fine; a real account name is what breaks portability.
#
# The slash form alone was not enough. Claude Code names its transcript directories by
# replacing every non-alphanumeric character in the cwd with a dash, so a real home path also
# travels as -Users-<account>-..., and one of those shipped in a provenance doc through every
# green run of this check. Desktop and Conductor workspace paths leak the same way: they name
# the author's private repos rather than the account. All three accept <bracketed> placeholders,
# which is how the docs legitimately talk about these paths.
scan "no hardcoded home paths" \
  '(/Users/[A-Za-z0-9]|-Users-[A-Za-z0-9]|~/Desktop/[A-Za-z0-9]|conductor/workspaces/[A-Za-z0-9])' \
  '([/-]Users[/-](you|USER|user|username|name)\b|(~/Desktop|conductor/workspaces)/<)'

# --- 5. no credentials committed --------------------------------------------------------------
# Real token shapes, plus any KEY/TOKEN/SECRET/PASSWORD assigned a long opaque value. The
# example file assigns nothing, so it passes; a filled-in secrets.env would not. The three
# spellings of each keyword catch lowercase api_key= and Title_Case, which the uppercase-only
# class used to walk straight past.
scan "no committed secrets" \
  '(sk-ant-[A-Za-z0-9_-]{16,}|sk-proj-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|xoxb-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(KEY|TOKEN|SECRET|PASSWORD|key|token|secret|password|Key|Token|Secret|Password)[A-Za-z_]*=[A-Za-z0-9_/+-]{20,})'

# --- 6. no infrastructure identifiers ---------------------------------------------------------
# This repo is public and its routines are templates. Real Vercel project or team IDs, Claude
# Code environment IDs, and cloud routine trigger IDs identify live infrastructure, so they
# belong in a local copy, never here. Placeholders ending in _ID or _xxx pass.
scan "no infrastructure ids" \
  '(prj_|team_|env_|trig_)[A-Za-z0-9]{12,}' \
  '(YOUR_[A-Z_]*ID|_xxx|placeholder)'

# --- 7. every skill named in prose exists on disk ----------------------------------------------
# CLAUDE.md and the session hook route situations to skills by name. Deleting or renaming a
# skill leaves those references dangling and the routing silently dead — this is the drift the
# check catches. Names must resolve VERBATIM. This check used to accept a short principle name
# (prove-it-works) by prepending principle- itself, which made the gate more forgiving than the
# runtime: the model sees a skill listing containing only principle-prove-it-works and cannot
# resolve the short form, so eight routing entries pointed at names that do not exist while this
# check reported them present. Measured cost was four of eight principle skills never firing.
# Agent and command names are legitimate non-skill references; ALLOW covers generic hyphenated
# English and git plumbing that the token pattern also matches.
ALLOW='agent-written|auto-apply|auto-fire|cross-cutting|git-common-dir|is-inside-work-tree|multi-phase|one-line|one-step|options-survey|re-point|re-pins|re-pin|rev-parse|show-current|show-toplevel|symbolic-ref|to-the-point|token-efficient|name-only|per-prompt|session-context|session-start|operating-mode|two-line'
errs=""
# \b keeps a capitalized word (Per-prompt) from yielding a bogus mid-word token (er-prompt).
# Only the hook's heredoc prose is scanned — its shell code contains regex character classes
# (A-Za-z0-9) that shred into false skill-name tokens.
hook_prose=$(sed -n "/<<'EOF'/,/^EOF\$/p" claude/hooks/inject-session-context.sh)
for tok in $( { cat claude/CLAUDE.md; printf '%s\n' "$hook_prose"; } | grep -ohE '\b[a-z][a-z0-9]*(-[a-z0-9]+)+' | sort -u); do
  [ -d "claude/skills/$tok" ] && continue
  [ -f "claude/agents/$tok.md" ] && continue
  [ -f "claude/commands/$tok.md" ] && continue
  printf '%s' "$tok" | grep -qE "^($ALLOW)$" && continue
  errs="$errs\n$tok: referenced in prose but no such skill/agent/command"
done
[ -z "$errs" ] && ok "referenced skills exist" || bad "referenced skills exist" "$(printf '%b' "$errs")"

# --- 8. the settings merge program compiles ---------------------------------------------------
# The dry run cannot catch this: the jq merge only runs when DRY=0, so a syntax error in that
# program ships green and then aborts a real install halfway through. Run the same program
# here against a throwaway target. This check exists because exactly that happened.
if command -v jq >/dev/null; then
  # The invocation this extracts from is itself multi-line and \-continued (one --arg/--argjson
  # per line before the jq filter's opening quote), and how many lines that spans is not fixed --
  # it grew from one line to two when --argjson allowed was added, and the old "drop exactly the
  # first captured line" extraction silently fed the SECOND invocation line ("--argjson allowed
  # \"$ALLOWED_HOOKS_JSON\" '") into jq as if it were filter text, a syntax error that looked
  # like install.sh's program was broken when the bug was in how this check reads it. Drop every
  # line up to and including the one that ends in the filter's bare opening quote, however many
  # of them there are, rather than a fixed count.
  raw=$(sed -n "/^  jq -s --arg h /,/^  ' \"\$US\"/p" install.sh)
  prog=$(printf '%s\n' "$raw" | awk 'f==1{print} f==0 && /'"'"'[[:space:]]*$/{f=1}')
  prog=$(printf '%s\n' "$prog" | sed '$d')
  if [ -z "$prog" ]; then
    bad "settings merge program" "could not extract the jq program from install.sh"
  else
    # mktemp, not fixed /tmp names: two Conductor workspaces verifying at once would
    # otherwise clobber each other's scratch files mid-check.
    md=$(mktemp -d)
    out=$(printf '{}\n' > "$md/a.json"; cp claude/settings.json "$md/b.json";
          jq -s --arg h "/tmp/hooks" --argjson retired '["probe_retired_key"]' \
             --argjson cm_present false --argjson tsl_present false \
             --argjson allowed '["format","inject-session-context","verify-gate"]' \
             "$prog" "$md/a.json" "$md/b.json" 2>&1)
    if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      ok "settings merge program"
    else
      bad "settings merge program" "$out"
    fi
    rm -rf "$md"
  fi
else
  skip "settings merge program" "jq not installed"
fi

# --- 9. the installer runs ---------------------------------------------------------------------
# Dry run: exercises every code path in install.sh without touching the filesystem.
if command -v jq >/dev/null; then
  out=$(./install.sh --dry-run 2>&1)
  if [ $? -eq 0 ]; then ok "install.sh --dry-run"; else bad "install.sh --dry-run" "$out"; fi
else
  skip "install.sh --dry-run" "jq not installed"
fi

# --- 9b. overlay works against a repo that already has settings -------------------------------
# The overlay's merge branch only runs when the target has a .claude/settings.json — a fresh
# scratch repo never exercises it, which is exactly how a broken merge shipped once. Overlay
# into a temp repo seeded with existing settings and hooks, and require the merge to survive.
if command -v jq >/dev/null && command -v git >/dev/null; then
  od=$(mktemp -d)
  git -C "$od" init -q 2>/dev/null
  mkdir -p "$od/.claude"
  #
  # The target's own Stop hook and its own skillOverrides entry must both be there afterwards,
  # and vstack's must be there alongside them. This clause used to assert the opposite for
  # skillOverrides -- that the target's `ghost-skill` entry was GONE -- which was the wholesale
  # `.skillOverrides = $ship.skillOverrides` overwrite written down as a requirement. Overlay
  # cannot tell a target's dead override from its live one, and auditing a project's own config
  # was never its job; check 15 polices vstack's own entries, which is the separate claim.
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo repo-own"}]}]},"skillOverrides":{"ghost-skill":"off"},"permissions":{"allow":["Bash(ls)"]}}\n' > "$od/.claude/settings.json"
  if out=$(./overlay.sh "$od" 2>&1); then
    if jq -e '.permissions.allow[0] == "Bash(ls)"
              and (.skillOverrides["ghost-skill"] == "off")
              and ((.skillOverrides | length) > 1)
              and ([.hooks.Stop[]?.hooks[]?.command] | index("echo repo-own") != null)
              and ([.hooks.Stop[]?.hooks[]?.command] | map(test("verify-gate\\.sh")) | any)' \
         "$od/.claude/settings.json" >/dev/null 2>&1; then
      ok "overlay merge path"
    else
      bad "overlay merge path" \
          "$(printf 'the overlay did not merge by ownership. after overlay:\n%s' \
             "$(jq -c '{permissions,skillOverrides,stop:[.hooks.Stop[]?.hooks[]?.command]}' "$od/.claude/settings.json" 2>&1)")"
    fi
  else
    bad "overlay merge path" "$out"
  fi
  rm -rf "$od"
else
  skip "overlay merge path" "jq or git not installed"
fi

# --- 10. agents and commands are loadable ------------------------------------------------------
# Same failure class as check 3: frontmatter drift silently breaks discovery.
# The n>0 guards mirror check 3: an empty directory makes the glob expand to itself, and
# without a count this check would report green on a tree that had lost every agent.
# "Loadable" used to mean: somewhere in the file, a line starts with name: or description:. That
# passes a file with no frontmatter at all, one whose block is never closed, and one whose only
# `description:` sits in a fenced example halfway down -- none of which Claude Code will load.
# fm_block() (defined above check 3) takes the real thing: the file must OPEN with --- on line 1,
# and the block ends at the next --- line. Everything read below comes out of that block.
errs=""; na=0; nc=0
for f in claude/agents/*.md; do
  [ -e "$f" ] || continue
  na=$((na+1))
  b=$(basename "$f" .md)
  if ! fm=$(fm_block "$f"); then
    errs="$errs\nagents/$b: no closed YAML frontmatter block at the top of the file"
    continue
  fi
  name=$(printf '%s\n' "$fm" | awk -F': *' '/^name:/{print $2; exit}' | tr -d '"')
  desc=$(printf '%s\n' "$fm" | awk '/^description:/{sub(/^description: */,""); print; exit}')
  [ "$name" = "$b" ] || errs="$errs\nagents/$b: frontmatter name ($name) does not match filename"
  [ -n "$desc" ] || errs="$errs\nagents/$b: no description in frontmatter"
done
for f in claude/commands/*.md; do
  [ -e "$f" ] || continue
  nc=$((nc+1))
  b=$(basename "$f" .md)
  if ! fm=$(fm_block "$f"); then
    errs="$errs\ncommands/$b: no closed YAML frontmatter block at the top of the file"
    continue
  fi
  desc=$(printf '%s\n' "$fm" | awk '/^description:/{sub(/^description: */,""); print; exit}')
  [ -n "$desc" ] || errs="$errs\ncommands/$b: no description in frontmatter"
done
[ "$na" -gt 0 ] || errs="$errs\nno agents found"
[ "$nc" -gt 0 ] || errs="$errs\nno commands found"
[ -z "$errs" ] && ok "agents ($na) + commands ($nc) loadable (frontmatter block parsed, not grepped)" || bad "agents + commands loadable" "$(printf '%b' "$errs")"

# --- 11. hook wiring is complete in all three lanes --------------------------------------------
# There are three wiring surfaces, and this check used to read two of them while its own label
# claimed otherwise: claude/hooks/hooks.json was never opened at all, so the plugin lane could
# lose a hook without anything noticing.
#
# Each lane is asserted against its own contract, not a single blanket list, because the lanes
# genuinely differ — see the plugin-lane note below.
if command -v jq >/dev/null; then
  errs=""

  # Lane 1 — project/overlay. claude/settings.json carries the full five.
  for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop PostToolUseFailure; do
    jq -e --arg e "$ev" '.hooks[$e]' claude/settings.json >/dev/null 2>&1 \
      || errs="$errs\n$ev: missing from claude/settings.json"
  done

  # Lane 2 — user scope. install.sh rebuilds the hooks with absolute paths, so the assertion
  # has to read that jq program rather than the file at large. `grep -q "$ev" install.sh`
  # proved nothing: every event name also appears in this file's prose, and "PostToolUse"
  # matches the "PostToolUseFailure" line, so either key could be deleted and the check would
  # still pass off the other. Anchoring on the object key is what makes it bite.
  prog=$(sed -n "/^  jq -s --arg h /,/^  ' \"\$US\"/p" install.sh)
  if [ -z "$prog" ]; then
    errs="$errs\ncould not extract the hook rebuild program from install.sh"
  else
    for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop PostToolUseFailure; do
      printf '%s' "$prog" | grep -qE "^ *$ev: *\[" || errs="$errs\n$ev: missing from install.sh hook rebuild"
    done
    # The user lane wires the same five events as the project lane and nothing more. It used to
    # wire seven, because SessionEnd and PermissionRequest existed only to reach a third-party
    # notifier (Superset) that this setup no longer uses. Installing vstack should not staple a
    # foreign tool's script to five hook events on a stranger's machine, so the notifier is gone
    # and this asserts it stays gone rather than trusting the next reader to notice.
    for dead in SessionEnd PermissionRequest; do
      printf '%s' "$prog" | grep -qE "^ *$dead: *\[" \
        && errs="$errs\n$dead: back in the install.sh hook rebuild — it exists only to serve a notifier this setup dropped"
    done
    # Test for the wiring, not for the word. The first version of this grepped install.sh for
    # "superset" and then failed on the jq filter whose whole job is to strip legacy notifier
    # entries out of a user's existing settings — the guard fired on the code that removes the
    # thing it was guarding against. What must not come back is a notifier command being
    # constructed and attached to hook events.
    grep -qE '^[[:space:]]*NOTIFY=|command:\$n\b' install.sh \
      && errs="$errs\ninstall.sh wires a notifier command into the hook rebuild again"
  fi

  # Lane 3 — plugin marketplace. Deliberately narrow, and asserted as an exact set rather than
  # a minimum. The manifest promises routing plus the verify gate and nothing more, because
  # inject-session-context.sh drops the token/delegation/autonomy policy under
  # VSTACK_PROFILE=skills: those rules are one person's operating preference and have no
  # business riding along with a skill pack a stranger installed. Asserting the exact set means
  # widening this lane has to be a deliberate edit here, not a quiet drift.
  # tr -d '\r' because the native Windows jq writes CRLF, which survived tr '\n' ' ' and made
  # the key list compare as "SessionStart\r Stop\r" against "SessionStart Stop".
  got=$(jq -r '.hooks | keys_unsorted[]' claude/hooks/hooks.json 2>/dev/null | tr -d '\r' | sort | tr '\n' ' ' | sed 's/ *$//')
  [ "$got" = "SessionStart Stop" ] \
    || errs="$errs\nplugin lane wires [$got], expected exactly [SessionStart Stop]"

  # Every script named by any lane exists. The old character class [a-z-]* silently exempted
  # any hook filename containing a digit or a capital, and an empty extraction made the whole
  # loop a no-op, so the count is asserted too. Extract from hooks.json (plugin lane) and
  # install.sh (user lane rebuild), but NOT settings.json (dev-only config). This ensures
  # a hook cannot pass validation if it is wired only in the developer's config rather than
  # in what actually ships to users.
  prog=$(sed -n "/^  jq -s --arg h /,/^  ' \"\$US\"/p" install.sh)
  refs_plugin=$(jq -r '.hooks[][]?.hooks[]?.command' claude/hooks/hooks.json 2>/dev/null \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh|[a-z0-9._-]+\.sh' | sed 's|^|hooks/|;s|hooks/hooks/|hooks/|' | sort -u)
  refs_user=$(printf '%s' "$prog" | grep -oE 'command:\(\$h\+[^)]*' | grep -oE '[a-z0-9._-]+\.sh' 2>/dev/null \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh|[a-z0-9._-]+\.sh' | sed 's|^|hooks/|;s|hooks/hooks/|hooks/|' | sort -u)
  refs=$(printf '%s\n%s\n' "$refs_plugin" "$refs_user" | grep -v '^$' | sort -u)
  nref=$(printf '%s\n' "$refs" | grep -c . )
  # Both directions, against the tree rather than a number. This was `[ "$nref" -ge 4 ]` while
  # the real count was 6, so two hooks could fall out of the wiring and the floor would still
  # clear. Rewiring one event's command to a script another event already names keeps every
  # event key present, every referenced file on disk, and drops nref from 6 to 5 -- the check
  # printed ok with format.sh wired to nothing at all. A literal floor cannot notice a tree
  # that grew past it; the set comparison below has nothing to go stale.
  for h in $refs; do
    [ -f "claude/$h" ] || errs="$errs\n$h: referenced in hook wiring but not in claude/hooks/"
  done
  # Coverage is asserted PER LANE, not on the union of both. This used to flatten refs_plugin and
  # refs_user into one `refs` set and ask "is this hook in refs anywhere" -- a hook wired only in
  # the plugin lane (claude/hooks/hooks.json) satisfied that, and skill-mandate.sh sat exactly
  # there for two release cycles: shipped, wired into hooks.json, never wired into install.sh's
  # hook rebuild, entirely inert for `./install.sh`, which is what every non-plugin user runs.
  # "wired in some lane" and "wired in the lane this user actually used" are different claims,
  # and the union check could not tell them apart. This asserts the second one directly: every
  # shipped hook must be in refs_user specifically, because that is the set install.sh produces.
  #
  # A hook that legitimately ships to only the plugin lane (never install.sh) is not a bug, but
  # it must say so here, by name, with a reason -- silence is exactly the loophole this replaces.
  # Empty today: every shipped hook belongs in the user lane, because installing vstack for real
  # use is what install.sh does.
  #   format: one "basename.sh:one-line reason why it is plugin-only" per line
  USER_LANE_EXEMPT=''
  refs_user_flat=" $(printf '%s' "$refs_user" | tr '\n' ' ') "
  for f in claude/hooks/*.sh; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    exempt=$(printf '%s\n' "$USER_LANE_EXEMPT" | grep "^$b:")
    if [ -n "$exempt" ]; then
      continue
    fi
    case "$refs_user_flat" in
      *" hooks/$b "*) ;;
      *) errs="$errs\n$b: shipped in claude/hooks/ but not wired in the USER lane (install.sh's hook rebuild) -- \`./install.sh\` ships it inert. Wire it into install.sh, or add it to USER_LANE_EXEMPT in this check with a reason." ;;
    esac
  done
  ndisk=0
  for f in claude/hooks/*.sh; do [ -e "$f" ] && ndisk=$((ndisk + 1)); done
  [ "$ndisk" -gt 0 ] || errs="$errs\nclaude/hooks/ has no scripts in it, so this compared nothing"

  [ -z "$errs" ] && ok "hook wiring (3 lanes, $nref wired, $ndisk shipped)" || bad "hook wiring" "$(printf '%b' "$errs")"
else
  skip "hook wiring" "jq not installed"
fi

# --- 12. documented counts match the tree ------------------------------------------------------
# Derive every count from the tree, then read the docs back and fail on any claim that
# disagrees.
#
# The old form asserted only that the *right* number appeared somewhere in README and the
# marketplace manifest, and only for skills and agents. That is a one-directional test: it
# cannot see a wrong number sitting next to a right one. "15 commands" therefore shipped green
# for as long as "25 skills" was also true, which is what happened when the orchestrate command
# was deleted. Reading the claims out and comparing each one is what closes that.
#
# Two forms are scanned, because README states its counts both ways: "14 commands" in prose and
# "| Commands | 14 |" in the component table, where the number follows the noun. The text is
# whitespace-normalised first — the headline wraps mid-count ("15\ncommands"), so no
# line-oriented grep could ever have seen it.
nsk=$(find claude/skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
nag=$(ls claude/agents/*.md   2>/dev/null | wc -l | tr -d ' ')
ncm=$(ls claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
nhk=$(ls claude/hooks/*.sh    2>/dev/null | wc -l | tr -d ' ')
nwr=$(ls bin/*                2>/dev/null | wc -l | tr -d ' ')
ncs=$(grep -cE '^run_(negative_)?case ' tests/auto-trigger.sh 2>/dev/null || echo 0)
nmc=0
command -v jq >/dev/null && nmc=$(jq 'keys|length' mcp/servers.json 2>/dev/null || echo 0)

# README teaches "every one of the N checks in the gate has a mutation that proves it" -- a claim
# about this file, which is exactly the kind that goes stale the moment a check is added. It sat
# at 25 against a gate of 26 and nothing could see it, because the noun was not in the map.
nck=$TOTAL

# Same shape, one noun later. The CHANGELOG said "29 shell scripts" against a tree of 27 .sh
# files and 31 shebang scripts, and nothing could see it because "shell script" was not in the
# map. Derived the same way check 29 selects, so the two can never disagree.
nsh=$(sh_files | grep -c .)

# Third of the same shape. README.md and tests/README.md both quoted the falsifiability suite's
# row count in prose to justify a runtime figure, and both sat at 94 against a live 100 for four
# releases, because "rows" was not in the map. It cannot go in as the bare noun: "25 rows",
# "5000 rows" and "19 rows" are all live, correct claims about other things. So the noun is the
# full phrase, and the two prose sites say "falsifiability rows" rather than "rows".
nfr=$(sed -n 's/^CHECKS="\(.*\)"/\1/p' tests/gate-falsifiability.sh | tr ' ' '\n' | grep -c '[0-9]')

# Lane-aware resolution for README's two "## What lands where" tables. Check 12 used to resolve
# one number per noun for the whole repository, but README states its counts once per install
# lane, and the two lanes ship different things: the plugin lane wires two routing hooks and
# ships no CLI wrappers or MCP servers at all. A repo-wide number satisfied both tables by
# coincidence for skills/agents/commands (the plugin lane's rows happen to equal the full lane's)
# and missed the rows that actually differ, because a cell reading "2 (routing only)" never
# matched the table regex below. That hole is where this repository's worst live contradiction
# sat: the plugin lane wired the Stop gate while README, bin/doctor and this check all agreed the
# lane shipped no hooks, because none of them read profiles.plugin.ships.
#
# The rule: a family absent from profiles.<lane>.ships must show 0. A family present shows the
# lane's own wired count where the manifest states one (hooks -- the plugin lane wires two of the
# eight hook scripts the repo ships via hook_scripts_wired, and both numbers are derived from the
# tree so they can never disagree with each other), and components.<family>.count otherwise.
lane_family_for(){ # README table noun -> inventory.json component family, or empty if uncovered
  case "$1" in
    skill|skills)                                          printf '%s' skills ;;
    subagent|subagents|sub-agent|sub-agents|agent|agents)  printf '%s' agents ;;
    command|commands)                                      printf '%s' commands ;;
    hook|hooks)                                            printf '%s' hooks ;;
    "cli wrapper"|"cli wrappers")                          printf '%s' wrappers ;;
    "mcp server"|"mcp servers")                            printf '%s' mcp_servers ;;
  esac
}

lane_want(){ # lane noun -> expected count for that lane's row, or empty if the noun has no family
  _ln_lane=$1 _ln_noun=$2
  _ln_fam=$(lane_family_for "$_ln_noun")
  [ -n "$_ln_fam" ] || { printf ''; return; }
  command -v jq >/dev/null || { printf ''; return; }
  _ln_present=$(jq -r --arg lane "$_ln_lane" --arg fam "$_ln_fam" \
    '(.profiles[$lane].ships // []) | index($fam) != null' claude/inventory.json 2>/dev/null)
  if [ "$_ln_present" != "true" ]; then printf '%s' 0; return; fi
  if [ "$_ln_fam" = hooks ]; then
    _ln_wired=$(jq -r --arg lane "$_ln_lane" \
      '(.profiles[$lane].hook_scripts_wired // empty) | length' claude/inventory.json 2>/dev/null)
    if [ -n "$_ln_wired" ] && [ "$_ln_wired" != null ]; then printf '%s' "$_ln_wired"; return; fi
  fi
  case "$_ln_fam" in
    skills)      printf '%s' "$nsk" ;;
    agents)      printf '%s' "$nag" ;;
    commands)    printf '%s' "$ncm" ;;
    hooks)       printf '%s' "$nhk" ;;
    wrappers)    printf '%s' "$nwr" ;;
    mcp_servers) printf '%s' "$nmc" ;;
  esac
}

want_for(){ # noun (lowercased, plural or singular), optional lane ("full"/"plugin"/"overlay")
            # -> expected count, or empty if not covered. With a lane given, resolves against
            # profiles.<lane>.ships in claude/inventory.json instead of the repo-wide totals below.
  if [ -n "${2:-}" ]; then
    lane_want "$2" "$1"
    return
  fi
  case "$1" in
    skill|skills)                                   printf '%s' "$nsk" ;;
    check|checks)                                   printf '%s' "$nck" ;;
    agent|agents|subagent|subagents|sub-agent|sub-agents) printf '%s' "$nag" ;;
    command|commands)                               printf '%s' "$ncm" ;;
    hook|hooks)                                     printf '%s' "$nhk" ;;
    "cli wrapper"|"cli wrappers")                   printf '%s' "$nwr" ;;
    case|cases)                                     printf '%s' "$ncs" ;;
    "mcp server"|"mcp servers")                     printf '%s' "$nmc" ;;
    "shell script"|"shell scripts")                 printf '%s' "$nsh" ;;
    "falsifiability row"|"falsifiability rows")     printf '%s' "$nfr" ;;
  esac
}

# Claims that are deliberately not repo-wide totals: one provenance subset and two historical
# measurements. Each is exempted by its own phrase rather than by line number, so editing the
# sentence away takes the exemption with it instead of leaving a dangling rule behind.
exempt_phrases(){
  case "$1" in
    README.md)               printf '%s\n' '18 skills are ported' ;;
    docs/how-skills-fire.md) printf '%s\n' 'installed 18 skills correctly' '44 skills' \
                                           '9 of 9 cases fire the expected skill' ;;
  esac
}

# Every noun this check can resolve, spelled once. The extraction regex is built from this
# list, so a noun can no longer be resolvable-but-never-extracted -- which is how "29 shell
# scripts" sat in the CHANGELOG unchallenged. want_for had no case for it, and even after one
# was added the claim stayed invisible, because the extractor carried its own separate
# alternation and nothing compared the two.
NOUNS='skills?|checks?|agents?|subagents?|sub-agents?|commands?|hooks?|CLI wrappers?|cases?|MCP servers?|shell scripts?|falsifiability rows?'

errs=""

# Positive control. Every alternative the extractor looks for must resolve to a number, or the
# check pulls claims out of the docs and then drops them on the floor without saying so.
while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  [ -n "$(want_for "$(printf '%s' "$_n" | tr '[:upper:]' '[:lower:]')")" ] \
    || errs="$errs\ninternal: the extractor looks for '$_n' but want_for cannot resolve it"
done <<EOF
$(printf '%s' "$NOUNS" | tr '|' '\n' | sed 's/?$//')
EOF

# Derived, not listed. This was a hand-maintained list of eight and it had grown by hand every
# time somebody noticed a miss -- tests/README.md and docs/how-skills-fire.md were both late
# additions, and tests/evals/RESULTS.md was the next one waiting to be noticed. That is exactly
# the shape check 29 removed one check over: a list you have to remember to update is a list
# that goes stale silently, and the remembering is the part that fails.
#
# Every tracked markdown and manifest is scanned except two trees, and the rule is one rule:
# a document whose numbers are evidence about something other than this tree's shape today.
# docs/provenance/** is dated internal handoffs -- they record what was true on the day, and
# rewriting them to satisfy today's tree would be falsifying history. docs/research/** is
# published evidence about other systems; its "15 agents" and "196 checks" are somebody else's
# benchmark, and holding them to this repository's counts is a category error, not a finding.
#
# This is still an exclusion somebody has to maintain, and worth being honest about: a document
# dropped into either tree is unscanned by design. It is two directories with a stated rule
# rather than eight filenames with none, which is the improvement -- not a claim that the
# problem is gone.
doc_set=$(git ls-files '*.md' '*.json' 2>/dev/null | grep -vE '^docs/(provenance|research)/')
ndocs=$(printf '%s' "$doc_set" | grep -c .)
# A derived set can silently shrink to nothing, which would make this check pass by scanning no
# documents at all -- the precise failure it exists to catch, turned on itself. So the set is
# asserted before it is used.
if [ "$ndocs" -lt 8 ] \
|| ! grep -qx 'README.md' <<<"$doc_set" \
|| ! grep -qx 'CHANGELOG.md' <<<"$doc_set"; then
  errs="$errs\ninternal: the derived document set is $ndocs file(s) and does not contain both README.md and CHANGELOG.md, so this scanned nothing worth scanning"
fi
for f in $doc_set; do
  [ -f "$f" ] || continue
  if [ "$f" = CHANGELOG.md ]; then
    # Only the entries that describe what ships today: Unreleased, plus the section for the
    # version the manifests declare. Older entries record what was true at that release and
    # rewriting them to satisfy today's tree would be falsifying history. Taking simply "the top
    # section" is not enough -- an Unreleased heading sits above the release, and slicing there
    # stopped one section short of the claim that had gone stale.
    _cv=$(jq -r '.version' claude/.claude-plugin/plugin.json 2>/dev/null)
    norm=$(awk -v v="$_cv" '/^## /{ sec = ($2 == "Unreleased" || index($2, v) == 1) } sec' "$f" \
             | tr '\n' ' ' | tr -s '[:space:]' ' ')
  else
    norm=$(tr '\n' ' ' < "$f" | tr -s '[:space:]' ' ')
  fi
  while IFS= read -r ph; do
    [ -n "$ph" ] && norm=${norm//"$ph"/}
  done <<EOF
$(exempt_phrases "$f")
EOF

  # prose form: "14 commands"
  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    num=${claim%% *}
    noun=$(printf '%s' "${claim#* }" | tr '[:upper:]' '[:lower:]')
    want=$(want_for "$noun")
    [ -n "$want" ] && [ "$num" != "$want" ] \
      && errs="$errs\n$f: claims '$claim', tree has $want"
  done <<EOF
$(printf '%s' "$norm" | grep -oE "(^|[^\$[:alnum:]])[0-9]+ ($NOUNS)" | sed -E 's/^[^0-9]*//' | sort -u)
EOF

  # table form: "| Commands | 14 |". The trailing "( *\([^|]*\))?" lets a cell read
  # "2 (routing only)" or "0 (not this lane)" match at all -- without it the number was still
  # there but the whole row fell out of the extraction silently, which is how the plugin lane's
  # Hooks/CLI-wrappers/MCP-servers rows escaped every check for this repository's life.
  if [ "$f" = README.md ]; then
    # README states its component table once per install lane (see "## What lands where"), and
    # the two lanes ship different things. Scanning the whole file as one blob is lane-blind by
    # construction, so split on the two lane headings already in the prose (they are the anchor
    # the "Confirm it worked" paragraph above this check already points a reader at) and resolve
    # each half's rows against that lane's own profile in claude/inventory.json.
    full_seg=$(printf '%s' "$norm" | sed -E 's/^.*\*\*Full install\*\*//; s/\*\*Plugin-marketplace install\*\*.*$//')
    plugin_seg=$(printf '%s' "$norm" | sed -E 's/^.*\*\*Plugin-marketplace install\*\*//; s/## Day to day.*$//')
    for _lane_seg in "full:$full_seg" "plugin:$plugin_seg"; do
      _lane=${_lane_seg%%:*}
      _seg=${_lane_seg#*:}
      while IFS= read -r row; do
        [ -n "$row" ] || continue
        noun=$(printf '%s' "$row" | sed -E 's/^\| *//; s/ *\|.*//' | tr '[:upper:]' '[:lower:]')
        num=$(printf '%s' "$row" | sed -E 's/.*\| *([0-9]+).*/\1/')
        want=$(want_for "$noun" "$_lane")
        [ -n "$want" ] && [ "$num" != "$want" ] \
          && errs="$errs\n$f: $_lane lane table row '$noun' says $num, that lane ships $want"
      done <<EOF2
$(printf '%s' "$_seg" | grep -oE '\| *[A-Za-z][A-Za-z ]*\| *[0-9]+( *\([^|]*\))? *\|' | sort -u)
EOF2
    done
  else
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      noun=$(printf '%s' "$row" | sed -E 's/^\| *//; s/ *\|.*//' | tr '[:upper:]' '[:lower:]')
      num=$(printf '%s' "$row" | sed -E 's/.*\| *([0-9]+).*/\1/')
      want=$(want_for "$noun")
      [ -n "$want" ] && [ "$num" != "$want" ] \
        && errs="$errs\n$f: table row '$noun' says $num, tree has $want"
    done <<EOF
$(printf '%s' "$norm" | grep -oE '\| *[A-Za-z][A-Za-z ]*\| *[0-9]+( *\([^|]*\))? *\|' | sort -u)
EOF
  fi
done

# Config values quoted in prose drift exactly the way counts do. how-skills-fire.md teaches the
# listing budget fraction as a number, and it sat two revisions behind the settings file.
if command -v jq >/dev/null && [ -f docs/how-skills-fire.md ]; then
  bf=$(jq -r '.skillListingBudgetFraction // empty' claude/settings.json 2>/dev/null)
  [ -n "$bf" ] && ! grep -qF "\`$bf\`" docs/how-skills-fire.md \
    && errs="$errs\ndocs/how-skills-fire.md: does not state the live skillListingBudgetFraction ($bf)"
fi

[ -z "$errs" ] \
  && ok "doc counts match tree ($nsk skills, $nag agents, $ncm commands, $nhk hooks, $nck checks, $ncs test cases)" \
  || bad "doc counts match tree" "$(printf '%b' "$errs")"

# --- 13. every file that declares the version agrees ------------------------------------------
# marketplace.json and plugin.json each carry their own version string and nothing had ever
# compared them. A release that bumps one and forgets the other publishes a marketplace entry
# pointing at a differently-numbered plugin.
#
# claude/inventory.json carries a THIRD copy, `product.version`, and names the other two in its
# own `product.version_source` array -- an explicit written claim that its number is derived
# from theirs. Nothing enforced that claim, so it drifted: measured 2026-08-28, the manifests
# were at 1.48.0 and inventory said 1.46.0, wrong across two shipped releases. inventory.json is
# payload, so that number is what a stranger reads to find out what they installed, and the
# check that validates the rest of the file walked past it. A field that documents where its
# truth comes from and is never compared against that source is the same defect as a check that
# names what it measures and does not measure it.
#
# So the census is derived from version_source rather than listed here. Add a fourth manifest to
# that array and it is compared from that moment, without anyone remembering to widen this.
if command -v jq >/dev/null; then
  c13_inv=claude/inventory.json
  c13_srcs=$(jq -r '.product.version_source[]?' "$c13_inv" 2>/dev/null)
  c13_n=0; c13_ref=""; c13_reff=""; c13_dis=""
  for c13_f in $c13_srcs; do
    if [ ! -f "$c13_f" ]; then
      c13_dis="$c13_dis\n  $c13_f is named in version_source but is not in the tree"
      continue
    fi
    # .version for a plugin manifest, .plugins[0].version for the marketplace entry. Trying both
    # keeps this generic over what a source file happens to look like.
    c13_v=$(jq -r '(.version // .plugins[0].version) // "missing"' "$c13_f" 2>/dev/null)
    c13_n=$((c13_n + 1))
    if [ -z "$c13_reff" ]; then c13_ref="$c13_v"; c13_reff="$c13_f"
    elif [ "$c13_v" != "$c13_ref" ]; then
      c13_dis="$c13_dis\n  $c13_f says $c13_v, $c13_reff says $c13_ref"
    fi
  done
  # The file's own claim about itself, checked against the sources it nominated.
  c13_own=$(jq -r '.product.version // "missing"' "$c13_inv" 2>/dev/null)
  if [ -n "$c13_reff" ] && [ "$c13_own" != "$c13_ref" ]; then
    c13_dis="$c13_dis\n  $c13_inv says $c13_own, but names $c13_reff as its version_source, which says $c13_ref"
  fi
  if [ "$c13_n" -eq 0 ]; then
    bad "plugin manifest versions" "$c13_inv declares no readable product.version_source, so there was no set of files to compare and this check measured nothing"
  elif [ -n "$c13_dis" ]; then
    bad "plugin manifest versions" "$(printf 'the version is declared in more than one place and they disagree:%b' "$c13_dis")"
  else
    ok "every file that declares the version agrees (v$c13_ref, $c13_n source(s) plus inventory's own claim)"
  fi
else
  skip "plugin manifest versions" "jq not installed"
fi

# --- 14. the Stop-hook gate actually blocks ----------------------------------------------------
# The gate is the mechanism every other check depends on: none of them matter if a failing
# verify.sh does not stop the agent. It hardcoded /usr/bin/jq, so on a host without that exact
# path the block decision was never emitted and the gate enforced nothing while looking
# installed. Drive it end to end against a seeded failing verify.sh, in both jq conditions.
if command -v jq >/dev/null && command -v git >/dev/null; then
  # pwd -P: the gate resolves its project dir physically (`vstack trust` records it that way),
  # and $TMPDIR is a symlink on macOS, so a logical fixture path armed a record the gate could
  # not find and this check reported the gate as not blocking.
  gd=$(cd "$(mktemp -d)" && pwd -P)
  # TMPDIR is redirected into the scratch dir because the gate keeps a per-session block
  # counter there and latches open at three. With a shared TMPDIR and a fixed session id this
  # check would pass twice and then fail forever on the same tree.
  mkdir -p "$gd/repo/.claude" "$gd/home/.config/agents" "$gd/bin" "$gd/tmp"
  printf '#!/usr/bin/env bash\necho "seeded failure"\nexit 1\n' > "$gd/repo/.claude/verify.sh"
  chmod +x "$gd/repo/.claude/verify.sh"
  gv="$gd/repo/.claude/verify.sh"
  if command -v shasum >/dev/null 2>&1; then gh=$(shasum -a 256 "$gv" | cut -d' ' -f1)
  else gh=$(sha256sum "$gv" | cut -d' ' -f1); fi
  printf '%s  %s\n' "$gh" "$gv" > "$gd/home/.config/agents/verify-trust"

  errs=""
  o=$(printf '{"session_id":"vs-gate"}' \
      | env HOME="$gd/home" TMPDIR="$gd/tmp" CLAUDE_PROJECT_DIR="$gd/repo" bash claude/hooks/verify-gate.sh 2>/dev/null)
  printf '%s' "$o" | jq -e '.decision=="block"' >/dev/null 2>&1 \
    || errs="$errs\nwith jq: a failing verify.sh did not produce decision:block"

  # Same run with no jq reachable: rewrite the absolute path and hand it a PATH holding only
  # the tools the hook itself needs.
  sed 's#/usr/bin/jq#/nonexistent/jq#' claude/hooks/verify-gate.sh > "$gd/nojq.sh"
  for t in bash sh cat cut grep sed awk tr shasum sha256sum rm mkdir env dirname basename; do
    p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$gd/bin/$t"
  done
  # The stripped PATH is built out of symlinks, and MSYS/Git Bash does not reliably make them
  # — without Developer Mode they silently become copies or fail outright. A sandbox that
  # cannot run bash at all makes this assertion fail for a reason that has nothing to do with
  # the hook, which is how Windows first reported a broken gate that was not broken.
  #
  # So probe the sandbox before trusting what it says. If it cannot execute, the sub-assertion
  # names itself unmeasurable instead of reporting a defect it did not observe.
  if [ "$(env PATH="$gd/bin" bash -c 'echo alive' 2>/dev/null)" != alive ]; then
    nojq_note=" (no-jq path unmeasurable here: a stripped PATH of symlinks does not execute on this platform)"
  else
    nojq_note=""
    o=$(printf '{"session_id":"vs-gate-nojq"}' \
        | env PATH="$gd/bin" HOME="$gd/home" TMPDIR="$gd/tmp" CLAUDE_PROJECT_DIR="$gd/repo" bash "$gd/nojq.sh" 2>/dev/null)
    printf '%s' "$o" | jq -e '.decision=="block"' >/dev/null 2>&1 \
      || errs="$errs\nwithout jq: a failing verify.sh did not produce a parseable decision:block"
  fi

  # A script verify.sh executes, changed after it was trusted, must stop the gate. Trust used
  # to cover the entry point alone, so a byte-identical verify.sh sailed through while the
  # install.sh it runs had been swapped underneath.
  printf '#!/usr/bin/env bash\necho original\n' > "$gd/repo/install.sh"
  if command -v shasum >/dev/null 2>&1; then ih=$(shasum -a 256 "$gd/repo/install.sh" | cut -d' ' -f1)
  else ih=$(sha256sum "$gd/repo/install.sh" | cut -d' ' -f1); fi
  printf '%s  %s\n' "$ih" "$gd/repo/install.sh" >> "$gd/home/.config/agents/verify-trust"
  printf '#!/usr/bin/env bash\necho swapped\n' > "$gd/repo/install.sh"
  o=$(printf '{"session_id":"vs-trust"}' \
      | env HOME="$gd/home" TMPDIR="$gd/tmp" CLAUDE_PROJECT_DIR="$gd/repo" bash claude/hooks/verify-gate.sh 2>/dev/null)
  printf '%s' "$o" | grep -q 'changed since it was trusted' \
    || errs="$errs\na trusted script changed underneath and the gate ran anyway"

  rm -rf "$gd"

  # And no hook may reach for jq by absolute path again. /usr/bin/jq is fine as a preference
  # inside the resolver, but calling it directly is what made these hooks inert off macOS —
  # the gate stopped blocking and the session hook stopped injecting the routing block at all.
  hp=$(grep -n '/usr/bin/jq' claude/hooks/*.sh 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' | grep -vF '[ -x /usr/bin/jq ]')
  [ -n "$hp" ] && errs="$errs\nhooks calling jq by absolute path instead of resolving it:\n$hp"

  [ -z "$errs" ] && ok "stop-hook gate blocks (jq present and absent)${nojq_note:-}" \
    || bad "stop-hook gate blocks" "$(printf '%b' "$errs")"
else
  skip "stop-hook gate blocks" "jq or git not installed"
fi

# --- 14b. the gate refuses to measure a tree the harness is mutating --------------------------
#
# tests/gate-falsifiability.sh breaks one payload file at a time on purpose. A gate run inside
# that window returns a real FAIL naming a defect nobody introduced, and it reads exactly like a
# finding -- three sessions sharing this checkout chased three of them before the lock existed.
#
# All three paths are asserted because each one fails silently in its own way. No refusal is the
# original bug. Refusing on a stale lock wedges the gate for everyone after a killed run, and this
# suite does get killed. Refusing to the harness itself deadlocks it against its own lock.
g_errs=""
if command -v git >/dev/null 2>&1; then
  # --git-common-dir: same reasoning as the two anchors above -- this probe's whole point is to
  # write to the exact path the harness and the refusal check above use as the lock, and that has
  # to be the shared, not per-worktree, path.
  _gd=$(git rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$_gd" ] && [ -w "$_gd" ]; then
    _lkf="$_gd/vstack-falsifiability-probe.lock"
    _saved=""
    [ -f "$_gd/vstack-falsifiability.lock" ] && _saved=$(cat "$_gd/vstack-falsifiability.lock")
    # env -u, not a bare ${2:+...}. The harness exports VSTACK_FALSIFY=1 for every gate run it
    # makes, so the nested call inherited it and the "live lock" path silently became a third
    # copy of the harness-bypass path -- green when run by hand, red the moment the harness ran
    # it, which is how the suite found this. A check that reads its answer off the ambient
    # environment is not testing the thing it names.
    _probe(){ # lockpid, falsify(1 or empty) -> "rc:firstline"
      printf '%s\n' "$1" > "$_gd/vstack-falsifiability.lock"
      if [ -n "$2" ]; then
        _o=$(env VSTACK_FALSIFY=1 VSTACK_GUARD_PROBE=1 bash "$SELF" 2>&1); _r=$?
      else
        _o=$(env -u VSTACK_FALSIFY VSTACK_GUARD_PROBE=1 bash "$SELF" 2>&1); _r=$?
      fi
      rm -f "$_gd/vstack-falsifiability.lock"
      # rc, first line and LAST line, in one string: _probe runs in a command substitution, so
      # anything it assigns to a variable dies with the subshell. Learned the hard way, one
      # `unbound variable` ago.
      printf '%s:%s~~%s' "$_r" "$(printf '%s' "$_o" | head -1)" "$(printf '%s' "$_o" | tail -1)"
    }
    _live=$(_probe "$$" "")
    case "$_live" in
      2:REFUSED*) ;;
      *) g_errs="$g_errs\n  a live lock did not stop the gate: got [$_live], want rc 2 and REFUSED" ;;
    esac
    # The refusal's LAST line, not just its first. A reader who tails the output has to meet a
    # verdict there or the absence of one reads as success.
    case "$_live" in
      *'~~NOT RUN'*) ;;
      *) g_errs="$g_errs\n  a refusal does not end with a NOT RUN terminator: got [${_live#*~~}]. Output with no verdict on its last line reads as green to anyone who tails it" ;;
    esac
    # 999999 is chosen to be dead, and asserted dead rather than assumed -- a pid that happens to
    # exist would turn this direction into a silent duplicate of the one above.
    if kill -0 999999 2>/dev/null; then
      g_errs="$g_errs\n  pid 999999 is alive on this machine, so the stale-lock case proves nothing"
    else
      _stale=$(_probe 999999 "")
      case "$_stale" in
        0:GUARD_PASSED*) ;;
        *) g_errs="$g_errs\n  a stale lock wedged the gate: got [$_stale], want rc 0 and GUARD_PASSED" ;;
      esac
    fi
    _self=$(_probe "$$" 1)
    case "$_self" in
      0:GUARD_PASSED*) ;;
      *) g_errs="$g_errs\n  the harness was locked out by its own lock: got [$_self], want rc 0" ;;
    esac
    rm -f "$_lkf"
    [ -n "$_saved" ] && printf '%s\n' "$_saved" > "$_gd/vstack-falsifiability.lock"
    [ -z "$g_errs" ] \
      && ok "the gate refuses a tree under mutation (3 paths: live, stale, harness)" \
      || bad "the gate refuses a tree under mutation" "$(printf '%b' "$g_errs")"
  else
    bad "the gate refuses a tree under mutation" "no writable git dir, so the lock path could not be exercised"
  fi
else
  skip "the gate refuses a tree under mutation" "git not installed"
fi

# --- 15. skillOverrides only names skills it can actually control ------------------------------
# Claude Code resolves a skill's listing mode before consulting skillOverrides when the skill
# comes from a plugin, so a plugin-namespaced key is silently inert. This file used to carry 38
# of them, in two spellings, for the same 19 skills — none had any effect, and their
# descriptions sat in the listing anyway. Dead config that looks like a working control is worse
# than no config, because it stops anyone looking for the real cause.
if command -v jq >/dev/null; then
  errs=""
  bk=$(jq -r '.skillOverrides // {} | keys[] | select(test("[:@]"))' claude/settings.json 2>/dev/null)
  [ -n "$bk" ] && errs="$errs\nplugin-namespaced keys cannot take effect (see docs/how-skills-fire.md):\n$(printf '%s' "$bk" | sed 's/^/  /')"
  bv=$(jq -r '.skillOverrides // {} | to_entries[]
              | select(.value != "off" and .value != "name-only" and .value != "on")
              | "  \(.key) = \(.value)"' claude/settings.json 2>/dev/null)
  [ -n "$bv" ] && errs="$errs\nunknown override mode:\n$bv"
  no_=$(jq '.skillOverrides // {} | length' claude/settings.json 2>/dev/null)
  [ -z "$errs" ] && ok "skillOverrides ($no_ entries, all effective)" \
    || bad "skillOverrides" "$(printf '%b' "$errs")"
else
  skip "skillOverrides" "jq not installed"
fi

# --- 16. every check can be shown to fail ------------------------------------------------------
# The accounting line above proves a check reported something. It cannot prove the check would
# ever report a failure. tests/gate-falsifiability.sh breaks what each check watches and
# requires the gate to go red naming it; this asserts that every declared check has a row there,
# so adding a check without proving it bites is itself a failure.
if [ -f tests/gate-falsifiability.sh ]; then
  errs=""
  cov=" $(grep -m1 -oE '^CHECKS="[^"]*"' tests/gate-falsifiability.sh | sed 's/^CHECKS="//; s/"$//') "
  nid=0
  for i in $(grep -oE '^# --- [0-9]+b?\.' "$SELF" | sed 's/^# --- //; s/\.$//'); do
    nid=$((nid+1))
    case "$cov" in
      *" $i "*) ;;
      *) errs="$errs\ncheck $i is not listed in CHECKS= in tests/gate-falsifiability.sh" ;;
    esac
    # Listing is not a row. This asserted membership in the CHECKS string and nothing else, so
    # an id could be added there with no break_it and no label_for and this check stayed green;
    # the omission surfaced only when somebody ran the suite, which is the thing this check
    # exists to make unnecessary. All three arms, or it is not falsifiable.
    grep -qE "^  $i\)" <<<"$(sed -n '/^label_for(){/,/^esac }/p' tests/gate-falsifiability.sh)" \
      || errs="$errs\ncheck $i has no label_for arm, so no row can match its FAIL line"
    # A row falsifies its check by editing a file or by changing the environment the gate runs
    # in -- check 0 is about the toolchain, so its row strips jq from PATH instead of editing
    # anything. Both count; neither existing does not.
    grep -qE "^  $i\)" <<<"$(sed -n '/^break_it(){/,/^esac }/p' tests/gate-falsifiability.sh)" \
      || grep -qE "\[ \"\\\$id\" = $i \]" tests/gate-falsifiability.sh \
      || errs="$errs\ncheck $i has neither a break_it arm nor an environment branch, so nothing ever breaks it"
  done
  [ -z "$errs" ] && ok "falsifiability coverage ($nid checks)" \
    || bad "falsifiability coverage" "$(printf '%b' "$errs")"
else
  bad "falsifiability coverage" "tests/gate-falsifiability.sh is missing"
fi

# --- 17. the overlay ships project settings and nothing personal -------------------------------
# overlay.sh copied claude/settings.json wholesale into other people's repos, theme and
# notification channel and login method included. The target is seeded the way an
# already-overlaid repo looks, so this proves both halves: personal keys are removed, and the
# repo's own settings survive.
if command -v jq >/dev/null && command -v git >/dev/null; then
  ov=$(mktemp -d)
  git -C "$ov" init -q 2>/dev/null
  mkdir -p "$ov/.claude"
  printf '{"theme":"dark","permissions":{"allow":["Bash(ls)"]}}\n' > "$ov/.claude/settings.json"
  errs=""
  if out=$(./overlay.sh "$ov" 2>&1); then
    allow=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' claude/settings.project-keys | tr '\n' ' ')
    leaked=$(jq -r --arg a "$allow" '
      ($a | split(" ") | map(select(length > 0))) as $A
      | (keys - $A - ["permissions","theme"]) | join(" ")' "$ov/.claude/settings.json" 2>/dev/null)
    [ -n "$leaked" ] && errs="$errs\nshipped non-project keys: $leaked"
    # "Ships nothing personal" means nothing personal is WRITTEN. It never meant a key that
    # resembles one of ours should be DELETED from the target, and this check enforced the wrong
    # one of those: demanding theme be absent afterwards is what made overlay.sh strip it, along
    # with enabledPlugins and forceLoginMethod, from any repo that had independently set them.
    # The gate was asserting the data loss as correct. theme and permissions are excluded from
    # the leak set above because the seed writes them -- they are the target's, and the question
    # is what vstack added, not what survived.
    jq -e 'has("theme")' "$ov/.claude/settings.json" >/dev/null 2>&1 \
      || errs="$errs\ndeleted a key the target repo owned (theme)"
    jq -e '.permissions.allow[0] == "Bash(ls)"' "$ov/.claude/settings.json" >/dev/null 2>&1 \
      || errs="$errs\ndropped the target repo's own permissions key"
    jq -e '.model and .hooks and .statusLine' "$ov/.claude/settings.json" >/dev/null 2>&1 \
      || errs="$errs\ndid not ship the project keys it is supposed to"
    [ -x "$ov/.claude/verify.sh" ] \
      || errs="$errs\nwired a verify gate but shipped no .claude/verify.sh"
    grep -qF "$(git rev-parse HEAD)" "$ov/.conductor/settings.toml" 2>/dev/null \
      || errs="$errs\n.conductor/settings.toml does not pin the commit being overlaid"
    # A Conductor workspace is a git worktree, where .git is a file rather than a directory.
    # overlay.sh tested -d and so refused to run in the exact place it is most needed.
    git -C "$ov" commit -q --allow-empty -m seed 2>/dev/null
    wt=$(mktemp -d); rm -rf "$wt"
    if git -C "$ov" worktree add -q "$wt" -b vs-overlay-probe 2>/dev/null; then
      ./overlay.sh "$wt" >/dev/null 2>&1 \
        || errs="$errs\noverlay.sh refuses to run in a git worktree (Conductor workspaces are worktrees)"
      git -C "$ov" worktree remove --force "$wt" 2>/dev/null
    fi
    rm -rf "$wt"
  else
    errs="$errs\noverlay.sh failed:\n$out"
  fi
  rm -rf "$ov"
  [ -z "$errs" ] && ok "overlay ships project keys only" \
    || bad "overlay ships project keys only" "$(printf '%b' "$errs")"
else
  skip "overlay ships project keys only" "jq or git not installed"
fi

# --- 18. the session hook's injected context stays bounded -------------------------------------
# Every byte here is paid on every session, and the per-prompt digest is paid on every turn —
# over a hundred turns it costs more than the session baseline does once. Nothing stopped
# either growing, and prose grows by default. The caps sit about 25 percent above the measured
# sizes: they catch a block that ran away, not a sentence added on purpose.
if command -v jq >/dev/null; then
  errs=""
  probe(){ printf '{"hook_event_name":"%s"}' "$1" | env CONDUCTOR_WORKSPACE_PATH="${3:-}" ${2:+VSTACK_PROFILE=$2} \
           bash claude/hooks/inject-session-context.sh 2>/dev/null | wc -c | tr -d ' '; }
  # Both bounds, and the floor is the one that matters. Every assertion here used to be an upper
  # cap, so a hook emitting ZERO bytes satisfied all three: `ok injected context bounded (digest
  # 0 B, baseline 0 B)` for a session that receives no operating policy at all. The figure
  # comparison below was the only thing standing between that and a green, and it is a
  # consistency test between two things that can both be wrong -- update the README to say
  # ~0.0 KB and the whole check passes with a dead hook. Verified: that exact pair printed ok.
  #
  # Floors are deliberately far below the measured sizes (215 fired digest / 3379 baseline /
  # 2513 skills). They are not a second cap and must not fire when someone trims a sentence;
  # they answer "did the hook say anything at all", which nothing else here asks.
  chk(){ # label value floor cap
    [ "$2" -ge "$3" ] || errs="$errs\n$1: $2 bytes is under the $3 byte floor -- the hook emitted nothing or nearly nothing"
    [ "$2" -le "$4" ] || errs="$errs\n$1: $2 bytes exceeds the $4 byte cap"
  }
  # The digest is CONDITIONAL-ONLY since the TOKENS/DELEGATE/FANOUT lines came out: a prompt
  # that trips neither the grill trigger nor a mandate strike legitimately emits
  # hookSpecificOutput with no additionalContext, ~60 bytes of JSON envelope. Probing that shape
  # against a 128-byte floor would demand bytes the hook is correct not to spend, so the probe
  # arms the FIRED form -- the one a real turn actually pays -- and the cap is applied to it.
  #
  # Both conditions seeded from the hook's own contract, read out of the source rather than
  # guessed: a 400-character prompt clears the 320-char VSTACK_GRILL_CHARS threshold, and one
  # counter file at $TMPDIR/vstack-mandate-<session_id>.unslop is exactly what skill-mandate.sh
  # writes and what the digest's mandate block reads. Throwaway TMPDIR so this neither inherits
  # a real session's grill marker (which would suppress the first-prompt lane) nor leaves one.
  #
  # The byte bounds alone cannot see one line go missing: measured here, both lines together are
  # 215 B, grill alone 149 B and mandate alone 147 B, all three over a 128 B floor. So presence
  # is asserted per line as well. The floor still answers "did the hook say anything at all";
  # the two greps answer "did each conditional line arm when its condition holds", which is the
  # only thing left in the digest and therefore the only thing left to lose.
  _dg_tmp="${TMPDIR:-/tmp}/vstack-digest-verify.$$"
  rm -rf "$_dg_tmp"; mkdir -p "$_dg_tmp"
  printf '1' > "$_dg_tmp/vstack-mandate-c18digest.unslop"
  _dg_prompt=$(awk 'BEGIN{s="";while(length(s)<400)s=s "rebuild the billing pipeline with retries and idempotency ";printf "%s", substr(s,1,400)}')
  [ "${#_dg_prompt}" -ge 320 ] \
    || errs="$errs\nthe digest probe built a ${#_dg_prompt}-character prompt, under the hook's 320-char grill threshold -- it would measure the unfired digest and call it the fired one"
  _dg_json=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"c18digest","prompt":"%s"}' "$_dg_prompt")
  _dg_out=$(printf '%s' "$_dg_json" | TMPDIR="$_dg_tmp" bash claude/hooks/inject-session-context.sh 2>/dev/null)
  rm -rf "$_dg_tmp"
  _digest=$(printf '%s\n' "$_dg_out" | wc -c | tr -d ' ')
  case "$_dg_out" in
    *'GRILL: run the grill-me skill'*) : ;;
    *) errs="$errs\nper-prompt digest: no GRILL line for a 400-character prompt -- the grill branch stopped firing, and the byte bounds cannot see it (mandate alone still clears the floor)" ;;
  esac
  case "$_dg_out" in
    *'MANDATE skill=1/2'*) : ;;
    *) errs="$errs\nper-prompt digest: no MANDATE skill=1/2 line with a seeded .unslop counter -- the mandate branch stopped reading skill-mandate.sh's counter files, and the byte bounds cannot see it" ;;
  esac
  chk "per-prompt digest"      "$_digest"                        128  512

  # The SessionStart baseline is the one probe that reaches the WORKSPACE CONVENTIONS block
  # (claude/hooks/inject-session-context.sh, "Repo root: $root - branch: $branch"). $root is
  # spliced in twice (the "Repo root:" line and the `$root/.context/` scratch-space line) and
  # $branch once, and both are genuinely environment text -- whatever this checkout's absolute
  # path and current branch happen to be, not prose this repo controls. A raw byte cap over that
  # output is a cap over the operator's directory name: a normal working checkout measured 4092 B
  # on a named branch, and the exact same commit measured 4103 B in a git worktree under a longer
  # temp-directory path on a detached HEAD -- 11 bytes of pure path/branch noise against a 4096 B
  # cap that had one byte of headroom. A clone two characters longer, or a longer branch name,
  # turns a clean tree red on every machine but the one it happened to be written on.
  #
  # Fix: normalize before capping. The hook truncates $root to <=160 bytes and $branch to <=80
  # bytes before splicing (`tr -cd ... | head -c 160` / `head -c 80`), so the worst those two
  # variables can ever contribute is fixed and known regardless of where this check runs. Derive
  # THIS checkout's actual root/branch (same commands the hook itself uses), subtract their real
  # contribution out of the raw measurement, and add back the hook's own worst case. What is left
  # is invariant to the operator's directory name and branch name -- it moves only when the
  # STRUCTURAL prose in the block changes, which is the only thing this cap should ever catch.
  # ($base -- "Target branch for every diff..." -- is spliced three times too, but it names the
  # remote's default branch, not this checkout's path or branch, so it does not vary with either
  # and is left out of the normalization on purpose. A fork whose remote default branch has an
  # unusually long name is a real, separate source of noise this does not cover.)
  # Mirrors the hook's own resolution exactly, fallbacks included (inject-session-context.sh
  # around the `symbolic-ref ... origin/HEAD` line): whatever the hook would splice is what has
  # to be subtracted back out, or the correction is for a different string than the one in the
  # output being measured.
  _base_of(){ # dir -> the $base string the hook would splice, post-sanitization
    _bb=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
          | tr -cd 'A-Za-z0-9._/-' | head -c 80)
    if [ -z "$_bb" ]; then
      for _bc in origin/main origin/master; do
        git -C "$1" rev-parse --verify --quiet "$_bc" >/dev/null 2>&1 && { _bb="$_bc"; break; }
      done
    fi
    [ -n "$_bb" ] || _bb="origin/main"
    printf '%s' "$_bb"
  }
  _root_now=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null | tr -cd 'A-Za-z0-9 ._/-' | head -c 160)
  _branch_now=$(git -C "$PWD" branch --show-current 2>/dev/null | tr -cd 'A-Za-z0-9._/-' | head -c 80)
  [ -n "$_branch_now" ] || _branch_now='<detached>'
  _base_now=$(_base_of "$PWD")
  _baseline_raw=$(probe SessionStart '' '')
  # Floor stays on the raw byte count -- "did the hook say anything at all" does not depend on
  # checkout path, and this never fires from trimming a sentence.
  [ "$_baseline_raw" -ge 1024 ] \
    || errs="$errs\nsession baseline: $_baseline_raw bytes is under the 1024 byte floor -- the hook emitted nothing or nearly nothing"
  # Worst-case normalized bytes: this checkout's raw measurement, with its own root/branch
  # contribution removed and the hook's documented worst case (root padded to 160, branch to 80)
  # added back. Identical regardless of where the repo sits on disk or what the branch is called.
  # Two derived numbers, one subtraction. _baseline_inv is the raw count with EVERY
  # environment-dependent splice removed -- $root twice, $branch once, $base three times -- so it
  # is the same integer on every machine and is the only count fit to compare against a published
  # figure. _baseline_worst adds back the hook's documented truncation ceilings (160/80/80) to
  # give the cap something invariant to bound.
  _baseline_inv=$(awk -v raw="$_baseline_raw" -v rl="${#_root_now}" -v bl="${#_branch_now}" \
    -v gl="${#_base_now}" 'BEGIN{print raw - 2*rl - bl - 3*gl}')
  _baseline_worst=$(awk -v inv="$_baseline_inv" 'BEGIN{print inv + 2*160 + 80 + 3*80}')
  # Cap derived, not chosen: worst-case measured 3905 B on this commit (invariant text 3265 B +
  # the hook's own 320+80+240 B worst-case root/branch/base padding), +25% headroom to match the
  # philosophy stated at the top of this check. 4992 is that number rounded up to a clean
  # multiple of 128. Recompute _baseline_worst by hand if this ever needs re-deriving -- it is
  # not a magic constant, it is this formula's output on the day it was set. It was 5888 against
  # a 4630 B worst case until the TOKENS/DELEGATE/AUTONOMY/PLAN MODE prose came out of the
  # SessionStart block (989 B off the raw count); a cap left at its pre-trim value would have
  # quietly granted 900 B of room the trim was the whole point of reclaiming. Below this cap:
  # the WORKSPACE CONVENTIONS block's structural text is bounded. Above it: something added
  # prose there, on every checkout, regardless of path length or remote default branch.
  _baseline_cap=4992
  [ "$_baseline_worst" -le "$_baseline_cap" ] \
    || errs="$errs\nsession baseline: normalized $_baseline_worst bytes (raw $_baseline_raw B at this checkout) exceeds the $_baseline_cap byte worst-case cap"

  # Path-invariance control. The normalization above is only honest if it removes every byte
  # that scales with where this repo sits on disk -- prove that live rather than asserting it.
  # Run the SAME probe from two directories of deliberately different path length and require
  # the SAME normalized (worst-case) count out of both. If a future edit splices in some other
  # environment-dependent string this formula does not know about, the two numbers disagree,
  # which is exactly the class of bug check 18's cap shipped with. Both directories are throwaway
  # git repos on the same branch name (main, forced via symbolic-ref rather than `git init -b`
  # for portability to older git), so path length is the only thing that differs between them.
  _inv_root="${TMPDIR:-/tmp}/vstack-inv-verify.$$"
  rm -rf "$_inv_root"
  _inv_short="$_inv_root/a"
  _inv_long="$_inv_root/a-much-longer-directory-name-chosen-to-move-the-prefix-by-a-lot"
  mkdir -p "$_inv_short" "$_inv_long"
  # The two repos differ in path length AND in remote default branch name. $base is spliced
  # three times into the same block, so a checkout whose origin/HEAD is `origin/a-long-name`
  # carries ~60 more bytes than one on `origin/main` -- environment text this normalization used
  # to ignore on the stated grounds that it "does not vary with this checkout." It varies with
  # the remote, which is no less environmental. Vary both here so neither source can rot unproven.
  _inv_i=0
  for _id in "$_inv_short" "$_inv_long"; do
    git -C "$_id" init -q >/dev/null 2>&1
    git -C "$_id" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
    _inv_i=$((_inv_i + 1))
    if [ "$_inv_i" = 1 ]; then _inv_b=main
    else _inv_b=a-deliberately-long-default-branch-name-to-move-the-base-splice; fi
    git -C "$_id" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$_inv_b" >/dev/null 2>&1
  done
  _inv_worst(){ # dir -> worst-case normalized byte count for a SessionStart probe run there
    _wd="$1"
    _wraw=$(printf '{"hook_event_name":"SessionStart"}' \
      | env CLAUDE_PROJECT_DIR="$_wd" CONDUCTOR_WORKSPACE_PATH="" bash claude/hooks/inject-session-context.sh 2>/dev/null \
      | wc -c | tr -d ' ')
    _wr=$(git -C "$_wd" rev-parse --show-toplevel 2>/dev/null | tr -cd 'A-Za-z0-9 ._/-' | head -c 160)
    _wb=$(git -C "$_wd" branch --show-current 2>/dev/null | tr -cd 'A-Za-z0-9._/-' | head -c 80)
    [ -n "$_wb" ] || _wb='<detached>'
    _wg=$(_base_of "$_wd")
    awk -v raw="$_wraw" -v rl="${#_wr}" -v bl="${#_wb}" -v gl="${#_wg}" \
      'BEGIN{print raw - 2*rl - bl - 3*gl + 2*160 + 80 + 3*80}'
  }
  _wc_short=$(_inv_worst "$_inv_short")
  _wc_long=$(_inv_worst "$_inv_long")
  rm -rf "$_inv_root"
  [ "$_wc_short" = "$_wc_long" ] \
    || errs="$errs\npath invariance: normalized byte count disagreed by checkout path length and remote default branch ($_wc_short B at a short prefix on origin/main vs $_wc_long B at a long one on a long default branch) -- the normalization above is not honest until these agree"

  chk "skills profile"         "$(probe SessionStart skills 1)"  512 2560
  # The README publishes these byte counts as the cost column of its comparison table. A number
  # in prose that nothing re-derives is a number that goes stale, which is the failure this repo
  # keeps finding in its own docs — so the published figures are read back and compared.
  #
  # Anchored on the row's LABEL, not on its figures. This was
  #   if [ -f README.md ] && grep -qE '~[0-9.]+ KB full / ~[0-9.]+ KB plugin' README.md
  # with no else, and cc76ba8 -- a README rewrite from 469 lines to 226 -- moved the sentence it
  # keyed on. The comparison then did nothing for eleven commits while the check printed ok, and
  # the same rewrite killed a second guard the same way. It happened a second time during the
  # v1.15.0 audit, on a second rewrite, while the fix was being written: a later commit here is
  # titled "put back the anchor my own mutation test moved". Anchoring on the figures cannot
  # survive that, because the figures are precisely the thing people edit. The label states what
  # the row means and outlives a rewrite of what the row says.
  #
  # Three outcomes, three messages. The row missing and the row present with an unparseable
  # value are different repairs, and conflating them sends the next reader looking for a row
  # that is sitting in front of them.
  # The INVARIANT count, not the raw one. Comparing a published figure against a raw measurement
  # made the README's number a property of the author's directory: this repo measured 4077 B in
  # a 25-character checkout path on `main` and 4163 B in a clone three characters longer whose
  # origin/HEAD pointed at a 24-character branch, which is 3.9 KB and 4.1 KB against a 0.15 KB
  # tolerance. The cap lane above was fixed for exactly this and the figure lane was left reading
  # raw, so the check passed on one machine and failed everywhere else -- a green that was a
  # property of where it ran. A published number has to be one a reader can reproduce.
  _full=$_baseline_inv
  _sk=$(probe SessionStart skills 1)
  _label='Context spent per session'
  _row=$(grep -F "| $_label " README.md 2>/dev/null | head -1)
  _qf=$(printf '%s' "$_row" | grep -oE '~[0-9.]+ KB full' | grep -oE '[0-9.]+')
  _qs=$(printf '%s' "$_row" | grep -oE '~[0-9.]+ KB plugin' | grep -oE '[0-9.]+')
  _lf=$(awk -v b="$_full" 'BEGIN{printf "%.1f", b/1024}')
  _ls=$(awk -v b="$_sk"   'BEGIN{printf "%.1f", b/1024}')
  if [ -z "$_row" ]; then
    errs="$errs\nREADME has no '$_label' row, so the published session cost was compared against nothing -- restore the row or repoint this at the one that replaced it"
  elif [ -z "$_qf" ] || [ -z "$_qs" ]; then
    errs="$errs\nREADME's '$_label' row is present but no ~N KB full / ~N KB plugin figures parse out of it -- the value format changed, not the row"
  else
    # Compared with tolerance, not for equality. The exact byte count is not a publishable
    # constant: the block embeds environment-dependent text, so this machine measured 3655, a
    # worktree on it measured 3670, and CI measured 3667 for the same commit. Demanding equality
    # made the gate depend on where it ran, which is a worse failure than the staleness it was
    # added to prevent. Real drift moves this by hundreds of bytes; noise moves it by tens.
    awk -v a="$_qf" -v b="$_lf" 'BEGIN{exit (a-b<0.15 && b-a<0.15)?0:1}' \
      || errs="$errs\nREADME quotes ~$_qf KB for the full session cost; live is ~$_lf KB"
    awk -v a="$_qs" -v b="$_ls" 'BEGIN{exit (a-b<0.15 && b-a<0.15)?0:1}' \
      || errs="$errs\nREADME quotes ~$_qs KB for the plugin session cost; live is ~$_ls KB"
  fi
  [ -z "$errs" ] \
    && ok "injected context bounded (digest $_digest B fired / $(probe UserPromptSubmit '' 1) B unfired, baseline $_baseline_raw B raw / $_baseline_inv B invariant / $_baseline_worst B worst-case)" \
    || bad "injected context bounded" "$(printf '%b' "$errs")"
else
  skip "injected context bounded" "jq not installed"
fi

# --- 19. the plugin manifests pass Claude Code's own validator ---------------------------------
# Checks 2 and 13 confirm the manifests parse and agree on a version. Neither knows the schema.
# `claude plugin validate --strict` does, and it fails on fields this repo would otherwise ship
# misspelled — the marketplace lane is the one surface a stranger installs, so a manifest that
# only *looks* right is the worst place for a silent defect.
#
# Positive control first. This check delegates its judgement to somebody else's binary, and a
# binary that answers "fine" to everything is indistinguishable from a repo with no problems.
# That is not hypothetical: this check printed ok on CI against a manifest deliberately broken
# by the falsifiability suite, because `claude plugin validate` exited 0 there while the same
# CLI version rejected the same manifest locally. The check was green and measuring nothing.
#
# So hand the validator a manifest that must be rejected, and if it accepts it, say the check
# cannot measure here rather than reporting a pass on its behalf.
# The control runs both ways, because each direction catches a different lie. A validator that
# rejects everything looks identical to a broken repo: on CI the `claude` shim was on PATH while
# its native binary was missing, so every invocation exited non-zero with an installation error
# and nothing here could tell that apart from a genuinely bad manifest. A validator that accepts
# everything looks identical to a healthy one. Require it to accept a good manifest AND reject a
# bad one before believing a word it says about this repo's.
ctl_state=usable
if command -v claude >/dev/null 2>&1; then
  ctl=$(mktemp -d)
  mkdir -p "$ctl/good/.claude-plugin" "$ctl/bad/.claude-plugin"
  # The good manifest carries author too: without it --strict warns about missing attribution
  # and the control fails itself, which reads exactly like a broken validator.
  printf '{"name":"probe","version":"0.0.1","description":"control","author":{"name":"control"}}\n' \
    > "$ctl/good/.claude-plugin/plugin.json"
  printf '{"name":42,"version":"nope"}\n'                               > "$ctl/bad/.claude-plugin/plugin.json"
  if ! ctl_out=$(claude plugin validate --strict "$ctl/good" 2>&1); then
    ctl_state="cannot run: $(printf '%s' "$ctl_out" | grep -v '^$' | head -1)"
  elif claude plugin validate --strict "$ctl/bad" >/dev/null 2>&1; then
    ctl_state="accepts anything: it passed a manifest with name:42"
  fi
  rm -rf "$ctl"
fi
if command -v claude >/dev/null 2>&1 && [ "$ctl_state" != usable ]; then
  skip "plugin manifests valid" "validator $ctl_state — reporting its answer would be reporting its own silence"
elif command -v claude >/dev/null 2>&1; then
  errs=""
  # Exactly one warning is expected: claude/CLAUDE.md is the source for the global and overlay
  # lanes and only happens to sit inside the plugin source directory. The plugin lane
  # deliberately does not load it, so the warning is correct and must not fail the run.
  #
  # This used to allow for it by grepping validate's output for the '❯' bullet and discarding
  # the line that named CLAUDE.md. That read the repo's health off a decorative glyph. CI does
  # not run on a TTY and its output carries no '❯', so the filter found nothing, concluded
  # there were no unknown warnings, and printed ok over a manifest the falsifiability suite had
  # deliberately corrupted. Green on CI, red locally, same CLI version, for a bullet character.
  #
  # Validate a copy with CLAUDE.md removed instead. Then the expected warning cannot arise, no
  # output has to be parsed at all, and the exit status means what it says.
  tmpp=$(mktemp -d)
  cp -R claude "$tmpp/plugin" && rm -f "$tmpp/plugin/CLAUDE.md"
  for m in . "$tmpp/plugin"; do
    if ! out=$(claude plugin validate --strict "$m" 2>&1); then
      errs="$errs\n${m#"$tmpp/"}:\n$out"
    fi
  done
  rm -rf "$tmpp"
  [ -z "$errs" ] && ok "plugin manifests valid (claude plugin validate --strict)" \
    || bad "plugin manifests valid" "$(printf '%b' "$errs")"
else
  skip "plugin manifests valid" "claude CLI not installed"
fi

# --- 20. every installed path named in prose is one install.sh actually creates ----------------
# The `/bootstrap` command told the model to run `~/.claude/scripts/bootstrap-claude-project.sh`.
# No such script was ever in this repo and install.sh never wrote one. It worked on the author's
# machine only because a pre-vstack copy happened to survive there, so the command was broken for
# every other human on earth and nothing noticed for months.
#
# This is the same defect class as the stale `orchestrate.md` -- prose and installed tree
# disagreeing -- just pointing the other way. Check 12 counts things; nothing read the paths back.
# A referenced path either maps to something in this repo that install.sh copies, or it is
# runtime state, or it is declared foreign below; anything else is a promise the installer
# does not keep.
#
# The first version of this extractor matched only ~/.claude, ~/.config/agents and ~/.conductor.
# That is an allow-list wearing a scanner's clothes: `/push` told the model to run
# `~/.100xprompt/hooks/pre-push.sh`, a path belonging to an entirely different tool's template,
# and the regex never saw it because it did not begin with one of the three blessed prefixes.
# The check written to catch a command pointing at a script nobody installs could not catch a
# command pointing at a script nobody installs, one namespace over. It now reads every ~/-rooted
# path and a foreign one must be declared, with a reason, rather than pass by being unmatched.
# Every ~ below is single-quoted on purpose. An unquoted tilde in a `case` pattern or a `${x#...}`
# prefix is expanded to $HOME before the match, so the first draft of this check compared
# "~/.claude/CLAUDE.md" against "/Users/<me>/.claude/CLAUDE.md", matched nothing, and reported
# every path in the repo as unmapped. The check was loud and completely wrong.
# shellcheck disable=SC2088  # these tildes are match patterns, not paths: the strings being
# matched are the literal "~/..." spellings that appear in documentation, so expanding them here
# is exactly the bug this function was fixed for.
runtime_path(){ # paths that exist at runtime but are created by Claude Code or by use, not install
  case "$1" in
    '~/.claude'|'~/.claude.json'|'~/.claude/settings.json'|'~/.claude/settings.local.json') return 0 ;;
    '~/.claude/projects'*|'~/.claude/plugins'*|'~/.claude/sessions'*|'~/.claude/tasks'*|'~/.claude/plans'*) return 0 ;;
    '~/.claude/shell-snapshots'/*|'~/.claude/history.jsonl'|'~/.claude/scheduled-tasks'*|'~/.claude/.credentials.json') return 0 ;;
    '~/.config/agents'|'~/.config/agents/secrets.env'|'~/.config/agents/verify-trust') return 0 ;;
    '~/.config/agents/vstack-repo'|'~/.config/agents/backups'*|'~/.config/agents/logs'*|'~/.config/agents/bg'*|'~/.config/agents/doctor.log') return 0 ;;
    '~/.conductor'|'~/.conductor/settings.toml'|'~/.conductor/settings.managed.toml') return 0 ;;
    # the shipped directories themselves, referenced bare ("installs to ~/.claude/skills/")
    '~/.claude/hooks'|'~/.claude/agents'|'~/.claude/commands'|'~/.claude/skills') return 0 ;;
    '~/.config/agents/bin'|'~/.config/agents/shell') return 0 ;;
  esac
  return 1
}
# Paths outside every namespace this repo installs into. Each entry states why it is here; a
# bare addition with no reason is how the ~/.100xprompt reference would have been waved through
# a second time. "It appears in the tree" is not a reason -- the reason has to be that the path
# belongs to something the user supplies and the docs are right to name.
# shellcheck disable=SC2088  # match patterns, not paths -- see runtime_path above
external_path(){
  case "$1" in
    # The repo checkout itself. Docs name it because the installer is run from it; install.sh
    # cannot create the directory it is being run out of.
    '~/Projects/vstack'|'~/Projects/vstack/'*) return 0 ;;
  esac
  return 1
}
# Paths install.sh CREATES BY WRITING rather than by copying, so there is no repo file to
# compare against -- src_for's "install copies a tracked file there" model does not apply, and
# runtime_path's "not install's doing at all" is wrong the other way: install.sh's own own()
# function writes ~/.config/agents/vstack-installed on every run (install.sh:65-66,
# OWNED_PATHS="$HOME/.config/agents/vstack-installed"). Filing a file install.sh itself creates
# under "not install's doing" is a false classification in the one check whose subject is prose
# and the tree disagreeing.
#
# The list below is floored, not a bare allow-list: the loop right after src_for asserts
# install.sh actually contains the literal path for every entry here, with the leading ~/
# rewritten to $HOME. A bare addition here would be exactly the shape this repo catalogues nine
# times over -- an exemption nothing holds to account. Renaming OWNED_PATHS's target turns this
# check red naming the floor, instead of silently widening the exemption to cover the old name
# forever.
# shellcheck disable=SC2088  # a literal "~/..." spelling to match against, like runtime_path above
INSTALL_GENERATED_PATHS='~/.config/agents/vstack-installed'
# shellcheck disable=SC2088  # match patterns, not paths -- see runtime_path above
install_generated(){
  case " $INSTALL_GENERATED_PATHS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
# A third shape neither category above can express. install.sh neither copies nor creates
# ~/.zshrc and ~/.zshenv: they already exist and belong to the user, and the installer appends a
# fenced block to each. Modelling them as copies would be false and modelling them as foreign
# would be worse, so until now they were modelled as nothing -- and a path this check cannot
# express is a path README's "What lands where" table was never asked about. The table listed
# every rule install.sh has and was still missing the one edit a stranger would most want warned
# about. Floored like INSTALL_GENERATED_PATHS: each entry must appear in install.sh as a literal
# append, so deleting the append turns this red instead of silently retiring the disclosure.
# shellcheck disable=SC2088  # a literal "~/..." spelling to match against, like runtime_path above
INSTALL_APPENDED_PATHS='~/.zshrc ~/.zshenv'
# shellcheck disable=SC2088  # match patterns, not paths -- see runtime_path above
install_appended(){
  case " $INSTALL_APPENDED_PATHS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
# shellcheck disable=SC2088  # match patterns, not paths -- see runtime_path above
src_for(){ # installed path -> the repo file install.sh copies there, or empty if unmapped
  case "$1" in
    '~/.claude/hooks/'*)        printf 'claude/hooks/%s'    "${1#'~/.claude/hooks/'}" ;;
    '~/.claude/agents/'*)       printf 'claude/agents/%s'   "${1#'~/.claude/agents/'}" ;;
    '~/.claude/commands/'*)     printf 'claude/commands/%s' "${1#'~/.claude/commands/'}" ;;
    '~/.claude/skills/'*)       printf 'claude/skills/%s'   "${1#'~/.claude/skills/'}" ;;
    '~/.claude/CLAUDE.md')      printf 'claude/CLAUDE.md' ;;
    '~/.claude/statusline.sh')  printf 'claude/statusline.sh' ;;
    '~/.config/agents/bin/'*)   printf 'bin/%s'   "${1#'~/.config/agents/bin/'}" ;;
    '~/.config/agents/shell/'*) printf 'shell/%s' "${1#'~/.config/agents/shell/'}" ;;
  esac
}
errs=""
ig_n=0
for _ig in $INSTALL_GENERATED_PATHS; do
  ig_n=$((ig_n + 1))
  _igh="\$HOME${_ig#'~'}"
  grep -Fq "$_igh" install.sh \
    || errs="$errs\ninstall_generated names $_ig but install.sh does not contain the literal path $_igh -- the exemption may be stale"
done
ia_n=0
for _ia in $INSTALL_APPENDED_PATHS; do
  ia_n=$((ia_n + 1))
  _iah=">> \"\$HOME${_ia#'~'}\""
  grep -Fq "$_iah" install.sh \
    || errs="$errs\ninstall_appended names $_ia but install.sh contains no literal append $_iah -- the exemption may be stale"
done
# shellcheck disable=SC2088  # the heredoc below greps for the literal "~/..." spelling in docs
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  runtime_path "$ref" && continue
  external_path "$ref" && continue
  install_generated "$ref" && continue
  install_appended "$ref" && continue
  src=$(src_for "$ref")
  if [ -z "$src" ]; then
    errs="$errs\n$ref: no install.sh rule puts anything there, and it is not declared foreign"
  elif [ ! -e "$src" ]; then
    errs="$errs\n$ref: install.sh would copy $src, which does not exist in this repo"
  fi
done <<EOF
$(grep -rhoE '~/[A-Za-z0-9._/-]+' \
    README.md claude/commands claude/agents claude/skills 2>/dev/null \
  | sed 's#[.,:;)`"]*$##; s#/$##' | sort -u)
EOF
[ -z "$errs" ] && ok "referenced install paths exist ($ig_n install_generated + $ia_n install_appended entries floored)" \
  || bad "referenced install paths exist" "$(printf '%b' "$errs")"

# --- 21. install.sh only deletes keys this repo actually retired -------------------------------
# install.sh delpaths every key in RETIRED out of the user's live settings.json on every run.
# That is the one genuinely destructive thing the installer does to a file it does not own, so
# the list needs a source of truth, and it has exactly one: a key qualifies only if
# claude/settings.json shipped it at some point and does not ship it now.
#
# The first RETIRED list was written from plausible-sounding names rather than from that
# history, and three of its four entries were Claude Code's own settings — including "sandbox",
# which would have stripped a user's native Bash sandboxing on every install. A reviewer caught
# it before it shipped. This check is why it cannot come back.
if command -v jq >/dev/null && command -v git >/dev/null; then
  retired=$(sed -n "s/^RETIRED='\(.*\)'.*/\1/p" install.sh | head -1)
  if [ -z "$retired" ]; then
    bad "RETIRED names only retired keys" "could not extract RETIRED from install.sh"
  else
    ever=$(for s in $(git log --all --format=%H -- claude/settings.json); do
             git show "${s}:claude/settings.json" 2>/dev/null | jq -r 'keys[]?' 2>/dev/null
           done | sort -u)
    now=$(jq -r 'keys[]' claude/settings.json | sort -u)
    errs=""
    for k in $(printf '%s' "$retired" | jq -r '.[]?' 2>/dev/null); do
      grep -qx "$k" <<<"$now"  && errs="$errs\n$k: still shipped in claude/settings.json, so it is not retired"
      grep -qx "$k" <<<"$ever" || errs="$errs\n$k: claude/settings.json has never shipped it — not this repo's key to delete"
    done
    nret=$(printf '%s' "$retired" | jq -r 'length')

    # RETIRED ships empty, which is correct: this repository currently retires nothing. But an
    # empty list means the loop above never runs, and "ok (0 entries)" then reads like a
    # measurement of zero rather than the absence of one -- a green with no evidence under it,
    # which is the shape this whole gate exists to remove. Skipping instead would be honest and
    # would still measure nothing.
    #
    # So measure the decider, the way checks 23, 27, 32 and 37 do. Two synthetic keys, one of
    # each kind, run through the same two comparisons the loop uses. A key still shipping must
    # be rejected as not retired; a key this repository has never shipped must be rejected as
    # not ours to delete. If those stop deciding correctly, the loop would not catch a real
    # retirement either, and that is true whether or not RETIRED currently has anything in it.
    ctl=""
    _live=$(printf '%s\n' "$now" | head -1)
    if [ -n "$_live" ]; then
      grep -qx "$_live" <<<"$now" || ctl="$ctl\n  control: a key claude/settings.json ships right now was not seen as still shipped"
    else
      ctl="$ctl\n  control: claude/settings.json has no keys, so this compared nothing"
    fi
    grep -qx 'zz-never-a-real-key' <<<"$ever" \
      && ctl="$ctl\n  control: a key this repository has never shipped was reported as having shipped"

    if [ -n "$ctl" ]; then
      bad "RETIRED names only retired keys" "$(printf '%b' "$ctl")"
    else
      [ -z "$errs" ] \
        && ok "RETIRED names only retired keys ($nret entries, decider verified both directions)" \
        || bad "RETIRED names only retired keys" "$(printf '%b' "$errs")"
    fi
  fi
else
  skip "RETIRED names only retired keys" "jq or git not installed"
fi

# --- 22. a skill never tells the model to use something the port does not ship -----------------
# The impeccable skill's body is upstream's, and it names 19 helper scripts across 42 places
# that this port deliberately does not vendor. That is disclosed in ATTRIBUTION.md, but
# disclosure is not the same as safety: the model reads the body, not the attribution, and one
# line was still a flat imperative to execute a missing file. Check 20 covers ~/.claude paths
# in prose; nothing looked inside a skill at the scripts it tells you to run.
#
# The rule is not "never reference a script you do not ship" — a faithful port of someone
# else's playbook will mention their tooling. It is that a skill doing so must say, in its own
# body, that those steps are unavailable. A reader of the skill has to learn it from the skill.
errs=""
for d in claude/skills/*/; do
  sk="$d/SKILL.md"; [ -f "$sk" ] || continue
  name=$(basename "$d")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Command-shaped references only: at the start of a line, in backticks, or after an
    # interpreter. A skill that merely names a script as an example — show-me-your-work's
    # sample decision log cites one as illustrative evidence, and says so — is not telling
    # anyone to run anything.
    refs=$(grep -hE '(^[[:space:]]*|`|node |bash |sh |python3? |\./)[A-Za-z0-9_./-]*scripts/[A-Za-z0-9_-]+\.(mjs|js|py|sh)' "$f" 2>/dev/null \
           | grep -oE '[A-Za-z0-9_./-]*scripts/[A-Za-z0-9_-]+\.(mjs|js|py|sh)' | sort -u)
    missing=""
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      base=${r##*scripts/}
      [ -e "$d/scripts/$base" ] || missing="$missing $base"
    done <<EOF
$refs
EOF
    # Namespaced skill references (superpowers:writing-plans, elements-of-style:...) are the
    # same defect wearing different clothes: a ported skill telling the model to invoke a skill
    # that is not installed here. The model reads the body, not ATTRIBUTION.md, and a dangling
    # `use superpowers:using-git-worktrees` is an instruction it will try to follow.
    #
    # Check 7 does not see these — its token pattern skips the namespace prefix — so six of them
    # sat across three skills through every green run.
    for sref in $(grep -hoE '\b[a-z][a-z0-9-]+:[a-z][a-z0-9-]+\b' "$f" 2>/dev/null | sort -u); do
      ns=${sref%%:*}; nm=${sref##*:}
      case "$ns" in http|https|file|note|warning|example|step|phase|input|output|result|goal|why|how|when|use|see|tip|nb|eg|ie) continue ;; esac
      [ -d "claude/skills/$nm" ] && continue
      [ -d "claude/skills/$sref" ] && continue
      missing="$missing $sref"
    done
    [ -n "$missing" ] || continue
    # The notice has to reach whoever is reading. It counts in the file carrying the commands,
    # or in SKILL.md, which every reader passes through first.
    # The accepted phrasings are listed rather than guessed at. Widening this is a deliberate
    # act: each phrase here is one a reader of the file would actually understand as "do not
    # try to use this", not a keyword that happens to appear nearby.
    _disc='unavailable here|not available here|not (included|vendored)|Not vendored here'
    if ! grep -qiE "$_disc" "$f" && ! grep -qiE "$_disc" "$sk"; then
      errs="$errs\n${f#claude/skills/}: points at things this port does not ship ($missing ) with no notice"
    fi
  done <<EOF
$(find "$d" -type f -name '*.md' | sort)
EOF
done
[ -z "$errs" ] && ok "skills disclose what they do not ship" \
  || bad "skills disclose what they do not ship" "$(printf '%b' "$errs")"

# --- 23. the destructive-command guard decides correctly ---------------------------------------
# The guard is armed on every install and runs before every Bash command, which makes it the
# single piece of this repo most able to do harm by being wrong in either direction: too loose
# and it is decoration, too tight and someone disables it and loses the protection entirely.
#
# gstack, where the idea comes from, ships an equivalent with no test of its decisions at all.
# A guard nobody has watched deny is indistinguishable from a guard that returns allow.
#
# The three tiers are asserted by feeding real payloads through the real hook: catastrophic
# commands must deny, destructive-but-legitimate ones must ask, and the commands an agent runs
# constantly must pass without a prompt. That last row is the one that keeps the guard installed.
if command -v jq >/dev/null; then
  errs=""
  g_decide(){ printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" \
                | bash claude/hooks/guard-destructive.sh 2>/dev/null \
                | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null; }
  # G_N counts the table rather than restating it. The label used to carry a literal, which went
  # from 16 to 22 to 24 while SECURITY.md still said sixteen -- a number in prose that nothing
  # re-derives is a number that rots, and this file exists to catch exactly that.
  G_N=0
  g_want(){ # <command> <expected>
    G_N=$((G_N+1))
    got=$(g_decide "$1")
    [ "$got" = "$2" ] || errs="$errs\n'$1' -> $got, expected $2"
  }
  g_want 'rm -rf /'                      deny
  g_want 'rm -rf ~'                      deny
  g_want 'rm -rf $HOME'                  deny
  g_want 'rm -rf /*'                     deny
  g_want 'rm -rf ~/*'                    deny
  # Same directory, four more spellings. The list this replaced was nine literals long and still
  # let every one of these through to `ask`, while `~/*` two lines up was denied -- identical
  # effect, opposite verdict, decided by which way the operator happened to type it.
  g_want 'rm -rf $HOME/*'                deny
  g_want 'rm -rf "$HOME"/*'              deny
  g_want 'rm -rf "${HOME}"'              deny
  g_want 'rm -rf ${HOME}/*'              deny
  g_want 'git push --force origin main'  deny
  g_want 'git push -f origin master'     deny
  g_want 'true && git push --force origin main' deny
  g_want 'git push -f origin HEAD:refs/heads/main' deny
  g_want 'echo hi; rm -rf /'             deny
  g_want 'git push --force origin refs/heads/main:refs/heads/main' deny
  # Wildcard staging is tier-dependent on WHERE it runs, so it needs its own probe: the decision
  # turns on CONDUCTOR_WORKSPACE_PATH and $PWD, not on the command alone. Both directions are
  # asserted. A rule that only ever asks would pass a test that only checks that it asks, and the
  # allow rows are the ones that keep this guard installed -- `git add -A` inside your own
  # workspace is the normal case and must stay silent.
  g_ws(){ # <command> <workspace_path> <expected>
    G_N=$((G_N+1))
    got=$(printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" \
            | env CONDUCTOR_WORKSPACE_PATH="$2" bash claude/hooks/guard-destructive.sh 2>/dev/null \
            | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ "$got" = "$3" ] || errs="$errs\n'$1' in workspace '$2' -> $got, expected $3"
  }
  g_ws 'git add -A'            /nonexistent/other-workspace ask
  g_ws 'git add .'             /nonexistent/other-workspace ask
  g_ws 'git commit -am "wip"'  /nonexistent/other-workspace ask
  g_ws 'git add bin/doctor'    /nonexistent/other-workspace allow
  g_ws 'git commit -m "add a thing"' /nonexistent/other-workspace allow
  g_ws 'git add -A'            "$PWD"                       allow
  g_want 'rm -rf /etc/nginx'             ask
  g_want 'git reset --hard HEAD~3'       ask
  g_want 'psql -c "DROP TABLE users"'    ask
  g_want 'terraform destroy'             ask
  g_want 'npm test && rm -rf node_modules' allow
  g_want 'rm -rf node_modules /etc'      ask
  g_want 'rm -rf node_modules'           allow
  g_want 'rm -rf dist'                   allow
  # Quoted spellings of the same safe paths. This is the tier the comment above calls the one
  # that keeps the guard installed, and every quoted form of it used to prompt: the whitelist
  # compared against the token as typed, so the literal quote characters never matched
  # `node_modules` or `/tmp/*`. An agent that quotes its paths got a confirmation dialog on
  # every build-artifact delete, which is how a guard gets turned off.
  g_want 'rm -rf "node_modules"'         allow
  g_want 'rm -rf "./dist"'               allow
  g_want 'rm -rf "/tmp/x"'               allow
  g_want 'npm test'                      allow
  g_want 'git push origin feature-x'     allow
  g_want 'git commit -m "wip"'           allow
  g_want 'vstack trust .'                ask
  g_want 'echo x >> ~/.config/agents/verify-trust' ask
  # The same decisions with a hostile environment. This is the case that would have caught the
  # guard shipping broken on every Linux host: it used "$TMPDIR" in a case pattern, TMPDIR is
  # routinely unset there, set -u made that fatal, and the hook emitted nothing at all. macOS
  # sets TMPDIR, so it passed locally and failed on three platforms in CI.
  for probe in 'rm -rf /:deny' 'rm -rf /etc/nginx:ask' 'rm -rf node_modules:allow'; do
    pc=${probe%:*}; pw=${probe##*:}
    pd=$(printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$pc" '$c')" \
         | env -u TMPDIR -u HOME -u USER -u LANG bash claude/hooks/guard-destructive.sh 2>/dev/null \
         | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ "$pd" = "$pw" ] || errs="$errs\nwith a stripped environment, '$pc' -> ${pd:-<no output>}, expected $pw"
  done

  # The decider's permission-mode axis. docs/guard-enforcement-gap.md's seventh fake green: the
  # guard returns `ask` for commands that destroy uncommitted work, but under bypassPermissions
  # -- the mode every unattended agent runs in -- an `ask` decision auto-approves, so the tier
  # that matters is what the guard decides ONCE permission_mode is in the payload, not what it
  # decides in the payload shape above (which never sets the key at all). This is that join,
  # tested directly against the real hook rather than reasoned about from the two halves
  # separately, which is exactly how the join went untested the first time.
  g_pm(){ # <command> <permission_mode> <expected>
    G_N=$((G_N+1))
    got=$(printf '{"tool_input":{"command":%s},"permission_mode":%s}' \
            "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg m "$2" '$m')" \
            | bash claude/hooks/guard-destructive.sh 2>/dev/null \
            | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ "$got" = "$3" ] || errs="$errs\n'$1' under permission_mode=$2 -> $got, expected $3"
  }
  g_pm 'git stash'                 bypassPermissions deny
  g_pm 'git reset --hard HEAD~3'   bypassPermissions deny
  g_pm 'git clean -fd'             bypassPermissions deny
  g_pm 'git reset --hard HEAD~3'   default           ask
  g_pm 'git stash pop'             bypassPermissions allow
  # An ask-tier command OUTSIDE the escalation set must stay ask under bypassPermissions.
  # Escalating every ask-tier command to deny under bypass would be the lazy fix -- it would
  # pass the five rows above and still be wrong, because it stops distinguishing "destroys
  # uncommitted work" from "merely needs a human."
  g_pm 'terraform destroy'         bypassPermissions ask
  # permission_mode absent from the payload entirely -- not "bypassPermissions", not "default",
  # simply not there, which is what every other row in this check (g_want, g_ws, the hostile-
  # environment loop above) already sends. An escalation-set command must resolve to exactly
  # today's tier here: not silently escalated as if bypass were assumed, and not silently
  # treated as safe because the field was missing. Unknown must not read as either extreme.
  G_N=$((G_N+1))
  got=$(printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c 'git reset --hard HEAD~3' '$c')" \
          | bash claude/hooks/guard-destructive.sh 2>/dev/null \
          | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
  [ "$got" = ask ] || errs="$errs\n'git reset --hard HEAD~3' with permission_mode absent from the payload -> $got, expected ask"

  # Unparseable or absent input must never reach allow. A guard that opens on malformed input
  # has inverted its own purpose, and malformed input is exactly what an attacker sends.
  for bad in 'not json' ''; do
    d=$(printf '%s' "$bad" | bash claude/hooks/guard-destructive.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ "$d" = ask ] || errs="$errs\nmalformed payload -> $d, expected ask"
  done
  # The label used to claim only "decides correctly, 3 tiers", which reads as coverage this
  # check does not have: it verifies the DECIDER in isolation, every time, against a real hook
  # invocation -- it does not re-run the runtime join (does bypassPermissions actually
  # auto-approve an `ask` the way the platform is documented to) on every gate run. That join was
  # proven once, by hand, measured in docs/guard-enforcement-gap.md, and is not re-checked here.
  # A label claiming coverage the check does not have is the same defect under a different name.
  [ -z "$errs" ] && ok "destructive guard decides correctly ($G_N commands, 3 tiers) (decider only, not runtime enforcement -- see docs/guard-enforcement-gap.md)" \
    || bad "destructive guard decides correctly" "$(printf '%b' "$errs")"
else
  skip "destructive guard decides correctly" "jq not installed"
fi

# --- 24. the declared version describes what actually installs -------------------------------
# Three lanes install three different trees. `VSTACK_REF=v1.4.0` gets the tag; an unpinned
# bootstrap resolves the latest release tag (since 1.65.0; it took the default branch before);
# the plugin marketplace still takes the default branch.
# So when the payload moves ahead of the tag while the manifests still name it, a stranger
# installs something that is not the version it claims to be — and the changelog describes a
# different artefact than the one they got.
#
# The rule is narrow on purpose: it does not demand that HEAD always be a release. It only
# demands that if a tag exists with the version the manifests declare, the installable payload
# is identical to it. Between releases you simply bump the version, and the check goes quiet
# until that version is tagged.
if command -v git >/dev/null && command -v jq >/dev/null; then
  mv_=$(jq -r '.version' claude/.claude-plugin/plugin.json 2>/dev/null)

  # A version pinned in the docs is not documentation, it is the thing a stranger installs. The
  # quickstart pinned v1.4.0 while the manifests said v1.8.0, so anyone copy-pasting the "pin a
  # release" lane got a four-version-old payload and no error -- the tag resolves, the install
  # succeeds, and the only symptom is a setup that quietly disagrees with its own README.
  #
  # Agreeing with the manifest is not enough. The quickstart's "pin a release" lane pinned
  # v1.8.0 while the manifests said v1.8.0 and no such tag existed, so the check was satisfied
  # and the URL a stranger copy-pastes returned 404. A pin has to name a tag that is actually
  # there.
  #
  # The right target is the newest tag, not the manifest version. Comparing against the manifest
  # was this check contradicting its own contract two paragraphs up: "between releases you simply
  # bump the version, and the check goes quiet until that version is tagged". It did not go quiet.
  # Bumping the manifest made every README pin wrong on the spot, and pinning the new version
  # instead made the URL 404, so there was no green state anywhere between the bump and the tag --
  # a release could only be prepared by leaving the gate red, which is how a red gate becomes
  # something you learn to walk past.
  #
  # Both defects that wrote this rule are still caught, and one more with them: a pin at v1.4.0
  # while v1.8.0 is the newest tag is stale, a pin at an untagged v1.8.0 is a 404, and now a pin
  # at any real-but-not-newest tag is stale too. Sorted by git itself (--sort=-v:refname) rather
  # than by `sort -V`, which busybox does not have. Only asserted where the checkout has tags at
  # all -- a shallow clone has none, and the branch below already declines to measure in that case.
  #
  # LOCAL TAGS ONLY, stated because it cost a day. This file is hermetic by design and makes no
  # network call, so "is a tag in this repository" means "is a tag in THIS CHECKOUT" -- and a tag
  # you created locally and never pushed is invisible to every stranger following the README.
  # Measured 2026-08-27: this machine held a v1.46.0 the remote did not, so the pin at v1.46.0
  # read as valid here while CI, whose clone has only what origin has, reported the documented
  # install URL as a 404. The gate was green and the install path was broken at the same moment,
  # which is the exact pair this check was written to make impossible.
  #
  # The remote half is bin/doctor's "declared release is fetchable", which does `git ls-remote`
  # and therefore lives outside this file. Neither check is sufficient alone: this one catches a
  # stale or unreleased pin without a network, that one catches a pin whose tag exists nowhere a
  # stranger can reach. A green here is evidence about your checkout, not about the internet.
  newest_tag=$(git tag -l 'v*' --sort=-v:refname 2>/dev/null | head -1)
  pins=""
  for f in README.md docs/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r pv; do
      [ -n "$pv" ] || continue
      [ -n "$newest_tag" ] || continue
      if ! git rev-parse -q --verify "refs/tags/v$pv" >/dev/null 2>&1; then
        pins="$pins\n  $f pins v$pv, which is not a tag in this repository (the URL 404s)"
      elif [ "v$pv" != "$newest_tag" ]; then
        pins="$pins\n  $f pins v$pv, but the newest release is $newest_tag"
      fi
    done <<PINEOF
$(grep -oE '(vstack/v|VSTACK_REF=v)[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null | sed -E 's/.*v//' | sort -u)
PINEOF
  done

  if [ -n "$pins" ]; then
    bad "declared version matches what installs" \
        "$(printf 'the manifests declare v%s, but the docs hand strangers a different release:%b' "$mv_" "$pins")"
  elif [ -z "$mv_" ]; then
    bad "declared version matches what installs" "could not read the version from the plugin manifest"
  elif [ -z "$(git tag -l 2>/dev/null | head -1)" ]; then
    # No tags at all means a shallow or tagless checkout, not a repo with no releases. Saying
    # "ok" there would make this check green on CI while measuring nothing — which is the exact
    # failure mode it was written to prevent, reproduced inside itself.
    skip "declared version matches what installs" "no tags in this checkout (shallow clone?), so there is nothing to compare against"
  elif ! git rev-parse -q --verify "refs/tags/v$mv_" >/dev/null 2>&1; then
    # A declared-but-untagged version has no payload to diff against, so this branch compares
    # nothing. It used to print "ok", which is the same defect the tagless branch above guards
    # against, one elif lower down: a green that measured nothing, hidden from the skip census
    # because only skips are counted there. Say skip, and the release unit has to tag before the
    # check starts measuring again.
    skip "declared version matches what installs" "v$mv_ is declared by the manifests but not tagged, so there is no payload to compare it against — tag the release and this starts measuring"
  else
    # Everything a lane actually delivers. Docs, tests and CI are deliberately excluded: they
    # change without changing what a stranger receives.
    PAYLOAD="claude/ mcp/ bin/ shell/ conductor/ install.sh bootstrap.sh overlay.sh uninstall.sh setup-machine.sh"
    # shellcheck disable=SC2086  # PAYLOAD is a deliberate word list of pathspecs, not one path
    drift=$(git diff --name-only "v$mv_..HEAD" -- $PAYLOAD 2>/dev/null)
    # The working tree too, not only HEAD. This compared v$mv_..HEAD and nothing else, so before
    # a commit HEAD *was* the tag, the diff was empty, and it printed ok while three modified
    # payload files sat in the working tree. After the commit, same file contents, it went red.
    # Nothing about the artefact changed between those two runs -- only which side of the commit
    # boundary the person stood on. A green whose truth value depends on when you ask is worse
    # than one that is simply wrong, because it is reproducible in both directions on demand,
    # and it becomes able to fail only once it is too late to act on.
    #
    # Staged, unstaged and untracked payload all count, since all three are things a stranger
    # would receive and the tag does not describe. A `git stash` still hides them; that is stated
    # in the ok line rather than solved, because the only honest fix for "somebody hid the
    # evidence" is to say what was looked at.
    # shellcheck disable=SC2086  # same deliberate word list
    wt=$(git status --porcelain -- $PAYLOAD 2>/dev/null | sed 's/^...//')
    if [ -n "$wt" ]; then
      drift=$(printf '%s\n%s' "$drift" "$wt" | grep -v '^$' | sort -u)
    fi
    # How much history actually separates the tag from HEAD. When a tag is cut at HEAD -- exactly
    # what release day does -- this is 0, `git diff v$mv_..HEAD` is empty by construction because
    # the *range* is empty, and the old "ok" line below read as a verified match over a comparison
    # that never happened. Computed unconditionally and reported in whichever line fires, so a
    # reader never has to re-derive it, and used to choose which sentence is honest: a real range
    # names how many commits it looked across, a zero-commit range names that it looked at none.
    chk24_range_size=$(git rev-list --count "v$mv_..HEAD" 2>/dev/null)
    case "$chk24_range_size" in (''|*[!0-9]*) chk24_range_size=0 ;; esac
    if [ -n "$drift" ]; then
      # The working-tree lane still bites here even when the range above is 0 -- a tag cut at
      # HEAD with a dirty payload afterward is drift $wt puts into $drift, and this branch is
      # reached before the zero-range branch below ever gets a look.
      bad "declared version matches what installs" \
          "$(printf 'the manifests say v%s but the payload has moved since that tag:\n%s\nbump the version and changelog it, or the plugin and unpinned lanes ship something v%s never described' "$mv_" "$(printf '%s' "$drift" | sed 's/^/  /' | head -10)" "$mv_")"
    elif [ "$chk24_range_size" -eq 0 ]; then
      ok "declared version matches what installs (v$mv_ is HEAD; 0 commits since the tag, so there was nothing to compare -- this becomes a measurement the moment the payload moves)"
    else
      ok "declared version matches what installs (v$mv_, HEAD and working tree; $chk24_range_size commit(s) since the tag touched no payload path; the tag is local -- this does not check any remote)"
    fi
  fi
else
  skip "declared version matches what installs" "git or jq not installed"
fi

# --- 25. the failure tail does not carry credentials back into the transcript ------------------
#
# PostToolUseFailure re-injects the tail of a failed command as context, so anything the command
# printed is preserved in the conversation for good. The redactor guarding that path caught one
# of seven real credential shapes when it was measured: it knew `NAME=value` and a list of token
# prefixes, and JSON, YAML, HTTP headers and URL userinfo -- the formats a failing command is
# most likely to emit -- all went through verbatim. Nothing could see that, because no check ever
# fed it a secret. This one does, through the real hook rather than the regex in isolation.
if command -v jq >/dev/null; then
  fd="claude/hooks/failure-diagnose.sh"
  if [ ! -x "$fd" ]; then
    bad "failure tail redacts credentials" "$fd is missing or not executable"
  else
    # Each line pairs a realistic payload with the substring that must not survive it.
    leaks=""
    while IFS='|' read -r payload secret; do
      [ -n "$payload" ] || continue
      out=$(printf '%s' "$(jq -cn --arg e "$payload" '{tool_name:"Bash",tool_response:{stderr:$e}}')" \
            | "$fd" 2>/dev/null)
      case "$out" in *"$secret"*) leaks="$leaks\n  survived: $payload" ;; esac
    done <<'REDEOF'
export ANTHROPIC_API_KEY=sk-ant-FAKEVAL|sk-ant-FAKEVAL
{"api_key": "abcd1234efgh5678"}|abcd1234efgh5678
{"apiKey":"abcd1234efgh5678","port":3000}|abcd1234efgh5678
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.PAYLOAD1234.SIGNATURE|PAYLOAD1234
curl -H 'x-api-key: abcd1234efgh5678'|abcd1234efgh5678
password: hunter2correcthorse|hunter2correcthorse
aws_secret_access_key = wJalrXUtnFEMIK7MDENGbPxRfiCY|wJalrXUtnFEMIK7MDENGbPxRfiCY
DATABASE_URL=postgres://user:s3cr3tpw@host/db|s3cr3tpw
GITHUB_TOKEN=ghp_FAKEVAL|ghp_FAKEVAL
REDEOF

    # The other half of the claim, and the half that actually broke. Redaction that eats ordinary
    # diagnostics is its own defect, because the tail exists to be read. One control line was not
    # enough: with only "cannot find module" here, a redactor that matched on the NAME alone
    # passed this check while turning the session digest "TOKENS: never read whole files" into
    # "TOKENS: [REDACTED] read whole files". Every line below contains a credential-shaped word
    # followed by a colon and ordinary prose, which is the case that was missed.
    while IFS= read -r ctl; do
      [ -n "$ctl" ] || continue
      cout=$(printf '%s' "$(jq -cn --arg e "$ctl" '{tool_name:"Bash",tool_response:{stderr:$e}}')" \
             | "$fd" 2>/dev/null)
      case "$cout" in
        *"$ctl"*) ;;
        *) leaks="$leaks\n  over-redacted an ordinary line: $ctl" ;;
      esac
    done <<'CTLEOF'
error: cannot find module at /usr/local/lib/thing.js (exit 2)
TOKENS: never read whole files, use grep
Keystrokes: 1420 recorded
passwords: are stored hashed in this table
npm ERR! code ELIFECYCLE, exit status 1
CTLEOF

    [ -z "$leaks" ] \
      && ok "failure tail redacts credentials (9 shapes masked, plain errors intact)" \
      || bad "failure tail redacts credentials" \
             "$(printf 'these reach the transcript verbatim:%b' "$leaks")"
  fi
else
  skip "failure tail redacts credentials" "jq not installed"
fi

# --- 26. the platforms the docs claim are the platforms CI actually runs -----------------------
#
# The README described a Windows lane in three places while the Windows job was failing, and
# nothing connected the two. Support is a claim about what is tested, so the runner names in the
# workflow and the runner names in the README have to be the same set, in both directions: a
# platform CI stopped running must leave the docs, and a platform CI starts running should enter
# them rather than being supported in silence.
if [ -f .github/workflows/verify.yml ]; then
  ci_runners=$(grep -oE '(runs-on|container): *[A-Za-z0-9:._-]+' .github/workflows/verify.yml \
    | sed -E 's/^(runs-on|container): *//' | sort -u)
  doc_runners=$(grep -ohE '\b(ubuntu|macos|windows|alpine)[:-][A-Za-z0-9.]+' README.md | sort -u)
  errs=""
  for r in $ci_runners; do
    printf '%s\n' "$doc_runners" | grep -qxF "$r" \
      || errs="$errs\n  CI runs $r, the README never names it"
  done
  for r in $doc_runners; do
    printf '%s\n' "$ci_runners" | grep -qxF "$r" \
      || errs="$errs\n  the README names $r, no CI job runs it"
  done
  [ -z "$errs" ] \
    && ok "documented platforms match CI ($(printf '%s' "$ci_runners" | tr '\n' ' '))" \
    || bad "documented platforms match CI" "$(printf 'support is a claim about what is tested:%b' "$errs")"
else
  # Not a skip. The workflow is a tracked file in this repository, not a dependency that may or
  # may not exist on a runner, so its absence does not mean "cannot measure here" -- it means CI
  # is gone and the README's platform claim has no evidence behind it at all. Nothing else
  # asserts the workflow exists; check 31 excludes .github/. A skip here reported the strongest
  # possible version of the failure as an absence of information.
  bad "documented platforms match CI" \
      ".github/workflows/verify.yml is missing, so the platforms the README promises are tested by nothing"
fi

# --- 27. the skill mandate blocks on an unmet rule and stays quiet otherwise -------------------
#
# The digest tells the model to route to a skill and the descriptions carry their own triggers.
# Both are instructions, and an instruction is a probability -- auto-trigger.sh measures the
# routing landing, not the routing being certain. This hook is the part that is certain, for the
# few rules decidable from tool calls rather than judgement, so it has to be exercised in both
# directions. A gate that never blocks and a gate that always blocks look identical from a
# passing test that only checks one of them.
if command -v jq >/dev/null; then
  sm="claude/hooks/skill-mandate.sh"
  if [ ! -x "$sm" ]; then
    bad "skill mandate decides correctly" "$sm is missing or not executable"
  elif [ ! -f tests/mandate-cases.sh ]; then
    bad "skill mandate decides correctly" \
        "tests/mandate-cases.sh is missing -- this check and tests/container-matrix.sh share their fixtures from there, so neither can drift from the other"
  else
    # tests/mandate-cases.sh is the ONE fixture set for this hook, shared with
    # tests/container-matrix.sh (installed hook, inside containers, release.yml only). It was
    # two independent, drifted fixture sets before this: this check's own 17 offline cases never
    # covered prove-it-works or conversational-silence, container-matrix.sh's 7 never covered
    # unslop or typescript-best-practices, and a v1.57.0 hook change updated one and not the
    # other -- the first signal was a failed release that deleted its own tag from origin. See
    # tests/mandate-cases.sh's own header for the full case-by-case provenance and the flag
    # vocabulary (STOP_ACTIVE / NO_MANDATE / PRIME2) implemented below.
    # shellcheck source=tests/mandate-cases.sh
    . tests/mandate-cases.sh
    md=$(mktemp -d); errs=""
    # VSTACK_NO_DELEGATION_LOG=1: every invocation below feeds the hook a synthetic fixture
    # transcript under a "vfy-*" session id, not a real session. Without this, each gate run
    # appends synthetic lines to the operator's real ~/.claude/vstack-delegation-log.jsonl (one
    # per case that reaches the logger before stop_hook_active/VSTACK_NO_MANDATE/the 2-strike
    # latch short-circuits it) -- the exact vfy-* contamination found predating any instrumented
    # run of this suite.
    _mc_has_flag() { case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
    _mc_call() { # <session-id> <stop_hook_active> <env-prefix-or-empty>
      printf '{"session_id":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":%s}' "$1" "$md" "$2" \
        | VSTACK_NO_DELEGATION_LOG=1 env $3 "./$sm" 2>/dev/null
    }
    n_cases=0
    for cid in $MANDATE_CASE_IDS; do
      n_cases=$((n_cases + 1))
      sid="vfy-$cid"
      mandate_case_lines "$cid" > "$md/t.jsonl"
      flags=$(mandate_case_flags "$cid")
      sha=false
      _mc_has_flag "$flags" STOP_ACTIVE && sha=true
      envp=""
      _mc_has_flag "$flags" NO_MANDATE && envp="VSTACK_NO_MANDATE=1"
      if _mc_has_flag "$flags" PRIME2; then
        # Two priming calls on the SAME session id, discarded, so the per-mandate strike
        # counter this case is testing reaches 2 before the judged call below reads it back.
        _mc_call "$sid" "$sha" "$envp" >/dev/null
        _mc_call "$sid" "$sha" "$envp" >/dev/null
      fi
      out=$(_mc_call "$sid" "$sha" "$envp")
      detail=$(mandate_case_judge "$cid" "$out")
      if [ $? -ne 0 ]; then
        errs="$errs\n  $detail"
      fi
    done

    # "*vfy-[a-q19]*" not "vfy-*": the mandate latch split (f4f5468) inserts "ckpt-" between the
    # "vstack-mandate-" anchor and the session id, and the delegation-family counters append
    # ".delegate"/".delegate-ts"/".delegate-scan"/".lock" after it -- a bare "vfy-*" anchor
    # matches none of the ckpt files and missed every one of them (verified: 12 stale
    # vstack-mandate-ckpt-vfy-* sat in $TMPDIR across runs of this gate before this fix).
    # Anchored on both ends the way 76d2366 fixed the identical bug in
    # tests/test-breadth-mandate.sh. The character class covers every MANDATE_CASE_IDS first
    # character: the 17 single-letter ids a-q, plus "9b" and "10"/"11"/"12" (first chars 9 and
    # 1) added when this check and tests/container-matrix.sh were unified onto one fixture set
    # -- so this still cannot reach a file this check did not create.
    rm -rf "$md"; rm -f "${TMPDIR:-/tmp}"/vstack-mandate-*vfy-[a-q19]* 2>/dev/null
    [ -z "$errs" ] \
      && ok "skill mandate decides correctly ($n_cases cases, shared with tests/container-matrix.sh via tests/mandate-cases.sh)" \
      || bad "skill mandate decides correctly" "$(printf '%b' "$errs")"
  fi
else
  skip "skill mandate decides correctly" "jq not installed"
fi

# --- 28. every doc is reachable from another doc ----------------------------------------------
#
# A file nobody links to is a file nobody reads and nobody updates, and it rots in public. A
# 783-line research handoff landed in docs/ and was reachable from nothing: not the README index,
# not another document. It read as deleted while still being served to anyone browsing the repo.
#
# The rule is reachability, not a fixed index: a doc linked from another doc is fine. What is not
# fine is a doc no path in the repository leads to.
docs_all=$(find docs -name '*.md' 2>/dev/null | sort)
if [ -z "$docs_all" ]; then
  # Not a skip, for the same reason: docs/ is tracked. Its absence silently retires three
  # assertions at once -- this one, and two rows inside check 12 that are guarded on files under
  # it -- and reports that as nothing to see.
  bad "every doc is reachable" "there is no docs/ directory, so this and two rows of check 12 are asserting nothing"
else
  # Written to a file and grepped directly. `printf ... | grep -q` returns 141 under pipefail
  # when grep exits early on a match, so every doc that WAS linked reported as an orphan -- the
  # same pipe-and-exit-status trap that has bitten this repository twice before.
  linkable=$(mktemp)
  find docs -name '*.md' -exec cat {} + > "$linkable" 2>/dev/null
  cat README.md CHANGELOG.md claude/skills/*/SKILL.md >> "$linkable" 2>/dev/null
  orphans=""
  for d in $docs_all; do
    base=${d##*/}
    # Either the repo-relative path or the bare filename, since docs link to each other by
    # sibling name.
    dir=${d%/*}
    # A link to the containing directory counts. docs/provenance/README.md points at `plans/`
    # rather than naming each plan, and a reader following it lands on all three -- that is
    # reachable, and demanding a per-file link would only produce an index nobody maintains.
    if ! grep -qF "$d" "$linkable" \
       && ! grep -qF "]($base" "$linkable" \
       && ! grep -qE "\]\((\./)?${dir##*/}/\)" "$linkable"; then
      orphans="$orphans\n  $d"
    fi
  done
  rm -f "$linkable"
  [ -z "$orphans" ] \
    && ok "every doc is reachable ($(printf '%s' "$docs_all" | wc -l | tr -d ' ') under docs/)" \
    || bad "every doc is reachable" "$(printf 'nothing in this repository links to:%b' "$orphans")"
fi

# --- 29. every shell script passes shellcheck ------------------------------------------------
#
# This bundle is shell scripts and almost nothing else, and the whole product is the claim
# that they behave correctly on someone else's machine. The class of bug that keeps landing here
# is not exotic -- an unquoted expansion, a pattern that can never match, a variable set for a
# check nobody wrote -- and a linter finds all three for free.
#
# Warning level, not style: informational notes are opinions and this should fail on defects.
# Where a warning is wrong the suppression carries a reason, which check 30 enforces.
#
# Selected by shebang, the same way check 1 selects. It used to be the hand-maintained list
# `git ls-files '*.sh' bin/doctor bin/vstack`, and bin/cloudflare-mcp -- a #!/bin/sh script with
# no .sh suffix -- had never been on it. Appending an unquoted `$HOME/some path` to that file
# left shellcheck exiting 1 on it while this check still printed "ok shellcheck clean (29
# scripts)". A list you have to remember to update is a list that goes stale silently.
if command -v shellcheck >/dev/null 2>&1; then
  sc_files=$(sh_files)
  # Read the delegate, do not infer from its silence. This ran `shellcheck ... 2>/dev/null`
  # inside a command substitution: stderr discarded, exit status never read. `shellcheck -S
  # nonsense -f gcc install.sh` writes nothing to stdout and exits 4, so a shellcheck that could
  # not run at all printed "ok shellcheck clean (33 scripts)". That is the same shape as the
  # count check whose extractor silently stopped matching, and it is why scan() above reads rc.
  # Exit-status contract: 0 clean, 1 findings, 2 bad input, 3 bad syntax, 4 bad usage. Only
  # the first two are answers; the rest mean the question was never asked.
  sc_out=""; sc_err=""
  # One shellcheck process for every file in the set, not one process per file: shellcheck
  # keeps scanning past a file it cannot open and reports the rest (verified by hand: two
  # missing files in one invocation each print their own "openBinaryFile" line with their own
  # path), and the batch's exit code is 2 whenever any file could not be opened, same as that
  # file alone would report -- a file with unparseable shell syntax still exits 1 (SC1xxx is a
  # finding, not an IO failure), so a batch rc of 0 or 1 answers for every file in it exactly as
  # the old per-file loop did. Only when the batch itself could not answer (rc>=2) does this fall
  # back to the original one-process-per-file loop, so the failure line still names the specific
  # file and its own rc instead of trusting shellcheck's freeform IO-error text to embed the path.
  sc_arr=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sc_arr+=("$f")
  done <<<"$sc_files"
  if [ "${#sc_arr[@]}" -gt 0 ]; then
    _bout=$(shellcheck -S warning -f gcc "${sc_arr[@]}" 2>/dev/null); _brc=$?
  else
    _bout=""; _brc=0
  fi
  case "$_brc" in
    0|1) sc_out="$_bout" ;;
    *)
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        _o=$(shellcheck -S warning -f gcc "$f" 2>/tmp/sc_err.$$); _rc=$?
        case "$_rc" in
          0|1) [ -n "$_o" ] && sc_out="$sc_out$_o
" ;;
          *)   sc_err="$sc_err\n  $f: shellcheck exited $_rc: $(head -1 /tmp/sc_err.$$)" ;;
        esac
      done <<<"$sc_files"
      rm -f /tmp/sc_err.$$
      ;;
  esac
  # Positive control, the same two-way shape check 19 uses: a linter that reports nothing is
  # only good news if it can still report something. Without this, disabling the tool and
  # deleting every defect are indistinguishable from here.
  _ctl=$(printf '#!/bin/bash\nx=$HOME/a b\nls $x\n' | shellcheck -S warning -f gcc - 2>/dev/null)
  [ -n "$_ctl" ] || sc_err="$sc_err\n  positive control: shellcheck found nothing wrong with a known-bad script, so a clean result here means nothing"
  [ -n "$sc_err" ] && sc_out="$sc_out$(printf '%b' "$sc_err")"
  [ -z "$sc_out" ] \
    && ok "shellcheck clean ($(grep -c . <<<"$sc_files") scripts, warning level)" \
    || bad "shellcheck clean" "$(printf '%s' "$sc_out" | sed 's/^/  /' | head -20)"
else
  skip "shellcheck clean" "shellcheck not installed (brew install shellcheck / apk add shellcheck)"
fi

# --- 30. every shellcheck suppression carries a reason ----------------------------------------
#
# Check 29's own header has said for several versions that a suppression carries its reason with
# it, so the next reader sees the argument rather than a bare disable. Nothing enforced it, and
# bootstrap.sh had carried a naked `# shellcheck disable=SC2086` since the lane was written. A
# rule that lives only in prose is a rule that gets skipped by whoever did not read the prose,
# which is the second time that has happened here -- the documented-count rule was the first.
#
# A reason counts if it is on the same line after the code list, which is how all seven
# suppressions in this repo are written, or on the line immediately above. Both are readable at
# the point of the disable; a reason three lines away is not.
bare=""
nsup=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    n=${hit%%:*}
    nsup=$((nsup + 1))
    line=$(sed -n "${n}p" "$f")
    # whatever follows the comma-separated code list on the same line
    tail_=$(sed -E 's/.*shellcheck[[:space:]]+disable=[A-Za-z0-9,]+//' <<<"$line")
    above=$(sed -n "$((n - 1))p" "$f")
    if ! grep -qE '[A-Za-z]{3}' <<<"$tail_" && ! grep -qE '^[[:space:]]*#.*[A-Za-z]{3}' <<<"$above"; then
      bare="$bare\n  $f:$n"
    fi
    # A directive shellcheck honours is always its own comment line, so anchor on that. Matching
    # the bare phrase also picked up this file's own prose about the rule and the mutation
    # payload in tests/gate-falsifiability.sh, and reported 9 suppressions where there are 7.
  done <<<"$(grep -nE '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+disable=' "$f" 2>/dev/null)"
done <<<"$(sh_files)"
[ -z "$bare" ] \
  && ok "shellcheck suppressions carry a reason ($nsup suppressions)" \
  || bad "shellcheck suppressions carry a reason" \
         "$(printf 'a bare disable hides the argument from the next reader:%b' "$bare")"

# --- 31. every shipped file has a referrer -----------------------------------------------------
#
# Check 28 does this for docs/, where a link to the containing directory counts. Everything else
# in the tree had no such rule, and two files had been riding along for versions: a launchd
# wrapper around the doctor that install.sh never installs and uninstall.sh never removes, and an
# eval-loop driver nothing but its own header mentioned. Neither was reachable and neither was
# visible to any check. They are not named here on purpose -- a basename in this comment is a
# referrer as far as the grep below is concerned, which is exactly how the first draft of this
# check passed over both of them.
#
# The limit, stated rather than hidden: a mention in prose counts. This finds files nothing points
# at, not files pointed at only rhetorically.
#
# Skills, agents, commands and everything under .github/ are excluded because their loader finds
# them by path convention: GitHub reads PULL_REQUEST_TEMPLATE.md, dependabot.yml, CODEOWNERS and
# the issue templates from fixed locations, so a referrer would be redundant there rather than
# missing. docs/ is excluded because check 28 owns it with directory-link semantics this basename
# match cannot express.
unref=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    claude/skills/*|claude/agents/*|claude/commands/*|.github/*|docs/*) continue ;;
    # Eval corpora, loaded by directory the same way skills are: the harness points FIX at the
    # directory and globs it (run-pathways.sh:42), so naming each fixture individually somewhere
    # would be redundant rather than informative. Adding a fixture is meant to be a file drop.
    tests/evals/fixtures/*|tests/evals/holdout/*|tests/evals/*/fixture/*) continue ;;
    # showcase/run.sh globs its trap fixtures the same way (traps/*/PROMPT.txt), so the same rule.
    tests/evals/showcase/traps/*) continue ;;
  esac
  # Matched on the path, not the basename. A basename match means every README.md in the tree is
  # "referenced" by any mention of any README.md, and a subtree that names only itself passes as
  # a group: ui-gate/ -- shipped as the fix for the fifth fake green -- was named by nothing
  # outside itself, was not linted, was not parsed, was not run by CI, and this check was green.
  [ -n "$(git grep -l -F -- "$f" -- . ":(exclude)$f" 2>/dev/null | head -1)" ] \
    || unref="$unref\n  $f"
done <<<"$(git ls-files 2>/dev/null)"
[ -z "$unref" ] \
  && ok "every shipped file has a referrer ($(git ls-files | grep -cvE '^(claude/(skills|agents|commands)/|\.github/|docs/)') outside the load-by-directory trees)" \
  || bad "every shipped file has a referrer" \
         "$(printf 'nothing in this repository names:%b\n  delete it, or give it a referrer -- a file nobody can find is a file nobody maintains' "$unref")"

# --- 32. the grill trigger decides correctly ---------------------------------------------------
#
# Same shape as checks 23 and 27: a hook that decides is tested on its decisions, in both
# directions. A trigger that always fires is a trigger nobody keeps, and one that never fires is
# indistinguishable from not having written it. The threshold cases are the ones worth pinning,
# because they are the ones a future edit moves by accident.
g_errs=""
g_dir="${TMPDIR:-/tmp}/vstack-grill-verify.$$"
g_ask(){ # session, prompt -> 1 if the grill line was injected
  TMPDIR="$g_dir" VSTACK_NO_GRILL="${VSTACK_NO_GRILL:-0}" \
    printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":"%s"}' "$1" "$2" \
    | TMPDIR="$g_dir" ./claude/hooks/inject-session-context.sh 2>/dev/null \
    | grep -c 'GRILL: run the grill-me skill'
}
g_want(){ # session, prompt, expected, label
  got=$(g_ask "$1" "$2")
  [ "$got" = "$3" ] || g_errs="$g_errs\n  $4: got $got, want $3"
}
if command -v jq >/dev/null 2>&1 && [ -x claude/hooks/inject-session-context.sh ]; then
  mkdir -p "$g_dir"
  # Built to length rather than written and hoped over. The first draft of these fixtures came in
  # at 120 and 169 characters against thresholds of 120 and 320, so the long case was not long and
  # the boundary case sat exactly on the line -- the check reported two failures that were its own.
  g_short="fix the typo"
  g_med=$(printf 'refactor the auth middleware %.0s' 1 2 3 4 5)
  g_long=$(printf 'rebuild the billing pipeline with retries and idempotency %.0s' 1 2 3 4 5 6)
  [ "${#g_short}" -lt 120 ] && [ "${#g_med}" -ge 120 ] && [ "${#g_med}" -lt 320 ] \
    && [ "${#g_long}" -ge 320 ] \
    || g_errs="$g_errs\n  the fixtures do not straddle the thresholds they are testing (short=${#g_short} med=${#g_med} long=${#g_long})"
  g_want gv1 "$g_short" 0 "a short first prompt must not open an interview"
  g_want gv2 "$g_med"   1 "a substantive first prompt gets grilled"
  g_want gv2 "$g_med"   0 "the same prompt later in the session is under the long threshold"
  g_want gv2 "$g_long"  1 "any prompt long enough to be a plan gets grilled"
  # Captured, not piped. Every other `| grep -q` in this file fails in the safe direction -- a
  # 141 reads as "no match" and invents a failure somebody will investigate. This one was the
  # exception: 141 on a match would skip the `&&` and report a broken VSTACK_NO_GRILL as green.
  # The payload is one short line so it never fired in practice, which is exactly why it would
  # have survived until the payload grew.
  _esc=$( export VSTACK_NO_GRILL=1
          got=$(g_ask gv3 "$g_long")
          [ "$got" = 0 ] || printf 'ESCAPE_FAILED\n' )
  grep -q ESCAPE_FAILED <<<"$_esc" \
    && g_errs="$g_errs\n  VSTACK_NO_GRILL=1 did not turn it off"
  # The digest runs on every prompt and has a byte cap of its own (check 18). Measure the fired
  # form too: the unfired one is what check 18 probes, so a grill line that blew the budget
  # would never have been seen by it.
  # The worst case, not a convenient one: every optional line on at once. Check 18 probes the
  # unfired digest and would never see this, and the two add-ons were measured separately at 312
  # and 386 against a 512 cap -- separately fine, together 476, which is a budget nobody was
  # watching.
  # "Every option on" needs the mandate strike too, and that reads a counter file keyed by the
  # session id; without it this probe measured the grill line alone and called it the worst case.
  printf '1' > "$g_dir/vstack-mandate-gv4.unslop"
  g_sz=$(TMPDIR="$g_dir" VSTACK_TERSE=1 \
         sh -c 'printf "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"gv4\",\"prompt\":\"$1\"}"' _ "$g_long" \
         | TMPDIR="$g_dir" VSTACK_TERSE=1 ./claude/hooks/inject-session-context.sh 2>/dev/null \
         | jq -r '.hookSpecificOutput.additionalContext // ""' | wc -c | tr -d ' ')
  [ "${g_sz:-0}" -le 512 ] || g_errs="$g_errs\n  the fired digest with every option on is $g_sz bytes, over the 512 cap"
  rm -rf "$g_dir"
  [ -z "$g_errs" ] \
    && ok "grill trigger decides correctly (5 cases, both directions, worst-case digest $g_sz B of 512)" \
    || bad "grill trigger decides correctly" "$(printf '%b' "$g_errs")"
else
  skip "grill trigger decides correctly" "jq missing or the session-context hook is not executable"
fi

# --- 33. the project overlay stands down when the user-scope hook is live ----------------------
#
# Claude Code merges hook arrays across settings layers rather than overriding them, so an
# overlaid repo ran ~/.claude's injector and its own committed copy: everything twice, every turn.
# The copy under a repo's .claude/ now suppresses itself when the user-scope one is registered.
#
# Tested in both directions and then some, because every way this can be wrong is silent. Testing
# only that the project copy goes quiet would rate a script broken end to end as healthy; testing
# only that the source copy still speaks would miss the duplication entirely. The sandbox case
# below is the one that matters most in production: a cloud sandbox has no ~/.claude, and if the
# suppression fires there the repo loses its only config lane and nobody sees an error.
d_errs=""
if command -v jq >/dev/null 2>&1 && [ -x claude/hooks/inject-session-context.sh ]; then
  d_root=$(mktemp -d)
  mkdir -p "$d_root/repo/.claude/hooks" "$d_root/withglobal/.claude/hooks" "$d_root/noglobal"
  cp claude/hooks/inject-session-context.sh "$d_root/repo/.claude/hooks/"
  cp claude/hooks/inject-session-context.sh "$d_root/withglobal/.claude/hooks/"
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"%s/.claude/hooks/inject-session-context.sh"}]}]}}' \
    "$d_root/withglobal" > "$d_root/withglobal/.claude/settings.json"
  # The prompt is long on purpose. This probe reads "did the copy speak" as "is there an
  # additionalContext key", and the per-prompt digest is conditional-only now (grill + mandate,
  # nothing unconditional) -- so a one-character prompt makes a perfectly healthy copy emit no
  # additionalContext, and all three must-speak cases read 0. A prompt over the hook's 320-char
  # grill threshold puts a line in the digest whenever the copy is speaking at all, which is the
  # signal this check has always meant to read. A suppressed copy still returns before the grill
  # branch, so the quiet direction is unchanged.
  d_prompt=$(awk 'BEGIN{s="";while(length(s)<400)s=s "rebuild the billing pipeline with retries and idempotency ";printf "%s", substr(s,1,400)}')
  d_ev=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"dv1","prompt":"%s"}' "$d_prompt")
  d_ask(){ # home, script -> 1 if any context was injected
    printf '%s' "$d_ev" | HOME="$1" "$2" 2>/dev/null | grep -c additionalContext
  }
  d_want(){ # home, script, expected, label
    got=$(d_ask "$1" "$2")
    [ "$got" = "$3" ] || d_errs="$d_errs\n  $4: got $got, want $3"
  }
  d_want "$d_root/withglobal" "$d_root/repo/.claude/hooks/inject-session-context.sh" 0 \
    "a repo copy must go quiet while the user-scope copy is registered"
  d_want "$d_root/noglobal" "$d_root/repo/.claude/hooks/inject-session-context.sh" 1 \
    "a repo copy in a sandbox with no ~/.claude is the only lane and must still speak"
  d_want "$d_root/withglobal" "$d_root/withglobal/.claude/hooks/inject-session-context.sh" 1 \
    "the user-scope copy must not suppress itself"
  d_want "$HOME" "./claude/hooks/inject-session-context.sh" 1 \
    "this repo's source copy at claude/hooks/ is not an overlay and must still speak"
  got=$(printf '%s' "$d_ev" | VSTACK_DUPE_SUPPRESS=0 HOME="$d_root/withglobal" \
        "$d_root/repo/.claude/hooks/inject-session-context.sh" 2>/dev/null | grep -c additionalContext)
  [ "$got" = 1 ] || d_errs="$d_errs\n  VSTACK_DUPE_SUPPRESS=0 did not turn the suppression off"
  # Silence still has to be well-formed. A hook that exits printing nothing is not "quiet", it is
  # a hook Claude Code logs as malformed on every single prompt.
  printf '%s' "$d_ev" | HOME="$d_root/withglobal" \
    "$d_root/repo/.claude/hooks/inject-session-context.sh" 2>/dev/null \
    | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
    || d_errs="$d_errs\n  the suppressed copy did not emit valid hook JSON"
  rm -rf "$d_root"
  [ -z "$d_errs" ] \
    && ok "project overlay stands down when the user-scope hook is live (6 cases, both directions)" \
    || bad "project overlay stands down when the user-scope hook is live" "$(printf '%b' "$d_errs")"
else
  skip "project overlay stands down when the user-scope hook is live" "jq missing or the session-context hook is not executable"
fi

# --- 34. the policy document reaches a session exactly once ------------------------------------
#
# It used to ship as a second CLAUDE.md committed into every overlaid repo. ~/.claude/CLAUDE.md
# holds the same bytes, .claude/CLAUDE.md is a project-memory path, and Claude Code loads both —
# so the entire policy document was in context twice, in seven repos, and no hook could intervene
# because the client reads both files itself.
#
# It now travels as .claude/hooks/policy.md, which nothing loads automatically, and the session
# hook speaks it only where it is the only voice. That makes "exactly once" a property worth
# asserting in both directions: zero copies in a sandbox is a repo that lost its operating policy
# silently, and two copies on this machine is the bug that started this.
o_errs=""
o_marker=$(head -1 claude/CLAUDE.md)
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && [ -n "$o_marker" ]; then
  o_tmp=$(mktemp -d)
  o_dir="$o_tmp/r"; mkdir -p "$o_dir"
  git -C "$o_dir" init -q 2>/dev/null
  # A repo overlaid before this change: the file the overlay now has to clear.
  mkdir -p "$o_dir/.claude"
  printf 'stale project memory\n' > "$o_dir/.claude/CLAUDE.md"
  ./overlay.sh "$o_dir" >/dev/null 2>&1

  [ -f "$o_dir/.claude/hooks/policy.md" ] \
    || o_errs="$o_errs\n  the overlay did not ship .claude/hooks/policy.md"
  cmp -s claude/CLAUDE.md "$o_dir/.claude/hooks/policy.md" 2>/dev/null \
    || o_errs="$o_errs\n  the shipped policy.md is not the policy document"
  [ -f "$o_dir/.claude/CLAUDE.md" ] \
    && o_errs="$o_errs\n  the overlay left a .claude/CLAUDE.md behind — the duplication survives a re-run"

  # Sandbox: no ~/.claude, so the overlay is the only lane and must carry the policy.
  #
  # Two ambient leaks made this scenario stop being a sandbox and start being "whichever shell
  # happened to run verify.sh":
  #
  # CONDUCTOR_WORKSPACE_PATH is set by the Conductor desktop app, which injects its own workspace
  # block and expects the hook to stand down (see the "workspace conventions" comment below in
  # inject-session-context.sh). A cloud sandbox is never Conductor-launched, so it never has this
  # var — but a developer measuring this check from inside a Conductor-launched terminal DOES,
  # which silently took the ~670-byte WORKSPACE CONVENTIONS block out of the count and made the
  # measurement pass on the author's machine while every plain terminal, CI runner and container
  # got the block and failed. Check 18's probe() already pins this same variable for the same
  # reason (`env CONDUCTOR_WORKSPACE_PATH="${3:-}"` a hundred lines up) — this scenario just never
  # got the same treatment when it was written a day later. Pinned to "" here, matching that
  # precedent: empty satisfies the hook's `[ -z ... ]` test the same as unset, so this always
  # measures the no-Conductor branch, which is what an actual sandbox is.
  #
  # CLAUDE_PROJECT_DIR (and $PWD, its fallback) is how the hook finds the repo root it should
  # describe. Never set here, the hook fell back to $PWD — which is wherever verify.sh itself was
  # invoked from, i.e. THIS checkout's own root and branch, not $o_dir's. The "sandbox" was
  # measuring the developer's real clone path and branch name, not the synthetic repo the check
  # built to stand in for one. Pinned to "$o_dir" so the block it measures actually describes the
  # sandbox under test.
  o_home="$o_tmp/empty"; mkdir -p "$o_home"
  o_out=$(printf '{"hook_event_name":"SessionStart"}' \
          | env CONDUCTOR_WORKSPACE_PATH="" CLAUDE_PROJECT_DIR="$o_dir" HOME="$o_home" \
            "$o_dir/.claude/hooks/inject-session-context.sh" 2>/dev/null \
          | jq -r '.hookSpecificOutput.additionalContext // ""')
  case "$o_out" in
    *"$o_marker"*) ;;
    *) o_errs="$o_errs\n  a sandbox session got no policy at all — the overlay is its only lane" ;;
  esac
  # Every byte is paid on every session there, and check 18 cannot see this variant because it
  # probes the source copy, which is not an overlay and never appends the policy.
  #
  # 8704 (8.5 KiB). The previous cap was 7168, fitted to a 6886 B reading on macOS (the longest
  # $TMPDIR: /private/var/folders/.../T/tmp.XXXXXXXXXX) against 6754-6784 B in debian, alpine and
  # ubuntu containers (short /tmp/tmp.XXXXXXXXXX, and init.defaultBranch varies main/master by
  # 2 bytes) -- ~130 B of tmpdir-naming noise, the same machine-to-machine drift check 18
  # documents in its own README tolerance. That cap claimed ~280 B of headroom, "room for a
  # sentence added on purpose, not for a block that ran away".
  #
  # Measured at v1.56.0: 7167 B against the 7168 cap. ONE byte. All 280 of those bytes had been
  # spent across intervening releases and this gate said nothing, because a threshold reports the
  # same ok at 1 byte of margin as at 280 -- it can only speak once the margin is already gone,
  # which is exactly when saying so stops being useful. So the headroom is now printed on every
  # run (see the ok line below). Erosion becomes visible while it is happening rather than as a
  # failure in whichever release finally crosses the line.
  #
  # 8704 carries the two dispatch rules added to the policy document in 1.57.0 (FAN OUT THROUGH
  # swarm, ISOLATE THE WRITERS, +825 B after compression) with ~625 B left. A deliberate spend,
  # not an accommodation: these bytes are paid on every session in every overlaid repo, and the
  # number to watch is the headroom in the ok line, not this constant.
  o_cap=8704
  o_sz=$(printf '%s' "$o_out" | wc -c | tr -d ' ')
  [ "${o_sz:-0}" -le "$o_cap" ] \
    || o_errs="$o_errs\n  the sandbox session block is $o_sz bytes, over the $o_cap cap (every byte is paid on every session in every overlaid repo)"

  # This machine: ~/.claude/CLAUDE.md carries the policy, so the overlay must not add a second.
  o_gh="$o_tmp/withglobal"; mkdir -p "$o_gh/.claude/hooks"
  cp claude/hooks/inject-session-context.sh "$o_gh/.claude/hooks/"
  printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"x/inject-session-context.sh"}]}]}}' \
    > "$o_gh/.claude/settings.json"
  o_dbl=$(printf '{"hook_event_name":"SessionStart"}' \
          | VSTACK_DUPE_SUPPRESS=0 HOME="$o_gh" "$o_dir/.claude/hooks/inject-session-context.sh" 2>/dev/null \
          | grep -c "$o_marker")
  # Asserted with the suppression switched OFF on purpose. The escape hatch exists to restore the
  # digest for debugging; if it also reintroduced a second policy it would hand back the original
  # bug to anyone who used it.
  [ "$o_dbl" = 0 ] \
    || o_errs="$o_errs\n  the overlay spoke the policy while ~/.claude/CLAUDE.md also holds it"
  # The user-scope copy must never append it either, or every non-overlaid repo doubles instead.
  o_src=$(printf '{"hook_event_name":"SessionStart"}' \
          | ./claude/hooks/inject-session-context.sh 2>/dev/null | grep -c "$o_marker")
  [ "$o_src" = 0 ] \
    || o_errs="$o_errs\n  the source copy appended the policy; only an overlay may carry it"

  rm -rf "$o_tmp"
  [ -z "$o_errs" ] \
    && ok "the policy document reaches a session exactly once (sandbox $o_sz B, $((o_cap - o_sz)) B headroom, 6 cases)" \
    || bad "the policy document reaches a session exactly once" "$(printf '%b' "$o_errs")"
else
  skip "the policy document reaches a session exactly once" "jq or git missing, or the policy document is empty"
fi

# --- 35. a gate that measured nothing does not report success ----------------------------------
#
# Three tools in this repository print declared/ran/skipped accounting and then a verdict, and
# two of them used to pass at ran=0. ui-gate.sh printed "9 declared, 0 ran, 0 passed, 0 failed,
# 9 skipped" followed by "UI GATE OK" against any directory with no interface files in it, which
# is the exact defect its own header says the repository exists to catch. doctor --drift printed
# "no drift ✔" after four whole families of globs matched nothing, though the resolve-failure
# branch one layer up had already learned that nothing-compared is a failure.
#
# So this is not a one-off: it is the same reading twice, in two tools, one of which had already
# been fixed in one branch and not the others. Both directions are asserted, because a gate that
# always refuses is worth exactly as much as one that never does -- and the refusing direction is
# the one nobody would notice breaking.
g_errs=""
if [ -x ui-gate/ui-gate.sh ] && [ -x bin/doctor ]; then
  g_empty=$(mktemp -d)

  # ui-gate, negative: no interface files, so no rule can run.
  _o=$(./ui-gate/ui-gate.sh "$g_empty" 2>&1)
  grep -q 'UI GATE OK' <<<"$_o" \
    && g_errs="$g_errs\n  ui-gate reports OK over a target where no rule ran"
  grep -q 'UI GATE NOT RUN' <<<"$_o" \
    || g_errs="$g_errs\n  ui-gate does not say it never ran; it must name that case, not stay quiet"

  # ui-gate, positive: a fixture with real component and stylesheet files.
  mkdir -p "$g_empty/app/src"
  printf 'export const C = () => <div className="mt-4 p-4">x</div>;\n' > "$g_empty/app/src/C.tsx"
  printf '.a{font-size: 16px;}\n' > "$g_empty/app/src/a.css"
  _o=$(./ui-gate/ui-gate.sh "$g_empty/app" 2>&1)
  grep -q 'UI GATE OK' <<<"$_o" \
    || g_errs="$g_errs\n  ui-gate withholds OK from a fixture whose rules do run and hold"

  # doctor --drift, negative: a $REPO that resolves but ships no families at all.
  g_repo=$(mktemp -d); g_home=$(mktemp -d)
  mkdir -p "$g_repo"/claude/hooks "$g_repo"/claude/agents "$g_repo"/claude/commands \
           "$g_repo"/claude/skills "$g_repo"/bin "$g_home/.claude"
  cp claude/CLAUDE.md claude/statusline.sh claude/settings.json "$g_repo/claude/" 2>/dev/null
  cp claude/CLAUDE.md claude/statusline.sh "$g_home/.claude/" 2>/dev/null
  _o=$(env HOME="$g_home" VSTACK_DIR="$g_repo" ./bin/doctor --drift 2>&1); _rc=$?
  # Three assertions, not one. Requiring only the ABSENCE of "no drift" passes a doctor that
  # crashed before printing anything, or one that was never executable -- silence would read as
  # the floor working. The ui-gate probe above already demands its own positive marker
  # ("UI GATE NOT RUN"); this one did not, and that asymmetry is the hole.
  grep -q 'no drift' <<<"$_o" \
    && g_errs="$g_errs\n  doctor --drift reports no drift after comparing zero items per family"
  grep -q 'DRIFT' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift does not say DRIFT over empty families; it must name that case, not stay quiet (output: $(printf '%s' "$_o" | tr '\n' ' ' | cut -c1-120))"
  [ "$_rc" -ne 0 ] \
    || g_errs="$g_errs\n  doctor --drift exits 0 over empty families, so no caller scripting on its status can tell"

  # doctor --drift, positive: one member in every family, mirrored on both sides.
  # agents/reference/*.ref is its own drift family, so it needs its own member here. Leaving it
  # out is how 1.45.1 first went red: doctor grew a family, the stub did not, and the positive
  # control started failing for a tree that was in fact identical. The stub has to track the
  # families or it stops being a control and becomes a second thing to keep in sync by hand.
  for _p in hooks/h.sh agents/a.md commands/c.md agents/reference/r.ref; do
    mkdir -p "$g_repo/claude/${_p%/*}" && printf 'x\n' > "$g_repo/claude/$_p"
    mkdir -p "$g_home/.claude/${_p%/*}" && printf 'x\n' > "$g_home/.claude/$_p"
  done
  mkdir -p "$g_repo/claude/skills/s" "$g_home/.claude/skills/s"
  printf 'x\n' > "$g_repo/claude/skills/s/SKILL.md"; printf 'x\n' > "$g_home/.claude/skills/s/SKILL.md"
  mkdir -p "$g_home/.config/agents/bin"
  printf 'x\n' > "$g_repo/bin/b"; printf 'x\n' > "$g_home/.config/agents/bin/b"
  # mcp/servers.json is a drift family too, and unlike the others it is compared key-by-key
  # against $CJSON's merged mcpServers rather than byte-diffed. The home side deliberately
  # carries the "env": {} that Claude Code injects into every registered entry, so this control
  # also proves doctor compares only the keys the repo declares. Without it a real install
  # reads as drift on a tree that matches.
  mkdir -p "$g_repo/mcp"
  printf '{"stub":{"command":"x","args":[]}}\n' > "$g_repo/mcp/servers.json"
  printf '{"mcpServers":{"stub":{"command":"x","args":[],"env":{}}}}\n' > "$g_home/.claude.json"
  _o=$(env HOME="$g_home" VSTACK_DIR="$g_repo" ./bin/doctor --drift 2>&1)
  grep -q 'no drift' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift withholds its verdict from a tree that matches item for item"
  grep -qE 'no drift .*[0-9]+ item' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift does not say how many items it compared, so the result cannot be audited"

  # doctor --drift, mcp-specific: the mirrored stub above proves nothing about the mcp lane on its
  # own. Delete run_drift()'s mcp loop entirely and that stub still reports no drift, because the
  # other five families satisfy both assertions by themselves -- a positive control that passes
  # for a reason unrelated to the family it plants. So move ONLY the mcp value and require doctor
  # to name it. This is the assertion the whole family stands or falls on.
  printf '{"mcpServers":{"stub":{"command":"MOVED","args":[],"env":{}}}}\n' > "$g_home/.claude.json"
  _o=$(env HOME="$g_home" VSTACK_DIR="$g_repo" ./bin/doctor --drift 2>&1); _rc=$?
  grep -q 'mcp/servers.json:stub' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift does not notice an mcp server whose installed value moved; the mcp family is not being compared"
  [ "$_rc" -ne 0 ] \
    || g_errs="$g_errs\n  doctor --drift exits 0 with an mcp server that differs from what the repo declares"
  # And the reverse: a key the repo declares that is not registered at all.
  printf '{"mcpServers":{}}\n' > "$g_home/.claude.json"
  _o=$(env HOME="$g_home" VSTACK_DIR="$g_repo" ./bin/doctor --drift 2>&1)
  grep -q 'missing.*mcp/servers.json:stub' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift does not notice a declared mcp server that is not registered"

  # A server vstack installed and no longer ships, still registered. Nothing in $CJSON says who
  # put a key there, so this lane reads install.sh's ownership record; a user's own server must
  # stay untouched. Both halves asserted here, because a lane that flagged everything registered
  # would "pass" the first half while being unusable on any real machine.
  printf '{"mcpServers":{"stub":{"command":"x","args":[],"env":{}},"dropped":{"command":"q"},"users-own":{"command":"z"}}}\n' \
    > "$g_home/.claude.json"
  printf 'mcpServers:stub\nmcpServers:dropped\n' > "$g_home/.config/agents/vstack-installed"
  _o=$(env HOME="$g_home" VSTACK_DIR="$g_repo" ./bin/doctor --drift 2>&1)
  grep -q 'stale.*mcp/servers.json:dropped' <<<"$_o" \
    || g_errs="$g_errs\n  doctor --drift does not notice an mcp server vstack installed and no longer ships"
  grep -q 'users-own' <<<"$_o" \
    && g_errs="$g_errs\n  doctor --drift reports the user's own mcp server as drift; only keys in the ownership record are vstack's"
  grep -q 'stale.*mcp/servers.json:stub' <<<"$_o" \
    && g_errs="$g_errs\n  doctor --drift calls a server this repo still ships stale; the record names it because it is installed, not because it was dropped"

  rm -rf "$g_empty" "$g_repo" "$g_home"
  [ -z "$g_errs" ] \
    && ok "gates refuse a green on nothing measured (ui-gate, doctor --drift, both directions)" \
    || bad "gates refuse a green on nothing measured" "$(printf '%b' "$g_errs")"
else
  skip "gates refuse a green on nothing measured" "ui-gate/ui-gate.sh or bin/doctor is not executable"
fi

# --- 36. an eval run log is opened without destroying the one already there --------------------
#
# Every harness under tests/evals/ opened its log with `printf '<header>\n' > "$RUNLOG"`. That
# truncates unconditionally, which is harmless for the default (a fresh mktemp dir) and
# destructive the moment a caller passes RUNLOG= to accumulate across arms -- which is required,
# because one model-calling arm does not fit in a single invocation. Each arm overwrote the one
# before it, exit status stayed 0, and the summary reported the survivor as the whole experiment.
#
# It has already cost data. .audit/run/falsedone-*.tsv retains nine rows, all arm=vstack; the
# twelve-run `none` baseline quoted in docs/research/do-harnesses-help.md has no surviving raw
# rows. Nothing noticed, because destroying data and succeeding look identical from outside.
#
# The line was copied into three harnesses, so the assertion is not "these three are fixed" but
# "no fourth can reintroduce it": the truncating redirect is banned outright under tests/evals/,
# and any harness that defines its own RUNLOG default must go through the shared opener. The
# behavioural half runs the opener; the static half stops the next copy.
r_errs=""
if [ -f tests/evals/lib/runlog.sh ]; then
  # shellcheck source=/dev/null
  . tests/evals/lib/runlog.sh
  r_dir=$(mktemp -d); r_f="$r_dir/runs.tsv"; r_h=$(printf 'arm\trun\tresult')

  open_runlog "$r_f" "$r_h" 2>/dev/null || r_errs="$r_errs\n  refused to open a log that does not exist yet"
  [ "$(grep -c . "$r_f")" = 1 ] || r_errs="$r_errs\n  a new log did not get exactly one header line"

  printf 'vstack\t1\tok\n' >> "$r_f"; printf 'vstack\t2\tok\n' >> "$r_f"
  open_runlog "$r_f" "$r_h" 2>/dev/null || r_errs="$r_errs\n  refused to reopen a log it had written itself"
  [ "$(grep -c . "$r_f")" = 3 ] || r_errs="$r_errs\n  reopening a log destroyed rows: $(grep -c . "$r_f") line(s) survive of 3"
  [ "$(grep -c '^arm' "$r_f")" = 1 ] || r_errs="$r_errs\n  reopening wrote a second header line into the middle of the data"

  # optimize.sh hands the harness `log=$(mktemp)`, which exists and is empty. A refusal keyed on
  # [ -f ] rather than [ -s ] would break the optimiser on its first call, so pin the distinction.
  r_e="$r_dir/empty.tsv"; : > "$r_e"
  open_runlog "$r_e" "$r_h" 2>/dev/null || r_errs="$r_errs\n  treated a zero-length file as occupied; optimize.sh passes exactly that"

  open_runlog "$r_f" "$(printf 'other\tschema')" >/dev/null 2>&1
  [ "$?" = 2 ] || r_errs="$r_errs\n  appended rows of one schema onto a log holding another"
  rm -rf "$r_dir"

  # The static half. A truncating redirect anywhere under tests/evals/ is the defect itself.
  # Anchored on code, not on the word. The first spelling of this matched the sentence in
  # runlog.sh's own header that quotes the defect, which is the same way check 30's first draft
  # counted its own prose as a suppression. A file explaining a bug is not committing it.
  r_trunc=$(git grep -n -E '^[^#]*[^>]>[[:space:]]*"\$RUNLOG"' -- tests/evals \
              ':(exclude)tests/evals/lib/runlog.sh' 2>/dev/null || true)
  [ -z "$r_trunc" ] || r_errs="$r_errs\n  a truncating redirect into \$RUNLOG is back:\n    $(printf '%s' "$r_trunc" | head -3)"

  # And any harness owning a RUNLOG default must use the shared opener rather than its own.
  while IFS= read -r r_file; do
    [ -n "$r_file" ] || continue
    grep -q 'runlog\.sh' "$r_file" \
      || r_errs="$r_errs\n  $r_file sets its own RUNLOG default but never sources tests/evals/lib/runlog.sh"
  done <<<"$(git grep -l -E '^RUNLOG=\$\{RUNLOG:-|^RUNLOG="\$\{RUNLOG:-' -- tests/evals 2>/dev/null)"

  [ -z "$r_errs" ] \
    && ok "run logs are opened append-safe (4 cases, plus no truncating redirect under tests/evals)" \
    || bad "run logs are opened append-safe" "$(printf '%b' "$r_errs")"
else
  bad "run logs are opened append-safe" "tests/evals/lib/runlog.sh is missing, so three harnesses are back to truncating"
fi

# --- 37. the optimiser decides correctly, and refuses to score a run that produced no data -----
#
# The fourth decider in this repository and the only one nobody tested. Checks 23, 27 and 32 all
# drive their decider through its cases in both directions; optimize.sh's accept/revert/noise
# branch had never executed at all -- --try hard-exits without .opt-state, and .opt-state has
# never existed, so MIN_GAIN was asserted rather than measured and the code beneath it unrun.
#
# The scoring half matters more than the threshold. The old awk collapsed three situations into
# "0 0 0": a run that genuinely scored zero, a run that produced no rows, and a run whose
# fixtures planted no defects. Only the first is a result. The other two read as f1 0.0000,
# which makes delta hugely negative, trips the revert branch, and tells you a good change "made
# things measurably worse" -- a broken harness arguing against a correct edit.
#
# Offline and free: both functions are pure, so this spends no model allowance.
o_errs=""
if command -v awk >/dev/null 2>&1 && [ -f tests/evals/optimize.sh ]; then
  # shellcheck source=/dev/null
  eval "$(sed -n '/^f1_from_log() {/,/^}/p;/^decide() {/,/^}/p' tests/evals/optimize.sh)"
  o_dir=$(mktemp -d)

  printf 'arm\tfixture\tsample\thits\tplanted\tfp\tentered\n' > "$o_dir/empty.tsv"
  case "$(f1_from_log "$o_dir/empty.tsv")" in
    INVALID*) ;; *) o_errs="$o_errs\n  a log with a header and no rows scored instead of reporting no data" ;;
  esac

  printf 'arm\tfixture\tsample\thits\tplanted\tfp\tentered\nvstack\ta\t1\t0\t0\t0\tyes\n' > "$o_dir/noplant.tsv"
  case "$(f1_from_log "$o_dir/noplant.tsv")" in
    INVALID*) ;; *) o_errs="$o_errs\n  a run whose fixtures planted no defects scored 0 instead of reporting no data" ;;
  esac

  printf 'arm\tfixture\tsample\thits\tplanted\tfp\tentered\nvstack\ta\t1\t0\t4\t0\tyes\n' > "$o_dir/zero.tsv"
  case "$(f1_from_log "$o_dir/zero.tsv")" in
    INVALID*) o_errs="$o_errs\n  a genuine score of zero was reported as no data; those are different findings" ;;
    *) read -r _r _p _f <<<"$(f1_from_log "$o_dir/zero.tsv")"
       [ "$_f" = "0.0000" ] || o_errs="$o_errs\n  a run that found none of 4 planted defects scored f1 $_f, expected 0.0000" ;;
  esac

  printf 'arm\tfixture\tsample\thits\tplanted\tfp\tentered\nvstack\ta\t1\t4\t4\t0\tyes\n' > "$o_dir/perfect.tsv"
  read -r _r _p _f <<<"$(f1_from_log "$o_dir/perfect.tsv")"
  [ "$_f" = "1.0000" ] || o_errs="$o_errs\n  a run that found all 4 of 4 with no false positives scored f1 $_f, expected 1.0000"

  # The decision, including the boundary an edit moves by accident.
  [ "$(decide 0.50 0.60 0.05)" = keep ]   || o_errs="$o_errs\n  a +0.10 gain was not kept"
  [ "$(decide 0.50 0.40 0.05)" = revert ] || o_errs="$o_errs\n  a -0.10 loss was not reverted"
  [ "$(decide 0.50 0.52 0.05)" = noise ]  || o_errs="$o_errs\n  a +0.02 move inside the spread was treated as a result"
  [ "$(decide 0.50 0.55 0.05)" = noise ]  || o_errs="$o_errs\n  exactly +MIN_GAIN was kept; the boundary is strictly greater than"

  rm -rf "$o_dir"
  [ -z "$o_errs" ] \
    && ok "optimiser decides correctly (4 scoring cases, 4 decisions, no model calls)" \
    || bad "optimiser decides correctly" "$(printf '%b' "$o_errs")"
else
  skip "optimiser decides correctly" "awk missing or tests/evals/optimize.sh absent"
fi

# --- 38. every repository path named in live prose exists --------------------------------------
#
# Check 20 does this for ~/-rooted install paths and frames it as prose and installed tree
# disagreeing. The repo-relative direction had never been checked, so a doc could point at a
# script that is not there and nothing would say so -- which is exactly the state tests/README.md
# was left in the moment tests/evals/run.sh was deleted.
#
# Backticked paths only, and only those ending in an extension this repository actually ships.
# Resolved against the repo root or against the doc's own directory, because tests/README.md
# writes `evals/run-pathways.sh` and means tests/evals/run-pathways.sh.
#
# Scope is stated rather than assumed. claude/skills, claude/agents and claude/commands are
# excluded: they are instructions to a model about the reader's project, full of placeholders
# like `exact/path/to/file.py` and target-project paths like `.impeccable/config.json`, none of
# which are claims about this tree. docs/provenance and docs/research are excluded for the same
# reason check 12 excludes them -- one is dated internal history, the other describes other
# people's repositories. CHANGELOG is excluded because its older entries name files that were
# real when written and deleting them later is not an error.
p_errs=""
# Derived, not listed. The old form was a hardcoded pathspec that silently narrowed as files
# were added or moved. Now it scans every .md file in the tree, then applies exclusions for
# placeholder paths (claude/skills|agents|commands), third-party evidence (docs/provenance|research),
# installed artifacts (.claude/), historical entries (CHANGELOG), and third-party test results
# (tests/evals/RESULTS.md). This matches check 12's approach and keeps the two consistent.
# Destinations `vstack overlay .` SEEDS into a TARGET repository, derived from overlay.sh rather
# than listed. README's overlay table names `.github/workflows/security.yml` in its "Lands at"
# column: that is a path in somebody else's repo after the overlay runs, the same category as the
# `.claude/*` exemption below, and holding this tree to it would demand vstack ship every file it
# hands to other people. Derived, so retiring a template retires its exemption with it -- a
# hardcoded list here would outlive the thing it excuses, which is the failure check 20d exists
# for. Leading and trailing spaces so the membership test below cannot match a prefix.
p_seeded=" $(grep -oE '^seed_tmpl [^ ]+ [^ ]+' overlay.sh 2>/dev/null | awk '{print $3}' | tr '\n' ' ')"
p_docs=$(git ls-files '*.md' 2>/dev/null | grep -vE '^(docs/(provenance|research)/|claude/(skills|agents|commands)/|\.claude/|CHANGELOG\.md$|tests/evals/RESULTS\.md$)')
p_n=$(printf '%s' "$p_docs" | grep -c .)
if [ "$p_n" -lt 8 ]; then
  p_errs="$p_errs\n  internal: only $p_n document(s) in scope, expected at least 8 (README.md, tests/README.md, ui-gate/README.md, docs/*.md, .github/*.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md)"
else
  p_seen=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      case "$ref" in
        http*|*'<'*|*'>'*|*'$'*|*'*'*) continue ;;   # URLs, placeholders, globs
        # The installed namespace, which check 20 owns. `.claude/CLAUDE.md` in prose is a file
        # the overlay writes into somebody else's repository, or one a falsifiability row plants
        # and removes; it is not a claim that this tree ships it, and demanding it exist here
        # would be the same category error as holding another project's benchmark counts to
        # this one. Paths this repository does ship live under claude/, without the dot.
        .claude/*) continue ;;
      esac
      case "$p_seeded" in *" $ref "*) continue ;; esac
      p_seen=$((p_seen + 1))
      [ -e "$ref" ] && continue
      [ -e "${d%/*}/$ref" ] && continue
      p_errs="$p_errs\n  $d names $ref, which is not in this repository"
    done <<<"$(grep -oE '`[./A-Za-z0-9_-]+/[./A-Za-z0-9_-]+\.(sh|md|json|py|zsh|toml|yml)`' "$d" 2>/dev/null \
               | tr -d '`' | sed 's|^\./||' | sort -u)"
  done <<<"$p_docs"
  [ "$p_seen" -gt 0 ] || p_errs="$p_errs\n  internal: no backticked repository paths matched at all, so the extractor is looking for the wrong shape"
fi
[ -z "$p_errs" ] \
  && ok "every repository path named in prose exists ($p_seen reference(s) across $p_n document(s))" \
  || bad "every repository path named in prose exists" "$(printf '%b' "$p_errs")"

# --- 39. CHANGELOG.md is structurally sound ------------------------------------------------
# Commit 2cda849 landed a second "## Unreleased" heading directly beneath the first. One
# session anchored its entry on what it believed was the top of the file while a different
# session concurrently shipped two releases above it; both were right about the heading they
# were looking at and wrong about the file as it actually stood. The duplicate sat in
# committed history for eight minutes before the next commit renamed it away. Nothing else
# here reads the shape of this file -- check 12 compares the numbers in its prose against the
# tree, not its heading structure, and would have said nothing.
#
# The convention below is read off the file's own 44 existing headings, not invented. "## " is
# followed by `Unreleased` or a bare semver, optionally a parenthetical suffix -- the one
# precedent is "1.8.0 (earlier entries)", two dated sections sharing a version because 1.8.0
# shipped across two sessions a day apart, which is why duplicate detection below keys on the
# full heading line rather than the bare version -- and optionally an em dash and an ISO date.
# `## Unreleased` is not present in the file today, confirmed by grep before writing this, but
# it is still accepted as a legal heading: the incident this check exists to catch was two of
# them.
if [ -f CHANGELOG.md ]; then
  c_errs=""
  c_heads=$(grep -n '^## ' CHANGELOG.md)
  c_fmt='^[0-9]+:## (Unreleased|[0-9]+\.[0-9]+\.[0-9]+)( \([^)]*\))?( — [0-9]{4}-[0-9]{2}-[0-9]{2})?$'

  # 4. every "## " line parses under the convention above, or it is not a section at all.
  c_bad=$(printf '%s\n' "$c_heads" | grep -vE "$c_fmt")
  [ -n "$c_bad" ] && c_errs="$c_errs\nmalformed heading(s):\n$c_bad"

  # 1. no duplicate heading. Byte-identical text twice is exactly what 2cda849 shipped; two
  # differently-dated or differently-suffixed sections for the same version, like 1.8.0's, are
  # not this defect and are left alone.
  c_dup=$(printf '%s\n' "$c_heads" | sed -E 's/^[0-9]+://' | sort | uniq -d)
  [ -n "$c_dup" ] && c_errs="$c_errs\nduplicate heading(s):\n$c_dup"

  # Numeric-field semver compare, ignoring any parenthetical suffix and date. macOS ships BSD
  # sort, which has no -V, and a plain string sort puts 1.9.0 above 1.10.0.
  _c_ge(){ # _c_ge A B -> true if version A is not older than version B
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<<"$1"
    IFS=. read -r b1 b2 b3 <<<"$2"
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}; b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
    [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
    [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
    [ "$a3" -ge "$b3" ]
  }
  # Only well-formed headings feed the ordering and top-version checks below -- a malformed
  # line is already reported above, and letting free text reach a numeric compare here would
  # print a raw shell arithmetic error instead of a finding.
  c_ok=$(printf '%s\n' "$c_heads" | grep -E "$c_fmt")
  c_vers=$(printf '%s\n' "$c_ok" | sed -E 's/^[0-9]+:## //; s/ \([^)]*\)//; s/ — .*$//')
  c_prev="" c_top=""
  while IFS= read -r c_v; do
    [ -n "$c_v" ] || continue
    [ "$c_v" = "Unreleased" ] && continue
    [ -z "$c_top" ] && c_top="$c_v"
    # 2. versions descend going down the file.
    if [ -n "$c_prev" ] && ! _c_ge "$c_prev" "$c_v"; then
      c_errs="$c_errs\nversions do not descend: $c_prev sits above $c_v"
    fi
    c_prev="$c_v"
  done <<EOF
$c_vers
EOF

  # 3. the newest real version heading is the release the manifests actually declare -- the
  # assertion that would have caught 2cda849, because a release filed under the wrong heading
  # is a release nobody can find.
  if command -v jq >/dev/null; then
    c_mv=$(jq -r '.version // empty' claude/.claude-plugin/plugin.json 2>/dev/null)
    c_mkv=$(jq -r '.plugins[0].version // empty' .claude-plugin/marketplace.json 2>/dev/null)
    [ -n "$c_mv" ] && [ -n "$c_top" ] && [ "$c_mv" != "$c_top" ] \
      && c_errs="$c_errs\ntop heading is $c_top, plugin.json declares $c_mv"
    [ -n "$c_mkv" ] && [ -n "$c_top" ] && [ "$c_mkv" != "$c_top" ] \
      && c_errs="$c_errs\ntop heading is $c_top, marketplace.json declares $c_mkv"
  fi

  [ -z "$c_errs" ] \
    && ok "CHANGELOG.md structure ($(printf '%s\n' "$c_heads" | grep -c .) headings, top $c_top)" \
    || bad "CHANGELOG.md structure" "$(printf '%b' "$c_errs")"
else
  bad "CHANGELOG.md structure" "CHANGELOG.md is missing"
fi

# --- 40. a latched session still writes a delegation-drift row ---------------------------------
#
# The 2-strike latch in skill-mandate.sh (cnt>=2) used to sit above the delegation-drift logger,
# so once a session accumulated 2 mandate strikes every later Stop returned before logging --
# permanently blind for exactly the long, multi-directory sessions the log exists to measure.
# Check 27 exercises the mandate's block/silent decisions in both directions but never drives a
# session past the latch, so it stayed green through the entire regression.
#
# The fix keeps the latch's blocking behaviour (a mandate the model cannot satisfy must not trap
# the session) and adds one cheap row on the way out: {..., dir_count:null, ext_count:null,
# task_count:null, named:null, latched:true, ts}. This drives the real hook through three Stops
# on one synthetic session -- two that trip an unmet mandate (cnt 0->1, 1->2) and a third that
# lands on the latch (cnt>=2) -- and checks both that logging survives the latch AND that
# blocking still stops there, because a check that only asserted the former would stay green if
# the latch also started emitting the block JSON it exists to suppress.
if command -v jq >/dev/null; then
  sm="claude/hooks/skill-mandate.sh"
  if [ ! -x "$sm" ]; then
    bad "latched session still logs a delegation-drift row" "$sm is missing or not executable"
  else
    c40_dir=$(mktemp -d)
    c40_log="$c40_dir/delegation-log.jsonl"
    c40_transcript="$c40_dir/t.jsonl"
    # $$-scoped and prefixed distinctly from check 27's "vfy-" ids: a real session_id is a UUID,
    # neither of these can collide with one, and the two fixture families stay distinguishable
    # from each other in a stray log line.
    c40_sid="chk40-$$-$(date +%s 2>/dev/null || echo 0)"
    c40_errs=""

    # The real log this hook writes to by default, untouched by this check's own destination
    # override below. Sampled before and after: this is the exact leak this file's own check 27
    # comment documents -- a `VAR=x cmd1 | cmd2` scoping mistake let ~12 vfy-* rows land here
    # once already. If this check ever regresses to that mistake, this is what catches it.
    c40_real_log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-delegation-log.jsonl"
    c40_real_before=0; [ -f "$c40_real_log" ] && c40_real_before=$(wc -l < "$c40_real_log" 2>/dev/null | tr -d ' ')
    [ -n "$c40_real_before" ] || c40_real_before=0

    c40_cleanup(){
      rm -rf "$c40_dir" 2>/dev/null
      # $c40_sid drives three checkpoint Stops, which is enough to reach the delegation-family
      # gate (skill-mandate.sh's $cnt_file.delegate / .delegate-ts / .delegate-scan) as well as
      # the plain counter and its ckpt-split sibling -- ".delegate-scan" is exactly the file that
      # leaked here (vstack-mandate-chk40-<pid>-<ts>.delegate-scan) when this only swept the
      # first two names. One anchored glob catches the counter and every suffix skill-mandate.sh
      # hangs off it (present or not yet added); the ckpt file needs its own line, same as check
      # 27, because "ckpt-" sits before the anchor rather than after it.
      rm -rf "${TMPDIR:-/tmp}/vstack-mandate-$c40_sid"* "${TMPDIR:-/tmp}/vstack-mandate-ckpt-$c40_sid" 2>/dev/null
      unset VSTACK_DELEGATION_LOG
    }
    trap c40_cleanup EXIT

    # Exported for the rest of this block, not prefixed onto one half of a pipe -- `VAR=x printf
    # ... | bash "$hook"` scopes the assignment to printf alone and the hook never sees it, which
    # is exactly how fixture rows reached the real log before. `export` here reaches every
    # invocation of $sm below, piped or not.
    export VSTACK_DELEGATION_LOG="$c40_log"

    # Trips ALL FOUR skill-family mandates on every Stop: a prose write with no unslop, a .tsx
    # edit with no typescript-best-practices, a turn that closes claiming done with no
    # Bash/Read/Task/Agent call to back it (prove-it-works), and a closing text that opens with
    # a banned register phrase ("Perfect."). One mandate is no longer enough, and this fixture
    # must grow a new trigger every time the skill family grows a mandate -- otherwise the
    # never-tripped mandate's counter stays clear, the family latch is never reached, and Stop 3
    # falls through to a dense latched:false row (exactly how the register mandate turned this
    # check red the day it was added).
    #
    # 1.57.0 split the 2-strike latch per mandate, because one shared counter meant two unrelated
    # unslop misses disarmed the other mandates for the rest of the session -- measured at the
    # family level in f4f5468 and still live one level down. The family-level short-circuit this
    # check drives to now needs every skill-family mandate individually latched, so an
    # unslop-only fixture never reaches it: Stop 3 falls through to the ordinary evaluator and
    # logs a dense latched:false row instead. That is correct behaviour, and a fixture that only
    # trips one mandate would quietly stop testing the latch at all while still passing its two
    # dense-row assertions.
    #
    # Each mandate's counter is CLEARED when it is evaluated and not hit, so all three have to
    # trip on the same Stop to accumulate together. Verified against the real hook: Stops 1 and 2
    # block and log dense rows, Stop 3 is silent and logs latched:true with all four counts null.
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App.tsx"}},{"type":"text","text":"Perfect. All done, the feature is complete and working."}]}}' \
      > "$c40_transcript"

    c40_hit(){
      printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":false}' \
        "$c40_sid" "$c40_transcript" | "./$sm" 2>/dev/null
    }

    c40_out1=$(c40_hit); c40_rc1=$?
    c40_out2=$(c40_hit); c40_rc2=$?
    c40_out3=$(c40_hit); c40_rc3=$?

    # Direction 1: the two unlatched Stops both blocked and both logged. A check that only ever
    # looked at the latched row would stay green if the logger started firing unconditionally --
    # this is what tells "logs on every Stop" apart from "logs only once latched".
    printf '%s' "$c40_out1" | grep -q '"decision":"block"' \
      || c40_errs="$c40_errs\nStop 1 (cnt=0, unmet mandate) did not block"
    printf '%s' "$c40_out2" | grep -q '"decision":"block"' \
      || c40_errs="$c40_errs\nStop 2 (cnt=1, unmet mandate) did not block"
    [ "$c40_rc1" -eq 0 ] || c40_errs="$c40_errs\nStop 1 exited $c40_rc1, expected 0"
    [ "$c40_rc2" -eq 0 ] || c40_errs="$c40_errs\nStop 2 exited $c40_rc2, expected 0"

    # Direction 2 (the regression itself): the third Stop lands on the latch (cnt=2) and must
    # still produce a row. Blocking behaviour must be unchanged at the latch: exit 0, no stdout --
    # the latch's entire purpose is that a mandate the model cannot satisfy does not trap the
    # session, and a passing check that let the block JSON reappear here has gated the wrong
    # thing.
    [ -z "$c40_out3" ] \
      || c40_errs="$c40_errs\nStop 3 (cnt=2, latched) produced stdout, must stay silent: $c40_out3"
    [ "$c40_rc3" -eq 0 ] || c40_errs="$c40_errs\nStop 3 (latched) exited $c40_rc3, expected 0"

    c40_nrows=$(grep -c . "$c40_log" 2>/dev/null)
    [ "${c40_nrows:-0}" -eq 3 ] \
      || c40_errs="$c40_errs\nexpected 3 delegation-drift rows, found ${c40_nrows:-0}: $(cat "$c40_log" 2>/dev/null)"

    if [ "${c40_nrows:-0}" -eq 3 ]; then
      c40_row1=$(sed -n '1p' "$c40_log")
      c40_row2=$(sed -n '2p' "$c40_log")
      c40_row3=$(sed -n '3p' "$c40_log")

      # Rows 1 and 2: evaluated Stops. Dense -- every count field is a real number, checkpoint
      # index advances, latched is false.
      jq -e --arg sid "$c40_sid" \
        '.session_id==$sid and .checkpoint_index==1 and .latched==false
         and (.dir_count|type)=="number" and (.ext_count|type)=="number"
         and (.task_count|type)=="number" and (.named|type)=="boolean"' \
        <<<"$c40_row1" >/dev/null 2>&1 \
        || c40_errs="$c40_errs\nrow 1 is not a well-formed evaluated row: $c40_row1"
      jq -e --arg sid "$c40_sid" \
        '.session_id==$sid and .checkpoint_index==2 and .latched==false
         and (.dir_count|type)=="number" and (.ext_count|type)=="number"
         and (.task_count|type)=="number" and (.named|type)=="boolean"' \
        <<<"$c40_row2" >/dev/null 2>&1 \
        || c40_errs="$c40_errs\nrow 2 is not a well-formed evaluated row: $c40_row2"

      # Row 3: latched. checkpoint_index still advanced (the counter moved above the latch),
      # latched is true, and every count field this row cannot afford to compute is JSON null,
      # not zero -- null is what makes this row tellable apart from a dense row where breadth
      # genuinely measured zero, which is the whole reason the fix chose null over 0.
      jq -e --arg sid "$c40_sid" \
        '.session_id==$sid and .checkpoint_index==3 and .latched==true
         and (.dir_count|type)=="null" and (.ext_count|type)=="null"
         and (.task_count|type)=="null" and (.named|type)=="null"' \
        <<<"$c40_row3" >/dev/null 2>&1 \
        || c40_errs="$c40_errs\nrow 3 is not a well-formed latched row: $c40_row3"
    fi

    c40_real_after=0; [ -f "$c40_real_log" ] && c40_real_after=$(wc -l < "$c40_real_log" 2>/dev/null | tr -d ' ')
    [ -n "$c40_real_after" ] || c40_real_after=0
    [ "$c40_real_before" = "$c40_real_after" ] \
      || c40_errs="$c40_errs\nthe operator's real delegation log changed ($c40_real_before -> $c40_real_after lines) -- fixture rows leaked into it"

    c40_cleanup
    trap - EXIT

    [ -z "$c40_errs" ] \
      && ok "latched session still logs a delegation-drift row (3 Stops, both directions)" \
      || bad "latched session still logs a delegation-drift row" "$(printf '%b' "$c40_errs")"
  fi
else
  skip "latched session still logs a delegation-drift row" "jq not installed"
fi

# --- 44. the dispatch counter's writer and reader agree, in both directions --------------------
# claude/statusline.sh renders "RICK ·N▸" by reading a per-session counter file that
# claude/hooks/dispatch-counter.sh writes on every Agent/Task PostToolUse. The reader shipped
# first and was verified against a hand-created fixture file -- nothing in the tree ever created
# that file at runtime, so the segment rendered nothing in production while a check built the
# same way would have stayed green throughout. This drives the REAL writer against the REAL
# reader on one throwaway session id -- no fixture file, the counter under test is the one the
# hook actually wrote -- and separately asserts the wiring that installs the reader, because a
# join proven only in this dev checkout is exactly check 11's inert-plugin-hook shape ported to
# a second lane.
#
# Extended for the same hook's replay-log addition (claude/vstack-replay-log.jsonl, one row per
# dispatch, sizes not contents): Direction 3 drives the SAME 4-dispatch fixture above through a
# real VSTACK_REPLAY_LOG/VSTACK_DELEGATION_LOG pair, so "the counter landed" and "the row landed"
# are evidence from one drive, not two runs that could quietly disagree. Assertions are on
# behaviour a grep cannot see -- the row exists with the right dispatch_index, nothing reaches
# the delegation log (fixture destination AND the operator's real one, sampled before/after the
# way check 40 already does), sentinel prompt/result text never appears anywhere in the log file,
# and the VSTACK_NO_REPLAY_LOG hatch silences the row without silencing the count. Direction 4
# pins, rather than fixes, the one gap M-6 disclosed: PostToolUseFailure carries `error` not
# `tool_response` and this hook's own jq never branches on hook_event_name, so the ONLY thing
# stopping a failed dispatch from producing a (malformed) row is that dispatch-counter.sh is not
# wired under PostToolUseFailure at all -- wiring, not logic, and the only part of that gap this
# repo's own tree can observe without the Claude Code binary actually emitting the event.
if command -v jq >/dev/null; then
  dc="claude/hooks/dispatch-counter.sh"
  sl="claude/statusline.sh"
  if [ ! -x "$dc" ] || [ ! -f "$sl" ]; then
    bad "dispatch counter join, both directions" "$dc missing/not executable, or $sl missing"
  else
    c44_errs=""
    c44_sid="chk44-$$-$(date +%s 2>/dev/null || echo 0)"
    c44_cnt="${TMPDIR:-/tmp}/vstack-dispatch-count-$c44_sid"
    c44_lock="$c44_cnt.lock"
    c44_cleanup(){
      rm -f "$c44_cnt" 2>/dev/null; rmdir "$c44_lock" 2>/dev/null
      rm -rf "${c44_replay_dir:-}" "${c44_deleg_dir:-}" 2>/dev/null
      unset VSTACK_REPLAY_LOG VSTACK_DELEGATION_LOG VSTACK_NO_REPLAY_LOG
    }
    trap c44_cleanup EXIT

    c44_payload(){ printf '{"session_id":"%s","model":{"display_name":"Claude"}}' "$c44_sid"; }
    c44_dispatch(){ printf '{"session_id":"%s","tool_name":"%s"}' "$c44_sid" "$1" | "./$dc" >/dev/null 2>&1; }

    # Direction 2 (zero renders, and renders as zero): a session with no dispatches must still
    # render the RICK segment, carrying the ·0▸ marker. This direction used to assert the
    # opposite -- no segment at all before the first dispatch, on the reasoning that an absent
    # counter file means "nobody asked yet" rather than "zero on purpose". That precision cost
    # total invisibility: the team indicator disappeared exactly in the sessions where
    # delegation never happened, which are the sessions the indicator exists to expose. The
    # counter file is only ever created by a dispatch, so for display purposes absent IS zero
    # dispatches so far, and zero is bad news that must be on screen, not blank.
    [ -e "$c44_cnt" ] && c44_errs="$c44_errs\ncounter file already existed before any dispatch: $c44_cnt"
    c44_out0=$(c44_payload | "./$sl" 2>/dev/null)
    case "$c44_out0" in
      *RICK*"·0▸"*) ;;
      *RICK*) c44_errs="$c44_errs\nzero dispatches rendered RICK without the ·0▸ marker -- a blank or positive count over a session that never delegated: $c44_out0" ;;
      *) c44_errs="$c44_errs\na session with zero dispatches rendered no RICK segment at all -- absence hides the team exactly when enforcement is failing: $c44_out0" ;;
    esac

    # Replay-log fixtures for Direction 3, wired up BEFORE the drive below so the same dispatches
    # produce both the counter file (Direction 1) and the replay rows (Direction 3). Two isolated
    # temp destinations, exported (not `VAR=x cmd | cmd`-scoped -- that leaked fixture rows into
    # the real delegation log once already), plus both real logs' line counts sampled now, before
    # anything is driven.
    c44_replay_dir=$(mktemp -d)
    c44_deleg_dir=$(mktemp -d)
    c44_replay="$c44_replay_dir/replay.jsonl"
    c44_deleg="$c44_deleg_dir/deleg.jsonl"
    c44_real_replay="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-replay-log.jsonl"
    c44_real_deleg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-delegation-log.jsonl"
    c44_rreplay_before=0; [ -f "$c44_real_replay" ] && c44_rreplay_before=$(wc -l < "$c44_real_replay" 2>/dev/null | tr -d ' ')
    c44_rdeleg_before=0; [ -f "$c44_real_deleg" ] && c44_rdeleg_before=$(wc -l < "$c44_real_deleg" 2>/dev/null | tr -d ' ')
    export VSTACK_REPLAY_LOG="$c44_replay"
    export VSTACK_DELEGATION_LOG="$c44_deleg"
    c44_desc="chk44-desc-$c44_sid"
    c44_prompt="chk44-PROMPT-SECRET-$c44_sid-must-not-leak"
    c44_result="chk44-RESULT-SECRET-$c44_sid-must-not-leak"
    c44_full(){
      printf '{"session_id":"%s","tool_name":"%s","tool_input":{"description":"%s","prompt":"%s","subagent_type":"qa-fixture"},"tool_response":{"content":"%s"},"duration_ms":137,"tool_use_id":"tu-%s"}' \
        "$c44_sid" "$1" "$c44_desc" "$c44_prompt" "$c44_result" "$c44_sid" | "./$dc" >/dev/null 2>&1
    }

    # Direction 1 (the join): drive the real writer -- 3 Task + 1 Agent, both tool_names the
    # hook accepts -- then one Write, which the hook must ignore, so the count asserted below is
    # the exact N driven and not just "some positive number". Then read the real reader on the
    # same session id. The first dispatch carries the sentinel description/prompt/result so
    # Direction 3 below reads off this SAME drive rather than a second one.
    c44_full Task; c44_dispatch Task; c44_dispatch Task; c44_dispatch Agent
    c44_n=4
    c44_dispatch Write

    c44_out1=$(c44_payload | "./$sl" 2>/dev/null)
    case "$c44_out1" in
      *"RICK"*"$c44_n"*) ;;
      *) c44_errs="$c44_errs\nafter $c44_n Agent/Task dispatches (+1 ignored Write) statusline did not render RICK ...$c44_n: $c44_out1" ;;
    esac

    # Direction 3a: a dispatch writes a replay row, and dispatch_index joins the SAME counter
    # file the statusline read above -- one row per Agent/Task dispatch, the ignored Write
    # produces none, so the count asserted is exact, not "at least one".
    c44_rows=$(grep -c . "$c44_replay" 2>/dev/null); [ -n "$c44_rows" ] || c44_rows=0
    [ "$c44_rows" -eq "$c44_n" ] \
      || c44_errs="$c44_errs\nexpected $c44_n replay rows (one per Agent/Task dispatch, Write excluded), found $c44_rows: $(cat "$c44_replay" 2>/dev/null)"

    c44_row1=$(sed -n '1p' "$c44_replay")
    c44_promptlen=$(printf '%s' "$c44_prompt" | wc -c | tr -d ' ')
    c44_desclen=$(printf '%s' "$c44_desc" | wc -m | tr -d ' ')
    jq -e --arg sid "$c44_sid" --argjson dlen "$c44_desclen" --argjson plen "$c44_promptlen" \
      '.session_id==$sid and .dispatch_index==1 and .tool_name=="Task"
       and .description_bytes==$dlen and .prompt_bytes==$plen and (.result_bytes|type)=="number"
       and (.duration_ms|type)=="number" and (.tool_use_id|type)=="string"' \
      <<<"$c44_row1" >/dev/null 2>&1 \
      || c44_errs="$c44_errs\nreplay row 1 is not a well-formed row for the sentinel dispatch: $c44_row1"

    c44_row_last=$(sed -n "${c44_n}p" "$c44_replay")
    c44_cnt_val=$(cat "$c44_cnt" 2>/dev/null)
    jq -e --arg sid "$c44_sid" --argjson n "$c44_n" \
      '.session_id==$sid and .dispatch_index==$n' <<<"$c44_row_last" >/dev/null 2>&1 \
      || c44_errs="$c44_errs\nreplay row $c44_n's dispatch_index does not equal $c44_n: $c44_row_last"
    [ "$c44_cnt_val" = "$c44_n" ] \
      || c44_errs="$c44_errs\nthe counter file the statusline reads ($c44_cnt) holds '$c44_cnt_val', not $c44_n -- replay dispatch_index and the statusline counter have drifted apart"

    # Direction 3b: the secrecy boundary. All three free-text fields are sizes only. description
    # used to be recorded verbatim on the reasoning that it is a label rather than content, but
    # nothing enforced that: it is unconstrained free text on the Task tool schema, and a
    # dispatch described as "rotate credential sk-ant-... before merge" put the credential in the
    # log. A carve-out defended by convention is not a boundary. Asserted by grepping the WHOLE
    # replay file for each sentinel string rather than trusting the schema -- a byte-count field
    # can be quietly swapped for the text it was meant to summarize without changing its name.
    grep -qF "$c44_desc" "$c44_replay" \
      && c44_errs="$c44_errs\ndescription sentinel text appears in the replay log -- description contents are leaking, not just description_bytes"
    grep -qF "$c44_prompt" "$c44_replay" \
      && c44_errs="$c44_errs\nprompt sentinel text appears in the replay log -- prompt contents are leaking, not just prompt_bytes"
    grep -qF "$c44_result" "$c44_replay" \
      && c44_errs="$c44_errs\nresult sentinel text appears in the replay log -- tool_response contents are leaking, not just result_bytes"

    # Direction 3c: the delegation log is a different file for a different purpose
    # (skill-mandate.sh's per-Stop aggregate) and this hook must never write to it. Sampled two
    # ways: the isolated destination above must stay untouched, and the operator's real
    # ~/.claude/vstack-delegation-log.jsonl line count -- sampled before the drive, compared
    # after cleanup below -- must be identical, the same leak check 40 already runs.
    [ -e "$c44_deleg" ] \
      && c44_errs="$c44_errs\ndispatch-counter.sh wrote to VSTACK_DELEGATION_LOG ($c44_deleg) -- it must never touch the delegation log"

    # Direction 3d: the escape hatch. VSTACK_NO_REPLAY_LOG=1 must silence the row while leaving
    # the counter (and therefore the statusline) advancing exactly as before -- both halves, or
    # neither proves anything: a hatch that also stops the count is VSTACK_NO_DISPATCH_COUNT
    # under a different name, and a hatch that keeps logging despite being set is no hatch.
    export VSTACK_NO_REPLAY_LOG=1
    c44_dispatch Task
    c44_n5=5
    c44_cnt_val5=$(cat "$c44_cnt" 2>/dev/null)
    [ "$c44_cnt_val5" = "$c44_n5" ] \
      || c44_errs="$c44_errs\nVSTACK_NO_REPLAY_LOG=1: counter did not advance to $c44_n5 (got '$c44_cnt_val5') -- the hatch must silence the replay row, not the count"
    c44_rows5=$(grep -c . "$c44_replay" 2>/dev/null); [ -n "$c44_rows5" ] || c44_rows5=0
    [ "$c44_rows5" -eq "$c44_n" ] \
      || c44_errs="$c44_errs\nVSTACK_NO_REPLAY_LOG=1: replay row count changed ($c44_n -> $c44_rows5) -- the hatch did not suppress the row"
    unset VSTACK_NO_REPLAY_LOG

    # Direction 3e (admission): a dispatch that CLAIMS a verdict without showing any is the whole
    # false-completion failure mode this repository's own research section is about, and until
    # this lane existed the replay log recorded the claim's byte count and nothing about whether
    # it was backed by anything. dispatch-counter.sh classifies the tool_response into `verdict`
    # (PASS/ISSUES/BLOCKED/DONE, else null) and `has_evidence` (a `path:NN` reference, a line
    # opening with `$ `, or an `exit <digit>`), and when a verdict arrives with no evidence it
    # returns hookSpecificOutput.additionalContext beginning with "UNVERIFIED:" so the claim is
    # contradicted in the transcript rather than only in a log nobody reads.
    #
    # Driven both ways in one lane, because either half alone proves nothing: a classifier that
    # answers "no evidence" to everything raises the flag on the bare claim AND on the cited one,
    # and a classifier that answers "evidence" to everything raises it on neither. Two payloads,
    # two isolated replay files, and the row read out of each -- the same one-drive-two-readings
    # shape as Direction 3a above rather than a second run that could quietly disagree.
    #
    # Each payload gets its OWN replay destination so the assertion is on row 1 of a file with
    # exactly one row: reusing the shared log would make these assertions depend on the dispatch
    # count Directions 1 and 3d left behind, which is a join between two unrelated lanes.
    c44_adm_bare="$c44_replay_dir/admission-bare.jsonl"
    c44_adm_evid="$c44_replay_dir/admission-evid.jsonl"
    c44_admit(){ # <replay destination> <tool_response text> -> the hook's stdout
      # Exported, not `VAR=x cmd | cmd`-prefixed: the comment on the fixtures above records what
      # that scoping cost the first time it was used here.
      export VSTACK_REPLAY_LOG="$1"
      printf '{"session_id":"%s","tool_name":"Task","tool_input":{"description":"adm","prompt":"p","subagent_type":"qa-fixture"},"tool_response":{"content":"%s"},"duration_ms":11,"tool_use_id":"tu-adm-%s"}' \
        "$c44_sid" "$2" "$c44_sid" | "./$dc" 2>/dev/null
    }
    # "PASS, all good" carries no path:line, no shell prompt and no exit status. "PASS, see
    # src/a.py:12" differs in exactly one respect: it cites a location. Anything the classifier
    # does that is not reading for evidence treats these two identically.
    c44_out_bare=$(c44_admit "$c44_adm_bare" "PASS, all good")
    c44_out_evid=$(c44_admit "$c44_adm_evid" "PASS, see src/a.py:12")
    c44_row_bare=$(sed -n '1p' "$c44_adm_bare" 2>/dev/null)
    c44_row_evid=$(sed -n '1p' "$c44_adm_evid" 2>/dev/null)

    if [ -z "$c44_row_bare" ] || [ -z "$c44_row_evid" ]; then
      c44_errs="$c44_errs\nadmission lane: the hook wrote no replay row for one or both admission payloads (bare='${c44_row_bare:-none}', evidenced='${c44_row_evid:-none}') -- this is the writer, not the assertions below, so read it as the drive failing rather than the fields being wrong"
    elif ! jq -e 'has("verdict") and has("has_evidence")' <<<"$c44_row_bare" >/dev/null 2>&1; then
      # Distinguished from a wrong VALUE on purpose. "the field is absent" means
      # claude/hooks/dispatch-counter.sh has not implemented the admission fields; "the field
      # holds the wrong thing" means it has, and got it wrong. Reported as one message each so a
      # reader is never left inferring which of the two they are looking at.
      c44_errs="$c44_errs\nadmission lane NOT IMPLEMENTED: the replay row carries no verdict/has_evidence field at all -- claude/hooks/dispatch-counter.sh has not been widened yet. Row: $c44_row_bare"
    else
      jq -e '.verdict == "PASS" and .has_evidence == false' <<<"$c44_row_bare" >/dev/null 2>&1 \
        || c44_errs="$c44_errs\nadmission lane: a tool_response of \"PASS, all good\" -- a verdict with no path:line, no \$ command and no exit status -- did not record verdict=PASS with has_evidence=false. Row: $c44_row_bare"
      jq -e '.verdict == "PASS" and .has_evidence == true' <<<"$c44_row_evid" >/dev/null 2>&1 \
        || c44_errs="$c44_errs\nadmission lane: a tool_response citing src/a.py:12 did not record verdict=PASS with has_evidence=true, so the evidence test is not reading path:line references. Row: $c44_row_evid"
    fi

    # The context the model actually sees. A field in a log file nobody reads is not an
    # admission control; the UNVERIFIED prefix is the half that lands in the transcript, and it
    # has to be present on the bare claim and absent on the cited one -- a hook that emits it
    # unconditionally is a hook that has stopped discriminating, and reads identical to a working
    # one if only the positive case is asserted.
    c44_ctx_bare=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$c44_out_bare" 2>/dev/null)
    c44_ctx_evid=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$c44_out_evid" 2>/dev/null)
    case "$c44_ctx_bare" in
      UNVERIFIED:*) ;;
      *) c44_errs="$c44_errs\nadmission lane: a verdict with no evidence produced no hookSpecificOutput.additionalContext beginning with \"UNVERIFIED:\" -- the claim reaches the transcript uncontradicted. Hook stdout was: ${c44_out_bare:-<empty>}" ;;
    esac
    case "$c44_ctx_evid" in
      UNVERIFIED:*) c44_errs="$c44_errs\nadmission lane: an evidenced verdict was still flagged UNVERIFIED, so the flag fires on every dispatch and carries no information. Hook stdout was: ${c44_out_evid:-<empty>}" ;;
      *) ;;
    esac

    unset VSTACK_REPLAY_LOG VSTACK_DELEGATION_LOG

    c44_rreplay_after=0; [ -f "$c44_real_replay" ] && c44_rreplay_after=$(wc -l < "$c44_real_replay" 2>/dev/null | tr -d ' ')
    c44_rdeleg_after=0; [ -f "$c44_real_deleg" ] && c44_rdeleg_after=$(wc -l < "$c44_real_deleg" 2>/dev/null | tr -d ' ')
    [ "$c44_rreplay_before" = "$c44_rreplay_after" ] \
      || c44_errs="$c44_errs\nthe operator's real replay log changed ($c44_rreplay_before -> $c44_rreplay_after lines) -- fixture rows leaked into it"
    [ "$c44_rdeleg_before" = "$c44_rdeleg_after" ] \
      || c44_errs="$c44_errs\nthe operator's real delegation log changed ($c44_rdeleg_before -> $c44_rdeleg_after lines) -- fixture rows leaked into it"

    rm -rf "$c44_replay_dir" "$c44_deleg_dir" 2>/dev/null

    # Static: the wiring that installs the reader. Anchored on the object key the same way check
    # 11 anchors on it -- `grep -q dispatch-counter.sh install.sh` proves the string is present
    # somewhere in the file, not that it sits under a PostToolUse matcher naming both tool names,
    # and a hook wired to the wrong event, or wired with only one of the two names, would pass
    # that weaker grep and fail every session that dispatches the other way.
    prog=$(sed -n "/^  jq -s --arg h /,/^  ' \"\$US\"/p" install.sh)
    if [ -z "$prog" ]; then
      c44_errs="$c44_errs\ncould not extract the hook rebuild program from install.sh"
    else
      c44_post=$(printf '%s' "$prog" | sed -n '/PostToolUse: \[/,/Stop: \[/p')
      c44_ctx=$(printf '%s' "$c44_post" | grep -B2 'dispatch-counter\.sh')
      c44_im=$(printf '%s' "$c44_ctx" | grep -oE 'matcher:"[^"]*"' | tail -1 | sed -E 's/^matcher:"(.*)"$/\1/')
      case "$c44_im" in
        *Agent*Task*|*Task*Agent*) ;;
        *) c44_errs="$c44_errs\ninstall.sh: dispatch-counter.sh is not wired under a PostToolUse matcher naming both Agent and Task (matcher: ${c44_im:-none found})" ;;
      esac
      # 1.71.0: the same hook writes skill_load rows, which only exist if the matcher also names
      # Skill. settings.json carried the new matcher first while install.sh kept the old one, and
      # the two-name pattern above stayed green through it: an installer got no skill rows at all.
      case $c44_im in
        *Skill*) ;;
        *) c44_errs="$c44_errs\ninstall.sh: dispatch-counter.sh matcher does not name Skill, so installs record no skill_load rows (matcher: ${c44_im:-none found})" ;;
      esac

      # Direction 4 (pin, not fix): a failed dispatch is invisible today only because
      # dispatch-counter.sh is not wired under PostToolUseFailure -- the hook's own jq never
      # branches on hook_event_name, so wiring it there would feed it a payload shaped for
      # PostToolUse (tool_response) when the runtime actually sends `.error` on failure. This
      # pins the current wiring so a future change that starts routing this hook to
      # PostToolUseFailure -- silently making failures visible, or silently crashing on the
      # unexpected shape -- shows up here instead of shipping unnoticed either way.
      c44_ptf_i=$(printf '%s' "$prog" | sed -n '/PostToolUseFailure: \[/,/} as \$ours/p')
      printf '%s' "$c44_ptf_i" | grep -q 'dispatch-counter\.sh' \
        && c44_errs="$c44_errs\ninstall.sh: dispatch-counter.sh is now wired under PostToolUseFailure -- it was built for PostToolUse payload shape only; either update it to read .error and this comment, or this is a wiring accident"
    fi

    c44_sm=$(jq -r '.hooks.PostToolUse[]? | select(any(.hooks[]?.command // ""; test("dispatch-counter\\.sh"))) | .matcher // ""' claude/settings.json 2>/dev/null)
    case "$c44_sm" in
      *Agent*Task*|*Task*Agent*) ;;
      *) c44_errs="$c44_errs\nclaude/settings.json: dispatch-counter.sh is not wired under a PostToolUse matcher naming both Agent and Task (matcher: ${c44_sm:-none found})" ;;
    esac
    case $c44_sm in
      *Skill*) ;;
      *) c44_errs="$c44_errs\nclaude/settings.json: dispatch-counter.sh matcher does not name Skill, so no skill_load rows land (matcher: ${c44_sm:-none found})" ;;
    esac

    c44_ptf=$(jq -r '.hooks.PostToolUseFailure[]? | select(any(.hooks[]?.command // ""; test("dispatch-counter\\.sh"))) | .matcher // "FOUND"' claude/settings.json 2>/dev/null)
    [ -z "$c44_ptf" ] \
      || c44_errs="$c44_errs\nclaude/settings.json: dispatch-counter.sh is now wired under PostToolUseFailure -- see the install.sh check above for why that needs a deliberate decision, not an automatic pass"

    # Generalized one step: every ${TMPDIR:-/tmp}/vstack-<name> path claude/statusline.sh reads
    # must be mentioned by at least one shipped claude/hooks/*.sh script -- a candidate writer.
    # This states the dispatch counter's own defect shape once, generically, so a second reader
    # added the same way cannot ship dark the same way twice. Deliberately weak: "mentions the
    # path" is not "proven to write it" -- the join above is the real evidence for THIS path --
    # but a path nothing else on disk even names is exactly the state this counter was in before
    # dispatch-counter.sh existed, and that state is what this catches.
    c44_prefixes=$(grep -oE '\$\{TMPDIR:-/tmp\}/vstack-[a-zA-Z0-9_-]+' "$sl" | sed 's|^\${TMPDIR:-/tmp}/||' | sort -u)
    for c44_p in $c44_prefixes; do
      c44_found=0
      for c44_h in claude/hooks/*.sh; do
        [ -e "$c44_h" ] || continue
        if grep -qF -- "$c44_p" "$c44_h" 2>/dev/null; then c44_found=1; break; fi
      done
      [ "$c44_found" -eq 1 ] \
        || c44_errs="$c44_errs\n$sl reads \${TMPDIR:-/tmp}/$c44_p<id> but no shipped claude/hooks/*.sh script mentions that path -- a reader with no candidate writer"
    done

    c44_cleanup
    trap - EXIT

    [ -z "$c44_errs" ] \
      && ok "dispatch counter join, both directions" \
      || bad "dispatch counter join, both directions" "$(printf '%b' "$c44_errs")"
  fi
else
  skip "dispatch counter join, both directions" "jq not installed"
fi

# --- 45. uninstall drops vstack's own settings entries and keeps the user's --------------------
# uninstall.sh decided hook ownership by directory prefix: any entry whose command started with
# ~/.claude/hooks was treated as vstack's. That directory is the conventional place for a user's
# own hooks, and vstack installs into it rather than owning it, so a stranger who kept personal
# scripts there had every hook entry pointing at them deleted -- while the scripts themselves
# stayed on disk, and the tool printed "vstack hooks, overrides and unedited policy keys
# removed". A destructive step reporting a narrower scope than the one it performed.
#
# install.sh had the right signal the whole time: the basenames this repo ships, matched with
# endswith("/hooks/" + name). Two halves of one repo disagreed about what ownership means and
# only the install half was ever checked. Both directions here, because a fix that removes
# nothing passes the user's half trivially.
if command -v jq >/dev/null; then
  c45_home=$(mktemp -d)
  c45_errs=""
  c45_hook="$c45_home/.claude/hooks/not-vstacks.sh"
  c45_sl="$c45_home/.claude/not-vstacks-statusline.sh"
  mkdir -p "$c45_home/.claude/hooks"
  printf '#!/bin/bash\nexit 0\n' > "$c45_hook"; chmod +x "$c45_hook"
  printf '#!/bin/bash\nexit 0\n' > "$c45_sl";   chmod +x "$c45_sl"
  jq -n --arg h "$c45_hook" --arg s "$c45_sl" \
    '{theme:"dark",statusLine:{type:"command",command:$s},
      hooks:{Notification:[{hooks:[{type:"command",command:$h}]}]}}' \
    > "$c45_home/.claude/settings.json"
  if HOME="$c45_home" ./install.sh >/dev/null 2>&1; then
    # Free ride on an install that is already running: the agent reference files are pointed at
    # from nine agent prompts by absolute installed path, and until 1.45.0 the user-scope lane
    # copied none of them -- the pointer resolved only on plugin installs. A plan is not the act,
    # so this reads the installed tree rather than install.sh --dry-run's intentions.
    for c45_r in claude/agents/reference/*.ref; do
      [ -e "$c45_r" ] || continue
      [ -f "$c45_home/.claude/agents/reference/$(basename "$c45_r")" ] \
        || c45_errs="$c45_errs\ninstall.sh did not place agents/reference/$(basename "$c45_r"); nine agent prompts name a path that is not there"
    done
  else
    c45_errs="$c45_errs\ninstall.sh failed under a throwaway HOME"
  fi
  if HOME="$c45_home" ./uninstall.sh --yes >/dev/null 2>&1; then
    jq -e --arg h "$c45_hook" '[.hooks.Notification[]?.hooks[]?.command] | index($h) != null' \
      "$c45_home/.claude/settings.json" >/dev/null 2>&1 \
      || c45_errs="$c45_errs\nthe user's own Notification hook is gone: uninstall removed an entry it does not own"
    jq -e --arg s "$c45_sl" '(.statusLine.command? // "") == $s' \
      "$c45_home/.claude/settings.json" >/dev/null 2>&1 \
      || c45_errs="$c45_errs\nthe user's own statusLine is gone: uninstall removed a key it does not own"
    for c45_f in claude/hooks/*.sh; do
      [ -e "$c45_f" ] || continue
      c45_b=$(basename "$c45_f")
      if jq -e --arg b "$c45_b" '[.. | .command? // empty] | any(endswith("/hooks/" + $b))' \
           "$c45_home/.claude/settings.json" >/dev/null 2>&1; then
        c45_errs="$c45_errs\n$c45_b is still wired after uninstall -- vstack left its own hook behind"
      fi
    done
  else
    c45_errs="$c45_errs\nuninstall.sh failed under a throwaway HOME"
  fi
  rm -rf "$c45_home"
  [ -z "$c45_errs" ] \
    && ok "uninstall keeps foreign settings, drops its own" \
    || bad "uninstall keeps foreign settings, drops its own" "$(printf '%b' "$c45_errs")"
else
  skip "uninstall keeps foreign settings, drops its own" "jq not installed"
fi

# --- 46. nothing under claude/agents/ loads as an agent by accident ----------------------------
# Claude Code walks an agent directory recursively and loads every *.md at any depth. Confirmed
# against the shipped binary, not inferred:
#   if(d.isDirectory())return a(p,[...c,d.name]);if(d.isFile()&&d.name.toLowerCase().endsWith(".md")
# marketplace.json sets "source": "./claude", so a reference file written as
# claude/agents/reference/ENVIRONMENT.md would install as a plugin agent named
# vstack:reference:ENVIRONMENT with the description auto-filled "Agent from vstack plugin" --
# a nameless entry sitting in the dispatcher's list next to the fourteen real ones. This repo has
# measured that two entries claiming the same ground suppress each other; an entry claiming
# nothing at all has never been measured and is not worth finding out by accident.
#
# So the extension is load-bearing. It is the kind of decision that is obvious to whoever made it
# and invisible to whoever renames the file six months later, which is what this check is for.
# Both directions: the tree must be clean now, and the detector must catch a planted one.
c46_errs=""
c46_stray=$(find claude/agents -mindepth 2 -name '*.md' 2>/dev/null | sort)
[ -z "$c46_stray" ] || c46_errs="$c46_errs\n$(printf '%s' "$c46_stray" | sed 's/^/  loads as a nameless plugin agent: /')"
c46_probe=$(mktemp -d)
mkdir -p "$c46_probe/agents/reference"
: > "$c46_probe/agents/reference/planted.md"
[ -n "$(find "$c46_probe/agents" -mindepth 2 -name '*.md' 2>/dev/null)" ] \
  || c46_errs="$c46_errs\n  the detector did not find a planted nested .md -- it measures nothing"
rm -rf "$c46_probe"
# The reference files have to actually reach a repo through the overlay lane, or the pointer in
# nine agent prompts names a path that is not there.
if command -v git >/dev/null && [ -d claude/agents/reference ]; then
  c46_dest=$(mktemp -d)
  git -C "$c46_dest" init -q 2>/dev/null
  if ./overlay.sh "$c46_dest" >/dev/null 2>&1; then
    for c46_f in claude/agents/reference/*.ref; do
      [ -e "$c46_f" ] || continue
      [ -f "$c46_dest/.claude/agents/reference/$(basename "$c46_f")" ] \
        || c46_errs="$c46_errs\n  overlay.sh did not place $(basename "$c46_f"); the pointer in the agent prompts resolves to nothing"
    done
  else
    c46_errs="$c46_errs\n  overlay.sh failed against a scratch repo"
  fi
  rm -rf "$c46_dest"
fi
[ -z "$c46_errs" ] \
  && ok "no accidental agents under claude/agents (references ship as .ref)" \
  || bad "no accidental agents under claude/agents (references ship as .ref)" "$(printf '%b' "$c46_errs")"

# --- 47. every hook the plugin lane ships runs in the plugin lane ------------------------------
# The marketplace lane installs skills, agents, commands and claude/hooks/hooks.json into the
# plugin cache. It installs no CLI wrappers, no ~/.config/agents, and merges nothing into
# ~/.claude/settings.json. A hook wired into hooks.json therefore has to work with the plugin
# cache and nothing else.
#
# verify-gate.sh did not. It refuses to run an untrusted .claude/verify.sh and tells the operator
# to run `vstack trust` -- a command only the full install provides -- so in this lane its only
# reachable outcome was naming a command the user does not have. It shipped that way while
# README's component table said the lane installed 0 hooks. Two lanes, two contracts, neither
# checked against the other.
#
# So: run every hooks.json script the way the plugin lane runs it. HOME is an empty sandbox with
# no ~/.config/agents, and PATH is scrubbed of this repo's own wrappers, which is the difference
# between "works here because the developer has the full install" and "works for a stranger".
if command -v jq >/dev/null && command -v git >/dev/null; then
  c47_errs=""
  c47_root=$(mktemp -d); c47_home=$(mktemp -d)
  cp -R claude/hooks "$c47_root/hooks" 2>/dev/null
  chmod 755 "$c47_root"/hooks/*.sh 2>/dev/null
  # The sandbox cwd must LOOK like a repo with a gate in it, or a Stop hook that only speaks when
  # it finds a .claude/verify.sh stays silent and this check passes over it without measuring
  # anything. That silence is what a thin fixture buys: the hook does nothing, nothing is wrong.
  mkdir -p "$c47_home/.claude"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$c47_home/.claude/verify.sh"
  chmod 755 "$c47_home/.claude/verify.sh"
  # PATH without the vstack wrappers: a stranger's machine, not this one.
  c47_path=$(printf '%s' "$PATH" | tr ':' '\n' \
             | grep -v "$HOME/.config/agents/bin" | grep -v "$PWD/bin" | tr '\n' ':')
  c47_run(){ # <script> <event-json>  -> prints "rc|stdout"
    _o=$(printf '%s' "$2" | env -i HOME="$c47_home" PATH="$c47_path" \
           CLAUDE_PLUGIN_ROOT="$c47_root" VSTACK_PROFILE=skills \
           TMPDIR="$c47_home" bash "$1" 2>/dev/null); printf '%s|%s' "$?" "$_o"; }

  c47_scripts=$(jq -r '.hooks[][]?.hooks[]?.command' claude/hooks/hooks.json 2>/dev/null \
                | grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' | sed 's|hooks/||' | sort -u)
  if [ -z "$c47_scripts" ]; then
    c47_errs="$c47_errs\ncould not extract any hook script from claude/hooks/hooks.json"
  fi
  for c47_s in $c47_scripts; do
    [ -f "$c47_root/hooks/$c47_s" ] || { c47_errs="$c47_errs\n$c47_s: named by hooks.json, not shipped"; continue; }
    case "$c47_s" in
      inject-session-context.sh) c47_ev='{"hook_event_name":"SessionStart","session_id":"c47","cwd":"'"$c47_home"'","source":"startup"}' ;;
      *)                         c47_ev='{"hook_event_name":"Stop","session_id":"c47","cwd":"'"$c47_home"'","stop_hook_active":false}' ;;
    esac
    c47_res=$(c47_run "$c47_root/hooks/$c47_s" "$c47_ev")
    c47_rc=${c47_res%%|*}; c47_out=${c47_res#*|}
    [ "$c47_rc" = "0" ] || c47_errs="$c47_errs\n$c47_s: exit $c47_rc in a plugin-only lane"
    # Empty is fine (a hook with nothing to say). Non-empty must be JSON Claude Code can read.
    if [ -n "$c47_out" ] && ! printf '%s' "$c47_out" | jq -e . >/dev/null 2>&1; then
      c47_errs="$c47_errs\n$c47_s: emitted non-JSON in a plugin-only lane"
    fi
    # The real defect: telling the operator to run something this lane never installed.
    for c47_w in vstack doctor; do
      if printf '%s' "$c47_out" | grep -qE "(run|Run) [\`']?$c47_w " 2>/dev/null; then
        c47_errs="$c47_errs\n$c47_s: tells the operator to run '$c47_w', which the plugin lane does not install"
      fi
    done
  done

  # Positive control. The scan above is a grep over hook output, and a grep that has stopped
  # matching reports the same clean result as a lane with nothing wrong in it. Plant a hook that
  # commits the exact defect and require the scan to see it.
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"x\\":\\"run vstack trust to arm this\\"}"\n' \
    > "$c47_root/hooks/c47-probe.sh"
  chmod 755 "$c47_root/hooks/c47-probe.sh"
  c47_p=$(c47_run "$c47_root/hooks/c47-probe.sh" '{"hook_event_name":"Stop"}')
  printf '%s' "${c47_p#*|}" | grep -qE "(run|Run) [\`']?vstack " 2>/dev/null \
    || c47_errs="$c47_errs\npositive control: the planted 'run vstack trust' hook was NOT caught — this scan measures nothing"
  rm -rf "$c47_root" "$c47_home"

  [ -z "$c47_errs" ] \
    && ok "plugin-lane hooks run standalone ($(printf '%s' "$c47_scripts" | grep -c .) script(s), no full-install dependency)" \
    || bad "plugin-lane hooks run standalone" "$(printf '%b' "$c47_errs")"
else
  skip "plugin-lane hooks run standalone" "jq or git not installed"
fi

# --- 48. the inventory contract matches what the tree actually ships ---------------------------
# claude/inventory.json is a check-time oracle: nothing shipped reads it, install.sh keeps
# deriving what it does straight from the filesystem exactly as before the file existed. The
# only value it has is that something independent regenerates the same lists/counts and diffs —
# tests/inventory-contract.sh is that independent half; this wires it into the gate.
if command -v jq >/dev/null 2>&1; then
  c48_errs=""
  c48_out=$(./tests/inventory-contract.sh 2>&1)
  c48_rc=$?
  [ "$c48_rc" -eq 0 ] || c48_errs="$c48_errs\n$c48_out"

  # doctor's plugin-lane hook text, cross-checked against the contract rather than a number
  # copied into this check by hand. c842cc2 fixed the README's plugin-lane row and added check
  # 47 to run every plugin-lane hook standalone; bin/doctor's own prose was not part of that fix
  # and, if it still claims the lane ships no hooks, disagrees with a component the contract
  # itself (claude/inventory.json's profiles.plugin.ships) says the lane does ship.
  if jq -e '.profiles.plugin.ships | index("hooks")' claude/inventory.json >/dev/null 2>&1; then
    if grep -qE '"hooks" +"not part of the plugin lane by design' bin/doctor 2>/dev/null; then
      c48_errs="$c48_errs\nbin/doctor still says hooks are 'not part of the plugin lane by design'; claude/inventory.json's profiles.plugin.ships names hooks as a component that lane does ship (2 routing hooks as of c842cc2)"
    fi
  fi

  # ATTRIBUTION provenance: the union of components.skills.provenance's six source lists must
  # equal components.skills.members exactly, each source list's length must equal its
  # ATTRIBUTION.md section heading count, and the sum of those must equal the skill count.
  c48_prov_union=$(jq -r '.components.skills.provenance[].skills[]' claude/inventory.json 2>/dev/null | sort -u)
  c48_members=$(jq -r '.components.skills.members[]' claude/inventory.json 2>/dev/null | sort -u)
  if [ "$c48_prov_union" != "$c48_members" ]; then
    c48_added=$(comm -23 <(printf '%s\n' "$c48_prov_union") <(printf '%s\n' "$c48_members") 2>/dev/null)
    c48_missing=$(comm -13 <(printf '%s\n' "$c48_prov_union") <(printf '%s\n' "$c48_members") 2>/dev/null)
    c48_msg="components.skills.provenance's six source lists do not union to components.skills.members."
    [ -n "$c48_added" ]   && c48_msg="$c48_msg\n  in provenance, not in members: $(printf '%s' "$c48_added" | tr '\n' ' ')"
    [ -n "$c48_missing" ] && c48_msg="$c48_msg\n  in members, not in any provenance list: $(printf '%s' "$c48_missing" | tr '\n' ' ')"
    c48_errs="$c48_errs\n$c48_msg"
  fi
  c48_prov_sum=0
  for c48_src in $(jq -r '.components.skills.provenance | keys[]' claude/inventory.json 2>/dev/null); do
    c48_n=$(jq -r --arg s "$c48_src" '.components.skills.provenance[$s].skills | length' claude/inventory.json 2>/dev/null)
    # ATTRIBUTION.md's own heading text does not spell the provenance key verbatim (the key is
    # "vercel-labs", the heading says "Vercel Labs"), so map key -> the substring its heading
    # actually contains rather than assume they match.
    case "$c48_src" in
      (pstack)      c48_hpat='pstack' ;;
      (superpowers) c48_hpat='Superpowers' ;;
      (impeccable)  c48_hpat='Impeccable' ;;
      (vercel-labs) c48_hpat='Vercel Labs' ;;
      (mattpocock)  c48_hpat='Matt Pocock' ;;
      (original)    c48_hpat='Original' ;;
      (*)           c48_hpat="$c48_src" ;;
    esac
    c48_hn=$(grep -E "^#+ .*$c48_hpat" claude/skills/ATTRIBUTION.md 2>/dev/null \
             | grep -oE '\([0-9]+\)' | head -1 | tr -d '()')
    if [ -z "$c48_hn" ]; then
      c48_errs="$c48_errs\nclaude/skills/ATTRIBUTION.md has no '(N)' section heading matching provenance source '$c48_src'"
    elif [ "$c48_hn" != "$c48_n" ]; then
      c48_errs="$c48_errs\ncomponents.skills.provenance.$c48_src lists $c48_n skill(s); claude/skills/ATTRIBUTION.md's matching heading says ($c48_hn)"
    fi
    c48_prov_sum=$((c48_prov_sum + c48_n))
  done
  c48_skill_count=$(jq -r '.components.skills.count' claude/inventory.json 2>/dev/null)
  if [ "$c48_prov_sum" != "$c48_skill_count" ]; then
    c48_errs="$c48_errs\nclaude/skills/ATTRIBUTION.md provenance: the six source lists sum to $c48_prov_sum skills, components.skills.count says $c48_skill_count"
  fi
  c48_attr_sum=$(grep -oE '\([0-9]+\)' claude/skills/ATTRIBUTION.md 2>/dev/null | tr -d '()' | awk '{s+=$1} END{print s+0}')
  if [ "$c48_attr_sum" != "$c48_skill_count" ]; then
    c48_errs="$c48_errs\nclaude/skills/ATTRIBUTION.md's own '(N)' section headings sum to $c48_attr_sum, components.skills.count says $c48_skill_count"
  fi

  [ -z "$c48_errs" ] \
    && ok "inventory contract matches the tree" \
    || bad "inventory contract matches the tree" "$(printf '%b' "$c48_errs")"
else
  skip "inventory contract matches the tree" "jq not installed"
fi

# --- 49. doctor's CI lane answers for the commit you are on, not for the branch ---------------
# The network call stays in bin/doctor -- this file is offline and hermetic by design, which is
# why the release-reachability and CI questions live there. What can be gated here is the
# DECISION, exercised through a `gh` stub with no network and no repository state.
#
# Both directions, because the failure this catches was a green: `gh run list --branch main
# --limit 1` reads a moving reference and takes whatever is newest under it, so a run belonging
# to an older commit spoke for the one you were standing on. Three of this session's defects
# reached main because a remote verdict was not read; this is the check that makes the reading
# itself falsifiable.
if command -v jq >/dev/null 2>&1 && [ -x bin/doctor ]; then
  c49_errs=""
  c49_dir=$(mktemp -d)
  c49_head=$(git rev-parse HEAD 2>/dev/null)
  c49_other=0000000000000000000000000000000000000000
  c49_line(){ # <rows-json> -> doctor's CI line
    cat > "$c49_dir/gh" <<C49STUB
#!/bin/sh
case "\$*" in
  *"run list"*) printf '%s\n' '$1' ;;
  *"api"*)      printf '%s\n' '$1' ;;
  *)            exit 0 ;;
esac
C49STUB
    chmod +x "$c49_dir/gh"
    # VSTACK_DIR pins doctor to this checkout; resolve_vstack_repo() otherwise prefers the path
    # install.sh last recorded, and the gate would grade a tree it is not testing.
    PATH="$c49_dir:$PATH" VSTACK_DIR="$PWD" bash ./bin/doctor 2>&1 | grep -E '^CI' | head -1
  }
  c49_row(){ printf '[{"headSha":"%s","name":"verify","status":"%s","conclusion":"%s","displayTitle":"t","databaseId":1}]' "$1" "$2" "$3"; }

  c49_n=0
  c49_want(){ # <label> <line> <want-glyph-or-none>
    c49_n=$((c49_n + 1))
    case "$3" in
      (green)  case "$2" in (*'✔'*) ;; (*) c49_errs="$c49_errs\n  $1: wanted a green verdict, got: $2" ;; esac ;;
      (red)    case "$2" in (*'✖'*) ;; (*) c49_errs="$c49_errs\n  $1: wanted a failure verdict, got: $2" ;; esac ;;
      (none)   case "$2" in (*'✔'*|*'✖'*) c49_errs="$c49_errs\n  $1: wanted no verdict, got: $2" ;; (*) ;; esac ;;
    esac
  }

  if [ -z "$c49_head" ]; then
    skip "doctor's CI lane answers for HEAD" "not a git checkout, so there is no HEAD to answer about"
  else
    c49_want "a green run for another commit"      "$(c49_line "$(c49_row "$c49_other" completed success)")" none
    c49_want "a green run for this commit"         "$(c49_line "$(c49_row "$c49_head"  completed success)")" green
    c49_want "a failed run for this commit"        "$(c49_line "$(c49_row "$c49_head"  completed failure)")" red
    c49_want "a run still going for this commit"   "$(c49_line "$(c49_row "$c49_head"  in_progress '')")"    none
    c49_want "no run for this commit at all"       "$(c49_line '[]')"                                        none
    [ "$c49_n" -eq 5 ] || c49_errs="$c49_errs\n  only $c49_n of 5 cases were exercised; the case list has collapsed"
    [ -z "$c49_errs" ] \
      && ok "doctor's CI lane answers for HEAD ($c49_n cases, both directions, no network)" \
      || bad "doctor's CI lane answers for HEAD" "$(printf '%b' "$c49_errs")"
  fi
  rm -rf "$c49_dir"
else
  skip "doctor's CI lane answers for HEAD" "jq not installed or bin/doctor not executable"
fi

# --- 50. every CI job is a required check, and every required check is a CI job --------------
# The release gate reads the conclusion of each name in release.yml's REQUIRED_CHECKS. Nothing
# connected that list to the workflow that produces the jobs, so adding a lane to verify.yml
# shipped a lane whose verdict no gate ever read: it could be red on every commit and the
# release would still publish. That is not hypothetical here -- `install-macos` was added, went
# red on its first run, and the failure was noticed by reading a log by hand.
#
# Both directions, because each is a different lie. A job missing from REQUIRED_CHECKS is an
# unread verdict. A name in REQUIRED_CHECKS with no job behind it never produces a run at all,
# and require-checks-green.sh reports that as UNDECIDED forever -- a release that can never
# publish, which is the deadlock this session already fixed once from the other end.
_c50_wf=.github/workflows/verify.yml
_c50_rl=.github/workflows/release.yml
if [ -f "$_c50_wf" ] && [ -f "$_c50_rl" ]; then
  c50_errs=""
  # Job keys are the two-space-indented mapping keys inside the top-level `jobs:` block. Scoped
  # to that block on purpose: `on:` carries `push:` and `pull_request:` at the same indent, and
  # a selector that only matched indentation would call those two CI jobs.
  _c50_jobs=$(awk '
    /^jobs:[[:space:]]*$/ {inj=1; next}
    inj && /^[^[:space:]#]/ {inj=0}
    inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {gsub(/[: ]/,""); print}
  ' "$_c50_wf" | sort)
  _c50_req=$(sed -n 's/^  REQUIRED_CHECKS:[[:space:]]*//p' "$_c50_rl" | head -1 | tr ' ' '\n' | sed '/^$/d' | sort)
  # Neither list may be empty: an empty selector makes both comparisons below vacuously true,
  # which is the exact shape this file catalogues.
  if [ -z "$_c50_jobs" ]; then
    c50_errs="$c50_errs\nno jobs parsed out of $_c50_wf -- the selector matched nothing, so the comparison below would pass on any workflow at all"
  fi
  if [ -z "$_c50_req" ]; then
    c50_errs="$c50_errs\nno names parsed out of $_c50_rl's REQUIRED_CHECKS -- the release gate would be comparing against an empty list"
  fi
  # A job can also be read INDIRECTLY: verify.yml's `verify` is a join that fans in verify-core
  # and the falsify shards and fails unless each one succeeded. Requiring those four by name
  # instead would deadlock the release -- `falsify` is a matrix job, so its check-runs are named
  # `falsify (0, ...)` and a required context spelled `falsify` never matches anything, which
  # require-checks-green.sh reports as MISSING forever. That is the same deadlock this check's
  # own second direction exists to prevent, so the model has to admit the join.
  #
  # It is not admitted on the strength of a `needs:` edge. A job can appear in `needs:` and have
  # its result ignored -- with `if: always()` the dependent runs anyway, and `echo` of a result
  # reads it without acting on it. So each candidate is proved by EXECUTION: the required job's
  # own run: script is extracted, its `${{ needs.X.result }}` templates are filled in with
  # success everywhere except the one job under test, and the script must exit non-zero. The
  # all-success run is the positive control; without it a join hardwired to exit 1 would "prove"
  # every job gated.
  _c50_runof(){ # <job> -> that job's run: script, dedented, from $_c50_wf
    awk -v j="$1" '
      $0 ~ "^  " j ":[[:space:]]*$" {inj=1; next}
      inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {inj=0}
      inj && /^[[:space:]]*run:[[:space:]]*\|[[:space:]]*$/ {
        match($0, /[^ ]/); ind=RSTART; inr=1; next
      }
      inr {
        if ($0 ~ /^[[:space:]]*$/) { print ""; next }
        match($0, /[^ ]/)
        if (RSTART <= ind) { inr=0; next }
        print substr($0, ind+2)
      }
    ' "$_c50_wf"
  }
  _c50_gates(){ # <required-job> <job-under-test> -> 0 if that job failing makes the script fail
    _g_script=$(_c50_runof "$1")
    [ -n "$_g_script" ] || return 1
    # ONLY a join's script is ever executed. Without this guard the loop below ran the first
    # run: block of every required job, and install-macos's first run: block *is*
    # `./.claude/verify.sh` -- so the gate executed itself, from inside itself, once per
    # candidate job. It never fired locally because $RUNNER_TEMP is unset here, which made that
    # line's redirect fail; on a runner RUNNER_TEMP is set, there is no `set -e` in an extracted
    # block, and a missing `brew` on ubuntu just carries on to the recursion. It hung seven CI
    # shards for 78 minutes. A job that never mentions needs.<x>.result cannot be gating on one,
    # so there is nothing here worth executing it to find out.
    case "$_g_script" in *'needs.'*'.result'*) ;; *) return 1 ;; esac
    # Belt and braces: even a real join is someone else's shell, and this gate must not be the
    # thing that hangs. No timeout(1) on macOS, so bound it with a watchdog subshell.
    _g_run(){ ( "$@" ) & _g_p=$!; ( sleep 20; kill -9 "$_g_p" 2>/dev/null ) 2>/dev/null & _g_w=$!
              wait "$_g_p"; _g_rc=$?
              # Reap the watchdog, do not just signal it. An unreaped killed job is reported
              # asynchronously by the shell -- five "Terminated: 15" lines on stderr, at whatever
              # line happens to be running when bash next notices, which is why they read like a
              # crash in an unrelated check. The `wait` collects it and the redirect covers the
              # notification the `wait` itself prints. Signalling alone cannot suppress it: the
              # message comes from this shell reaping the job, not from the job's own stderr.
              { kill "$_g_w" 2>/dev/null; wait "$_g_w"; } 2>/dev/null
              return "$_g_rc"; }
    # every needs.X.result -> success, then the one under test -> failure
    _g_ok=$(printf '%s' "$_g_script" | sed -E 's/\$\{\{[[:space:]]*needs\.[A-Za-z0-9_-]+\.result[[:space:]]*\}\}/success/g')
    _g_bad=$(printf '%s' "$_g_script" \
      | sed -E "s/\\\$\\{\\{[[:space:]]*needs\\.$2\\.result[[:space:]]*\\}\\}/failure/g" \
      | sed -E 's/\$\{\{[[:space:]]*needs\.[A-Za-z0-9_-]+\.result[[:space:]]*\}\}/success/g')
    # any surviving ${{ ... }} would make bash choke on its own syntax rather than decide
    case "$_g_bad" in *'${{'*) return 1 ;; esac
    _g_f=$(mktemp); printf '%s\n' "$_g_ok"  > "$_g_f"
    _g_run bash "$_g_f" >/dev/null 2>&1 || { rm -f "$_g_f"; return 1; }   # positive control
    printf '%s\n' "$_g_bad" > "$_g_f"
    _g_run bash "$_g_f" >/dev/null 2>&1 && { rm -f "$_g_f"; return 1; }   # must fail on its red
    rm -f "$_g_f"
    return 0
  }

  # Self-check on the executor itself, before it is trusted to answer anything. install-macos is
  # a required job whose first run: block is `./.claude/verify.sh`, so "refused, and refused
  # WITHOUT being run" is the difference between a gate and a fork bomb. Proved by sentinel: the
  # block writes into $RUNNER_TEMP, so an empty sandbox after the call is evidence it never ran,
  # not merely that it returned the right number.
  if [ -n "$_c50_req" ]; then
    _c50_sent=$(mktemp -d)
    if RUNNER_TEMP="$_c50_sent" _c50_gates install-macos falsify 2>/dev/null; then
      c50_errs="$c50_errs\ninstall-macos was accepted as a join gating falsify, but its script asserts no needs.<x>.result at all"
    fi
    [ -z "$(ls -A "$_c50_sent" 2>/dev/null)" ] \
      || c50_errs="$c50_errs\nthe join executor ran install-macos's run: block (it wrote into RUNNER_TEMP) -- that block is ./.claude/verify.sh, so the gate would be running itself"
    rm -rf "$_c50_sent"
  fi

  if [ -n "$_c50_jobs" ] && [ -n "$_c50_req" ]; then
    # Fold in every job a required job provably gates on, then compare what is left.
    _c50_covered="$_c50_req"
    for _c50_j in $_c50_jobs; do
      case "
$_c50_req
" in *"
$_c50_j
"*) continue ;; esac
      for _c50_r in $_c50_req; do
        if _c50_gates "$_c50_r" "$_c50_j"; then
          _c50_covered="$_c50_covered
$_c50_j"
          break
        fi
      done
    done
    _c50_covered=$(printf '%s\n' "$_c50_covered" | sed '/^$/d' | sort -u)
    _c50_unread=$(comm -23 <(printf '%s\n' "$_c50_jobs") <(printf '%s\n' "$_c50_covered"))
    _c50_phantom=$(comm -13 <(printf '%s\n' "$_c50_jobs") <(printf '%s\n' "$_c50_req"))
    [ -z "$_c50_unread" ] \
      || c50_errs="$c50_errs\nCI job(s) no gate reads: $(printf '%s' "$_c50_unread" | tr '\n' ' ') -- add them to REQUIRED_CHECKS in $_c50_rl, or fan them into a required job that asserts needs.<job>.result and exits non-zero on it"
    [ -z "$_c50_phantom" ] \
      || c50_errs="$c50_errs\nREQUIRED_CHECKS name(s) with no job behind them: $(printf '%s' "$_c50_phantom" | tr '\n' ' ') -- nothing will ever report for these, so the gate stays UNDECIDED forever"
  fi
  _c50_njobs=$(printf '%s' "$_c50_jobs" | grep -c . )
  [ -z "$c50_errs" ] \
    && ok "every CI job is a required check ($_c50_njobs jobs, both directions; $(printf '%s\n' "$_c50_covered" | grep -c .) covered directly or by a proved join)" \
    || bad "every CI job is a required check" "$(printf '%b' "$c50_errs")"
else
  bad "every CI job is a required check" "$_c50_wf or $_c50_rl is missing -- CI itself is gone, which is a failure and not an environment fact"
fi

# --- 51. the one destructive step in the release workflow decides correctly -------------------
# cleanup-on-failed-gate force-deletes a candidate tag from origin. It is the only step in this
# repository that destroys something a human might not be able to reconstruct, and until now it
# was also the only step whose decision could not be run: the whole rule lived in a GitHub
# Actions `if:` expression. It was wrong in production on 2026-08-27 -- it deleted the tag for a
# gate that was UNDECIDED rather than failed, and since verify cannot go green until the tag is
# on origin, no tag could survive long enough to earn the green it needed.
#
# The rule now lives in .github/scripts/should-delete-candidate-tag.sh and tests/release-cleanup.sh
# is its truth table. This check runs that table BOTH WAYS: against the real decider, which must
# pass, and against a copy with the undecided carve-out removed, which must fail. A truth table
# that cannot go red proves nothing about the decider it points at -- and that is not a
# hypothetical concern in this file, it is entry after entry in
# docs/checks-that-inherit-their-answer.md.
if [ -x tests/release-cleanup.sh ] && [ -f .github/scripts/should-delete-candidate-tag.sh ]; then
  c51_errs=""
  ./tests/release-cleanup.sh >/dev/null 2>&1 \
    || c51_errs="$c51_errs\nthe release-cleanup truth table fails against the real decider: $(./tests/release-cleanup.sh 2>&1 | grep '^FAIL' | head -3 | tr '\n' ' ')"
  # Positive control. Remove the carve-out that keeps an undecided tag alive; the table must
  # notice. If it still passes, the table is not reading the decider and nothing above is
  # evidence of anything.
  c51_dir=$(mktemp -d)
  sed 's/if \[ "$gate" = undecided \]; then/if false; then/' \
    .github/scripts/should-delete-candidate-tag.sh > "$c51_dir/broken.sh"
  chmod +x "$c51_dir/broken.sh"
  if cmp -s "$c51_dir/broken.sh" .github/scripts/should-delete-candidate-tag.sh; then
    c51_errs="$c51_errs\nthe control mutation changed nothing -- the sed pattern no longer matches the decider, so the both-directions claim below is vacuous"
  elif RELEASE_CLEANUP_SCRIPT="$c51_dir/broken.sh" ./tests/release-cleanup.sh >/dev/null 2>&1; then
    c51_errs="$c51_errs\nthe truth table passed against a decider with the undecided carve-out deleted -- it is not reading the script it names"
  fi
  rm -rf "$c51_dir"
  [ -z "$c51_errs" ] \
    && ok "release cleanup decides correctly (truth table both directions)" \
    || bad "release cleanup decides correctly" "$(printf '%b' "$c51_errs")"
else
  bad "release cleanup decides correctly" "tests/release-cleanup.sh is not executable or .github/scripts/should-delete-candidate-tag.sh is missing -- the destructive step is back to having no test, which is a failure and not an environment fact"
fi

# --- 52. the bin-scripts suite can actually fail ----------------------------------------------
# tests/bin-scripts.sh prints "38 passed, 0 failed" and nothing had ever asked whether it can
# print anything else. That is the same question tests/gate-falsifiability.sh asks of every gate
# check, and this repository's own history says a suite that has never been watched red is a
# suite nobody has evidence about: bin-scripts itself shipped claiming it never reaches the real
# `claude` CLI while two of its cases did exactly that, undetected until a poison stub was added.
#
# Scoped to the `bg-args` case and to a two-file copy of the tree, which runs in about two
# seconds. The full suite is 17s and the point here is falsifiability, not coverage -- coverage
# is what CI's own bin-scripts step is for.
#
# NOT COVERED, stated rather than skipped: tests/install-matrix.sh has no equivalent control.
# Its cheapest single case measured 2m10s, which does not belong in an offline gate, and it is
# currently red for an unrelated reason (a declared-but-untagged release), so a "must fail when
# broken" control against it would pass without measuring anything. That gap is real and is
# named in docs/checks-that-inherit-their-answer.md rather than papered over here.
if [ -f tests/bin-scripts.sh ] && [ -f bin/claude-bg.sh ]; then
  c52_errs=""
  c52_dir=$(mktemp -d)
  mkdir -p "$c52_dir/bin" "$c52_dir/tests"
  cp bin/claude-bg.sh bin/claude-task.sh "$c52_dir/bin/" 2>/dev/null
  cp tests/bin-scripts.sh "$c52_dir/tests/"
  # Direction one: the suite passes on the tree as it stands. If this fails the suite is telling
  # the truth about a real defect, and the control below would be meaningless anyway.
  ( cd "$c52_dir" && bash tests/bin-scripts.sh bg-args >/dev/null 2>&1 ) \
    || c52_errs="$c52_errs\ntests/bin-scripts.sh bg-args fails against the tree as it stands -- run it directly; either bin/claude-bg.sh has a defect or the suite does"
  # Direction two: break the argument guard the case is about, and the suite must notice.
  sed 's/^if \[ $# -eq 0 \]; then/if false; then/' bin/claude-bg.sh > "$c52_dir/bin/claude-bg.sh"
  if cmp -s "$c52_dir/bin/claude-bg.sh" bin/claude-bg.sh; then
    c52_errs="$c52_errs\nthe control mutation changed nothing -- the no-args guard in bin/claude-bg.sh was reworded, so this check's falsifiability claim is vacuous until the pattern is repointed"
  elif ( cd "$c52_dir" && bash tests/bin-scripts.sh bg-args >/dev/null 2>&1 ); then
    c52_errs="$c52_errs\ntests/bin-scripts.sh passed against a claude-bg.sh whose no-args guard was deleted -- the suite is not reading the script it names"
  fi
  rm -rf "$c52_dir"
  [ -z "$c52_errs" ] \
    && ok "the bin-scripts suite can actually fail (bg-args, both directions; install-matrix uncovered by design, see the check comment)" \
    || bad "the bin-scripts suite can actually fail" "$(printf '%b' "$c52_errs")"
else
  bad "the bin-scripts suite can actually fail" "tests/bin-scripts.sh or bin/claude-bg.sh is missing -- the suite this check proves falsifiable is gone, which is a failure and not an environment fact"
fi

# --- 53. no shell file hashes with a tool only one platform ships -----------------------------
# macOS ships `shasum` and no `sha256sum`. BusyBox and most slim Linux images ship `sha256sum`
# and no `shasum`. A file that calls exactly one of them works on exactly one of this
# repository's three documented platforms, and the failure mode is the bad one: both commands
# write nothing to stdout when absent, so the caller gets the EMPTY STRING rather than an error.
#
# Measured on 2026-08-27, on Alpine, after the lane stopped swallowing its own exit code:
# tests/inventory-contract.sh computed an empty payload digest and reported "the tree's is ."
# That one failed loudly only because the expected digest was non-empty. The same bug in
# tests/gate-falsifiability.sh's no-op-mutation detector compares an empty before-hash against
# an empty after-hash, and two empty strings are equal -- a detector whose entire job is to
# notice that a mutation landed, reporting that none of them did.
#
# The rule is deliberately coarse and cheap: a tracked shell file that names one hasher must
# also name the other. Every real fix here is a two-branch `command -v` fallback, so naming both
# is what a correct file looks like, and naming one is what every instance of this bug looked
# like. It cannot tell a good fallback from a bad one -- check 29 and the suites do that -- but
# it makes the platform-specific call impossible to add without noticing.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  c53_bad=""
  c53_n=0
  for c53_f in $(git ls-files); do
    case "$c53_f" in
      *.sh|bin/*|claude/hooks/*|*.bash) ;;
      *) continue ;;
    esac
    [ -f "$c53_f" ] || continue
    c53_has_a=0; c53_has_b=0
    grep -q 'shasum' "$c53_f" 2>/dev/null && c53_has_a=1
    grep -q 'sha256sum' "$c53_f" 2>/dev/null && c53_has_b=1
    [ "$c53_has_a" = 0 ] && [ "$c53_has_b" = 0 ] && continue
    c53_n=$((c53_n + 1))
    if [ "$c53_has_a" != "$c53_has_b" ]; then
      if [ "$c53_has_a" = 1 ]; then
        c53_bad="$c53_bad\n  $c53_f names shasum and not sha256sum -- returns the empty string on Alpine"
      else
        c53_bad="$c53_bad\n  $c53_f names sha256sum and not shasum -- returns the empty string on macOS"
      fi
    fi
  done
  # A selector that matches nothing passes this check trivially. There are hashers in this tree;
  # if the census ever reads zero, the selector broke, not the tree.
  if [ "$c53_n" -eq 0 ]; then
    bad "hashers work on every documented platform" "no tracked shell file names shasum or sha256sum -- the census is empty, so the comparison above measured nothing"
  elif [ -n "$c53_bad" ]; then
    bad "hashers work on every documented platform" "$(printf 'a missing hasher writes nothing to stdout, so these hash to the empty string instead of failing:%b' "$c53_bad")"
  else
    ok "hashers work on every documented platform ($c53_n file(s), each naming both)"
  fi
else
  bad "hashers work on every documented platform" "not inside a git work tree, so the file census could not run -- an empty census would pass this check while measuring nothing"
fi

# --- 54. the release gate's inputs are actually supplied by the release workflow ---------------
# A reader tested against a hand-made fixture passes forever while its writer does not exist.
# tests/require-checks-green.sh proves the gate honours CANDIDATE_CREATED_AT by setting it
# itself; nothing there can notice that release.yml never sets it in production, and the gate
# reads it with a `:-` default, so unwired it is silently empty and the whole rule is inert.
# That is the shape this file exists to catch, one layer up: a green about a half.
#
# So the census is DERIVED, not listed. Every environment variable require-checks-green.sh
# reads with a default must be named in release.yml, or carry an exemption here with a reason.
# A new knob added to the script is therefore unwired-and-red by construction rather than
# unwired-and-quiet, which is the only ordering that survives someone adding one in a hurry.
c54_s=".github/scripts/require-checks-green.sh"
c54_w=".github/workflows/release.yml"
# Reading the poll cadence is not reading a verdict: REQUIRE_CHECKS_POLL_SECONDS changes how
# often the gate asks, never what answer it gets or what the caller does with it. Exempt with
# that reason stated, so the exemption can be argued with rather than inferred from silence.
C54_EXEMPT="REQUIRE_CHECKS_POLL_SECONDS"
if [ ! -f "$c54_s" ] || [ ! -f "$c54_w" ]; then
  bad "the release gate's inputs are supplied by the workflow" "$c54_s or $c54_w is missing, so the join between the gate and its caller could not be read at all"
else
  c54_vars=$(sed -n 's/^[A-Za-z_][A-Za-z0-9_]*=\${\([A-Z][A-Z0-9_]*\):-.*/\1/p' "$c54_s" | sort -u)
  c54_n=0; c54_unwired=""
  for c54_v in $c54_vars; do
    case " $C54_EXEMPT " in (*" $c54_v "*) continue ;; esac
    c54_n=$((c54_n + 1))
    grep -q "$c54_v" "$c54_w" 2>/dev/null \
      || c54_unwired="$c54_unwired\n  $c54_v is read by ${c54_s##*/} but never set in ${c54_w##*/} -- it defaults to empty in production, so the behaviour it controls is off while its test is green"
  done
  if [ "$c54_n" -eq 0 ]; then
    bad "the release gate's inputs are supplied by the workflow" "the gate reads no defaulted environment variable at all -- the extractor stopped matching, so this compared nothing"
  elif [ -n "$c54_unwired" ]; then
    bad "the release gate's inputs are supplied by the workflow" "$(printf 'the gate reads inputs its caller never supplies:%b' "$c54_unwired")"
  else
    ok "the release gate's inputs are supplied by the workflow ($c54_n variable(s) read and wired, 1 exempt)"
  fi
fi

echo
# --- 55. the mtime probe returns an integer on every documented platform ----------------------
# `stat -f` means "file status" on BSD/macOS and "FILESYSTEM status" on GNU coreutils and
# BusyBox. On Linux it ignores %m entirely, prints a five-line block about the mount, and
# EXITS 0 -- so the familiar `stat -f %m "$p" 2>/dev/null || stat -c %Y "$p"` never reaches its
# second branch there. The caller gets a paragraph where it asked for an integer. Measured
# 2026-08-28 in alpine and postgres:16 containers: both printed `File: "/tmp"` as the first of
# five lines and exited 0, and the BusyBox shell then died on the comparison with
# `1781368758: out of range`.
#
# That ordering shipped in four files. Three are lock-staleness reclaims inside hooks whose
# `while ! mkdir` loop is otherwise unbounded, so on Linux an abandoned lock directory is never
# reclaimed and every later invocation of that hook spins forever. A hang, not a wrong number.
#
# Same class as check 53 and checked the harder way: by execution, not by grep. Three stubs
# stand in for the three documented platforms, each reproducing the measured behaviour --
# including the macOS one where `stat -c` is a usage error, which is the honest failure the
# `||` was written for. Four copies of mtime_of() is a deliberate trade: hooks are installed
# standalone and source nothing, so they cannot share a library. Executing every copy against
# every stub is what stops the four drifting apart quietly, and a stat mtime call OUTSIDE
# mtime_of() fails the census, so a fifth copy cannot be added by hand without noticing.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad "the mtime probe returns an integer on every platform" "not inside a git work tree, so the file census could not run -- an empty census would pass this check while measuring nothing"
else
  c55_d=$(mktemp -d 2>/dev/null || echo "/tmp/c55.$$")
  c55_ep=1756339200
  mkdir -p "$c55_d/gnu" "$c55_d/bsd" "$c55_d/none"
  # GNU coreutils and BusyBox behaved identically when measured, so one stub covers both.
  cat > "$c55_d/gnu/stat" <<'C55GNU'
#!/bin/sh
if [ "$1" = "-c" ] && [ "$2" = "%Y" ]; then printf '%s\n' "$C55_EPOCH"; exit 0; fi
if [ "$1" = "-f" ]; then
  printf '  File: "%s"\n    ID: eab9943b4efd9b1d Namelen: 255     Type: overlayfs\n' "$3"
  printf 'Block size: 4096       Fundamental block size: 4096\n'
  printf 'Blocks: Total: 118511122  Free: 117936091  Available: 111897679\n'
  printf 'Inodes: Total: 30179328   Free: 30146270\n'
  exit 0
fi
exit 1
C55GNU
  cat > "$c55_d/bsd/stat" <<'C55BSD'
#!/bin/sh
if [ "$1" = "-f" ] && [ "$2" = "%m" ]; then printf '%s\n' "$C55_EPOCH"; exit 0; fi
echo "stat: illegal option -- c" >&2
exit 1
C55BSD
  # Neither spelling works: the path is gone, or stat is not installed at all. The probe must
  # answer 0 -- an integer the caller can compare -- rather than the empty string, which is
  # what turns `[ "$m" -gt 0 ]` into a shell error instead of a false.
  printf '#!/bin/sh\nexit 1\n' > "$c55_d/none/stat"
  chmod +x "$c55_d/gnu/stat" "$c55_d/bsd/stat" "$c55_d/none/stat"

  c55_n=0; c55_bad=""
  for c55_f in $(git ls-files); do
    case "$c55_f" in
      *.sh|bin/*|claude/hooks/*|*.bash) ;;
      *) continue ;;
    esac
    [ -f "$c55_f" ] || continue
    # Two tracked files name both spellings while probing nothing: this one, in check 55's own
    # platform stubs a few lines below, and the falsifiability suite, in the mutations that put
    # the defect back. Exempted by exact path rather than by a pattern that would also cover a
    # real probe added to either later: an exemption you can argue with beats a regex that
    # quietly grows.
    case "$c55_f" in (.claude/verify.sh|tests/gate-falsifiability.sh) continue ;; esac
    grep -q 'stat -f %m\|stat -c %Y' "$c55_f" 2>/dev/null || continue
    c55_n=$((c55_n + 1))
    c55_fn="$c55_d/fn.sh"
    sed -n '/^mtime_of() {/,/^}/p' "$c55_f" > "$c55_fn"
    if [ ! -s "$c55_fn" ]; then
      c55_bad="$c55_bad\n  $c55_f calls stat for an mtime but defines no mtime_of() -- an inline copy is a copy nothing here executes"
      continue
    fi
    # Every stat mtime call in the file must be inside that function. Count them both ways.
    # Comment lines are excluded: mtime_of's own header quotes both spellings while explaining
    # why the order matters, and prose about a call is not a call.
    c55_all=$(grep -v '^[[:space:]]*#' "$c55_f" | grep -c 'stat -f %m\|stat -c %Y') || c55_all=0
    c55_in=$(grep -v '^[[:space:]]*#' "$c55_fn" | grep -c 'stat -f %m\|stat -c %Y') || c55_in=0
    if [ "$c55_all" -ne "$c55_in" ]; then
      c55_bad="$c55_bad\n  $c55_f has $((c55_all - c55_in)) stat mtime call(s) outside mtime_of() -- outside the function is outside this check"
      continue
    fi
    for c55_p in gnu bsd none; do
      c55_want=$c55_ep
      [ "$c55_p" = none ] && c55_want=0
      c55_got=$(PATH="$c55_d/$c55_p:$PATH" C55_EPOCH="$c55_ep" \
        sh -c ". \"$c55_fn\"; mtime_of \"$c55_d\"" 2>/dev/null)
      if [ "$c55_got" != "$c55_want" ]; then
        c55_bad="$c55_bad\n  $c55_f mtime_of on the $c55_p stub answered [$(printf '%s' "$c55_got" | tr '\n' '|')] and not $c55_want"
      fi
    done
  done
  rm -rf "$c55_d"
  if [ "$c55_n" -eq 0 ]; then
    bad "the mtime probe returns an integer on every platform" "no tracked shell file calls stat for an mtime -- the census is empty, so every assertion above ran zero times"
  elif [ -n "$c55_bad" ]; then
    bad "the mtime probe returns an integer on every platform" "$(printf 'stat -f is filesystem status on Linux and exits 0, so the wrong order never falls through:%b' "$c55_bad")"
  else
    ok "the mtime probe returns an integer on every platform ($c55_n file(s) x 3 platform stubs)"
  fi
fi

# --- 56. every shipped hook decides with a stripped environment --------------------------------
# Check 23 runs ONE hook under `env -u TMPDIR -u HOME -u USER -u LANG`, because guard-destructive.sh
# once read $TMPDIR without a default. Seven other hooks ship alongside it and none of them were
# ever run that way. Two died: compat-canary.sh and verify-gate.sh both expand a bare $HOME under
# `set -u`, so with HOME absent they abort with `unbound variable` before reaching any decision.
#
# verify-gate.sh is the Stop hook. Aborting there is not a wrong answer, it is no answer: the line
# that died is the trust-store lookup deciding whether this repo's verify.sh may run unattended. A
# hook that stops on a shell error has not allowed or blocked anything; it has handed the runtime a
# stack trace and left the outcome to whatever the runtime does with a non-zero exit.
#
# HOME is absent more often than it looks: launchd agents, `env -i`, a Docker `USER` with no passwd
# entry, systemd units without PAMName. But the reason this check exists is not that HOME is likely
# to be missing. It is that check 23 proved this property for one hook and nothing carried it to
# the rest, which is check 54's shape one layer down.
#
# The EVENT IS DERIVED from claude/settings.json, not typed here. The first draft sent every hook
# the same PreToolUse payload; format.sh returns immediately on an event it is not registered for,
# so its body never ran and its row stayed green under a mutation that broke it outright. A hook
# fed the wrong event is a hook this check does not reach.
#
# The assertion is on stderr, not the exit code: hooks legitimately exit 0, 1 and 2, and what none
# of them may do is emit a shell-level error, because that means the script stopped before
# deciding. Census derived from the tree, and empty is a failure.
if command -v jq >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  c56_n=0; c56_bad=""; c56_unwired=""
  c56_pd=$(mktemp -d 2>/dev/null || echo /tmp/c56.$$)
  # The fixture has to make each hook do its work, or this checks that they return early. Both of
  # the hooks that were broken here return immediately on an empty project: verify-gate.sh is
  # opt-in on $CLAUDE_PROJECT_DIR/.claude/verify.sh existing, and format.sh needs a real file to
  # take the dirname of. Given an empty temp dir, both rows below went green against code that
  # aborts on line one of its actual body.
  #
  # The planted verify.sh is `exit 0` because the Stop hook may decide to run it. It should not --
  # with HOME stripped there is no trust store, so nothing is trusted, which is the decision under
  # test -- and if that reasoning is ever wrong, what runs does nothing.
  mkdir -p "$c56_pd/.claude" "$c56_pd/src" 2>/dev/null
  printf '#!/bin/sh\nexit 0\n' > "$c56_pd/.claude/verify.sh" 2>/dev/null
  chmod 755 "$c56_pd/.claude/verify.sh" 2>/dev/null
  printf 'const x = 1\n' > "$c56_pd/src/fixture.ts" 2>/dev/null
  : > "$c56_pd/t.jsonl" 2>/dev/null
  for c56_h in $(git ls-files 'claude/hooks/*.sh'); do
    [ -f "$c56_h" ] || continue
    c56_n=$((c56_n + 1))
    c56_base=${c56_h##*/}
    # First event in settings.json whose command names this script. A hook nobody registered is
    # still run, under PreToolUse, and named in the ok line so the gap is visible rather than
    # silently untested.
    c56_ev=$(jq -r --arg b "$c56_base" '
        .hooks // {} | to_entries[]
        | .key as $e | (.value[]?.hooks[]?.command // empty)
        | select(test($b)) | $e' claude/settings.json 2>/dev/null | head -1)
    if [ -z "$c56_ev" ]; then
      c56_ev=PreToolUse
      c56_unwired="$c56_unwired $c56_base"
    fi
    c56_in=$(jq -nc --arg e "$c56_ev" --arg d "$c56_pd" '{
      hook_event_name:$e, session_id:"c56", transcript_path:($d+"/t.jsonl"),
      cwd:$d, prompt:"hi", tool_name:"Bash",
      tool_input:{command:"true", file_path:($d+"/src/fixture.ts")},
      tool_response:{stdout:"",stderr:"",exit_code:0}}')
    c56_err=$(printf '%s' "$c56_in" \
      | env -u HOME -u TMPDIR -u USER -u LANG CLAUDE_PROJECT_DIR="$c56_pd" \
            bash "$c56_h" 2>&1 >/dev/null)
    # The FIRST rule is derived, and it is the one that matters. A list of bash phrasings is a
    # list, and the tenth spelling beats it: this check shipped matching "parameter null or not
    # set", which is what bash 3.2 says, while bash 5 says "parameter not set". The hook died on
    # every Linux runner and this check called it healthy -- row 56b green against a file that
    # aborts on line 36, caught by CI on 292571e and by nothing here.
    #
    # What is stable across every bash is the DIAGNOSTIC PREFIX. A runtime error from the shell
    # is reported as "<the script as invoked>: line N: ...", and nothing a hook chooses to print
    # carries that prefix, because it names the path this check invoked it by. Matching on the
    # prefix asks "did the shell stop this script" instead of "do I recognise the complaint".
    #
    # A newline is prepended so the first line matches the same pattern as any later one, rather
    # than needing a second alternative that someone later forgets to keep in step.
    #
    # The old substrings stay as a union, not as the criterion. They cover the one case the
    # prefix rule cannot see: a message a CHILD process wrote to the same stderr, such as
    # "cat: /nope: No such file or directory", which carries the child's prefix and not the
    # hook's, and still means the hook could not do its work.
    c56_nl=$(printf '\nx'); c56_nl=${c56_nl%x}
    case "$c56_nl$c56_err" in
      *"$c56_nl$c56_h: line "*|*"unbound variable"*|*"bad substitution"*|*"parameter null or not set"*|*"parameter not set"*|*"No such file or directory"*)
        c56_bad="$c56_bad\n  $c56_base on its $c56_ev event: $(printf '%s' "$c56_err" | head -1)" ;;
    esac
  done
  rm -rf "$c56_pd"
  if [ "$c56_n" -eq 0 ]; then
    bad "every hook decides with a stripped environment" "no hook was found under claude/hooks/ -- the census is empty, so every assertion above ran zero times"
  elif [ -n "$c56_bad" ]; then
    bad "every hook decides with a stripped environment" "$(printf 'run with HOME, TMPDIR, USER and LANG absent, each on the event settings.json registers it for:%b' "$c56_bad")"
  else
    ok "every hook decides with a stripped environment ($c56_n hook(s) on their registered events${c56_unwired:+; not in settings.json, run as PreToolUse:$c56_unwired})"
  fi
else
  skip "every hook decides with a stripped environment" "jq or a git work tree is unavailable, and the hook census needs both"
fi

# --- 57. every reader of the trust store answers the gate's question ---------------------------
# `vstack trust` writes one record and four things read it. Only one of them decides anything:
# claude/hooks/verify-gate.sh, which runs a repo's own script unattended on Stop. The other three
# report on that decision to a human -- and a report that disagrees with the decision it claims to
# describe is worse than no report, because the operator acts on the report.
#
# They disagreed. Measured against the real programs, on the same sandbox, three ways:
#
#   scenario                          gate         doctor       statusline
#   armed, hash current               trusted      trusted      trusted
#   verify.sh edited since trusting   untrusted    untrusted    trusted
#   record names a different file     untrusted    trusted      trusted
#   a recorded companion changed      untrusted    trusted      trusted
#
# statusline.sh looked only for the path and never hashed anything, so it rendered its green
# "shield" on a checkout whose gate refuses to run -- on every turn, which makes it the most-read
# of the three. Its own comment above the block says shield means "it is trusted, so Stop actually
# blocks", and its perf note gave the reason: no subprocess. Measured here, shasum -a 256 over
# this repository's verify.sh costs 9 ms against the 12 ms git call the same script already pays
# every turn, so the saving bought a wrong answer for under one spawn.
#
# bin/doctor matched as a substring rather than as a whole line, so a record for
# <path>/verify.sh.orig satisfied a query for <path>/verify.sh.
#
# claude/hooks/format.sh reads the same store to decide whether prettier may load a config-declared
# plugin. It is excluded here on purpose: it displays no verdict, so there is no report to
# disagree with, and reaching its lookup needs a plugin-declaring prettier config -- machinery
# that would test prettier discovery, not trust agreement.
#
# The probe runs the three programs for real and compares their answers to the gate's. It asserts
# agreement, not spelling: any of them may be rewritten however its author likes, and this check
# only cares that it still lands where the gate lands. The armed row is the positive control --
# without it, three readers hardwired to "untrusted" would agree perfectly and pass.
if command -v jq >/dev/null 2>&1 && { command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; }; then
  c57_d=$(mktemp -d)
  mkdir -p "$c57_d/repo/.claude" "$c57_d/repo/claude" "$c57_d/home/.config/agents"
  printf '{}\n' > "$c57_d/repo/claude/settings.json"
  printf '#!/bin/sh\nexit 0\n' > "$c57_d/repo/.claude/verify.sh"
  chmod 755 "$c57_d/repo/.claude/verify.sh"
  # pwd -P here too: this sandbox lives under $TMPDIR, which is itself a symlink on macOS, so a
  # logical spelling made the fixture disagree with the gate it is measuring.
  c57_v="$(cd "$c57_d/repo/.claude" && pwd -P)/verify.sh"
  c57_ts="$c57_d/home/.config/agents/verify-trust"
  c57_hash(){
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else sha256sum "$1" | cut -d' ' -f1; fi
  }
  # Each reader reduced to the verdict it shows. The gate shows its verdict by refusing.
  c57_gate(){
    c57_o=$(printf '{"session_id":"c57"}' \
      | env HOME="$c57_d/home" CLAUDE_PROJECT_DIR="$c57_d/repo" bash claude/hooks/verify-gate.sh 2>&1)
    # Two refusals, not one. An unrecognised verify.sh says "skipped untrusted"; a recorded
    # companion that changed says "refused to run". Matching only the first read the second as
    # trusted, so the fixture blamed itself ("the gate no longer sets up what it claims to")
    # for a disagreement the gate was reporting correctly.
    case "$c57_o" in
      *"skipped untrusted"*|*"refused to run"*) echo untrusted ;;
      *) echo trusted ;;
    esac
  }
  c57_doctor(){
    env HOME="$c57_d/home" VSTACK_DIR="$c57_d/repo" bash bin/doctor --json 2>/dev/null \
      | jq -r '.trust.state // "NO-VERDICT"'
  }
  c57_statusline(){
    c57_o=$(printf '{"workspace":{"current_dir":"%s"}}' "$c57_d/repo" \
      | env HOME="$c57_d/home" bash claude/statusline.sh 2>&1)
    case "$c57_o" in
      *shield*)      echo trusted ;;
      *"gate open"*) echo untrusted ;;
      *)             echo NO-VERDICT ;;
    esac
  }
  c57_errs=""
  c57_probe(){ # $1 scenario name, $2 what the gate must say for this scenario to be meaningful
    c57_g=$(c57_gate)
    if [ "$c57_g" != "$2" ]; then
      c57_errs="$c57_errs\n  $1: the gate itself answered '$c57_g' where this scenario needs '$2' -- the fixture no longer sets up what it claims to"
      return
    fi
    for c57_r in doctor statusline; do
      c57_a=$("c57_$c57_r")
      [ "$c57_a" = "$c57_g" ] \
        || c57_errs="$c57_errs\n  $1: $c57_r reports '$c57_a' where the gate decides '$c57_g'"
    done
  }
  # armed: the positive control. Readers stuck on one answer pass every negative row.
  printf '%s  %s\n' "$(c57_hash "$c57_v")" "$c57_v" > "$c57_ts"
  c57_probe "armed" trusted
  # the script changed after it was trusted -- the case the trust store exists to catch
  printf 'x\n' >> "$c57_d/repo/.claude/verify.sh"
  c57_probe "edited since trusting" untrusted
  # a record for a neighbouring path, which a substring match accepts and a line match does not
  printf '#!/bin/sh\nexit 0\n' > "$c57_d/repo/.claude/verify.sh"
  printf '%s  %s.orig\n' "$(c57_hash "$c57_v")" "$c57_v" > "$c57_ts"
  c57_probe "record names another file" untrusted
  # A companion script. `vstack trust` (bin/vstack) records every install.sh/overlay.sh/
  # uninstall.sh/bootstrap.sh at the repo root and every path verify.sh sources, and
  # claude/hooks/verify-gate.sh:44-63 re-hashes all of them before running anything. The three
  # scenarios above only ever write .claude/verify.sh, so they exercised the one file all three
  # programs agreed about and were blind to the rest of the recorded set: with install.sh changed,
  # the gate refused while doctor said "trusted" and statusline rendered "shield". A fixture that
  # writes one file cannot see a disagreement about a second one.
  printf '#!/bin/sh\nexit 0\n' > "$c57_d/repo/.claude/verify.sh"
  printf '#!/bin/sh\necho install\n' > "$c57_d/repo/install.sh"
  c57_i="$(cd "$c57_d/repo" && pwd -P)/install.sh"
  { printf '%s  %s\n' "$(c57_hash "$c57_v")" "$c57_v"
    printf '%s  %s\n' "$(c57_hash "$c57_i")" "$c57_i"; } > "$c57_ts"
  # positive control for this pair: a recorded, unmodified companion must not read as untrusted,
  # or a reader that simply distrusts anything with two records would pass the row below.
  c57_probe "companion recorded and unchanged" trusted
  printf '# changed\n' >> "$c57_d/repo/install.sh"
  c57_probe "companion changed since trusting" untrusted
  # The repo reached through a symlink. `vstack trust` is typed by a human against whatever
  # spelling their shell shows; the Stop hook is handed CLAUDE_PROJECT_DIR already resolved by
  # the runtime. Keyed on the logical spelling, the two never met: on macOS every repo under
  # $TMPDIR (/var -> /private/var) armed cleanly and then skipped as untrusted on every Stop,
  # silently, forever. Measured 2026-09-04 on the showcase benchmark, where ten armed runs all
  # reported "skipped untrusted". Writer and readers now normalise with pwd -P; this row arms
  # through the symlink and probes through the physical path, so a reader that drops the
  # normalisation goes red.
  rm -f "$c57_d/repo/install.sh"
  printf '#!/bin/sh\nexit 0\n' > "$c57_d/repo/.claude/verify.sh"
  ln -s "$c57_d/repo" "$c57_d/link" 2>/dev/null
  if [ -L "$c57_d/link" ]; then
    c57_lv="$(cd "$c57_d/link/.claude" && pwd)/verify.sh"     # logical: names the symlink
    c57_pv="$(cd "$c57_d/link/.claude" && pwd -P)/verify.sh"  # physical: what the gate is handed
    if [ "$c57_lv" = "$c57_pv" ]; then
      c57_errs="$c57_errs\n  reached through a symlink: this platform resolves both spellings the same, so the row proves nothing"
    else
      printf '%s  %s\n' "$(c57_hash "$c57_pv")" "$c57_pv" > "$c57_ts"
      c57_probe "armed through a symlink, probed physically" trusted
    fi
  fi
  rm -rf "$c57_d"
  if [ -n "$c57_errs" ]; then
    bad "every reader of the trust store answers the gate's question" \
      "$(printf 'bin/doctor and claude/statusline.sh report on a decision claude/hooks/verify-gate.sh makes:%b' "$c57_errs")"
  else
    ok "every reader of the trust store answers the gate's question (2 reader(s) x 6 scenario(s); format.sh excluded, it shows no verdict)"
  fi
else
  skip "every reader of the trust store answers the gate's question" \
    "jq, or both shasum and sha256sum, are unavailable -- the probe needs jq to read doctor's verdict and a hasher to arm the store"
fi

# --- 58. the release gate's wait ceiling clears the job it waits for --------------------------
# REQUIRE_CHECKS_WAIT_SECONDS bounds how long release.yml's `resolve` waits for `verify` to
# decide. It has been below that job twice -- v1.51.0 gave up eight seconds before the run it
# was waiting for went green -- and both times for the same reason: the suite grew, the comment
# beside the number did not, and nothing compared the two. The comment said so about itself and
# was right. So derive the floor from the tree rather than trusting any measurement to stay true.
#
# `verify` is a join; its wall clock is bounded by the slowest falsify shard, which runs
# ceil(rows/shards) mutation rows plus the 3 fixed rows every shard repeats, at PER_ROW seconds
# each, after FIXED seconds of checkout and install. The ceiling must clear TWICE that floor. A
# ceiling merely above the floor is a coin flip: the two failures were 90 minutes against 93, and
# 25 minutes against 27.
#
# PER_ROW is NOT a constant here, and that is the whole point. A constant inside the checker,
# justified by a run that already happened, is the same defect this check exists to stop being
# trusted -- moved one level down into the thing doing the checking. Two independent reviews of
# the first draft of this check said so, and both were right.
#
# Every falsifiability row runs the WHOLE gate to see which check goes red, so per-row cost is a
# function of the gate's own size: adding a check makes all 107 rows slower. So the recorded
# measurement carries the check count it was taken at, and the model scales it by the gate size
# it finds right here. Adding checks to this file raises the floor it derives, automatically.
#
# Read with sed rather than jq on purpose. Every other reader of inventory.json in this file may
# skip when jq is absent, and a check whose whole subject is a number nobody re-derives must not
# be the one that stops enforcing on a machine without a JSON parser.
#
# What this still does NOT close, stated rather than papered over. FIXED is an assumption, not a
# measurement: one run gives one equation for two unknowns, and that run's two 16-row shards took
# 1034s and 690s, so per-row cost varies by row and fixed cost is not separable from it. And a
# single new row costing far more than the average moves the real job time while the model sees
# only an average. The 2x margin absorbs both unless one row alone exceeds twice the recorded
# per-row cost. Rows 58b and 58c falsify the two halves that ARE load-bearing.
c58_fx=300
c58_rel=".github/workflows/release.yml"; c58_ver=".github/workflows/verify.yml"
c58_fal="tests/gate-falsifiability.sh"
if [ -f "$c58_rel" ] && [ -f "$c58_ver" ] && [ -f "$c58_fal" ]; then
  c58_wait=$(sed -n 's/^ *REQUIRE_CHECKS_WAIT_SECONDS: *"\([0-9]*\)".*/\1/p' "$c58_rel" | head -1)
  c58_sh=$(sed -n 's/^ *FALSIFY_SHARDS: *"\([0-9]*\)".*/\1/p' "$c58_ver" | head -1)
  c58_rows=$(sed -n 's/^CHECKS="\(.*\)"/\1/p' "$c58_fal" | tr ' ' '\n' | grep -c '[0-9]')
  c58_meas=$(sed -n 's/.*"seconds_per_row": *\([0-9]*\).*/\1/p' claude/inventory.json | head -1)
  c58_mck=$(sed -n 's/.*"checks_at_measurement": *\([0-9]*\).*/\1/p' claude/inventory.json | head -1)
  c58_errs=""
  [ -n "$c58_meas" ] && [ "$c58_meas" -gt 0 ] 2>/dev/null \
    || c58_errs="$c58_errs\nno cost_model.seconds_per_row recorded in claude/inventory.json, so the per-row cost below would be justified by nothing in this tree"
  [ -n "$c58_mck" ] && [ "$c58_mck" -gt 0 ] 2>/dev/null \
    || c58_errs="$c58_errs\nno cost_model.checks_at_measurement recorded in claude/inventory.json, so the recorded per-row cost cannot be scaled to this gate's size and would silently stay frozen at the size it was measured on"
  # Every anchor must be found. An extractor that silently returns nothing is how check 18's
  # published-figure guard went quiet for 18 commits: a missing anchor has to be a failure.
  [ -n "$c58_wait" ] || c58_errs="$c58_errs\nno REQUIRE_CHECKS_WAIT_SECONDS: \"<n>\" line in $c58_rel"
  [ -n "$c58_sh" ] && [ "$c58_sh" -gt 0 ] 2>/dev/null \
    || c58_errs="$c58_errs\nno positive FALSIFY_SHARDS: \"<n>\" line in $c58_ver"
  [ "${c58_rows:-0}" -gt 0 ] 2>/dev/null \
    || c58_errs="$c58_errs\nno CHECKS=\"...\" row list in $c58_fal"
  if [ -z "$c58_errs" ]; then
    # Scale the recorded per-row cost by this gate's size against the size it was measured at.
    c58_pr=$(( (c58_meas * TOTAL + c58_mck - 1) / c58_mck ))
    c58_per=$(( (c58_rows + c58_sh - 1) / c58_sh + 3 ))
    c58_floor=$(( c58_fx + c58_per * c58_pr ))
    c58_min=$(( c58_floor * 2 ))
    if [ "$c58_wait" -lt "$c58_min" ]; then
      bad "the release gate's wait ceiling clears the job it waits for" \
        "REQUIRE_CHECKS_WAIT_SECONDS is ${c58_wait}s, under the ${c58_min}s this tree needs: $c58_rows rows over $c58_sh shard(s) is $c58_per rows on the slowest shard, ${c58_pr}s each (${c58_meas}s measured at $c58_mck checks, scaled to $TOTAL) plus ${c58_fx}s fixed = ${c58_floor}s, doubled. Raise it in $c58_rel, shard further, or re-derive the measurement in claude/inventory.json"
    else
      ok "the release gate's wait ceiling clears the job it waits for (${c58_wait}s >= ${c58_min}s: $c58_rows rows / $c58_sh shards -> $c58_per rows x ${c58_pr}s + ${c58_fx}s, doubled; ${c58_meas}s/row measured at $c58_mck checks, scaled to $TOTAL)"
    fi
  else
    bad "the release gate's wait ceiling clears the job it waits for" \
      "$(printf 'the ceiling cannot be derived, so it is not being checked at all:%b' "$c58_errs")"
  fi
else
  bad "the release gate's wait ceiling clears the job it waits for" \
    "$c58_rel, $c58_ver or $c58_fal is missing -- these are tracked files in this repository, not an environment dependency, so their absence is a failure and not a skip"
fi

# --- 59. the goal gate blocks on an open goal and only on an open goal -------------------------
# vstack shipped claude/commands/goal.md, which promises the agent "only stops when fully
# verified", and shipped no reader for the .goal/<slug>/goal.md it writes. The writer had no
# reader for 4 releases: the file was produced and then consulted by nothing. This check is the
# join. It drives the hook end to end on synthetic repos rather than reading it, because the
# question "does a recorded goal actually stop the agent" is only answerable by a decision.
#
# Both directions matter, and the NEGATIVE ones matter more. A gate that blocks whenever it sees
# a checkbox is worse than no gate: two of the four silent cases below are items only the
# operator can finish, and blocking on those loops the agent forever on work it cannot do.
if command -v jq >/dev/null; then
  c59_d=$(mktemp -d)
  mkdir -p "$c59_d/nogoal" "$c59_d/tmp"
  c59_repo(){ _n=$1; shift; mkdir -p "$c59_d/$_n/.goal/x"; printf '%s\n' "$@" > "$c59_d/$_n/.goal/x/goal.md"; }
  c59_repo open  '# G' 'Status: **in progress**' '## Rubric' '- [x] R1' '- [ ] R2 wire it' '## Residuals' '- [ ] not mine'
  c59_repo shut  '# G' 'Status: **complete**'    '## Rubric' '- [ ] R1 never ticked'
  c59_repo resid '# G' 'Status: **in progress**' '## Rubric' '- [x] R1' '## Residuals' '- [ ] vercel login'
  c59_repo human '# G' 'Status: **in progress**' '## Rubric' '- [ ] R2 run pmset (needs: user)'

  # A distinct session id per case: the hook caps at 3 blocks per session, so reusing one id
  # would let case 4 pass because the cap latched, not because the hook decided correctly.
  c59_run(){ printf '{"session_id":"%s"}' "$2" \
    | env TMPDIR="$c59_d/tmp" CLAUDE_PROJECT_DIR="$c59_d/$1" bash claude/hooks/goal-gate.sh 2>/dev/null; }
  c59_errs=""
  c59_want(){ # <repo> <sid> <block|silent> <what>
    _o=$(c59_run "$1" "$2")
    if [ "$3" = block ]; then
      printf '%s' "$_o" | jq -e '.decision=="block"' >/dev/null 2>&1 \
        || c59_errs="$c59_errs\n$4: expected decision:block, got '$_o'"
    else
      [ -z "$_o" ] || c59_errs="$c59_errs\n$4: expected silence, got '$_o'"
    fi
  }
  c59_want nogoal c59a silent "a repo with no .goal directory"
  c59_want open   c59b block  "an open goal with an unchecked rubric item"
  c59_want shut   c59c silent "a goal whose Status says complete"
  c59_want resid  c59d silent "unchecked items only under ## Residuals"
  c59_want human  c59e silent "an unchecked item tagged (needs: user)"

  # The cap must go OPEN, not shut. Deliberately opposite to verify-gate.sh's B-12 fix: a red
  # test is always fixable by the agent, an unchecked box may not be, so looping forever here
  # costs more than releasing does. Four Stops on one session: three block, the fourth stands
  # down with a systemMessage rather than a decision.
  c59_n=0
  c59_i=0
  while [ "$c59_i" -lt 4 ]; do
    c59_i=$((c59_i + 1))
    c59_o=$(c59_run open c59cap)
    printf '%s' "$c59_o" | jq -e '.decision=="block"' >/dev/null 2>&1 && c59_n=$((c59_n + 1))
  done
  [ "$c59_n" -eq 3 ] || c59_errs="$c59_errs\nthe 3-block cap did not engage: $c59_n of 4 stops blocked (expected exactly 3)"
  printf '%s' "$c59_o" | jq -e '.systemMessage' >/dev/null 2>&1 \
    || c59_errs="$c59_errs\nat the cap the hook went silent instead of naming what is still open"

  # The wiring half. A hook nothing invokes is the defect this check exists to close, so assert
  # both shipped lanes name it -- settings.json for the full install, hooks.json for the plugin.
  jq -e '[.hooks.Stop[].hooks[].command] | any(test("goal-gate\\.sh"))' claude/settings.json >/dev/null 2>&1 \
    || c59_errs="$c59_errs\nclaude/settings.json does not wire goal-gate.sh into Stop"
  jq -e '[.hooks.Stop[].hooks[].command] | any(test("goal-gate\\.sh"))' claude/hooks/hooks.json >/dev/null 2>&1 \
    || c59_errs="$c59_errs\nclaude/hooks/hooks.json does not wire goal-gate.sh into Stop"

  rm -rf "$c59_d"
  if [ -z "$c59_errs" ]; then
    ok "the goal gate blocks on an open goal and only on an open goal (5 decisions, 3-block cap, both lanes wired)"
  else
    bad "the goal gate blocks on an open goal and only on an open goal" "$(printf '%b' "$c59_errs")"
  fi
else
  skip "the goal gate blocks on an open goal and only on an open goal" "jq is not installed"
fi

# --- 60. the catalogue's count is derived, and every site that publishes it agrees -------------
# Three files published three different figures for the same catalogue at once -- README.md said
# eighteen, docs/what-this-actually-does.md said thirteen, and the catalogue's own heading said
# seventeen -- and nothing here noticed. Check 12 compares published counts against the tree, but
# its extractor only matches digit+noun, so a spelled-out number is invisible to it, and this
# figure has no tree to count anyway: its subject is a prose catalogue.
#
# The number is now DERIVED rather than asserted in a list kept here. Instances are the bolded
# leads between the catalogue's first `## ` heading and its next one. The coverage-gap note that
# used to sit among them, and was the reason the heading and the entries disagreed by one, now
# lives under `## Named, not counted`, so the boundary is a property of the document's structure
# rather than of an exclusion someone has to remember to update.
#
# Stated hole: a NEW doc that publishes the figure without the `<!-- catalogue-count -->` marker
# escapes lane 2. Lane 3 requires the marker in README.md specifically, because that is the public
# claim, so the one that matters cannot lose its guard silently.
c60_doc="docs/checks-that-inherit-their-answer.md"
if [ -f "$c60_doc" ]; then
  c60_errs=""
  c60_word=$(awk '/^## /{print $3; exit}' "$c60_doc")
  c60_n=$(awk '
    /^## / { if (seen) exit; seen = 1; next }
    seen && /^\*\*/ { n++ }
    END { print n + 0 }
  ' "$c60_doc")
  c60_num=$(awk -v w="$c60_word" 'BEGIN {
    split("one two three four five six seven eight nine ten eleven twelve thirteen fourteen \
fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three \
twenty-four twenty-five", a, " ")
    for (i in a) if (a[i] == w) { print i; exit }
    print -1
  }')

  # Lane 1 -- the heading is the count. A word this table does not know is a failure, not a skip:
  # the catalogue outgrowing the table is exactly when the number stops being checked.
  if [ "$c60_num" -lt 0 ] 2>/dev/null; then
    c60_errs="$c60_errs\n$c60_doc: heading names \"$c60_word\", which is not a number this check can read"
  elif [ "$c60_num" -ne "$c60_n" ]; then
    c60_errs="$c60_errs\n$c60_doc: heading says $c60_word ($c60_num) but the section holds $c60_n entries"
  fi
  [ "$c60_n" -gt 0 ] || c60_errs="$c60_errs\n$c60_doc: no entries found; the extractor matched nothing"

  # Lane 2 -- every marked publication site names the same word.
  c60_sites=$(git grep -lF -- '<!-- catalogue-count -->' -- '*.md' 2>/dev/null)
  if [ -z "$c60_sites" ]; then
    c60_errs="$c60_errs\nno file carries the <!-- catalogue-count --> marker; lane 2 would pass on an empty set"
  else
    c60_off=$(git grep -nF -- '<!-- catalogue-count -->' -- '*.md' 2>/dev/null \
      | grep -viE "(^|[^[:alpha:]])$c60_word([^[:alpha:]]|\$)")
    [ -z "$c60_off" ] && : || c60_errs="$c60_errs\nmarked line(s) not saying \"$c60_word\":\n$c60_off"
  fi

  # Lane 3 -- the public claim keeps its guard.
  printf '%s\n' "$c60_sites" | grep -qx 'README.md' \
    || c60_errs="$c60_errs\nREADME.md publishes this figure and must carry the marker"

  if [ -z "$c60_errs" ]; then
    ok "catalogue count derived and agreed ($c60_word = $c60_n entries, $(printf '%s\n' "$c60_sites" | grep -c . ) marked file(s))"
  else
    bad "catalogue count derived and agreed" "$(printf '%b' "$c60_errs")"
  fi
else
  bad "catalogue count derived and agreed" "$c60_doc is missing; every published figure for it is now unbacked"
fi

# --- 61. install.sh's trust step covers the scripts verify.sh executes -------------------------
# install.sh used to hash exactly one file into the trust store, its own .claude/verify.sh, while
# `vstack trust` recorded that file plus every literal .sh path verify.sh executes, its source/.
# refs, and package manifests -- 34 entries against 1. verify.sh runs ./install.sh --dry-run and
# ./overlay.sh, so the install lane armed the Stop-hook gate over code the store did not cover.
#
# The failure is quiet by construction: verify-gate.sh iterates the entries the store HAS and
# compares each one's hash. A file that was never recorded has no line to mismatch, so it is not
# refused, it is invisible. Only "trusted once, edited since" produces a refusal, so the narrower
# writer could not report its own narrowness.
#
# Two writers for one boundary is the defect; one of them knowing what verify.sh runs and the
# other not is how they drifted. Lane 1 asserts the delegation exists. Lanes 2-4 assert the thing
# it delegates to actually scans, in both directions, because a check that only greps for a call
# proves a call and not a boundary.
c61_errs=""

# Lane 1 -- install.sh delegates rather than hashing on its own.
grep -Fq 'bin/vstack" trust' install.sh \
  || c61_errs="$c61_errs\ninstall.sh does not call bin/vstack trust; if it hashes verify.sh itself, the two writers can disagree again"
grep -Fq 'verify-trust' install.sh \
  && c61_errs="$c61_errs\ninstall.sh names the trust store directly; the store has one writer, bin/vstack"

c61_d=$(mktemp -d)
c61_mkrepo(){ # <dir> <extra line for verify.sh>
  mkdir -p "$1/.claude" "$1/home"
  printf '#!/bin/sh\necho gate\n%s\n' "$2" > "$1/.claude/verify.sh"
  chmod +x "$1/.claude/verify.sh"
}
c61_store(){ printf '%s' "$1/home/.config/agents/verify-trust"; }
# Keeps stderr and the exit code instead of discarding them. This check went red on Alpine in CI
# and nowhere else, and all three lanes reported only "vstack trust failed" because the command
# was run with `>/dev/null 2>&1` -- a check that knows something is wrong and has thrown away the
# only sentence saying what. Two reproduction attempts against a byte-identical image failed to
# make it fail, which is exactly the case where the swallowed stderr is the whole investigation.
# VSTACK_DIR is set for the same reason HOME is overridden, and the two interact. HOME is
# redirected so each lane gets its own trust store instead of writing the operator's. That also
# hides ~/.vstack and the global gitconfig, and bin/vstack resolves its repo from $VSTACK_DIR,
# then ~/.vstack, then `git rev-parse --show-toplevel`. Under a foreign HOME the first two are
# gone, and inside the Alpine CI container the third fails too -- actions/checkout writes its
# safe.directory exemption into the runner HOME's gitconfig, which the override hides, so git
# refuses the checkout as dubiously owned. bin/vstack then exits 1 before `trust` runs at all.
#
# PROVEN: the three lanes reported `no vstack repo found (checked $VSTACK_DIR, ~/.vstack, and
# this script's git root)`, rc=1, on Alpine only. INFERRED: that the git-root lane failed
# specifically on dubious ownership; the message does not say which of the three lost. Naming
# $VSTACK_DIR settles it either way, and it is what the error text itself tells you to do.
#
# This is the check's own environment, not a defect in what it measures: a user does not run
# vstack under a substituted HOME. It cost a red on one platform and three destroyed tags'
# worth of noise because the invocation discarded stderr.
c61_last=""
c61_trust(){
  c61_last=$(HOME="$1/home" VSTACK_DIR="$PWD" ./bin/vstack trust "$1" --yes 2>&1 >/dev/null)
  c61_rc=$?
  [ -n "$c61_last" ] || c61_last="(command printed nothing on stderr)"
  c61_last="rc=$c61_rc, stderr: $(printf '%s' "$c61_last" | tr '\n' ' ')"
  return "$c61_rc"
}

# Lane 2 -- positive control. A repo whose gate runs ./scripts/ci.sh must get ci.sh recorded, and
# that path is in no hardcoded list anywhere: it can only come from reading verify.sh.
c61_a="$c61_d/a"; c61_mkrepo "$c61_a" './scripts/ci.sh'
mkdir -p "$c61_a/scripts"; printf '#!/bin/sh\ntrue\n' > "$c61_a/scripts/ci.sh"
if c61_trust "$c61_a"; then
  grep -q '/scripts/ci\.sh$' "$(c61_store "$c61_a")" \
    || c61_errs="$c61_errs\nvstack trust did not record scripts/ci.sh, a path only verify.sh names -- the scan is not reading the gate"
else
  c61_errs="$c61_errs\nvstack trust failed on a synthetic repo naming ./scripts/ci.sh -- $c61_last"
fi

# Lane 3 -- negative control. A gate that runs nothing else gets one entry. Without this, lane 2
# passes on a writer that records every .sh it can find, which would be a different boundary
# wearing the same output.
c61_b="$c61_d/b"; c61_mkrepo "$c61_b" 'true'
mkdir -p "$c61_b/scripts"; printf '#!/bin/sh\ntrue\n' > "$c61_b/scripts/unnamed.sh"
if c61_trust "$c61_b"; then
  c61_n=$(grep -c . "$(c61_store "$c61_b")" || true)
  [ "$c61_n" = 1 ] \
    || c61_errs="$c61_errs\nvstack trust recorded $c61_n entries for a gate that names no other script; it should record 1"
else
  c61_errs="$c61_errs\nvstack trust failed on a synthetic repo naming nothing -- $c61_last"
fi

# Lane 4 -- this repository. The two files the narrow writer missed, named because they are the
# ones verify.sh actually executes, not because they are a general category.
c61_c="$c61_d/c"; mkdir -p "$c61_c/home"
if c61_last=$(HOME="$c61_c/home" VSTACK_DIR="$PWD" ./bin/vstack trust "$PWD" --yes 2>&1 >/dev/null); c61_rc=$?; \
   c61_last="rc=$c61_rc, stderr: $(printf '%s' "${c61_last:-(nothing on stderr)}" | tr '\n' ' ')"; \
   [ "$c61_rc" -eq 0 ]; then
  for c61_f in install.sh overlay.sh; do
    grep -q "/$c61_f\$" "$(c61_store "$c61_c")" \
      || c61_errs="$c61_errs\nthe trust store for this repo does not record $c61_f, which .claude/verify.sh executes"
  done
  c61_tot=$(grep -c . "$(c61_store "$c61_c")" || true)
else
  c61_tot=0
  c61_errs="$c61_errs\nvstack trust failed on this repository -- $c61_last"
fi
rm -rf "$c61_d"

if [ -z "$c61_errs" ]; then
  ok "install trust covers what the gate executes ($c61_tot entries here; scan proven in both directions)"
else
  bad "install trust covers what the gate executes" "$(printf '%b' "$c61_errs")"
fi

# --- 61b. a non-interactive install without opt-in leaves this repo untrusted -------------------
# install.sh used to call `bin/vstack trust "$SRC" --yes` unconditionally (fixed alongside check
# 61 above): bootstrap.sh's curl|bash one-liner drives install.sh with stdin as the pipe carrying
# the script, so a stranger who never read a line of it still walked away with the Stop-hook gate
# armed to execute .claude/verify.sh (which itself runs install.sh --dry-run and overlay.sh)
# unattended. Every OTHER repo's gate stays off until someone runs `vstack trust` there and
# answers its "have you read this, just now? [y/N]" prompt; a bare non-interactive install of
# THIS repo must get the same refusal, not a free pass because it happens to be the repo that
# ships the gate.
#
# PROVEN as a regression check, not a design opinion: run against `git show
# origin/main:install.sh` (before this fix) with stdin redirected from /dev/null, the trust store
# gets this repo's .claude/verify.sh entry anyway -- confirming the defect was real before it was
# "fixed" by only editing prose. Run the same probe against the install.sh in this checkout and
# the entry must be absent.
c61b_errs=""
if ! command -v git >/dev/null 2>&1; then
  skip "non-interactive install without opt-in leaves the trust gate off" "git not installed"
else
  c61b_home=$(mktemp -d)
  # No --trust, no VSTACK_TRUST, and stdin explicitly closed so this is deterministic regardless
  # of whether verify.sh itself is being run at an interactive terminal or piped.
  HOME="$c61b_home" VSTACK_DIR="$PWD" ./install.sh </dev/null >/dev/null 2>&1
  c61b_ts="$c61b_home/.config/agents/verify-trust"
  if [ -f "$c61b_ts" ] && grep -q "/\.claude/verify\.sh\$" "$c61b_ts"; then
    c61b_errs="$c61b_errs\na non-interactive install with no opt-in armed the verify gate for this repo anyway"
  fi
  rm -rf "$c61b_home"
  if [ -z "$c61b_errs" ]; then
    ok "non-interactive install without opt-in leaves the trust gate off"
  else
    bad "non-interactive install without opt-in leaves the trust gate off" "$(printf '%b' "$c61b_errs")"
  fi
fi

# --- 62. the pre-tag carve-out names one finding and does not leak into the tool ---------------
# On 2026-09-01 the v1.61.0 tag was created and destroyed twice in under an hour. bin/doctor's
# "declared release is fetchable" does a live ls-remote against origin -- the right question of
# the right machine, and itself the fix for a catalogued defect. But verify.yml triggers on the
# COMMIT that declares the version, and the tag is a separate ref pushed seconds later, so
# install-matrix and container-matrix run inside a window where the manifests say v1.N.0 and
# origin does not yet carry it. Their red was true about that instant and said nothing about the
# candidate; resolve read it as a decision and cleanup-on-failed-gate deleted the tag whose
# absence was the finding. require-checks-green.sh's staleness carve-out did not fire and was
# right not to: it excuses a run that STARTED before the candidate, and this one started after.
#
# tests/pretag-findings.sh makes that one finding a note in those two harnesses. An exemption is
# only as good as what holds it to account, so this asserts four things: the list is exactly one
# entry, both harnesses actually read it, and -- the load-bearing one -- bin/doctor still reports
# the same label as a hard failure. A carve-out scoped to two test lanes that quietly became a
# carve-out in the tool would remove the finding for every user, which is the opposite of the fix.
c62_f="tests/pretag-findings.sh"
if [ -f "$c62_f" ]; then
  c62_errs=""
  c62_n=$(grep -c '^PRETAG_ALLOWED_FINDING=' "$c62_f" || true)
  [ "$c62_n" = 1 ] \
    || c62_errs="$c62_errs\n$c62_f defines $c62_n PRETAG_ALLOWED_FINDING assignment(s); the list is one entry by design"
  c62_lbl=$(sed -n "s/^PRETAG_ALLOWED_FINDING='\(.*\)'$/\1/p" "$c62_f")
  [ -n "$c62_lbl" ] \
    || c62_errs="$c62_errs\n$c62_f: could not read the finding label; an empty carve-out silently excludes nothing and every lane fails for a reason nobody wrote down"

  # Both harnesses read the shared file rather than spelling the label themselves. Two copies is
  # how tests/mandate-cases.sh's predecessor drifted, in this repository, already once.
  grep -q 'pretag-findings\.sh' tests/install-matrix.sh \
    || c62_errs="$c62_errs\ntests/install-matrix.sh does not read $c62_f"
  grep -q 'PRETAG_ALLOWED_FINDING' tests/install-matrix.sh \
    || c62_errs="$c62_errs\ntests/install-matrix.sh reads $c62_f but never uses the label"
  grep -q 'pretag-findings\.sh' tests/container-matrix.sh \
    || c62_errs="$c62_errs\ntests/container-matrix.sh does not read $c62_f"
  grep -q 'PRETAG_ALLOWED_FINDING' tests/container-matrix.sh \
    || c62_errs="$c62_errs\ntests/container-matrix.sh reads $c62_f but never uses the label"

  # The tool keeps the finding. Derived from the file's own value, so a typo in either place is a
  # failure rather than two literals agreeing with nothing.
  if [ -n "$c62_lbl" ]; then
    # Anchor on the BRANCH, not on the label. bin/doctor spells this label six times -- two
    # `bad`, three `note`, one `ok` -- so a whole-file `grep -F 'bad "<label>"'` stays green while
    # the one branch the carve-out excuses is downgraded, because a different `bad` still matches.
    # Row 62b did exactly that and this check reported ok. The branch is identified by its own
    # message: a declared version with no tag on origin.
    c62_ln=$(grep -n 'has no tag on origin' bin/doctor | head -1 | cut -d: -f1)
    if [ -z "$c62_ln" ]; then
      c62_errs="$c62_errs\nbin/doctor has no branch reporting a declared version with no tag on origin; that finding is what the carve-out excuses in two test lanes, and it must still exist for a user"
    else
      sed -n "${c62_ln}p" bin/doctor | grep -q "^[[:space:]]*bad \"$c62_lbl\"" \
        || c62_errs="$c62_errs\nbin/doctor:$c62_ln no longer reports \"$c62_lbl\" as a hard failure when the declared version has no tag on origin; the carve-out is scoped to two test lanes and must not reach a user's doctor"
    fi
  fi

  if [ -z "$c62_errs" ]; then
    ok "pre-tag carve-out is one finding, read by both harnesses, still hard in bin/doctor (\"$c62_lbl\")"
  else
    bad "pre-tag carve-out is one finding, read by both harnesses, still hard in bin/doctor" "$(printf '%b' "$c62_errs")"
  fi
else
  bad "pre-tag carve-out is one finding, read by both harnesses, still hard in bin/doctor" "$c62_f is missing, so two harnesses are carving out a finding with nothing naming which one"
fi

# --- 63. published corpus figures have an instrument, and its arithmetic is proven
# CHANGELOG 1.57.0 published six numbers about this machine's transcript corpus and `git grep`
# for any of them returned CHANGELOG.md alone. Prose is not a measurement. tests/transcript-census.sh
# now recomputes them, and running it against the corpus already found that one of the six --
# "53.0% per run" -- reproduces under no denominator the instrument computes.
#
# The census itself cannot run here: CI has no transcripts, and neither does a stranger's clone.
# So this checks the half that is checkable everywhere, and checks it in BOTH directions. Lane 1
# runs the self-test and requires its PROVEN verdict. Lane 2 does not trust that verdict: it
# re-runs the engine against an empty corpus directly and requires a non-zero exit, because a
# self-test that reports PROVEN having asserted nothing is precisely the shape this gate exists
# to catch, and a script grading its own homework is not a control.
c63_sh="tests/transcript-census.sh"
c63_py="tests/transcript-census.py"
if [ ! -f "$c63_sh" ] || [ ! -f "$c63_py" ]; then
  bad "corpus census arithmetic is proven" "$c63_sh / $c63_py missing, so CHANGELOG's corpus figures have no instrument again"
elif ! command -v python3 >/dev/null 2>&1; then
  skip "corpus census arithmetic is proven" "python3 not on PATH"
else
  c63_errs=""
  c63_out=$(bash "$c63_sh" --self-test 2>&1)
  printf '%s' "$c63_out" | grep -q '^CENSUS ARITHMETIC PROVEN$' \
    || c63_errs="$c63_errs\n$c63_sh --self-test did not report PROVEN: $(printf '%s' "$c63_out" | tail -3 | tr '\n' ';')"
  c63_n=$(printf '%s' "$c63_out" | grep -c '^ok    ' || true)
  [ "${c63_n:-0}" -ge 15 ] \
    || c63_errs="$c63_errs\n$c63_sh --self-test reported PROVEN on only ${c63_n:-0} assertion(s); it declares 7 proofs and a verdict over an empty proof set is the defect this check is for"
  # Independent control: the engine must refuse an empty corpus rather than report 0.0%.
  c63_tmp=$(mktemp -d "${TMPDIR:-/tmp}/vstack-c63.XXXXXX")
  mkdir -p "$c63_tmp/proj"
  c63_e=$(python3 "$c63_py" "$c63_tmp" 2>&1); c63_rc=$?
  rm -rf "$c63_tmp"
  { [ "$c63_rc" -ne 0 ] && printf '%s' "$c63_e" | grep -q 'INCONCLUSIVE'; } \
    || c63_errs="$c63_errs\n$c63_py reported rc=$c63_rc on an empty corpus; an empty census is not a rate of zero and must not exit 0"
  if [ -z "$c63_errs" ]; then
    ok "corpus census arithmetic is proven ($c63_n assertions, empty corpus refused)"
  else
    bad "corpus census arithmetic is proven" "$(printf '%b' "$c63_errs")"
  fi
fi

# --- 64. the security lane skips a missing scanner and still fails on a real finding -----------
# The security toolchain shipped as three payload files and a README table, and every part of it
# was prose. Nothing ran claude/security-scan.sh, nothing read the workflow template's action
# pins, and nothing compared the tools README's "Prod-ready gates" table publishes against the
# tools the script actually calls. The failure mode is not that the scan is missing -- it is that
# the scan runs, finds no scanners installed, prints five reassuring lines and exits 0. That is a
# fake green with a per-tool report attached, which reads stronger than no check at all.
#
# Measured in a throwaway git repo, never in this one: the answer here is contaminated by whichever
# scanners this particular machine happens to have installed, so a run on the author's laptop and
# a run in CI would be testing two different scripts.
#
# Lane 1 -- PATH=/usr/bin:/bin, so no scanner is reachable. Every tool must SKIP and the script
# must exit 0. A missing scanner failing the run would make the overlay's gate red on every
# machine that has not installed five binaries, which is how a gate gets switched off.
# Lane 2 -- the same repo with a stub `gitleaks` that reports a finding and exits 1. The script
# must exit 1 and name it. Lane 1 alone is satisfied by a script that can only ever skip, which
# is precisely the shape lane 1 cannot distinguish from a working scan.
# Lane 64b -- the half that is not executable here: the CI workflow's pins and the README table
# that documents which tool runs where.
c64_lbl="the security lane skips a missing scanner and fails on a finding"
c64_sh="claude/security-scan.sh"
c64_wf="claude/security.yml.tmpl"
if [ ! -f "$c64_sh" ]; then
  bad "$c64_lbl" "$c64_sh is missing, so overlay.sh ships a verify.sh template that calls a script nobody wrote"
elif [ ! -f "$c64_wf" ]; then
  bad "$c64_lbl" "$c64_wf is missing, so the CI half of the lane README publishes does not exist"
else
  c64_errs=""
  c64_note=""

  # The exec bit as GIT records it, not as this filesystem shows it. A 100644 payload script is
  # runnable here (the author chmod'd it once) and unrunnable for everyone who clones, and the
  # overlay's own chmod hides that from the only lane that would have caught it.
  c64_mode=$(git ls-files -s "$c64_sh" 2>/dev/null | awk '{print $1}')
  [ "$c64_mode" = "100755" ] \
    || c64_errs="$c64_errs\n$c64_sh is ${c64_mode:-not tracked by git}, not mode 100755; a stranger's clone gets a file it cannot execute"

  # Skip, not fail, on a host without shellcheck -- check 0 already decides whether this gate may
  # run at all without it, and duplicating that judgement here would fail hosts check 0 passes.
  if command -v shellcheck >/dev/null 2>&1; then
    if ! c64_sc=$(shellcheck -S warning -f gcc "$c64_sh" 2>/dev/null); then
      c64_errs="$c64_errs\nshellcheck -S warning on $c64_sh: $(printf '%s' "$c64_sc" | head -5 | tr '\n' ';')"
    fi
  else
    c64_note=", shellcheck not on PATH"
  fi

  c64_tmp=$(mktemp -d "${TMPDIR:-/tmp}/vstack-c64.XXXXXX")
  git -C "$c64_tmp" init -q >/dev/null 2>&1
  cp "$c64_sh" "$c64_tmp/security-scan.sh"
  chmod 755 "$c64_tmp/security-scan.sh"

  # env -i: this shell's PATH carries whatever the developer has installed, and inheriting it is
  # the difference between measuring the script and measuring the machine.
  c64_out=$(cd "$c64_tmp" && env -i PATH=/usr/bin:/bin HOME="$c64_tmp" TMPDIR="$c64_tmp" \
              bash ./security-scan.sh 2>&1); c64_rc=$?
  c64_nskip=$(printf '%s\n' "$c64_out" | grep -c '^skip' || true)
  [ "$c64_rc" -eq 0 ] \
    || c64_errs="$c64_errs\n$c64_sh exited $c64_rc with no scanner on PATH; a tool that is not installed is a skip, and failing there switches the whole gate off for everyone who has not installed five binaries"
  [ "${c64_nskip:-0}" -ge 4 ] \
    || c64_errs="$c64_errs\n$c64_sh reported ${c64_nskip:-0} skip line(s) with no scanner on PATH; it declares five tools, and exit 0 over a report that named none of them is the fake green this check exists for"

  # Lane 2. The stub is what makes lane 1 mean anything: without it, a script whose every branch
  # is `skip` passes lane 1 perfectly.
  c64_stub="$c64_tmp/stub"
  mkdir -p "$c64_stub"
  printf '#!/bin/sh\necho "leak: generic-api-key at config.yml:3"\nexit 1\n' > "$c64_stub/gitleaks"
  chmod 755 "$c64_stub/gitleaks"
  c64_out2=$(cd "$c64_tmp" && env -i PATH="$c64_stub:/usr/bin:/bin" HOME="$c64_tmp" TMPDIR="$c64_tmp" \
               bash ./security-scan.sh 2>&1); c64_rc2=$?
  rm -rf "$c64_tmp"
  [ "$c64_rc2" -eq 1 ] \
    || c64_errs="$c64_errs\n$c64_sh exited $c64_rc2 against a gitleaks that reported a finding and exited 1; a scanner whose findings do not reach the exit code is decoration"
  printf '%s\n' "$c64_out2" | grep -qE '^FAIL +gitleaks' \
    || c64_errs="$c64_errs\n$c64_sh did not print a FAIL line naming gitleaks against a scanner that found something: $(printf '%s' "$c64_out2" | tail -3 | tr '\n' ';')"

  # --- 64b, in the same body: the CI half, which cannot be executed here.
  #
  # Every action pinned to a 40-hex commit with the human-readable tag beside it. A tag is a
  # mutable pointer somebody else controls, and `uses: foo@v7` in a workflow with repo write
  # gives that somebody a push into this repo's CI. The `# v` suffix is required too: a bare SHA
  # with no tag comment is unreviewable and never gets bumped.
  while IFS= read -r c64_u; do
    [ -n "$c64_u" ] || continue
    printf '%s' "$c64_u" | grep -qE '@[0-9a-f]{40} # v' \
      || c64_errs="$c64_errs\n$c64_wf: $(printf '%s' "$c64_u" | sed 's/^[[:space:]]*//') is not pinned to a 40-hex commit with its tag beside it"
  done <<EOF
$(grep -E '^[[:space:]]*uses:' "$c64_wf" 2>/dev/null)
EOF
  grep -qE '^[[:space:]]*uses:' "$c64_wf" 2>/dev/null \
    || c64_errs="$c64_errs\n$c64_wf declares no 'uses:' line at all, so the pinning rule above scanned nothing"

  # README's "Prod-ready gates" table is the published contract; $c64_sh is the implementation.
  # The Tool column is extracted rather than typed here, so deleting a row is as visible as
  # deleting the tool. Which of those tools the LOCAL gate is expected to run is named, not
  # inferred -- npm audit and nuclei are CI and post-deploy only, and inferring the list from
  # what the script mentions would let the check read its answer off its own subject.
  c64_local="gitleaks semgrep osv-scanner zizmor eslint"
  c64_tools=$(awk '/^## Prod-ready gates/{s=1; next} s && /^## /{s=0} s && /^\|/{print}' README.md 2>/dev/null \
              | sed -E 's/^\| *//; s/ *\|.*//')
  for c64_t in $c64_local; do
    grep -qxF "$c64_t" <<<"$c64_tools" \
      || c64_errs="$c64_errs\nREADME's Prod-ready gates table no longer names '$c64_t' in its Tool column, so the published contract and $c64_sh have drifted apart"
    grep -qF "$c64_t" "$c64_sh" \
      || c64_errs="$c64_errs\n$c64_sh never mentions '$c64_t', which README's Prod-ready gates table says the local gate runs"
  done

  # A payload file the overlay does not copy ships to nobody. All three landed in this repo
  # before overlay.sh knew about any of them.
  for c64_p in claude/security-scan.sh claude/security.yml.tmpl claude/dependabot.yml.tmpl; do
    grep -qF "$c64_p" overlay.sh 2>/dev/null \
      || c64_errs="$c64_errs\noverlay.sh never names $c64_p, so it is payload this repository ships to itself"
  done

  if [ -z "$c64_errs" ]; then
    ok "$c64_lbl (${c64_nskip} skips at exit 0, stub finding caught at exit 1, $(grep -cE '^[[:space:]]*uses:' "$c64_wf") actions pinned$c64_note)"
  else
    bad "$c64_lbl" "$(printf '%b' "$c64_errs")"
  fi
fi

# --- 65. every shipped mechanism records what justifies it, and the record has not expired -----
# Every hook in claude/hooks/ ships because somebody believed it does something. Nothing in this
# tree ever held that belief to an artefact. docs/what-this-actually-does.md exists precisely
# because the honest answer to "does this help" is mostly "unmeasured", and a document that says
# so goes stale the same way every other prose count in this repo has: the mechanism changes, the
# row does not, and the disclosure quietly becomes a claim.
#
# So the justification is a ledger entry, not prose, and this check joins the three things that
# have to agree: what is WIRED (claude/settings.json + claude/hooks/hooks.json), what is RECORDED
# (claude/inventory.json .components.hooks.mechanisms[]), and what is PUBLISHED
# (docs/what-this-actually-does.md sections 1 and 2). A hook wired with no entry ships with
# nothing recorded about why. An entry with no published row is a mechanism the document does not
# disclose. Both are the same defect from opposite ends.
#
# The three justification kinds are checked against their own evidence, not against their own
# say-so:
#   measurement -- the cited artefact must exist AND the hook must not have changed since. A
#                  measurement names a commit; if the file has moved on in any non-comment line,
#                  the number is about code that no longer ships. Comment-only edits are excluded
#                  deliberately: rewriting this file's own header must not invalidate a run.
#   literature  -- the cited entry's verdict row in the matching .verification.md must read
#                  VERIFIED. Those files already carry MISREAD verdicts for real citation errors
#                  (see false-completion.verification.md, 4 of 14), so citing an entry is not the
#                  same as citing a checked one, and only reading the verdict cell separates them.
#   none        -- allowed, with an expiry. An unmeasured mechanism that can BLOCK a session is a
#                  cost with no demonstrated benefit, so it carries a decide_by; past that date it
#                  is a failure naming the id, and before it the ok line prints the ids and dates
#                  so the debt is on screen every run rather than in a backlog.
#
# Every anchor is required. A missing settings file, an empty mechanisms array, a missing section
# heading and an unparseable entry string are all failures here, never silence -- this file's
# founding defect is a check that reports success having read nothing, and a ledger reader is the
# easiest possible place to commit it again.
c65_lbl="every shipped mechanism records what justifies it"
if command -v jq >/dev/null && command -v git >/dev/null; then
  c65_inv="claude/inventory.json"
  c65_doc="docs/what-this-actually-does.md"
  if [ ! -f "$c65_inv" ] || [ ! -f "$c65_doc" ]; then
    bad "$c65_lbl" \
      "$c65_inv or $c65_doc is missing -- both are tracked files in this repository, not an environment dependency, so their absence is a failure and not a skip"
  else
    c65_n=$(jq -r '(.components.hooks.mechanisms // []) | length' "$c65_inv" 2>/dev/null)
    case "$c65_n" in ''|*[!0-9]*) c65_n=0 ;; esac
    if [ "$c65_n" -eq 0 ]; then
      bad "$c65_lbl" \
        "$c65_inv carries no .components.hooks.mechanisms[] entries, so nothing in this tree records why any shipped hook exists -- and with nothing to read, every assertion below would pass over an empty set, which is the exact shape of a green that measured nothing"
    else
      c65_errs=""
      c65_today=$(date +%F 2>/dev/null)
      [ -n "$c65_today" ] \
        || c65_errs="$c65_errs\ndate +%F produced nothing, so no decide_by can be compared and the expiry half of this check is not running"

      # WIRED: every command under the five events that actually run a shipped hook, from both
      # install lanes, reduced to script basenames. Both files, not one: the plugin lane wires a
      # different (smaller) subset, and a mechanism recorded only for the settings lane would
      # leave the plugin lane's hooks unaccounted for -- the same one-lane blindness check 11 and
      # check 47 exist for, one artefact over.
      c65_files=$(jq -r '(.components.hooks.mechanisms // [])[] | .file // ""' "$c65_inv" 2>/dev/null \
                  | grep -v '^$' | sort -u)
      c65_wired=""
      for c65_f in claude/settings.json claude/hooks/hooks.json; do
        if [ ! -f "$c65_f" ]; then
          c65_errs="$c65_errs\n$c65_f is missing, so the set of wired hook commands cannot be enumerated and the mapping below would be checked against a short list"
          continue
        fi
        c65_w=$(jq -r '(.hooks // {}) | to_entries[]
                       | select(.key == "Stop" or .key == "PostToolUse" or .key == "PreToolUse"
                                or .key == "UserPromptSubmit" or .key == "SessionStart")
                       | .value[]? | .hooks[]? | .command // ""' "$c65_f" 2>/dev/null \
                | grep -oE '[A-Za-z0-9_.-]+\.sh' | sort -u)
        if [ -z "$c65_w" ]; then
          c65_errs="$c65_errs\n$c65_f declares no hook command under any of Stop/PostToolUse/PreToolUse/UserPromptSubmit/SessionStart -- the extractor found nothing, which is a missing anchor and not a clean bill"
        else
          c65_wired=$(printf '%s\n%s\n' "$c65_wired" "$c65_w")
        fi
      done
      c65_wired=$(printf '%s\n' "$c65_wired" | grep -v '^$' | sort -u)
      c65_nw=0
      for c65_b in $c65_wired; do
        c65_nw=$((c65_nw+1))
        grep -qxF "$c65_b" <<<"$c65_files" \
          || c65_errs="$c65_errs\n$c65_b is wired as a hook but no .components.hooks.mechanisms[] entry in $c65_inv names it in .file, so it ships with nothing recorded about why it is there"
      done

      # PUBLISHED: the two sections that are allowed to carry a mechanism row. The flag flips off
      # on any other `## ` heading, so section 3 ("Unproven, and named as such") cannot satisfy a
      # mechanism's disclosure -- a mechanism listed only there is exactly the row this check
      # would otherwise let pass by matching anywhere in the file.
      c65_h1='^## 1\. Measured'
      c65_h2='^## 2\. Mechanism works, effect unmeasured'
      grep -qE "$c65_h1" "$c65_doc" \
        || c65_errs="$c65_errs\n$c65_doc has no heading matching /$c65_h1/, so the section this check reads mechanism rows out of cannot be located"
      grep -qE "$c65_h2" "$c65_doc" \
        || c65_errs="$c65_errs\n$c65_doc has no heading matching /$c65_h2/, so the section this check reads mechanism rows out of cannot be located"
      c65_docrows=$(awk '/^## /{ s = ($0 ~ /^## 1\. Measured/ || $0 ~ /^## 2\. Mechanism works, effect unmeasured/) ? 1 : 0; next } s' "$c65_doc" 2>/dev/null)

      c65_nmeas=0; c65_nlit=0; c65_nnone=0; c65_pend=""
      # Unit separator, not @tsv. Tab is IFS *whitespace*, so `read` collapses a run of them
      # into one delimiter and every empty field silently disappears -- an entry with a null
      # justified_by.file shifted run_id into its slot and measured_head out of the record
      # entirely, and the check then reported a missing head that was right there in the file.
      # \x1f is not IFS whitespace, so empty fields hold their position.
      while IFS=$'\x1f' read -r c65_id c65_file c65_blk c65_kind c65_jfile c65_run c65_entry c65_head c65_by; do
        [ -n "$c65_id" ] || continue
        case "$c65_kind" in
          measurement)
            c65_nmeas=$((c65_nmeas+1))
            if [ -n "$c65_jfile" ] && [ -e "$c65_jfile" ]; then :
            elif [ -n "$c65_run" ] && [ -e "runs/$c65_run" ]; then :
            else
              c65_errs="$c65_errs\n$c65_id: kind is measurement but neither justified_by.file (${c65_jfile:-unset}) nor runs/${c65_run:-unset} exists in this tree, so the measurement it cites is not here to re-read"
            fi
            if [ -z "$c65_head" ]; then
              c65_errs="$c65_errs\n$c65_id: kind is measurement with no measured_head, so nothing records which version of claude/hooks/${c65_file:-?} the number was taken against"
            elif ! git cat-file -e "$c65_head^{commit}" 2>/dev/null \
                 && [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
              # A depth-1 clone has no history to walk, so "not an ancestor" would be a verdict
              # about the clone, not the ledger. The 1.70.0 release lane went red on exactly this:
              # the container matrix clones at depth 1 and the first measured mechanism reddened
              # every image. Name the real cause and how to lift it; tests/container-matrix.sh
              # now deepens its clone before running this file.
              c65_errs="$c65_errs\n$c65_id: measured_head $c65_head is not present in this shallow clone, so ancestry cannot be judged here -- run \`git fetch --unshallow\` (or deepen the clone) and re-run; a depth-1 checkout cannot tell a lost commit from an unfetched one"
            elif ! git merge-base --is-ancestor "$c65_head" HEAD >/dev/null 2>&1; then
              c65_errs="$c65_errs\n$c65_id: measured_head $c65_head is not an ancestor of HEAD, so the measurement was taken on a commit this branch does not contain -- an unreachable commit cannot justify what ships here"
            elif [ -n "$c65_file" ]; then
              # -U0 and a +/- filter, not --stat: a comment-only edit must not invalidate a
              # measurement, and only reading the changed lines themselves can tell the two
              # apart. +++/--- headers are dropped before the leading sign is stripped, or the
              # file header itself would read as a changed line on every diff.
              c65_drift=$(git diff -U0 "$c65_head..HEAD" -- "claude/hooks/$c65_file" 2>/dev/null \
                          | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | sed -E 's/^[+-]//' \
                          | grep -vE '^[[:space:]]*(#|$)')
              [ -z "$c65_drift" ] \
                || c65_errs="$c65_errs\n$c65_id: claude/hooks/$c65_file has $(printf '%s\n' "$c65_drift" | grep -c '') non-comment line(s) changed since measured_head $c65_head, so the recorded measurement describes code that no longer ships -- re-measure or move the head deliberately"
            fi
            ;;
          literature)
            c65_nlit=$((c65_nlit+1))
            c65_lname=${c65_entry%%#*}
            c65_lnum=${c65_entry##*#}
            if [ -z "$c65_entry" ] || [ "$c65_lname" = "$c65_entry" ] || [ -z "$c65_lnum" ] \
               || case "$c65_lnum" in ''|*[!0-9]*) true ;; *) false ;; esac; then
              c65_errs="$c65_errs\n$c65_id: kind is literature but justified_by.entry ('${c65_entry:-unset}') is not <report>#<entry number>, so no verdict row can be located for it"
            else
              c65_lfile="docs/research/harness-effect/literature/$c65_lname.verification.md"
              if [ ! -f "$c65_lfile" ]; then
                c65_errs="$c65_errs\n$c65_id: cites $c65_entry but $c65_lfile does not exist, so the citation was never checked against the source in this tree"
              else
                # The verdict CELL, not the line. The evidence cell of a MISREAD row routinely
                # contains the word VERIFIED in prose; a line-wide grep would read those rows as
                # verified, which is the one distinction this whole kind turns on.
                c65_verdict=$(awk -F'|' -v n="$c65_lnum" '
                  /^\|/ { k = $2; v = $3;
                          gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v);
                          if (k == n) { print v; exit } }' "$c65_lfile" 2>/dev/null)
                if [ -z "$c65_verdict" ]; then
                  c65_errs="$c65_errs\n$c65_id: $c65_lfile has no verdict row for entry $c65_lnum, so the citation points at nothing that was checked"
                elif [ "$c65_verdict" != VERIFIED ]; then
                  c65_errs="$c65_errs\n$c65_id: $c65_lfile records entry $c65_lnum as '$c65_verdict', not VERIFIED -- a mechanism justified by a citation its own verification marked wrong"
                fi
              fi
            fi
            ;;
          none)
            c65_nnone=$((c65_nnone+1))
            if [ "$c65_blk" != true ]; then
              :
            elif [ -z "$c65_by" ]; then
              c65_errs="$c65_errs\n$c65_id: blocking, kind none, and no decide_by -- a mechanism that can stop a session with nothing measured about it and no date by which that has to change is permanent by default"
            elif [ -n "$c65_today" ] && [[ "$c65_today" > "$c65_by" ]]; then
              c65_errs="$c65_errs\n$c65_id: blocking, still unmeasured, and its decide_by ($c65_by) passed on $c65_today -- measure it, stop it blocking, or move the date on purpose"
            else
              c65_pend="$c65_pend $c65_id(by ${c65_by:-?})"
            fi
            ;;
          *)
            c65_errs="$c65_errs\n$c65_id: justified_by.kind is '${c65_kind:-missing}', not one of measurement/literature/none -- an entry whose kind this check cannot recognise is an entry it is not checking"
            ;;
        esac

        # Third cell non-empty, not merely present: a disclosure row whose "what is not measured"
        # cell is blank publishes a mechanism name and nothing else, which reads as coverage.
        c65_cell=$(printf '%s\n' "$c65_docrows" \
          | awk -F'|' -v id="$c65_id" '
              /^\|/ && index($2, "`" id "`") {
                c = $4; gsub(/^[ \t]+|[ \t]+$/, "", c);
                print (c == "" ? "@EMPTY@" : "@OK@"); exit }')
        case "$c65_cell" in
          '@OK@')    ;;
          '@EMPTY@') c65_errs="$c65_errs\n$c65_id: has a row in $c65_doc but its third cell is empty, so the document names the mechanism without saying what is or is not shown about it" ;;
          *)         c65_errs="$c65_errs\n$c65_id: no table row in section 1 or 2 of $c65_doc carries \`$c65_id\` in its first cell, so a shipped mechanism is disclosed nowhere" ;;
        esac
      done <<< "$(jq -r '(.components.hooks.mechanisms // [])[]
                         | [ (.id // ""), (.file // ""), ((.blocking // false) | tostring),
                             (.justified_by.kind // ""), (.justified_by.file // ""),
                             (.justified_by.run_id // ""), (.justified_by.entry // ""),
                             (.justified_by.measured_head // ""), (.justified_by.decide_by // "") ]
                         | map(tostring | gsub("[\\n\\t]"; " ")) | join("\u001f")' "$c65_inv" 2>/dev/null)"

      if [ -z "$c65_errs" ]; then
        ok "$c65_lbl ($c65_n mechanisms covering $c65_nw wired hook script(s): $c65_nmeas measurement, $c65_nlit literature, $c65_nnone unmeasured${c65_pend:+; blocking and still unmeasured:$c65_pend})"
      else
        bad "$c65_lbl" "$(printf '%b' "$c65_errs")"
      fi
    fi
  fi
else
  skip "$c65_lbl" "jq or git not installed"
fi

# Accounting. Every declared check must have reported either a result or a skip. A check
# that throws a shell error mid-body, or is wrapped in a conditional with no else, silently
# reports nothing — and used to leave no trace in the output at all. Now it fails the run.
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  bad "check accounting" "$((TOTAL - RAN - SKIPPED)) declared check(s) reported nothing"
fi

[ "$FAIL" -eq 0 ] && echo "VERIFIED" || echo "VERIFICATION FAILED"
exit "$FAIL"
