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
  for ev in SessionStart UserPromptSubmit PostToolUse Stop PostToolUseFailure; do
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
    for ev in SessionStart UserPromptSubmit PostToolUse Stop PostToolUseFailure; do
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

want_for(){ # noun (lowercased, plural or singular) -> expected count, or empty if not covered
  case "$1" in
    skill|skills)                                   printf '%s' "$nsk" ;;
    agent|agents|subagent|subagents|sub-agent|sub-agents) printf '%s' "$nag" ;;
    command|commands)                               printf '%s' "$ncm" ;;
    hook|hooks)                                     printf '%s' "$nhk" ;;
    "cli wrapper"|"cli wrappers")                   printf '%s' "$nwr" ;;
    case|cases)                                     printf '%s' "$ncs" ;;
    "mcp server"|"mcp servers")                     printf '%s' "$nmc" ;;
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

errs=""
for f in README.md .claude-plugin/marketplace.json claude/.claude-plugin/plugin.json \
         claude/skills/ATTRIBUTION.md claude/CLAUDE.md docs/how-skills-fire.md tests/README.md; do
  [ -f "$f" ] || continue
  norm=$(tr '\n' ' ' < "$f" | tr -s '[:space:]' ' ')
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
$(printf '%s' "$norm" | grep -oE '[0-9]+ ((sub-?)?agents?|skills?|commands?|hooks?|cases?|MCP servers?|CLI wrappers?)' | sort -u)
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
  && ok "doc counts match tree ($nsk skills, $nag agents, $ncm commands, $nhk hooks, $ncs test cases)" \
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
      | (keys - $A - ["permissions"]) | join(" ")' "$ov/.claude/settings.json" 2>/dev/null)
    [ -n "$leaked" ] && errs="$errs\nshipped non-project keys: $leaked"
    jq -e 'has("theme")' "$ov/.claude/settings.json" >/dev/null 2>&1 \
      && errs="$errs\nleft a personal key (theme) behind on an already-overlaid repo"
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
  chk(){ [ "$2" -le "$3" ] || errs="$errs\n$1: $2 bytes exceeds the $3 byte cap"; }
  chk "per-prompt digest"      "$(probe UserPromptSubmit '' 1)" 512
  chk "session baseline"       "$(probe SessionStart '' '')"    4096
  chk "skills profile"         "$(probe SessionStart skills 1)" 2560
  [ -z "$errs" ] \
    && ok "injected context bounded (digest $(probe UserPromptSubmit '' 1) B, baseline $(probe SessionStart '' '') B)" \
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

# --- 22. a skill never tells the model to run a file the port does not ship --------------------
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
    [ -n "$refs" ] || continue
    missing=""
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      base=${r##*scripts/}
      [ -e "$d/scripts/$base" ] || missing="$missing $base"
    done <<EOF
$refs
EOF
    [ -n "$missing" ] || continue
    # The notice has to reach whoever is reading. It counts in the file carrying the commands,
    # or in SKILL.md, which every reader passes through first.
    if ! grep -qiE 'unavailable here|not (included|vendored)|Not vendored here' "$f" \
       && ! grep -qiE 'unavailable here|not (included|vendored)' "$sk"; then
      errs="$errs\n${f#claude/skills/}: runs scripts it does not ship ($missing ) with no notice"
    fi
  done <<EOF
$(find "$d" -type f -name '*.md' | sort)
EOF
done
[ -z "$errs" ] && ok "skills disclose scripts they do not ship" \
  || bad "skills disclose scripts they do not ship" "$(printf '%b' "$errs")"

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
