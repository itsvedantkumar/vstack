#!/usr/bin/env bash
# Stop: refuse to finish when the session did work that a skill is mandated for and never ran it.
#
# vstack already tells the model how to route: the SessionStart digest spells out "any prose you
# write -> unslop", and the skill descriptions carry their own triggers. Both are instructions,
# and an instruction is a probability. Measured over 12 prompts the routing lands, but "lands most
# of the time" is not the same claim as "always", and the second one is the one worth having.
#
# This closes the gap for the few rules where the situation is decidable from the transcript
# rather than from judgement. It reads what the session actually did -- which files were written,
# which skills were invoked -- and blocks Stop when a mandate went unmet. Nothing here guesses at
# intent: if the rule cannot be decided by looking at tool calls, it does not belong in this file.
#
# Escape hatch: VSTACK_NO_MANDATE=1 disables it entirely. A gate you cannot turn off gets deleted
# by the first person it inconveniences, which is worse than one that is on by default.
set -uo pipefail

[ "${VSTACK_NO_MANDATE:-0}" = "1" ] && exit 0

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi
# Without jq there is no way to read the transcript path or emit a block reason safely. Say
# nothing rather than guess: a mandate that misfires is worse than one that abstains.
[ -n "$JQ" ] || exit 0

input=$(cat 2>/dev/null || true)

# Claude Code sets this when Stop already fired once for this turn. Blocking again from inside a
# block is how a hook turns into an infinite loop.
[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = "true" ] && exit 0

tr_=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty')
[ -n "$tr_" ] && [ -f "$tr_" ] || exit 0

sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty'); [ -n "$sid" ] || sid="pid$PPID"
cnt_file="${TMPDIR:-/tmp}/vstack-mandate-$sid"
cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
# Same latch as the verify gate. A mandate the model cannot satisfy must not trap the session.
[ "$cnt" -ge 2 ] && exit 0

# Every file this session wrote or edited, and every skill it invoked. Both come from the
# transcript, so this measures what happened rather than what was asked for.
paths=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="NotebookEdit"))
            | .input.file_path // empty' "$tr_" 2>/dev/null | sort -u
)
skills=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' "$tr_" 2>/dev/null \
  | sed 's/.*://' | sort -u
)

fired(){ printf '%s\n' "$skills" | grep -qxF "$1"; }

unmet=""
# --- the mandates -----------------------------------------------------------------------------
# Each one needs a situation decidable from a tool call, and a skill that is the answer to it
# every single time. That second half is the strict part: a rule that is right nine times out of
# ten belongs in the digest as guidance, not here as a gate.

# Prose. Any Markdown that is not a machine-written log or a vendored file.
prose=$(printf '%s\n' "$paths" | grep -iE '\.(md|mdx)$' \
        | grep -viE '(CHANGELOG\.md|node_modules|\.audit/|/(dist|build|vendor)/)' | head -5)
if [ -n "$prose" ] && ! fired unslop; then
  unmet="$unmet
  unslop -- you wrote prose and it never ran: $(printf '%s' "$prose" | tr '\n' ' ')"
fi

# TypeScript. Reading one is judgement; writing one is not.
ts=$(printf '%s\n' "$paths" | grep -E '\.(ts|tsx)$' | grep -v node_modules | head -5)
if [ -n "$ts" ] && ! fired typescript-best-practices; then
  unmet="$unmet
  typescript-best-practices -- you wrote TypeScript and it never ran: $(printf '%s' "$ts" | tr '\n' ' ')"
fi

[ -n "$unmet" ] || { rm -f "$cnt_file"; exit 0; }

echo $((cnt+1)) > "$cnt_file"
reason="A vstack skill mandate went unmet (attempt $((cnt+1))/2). These fire every time, not when they seem relevant:
$unmet

Run each named skill with the Skill tool against the files listed, apply what it says, then finish.
Set VSTACK_NO_MANDATE=1 to disable this gate."
"$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
