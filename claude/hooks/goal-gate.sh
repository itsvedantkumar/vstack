#!/usr/bin/env bash
# Stop hook. Refuses to finish while a recorded goal still has unchecked rubric items.
#
# WHY THIS EXISTS. vstack shipped `claude/commands/goal.md`, whose own description promises the
# agent "only stops when fully verified". A command is text injected at the moment you type it.
# Nothing re-invoked it, and nothing read the `.goal/<slug>/goal.md` file it produces: measured
# 2026-09-01, `grep -rn '\.goal' claude/hooks/` returned zero matches. The writer shipped without
# its reader, so a recorded goal had no effect on any later turn and the agent stopped the moment
# the immediate request was answered. This file is the missing reader.
#
# WHY IT IS NOT MODELLED ON verify-gate.sh. That gate blocks on a red `.claude/verify.sh`, which
# is a fact the agent can act on: fix the code, the red clears. An unchecked rubric box is a
# different animal. Some of them are only completable by the operator -- the goal file that
# prompted this hook lists `vercel login` and "click a button on claude.ai". Blocking Stop on
# those is not persistence, it is a livelock wearing a gate's clothes. Three narrowings follow
# from that, and each one is load-bearing:
#
#   1. Only the `## Rubric` section is read. A `## Residuals` box is by definition work its
#      author deferred to a human.
#   2. A goal whose `Status:` says complete/closed/abandoned is never reopened. The author
#      closed it; a gate that argues with the record is just noise.
#   3. An item tagged `(needs: user)` is reported, never blocking.
#
# And the cap below goes OPEN rather than staying shut, which is the opposite of verify-gate's
# B-12 fix, deliberately. For a correctness gate the cost of releasing too early is shipping a
# red tree, so it keeps blocking. Here the cost of never releasing is an unbounded loop on work
# the agent cannot do, and the cost of releasing is one visible message. Different asymmetry,
# different direction.
#
# Reads markdown and nothing else. It never executes anything out of the repo, which is why it
# needs no `vstack trust` entry and is safe in the plugin lane that verify-gate is excluded from.
set -uo pipefail

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi

# JSON string escaping for the no-jq path, identical in behaviour to verify-gate.sh's: escape
# backslash and quote, fold newlines, drop the control bytes that break the object.
esc(){ printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
       | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
       | awk 'BEGIN{ORS=""}{print (NR>1?"\\n":"") $0}'; }

input=$(cat 2>/dev/null || true)
d="${CLAUDE_PROJECT_DIR:-$PWD}"

# Opt-in by construction: no .goal directory, no opinion. A repo that never ran /goal must not
# acquire a Stop gate it did not ask for.
[ -d "$d/.goal" ] || exit 0

GREP="grep"
[ -x /usr/bin/grep ] && GREP=/usr/bin/grep

goal_is_closed() { # <file>
  "$GREP" -qiE '^(Created:.*)?Status:.*\*\*?(complete|closed|abandoned)' "$1"
}

# Scope by heading. `in_r` latches on at "## Rubric" and off at the next "## " of any kind, so
# adding a section after the rubric cannot silently widen what this gate blocks on.
rubric_section() { # <file>
  awk '
    /^##[[:space:]]/ { in_r = ($0 ~ /^##[[:space:]]+Rubric/) ? 1 : 0; next }
    in_r { print }
  ' "$1"
}

pending_items() { # <file> -- blocking pending items only
  goal_is_closed "$1" && return 0
  rubric_section "$1" | "$GREP" -E '^- \[ \]' \
    | "$GREP" -viE '\(needs:[[:space:]]*(user|human)\)|needs user action'
}

deferred_items() { # <file> -- pending, but routed to a human
  goal_is_closed "$1" && return 0
  rubric_section "$1" | "$GREP" -E '^- \[ \]' \
    | "$GREP" -iE '\(needs:[[:space:]]*(user|human)\)|needs user action'
}

pending=""
deferred=""
open_goals=0
for g in "$d"/.goal/*/goal.md; do
  [ -f "$g" ] || continue
  p=$(pending_items "$g")
  q=$(deferred_items "$g")
  rel=${g#"$d"/}
  if [ -n "$p" ]; then
    open_goals=$((open_goals + 1))
    pending="$pending
$rel:
$p"
  fi
  [ -n "$q" ] && deferred="$deferred
$rel: $(printf '%s' "$q" | "$GREP" -c .) item(s) awaiting you"
done

[ -n "$pending" ] || exit 0

# Per-session attempt counter. mkdir IS the counter: it is atomic on every POSIX filesystem, so
# concurrent Stops from parallel sub-agents each claim a distinct number. This avoids the
# unlocked read-modify-write that verify-gate.sh had to grow a lock around -- ten racing readers
# there all saw the same count, so the cap never engaged.
sid=""
[ -n "$JQ" ] && sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
[ -n "$sid" ] || sid="pid$PPID"
cnt_base="${TMPDIR:-/tmp}/vstack-goal-gate-$sid"
CAP=3
attempt=0
i=1
while [ "$i" -le "$CAP" ]; do
  if mkdir "$cnt_base.$i" 2>/dev/null; then attempt=$i; break; fi
  i=$((i + 1))
done

if [ "$attempt" -eq 0 ]; then
  m="goal gate: $open_goals goal(s) still have unchecked rubric items after $CAP blocks this session, so this gate is standing down rather than looping. Still open:$pending"
  if [ -n "$JQ" ]; then "$JQ" -cn --arg m "$m" '{systemMessage:$m}'
  else printf '{"systemMessage":"%s"}\n' "$(esc "$m")"; fi
  exit 0
fi

reason="A recorded goal is not finished (attempt $attempt of $CAP). Unchecked rubric items:$pending

Work the next unchecked item, then tick its box. If an item needs the operator rather than you,
tag it '(needs: user)' and it will stop blocking. If the goal is done, set its Status to complete."
[ -n "$deferred" ] && reason="$reason

Not blocking, awaiting the operator:$deferred"

if [ -n "$JQ" ]; then "$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
else printf '{"decision":"block","reason":"%s"}\n' "$(esc "$reason")"; fi
exit 0
