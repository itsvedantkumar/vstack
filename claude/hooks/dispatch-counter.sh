#!/usr/bin/env bash
# PostToolUse (matcher: Agent|Task): increments a per-session dispatch counter that
# claude/statusline.sh reads to render "RICK ·N▸". This is the WRITE side of that contract.
# Before this hook existed there was a reader with no writer -- claude/statusline.sh was built
# and verified against a hand-created fixture file, so its own test suite passed while the
# runtime path that was supposed to produce that file did not exist. Same defect shape this
# repo's own gates exist to catch elsewhere (a check that passes without measuring); the fix
# here is the same as everywhere else in this file's neighbours: build the missing half and
# prove both halves together, not each in isolation.
#
# Contract, fixed by the reader and matched here exactly -- see claude/statusline.sh's own
# "Lead and delegation" comment for the read side:
#   path   : ${TMPDIR:-/tmp}/vstack-dispatch-count-<session_id>
#   value  : bare integer, single line, no trailing newline (printf, not echo)
#   create : on first dispatch, not at SessionStart. A fresh session must have NO counter file at
#            all, not a "0" one -- that absence is what lets the reader render nothing instead of
#            "·0▸" for a session that hasn't delegated yet. Nothing in this repo creates this
#            file except this hook, and this hook only ever runs on an actual Agent/Task
#            dispatch, so the distinction holds by construction: no dispatch, no invocation, no
#            file.
#
# Cost: O(1) by design, never touches the transcript -- read one small file, add 1, write it
# back. This is the same shape as skill-mandate.sh's $cnt_file, which is also why the lock below
# is that file's lock ported verbatim rather than re-derived (see next paragraph). Measured
# against a real dispatch on this machine, n=30: mean/p50/p95 reported in the commit/handback
# that shipped this rather than duplicated here, where a number would drift stale next to the
# code that produces it.
#
# Concurrency: parallel subagents finish at once, which makes an unlocked read-modify-write here
# the identical race skill-mandate.sh already solved for $cnt_file -- ten racing invocations all
# read the same starting count, each computes its own +1, and the last write wins, undercounting
# every dispatch that raced another. `mkdir` is atomic on every POSIX filesystem (exactly one
# racing caller sees it succeed), needs no GNU flock and no coreutils on stock macOS, and is the
# same fix already proven in skill-mandate.sh and verify-gate.sh -- ported here, not reinvented.
# A lock older than 30s is assumed abandoned by a killed sibling rather than honored forever, so
# a crash can't wedge the counter shut for the rest of the session.
#
# Escape hatch, same shape as every other gate/log in this repo: VSTACK_NO_DISPATCH_COUNT=1
# disables this entirely. A counter nobody can turn off gets deleted by the first person it
# inconveniences.
set -uo pipefail

[ "${VSTACK_NO_DISPATCH_COUNT:-0}" = "1" ] && exit 0

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi
# Without jq there is no reliable way to read tool_name or session_id. Say nothing rather than
# guess: an undercounted statusline is a worse failure than a silent one, same reasoning
# skill-mandate.sh applies to its own jq-missing case.
[ -n "$JQ" ] || exit 0

input=$(cat 2>/dev/null || true)

# Defense in depth: the settings.json matcher is what actually restricts which PostToolUse
# events reach this script, but a hook that trusts its own wiring to be the only thing standing
# between it and a miscount is one config edit away from silently counting Writes as dispatches.
tool_name=$(printf '%s' "$input" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
case "$tool_name" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
[ -n "$sid" ] || sid="pid$PPID"

cnt_file="${TMPDIR:-/tmp}/vstack-dispatch-count-$sid"
lock_dir="$cnt_file.lock"

# Lock pattern ported verbatim from claude/hooks/skill-mandate.sh's $cnt_file lock (itself
# ported from verify-gate.sh) -- see that file's own comment for the full reasoning. Not
# re-derived here on purpose: two copies of the same fix are two chances for them to drift.
lock_acquired=0
i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    lm=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$lm" -gt 0 ] && [ $((now - lm)) -ge 30 ]; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    i=0
  fi
  sleep 0.02 2>/dev/null || sleep 1
done
lock_acquired=1
trap '[ "$lock_acquired" = 1 ] && rmdir "$lock_dir" 2>/dev/null' EXIT

cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
cnt=$((cnt + 1))
printf '%s' "$cnt" > "$cnt_file" 2>/dev/null

# Hook contract: JSON-on-stdout-or-nothing, same as every other hook in this directory. This one
# has nothing to tell the model -- it is pure plumbing for the statusline -- so it says nothing.
exit 0
