#!/usr/bin/env bash
# Merged SessionStart injector: TOKENMAXXING + ORCHESTRATOR + workspace conventions.
# Replaces inject-tokenmaxxing.sh + inject-orchestrator.sh (one spawn instead of three).
# Portable: no absolute /Users paths, so it also works from a committed repo overlay.
event=$(/usr/bin/jq -r '.hook_event_name // "SessionStart"' 2>/dev/null </dev/stdin)
[ -z "$event" ] || [ "$event" = "null" ] && event="SessionStart"

MSG=$(cat <<'EOF'
OPERATING MODE — ACTIVE EVERY RESPONSE, REGARDLESS OF MODEL.
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
EOF
)

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
