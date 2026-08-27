#!/usr/bin/env bash
# claude-task.sh <task-name> [model] — run ~/.claude/scheduled-tasks/<task-name>/SKILL.md headless.
# Used by cron for overnight autonomous runs. Logs to the task dir; keeps last run only.
set -u

self="claude-task.sh"

usage(){
  cat >&2 <<'EOF'
usage: claude-task.sh <task-name> [model]

Run ~/.claude/scheduled-tasks/<task-name>/SKILL.md headless via claude -p.
Intended for cron/launchd; logs the run to the task directory (last run only).
Exit status mirrors the inner claude run.
EOF
}

if [ $# -eq 0 ]; then
  echo "$self: task name required" >&2
  usage
  exit 2
fi

case "$1" in
  --help|-h)
    usage
    exit 2
    ;;
  -*)
    echo "$self: unknown option: $1" >&2
    usage
    exit 2
    ;;
esac

t="$1"
# Pinned: user settings.json now defaults to claude-opus-5[1m] + effortLevel:high.
# Scheduled tasks must not silently inherit that — they are cheap, unattended runs.
model="${2:-sonnet}"
if [ $# -gt 2 ]; then
  echo "$self: ignoring extra argument(s): ${*:3}" >&2
fi

taskdir="$HOME/.claude/scheduled-tasks/$t"
f="$taskdir/SKILL.md"
if [ ! -d "$taskdir" ]; then
  echo "$self: no such task directory: $taskdir" >&2
  exit 3
fi
if [ ! -f "$f" ]; then
  echo "$self: task directory has no SKILL.md: $f" >&2
  exit 3
fi

# Resolve PATH robustly under launchd (no login shell, minimal env, no nvm version pinned):
# prefer $HOME/.local/bin, then an nvm current/default symlink, then the newest installed nvm
# version dir (by mtime), then common Homebrew/system paths. These are PREPENDED to the
# inherited PATH, never a replacement for it — a claude install anywhere else on the caller's
# own PATH must still resolve.
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
  # Newest installed nvm version dir by mtime. Avoids SC2012 (parsing `ls` output): glob the
  # candidate dirs directly and rank them by mtime instead of piping `ls -dt` into `head`.
  newest=""; newest_mtime=0
  for d in "$HOME"/.nvm/versions/node/*/bin; do
    [ -d "$d" ] || continue
    # stat -f (BSD/macOS) vs -c (GNU/Linux)
    mtime=$(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$newest_mtime" ]; then newest_mtime=$mtime; newest="$d"; fi
  done
  nvm_bin="$newest"
fi
# Appended, not prepended: see the paragraph on the same line in bin/claude-bg.sh. A caller
# who puts a claude first on PATH means it, and this script is invoked unattended by cron and
# launchd, where silently running a different binary than the one the operator installed is
# the least debuggable failure available.
export PATH="$PATH:$HOME/.local/bin${nvm_bin:+:$nvm_bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

if ! command -v claude >/dev/null 2>&1; then
  echo "$self: claude not found on PATH ($PATH)" >&2
  exit 4
fi

log="$taskdir/last-run.log"
# Redirections apply left-to-right: `2>/dev/null` must come BEFORE `> "$log"` so that if opening
# $log fails, bash's own "Permission denied" decoration lands on the already-silenced fd 2
# instead of leaking to the caller ahead of the authored message below.
if ! : 2>/dev/null > "$log"; then
  echo "$self: cannot write log file: $log" >&2
  exit 5
fi

{
  echo "=== run $(date '+%Y-%m-%d %H:%M:%S')"
  # prompt via stdin: SKILL.md frontmatter starts with '---', which the CLI would parse as an option
  claude -p ${model:+--model "$model"} --dangerously-skip-permissions --max-turns 50 < "$f"
  rc=$?
  echo "=== exit $rc $(date '+%Y-%m-%d %H:%M:%S')"
} > "$log" 2>&1

exit "$rc"
