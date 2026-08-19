#!/usr/bin/env bash
# PostToolUseFailure: feed the failure back so the agent self-heals instead of blindly retrying.
set -uo pipefail
# jq resolved, not hardcoded: at /usr/bin/jq only this hook emitted nothing at all on a Linux
# host, so the self-heal feedback silently stopped existing on exactly the machines least
# likely to be watched.
JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi

esc(){ printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
       | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
       | awk 'BEGIN{ORS=""}{print (NR>1?"\\n":"") $0}'; }

in=$(cat)
if [ -n "$JQ" ]; then tool=$(printf '%s' "$in" | "$JQ" -r '.tool_name // "tool"' 2>/dev/null)
else tool=$(printf '%s' "$in" | sed -n 's/.*"tool_name" *: *"\([^"]*\)".*/\1/p' | head -1); fi
[ -n "$tool" ] || tool=tool
# Redact token shapes before the tail re-enters the transcript: a failing command that
# echoed a credential would otherwise persist it in the conversation log forever.
# Redact token shapes before the tail re-enters the transcript: a failing command that
# echoed a credential would otherwise persist it in the conversation log forever. The keyword
# class covers all three cases — an uppercase-only pattern walked straight past api_key=.
redact(){ sed -E 's/(sk-ant-|sk-proj-|github_pat_|ghp_|gho_|xoxb-|AKIA|AIza)[A-Za-z0-9_\/+-]+/\1[REDACTED]/g; s/((KEY|TOKEN|SECRET|PASSWORD|key|token|secret|password|Key|Token|Secret|Password)[A-Za-z_]*=)[^[:space:]]+/\1[REDACTED]/g'; }
if [ -n "$JQ" ]; then
  err=$(printf '%s' "$in" | "$JQ" -r '(.tool_response.error // .tool_response.stderr // .tool_response // "") | tostring' 2>/dev/null \
    | redact | tail -c 900)
else
  # No jq means no reliable way to pull a nested field out of the payload. Say so rather than
  # splicing in a half-parsed fragment, and still deliver the instruction.
  err="(error tail unavailable: jq not installed)"
fi
MSG="SELF-HEAL: the last $tool call FAILED. Do NOT blindly re-run the same call. Diagnose the root cause from the error below, fix the underlying issue (missing dep / wrong path / syntax / perms / bad assumption), then retry. If it fails twice more, stop and report the diagnosis. Error tail:
$err"
if [ -n "$JQ" ]; then
  "$JQ" -cn --arg c "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUseFailure",additionalContext:$c}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"%s"}}\n' "$(esc "$MSG")"
fi
exit 0
