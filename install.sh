#!/usr/bin/env bash
# install.sh — install the whole vstack bundle onto this Mac.
#
# Idempotent: safe to re-run any number of times. Every file it overwrites is copied to a
# timestamped backup dir first, and it never touches secrets you already have.
#
# Lanes it materialises:
#   $CLAUDE_CONFIG_DIR, or ~/.claude   hooks, agents, commands, skills, settings
#   ~/.config/agents/bin/      CLI wrappers (deploy, headless runner, MCP shims, doctor)
#   ~/.config/agents/shell/    zsh parity wrapper + env snippet, wired into .zshrc/.zshenv
#   .claude.json               MCP server entries (merged, never clobbered)
#
# Usage:
#   ./install.sh                  install the config
#   ./install.sh --with-deps      install the tools first (fresh machine)
#   ./install.sh --bypass-permissions
#                                 stop asking before every tool call. Deliberately opt-in:
#                                 this repo is public, and nobody should get it by default.
#   ./install.sh --dry-run        print what would change, touch nothing
#   ./install.sh --profile=NAME   install a subset instead of everything (or VSTACK_PROFILE=NAME).
#                                 core        safety/lifecycle only: hooks that guard, format,
#                                             self-heal and gate Stop; doctor; vstack trust;
#                                             the CLI wrappers; statusline. No skills, no agents,
#                                             no CLAUDE.md, no routing policy.
#                                 team        core + the multi-agent roster: all 14 agents,
#                                             /team (+ release/review/test), dispatch logging
#                                             and the delegation mandate, the swarm skill.
#                                 ui          core + the UI lane: ui-engineer, design-reviewer,
#                                             accessibility-auditor, and the 4 UI-tagged skills
#                                             (component-registry, impeccable, ui-iterate,
#                                             agent-browser). No roster, no routing policy.
#                                 opinionated everything -- today's install.sh. Default: a bare
#                                             ./install.sh is unaffected by this flag existing.
#                                 Membership is derived below, next to PROFILE_HOOK_CORE and its
#                                 neighbours, with the evidence read out of each file it names.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code reads its user config from $CLAUDE_CONFIG_DIR when that is set, and from
# ~/.claude otherwise. vstack hardcoded ~/.claude, so anyone running with CLAUDE_CONFIG_DIR
# pointed elsewhere — VMs, containers, and anyone keeping separate profiles — got a complete,
# clean-looking install into a directory Claude Code never reads. It failed silently and
# looked like success, which is the worst way for an installer to be wrong.
#
# .claude.json follows the same rule: it sits inside the config dir when one is named, and
# beside it at ~/.claude.json when it is not.
CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then CJSON="$CDIR/.claude.json"; else CJSON="$HOME/.claude.json"; fi
# Second-resolution timestamps collide, and mkdir -p is happy to reuse the directory. Two
# installs in the same second therefore shared one backup, and the second run overwrote the
# first run's copies with files vstack had just installed — destroying the only record of what
# the user had before. Automation, retries and CI hit this easily. Claim the directory
# exclusively and step to a suffix when it is taken.
BK_BASE="$HOME/.config/agents/backups/install-$(date +%Y%m%d-%H%M%S)"
# Every path this install owns, appended as it is written, and read by the NEXT install to tell
# its own previous payload from the user's files. This is a plain, unsigned, world-readable-to-
# the-user text list of paths -- an ownership record, not an attestation. Nothing here is signed
# or hashed against tampering; anything running as this user can edit it, and the trust this file
# buys is entirely "install.sh wrote this path" bookkeeping, never "this path is unmodified" or
# "this path was really installed by vstack and not forged by something else running as you".
# Ownership by this record beats ownership by content comparison because it survives a version
# change: v1.45.1's verify-gate.sh and HEAD's differ byte for byte and are both ours. Lives
# outside $CDIR so uninstalling the config does not destroy the record of what the config was.
OWNED_PATHS="$HOME/.config/agents/vstack-installed"
own(){ [ "$DRY" = 1 ] && return 0
  mkdir -p "$(dirname "$OWNED_PATHS")" 2>/dev/null || return 0
  grep -qxF "$1" "$OWNED_PATHS" 2>/dev/null || printf '%s\n' "$1" >> "$OWNED_PATHS"
  return 0
}

# One-time migration for machines installed by vstack <= 1.45.1, which kept no ownership record.
# Without this, upgrading from an older version launders exactly one payload: the old file and
# the new one differ byte for byte -- both are ours, but content comparison cannot see that -- so
# back() records the old one as the user's and the next uninstall restores it. seq3 of
# tests/repro/lifecycle.sh is that case.
#
# The fingerprint is >= 3 of vstack's own hook basenames sitting in $CDIR/hooks. Those names
# (dispatch-counter.sh, skill-mandate.sh, guard-destructive.sh, ...) are this repo's; a user
# who happens to keep three of them under those exact names, having never installed vstack, is
# not a case worth trading the uninstall guarantee for. One or two matches seeds nothing.
seed_owned_paths(){ [ "$DRY" = 1 ] && return 0
  [ -f "$OWNED_PATHS" ] && return 0
  _hits=0
  for _h in "$SRC"/claude/hooks/*.sh; do
    [ -e "$_h" ] || continue
    [ -f "$CDIR/hooks/$(basename "$_h")" ] && _hits=$((_hits+1))
  done
  [ "$_hits" -ge 3 ] || return 0
  # Every loop below tests the DESTINATION ($CDIR/...), the same thing the fingerprint loop
  # above already tests -- not just [ -e "$_a" ]/[ -d "$_d" ], which is only asking "does the
  # REPO ship this," and the repo ships all of them, every time, regardless of what is really
  # on disk or which profile this run is. That earlier version claimed every agent, command,
  # reference file and skill in the repository on ANY machine with >= 3 recognisable hooks --
  # including a fresh --profile=core install, where .claude/agents and .claude/skills are
  # empty by design. uninstall.sh's skills-removal loop trusts the record alone (directories
  # have no per-file content-comparison fallback the way plan_file_removal gives single files),
  # so a name a user later reused for their own directory -- ordinary skill names like
  # "brainstorming" are exactly the names someone would pick unprompted -- got rm -rf'd on the
  # next uninstall as "installed by vstack, not present in backup." Deliberately NOT also
  # gated on profile_wants_* (see PROFILE_HOOK_CORE and its neighbours above): a file that is
  # really sitting at $CDIR was really put there by some earlier vstack run, whichever profile
  # that run used, and it staying permanently unrecorded -- never adoptable, hence never
  # uninstallable -- would be worse for "uninstall returns the machine to its pre-vstack state"
  # than adopting it now and letting a later, real uninstall clean it up.
  for _h in "$SRC"/claude/hooks/*.sh; do
    [ -e "$_h" ] || continue
    _t="$CDIR/hooks/$(basename "$_h")"; [ -f "$_t" ] && own "$_t"
  done
  for _a in "$SRC"/claude/agents/*.md; do
    [ -e "$_a" ] || continue
    _t="$CDIR/agents/$(basename "$_a")"; [ -f "$_t" ] && own "$_t"
  done
  for _r in "$SRC"/claude/agents/reference/*.ref; do
    [ -e "$_r" ] || continue
    _t="$CDIR/agents/reference/$(basename "$_r")"; [ -f "$_t" ] && own "$_t"
  done
  for _c in "$SRC"/claude/commands/*.md; do
    [ -e "$_c" ] || continue
    _t="$CDIR/commands/$(basename "$_c")"; [ -f "$_t" ] && own "$_t"
  done
  for _d in "$SRC"/claude/skills/*/; do
    [ -d "$_d" ] || continue
    _t="$CDIR/skills/$(basename "$_d")"; [ -d "$_t" ] && own "$_t"
  done
  [ -f "$CDIR/CLAUDE.md" ] && own "$CDIR/CLAUDE.md"
  [ -f "$CDIR/statusline.sh" ] && own "$CDIR/statusline.sh"
  say "adopted    an existing vstack install into $OWNED_PATHS ($_hits hook(s) matched; pre-1.46.0 kept no ownership record)"
}
BK="$BK_BASE"
# Set only once `mkdir "$BK"` has actually succeeded below. BK itself is assigned unconditionally
# right above, so guarding abort_note on `[ "${BK:-}" = "" ]` never fired -- BK is never empty --
# and a run that died before the backup directory could even be created (HOME unwritable, disk
# full, no permission on ~/.config) still printed "every file this run touched was copied to $BK
# first" pointing at a path that was never made. This flag is the actual truth the message needs.
BK_CREATED=0
DRY=0
WITH_DEPS=0
BYPASS=0
PROFILE="${VSTACK_PROFILE:-opinionated}"
for a in "$@"; do
  case "$a" in
    --bypass-permissions) BYPASS=1 ;;
    --with-deps)    WITH_DEPS=1 ;;
    --dry-run)      DRY=1 ;;
    --profile=*)    PROFILE="${a#--profile=}" ;;
    -h|--help)      sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

# A CLI flag beats the env var (the env var exists so CI and scripted installs can set it once;
# a flag on the actual invocation is a more specific instruction and should win).
#
# VSTACK_PROFILE=skills is rejected by name, not silently accepted as an unknown profile. It is
# already load-bearing: claude/hooks/hooks.json's plugin lane and .claude/verify.sh check 47 both
# set it to make inject-session-context.sh emit ONLY the skill-routing block, at the moment that
# ONE hook script runs -- a runtime switch read by a hook process, not an install-time selector
# read by this installer. Reusing the value here for a different axis (which files this script
# copies) would make `VSTACK_PROFILE=skills ./install.sh`, run by anyone who has that value in
# their shell for an unrelated reason (testing a hook by hand, this repo's own falsifiability
# harness), silently do something no profile below claims to do. Fail loud instead.
case "$PROFILE" in
  core|team|ui|opinionated) ;;
  skills)
    echo "error: VSTACK_PROFILE=skills is a hook-runtime value (see claude/hooks/hooks.json," >&2
    echo "       claude/hooks/inject-session-context.sh), not an install profile. Install" >&2
    echo "       profiles are: core, team, ui, opinionated." >&2
    exit 2 ;;
  *) echo "error: unknown profile '$PROFILE' (core, team, ui, opinionated)" >&2; exit 2 ;;
esac

say(){ printf '%s\n' "$*"; }

# --- profile membership ----------------------------------------------------------------------
# Derived from what each file's own description says it does, not declared. The evidence for
# each list is a `grep`/`head` any reader can re-run against this checkout:
#
#   PROFILE_HOOK_CORE       compat-canary.sh (its own header: "the one place that is allowed to
#                            say I do not know out loud instead of quietly doing nothing" --
#                            docs/checks-that-inherit-their-answer.md's own failure shape, wired
#                            on SessionStart only, once per session), failure-diagnose.sh
#                            (PostToolUseFailure self-heal), format.sh (opt-in formatter),
#                            guard-destructive.sh (PreToolUse destructive-command guard),
#                            verify-gate.sh (the Stop-hook test gate `vstack trust` arms). None
#                            of the five has an opinion about HOW you work; each is safety,
#                            self-repair, or the diagnostic that admits when it cannot tell.
#   PROFILE_HOOK_TEAM_ONLY   dispatch-counter.sh's own header: "increments a per-session dispatch
#                            counter that claude/statusline.sh reads to render 'RICK N'" -- this
#                            is the "dispatch logging" the brief names for team. skill-mandate.sh
#                            mandates BOTH skill usage and delegation breadth/naming against the
#                            roster's call signs -- roster enforcement, not lifecycle machinery.
#   (inject-session-context.sh installs under opinionated only -- see the comment above PROFILE.)
#
#   Agents: none for core (a roster is what "no roster" in the brief's core definition rules
#   out). ui gets exactly the three whose own `description:` frontmatter names UI/interface
#   work: ui-engineer ("Build interface code... React/Tailwind"), design-reviewer ("how a
#   running interface looks"), accessibility-auditor ("Audit a running UI for accessibility").
#   The other 11 read as general engineering roles (debugger, planner, qa, ...) with nothing
#   UI-specific in their description -- team gets all 14, since /team's own roster table
#   (README) names all 14 as phases of one pipeline.
#
#   Commands: core gets the 11 that read as git/verify/deploy lifecycle with no subagent
#   dispatch in their body (checked by grep -oE '`[a-z-]+`' against every command file: none of
#   these 11 names an agent in backticks). team adds the 4 that do: team.md (all 14 agents),
#   release.md ("via the release-manager subagent" -- and its body says outright "This is not a
#   standalone release command; it is a phase within the full engineering workflow"), review.md
#   (dispatches `code-reviewer`), test.md (dispatches `debugger`). None of the 15 names UI
#   specifically, so ui installs no commands beyond core's 11.
#
#   Skills: core gets none, for the same reason as agents -- every one of the 28 packages a
#   working-style choice (TDD, brainstorming, unslop, the principle-* series, ...), which is
#   what "no skills that only encode taste" rules out wholesale; there is no file-level way to
#   split a skill into its taste half and its mechanism half. ui gets the four whose own
#   `description:` is explicitly about UI/component/browser work: component-registry (pull a
#   UI primitive), impeccable (polishing UI that already renders), ui-iterate (screenshot/
#   critique after editing a UI file), agent-browser (screenshot or drive a dev server -- the
#   tool ui-iterate and impeccable both need to act on what they find). team gets swarm alone:
#   its description is "Fans out N agents in ONE batched message" -- multi-agent routing under
#   a different name, which is exactly what the brief's team definition names.
#
#   ENVIRONMENT.ref installs only when at least one of the 9 agents that point at it does
#   (`grep -rl reference/ claude/agents/*.md`): debugger, code-reviewer, planner, performance-
#   engineer, security-auditor, qa, release-manager, test-writer, worker. None of those 9 is in
#   ui's 3-agent set, so team/opinionated is exactly the right condition, derived rather than
#   named twice.
#
#   ui-gate/ is NOT gated here. It carries no install.sh target today -- README calls it "a UI
#   lint harness for OTHER PEOPLE'S repos", run from a checkout, never copied to ~/.claude by
#   any lane -- and a profile selects among what install.sh already installs; it does not grow
#   a new one. Confirm with: grep -n ui-gate install.sh (nothing, before or after this change).
#
#   Wrappers (bin/*), doctor, vstack, statusline.sh, the MCP merge, the shell lane and the
#   Conductor files are unconditional in every profile: the brief's own core definition names
#   "hooks, wrappers, doctor, trust, the Stop gate" as what core keeps, and none of the other
#   three profiles narrows that set back down.
PROFILE_HOOK_CORE="compat-canary.sh failure-diagnose.sh format.sh guard-destructive.sh verify-gate.sh"
PROFILE_HOOK_TEAM_ONLY="dispatch-counter.sh skill-mandate.sh"

PROFILE_AGENT_UI="ui-engineer.md design-reviewer.md accessibility-auditor.md"
PROFILE_ENV_REF_AGENTS="debugger.md code-reviewer.md planner.md performance-engineer.md security-auditor.md qa.md release-manager.md test-writer.md worker.md"

PROFILE_COMMAND_CORE="bootstrap.md commit.md deploy.md deploy-auto.md doctor.md goal.md observability.md pr.md push.md security.md ship.md"
PROFILE_COMMAND_TEAM_ONLY="team.md release.md review.md test.md"

PROFILE_SKILL_UI="component-registry impeccable ui-iterate agent-browser"
PROFILE_SKILL_TEAM_ONLY="swarm"

# Space-list membership test. Bash-3.2-safe: no arrays, just word-splitting inside a pattern.
in_list(){ case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }

profile_wants_hook(){    # <basename>
  case "$PROFILE" in
    opinionated) return 0 ;;
    team) in_list "$PROFILE_HOOK_CORE $PROFILE_HOOK_TEAM_ONLY" "$1" ;;
    core|ui) in_list "$PROFILE_HOOK_CORE" "$1" ;;
  esac
}
profile_wants_agent(){   # <basename>
  case "$PROFILE" in
    opinionated|team) return 0 ;;
    ui) in_list "$PROFILE_AGENT_UI" "$1" ;;
    core) return 1 ;;
  esac
}
profile_wants_env_ref(){ # no arg: ENVIRONMENT.ref ships iff this profile ships an agent that
  case "$PROFILE" in     # points at it -- derived from PROFILE_ENV_REF_AGENTS rather than
    opinionated) return 0 ;; # hardcoded a second time, so the two cannot drift apart.
    *)
      for _era in $PROFILE_ENV_REF_AGENTS; do
        profile_wants_agent "$_era" && return 0
      done
      return 1 ;;
  esac
}
profile_wants_command(){ # <basename>
  case "$PROFILE" in
    opinionated) return 0 ;;
    team) in_list "$PROFILE_COMMAND_CORE $PROFILE_COMMAND_TEAM_ONLY" "$1" ;;
    core|ui) in_list "$PROFILE_COMMAND_CORE" "$1" ;;
  esac
}
profile_wants_skill(){   # <dirname>
  case "$PROFILE" in
    opinionated) return 0 ;;
    team) in_list "$PROFILE_SKILL_TEAM_ONLY" "$1" ;;
    ui) in_list "$PROFILE_SKILL_UI" "$1" ;;
    core) return 1 ;;
  esac
}

# CLAUDE.md and inject-session-context.sh (SessionStart/UserPromptSubmit) are opinionated-only,
# by the same read: CLAUDE.md IS the routing policy the brief describes wanting to opt out of --
# "USE THE STACK: route work through this configuration... Multi-phase work goes through /team",
# "NAME THE AGENT: you are RICK", plus an autonomy stance and an output register that have
# nothing to do with safety or the team roster either. It is not core-safe to install and there
# is no line-level way to keep half of one file. inject-session-context.sh's only other mode
# (VSTACK_PROFILE=skills, read by the plugin lane and .claude/verify.sh check 47) still prints
# all 28 skill names and the full 14-name roster call-sign list -- true for the plugin lane,
# which ships all 28 skills, false for core/team/ui here, which do not. Installing a hook that
# advertises a payload this profile did not ship is not a smaller version of the policy; it is a
# wrong claim, so the hook is left out rather than run in a mode built for someone else's set.
profile_wants_claude_md(){ [ "$PROFILE" = "opinionated" ]; }

# Every jq merge below was `jq -e . "$tmp" >/dev/null && cat "$tmp" > "$dest"`, followed
# unconditionally by say "merged ...". When jq produced nothing usable the && short-circuited,
# the destination kept its old contents, and the install still printed "merged" and exited 0 --
# so a settings merge that silently did not happen looked exactly like one that did. Failure has
# to be visible, name the backup, and survive to the exit code.
DEGRADED=0

# set -e means any failing command aborts mid-install. That is the right call -- continuing past
# a broken merge is how you get a half-configured machine -- but the bare abort printed a raw jq
# error and stopped, leaving the user staring at a partial install with no idea whether their
# own files had survived. They always had; nobody was ever told where.
abort_note(){
  st=$?
  [ "$st" = 0 ] && return 0
  [ "$BK_CREATED" = 1 ] || return 0
  [ "$DRY" = 1 ] && return 0
  printf '\ninstall aborted (exit %s). Nothing of yours was lost:\n' "$st"
  printf '  every file this run touched was copied to %s first\n' "$BK"
  printf '  restore with: %s/uninstall.sh\n' "$SRC"
  printf '  this installer is safe to re-run once the cause above is fixed\n'
}
trap abort_note EXIT

commit_json(){ # <tmp> <dest> <what>
  if jq -e . "$1" >/dev/null 2>&1; then
    cat "$1" > "$2"; rm -f "$1"; return 0
  fi
  rm -f "$1"
  DEGRADED=1
  say "FAILED     $3 was NOT written -- the merge produced invalid JSON"
  say "           $2 is unchanged; your copy from before this run is in $BK"
  return 1
}
run(){ if [ "$DRY" = 1 ]; then say "would: $*"; else "$@"; fi; }

[ -f "$SRC/claude/settings.json" ] || { echo "error: run this from the vstack repo" >&2; exit 1; }

# --with-deps installs the tools first. Kept opt-in here because a normal re-install should
# not reach for a package manager; bootstrap.sh turns it on for fresh machines.
if [ "$WITH_DEPS" = 1 ] && [ -x "$SRC/setup-machine.sh" ]; then
  if [ "$DRY" = 1 ]; then "$SRC/setup-machine.sh" --dry-run; else "$SRC/setup-machine.sh"; fi
  echo
fi

# jq drives the two merge steps (settings, MCP). Linux cloud sandboxes often lack it, and
# skills plus hooks are still worth installing there, so degrade instead of aborting.
HAVE_JQ=1
command -v jq >/dev/null || { HAVE_JQ=0; echo "warn: jq not found — settings and MCP merge will be skipped (brew install jq / apt install jq)" >&2; }

if [ "$DRY" = 0 ]; then
  # Claim the backup directory exclusively. `mkdir -p` is happy to reuse one, and the timestamp
  # only has second resolution, so two installs in the same second shared a directory and the
  # second overwrote the first's copies with files vstack had just installed — destroying the
  # only record of what the user had before. Automation and retries hit this easily.
  mkdir -p "$(dirname "$BK_BASE")"
  bn=1
  until mkdir "$BK" 2>/dev/null; do
    BK="$BK_BASE-$bn"
    bn=$((bn+1))
    [ "$bn" -gt 500 ] && { echo "error: cannot create a backup dir under $(dirname "$BK_BASE")" >&2; exit 1; }
  done
  BK_CREATED=1
  # vstack recover's contract (see bin/vstack's cmd_recover comment, which this must match
  # exactly): one line, "backup=<path>", written the moment this run has a backup dir to point
  # to, overwritten unconditionally on every run, removed as this script's own last action on
  # a successful exit. A copy of this file surviving the process is recover's only signal that
  # this run did not reach its own end -- so nothing between here and the final rm may skip it
  # on an error path; that is what `set -e` plus abort_note's own separate job already cover.
  printf 'backup=%s\n' "$BK" > "$HOME/.config/agents/install-state"
  mkdir -p "$CDIR/hooks" "$CDIR/agents" "$CDIR/agents/reference" "$CDIR/commands" \
           "$CDIR/skills" \
           "$HOME/.config/agents/bin" "$HOME/.config/agents/shell"
  chmod 700 "$HOME/.config/agents/backups"
fi
# Backups preserve the real path under files/ — the old flat `tr / _` names were a lossy
# encoding that misparsed any future filename containing an underscore on restore.
back(){ [ "$DRY" = 1 ] && return 0
  # Record ownership unconditionally, before the "is there anything to back up" guard below.
  # own() is what makes $1 show up in $OWNED_PATHS at all; a fresh install (nothing at $1 yet,
  # since back() runs before this loop's `cp`) used to hit the old `[ -f "$1" ] || return 0`
  # guard first and return without ever calling own() -- so a first-ever install of a profile
  # that also installs at least one skill (whose loop calls own() directly, unconditionally)
  # got a real, populated $OWNED_PATHS containing ONLY the skills, and uninstall.sh's
  # owns_path() -- which trusts a present file completely -- then silently kept every hook,
  # agent, command, wrapper and CLAUDE.md a --yes uninstall was supposed to remove. A profile
  # with no skills (core) never tripped this, because with $OWNED_PATHS never created at all,
  # owns_path()'s missing-file branch fell back to "assume everything", the pre-1.46.0 behaviour
  # -- the right answer by accident, not because ownership was actually being recorded.
  # Read the ownership guard's answer BEFORE own() supplies it. own() appends $1 to
  # $OWNED_PATHS, so the check further down -- which asks "did an EARLIER install claim this
  # path" -- was reading a line this call had just written, matched every path on every run,
  # and returned before its `cp`. Nothing was ever backed up. $BK was still created, still
  # announced on install.sh's last line, and still empty. Ordering is the whole fix: own() must
  # stay above the `[ -f "$1" ]` guard (see the paragraph above) and the ownership question must
  # be asked above own().
  _pre_owned=0
  if [ -f "$OWNED_PATHS" ] && grep -qxF "$1" "$OWNED_PATHS"; then _pre_owned=1; fi
  own "$1"
  [ -f "$1" ] || return 0
  # Two independent ways to know $1 is vstack's own and must NOT be recorded as pre-existing
  # user content. Recording it there is what let a second install launder the payload into
  # "the user had this", after which uninstall.sh restored it and the machine could never be
  # returned to its pre-vstack state.
  #
  # (a) The ownership record from an earlier install already claims this path. This is the
  #     authority -- it survives across versions, so a file installed by v1.45.1 and overwritten
  #     by a newer vstack is still recognised as ours even though the bytes differ. Content
  #     comparison alone could not see that, and seq3 of tests/repro/lifecycle.sh is exactly
  #     that case.
  # (b) $2, when given, is the repo file about to overwrite $1, and the two are already
  #     byte-identical. Covers a first uninstall on a machine with no ownership record yet.
  #
  # The trade, stated: a user file whose bytes exactly equal vstack's is indistinguishable from
  # vstack's and is treated as vstack's, so uninstall deletes it. What is lost is content this
  # repo still ships verbatim. The alternative loses the ability to uninstall at all.
  if [ "$_pre_owned" = 1 ]; then return 0; fi
  if [ -n "${2:-}" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then return 0; fi
  # Paths under $HOME are stored HOME-relative so uninstall can map them back. A config dir
  # moved outside $HOME by CLAUDE_CONFIG_DIR has no such relative form, so it is stored under
  # files_abs/ with its full path and restored to exactly where it came from.
  case "$1" in
    "$HOME"/*) rel="${1#$HOME/}"; dest="$BK/files/$rel" ;;
    *)         dest="$BK/files_abs${1}" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp "$1" "$dest"
  return 0
}

# Record where this install came from so doctor --drift and `vstack` can find the repo even
# when it is cloned somewhere other than ~/.vstack and $VSTACK_DIR is unset.
[ "$DRY" = 0 ] && printf '%s\n' "$SRC" > "$HOME/.config/agents/vstack-repo"

# Trust this repo's own verify.sh for the Stop-hook gate: running install.sh IS the explicit
# consent. Other repos' gates stay off until the user runs `vstack trust` there — the gate
# executes repo-controlled code, so a bare clone must never arm it by itself.
if [ "$DRY" = 0 ] && [ -f "$SRC/.claude/verify.sh" ]; then
  tv="$(cd "$SRC/.claude" && pwd)/verify.sh"
  if command -v shasum >/dev/null 2>&1; then th=$(shasum -a 256 "$tv" | cut -d' ' -f1)
  else th=$(sha256sum "$tv" | cut -d' ' -f1); fi
  tf="$HOME/.config/agents/verify-trust"
  ttmp=$(mktemp); grep -vF "  $tv" "$tf" 2>/dev/null > "$ttmp" || true
  printf '%s  %s\n' "$th" "$tv" >> "$ttmp"; mv "$ttmp" "$tf"
  say "trusted    $SRC/.claude/verify.sh (verify gate)"
fi

# --- hooks / agents / commands ------------------------------------------------------------
seed_owned_paths
n_hooks=0; n_agents=0; n_commands=0
for f in "$SRC"/claude/hooks/*.sh; do
  b=$(basename "$f")
  profile_wants_hook "$b" || continue
  back "$CDIR/hooks/$b" "$f"; run cp "$f" "$CDIR/hooks/"
  n_hooks=$((n_hooks + 1))
done
for f in "$SRC"/claude/agents/*.md; do
  b=$(basename "$f")
  profile_wants_agent "$b" || continue
  back "$CDIR/agents/$b" "$f"; run cp "$f" "$CDIR/agents/"
  n_agents=$((n_agents + 1))
done
# Reference material the agents are pointed at. Deliberately *.ref, not *.md: Claude Code walks
# an agent directory recursively and loads every .md at any depth, so a reference written as
# markdown would install as a nameless agent competing for dispatch.
#
# Ships iff a referencing agent does (profile_wants_env_ref), not unconditionally: a reference
# file with no agent installed to point at it is dead weight this profile did not ask for, and
# core/ui installing it would claim ownership this profile never earns an ownership-record entry for.
if profile_wants_env_ref; then
  for f in "$SRC"/claude/agents/reference/*.ref; do
    [ -e "$f" ] || continue
    back "$CDIR/agents/reference/$(basename "$f")" "$f"; run cp "$f" "$CDIR/agents/reference/"
  done
fi
for f in "$SRC"/claude/commands/*.md; do
  b=$(basename "$f")
  profile_wants_command "$b" || continue
  back "$CDIR/commands/$b" "$f"; run cp "$f" "$CDIR/commands/"
  n_commands=$((n_commands + 1))
done
[ "$DRY" = 0 ] && [ -d "$CDIR/hooks" ] && chmod 755 "$CDIR"/hooks/*.sh 2>/dev/null
say "installed  hooks ($n_hooks), agents ($n_agents), commands ($n_commands)  [profile: $PROFILE]"

# --- global directives + statusline ---------------------------------------------------------
# CLAUDE.md is the standing instruction file every session reads. It is backed up first: it is
# the file most likely to have been hand-edited on a machine that has been running a while.
#
# opinionated only -- see the comment above profile_wants_claude_md for why the other three
# profiles do not get a smaller version of it instead.
if profile_wants_claude_md; then
  back "$CDIR/CLAUDE.md" "$SRC/claude/CLAUDE.md"
  run cp "$SRC/claude/CLAUDE.md" "$CDIR/CLAUDE.md"
  say "installed  CLAUDE.md"
fi
# statusline.sh is unconditional: model/dir/git/cost display with no opinion about how you
# work, and it renders nothing for the dispatch count when dispatch-counter.sh never wrote one
# (its own comment: "Renders nothing if counter is absent... this is correct, not a zero").
back "$CDIR/statusline.sh" "$SRC/claude/statusline.sh"
run cp "$SRC/claude/statusline.sh" "$CDIR/statusline.sh"
[ "$DRY" = 0 ] && chmod 755 "$CDIR/statusline.sh"
say "installed  statusline.sh"

# --- conductor user settings ------------------------------------------------------------------
# Conductor reads model and workflow defaults from here. Only written when absent: these are
# per-person preferences, and clobbering them would change how every workspace launches.
if [ ! -f "$HOME/.conductor/settings.toml" ]; then
  [ "$DRY" = 0 ] && { mkdir -p "$HOME/.conductor"; cp "$SRC/conductor/settings.toml" "$HOME/.conductor/settings.toml"; own "$HOME/.conductor/settings.toml"; }
  say "installed  ~/.conductor/settings.toml"
else
  say "kept       existing ~/.conductor/settings.toml"
fi

# The managed layer is different: it exists to pin model/fastMode/plan-mode above the Settings
# UI, so it is ALWAYS overwritten — a managed file that install leaves alone is just a second
# preferences file. The pins and their rationale live in conductor/settings.managed.toml.
if [ -f "$SRC/conductor/settings.managed.toml" ]; then
  # Backed up first. This file is always overwritten by design — a managed layer that install
  # leaves alone is just a second preferences file — but overwriting without a backup is how
  # someone already using Conductor managed settings loses machine-wide policy on first install,
  # with nothing to restore from. It is the only file this installer replaced unconditionally
  # and unrecoverably.
  back "$HOME/.conductor/settings.managed.toml"
  [ "$DRY" = 0 ] && { mkdir -p "$HOME/.conductor"; cp "$SRC/conductor/settings.managed.toml" "$HOME/.conductor/settings.managed.toml"; }
  say "pinned     ~/.conductor/settings.managed.toml (models, fast mode, plan mode)"
fi

# --- skills -------------------------------------------------------------------------------
# Whole-dir replace per skill: they carry references/ and scripts/ subtrees, so a file-by-file
# copy would leave stale files behind after an upstream removal. Only touches skills this repo
# owns; never deletes skills you wrote yourself.
n_skills=0
for d in "$SRC"/claude/skills/*/; do
  s=$(basename "$d")
  profile_wants_skill "$s" || continue
  [ "$DRY" = 1 ] && { say "would: install skill $s"; n_skills=$((n_skills + 1)); continue; }
  # Same provenance rule as back(), ownership record first: a skill dir this repo has installed before is
  # ours even when its contents have since changed with a version, and backing it up would let
  # the next uninstall restore it.
  if [ -d "$CDIR/skills/$s" ] \
     && ! grep -qxF "$CDIR/skills/$s" "$OWNED_PATHS" 2>/dev/null \
     && ! diff -rq "$CDIR/skills/$s" "${d%/}" >/dev/null 2>&1; then
    cp -R "$CDIR/skills/$s" "$BK/skills_$s"
  fi
  own "$CDIR/skills/$s"
  rm -rf "${CDIR:?}/skills/$s"
  # NB: strip the trailing slash. BSD/macOS `cp -R src/ dest/` copies src CONTENTS into dest,
  # not src itself, which would scatter SKILL.md and references/ across the skills root.
  cp -R "${d%/}" "$CDIR/skills/"
  n_skills=$((n_skills + 1))
done
# The licence and the attribution travel with the skills, and only when at least one skill
# actually landed -- core installs none, and a LICENSE/ATTRIBUTION file with nothing under it
# to attribute is a claim about a payload this profile did not ship.
if [ "$n_skills" -gt 0 ]; then
  for meta in LICENSE.pstack ATTRIBUTION.md; do
    [ -f "$SRC/claude/skills/$meta" ] && { run cp "$SRC/claude/skills/$meta" "$CDIR/skills/"; own "$CDIR/skills/$meta"; }
  done
fi
[ "$DRY" = 0 ] && [ -d "$CDIR/skills" ] && find "$CDIR/skills" -name "*.sh" -exec chmod 755 {} + 2>/dev/null
say "installed  skills ($n_skills)  [profile: $PROFILE]"

# --- agent bin ----------------------------------------------------------------------------
for f in "$SRC"/bin/*; do
  b=$(basename "$f")
  back "$HOME/.config/agents/bin/$b"
  run cp "$f" "$HOME/.config/agents/bin/$b"
done
[ "$DRY" = 0 ] && chmod 755 "$HOME"/.config/agents/bin/*
say "installed  bin wrappers"

# claude-bg.sh writes its per-run log under here and never created the directory itself (it only
# printed "dispatched" and let the redirection into a nonexistent dir fail silently before the
# subshell even started). First invocation on a fresh install must not lie about having dispatched.
run mkdir -p "$HOME/.config/agents/bg"
say "installed  bg log dir"

# --- secrets scaffold ---------------------------------------------------------------------
# Never overwrite real secrets. Only create the file (from the example) when it is absent.
SE="$HOME/.config/agents/secrets.env"
if [ ! -f "$SE" ]; then
  run cp "$SRC/secrets.env.example" "$SE"
  [ "$DRY" = 0 ] && chmod 600 "$SE"
  say "created    secrets.env from example — fill it in"
else
  [ "$DRY" = 0 ] && chmod 600 "$SE"
  say "kept       existing secrets.env (chmod 600)"
fi

# --- settings ------------------------------------------------------------------------------
# Merge the portable subset INTO existing user settings, then rebuild hooks with absolute
# paths (user scope has no $CLAUDE_PROJECT_DIR). The portable file is authoritative for
# every key it ships — including enabledPlugins and skillOverrides, which is replaced
# wholesale so overrides for deleted skills don't linger in the live file forever. Keys the
# portable file never mentions (forceLoginMethod / remote / permissions) survive untouched.
#
# RETIRED is the part that used to be a lie: the comment here claimed retired keys were
# del()ed "explicitly below" and no such code was ever written, so a key this repo dropped
# would sit in the live file forever. A merge that cannot delete is an accumulator.
#
# It is EMPTY, and that is the correct value today. This list may only ever name a key that
# claude/settings.json itself once shipped and no longer does. Across every revision of that
# file the union of its top-level keys equals the count shipped today: this repo has never
# retired one. Check the two numbers against each other rather than against a number written
# here — the previous wording hardcoded 27, and was stale at 28 before anyone noticed.
#
# Read that before adding anything here. The first draft of this list was invented from
# plausible-sounding names — "sandbox", "enabledMcpjsonServers", "autoCompactEnabled" — none
# of which this repo has ever shipped. They are Claude Code's own settings. Shipping that list
# would have silently stripped a user's native Bash sandboxing on every install of a public
# repo: a security feature, deleted without a word, on someone else's machine. Deleting a key
# vstack does not own is not cleanup, it is vandalism with a changelog.
#
# To add one: confirm with
#   for s in $(git log --all --format=%H -- claude/settings.json); do
#     git show "${s}:claude/settings.json" | jq -r 'keys[]'; done | sort -u
# that the key appears there and not in the current file. Check 21 enforces exactly that.
RETIRED='[]'
# Hook basenames this profile installs. Computed once, in plain shell (no jq needed for the
# loop itself), so the jq branch and the no-jq degrade branch below both read the same answer
# as the file-copy loop earlier used to decide what actually landed in $CDIR/hooks.
ALLOWED_HOOKS=""
for _hf in "$SRC"/claude/hooks/*.sh; do
  _hb=$(basename "$_hf")
  profile_wants_hook "$_hb" && ALLOWED_HOOKS="$ALLOWED_HOOKS $_hb"
done
US="$CDIR/settings.json"; back "$US"
[ -f "$US" ] || { [ "$DRY" = 0 ] && echo '{}' > "$US"; }

# A settings.json that does not parse is not a merge problem, it is a broken file. It happens:
# a crash or a full disk mid-write, or a hand edit that dropped a brace. Until now the merge
# just failed — jq printed a raw parse error, the file stayed corrupt, install.sh exited with
# jq's status, and the user was left with everything else installed and a settings file Claude
# Code cannot read at all. Nothing said which of those things had happened.
#
# The backup was already taken above, so the honest move is to say so loudly and start from a
# known-good file. Keeping an unparseable one helps nobody: Claude Code cannot read it either.
if [ "$DRY" = 0 ] && [ "$HAVE_JQ" = 1 ] && [ -s "$US" ]; then
  if ! jq -e . "$US" >/dev/null 2>&1; then
    say "WARNING    $US did not parse as JSON and has been replaced."
    say "           your copy is safe at $BK/files/${US#"$HOME"/}"
    say "           re-apply anything you need from it by hand."
    echo '{}' > "$US"
  fi
fi
if [ "$DRY" = 0 ] && [ "$HAVE_JQ" = 0 ]; then
  # No jq: never hand-merge JSON. Write the portable settings only when there is nothing
  # to lose, otherwise leave the existing file untouched.
  if [ ! -s "$US" ] || [ "$(cat "$US")" = "{}" ]; then
    if [ "$PROFILE" != opinionated ]; then
      # claude/settings.json's shipped "hooks" object names all seven scripts unconditionally --
      # the sed substitution three lines down only rewrites the path prefix, it does not (and
      # without jq, cannot cheaply) drop the entries for hooks this profile did not copy to
      # $CDIR/hooks above. Writing it anyway would wire Claude Code to run a command that is not
      # on disk on every SessionStart/Stop -- a worse failure than leaving the file alone, and
      # the kind of thing this repo's own gate exists to catch. Say so and stop short, rather
      # than filtering JSON by hand with sed against a file this script does not own the shape of.
      say "skipped    settings merge (no jq — cannot filter hook wiring to profile '$PROFILE'"
      say "           without JSON parsing; hooks this profile installs: ${ALLOWED_HOOKS# })"
      say "           install jq, or wire them into $US by hand"
    else
      # Rewrite the hook paths on the way in. The shipped file addresses hooks as
      # $CLAUDE_PROJECT_DIR/.claude/hooks/... because that is correct for the overlay lane, where
      # the hooks live in the repo. At user scope there is no project dir, so copying the file
      # verbatim produced an install that reported success and wired every hook to a path that
      # does not exist — exit 127 on every session start, every stop, every tool failure. The
      # gate, the routing and the formatter were all inert, on exactly the jq-less sandboxes this
      # branch exists to support.
      #
      # It is a textual substitution rather than a JSON edit, which is the only honest option
      # without jq, and it is safe here because the target is a file this repo controls.
      sed "s|\$CLAUDE_PROJECT_DIR/.claude/hooks|$CDIR/hooks|g" \
        "$SRC/claude/settings.json" > "$US"
      say "wrote      $US (no jq — hook paths rewritten to $CDIR/hooks; no statusline, no MCP merge)"
    fi
  else
    say "skipped    settings merge (no jq — existing settings left untouched)"
  fi
elif [ "$DRY" = 0 ]; then
  tmp=$(mktemp)
  # typescript-lsp is stripped from enabledPlugins below when the plugin is not actually
  # installed (see the del() call), because an entry claiming enablement for a plugin the
  # toolchain never installed is a claim nothing backs. Stripping it unconditionally on every
  # run was itself a bug: a user who opted in with --with-plugins/VSTACK_PLUGINS=1 had their own
  # explicit choice undone on the next `./install.sh`, because install.sh cannot see a flag
  # passed to a different script in an earlier run. `claude plugin list` is the same detection
  # setup-machine.sh already uses to decide presence, so a plugin actually on disk keeps its
  # entry and only a stale claim (no matching install) gets deleted.
  TSL_PRESENT=false
  if command -v claude >/dev/null 2>&1; then
    PL_LIST=$(claude plugin list 2>/dev/null)
    echo "$PL_LIST" | grep -qi typescript-lsp && TSL_PRESENT=true
  fi
  # Hooks and skillOverrides are merged by ownership, not replaced wholesale.
  #
  # Replacing them was silent destruction. A user with a Notification hook, a PreToolUse policy
  # or security hook, or a skillOverride for a skill of their own lost every one of them on
  # install — no prompt, no mention in the output, just a backup they had no reason to know they
  # needed. The wholesale replace existed to stop overrides for deleted skills lingering
  # forever, which is a real problem, but the cure removed configuration this repo does not own.
  #
  # Ownership is decided by what a hook command points at: anything under this install's hooks
  # directory is ours to rebuild, and anything else is theirs to keep. Legacy notifier entries
  # are dropped by name, since the integration they served is gone.
  #
  # skillOverrides merge with ours winning on collision. A stale entry naming a skill nobody
  # ships is inert — Claude Code ignores it — and losing a user's override is not.
  #
  # $allowed is ALLOWED_HOOKS (computed once, above the have-jq/no-jq split) as a JSON array.
  # $ours below stays the full, unfiltered six-event object -- unchanged text, on purpose,
  # because .claude/verify.sh's own checks extract this program's literal source and look for
  # each of the six `EventName: [` keys and every hook filename it references. $ours_filtered is
  # what actually gets merged in; $ourbasenames (a few lines below) stays derived from the
  # UNFILTERED $ours so a stale entry from an earlier, broader-profile install of this same
  # machine is still recognised as vstack's own and gets cleaned up, even though this run does
  # not reinstall it.
  # shellcheck disable=SC2086  # intentional word-split: hook basenames, never containing spaces
  ALLOWED_HOOKS_JSON=$(printf '%s\n' $ALLOWED_HOOKS | awk 'NF' | jq -R . | jq -s .)
  jq -s --arg h "$CDIR/hooks" --argjson retired "$RETIRED" --argjson tsl_present "$TSL_PRESENT" \
        --argjson allowed "$ALLOWED_HOOKS_JSON" '
    ((.[1] | del(.hooks)) as $portable
      | (.[0].hooks // {}) as $userhooks
      | (.[0].skillOverrides // {}) as $userso
      | {
          SessionStart: [
            { hooks: [ {type:"command", command:($h+"/inject-session-context.sh"), statusMessage:"context"},
                       {type:"command", command:($h+"/compat-canary.sh")} ] } ],
          UserPromptSubmit: [
            { hooks: [ {type:"command", command:($h+"/inject-session-context.sh")} ] } ],
          PreToolUse: [
            { matcher:"Bash",
              hooks: [ {type:"command", command:($h+"/guard-destructive.sh"), statusMessage:"guard"} ] } ],
          PostToolUse: [
            { matcher:"Edit|Write|MultiEdit",
              hooks: [ {type:"command", command:($h+"/format.sh"), statusMessage:"format"} ] },
            { matcher:"Agent|Task",
              hooks: [ {type:"command", command:($h+"/dispatch-counter.sh"), statusMessage:"dispatch count"} ] } ],
          Stop: [
            { hooks: [ {type:"command", command:($h+"/verify-gate.sh")},
                       {type:"command", command:($h+"/skill-mandate.sh")} ] } ],
          PostToolUseFailure: [
            { matcher:"*", hooks: [ {type:"command", command:($h+"/failure-diagnose.sh")} ] } ]
        } as $ours
      # Basenames of every command $ours ships (inject-session-context.sh, guard-destructive.sh,
      # ...), derived from $ours itself rather than duplicated, so this list can never drift out
      # of sync with the hooks actually installed above. Deliberately the FULL set, not
      # $allowed: a settings.json entry left behind by an earlier, broader-profile install is
      # still vstack-owned, and must be recognised and cleaned up, even when the profile chosen
      # for this run no longer ships it. (No apostrophes inside this quoted jq program: the
      # whole thing is one bash single-quoted string, and bash does not know jq comment syntax.)
      | ([$ours | .. | .command? // empty] | map(split("/") | last) | unique) as $ourbasenames
      # $ours narrowed to the current profile, filtered per individual hook rather than per
      # group -- Stop carries verify-gate.sh and skill-mandate.sh as two hooks inside ONE group,
      # so dropping skill-mandate.sh for core/ui has to remove one array element, not the group
      # both share. A group that empties out is dropped; an event whose groups all emptied out
      # is dropped with it, which is what lets PostToolUse end up format.sh-only under core.
      | ($ours
          | with_entries(.value |= (
              map(.hooks |= map(select(
                    . as $hookobj
                    | ($allowed | any(. as $b | $hookobj.command | endswith("/hooks/" + $b)))
                  )))
              | map(select(.hooks | length > 0))))
          | with_entries(select(.value | length > 0))) as $ours_filtered
      | ($userhooks
          | with_entries(.value |= map(select(
              [.hooks[]?.command]
              # Matched by shape (a path ending in .../hooks/<one of our filenames>), not by
              # startswith($h) against the CURRENT $CDIR/hooks. startswith tied ownership to
              # THIS machine HOME at merge time, so a settings.json copied from a different HOME
              # (a new machine, a restored backup, a renamed account) had its own vstack entries
              # treated as user-authored forever, because they no longer started with $h -- doctor
              # stayed green while every reinstall appended a duplicate SessionStart entry
              # pointing at a path that no longer exists. A path is ours if its immediate parent
              # directory is literally named "hooks" and its filename is one $ours installs; that
              # survives a HOME move without also claiming a same-named script a user keeps in
              # some unrelated hooks directory of their own, since that script is never one of
              # ours by name.
              | map(
                  . as $cmd
                  | ($cmd | test("SUPERSET_HOME_DIR"))
                  or ($ourbasenames | any(. as $b | $cmd | endswith("/hooks/" + $b)))
                )
              | any | not )))
          | with_entries(select(.value | length > 0))) as $theirs
      | (.[0] * $portable)
      | .skillOverrides = ($userso + ($portable.skillOverrides // {}))
      | del(.enabledPlugins["claude-mem@thedotmack"]?)
      | (if $tsl_present then . else del(.enabledPlugins["typescript-lsp@claude-plugins-official"]?) end)
      | delpaths([$retired[] | [.]])
      | .hooks = (reduce ($ours_filtered | to_entries[]) as $e
                   ($theirs; .[$e.key] = (($theirs[$e.key] // []) + $e.value)))
      # Set only when absent or already ours (basename "statusline.sh") -- refreshing our own
      # entry on a reinstall/upgrade (the path embeds $h, which moves with $CDIR) is not the
      # same decision as clobbering a value the user set before ever running this installer.
      # This key used to be the one exception to "merges rather than overwrites, leaves keys
      # it does not recognise alone" (see this file and READMEs own header claim): every
      # install silently replaced a users own statusLine with no record of what it had been,
      # so a later uninstall had nothing left to restore it from -- check 45 in .claude/verify.sh
      # reproduces this on the commit before profile support existed, so it predates that work.
      # (No apostrophes anywhere in this comment either, for the same reason noted above: the
      # whole program is one bash single-quoted string.)
      | .statusLine = (
          if (.statusLine == null) or (((.statusLine.command? // "") | split("/") | last) == "statusline.sh")
          then {type:"command", command:(($h|rtrimstr("/hooks")) + "/statusline.sh"), padding:0, refreshInterval:3}
          else .statusLine
          end))
  ' "$US" "$SRC/claude/settings.json" > "$tmp"
  # shellcheck disable=SC2088  # the third argument is a label printed to the operator
  if commit_json "$tmp" "$US" "~/.claude/settings.json"; then
    if [ "$BYPASS" = 1 ]; then
      tmp=$(mktemp)
      jq '.permissions.defaultMode = "bypassPermissions" | .skipDangerousModePermissionPrompt = true' "$US" > "$tmp"
      commit_json "$tmp" "$US" "~/.claude/settings.json (bypassPermissions)" \
        && say "merged     ~/.claude/settings.json (+ bypassPermissions)"
    else
      say "merged     ~/.claude/settings.json"
    fi
  fi
fi

# --- MCP servers ---------------------------------------------------------------------------
# Merged into the GLOBAL mcpServers map. Ours win on key collision; anything else you have
# configured is preserved. Project-scoped servers stay yours to add (see mcp/README).
CJ="$CJSON"
if [ "$HAVE_JQ" = 0 ]; then
  say "skipped    MCP merge (no jq)"
elif [ "$DRY" = 0 ]; then
  # The file is created when absent rather than skipped.
  #
  # This branch used to require $CJSON to already exist, which is never true on a machine that
  # has not run Claude Code yet -- exactly the machine running this installer. The result was
  # that a first install printed "run claude once, then re-run this" and every stranger who
  # followed the README once, as instructed, ended up without a single MCP server. The README
  # says these ship. They did not. bin/doctor now checks the same thing from the other side.
  if [ -f "$CJ" ]; then cp "$CJ" "$BK/claude.json"; else printf '{}\n' > "$CJ"; fi
  tmp=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$SRC/mcp/servers.json" > "$tmp.servers"
  jq -s '.[0] as $cur | .[1] as $new | $cur | .mcpServers = (($cur.mcpServers // {}) * $new)' \
     "$CJ" "$tmp.servers" > "$tmp"
  commit_json "$tmp" "$CJ" "MCP servers in $CJSON" \
    && say "merged     MCP servers into $CJSON"
  # Record which mcpServers keys are ours, in the same ownership file the file lanes use.
  # Without this there is no way to tell a server vstack installed from one the user added, so
  # a server this repo STOPS shipping is invisible forever: bin/doctor iterates the keys the
  # repo currently declares, and a key that left the repo is not among them. The record is what
  # lets doctor look from the installed side instead. Machines installed by <= 1.46.0 carry no
  # mcpServers: lines, so they gain the coverage on their next install, not retroactively.
  for _mk in $(jq -r 'keys[]' "$tmp.servers" 2>/dev/null); do own "mcpServers:$_mk"; done
  rm -f "$tmp" "$tmp.servers"
else
  say "skipped    MCP merge (dry run)"
fi

# --- shell lane ----------------------------------------------------------------------------
back "$HOME/.config/agents/shell/claude-parity.zsh"
run cp "$SRC/shell/claude-parity.zsh" "$HOME/.config/agents/shell/"
back "$HOME/.zshrc"
if [ "$DRY" = 0 ] && ! grep -q '>>> claude-parity >>>' "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# >>> claude-parity >>>\n[ -f "$HOME/.config/agents/shell/claude-parity.zsh" ] && . "$HOME/.config/agents/shell/claude-parity.zsh"\n# <<< claude-parity <<<\n' >> "$HOME/.zshrc"
fi
back "$HOME/.zshenv"
if [ "$DRY" = 0 ] && ! grep -q '>>> claude-parity env >>>' "$HOME/.zshenv" 2>/dev/null; then
  cat "$SRC/shell/zshenv.snippet" >> "$HOME/.zshenv"
fi
# Credentials are NOT exported into your shells, and any earlier line that did is removed.
#
# Leaving it behind would mean the fix only reached new machines while every existing install
# kept leaking. vstack wrote that line, so vstack takes it out — matched exactly, backed up
# first, and only ever the form this installer produced. A line you wrote yourself that happens
# to mention secrets.env is not touched.
if [ "$DRY" = 0 ]; then
  for rc in .zshenv .zshrc .bashrc .profile; do
    [ -f "$HOME/$rc" ] || continue
    grep -q 'set -a && \. "$HOME/.config/agents/secrets.env" && set +a' "$HOME/$rc" 2>/dev/null || continue
    back "$HOME/$rc"
    tmp=$(mktemp)
    grep -vF '[ -f "$HOME/.config/agents/secrets.env" ] && set -a && . "$HOME/.config/agents/secrets.env" && set +a' "$HOME/$rc" > "$tmp" && cat "$tmp" > "$HOME/$rc"
    rm -f "$tmp"
    say "removed    credential export from ~/$rc (wrappers load their own; backup in $BK)"
  done
fi

# Credentials are NOT exported into your shells.
#
# This used to source secrets.env with `set -a` into .zshenv, and then — when the bash lane was
# added — into .bashrc and .profile too, which widened it rather than fixing it. The effect was
# that filling in a Cloudflare token handed it to every child process of every shell: every
# script in every repo you cd into, every package postinstall, every tool you try once.
#
# Nothing needed it. Every wrapper in bin/ already loads secrets.env itself (see
# bin/cloudflare-mcp), which is the correct scope: the process that needs the credential reads
# it, and nothing else sees it. The parity block above stays, because those are CLAUDE_* tuning
# variables, not secrets.

# bash gets the same environment. The wrapper does not travel — claude-parity.zsh is written
# in zsh (whence -p, print -r, local -a) and cannot be sourced by bash — but the env snippet
# and the secrets line are plain POSIX exports, and they are the part that actually changes
# behaviour: the 1h prompt cache, tool concurrency, streaming, task support.
#
# Only zsh users got any of it, which meant a default Debian, Ubuntu or Alpine box — every
# cloud VM and nearly every container — installed cleanly and then ran with none of it. Both
# rc files are written when both shells are present, because a machine can have both.
SHELL_LANES=".zshrc, .zshenv"
if [ "$DRY" = 0 ]; then
  for rc in .bashrc .profile; do
    # .profile only when there is no .bashrc: writing both double-exports on login shells.
    [ "$rc" = .profile ] && [ -f "$HOME/.bashrc" ] && continue
    [ "$rc" = .bashrc ] || [ -f "$HOME/$rc" ] || [ -n "${BASH_VERSION:-}" ] || continue
    back "$HOME/$rc"
    if ! grep -q '>>> claude-parity env >>>' "$HOME/$rc" 2>/dev/null; then
      cat "$SRC/shell/zshenv.snippet" >> "$HOME/$rc"
      SHELL_LANES="$SHELL_LANES, $rc"
    fi
  done
  case "${SHELL:-}" in
    *zsh) ;;
    *) say "note       the claude wrapper is zsh-only; \$SHELL is ${SHELL:-unset}, so you get the env lane without it" ;;
  esac
fi
say "installed  shell lane ($SHELL_LANES)"

# --- verify ----------------------------------------------------------------------------------
say ""
if [ "$DRY" = 1 ]; then
  say "dry run complete — nothing was changed."
  exit 0
fi
say "backup: $BK"
say ""
if [ -x "$HOME/.config/agents/bin/doctor" ]; then
  if ! "$HOME/.config/agents/bin/doctor"; then
    say ""
    say "doctor reports drift above. Most causes are one-time setup steps it cannot do for you:"
    say "  - fill in ~/.config/agents/secrets.env"
    say "  - exec zsh -l   (to pick up the shell lane)"
  fi
fi
if [ "$DEGRADED" = 1 ]; then
  say ""
  say "install finished with failures above. Nothing was lost -- the originals are in $BK --"
  say "but the setup is incomplete. Fix the cause and re-run; this is safe to run twice."
  # Marker deliberately NOT removed: vstack recover's contract (see bin/vstack's cmd_recover
  # comment and the printf near BK_CREATED=1 above) says it clears only on this script's own
  # successful exit 0, not on any error path. DEGRADED means the merges failed -- the install
  # is genuinely incomplete -- so leaving the marker in place is the correct, truthful signal.
  exit 1
fi
# Last action before a successful exit, on purpose (see bin/vstack's cmd_recover comment and
# the printf near BK_CREATED=1 above): a marker still present after this process has ended is
# the only signal recover has that a run did not reach here.
rm -f "$HOME/.config/agents/install-state"
say "run: exec zsh -l"
