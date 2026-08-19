#!/usr/bin/env bash
# Run a Claude task HEADLESS (claude -p) → separate weekly pool, does NOT touch interactive Opus 5 budget.
# Usage: claude-bg.sh "<prompt or /command>" [model]   (model default: sonnet — cheap grunt work)
# Interactive Opus 5 can dispatch heavy/mechanical work here to conserve the interactive pool.
set -uo pipefail
prompt="${1:?usage: claude-bg.sh \"<prompt>\" [model]}"; model="${2:-sonnet}"
ts=$(date +%Y%m%d-%H%M%S); log="$HOME/.config/agents/bg/$ts.log"
{
  echo "▶ headless run @ $ts  model=$model"
  claude -p "$prompt" --model "$model" --dangerously-skip-permissions
  rc=$?
  echo "◀ exit $rc"
  osascript -e "display notification \"headless job done (exit $rc)\" with title \"claude-bg\" sound name \"Glass\"" >/dev/null 2>&1 || true
} > "$log" 2>&1 &
echo "dispatched → $log (pid $!)  [separate headless pool]"
