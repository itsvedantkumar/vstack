#!/usr/bin/env bash
# compat-canary.sh — Claude Code compatibility canary.
#
# Every hook in this directory parses the JSON payload Claude Code hands it with `jq ... // empty`
# or `// "SessionStart"` fallbacks and no `else`. That is the right default for *that* hook (a
# mandate that misfires is worse than one that abstains — skill-mandate.sh's own comment), but it
# means a version or payload shape this bundle has never seen degrades to exactly the same
# behaviour as nothing happening: exit 0, no output. docs/checks-that-inherit-their-answer.md
# names this pattern "silence read as success". This script is the one place that is allowed to
# say "I don't know" out loud instead of quietly doing nothing.
#
# Contract: exit 0 + silent stdout = KNOWN (a recognised Claude Code version and a payload whose
# shape this bundle understands for its event). exit 2 + a line starting "COMPAT: UNKNOWN" =
# UNKNOWN, and the line names every field or version it could not read. Never exit 1 for a
# compatibility question — 1 is reserved for this script's own crash (e.g. cat/date missing).
#
# This is a canary, not a gate: nothing here blocks a session or a tool call. A version bump
# reports UNKNOWN; it does not brick the next `claude` invocation over a routine upgrade.
#
# KNOWN_FAMILIES is the set of Claude Code major.minor lines this bundle's hooks have actually
# been run against. 2.1 is the family the local reference CLI (2.1.243) belongs to. Add a family
# here only after running the hook suite against it — this list is a claim about what was
# verified, not a guess about what will probably still work.
set -uo pipefail

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi

KNOWN_EVENTS="SessionStart UserPromptSubmit Stop SubagentStop PreToolUse PostToolUse PostToolUseFailure Notification PreCompact"
KNOWN_FAMILIES="2.1"

# ${HOME:-} rather than $HOME: under `set -u` a bare expansion aborts this hook on its own
# assignment line when HOME is absent, which is every launchd agent and every `env -i`. The
# canary's job is to report what it observed, so failing to find somewhere to write it must
# degrade to writing nowhere, not to killing the tool call that triggered it.
STATE_FILE="${VSTACK_COMPAT_CANARY_LOG:-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/vstack-compat-canary.json}"

reasons=""
add_reason(){ reasons="${reasons:+$reasons; }$1"; }

input=$(cat 2>/dev/null || true)

if [ -z "$JQ" ]; then
  add_reason "jq unavailable: cannot validate payload shape"
fi

event=""
if [ -n "$JQ" ]; then
  if ! printf '%s' "$input" | "$JQ" -e . >/dev/null 2>&1; then
    add_reason "payload did not parse as JSON"
  else
    event=$(printf '%s' "$input" | "$JQ" -r '.hook_event_name // empty' 2>/dev/null)
    if [ -z "$event" ]; then
      add_reason "payload has no hook_event_name field"
    else
      case " $KNOWN_EVENTS " in
        *" $event "*) : ;;
        *) add_reason "hook_event_name '$event' is not one this bundle recognises" ;;
      esac
      # Per-event companion field this bundle's hooks actually read for that event (see
      # inject-session-context.sh:.session_id, skill-mandate.sh:.transcript_path,
      # format.sh/guard-destructive.sh:.tool_input -> .tool_name upstream of it).
      case "$event" in
        SessionStart|UserPromptSubmit)
          f=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
          [ -n "$f" ] || add_reason "payload for $event has no session_id field"
          ;;
        Stop|SubagentStop)
          f=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)
          [ -n "$f" ] || add_reason "payload for $event has no transcript_path field"
          ;;
        PreToolUse|PostToolUse|PostToolUseFailure)
          f=$(printf '%s' "$input" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
          [ -n "$f" ] || add_reason "payload for $event has no tool_name field"
          ;;
      esac
    fi
  fi
fi

# VSTACK_CLAUDE_VERSION_OVERRIDE exists for tests and for an operator who wants to pin/simulate a
# version without invoking the real CLI. Real detection shells out to `claude --version`.
version="${VSTACK_CLAUDE_VERSION_OVERRIDE:-}"
if [ -z "$version" ] && command -v claude >/dev/null 2>&1; then
  version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi
if [ -z "$version" ]; then
  add_reason "could not determine the running Claude Code version (no VSTACK_CLAUDE_VERSION_OVERRIDE and no 'claude' on PATH)"
else
  fam=$(printf '%s' "$version" | cut -d. -f1-2)
  case " $KNOWN_FAMILIES " in
    *" $fam "*) : ;;
    *) add_reason "Claude Code version $version (family $fam) is outside the tested set ($KNOWN_FAMILIES.x)" ;;
  esac
fi

ts=$(date +%s 2>/dev/null || echo 0)
case "$ts" in ''|*[!0-9]*) ts=0 ;; esac

if [ -n "$reasons" ]; then status="UNKNOWN"; else status="KNOWN"; fi

if [ -n "$JQ" ]; then
  rec=$("$JQ" -cn --arg s "$status" --arg v "$version" --arg e "$event" --arg r "$reasons" --argjson ts "$ts" \
    '{status:$s, version:$v, event:$e, reasons:$r, ts:$ts}' 2>/dev/null)
else
  rec="{\"status\":\"$status\"}"
fi
log_dir_="${STATE_FILE%/*}"
[ "$log_dir_" = "$STATE_FILE" ] && log_dir_="."
mkdir -p "$log_dir_" 2>/dev/null
# `> "$STATE_FILE" 2>/dev/null` does not silence a failed redirection. The shell opens the target
# and reports the failure itself, before printf exists to have its stderr redirected -- which is
# why an unwritable path printed `No such file or directory` on every tool call rather than
# degrading quietly. The subshell puts the shell's own message somewhere we can redirect.
#
# Temp file then rename, rather than truncate in place: this is a PreToolUse hook, it fires on
# every tool call, and nothing serialises two of them. A truncating write that loses its race
# leaves a half-written record for the next run to parse.
(
  if _cc_tmp=$(mktemp "$log_dir_/.canary.XXXXXX" 2>/dev/null); then
    if printf '%s\n' "$rec" > "$_cc_tmp" 2>/dev/null; then
      mv -f "$_cc_tmp" "$STATE_FILE" 2>/dev/null || rm -f "$_cc_tmp" 2>/dev/null
    else
      rm -f "$_cc_tmp" 2>/dev/null
    fi
  fi
) 2>/dev/null

if [ "$status" = UNKNOWN ]; then
  printf 'COMPAT: UNKNOWN -- %s\n' "$reasons"
  exit 2
fi
exit 0
