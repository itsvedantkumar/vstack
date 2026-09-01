#!/usr/bin/env bash
# Session-context injector. SessionStart gets the full operating-mode baseline plus
# workspace conventions; UserPromptSubmit gets a two-line digest so the discipline
# survives long sessions without paying the full block every turn.
# Portable: no absolute /Users paths, so it also works from a committed repo overlay.
#
# VSTACK_PROFILE=skills emits ONLY the skill routing block and nothing else. The plugin
# build sets it: routing is what makes skills fire, but the token, delegation and autonomy
# rules are one person's operating policy and have no business being forced on someone who
# installed a skill pack from a marketplace.
#
# jq is resolved rather than hardcoded to /usr/bin/jq. That path is macOS-only, and without it
# the event lookup below failed and defaulted to SessionStart — which meant every prompt got
# the full baseline block instead of the two-line digest, several kilobytes a turn, silently.
JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi

esc(){ printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
       | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
       | awk 'BEGIN{ORS=""}{print (NR>1?"\\n":"") $0}'; }

emit(){ # event, optional context
  if [ -n "$JQ" ]; then
    if [ -z "${2:-}" ]; then "$JQ" -cn --arg e "$1" '{hookSpecificOutput:{hookEventName:$e}}'
    else "$JQ" -cn --arg e "$1" --arg c "$2" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'; fi
  elif [ -z "${2:-}" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"%s"}}\n' "$(esc "$1")"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$(esc "$1")" "$(esc "$2")"
  fi
}

in=$(cat 2>/dev/null || true)
if [ -n "$JQ" ]; then
  event=$(printf '%s' "$in" | "$JQ" -r '.hook_event_name // "SessionStart"' 2>/dev/null)
else
  event=$(printf '%s' "$in" | sed -n 's/.*"hook_event_name" *: *"\([^"]*\)".*/\1/p' | head -1)
fi
[ -z "$event" ] || [ "$event" = "null" ] && event="SessionStart"

# --- one voice per event ---------------------------------------------------------------
# Claude Code MERGES hook arrays across settings layers instead of overriding them, so a repo
# carrying the committed overlay ran ~/.claude's copy AND its own: every baseline block, digest
# and directive twice, every turn, on this machine.
#
# Deleting the committed copy is not the fix — a cloud sandbox clones the repo and has no
# ~/.claude, so that copy is the only lane config reaches it by. The project copy stands down
# instead, and only while the user-scope copy is demonstrably doing the job.
#
# Each of the three tests earns its place. The */.claude/hooks/ shape keeps vstack's own source
# copy at claude/hooks/ (no dot) emitting, which is what the gate pipes into. The self != global
# test keeps ~/.claude's copy — which matches that same shape — alive. The grep proves the global
# copy is actually registered, so a half-installed ~/.claude cannot silence every repo at once.
self="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
global="$HOME/.claude/hooks/inject-session-context.sh"
is_overlay=0
case "$self" in
  */.claude/hooks/inject-session-context.sh)
    [ "$self" != "$global" ] && is_overlay=1 ;;
esac
global_live=0
if [ -f "$global" ] && grep -q 'inject-session-context\.sh' "$HOME/.claude/settings.json" 2>/dev/null; then
  global_live=1
fi
if [ "${VSTACK_DUPE_SUPPRESS:-1}" = "1" ] && [ "$is_overlay" = 1 ] && [ "$global_live" = 1 ]; then
  emit "$event"
  exit 0
fi

# Compatibility canary: SessionStart only (not every prompt) -- a version/payload-shape check is
# a once-per-session concern, and this is the copy that actually speaks for this session (the
# dupe-suppressed overlay returned above without reaching here). VSTACK_NO_COMPAT_CANARY=1 turns
# it off. Never blocks and NEVER touches this hook's own stdout: check 18 (.claude/verify.sh)
# measures the SessionStart hook's total stdout byte count and the real baseline sits 4 bytes
# under its 4096-byte cap, so anything appended to hookSpecificOutput here -- additionalContext
# OR a sibling systemMessage field, both live in the same JSON line -- would push the gate red on
# exactly the occasion the canary is doing its job (a real Claude Code version bump). The
# durable, visible record is compat-canary.sh's own state file
# (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-compat-canary.json, one JSON object, overwritten
# per check) plus this stderr line, which check 18's probe explicitly discards (`2>/dev/null`)
# and which a real Claude Code session does not fold into model context either.
if [ "$event" = "SessionStart" ] && [ "${VSTACK_NO_COMPAT_CANARY:-0}" != "1" ]; then
  _cc="$(dirname "$self")/compat-canary.sh"
  if [ -x "$_cc" ]; then
    _cc_out=$(printf '%s' "$in" | "$_cc" 2>/dev/null)
    [ $? -eq 2 ] && printf 'vstack compat canary: %s\n' "$_cc_out" >&2
  fi
fi

# Per-prompt digest: must stay tiny and fast (no git work) — it runs on every prompt.
# The skills profile re-pins nothing per prompt; one session-start block is the
# least a skill pack can inject and still work.
if [ "$event" = "UserPromptSubmit" ]; then
  if [ "${VSTACK_PROFILE:-}" = "skills" ]; then
    emit "$event"
    exit 0
  fi
  # Grilling, on two triggers.
  #
  # A long prompt is a plan whether or not it says so, and the first substantive request of a
  # session is the one where a bad assumption is cheapest to catch and most expensive to keep.
  # Both are decidable here without judgement: one is a character count, the other is whether
  # this session has been seen before.
  #
  # Deliberately not a Stop-hook mandate. Blocking the end of every long-prompt turn that did not
  # grill would fire constantly, and compare-baseline already records the rule this setup runs
  # on: a guard that nags gets switched off, which is worse than one that is merely probable.
  # This injects an instruction at the moment it applies and leaves the model to act on it.
  #
  # VSTACK_NO_GRILL=1 turns it off. VSTACK_GRILL_CHARS moves the long-prompt threshold.
  grill=""
  if [ "${VSTACK_NO_GRILL:-0}" != "1" ] && [ -n "$JQ" ]; then
    _p=$(printf '%s' "$in" | "$JQ" -r '.prompt // empty' 2>/dev/null)
    _n=${#_p}
    _sid=$(printf '%s' "$in" | "$JQ" -r '.session_id // empty' 2>/dev/null)
    _seen=""
    if [ -n "$_sid" ]; then
      _dir="${TMPDIR:-/tmp}/vstack-grill"
      mkdir -p "$_dir" 2>/dev/null
      # Pruned by age rather than on exit: there is no hook event for "session ended", and a
      # marker directory that only grows is a slow leak on a machine that runs many sessions.
      find "$_dir" -type f -mmin +720 -delete 2>/dev/null
      _mark="$_dir/$(printf '%s' "$_sid" | tr -cd 'A-Za-z0-9_-')"
      [ -e "$_mark" ] && _seen=1
      : > "$_mark" 2>/dev/null
    fi
    # First substantive prompt of the session, or any prompt long enough to be a plan. The
    # 120-character floor on the first one keeps "fix this typo" from opening an interview.
    if [ "$_n" -ge "${VSTACK_GRILL_CHARS:-320}" ] \
       || { [ -z "$_seen" ] && [ "$_n" -ge 120 ]; }; then
      grill='
GRILL: run the grill-me skill when no skill matches this situation more specifically. A
situation-matched skill outranks it. grill-me is for a request whose shape is still undecided.'
    fi
  fi
  # Delegation-mandate strike count, re-pinned every prompt instead of stated once at
  # SessionStart and then never again. skill-mandate.sh (Stop) is the only writer of these two
  # small counter files; this only reads them -- a cat of two tiny files under $TMPDIR, not a
  # transcript parse, so it costs nothing like the Stop hook's own evaluation does. It is also
  # why this can run every single prompt with no latency argument to make: there is no scan here.
  #
  # Two independent counters because skill-mandate.sh's own delegation family (breadth +
  # agent-naming) no longer shares the skill mandates' (unslop/typescript/prove-it-works)
  # 2-strike-per-session latch -- it latches 2-per-$VSTACK_DELEGATE_RESET_SECS-window instead, so
  # a long session's delegation reminder keeps re-arming instead of going silent forever the
  # first time both skill mandates tripped. See skill-mandate.sh's own comment at the top of its
  # counter-reading section for the real-session evidence (5b14be87-2cee-4661-96ea-6106ef15f313)
  # that motivated the split.
  #
  # Silent (0 bytes) at 0/0, same as $grill's own steady state -- most prompts in most sessions
  # never tripped either mandate, and the byte budget (check 18 / the grill worst-case probe in
  # .claude/verify.sh) is a hard cap paid on every single prompt whether or not either counter is
  # nonzero, so a line that always rendered would be the expensive default for the common case.
  mandate=""
  if [ "${VSTACK_NO_MANDATE:-0}" != "1" ] && [ -n "$JQ" ]; then
    _msid=$(printf '%s' "$in" | "$JQ" -r '.session_id // empty' 2>/dev/null)
    [ -n "$_msid" ] || _msid="pid$PPID"
    _mcnt_file="${TMPDIR:-/tmp}/vstack-mandate-$_msid"
    _mcnt=$(cat "$_mcnt_file" 2>/dev/null || echo 0)
    case "$_mcnt" in ''|*[!0-9]*) _mcnt=0 ;; esac
    _mdcnt=$(cat "$_mcnt_file.delegate" 2>/dev/null || echo 0)
    case "$_mdcnt" in ''|*[!0-9]*) _mdcnt=0 ;; esac
    if [ "$_mcnt" -ge 1 ] || [ "$_mdcnt" -ge 1 ]; then
      mandate="
MANDATE skill=$_mcnt/2 delegate=$_mdcnt/2: dispatch + name a call sign now."
    fi
  fi
  emit "$event" 'TOKENS: grep/ranges, not whole files; batch independent tool calls in ONE message.
DELEGATE: mechanical -> worker/explorer, judgment -> sonnet agents. ACT, do not ask. Skills fire on the situation — call the Skill tool.'"$grill$mandate"
  exit 0
fi

MSG=$(cat <<'EOF'
OPERATING MODE — SESSION BASELINE (a per-prompt digest re-pins the essentials).
TOKENS: never read whole files (grep/glob + line ranges), never dump file contents to output
(summarize), batch all independent tool calls in ONE message, cap context use.
DELEGATE: the main loop is the expensive frontier model. Mechanical work (simple edits,
boilerplate, renames, config, search, reads) -> worker/explorer (Haiku). Judgment work (code
review, tests, debugging, security) -> Sonnet (code-reviewer/test-writer/debugger/
security-auditor). Architecture -> planner. Keep only hard cross-cutting reasoning and final
synthesis on the main thread. Subagents return tight summaries, never file dumps. Serialize
edits to shared files. Skip delegation only for a truly trivial one-step ask.
AUTONOMY: act without asking; assume + document + proceed. Still confirm irreversible
destructive ops.
PLAN MODE: preempts this. Forces builtin Explore/Plan agents, bars writes. MORTY and ZEEP
unreachable, /team deferred until exit.
SKILLS + AGENTS: dispatch is attributed (e.g., "qa (BETH J-42) sampled X cases").
Skills fire on the SITUATION, not a slash command. When one matches, call the Skill tool
and follow it. Agent dispatch: each report says which agent, using roster call signs
(RICK/MEESEEKS/MORTY/SUMMER/ZEEP/GLOOTIE/JAGUAR/BETH/BIRDPERSON/EVIL-MORTY/NOOBNOOB/PICKLE-RICK/SCARY-TERRY/POOPYBUTTHOLE/UNITY).
Descriptions alone do not reliably trigger the first two lines below, so they are spelled out:
- any prose you write (docs, README, PR body, commit msg) -> unslop; docs/RFC/README ->
  technical-writing. Reading/writing/reviewing .ts/.tsx -> typescript-best-practices.
- work splits into independent parts, or "in parallel"/"at once"/"try N ways" -> swarm.
  Deterministic pipelines (stages, loops, verify passes) -> the native Workflow tool, not
  chained Agent calls.
- shipping a risky change or a diff you do not trust -> blast-radius. Merging auth, payments,
  or agent-written code with no second reviewer -> interrogate.
- about to write a UI component from scratch in a React/Tailwind repo -> component-registry.
- repo has no scripted proof it works -> create-verification-skill (it writes the
  .claude/verify.sh the Stop hook runs). That gate stale -> maintain-verification-skill.
- work runs unattended/overnight, or you are told someone reviews it later -> start
  show-me-your-work BEFORE doing the work, not after.
- feature/change request, shape undecided -> brainstorming.
- shape agreed, nothing written down -> writing-plans.
- plan written, no test yet -> test-driven-development.
- failing test exists against plan -> executing-plans.
- you were corrected, or found a workflow worth keeping -> reflect.
- PRINCIPLES (load the one that matches, then apply it): before claiming done ->
  principle-prove-it-works. Debugging or adding a try/except guard ->
  principle-fix-root-causes. Same correction twice -> principle-encode-lessons-in-structure.
  Designing types/signatures -> principle-type-system-discipline. Validation/error
  handling/auth/MCP adapters -> principle-boundary-discipline. Cron, launchd, retry loops ->
  principle-make-operations-idempotent. Sweeps, migrations, stacked commits ->
  principle-sequence-verifiable-units. Repeated manual edits or checks ->
  principle-build-the-lever.
EOF
)

# Skills profile: keep only the SKILLS block. Everything above it is operating policy.
#
# The chain used to be one mandate line ("run the chain: brainstorming, then writing-plans,
# then...") that this branch rewrote into softer, non-mandate prose so a bare skill-pack
# install carried no policy. It is now four situational lines in the source block itself --
# each fires on its own precondition, not a forced sequence -- so no profile-specific rewrite
# is needed; the skills-only pack gets the same judgement-not-instruction framing as everyone
# else for free.
if [ "${VSTACK_PROFILE:-}" = "skills" ]; then
  MSG=$(printf '%s\n' "$MSG" | sed -n '/^SKILLS/,$p')
  emit "$event" "$MSG"
  exit 0
fi

# --- workspace conventions: only outside Conductor (the app prepends its own, richer block) ---
if [ -z "$CONDUCTOR_WORKSPACE_PATH" ]; then
  d="${CLAUDE_PROJECT_DIR:-$PWD}"
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    root=$(git -C "$d" rev-parse --show-toplevel)
    branch=$(git -C "$d" branch --show-current 2>/dev/null)
    base=$(git -C "$d" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    # These values are repo-controlled (a cloned repo picks its branch names and its dir
    # name) and get spliced into trusted session context — strip them to a plain charset so
    # a crafted name cannot smuggle instruction text or formatting into the block.
    root=$(printf '%s' "$root" | tr -cd 'A-Za-z0-9 ._/-' | head -c 160)
    branch=$(printf '%s' "$branch" | tr -cd 'A-Za-z0-9._/-' | head -c 80)
    base=$(printf '%s' "$base" | tr -cd 'A-Za-z0-9._/-' | head -c 80)
    if [ -z "$base" ]; then
      for c in origin/main origin/master; do
        git -C "$d" rev-parse --verify --quiet "$c" >/dev/null 2>&1 && { base="$c"; break; }
      done
    fi
    [ -z "$base" ] && base="origin/main"
    MSG="$MSG

WORKSPACE CONVENTIONS.
- Repo root: $root - branch: ${branch:-<detached>}.
- Target branch for every diff, review and PR: $base. Use \`git diff $base...HEAD\`, never a
  bare \`git diff\`. Open PRs against $base.
- Do NOT rename, delete or re-point the current branch. Commit onto it.
- Scratch space is \`$root/.context/\` - plans, notes, research, todos go there and nowhere
  else in the repo. Keep it untracked: if \`.context/\` is absent from
  \`\$(git rev-parse --git-common-dir)/info/exclude\`, append it before writing.
- If the user asks for work unrelated to this branch, do not start it here; say so and offer
  a separate git worktree (\`claude -w <name>\`)."
  fi
fi

# --- the policy document, for sandboxes only ---------------------------------------------
# It used to travel as a second CLAUDE.md committed into the repo. That worked, and it also meant
# ~/.claude/CLAUDE.md and .claude/CLAUDE.md held identical bytes on this machine and Claude Code
# loaded both, as user memory and as project memory. Nothing could dedupe that: the client reads
# both files itself and no hook runs in between.
#
# So the overlay ships the text as .claude/hooks/policy.md, which is not a memory path and is read
# by nothing but this script, and the copy that already knows whether it is the only voice in the
# room decides whether to speak it. A sandbox has no ~/.claude, so the overlay is the only lane and
# it carries the policy. On a machine with the user-scope install, ~/.claude/CLAUDE.md carries it
# and this appends nothing -- which is also why the condition is global_live rather than the
# suppression switch: turning the switch off should restore the digest, not reintroduce a second
# copy of the policy.
if [ "${is_overlay:-0}" = 1 ] && [ "${global_live:-0}" = 0 ]; then
  pol="$(dirname "$self")/policy.md"
  if [ -r "$pol" ]; then
    MSG="$MSG

$(cat "$pol")"
  fi
fi

emit "$event" "$MSG"
exit 0
