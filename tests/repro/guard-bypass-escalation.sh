#!/usr/bin/env bash
# guard-bypass-escalation.sh — repro for the seventh fake green: check 23/25 in .claude/verify.sh
# asserts claude/hooks/guard-destructive.sh DECIDES correctly (ask/deny/allow), never that the
# decision changes what the runtime does. Measured live, twice, in this session under
# bypassPermissions (RICK's report): `git reset --hard` gets `ask` from the guard and runs anyway,
# rc=0, no prompt. `git push --force` gets `deny` and is actually blocked. So `deny` bites and `ask`
# is decoration for any agent running in bypass mode -- which is every subagent in this setup,
# because install.sh --bypass-permissions is the shipped default (see guard-destructive.sh's own
# header).
#
# Root cause: the PreToolUse payload carries `permission_mode` (confirmed empirically against the
# live installed hook this session -- see docs/guard-enforcement-gap.md for the captured payload).
# guard-destructive.sh never reads it, so it cannot tell an ask a human will see from an ask nobody
# will ever see, and emits the same "ask" either way.
#
# This is a FAILING regression test on purpose, in two ways:
#   - git stash (bare, no pathspec) is not matched by ANY tier today -> falls through to allow.
#     Direction 1/2 below expect at least `ask`; today's guard gives `allow`.
#   - even where a rule exists (git reset --hard, git clean -fd, git add -A outside workspace,
#     git commit -a outside workspace), it stays `ask` regardless of permission_mode. Directions
#     3-6 expect `deny` when permission_mode=bypassPermissions; today's guard gives `ask`.
# Backward compatibility is asserted too (directions 7-9): when permission_mode is absent, or is
# "default"/"acceptEdits"/"plan" (session CAN prompt), decisions must stay exactly what they are
# today -- an escalation that fires when it should not is a new, different fake green.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GUARD="$REPO/claude/hooks/guard-destructive.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/guard-bypass-repro.XXXXXX")
SANDBOX=$(cd "$SANDBOX" && pwd)  # normalize away macOS's double-slash TMPDIR
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM HUP

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

# <command> <permission_mode-or-empty> <expected-decision> <label>
decide(){
  local cmd="$1" pmode="$2" cwd="${5:-$SANDBOX}"
  local payload
  if [ -n "$pmode" ]; then
    payload=$(jq -cn --arg c "$cmd" --arg pm "$pmode" '{tool_input:{command:$c},permission_mode:$pm}')
  else
    payload=$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')
  fi
  ( cd "$cwd" && printf '%s' "$payload" | bash "$GUARD" 2>/dev/null ) | jq -r '.hookSpecificOutput.permissionDecision // "NO-OUTPUT"'
}

want(){ # <label> <command> <permission_mode-or-""> <expected>
  local label="$1" cmd="$2" pmode="$3" expected="$4"
  got=$(decide "$cmd" "$pmode")
  if [ "$got" = "$expected" ]; then ok "$label"; else bad "$label -- got '$got', want '$expected' (cmd='$cmd' permission_mode='${pmode:-<absent>}')"; fi
}

echo "=== escalation set, under bypassPermissions (session cannot prompt) -> deny ==="
want "bare 'git stash' under bypass -> deny"            'git stash'                       bypassPermissions deny
want "'git stash push' (no pathspec) under bypass -> deny" 'git stash push'               bypassPermissions deny
want "'git reset --hard' under bypass -> deny"           'git reset --hard HEAD~3'         bypassPermissions deny
want "'git clean -fd' under bypass -> deny"              'git clean -fd'                   bypassPermissions deny

echo "=== not in the escalation set -> stays ask even under bypass ==="
want "DB drop under bypass stays ask (not the escalation set)" 'psql -c "DROP TABLE users"' bypassPermissions ask
want "terraform destroy under bypass stays ask (not the escalation set)" 'terraform destroy' bypassPermissions ask

echo "=== a session that CAN prompt -> escalation set stays ask, not deny ==="
want "'git reset --hard' in default mode stays ask"       'git reset --hard HEAD~3'        default           ask
want "'git reset --hard' in acceptEdits mode stays ask"    'git reset --hard HEAD~3'        acceptEdits       ask
want "'git reset --hard' in plan mode stays ask"           'git reset --hard HEAD~3'        plan              ask
want "'git stash' in default mode stays ask, not allow"    'git stash'                      default           ask

echo "=== permission_mode absent (older Claude Code, or check 23's own synthetic payloads) ==="
echo "=== -> unknown enforceability, so it must not silently escalate; stays exactly today's tier ==="
want "'git reset --hard' with no permission_mode field stays ask" 'git reset --hard HEAD~3' ""                ask
want "'git stash' with no permission_mode field is at least ask, never allow" 'git stash'   ""                ask

echo "=== git stash safe subcommands are never flagged (pop/apply/list/show are not destructive) ==="
want "'git stash pop' under bypass stays allow"   'git stash pop'  bypassPermissions allow
want "'git stash list' under bypass stays allow"  'git stash list' bypassPermissions allow

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
