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
# Redact credential shapes before the tail re-enters the transcript: a failing command that
# echoed a secret would otherwise persist it in the conversation log forever.
#
# This used to be two rules -- known token prefixes, and NAME=value. Against seven real shapes it
# caught one. `{"api_key": "..."}`, `x-api-key: ...`, `password: ...`, `aws_secret_access_key =
# ...`, `Authorization: Bearer <jwt>` and `postgres://user:pw@host` all went through verbatim,
# because every one of them separates the name from the value with something other than a bare
# `=`. JSON, YAML and HTTP headers are the formats a failing command is most likely to print.
#
# Over-redaction is the cheap direction here: this text is diagnostic context for a model, and a
# masked value costs a retry while a leaked one is permanent.
redact(){
  # Prefixed tokens, JWTs, auth headers and URL userinfo are unambiguous, so sed handles them.
  sed -E \
    -e 's/(sk-ant-|sk-proj-|sk-|github_pat_|ghp_|gho_|ghu_|ghs_|ghr_|glpat-|xoxb-|xoxp-|xoxa-|xapp-|AKIA|ASIA|AIza|ya29\.|hf_|npm_|dop_v1_)[A-Za-z0-9_\/+.-]{6,}/\1[REDACTED]/g' \
    -e 's/(eyJ[A-Za-z0-9_-]{4,})\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]+/\1.[REDACTED]/g' \
    -e 's/([Aa]uthorization|[Pp]roxy-[Aa]uthorization)([[:space:]]*[:=][[:space:]]*)("?)([A-Za-z]+[[:space:]]+)?[^[:space:]"'"'"']{6,}/\1\2\3\4[REDACTED]/g' \
    -e 's|([A-Za-z][A-Za-z0-9+.-]*://[^/:[:space:]]+):[^@[:space:]]+@|\1:[REDACTED]@|g' \
  | awk '
  # NAME=VALUE needs both halves judged, which sed cannot do. Matching the name alone ate
  # ordinary output: the hook digest line "TOKENS: never read whole files" came back as
  # "TOKENS: [REDACTED] read whole files", and "Keystrokes: 1420 recorded" went the same way.
  # A diagnostic tail that has been chewed up is worth nothing, and the point of this hook is
  # that the tail gets read. So the name only nominates a candidate; the value decides.
  #
  # A credential is opaque. English is not. Sixteen or more characters, or six-plus with a
  # digit in them, or base64 padding, and it is not a word anyone typed as prose. "never" and
  # "1420" survive that test and every real key shape below fails it.
  function looks_secret(v,   n) {
    gsub(/^["\047]+|["\047]+$/, "", v)
    n = length(v)
    if (n < 4) return 0
    if (n >= 16) return 1
    if (v ~ /[0-9]/ && n >= 6) return 1
    if (v ~ /[\/+=]/) return 1
    return 0
  }
  {
    line = $0; out = ""
    while (1) {
      lc = tolower(line)
      if (!match(lc, /(^|[^a-z0-9_-])[a-z0-9_-]*(key|token|secret|passwd|password|credential)[a-z0-9_-]*"?[ \t]*[:=][ \t]*"?[^ \t,;"\047]+/)) break
      st = RSTART; ln = RLENGTH
      seg = substr(line, st, ln)
      if (match(seg, /[:=][ \t]*"?/)) {
        head = substr(seg, 1, RSTART + RLENGTH - 1)
        val  = substr(seg, RSTART + RLENGTH)
        if (looks_secret(val)) seg = head "[REDACTED]"
      }
      out = out substr(line, 1, st - 1) seg
      line = substr(line, st + ln)
    }
    print out line
  }'
}
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
