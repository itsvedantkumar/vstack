#!/usr/bin/env bash
# Run a Claude task HEADLESS (claude -p) → separate weekly pool, does NOT touch interactive Opus 5 budget.
# Usage: claude-bg.sh "<prompt or /command>" [model]   (model default: sonnet — cheap grunt work)
# Interactive Opus 5 can dispatch heavy/mechanical work here to conserve the interactive pool.
set -uo pipefail

self="claude-bg.sh"

usage(){
  cat >&2 <<'EOF'
usage: claude-bg.sh "<prompt or /command>" [model]

Dispatch a headless claude -p run in the background (separate weekly pool from the
interactive session). model defaults to sonnet.
EOF
}

if [ $# -eq 0 ]; then
  echo "$self: prompt required" >&2
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

prompt="$1"; model="${2:-sonnet}"
if [ $# -gt 2 ]; then
  echo "$self: ignoring extra argument(s): ${*:3}" >&2
fi

# PATH hardening: APPEND known locations to the inherited PATH (never replace it, never
# override it) so a cron-shaped minimal PATH still finds claude.
#
# These used to be prepended, which achieves the stated goal and one unstated thing besides:
# it overrides the caller. A `claude` the caller deliberately put first -- a wrapper, a pinned
# version, a test stub -- lost to whatever sits in /usr/local/bin. tests/bin-scripts.sh
# advertises that "every claude in here is a local stub script, never the real CLI" and CI
# proved otherwise the first time it ran: the real CLI dispatched and answered
# "Not logged in - Please run /login". Appending serves the cron case exactly as well, because
# a minimal PATH has no claude on it to win the race in the first place.
export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
if ! command -v claude >/dev/null 2>&1; then
  echo "$self: claude not found on PATH ($PATH)" >&2
  exit 3
fi

bgdir="$HOME/.config/agents/bg"
mkdir -p "$bgdir" 2>/dev/null
if [ ! -d "$bgdir" ] || [ ! -w "$bgdir" ]; then
  echo "$self: cannot write to $bgdir" >&2
  exit 1
fi
ts=$(date +%Y%m%d-%H%M%S); log="$bgdir/$ts.log"
if ! : > "$log" 2>/dev/null; then
  echo "$self: cannot create log file: $log" >&2
  exit 1
fi

{
  echo "▶ headless run @ $ts  model=$model"
  claude -p "$prompt" --model "$model" --dangerously-skip-permissions
  rc=$?
  echo "◀ exit $rc"
  osascript -e "display notification \"headless job done (exit $rc)\" with title \"claude-bg\" sound name \"Glass\"" >/dev/null 2>&1 || true
} > "$log" 2>&1 &
echo "dispatched → $log (pid $!)  [separate headless pool]"
