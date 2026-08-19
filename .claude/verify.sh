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
scan "no hardcoded home paths" \
  '/Users/[A-Za-z0-9]' \
  '/Users/(you|USER|user|username|name)\b'

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
          jq -s --arg h "/tmp/hooks" --arg n "true" "$prog" "$md/a.json" "$md/b.json" 2>&1)
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
    for ev in SessionStart UserPromptSubmit PostToolUse Stop PostToolUseFailure SessionEnd PermissionRequest; do
      printf '%s' "$prog" | grep -qE "^ *$ev: *\[" || errs="$errs\n$ev: missing from install.sh hook rebuild"
    done
    # The notify hook is what reaches the phone. It is wired to five of the seven events.
    nn=$(printf '%s' "$prog" | grep -cF 'command:$n')
    [ "$nn" -eq 5 ] || errs="$errs\nnotify wired to $nn sites in install.sh, expected 5"
  fi

  # Lane 3 — plugin marketplace. Deliberately narrow, and asserted as an exact set rather than
  # a minimum. The manifest promises routing plus the verify gate and nothing more, because
  # inject-session-context.sh drops the token/delegation/autonomy policy under
  # VSTACK_PROFILE=skills: those rules are one person's operating preference and have no
  # business riding along with a skill pack a stranger installed. Asserting the exact set means
  # widening this lane has to be a deliberate edit here, not a quiet drift.
  got=$(jq -r '.hooks | keys_unsorted[]' claude/hooks/hooks.json 2>/dev/null | sort | tr '\n' ' ' | sed 's/ *$//')
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
ncs=$(grep -cE '^run_case ' tests/auto-trigger.sh 2>/dev/null || echo 0)
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
    docs/how-skills-fire.md) printf '%s\n' 'installed 18 skills correctly' '44 skills' ;;
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
  o=$(printf '{"session_id":"vs-gate-nojq"}' \
      | env PATH="$gd/bin" HOME="$gd/home" TMPDIR="$gd/tmp" CLAUDE_PROJECT_DIR="$gd/repo" bash "$gd/nojq.sh" 2>/dev/null)
  printf '%s' "$o" | jq -e '.decision=="block"' >/dev/null 2>&1 \
    || errs="$errs\nwithout jq: a failing verify.sh did not produce a parseable decision:block"

  rm -rf "$gd"

  # And no hook may reach for jq by absolute path again. /usr/bin/jq is fine as a preference
  # inside the resolver, but calling it directly is what made these hooks inert off macOS —
  # the gate stopped blocking and the session hook stopped injecting the routing block at all.
  hp=$(grep -n '/usr/bin/jq' claude/hooks/*.sh 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' | grep -vF '[ -x /usr/bin/jq ]')
  [ -n "$hp" ] && errs="$errs\nhooks calling jq by absolute path instead of resolving it:\n$hp"

  [ -z "$errs" ] && ok "stop-hook gate blocks (jq present and absent)" \
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
  else
    errs="$errs\noverlay.sh failed:\n$out"
  fi
  rm -rf "$ov"
  [ -z "$errs" ] && ok "overlay ships project keys only" \
    || bad "overlay ships project keys only" "$(printf '%b' "$errs")"
else
  skip "overlay ships project keys only" "jq or git not installed"
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
