#!/usr/bin/env bash
# claude-task.sh <task-name> [model] — run ~/.claude/scheduled-tasks/<task-name>/SKILL.md headless.
# Used by cron for overnight autonomous runs. Logs to the task dir; keeps last run only.

# Resolve PATH robustly under launchd (no login shell, minimal env, no nvm version pinned):
# prefer $HOME/.local/bin, then an nvm current/default symlink, then the newest installed
# nvm version dir (by mtime), then common Homebrew/system paths.
nvm_bin=""
if [ -x "$HOME/.nvm/current/bin/node" ]; then
  nvm_bin="$HOME/.nvm/current/bin"
elif [ -f "$HOME/.nvm/alias/default" ]; then
  default_ver=$(cat "$HOME/.nvm/alias/default" 2>/dev/null)
  if [ -d "$HOME/.nvm/versions/node/v$default_ver" ]; then
    nvm_bin="$HOME/.nvm/versions/node/v$default_ver/bin"
  elif [ -n "$default_ver" ] && [ -d "$HOME/.nvm/versions/node/$default_ver" ]; then
    nvm_bin="$HOME/.nvm/versions/node/$default_ver/bin"
  fi
fi
if [ -z "$nvm_bin" ]; then
  nvm_bin=$(ls -dt "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | head -1)
fi
export PATH="$HOME/.local/bin${nvm_bin:+:$nvm_bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

t="${1:?task name required}"
# Pinned: user settings.json now defaults to claude-opus-5[1m] + effortLevel:high.
# Scheduled tasks must not silently inherit that — they are cheap, unattended runs.
model="${2:-sonnet}"
f="$HOME/.claude/scheduled-tasks/$t/SKILL.md"
[ -f "$f" ] || exit 0
log="$HOME/.claude/scheduled-tasks/$t/last-run.log"
{
  echo "=== run $(date '+%Y-%m-%d %H:%M:%S')"
  # prompt via stdin: SKILL.md frontmatter starts with '---', which the CLI would parse as an option
  claude -p ${model:+--model "$model"} --dangerously-skip-permissions --max-turns 50 < "$f"
  echo "=== exit $? $(date '+%Y-%m-%d %H:%M:%S')"
} > "$log" 2>&1
