#!/usr/bin/env bash
# Stop hook. Opt-in: acts only if $CLAUDE_PROJECT_DIR/.claude/verify.sh exists & is executable.
# Runs it; if it fails, blocks the agent from finishing and feeds the failure back. Safe no-op otherwise.
# Caps at 3 blocks per session so an unfixable failure can't infinite-loop an overnight run.
input=$(cat 2>/dev/null || true)
d="${CLAUDE_PROJECT_DIR:-$PWD}"
v="$d/.claude/verify.sh"
[ -x "$v" ] || exit 0
sid=$(printf '%s' "$input" | /usr/bin/jq -r '.session_id // "nosess"' 2>/dev/null || echo nosess)
cnt_file="${TMPDIR:-/tmp}/verify-gate-block-$sid"
cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
# Latched open at the cap: the counter file stays put so an unfixable failure blocks at
# most 3 times per session, ever — not in repeating groups of 3. A later real pass below
# removes the file and re-arms the gate.
if [ "$cnt" -ge 3 ]; then
  exit 0
fi
out=$(cd "$d" && bash "$v" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo $((cnt+1)) > "$cnt_file"
  /usr/bin/jq -cn --arg r "Verification failed (.claude/verify.sh exit $rc, attempt $((cnt+1))/3). Fix these before finishing:
$out" '{decision:"block",reason:$r}'
else
  rm -f "$cnt_file"
fi
exit 0
