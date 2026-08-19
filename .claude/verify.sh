#!/usr/bin/env bash
# verify.sh — proof that this bundle is installable and portable.
#
# Run by the verify-gate.sh Stop hook: a non-zero exit blocks an agent from claiming the
# work is done. Checks that need a missing tool SKIP rather than fail, so a fresh clone
# without jq still gets a useful answer instead of a red herring.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAIL=0
ok(){   printf 'ok    %s\n' "$1"; }
bad(){  printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; FAIL=1; }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; }

# --- 1. every shell script parses ----------------------------------------------------------
errs=""
while IFS= read -r f; do
  head -1 "$f" | grep -q '^#!.*sh' || continue
  out=$(bash -n "$f" 2>&1) || errs="$errs\n$f: $out"
done < <(find . -path ./.git -prune -o -type f \( -name "*.sh" -o -path "./bin/*" \) -print)
[ -z "$errs" ] && ok "shell syntax" || bad "shell syntax" "$(printf '%b' "$errs")"

# --- 2. every JSON file parses --------------------------------------------------------------
if command -v jq >/dev/null; then
  errs=""
  for f in claude/settings.json mcp/servers.json claude/hooks/hooks.json \
           .claude-plugin/marketplace.json claude/.claude-plugin/plugin.json; do
    [ -f "$f" ] || { errs="$errs\n$f: missing"; continue; }
    jq -e . "$f" >/dev/null 2>&1 || errs="$errs\n$f: invalid JSON"
  done
  [ -z "$errs" ] && ok "json valid" || bad "json valid" "$(printf '%b' "$errs")"
else
  skip "json valid" "jq not installed"
fi

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
  name=$(awk -F': *' '/^name:/{print $2; exit}' "$s" | tr -d '"')
  desc=$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$s" | tr -d '"')
  dir=$(basename "$(dirname "$s")")
  [ -n "$name" ] || errs="$errs\n$dir: no name in frontmatter"
  [ "$name" = "$dir" ] || errs="$errs\n$dir: name ($name) does not match directory"
  [ -n "$desc" ] || errs="$errs\n$dir: no description"
  grep -q 'disable-model-invocation' "$s" && errs="$errs\n$dir: disable-model-invocation blocks auto-trigger"
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
[ -z "$errs" ] && ok "skills ($n) loadable" || bad "skills loadable" "$(printf '%b' "$errs")"

# --- 4. nothing is pinned to the author machine ----------------------------------------------
# The bracket class keeps this pattern from matching its own source line. Generic
# placeholders in docs (/Users/you) are fine; a real account name is what breaks portability.
hits=$(grep -rInE --exclude-dir=.git "/Users/[A-Za-z0-9]" . 2>/dev/null \
       | grep -vE "/Users/(you|USER|user|username|name)\b" | head -5)
[ -z "$hits" ] && ok "no hardcoded home paths" || bad "no hardcoded home paths" "$hits"

# --- 5. no credentials committed --------------------------------------------------------------
# Matches real token shapes and any KEY/TOKEN/SECRET assigned a long opaque value. The
# example file assigns nothing, so it passes; a filled-in secrets.env would not.
hits=$(grep -rIn --exclude-dir=.git -E \
  '(sk-ant-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|(KEY|TOKEN|SECRET|PASSWORD)[A-Z_]*=[A-Za-z0-9_/+-]{20,})' \
  . 2>/dev/null | head -5)
[ -z "$hits" ] && ok "no committed secrets" || bad "no committed secrets" "$hits"

# --- 6. no infrastructure identifiers ---------------------------------------------------------
# This repo is public and its routines are templates. Real Vercel project or team IDs, Claude
# Code environment IDs, and cloud routine trigger IDs identify live infrastructure, so they
# belong in a local copy, never here. Placeholders ending in _ID or _xxx pass.
hits=$(grep -rInE --exclude-dir=.git \
  '(prj_|team_|env_|trig_)[A-Za-z0-9]{12,}' . 2>/dev/null \
  | grep -vE '(YOUR_[A-Z_]*ID|_xxx|placeholder)' | head -5)
[ -z "$hits" ] && ok "no infrastructure ids" || bad "no infrastructure ids" "$hits"

# --- 7. every skill named in prose exists on disk ----------------------------------------------
# CLAUDE.md and the session hook route situations to skills by name. Deleting or renaming a
# skill leaves those references dangling and the routing silently dead — this is the drift the
# check catches. Short principle names (prove-it-works) resolve via the principle- prefix;
# agent and command names are legitimate non-skill references; ALLOW covers generic hyphenated
# English and git plumbing that the token pattern also matches.
ALLOW='agent-written|auto-apply|auto-fire|cross-cutting|git-common-dir|is-inside-work-tree|multi-phase|one-line|one-step|options-survey|re-point|re-pins|rev-parse|show-current|show-toplevel|symbolic-ref|to-the-point|token-efficient|name-only|per-prompt|session-context|session-start|operating-mode|two-line'
errs=""
# \b keeps a capitalized word (Per-prompt) from yielding a bogus mid-word token (er-prompt).
for tok in $(grep -ohE '\b[a-z][a-z0-9]*(-[a-z0-9]+)+' claude/CLAUDE.md claude/hooks/inject-session-context.sh | sort -u); do
  [ -d "claude/skills/$tok" ] && continue
  [ -d "claude/skills/principle-$tok" ] && continue
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
  prog=$(sed -n "/^  jq -s --arg h /,/^  ' \"\$US\"/p" install.sh \
         | sed '1d;$d')
  if [ -z "$prog" ]; then
    bad "settings merge program" "could not extract the jq program from install.sh"
  else
    out=$(printf '{}\n' > /tmp/vs-merge-a.json; cp claude/settings.json /tmp/vs-merge-b.json;
          jq -s --arg h "/tmp/hooks" --arg n "true" "$prog" /tmp/vs-merge-a.json /tmp/vs-merge-b.json 2>&1)
    if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      ok "settings merge program"
    else
      bad "settings merge program" "$out"
    fi
    rm -f /tmp/vs-merge-a.json /tmp/vs-merge-b.json
  fi
fi

# --- 9. the installer runs ---------------------------------------------------------------------
# Dry run: exercises every code path in install.sh without touching the filesystem.
if command -v jq >/dev/null; then
  out=$(./install.sh --dry-run 2>&1)
  if [ $? -eq 0 ]; then ok "install.sh --dry-run"; else bad "install.sh --dry-run" "$out"; fi
else
  skip "install.sh --dry-run" "jq not installed"
fi

echo
[ "$FAIL" -eq 0 ] && echo "VERIFIED" || echo "VERIFICATION FAILED"
exit "$FAIL"
