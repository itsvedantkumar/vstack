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
event=$(/usr/bin/jq -r '.hook_event_name // "SessionStart"' 2>/dev/null </dev/stdin)
[ -z "$event" ] || [ "$event" = "null" ] && event="SessionStart"

# Per-prompt digest: must stay tiny and fast (no git work) — it runs on every prompt.
# The skills profile re-pins nothing per prompt; one session-start block is the
# least a skill pack can inject and still work.
if [ "$event" = "UserPromptSubmit" ]; then
  if [ "${VSTACK_PROFILE:-}" = "skills" ]; then
    /usr/bin/jq -cn --arg e "$event" '{hookSpecificOutput:{hookEventName:$e}}'
    exit 0
  fi
  /usr/bin/jq -cn --arg e "$event" --arg c \
'TOKENS: grep/ranges, not whole files; batch independent tool calls in ONE message.
DELEGATE: mechanical -> worker/explorer, judgment -> sonnet agents. ACT, do not ask. Skills fire on the situation — call the Skill tool.' \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
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
SKILLS: these fire on the SITUATION, not on a slash command. When one matches, call the Skill
tool and follow it; do not reconstruct its method from memory, and do not wait to be asked.
Descriptions alone do not reliably trigger the first two lines below, so they are spelled out:
- any prose you write (docs, README, PR body, commit msg) -> unslop; docs/RFC/README ->
  technical-writing. Reading/writing/reviewing .ts/.tsx -> typescript-best-practices.
- work splits into independent parts, or "in parallel"/"at once"/"try N ways" -> swarm.
- shipping a risky change or a diff you do not trust -> blast-radius. Merging auth, payments,
  or agent-written code with no second reviewer -> interrogate.
- repo has no scripted proof it works -> create-verification-skill (it writes the
  .claude/verify.sh the Stop hook runs). That gate stale -> maintain-verification-skill.
- work runs unattended/overnight, or you are told someone reviews it later -> start
  show-me-your-work BEFORE doing the work, not after.
- any feature or change request -> run the chain: brainstorming, then writing-plans, then
  test-driven-development, then executing-plans.
- you were corrected, or found a workflow worth keeping -> reflect.
- PRINCIPLES (load the one that matches, then apply it): before claiming done ->
  prove-it-works. Debugging or adding a try/except guard -> fix-root-causes. Same correction
  twice -> encode-lessons-in-structure. Designing types/signatures -> type-system-discipline.
  Validation/error handling/auth/MCP adapters -> boundary-discipline. Cron, launchd, retry
  loops -> make-operations-idempotent. Sweeps, migrations, stacked commits ->
  sequence-verifiable-units. Repeated manual edits or checks -> build-the-lever.
EOF
)

# Skills profile: keep only the SKILLS block. Everything above it is operating policy.
if [ "${VSTACK_PROFILE:-}" = "skills" ]; then
  MSG=$(printf '%s\n' "$MSG" | sed -n '/^SKILLS:/,$p')
  /usr/bin/jq -cn --arg e "$event" --arg c "$MSG" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
  exit 0
fi

# --- workspace conventions: only outside Conductor (the app prepends its own, richer block) ---
if [ -z "$CONDUCTOR_WORKSPACE_PATH" ]; then
  d="${CLAUDE_PROJECT_DIR:-$PWD}"
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    root=$(git -C "$d" rev-parse --show-toplevel)
    branch=$(git -C "$d" branch --show-current 2>/dev/null)
    base=$(git -C "$d" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
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

/usr/bin/jq -cn --arg e "$event" --arg c "$MSG" \
  '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
exit 0
