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
  _lk="$(git rev-parse --git-dir 2>/dev/null)/vstack-falsifiability.lock"
  if [ -f "$_lk" ] && kill -0 "$(cat "$_lk" 2>/dev/null)" 2>/dev/null; then
    printf 'REFUSED  tests/gate-falsifiability.sh (pid %s) is mutating this working tree.\n' "$(cat "$_lk")"
    printf '         Any result now would name a defect the harness planted. Wait for it to finish.\n'
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
  grep -q '^#!.*sh' <<<"$(head -1 "$f" 2>/dev/null)" || continue   # not a pipe: SIGPIPE + pipefail = 141
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
# check catches. Short principle names (prove-it-works) resolve via the principle- prefix;
# agent and command names are legitimate non-skill references; ALLOW covers generic hyphenated
# English and git plumbing that the token pattern also matches.
ALLOW='agent-written|auto-apply|auto-fire|cross-cutting|git-common-dir|is-inside-work-tree|multi-phase|one-line|one-step|options-survey|re-point|re-pins|re-pin|rev-parse|show-current|show-toplevel|symbolic-ref|to-the-point|token-efficient|name-only|per-prompt|session-context|session-start|operating-mode|two-line'
errs=""
# \b keeps a capitalized word (Per-prompt) from yielding a bogus mid-word token (er-prompt).
# Only the hook's heredoc prose is scanned — its shell code contains regex character classes
# (A-Za-z0-9) that shred into false skill-name tokens.
hook_prose=$(sed -n "/<<'EOF'/,/^EOF\$/p" claude/hooks/inject-session-context.sh)
for tok in $( { cat claude/CLAUDE.md; printf '%s\n' "$hook_prose"; } | grep -ohE '\b[a-z][a-z0-9]*(-[a-z0-9]+)+' | sort -u); do
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
    # mktemp, not fixed /tmp names: two Conductor workspaces verifying at once would
    # otherwise clobber each other's scratch files mid-check.
    md=$(mktemp -d)
    out=$(printf '{}\n' > "$md/a.json"; cp claude/settings.json "$md/b.json";
          jq -s --arg h "/tmp/hooks" --argjson retired '["probe_retired_key"]' \
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
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo repo-own"}]}]},"skillOverrides":{"ghost-skill":"off"},"permissions":{"allow":["Bash(ls)"]}}\n' > "$od/.claude/settings.json"
  if out=$(./overlay.sh "$od" 2>&1); then
    if jq -e '.permissions.allow[0] == "Bash(ls)" and (.skillOverrides["ghost-skill"] // null) == null' \
         "$od/.claude/settings.json" >/dev/null 2>&1; then
      ok "overlay merge path"
    else
      bad "overlay merge path" "merged settings lost user keys or kept dead skillOverrides"
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
errs=""; na=0; nc=0
for f in claude/agents/*.md; do
  [ -e "$f" ] || continue
  na=$((na+1))
  b=$(basename "$f" .md)
  name=$(awk -F': *' '/^name:/{print $2; exit}' "$f" | tr -d '"')
  desc=$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$f")
  [ "$name" = "$b" ] || errs="$errs\nagents/$b: name ($name) does not match filename"
  [ -n "$desc" ] || errs="$errs\nagents/$b: no description"
done
for f in claude/commands/*.md; do
  [ -e "$f" ] || continue
  nc=$((nc+1))
  b=$(basename "$f" .md)
  desc=$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$f")
  [ -n "$desc" ] || errs="$errs\ncommands/$b: no description"
done
[ "$na" -gt 0 ] || errs="$errs\nno agents found"
[ "$nc" -gt 0 ] || errs="$errs\nno commands found"
[ -z "$errs" ] && ok "agents ($na) + commands ($nc) loadable" || bad "agents + commands loadable" "$(printf '%b' "$errs")"

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
  # loop a no-op, so the count is asserted too.
  refs=$( { jq -r '.hooks[][]?.hooks[]?.command' claude/settings.json 2>/dev/null
            jq -r '.hooks[][]?.hooks[]?.command' claude/hooks/hooks.json 2>/dev/null
          } | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sort -u)
  nref=$(printf '%s\n' "$refs" | grep -c . )
  [ "$nref" -ge 4 ] || errs="$errs\nhook command extraction found $nref scripts, expected 4+ (the settings schema or jq filter changed)"
  for h in $refs; do
    [ -f "claude/$h" ] || errs="$errs\n$h: referenced in hook wiring but not in claude/hooks/"
  done

  [ -z "$errs" ] && ok "hook wiring (3 lanes, $nref scripts)" || bad "hook wiring" "$(printf '%b' "$errs")"
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
nsh=$(git ls-files 2>/dev/null | while IFS= read -r f; do
  grep -q '^#!.*sh' <<<"$(head -1 "$f" 2>/dev/null)" && printf 'x\n'
done | grep -c .)

want_for(){ # noun (lowercased, plural or singular) -> expected count, or empty if not covered
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

for f in README.md CHANGELOG.md .claude-plugin/marketplace.json claude/.claude-plugin/plugin.json \
         claude/skills/ATTRIBUTION.md claude/CLAUDE.md docs/how-skills-fire.md tests/README.md; do
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
$(printf '%s' "$norm" | grep -oE "[0-9]+ ($NOUNS)" | sort -u)
EOF

  # table form: "| Commands | 14 |"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    noun=$(printf '%s' "$row" | sed -E 's/^\| *//; s/ *\|.*//' | tr '[:upper:]' '[:lower:]')
    num=$(printf '%s' "$row" | sed -E 's/.*\| *([0-9]+).*/\1/')
    want=$(want_for "$noun")
    [ -n "$want" ] && [ "$num" != "$want" ] \
      && errs="$errs\n$f: table row '$noun' says $num, tree has $want"
  done <<EOF
$(printf '%s' "$norm" | grep -oE '\| *[A-Za-z][A-Za-z ]*\| *[0-9]+ *\|' | sort -u)
EOF
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
  _gd=$(git rev-parse --git-dir 2>/dev/null)
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
      printf '%s:%s' "$_r" "$(printf '%s' "$_o" | head -1)"
    }
    _live=$(_probe "$$" "")
    case "$_live" in
      2:REFUSED*) ;;
      *) g_errs="$g_errs\n  a live lock did not stop the gate: got [$_live], want rc 2 and REFUSED" ;;
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
    case "$cov" in *" $i "*) ;; *) errs="$errs\ncheck $i has no row in tests/gate-falsifiability.sh" ;; esac
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
  chk "session baseline"       "$(probe SessionStart '' '')"    1024 4096
  chk "skills profile"         "$(probe SessionStart skills 1)"  512 2560
  # The README publishes these byte counts as the cost column of its comparison table. A number
  # in prose that nothing re-derives is a number that goes stale, which is the failure this repo
  # keeps finding in its own docs — so the published figures are read back and compared.
  _full=$(probe SessionStart '' '')
  _sk=$(probe SessionStart skills 1)
  # Compared with tolerance, not for equality. The exact byte count is not a publishable
  # constant: the block embeds environment-dependent text, so this machine measured 3655 and CI
  # measured 3667 for the same commit. Demanding equality made the gate depend on where it ran,
  # which is a worse failure than the staleness it was added to prevent — a check that is only
  # true on one machine is the thing this repo keeps finding and removing.
  #
  # So the README publishes a rounded KB figure and this asserts the live value still rounds to
  # it. Real drift moves this by hundreds of bytes; noise moves it by tens.
  if [ -f README.md ] && grep -qE '~[0-9.]+ KB full / ~[0-9.]+ KB plugin' README.md; then
    _qf=$(grep -oE '~[0-9.]+ KB full' README.md | head -1 | grep -oE '[0-9.]+')
    _qs=$(grep -oE '~[0-9.]+ KB plugin' README.md | head -1 | grep -oE '[0-9.]+')
    _lf=$(awk -v b="$_full" 'BEGIN{printf "%.1f", b/1024}')
    _ls=$(awk -v b="$_sk"   'BEGIN{printf "%.1f", b/1024}')
    awk -v a="$_qf" -v b="$_lf" 'BEGIN{exit (a-b<0.15 && b-a<0.15)?0:1}' \
      || errs="$errs\nREADME quotes ~$_qf KB for the full session cost; live is ~$_lf KB"
    awk -v a="$_qs" -v b="$_ls" 'BEGIN{exit (a-b<0.15 && b-a<0.15)?0:1}' \
      || errs="$errs\nREADME quotes ~$_qs KB for the plugin session cost; live is ~$_ls KB"
  else
    # Absence of the anchor is the failure, not a reason to stop measuring. This guard was
    # `if grep -q ANCHOR; then compare; fi` with no else, and cc76ba8 -- a README rewrite from 469
    # lines to 226 -- moved the sentence it keys on. The comparison then did nothing for eleven
    # commits while the check went on printing ok, and the same rewrite killed a second guard the
    # same way. A gate whose anchor lives in prose degrades to silence the moment someone edits
    # the prose, and prose gets edited.
    errs="$errs\nREADME no longer publishes the ~N KB full / ~N KB plugin figures, so the published cost was compared against nothing -- restore the anchor or rewrite this to read the new one"
  fi
  [ -z "$errs" ] \
    && ok "injected context bounded (digest $(probe UserPromptSubmit '' 1) B, baseline $_full B)" \
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
# This is the same defect class as the stale `orchestrate.md` — prose and installed tree
# disagreeing — just pointing the other way. Check 12 counts things; nothing read the paths back.
# A referenced path either maps to something in this repo that install.sh copies, or it is
# runtime state; anything else is a promise the installer does not keep.
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
# shellcheck disable=SC2088  # the heredoc below greps for the literal "~/..." spelling in docs
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  runtime_path "$ref" && continue
  src=$(src_for "$ref")
  if [ -z "$src" ]; then
    errs="$errs\n$ref: no install.sh rule puts anything there"
  elif [ ! -e "$src" ]; then
    errs="$errs\n$ref: install.sh would copy $src, which does not exist in this repo"
  fi
done <<EOF
$(grep -rhoE '~/\.(claude|config/agents|conductor)[A-Za-z0-9._/-]*' \
    README.md claude/commands claude/agents claude/skills 2>/dev/null \
  | sed 's#[.,:;)`"]*$##; s#/$##' | sort -u)
EOF
[ -z "$errs" ] && ok "referenced install paths exist" \
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
      printf '%s\n' "$now"  | grep -qx "$k" && errs="$errs\n$k: still shipped in claude/settings.json, so it is not retired"
      printf '%s\n' "$ever" | grep -qx "$k" || errs="$errs\n$k: claude/settings.json has never shipped it — not this repo's key to delete"
    done
    [ -z "$errs" ] && ok "RETIRED names only retired keys ($(printf '%s' "$retired" | jq -r 'length') entries)" \
      || bad "RETIRED names only retired keys" "$(printf '%b' "$errs")"
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
  g_want(){ # <command> <expected>
    got=$(g_decide "$1")
    [ "$got" = "$2" ] || errs="$errs\n'$1' -> $got, expected $2"
  }
  g_want 'rm -rf /'                      deny
  g_want 'rm -rf ~'                      deny
  g_want 'rm -rf $HOME'                  deny
  g_want 'git push --force origin main'  deny
  g_want 'git push -f origin master'     deny
  g_want 'rm -rf /etc/nginx'             ask
  g_want 'git reset --hard HEAD~3'       ask
  g_want 'psql -c "DROP TABLE users"'    ask
  g_want 'terraform destroy'             ask
  g_want 'echo x && rm -rf /'            ask
  g_want 'rm -rf node_modules /etc'      ask
  g_want 'rm -rf node_modules'           allow
  g_want 'rm -rf dist'                   allow
  g_want 'npm test'                      allow
  g_want 'git push origin feature-x'     allow
  g_want 'git commit -m "wip"'           allow
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

  # Unparseable or absent input must never reach allow. A guard that opens on malformed input
  # has inverted its own purpose, and malformed input is exactly what an attacker sends.
  for bad in 'not json' ''; do
    d=$(printf '%s' "$bad" | bash claude/hooks/guard-destructive.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ "$d" = ask ] || errs="$errs\nmalformed payload -> $d, expected ask"
  done
  [ -z "$errs" ] && ok "destructive guard decides correctly (16 commands, 3 tiers)" \
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
  # there. Only asserted where the checkout has tags at all -- a shallow clone has none, and the
  # branch below already declines to measure in that case.
  pins=""
  for f in README.md docs/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r pv; do
      [ -n "$pv" ] || continue
      if [ "$pv" != "$mv_" ]; then
        pins="$pins\n  $f pins v$pv"
      elif [ -n "$(git tag -l 2>/dev/null | head -1)" ] \
           && ! git rev-parse -q --verify "refs/tags/v$pv" >/dev/null 2>&1; then
        pins="$pins\n  $f pins v$pv, which is not a tag in this repository (the URL 404s)"
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
    drift=$(git diff --name-only "v$mv_..HEAD" -- claude/ mcp/ bin/ shell/ conductor/ \
              install.sh bootstrap.sh overlay.sh uninstall.sh setup-machine.sh 2>/dev/null)
    [ -z "$drift" ] && ok "declared version matches what installs (v$mv_)" \
      || bad "declared version matches what installs" \
             "$(printf 'the manifests say v%s but the payload has moved since that tag:\n%s\nbump the version and changelog it, or the plugin and unpinned lanes ship something v%s never described' "$mv_" "$(printf '%s' "$drift" | sed 's/^/  /' | head -10)" "$mv_")"
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
  skip "documented platforms match CI" "no .github/workflows/verify.yml"
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
    hit_(){ printf '{"session_id":"vfy-%s","transcript_path":"%s/t.jsonl","stop_hook_active":%s}' \
              "$1" "$md" "${2:-false}" | "./$sm" 2>/dev/null; }
    W='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/README.md"}}]}}'
    T='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/App.tsx"}}]}}'
    U='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"unslop"}}]}}'
    P='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/main.py"}}]}}'

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

    rm -rf "$md"; rm -f "${TMPDIR:-/tmp}"/vstack-mandate-vfy-* 2>/dev/null
    [ -z "$errs" ] && ok "skill mandate decides correctly (7 cases, both directions)" \
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
  skip "every doc is reachable" "no docs/ directory"
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
  sc_files=$(git ls-files 2>/dev/null | while IFS= read -r f; do
    grep -q '^#!.*sh' <<<"$(head -1 "$f" 2>/dev/null)" && printf '%s\n' "$f"
  done)
  sc_out=$(while IFS= read -r f; do
    [ -n "$f" ] && shellcheck -S warning -f gcc "$f" 2>/dev/null
  done <<<"$sc_files")
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
# A reason counts if it is on the same line after the code list, which is how the other five
# suppressions in this repo are written, or on the line immediately above. Both are readable at
# the point of the disable; a reason three lines away is not.
bare=""
nsup=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q '^#!.*sh' <<<"$(head -1 "$f" 2>/dev/null)" || continue
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
    # payload in tests/gate-falsifiability.sh, and reported 9 suppressions where there are 6.
  done <<<"$(grep -nE '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+disable=' "$f" 2>/dev/null)"
done <<<"$(git ls-files 2>/dev/null)"
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
  esac
  [ -n "$(git grep -l -F "${f##*/}" -- . ":(exclude)$f" 2>/dev/null | head -1)" ] \
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
  ( export VSTACK_NO_GRILL=1
    got=$(g_ask gv3 "$g_long")
    [ "$got" = 0 ] || printf 'ESCAPE_FAILED\n' ) | grep -q ESCAPE_FAILED \
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
  o_home="$o_tmp/empty"; mkdir -p "$o_home"
  o_out=$(printf '{"hook_event_name":"SessionStart"}' \
          | HOME="$o_home" "$o_dir/.claude/hooks/inject-session-context.sh" 2>/dev/null \
          | jq -r '.hookSpecificOutput.additionalContext // ""')
  case "$o_out" in
    *"$o_marker"*) ;;
    *) o_errs="$o_errs\n  a sandbox session got no policy at all — the overlay is its only lane" ;;
  esac
  # Every byte is paid on every session there, and check 18 cannot see this variant because it
  # probes the source copy, which is not an overlay and never appends the policy.
  o_sz=$(printf '%s' "$o_out" | wc -c | tr -d ' ')
  [ "${o_sz:-0}" -le 6144 ] \
    || o_errs="$o_errs\n  the sandbox session block is $o_sz bytes, over the 6144 cap"

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
