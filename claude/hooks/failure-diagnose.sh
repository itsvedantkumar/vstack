#!/usr/bin/env bash
# PostToolUseFailure: feed the failure back so the agent self-heals instead of blindly retrying.
in=$(cat)
tool=$(printf '%s' "$in" | /usr/bin/jq -r '.tool_name // "tool"' 2>/dev/null)
err=$(printf '%s' "$in" | /usr/bin/jq -r '(.tool_response.error // .tool_response.stderr // .tool_response // "") | tostring' 2>/dev/null | tail -c 900)
MSG="SELF-HEAL: the last $tool call FAILED. Do NOT blindly re-run the same call. Diagnose the root cause from the error below, fix the underlying issue (missing dep / wrong path / syntax / perms / bad assumption), then retry. If it fails twice more, stop and report the diagnosis. Error tail:
$err"
/usr/bin/jq -cn --arg c "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUseFailure",additionalContext:$c}}'
exit 0
