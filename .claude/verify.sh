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
NOUNS='skills?|checks?|agents?|subagents?|sub-agents?|commands?|hooks?|CLI wrappers?|cases?|MCP servers?|shell scripts?'

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

# --- 13. the two plugin manifests agree on a version -------------------------------------------
# marketplace.json and plugin.json each carry their own version string and nothing has ever
# compared them. A release that bumps one and forgets the other publishes a marketplace entry
# pointing at a differently-numbered plugin.
if command -v jq >/dev/null; then
  mv_=$(jq -r '.plugins[0].version // "missing"' .claude-plugin/marketplace.json 2>/dev/null)
  pv_=$(jq -r '.version // "missing"' claude/.claude-plugin/plugin.json 2>/dev/null)
  [ "$mv_" = "$pv_" ] && ok "plugin manifests agree (v$mv_)" \
    || bad "plugin manifest versions" "marketplace.json says $mv_, plugin.json says $pv_"
else
  skip "plugin manifest versions" "jq not installed"
fi

# --- 14. the Stop-hook gate actually blocks ----------------------------------------------------
# The gate is the mechanism every other check depends on: none of them matter if a failing
# verify.sh does not stop the agent. It hardcoded /usr/bin/jq, so on a host without that exact
# path the block decision was never emitted and the gate enforced nothing while looking
# installed. Drive it end to end against a seeded failing verify.sh, in both jq conditions.
if command -v jq >/dev/null && command -v git >/dev/null; then
  gd=$(mktemp -d)
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
  # Floors are deliberately far below the measured sizes (305 / 3655 / 2178). They are not a
  # second cap and must not fire when someone trims a sentence; they answer "did the hook say
  # anything at all", which nothing else here asks.
  chk(){ # label value floor cap
    [ "$2" -ge "$3" ] || errs="$errs\n$1: $2 bytes is under the $3 byte floor -- the hook emitted nothing or nearly nothing"
    [ "$2" -le "$4" ] || errs="$errs\n$1: $2 bytes exceeds the $4 byte cap"
  }
  chk "per-prompt digest"      "$(probe UserPromptSubmit '' 1)"  128  512

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
  # Cap derived, not chosen: worst-case measured 4630 B on this commit (invariant text 3990 B +
  # the hook's own 320+80+240 B worst-case root/branch/base padding), +25% headroom to match the
  # philosophy stated at the top of this check. 5888 is that number rounded up to a clean
  # multiple of 128. Recompute _baseline_worst by hand if this ever needs re-deriving -- it is
  # not a magic constant, it is this formula's output on the day it was set. Below this cap: the
  # WORKSPACE CONVENTIONS block's structural text is bounded. Above it: something added prose
  # there, on every checkout, regardless of path length or remote default branch.
  _baseline_cap=5888
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
    && ok "injected context bounded (digest $(probe UserPromptSubmit '' 1) B, baseline $_baseline_raw B raw / $_baseline_inv B invariant / $_baseline_worst B worst-case)" \
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
# shellcheck disable=SC2088  # the heredoc below greps for the literal "~/..." spelling in docs
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  runtime_path "$ref" && continue
  external_path "$ref" && continue
  install_generated "$ref" && continue
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
[ -z "$errs" ] && ok "referenced install paths exist ($ig_n install_generated entr$([ "$ig_n" = 1 ] && printf y || printf ies) floored)" \
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
# Three lanes install three different trees, and only one of them is pinned. `VSTACK_REF=v1.4.0`
# gets the tag; the unpinned bootstrap and the plugin marketplace both take the default branch.
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
  else
    md=$(mktemp -d); errs=""
    say_(){ printf '%s\n' "$@" > "$md/t.jsonl"; }
    # VSTACK_NO_DELEGATION_LOG=1: every hit_ call below feeds the hook a synthetic fixture
    # transcript under a "vfy-*" session id, not a real session. Without this, each gate run
    # appends ~12 synthetic lines to the operator's real ~/.claude/vstack-delegation-log.jsonl
    # (one per case that reaches the logger before stop_hook_active/VSTACK_NO_MANDATE/the
    # 2-strike latch short-circuits it) -- the exact vfy-* contamination found predating any
    # instrumented run of this suite.
    hit_(){ printf '{"session_id":"vfy-%s","transcript_path":"%s/t.jsonl","stop_hook_active":%s}' \
              "$1" "$md" "${2:-false}" | VSTACK_NO_DELEGATION_LOG=1 "./$sm" 2>/dev/null; }
    W='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}}]}}'
    T='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App.tsx"}}]}}'
    U='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"unslop"}}]}}'
    P='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/main.py"}}]}}'
    TA='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"running"}]}}'
    TB='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"tool":"Skill"}},{"type":"text","text":"qa (BETH J-42)"}]}}'

    # blocks when the rule is unmet
    say_ "$W"; hit_ a | grep -q '"decision":"block"' || errs="$errs\nwrote prose without unslop and it did not block"
    say_ "$T"; hit_ b | grep -q '"decision":"block"' || errs="$errs\nwrote TypeScript without the ts skill and it did not block"
    # silent when the rule is met, or does not apply
    say_ "$W" "$U"; [ -z "$(hit_ c)" ] || errs="$errs\nblocked even though unslop had run"
    say_ "$P";      [ -z "$(hit_ d)" ] || errs="$errs\nblocked on a file no mandate covers"
    # cannot trap the session
    say_ "$W"; [ -z "$(hit_ e true)" ] || errs="$errs\nblocked while stop_hook_active was already true"
    say_ "$W"; [ -z "$(VSTACK_NO_MANDATE=1 hit_ f)" ] || errs="$errs\nignored VSTACK_NO_MANDATE=1"
    say_ "$W"; hit_ g >/dev/null; hit_ g >/dev/null
    [ -z "$(hit_ g)" ] || errs="$errs\ndid not latch open after 2 blocks in one session"
    # multi-directory, multi-type work: breadth mandate
    F1='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"fix/test1.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test2.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test3.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test4.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"fix/test5.sh","content":""}}]}}'
    say_ "$F1"; [ -z "$(hit_ h)" ] || errs="$errs\nfive fixtures in one dir falsely blocked multi-dir mandate"
    F2='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"a.sh","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"lib/b.json","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"src/c.py","content":""}}]}}'
    say_ "$F2"; hit_ i | grep -q '"decision":"block"' || errs="$errs\nthree dirs with two extensions did not block multi-dir mandate"
    F3='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":".editorconfig","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"home/.gitignore","content":""}},{"type":"tool_use","name":"Write","input":{"file_path":"proj/.npmrc","content":""}}]}}'
    say_ "$F3"; [ -z "$(hit_ j)" ] || errs="$errs\nthree dotfiles across three dirs falsely blocked multi-dir mandate"
    # agent naming: dispatch attribution required
    say_ "$TA"; hit_ k | grep -q '"decision":"block"' || errs="$errs\nTask call with no call sign did not block"
    say_ "$TB"; [ -z "$(hit_ l)" ] || errs="$errs\nTask call with call sign (BETH) blocked anyway"
    say_ "$P"; [ -z "$(hit_ m)" ] || errs="$errs\nzero Task calls falsely blocked on naming rule"
    say_ "$TA"; [ -z "$(VSTACK_NO_MANDATE=1 hit_ n)" ] || errs="$errs\nVSTACK_NO_MANDATE=1 did not disable agent naming block"

    # "*vfy-[a-n]*" not "vfy-*": the mandate latch split (f4f5468) inserts "ckpt-" between the
    # "vstack-mandate-" anchor and the session id, and the delegation-family counters (h/i/j
    # exercise the breadth mandate) append ".delegate"/".delegate-ts"/".delegate-scan"/".lock"
    # after it -- a bare "vfy-*" anchor matches none of the ckpt files and missed every one of
    # them (verified: 12 stale vstack-mandate-ckpt-vfy-* sat in $TMPDIR across runs of this gate
    # before this fix). Anchored on both ends the way 76d2366 fixed the identical bug in
    # tests/test-breadth-mandate.sh: "vfy-[a-n]" is exactly the 14 single-letter session ids this
    # block hands to hit_ above, so this cannot reach a file this check did not create.
    rm -rf "$md"; rm -f "${TMPDIR:-/tmp}"/vstack-mandate-*vfy-[a-n]* 2>/dev/null
    [ -z "$errs" ] && ok "skill mandate decides correctly (14 cases, both directions)" \
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
  d_ev='{"hook_event_name":"UserPromptSubmit","session_id":"dv1","prompt":"x"}'
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
  # 7168 (7 KiB) is not fitted to a single reading. With both leaks above pinned, this scenario
  # measured 6886 B on macOS (the longest $TMPDIR: /private/var/folders/.../T/tmp.XXXXXXXXXX) and
  # 6754-6784 B in debian, alpine and ubuntu containers (short /tmp/tmp.XXXXXXXXXX, and
  # init.defaultBranch varies main/master by 2 bytes) — same commit, same content, ~130 B of pure
  # tmpdir-naming noise, the same kind of machine-to-machine drift check 18 already documents in
  # its own README-comparison tolerance. 7168 clears the worst of those with ~280 B of headroom,
  # matching check 18's absolute margin on its own baseline (441 B) and skills (382 B) rows: room
  # for a sentence added on purpose, not for a block that ran away.
  o_sz=$(printf '%s' "$o_out" | wc -c | tr -d ' ')
  [ "${o_sz:-0}" -le 7168 ] \
    || o_errs="$o_errs\n  the sandbox session block is $o_sz bytes, over the 7168 cap"

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
    && ok "the policy document reaches a session exactly once (sandbox $o_sz B, 6 cases)" \
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

    # An unmet mandate every time it is asked: prose written, unslop never run. What matters
    # here is the latch, not which mandate trips it, so the simplest one that trips reliably.
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}}]}}' \
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

    # Direction 2 (absence is not zero): a session with no dispatches must render no RICK
    # segment at all. "·0▸" would claim zero delegation happened when the truth is nobody has
    # asked yet -- a fresh session and a session that delegated zero times on purpose are not
    # the same state, and only the absent-file case is this one.
    [ -e "$c44_cnt" ] && c44_errs="$c44_errs\ncounter file already existed before any dispatch: $c44_cnt"
    c44_out0=$(c44_payload | "./$sl" 2>/dev/null)
    case "$c44_out0" in
      *RICK*) c44_errs="$c44_errs\na session with zero dispatches rendered a RICK segment: $c44_out0" ;;
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
    jq -e --arg sid "$c44_sid" --arg desc "$c44_desc" --argjson plen "$c44_promptlen" \
      '.session_id==$sid and .dispatch_index==1 and .tool_name=="Task"
       and .description==$desc and .prompt_bytes==$plen and (.result_bytes|type)=="number"
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

    # Direction 3b: the secrecy boundary. description is recorded verbatim by design; prompt and
    # result are sizes only. Asserted by grepping the WHOLE replay file for each sentinel string
    # rather than trusting the schema -- a byte-count field can be quietly swapped for the text
    # it was meant to summarize without ever changing its name.
    grep -qF "$c44_desc" "$c44_replay" \
      || c44_errs="$c44_errs\ndescription sentinel never appears in the replay log -- description is not being recorded verbatim"
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
  if [ -n "$_c50_jobs" ] && [ -n "$_c50_req" ]; then
    _c50_unread=$(comm -23 <(printf '%s\n' "$_c50_jobs") <(printf '%s\n' "$_c50_req"))
    _c50_phantom=$(comm -13 <(printf '%s\n' "$_c50_jobs") <(printf '%s\n' "$_c50_req"))
    [ -z "$_c50_unread" ] \
      || c50_errs="$c50_errs\nCI job(s) no gate reads: $(printf '%s' "$_c50_unread" | tr '\n' ' ') -- add them to REQUIRED_CHECKS in $_c50_rl or the release publishes over their red"
    [ -z "$_c50_phantom" ] \
      || c50_errs="$c50_errs\nREQUIRED_CHECKS name(s) with no job behind them: $(printf '%s' "$_c50_phantom" | tr '\n' ' ') -- nothing will ever report for these, so the gate stays UNDECIDED forever"
  fi
  _c50_njobs=$(printf '%s' "$_c50_jobs" | grep -c . )
  [ -z "$c50_errs" ] \
    && ok "every CI job is a required check ($_c50_njobs jobs, both directions)" \
    || bad "every CI job is a required check" "$(printf '%b' "$c50_errs")"
else
  bad "every CI job is a required check" "$_c50_wf or $_c50_rl is missing -- CI itself is gone, which is a failure and not an environment fact"
fi

echo
# Accounting. Every declared check must have reported either a result or a skip. A check
# that throws a shell error mid-body, or is wrapped in a conditional with no else, silently
# reports nothing — and used to leave no trace in the output at all. Now it fails the run.
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  bad "check accounting" "$((TOTAL - RAN - SKIPPED)) declared check(s) reported nothing"
fi

[ "$FAIL" -eq 0 ] && echo "VERIFIED" || echo "VERIFICATION FAILED"
exit "$FAIL"
