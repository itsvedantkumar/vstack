#!/usr/bin/env bash
LOG="$HOME/.config/agents/doctor.log"
ts=$(date '+%Y-%m-%d %H:%M')
out=$("$HOME/.config/agents/bin/doctor" 2>&1); rc=$?
printf '\n=== %s (exit %s) ===\n%s\n' "$ts" "$rc" "$out" >> "$LOG"
if [ "$rc" -ne 0 ]; then
  osascript -e 'display notification "Setup drift detected — run /doctor" with title "Agent Doctor" sound name "Basso"' >/dev/null 2>&1 || true
fi
exit 0

