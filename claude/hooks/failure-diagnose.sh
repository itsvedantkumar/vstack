#!/usr/bin/env bash
# PostToolUseFailure: feed the failure back so the agent self-heals instead of blindly retrying.
in=$(cat)
tool=$(printf '%s' "$in" | /usr/bin/jq -r '.tool_name // "tool"' 2>/dev/null)
# Redact token shapes before the tail re-enters the transcript: a failing command that
# echoed a credential would otherwise persist it in the conversation log forever.
err=$(printf '%s' "$in" | /usr/bin/jq -r '(.tool_response.error // .tool_response.stderr // .tool_response // "") | tostring' 2>/dev/null \
  | sed -E 's/(sk-ant-|github_pat_|ghp_|gho_|AKIA)[A-Za-z0-9_\/+-]+/\1[REDACTED]/g; s/((KEY|TOKEN|SECRET|PASSWORD)[A-Z_]*=)[^[:space:]]+/\1[REDACTED]/g' \
  | tail -c 900)
MSG="SELF-HEAL: the last $tool call FAILED. Do NOT blindly re-run the same call. Diagnose the root cause from the error below, fix the underlying issue (missing dep / wrong path / syntax / perms / bad assumption), then retry. If it fails twice more, stop and report the diagnosis. Error tail:
$err"
/usr/bin/jq -cn --arg c "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUseFailure",additionalContext:$c}}'
exit 0
