#!/usr/bin/env bash
# stop-gate.sh — repro for P0 defect 3: claude/hooks/verify-gate.sh caps a red gate at 3 blocks
# per session, then goes permanently silent for the rest of that session regardless of whether
# verify.sh is still failing, and the off-switch it uses (a plain file under $TMPDIR keyed on a
# session id the hook trusts blindly) is writable by the same agent the gate exists to stop.
#
# This is a FAILING regression test on purpose: it exits non-zero today, because today the gate
# fails open. It is written to exit 0 the day a red gate stays red no matter how many Stop
# attempts it sees in one session, and a later green pass is what clears it -- not persistence.
#
# Every assertion is black-box: it reads only the hook's own JSON output (decision:"block" or
# nothing), never the hook's internals, so it keeps meaning the same thing if the fix changes the
# counter's storage shape.
#
# Fully sandboxed: HOME, TMPDIR, and the "repo" verify-gate.sh runs against all live under one
# mktemp -d, torn down on exit. This hook never touches VSTACK_DELEGATION_LOG/VSTACK_REPLAY_LOG,
# but both are pointed at sandbox paths and exported anyway, and the real logs' line counts are
# printed before and after so a change would be visible immediately.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HOOK="$REPO/claude/hooks/verify-gate.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/stop-gate-repro.XXXXXX")
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM HUP

# Real logs, before: printed in the report, never written to below (this hook doesn't touch them
# regardless; the export is defensive).
REAL_DELEG="$HOME/.claude/vstack-delegation-log.jsonl"
REAL_REPLAY="$HOME/.claude/vstack-replay-log.jsonl"
before_deleg=$(wc -l < "$REAL_DELEG" 2>/dev/null | tr -d ' ')
before_replay=$(wc -l < "$REAL_REPLAY" 2>/dev/null | tr -d ' ')

export HOME="$SANDBOX/home"
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$HOME/.config/agents" "$TMPDIR"
export VSTACK_DELEGATION_LOG="$SANDBOX/deleg.jsonl"
export VSTACK_REPLAY_LOG="$SANDBOX/replay.jsonl"

PROJECT="$SANDBOX/repo"
mkdir -p "$PROJECT/.claude"
export CLAUDE_PROJECT_DIR="$PROJECT"

# verify.sh whose pass/fail is switched by a control file, so the same trusted script can be
# driven red or green across the same session without re-trusting anything mid-run.
cat > "$PROJECT/.claude/verify.sh" <<'VERIFY_EOF'
#!/usr/bin/env bash
mode=$(cat "$(dirname "$0")/verify-mode" 2>/dev/null || echo red)
if [ "$mode" = red ]; then
  echo "FAIL   deliberately red for stop-gate.sh repro"
  exit 1
fi
echo "ok     deliberately green for stop-gate.sh repro"
exit 0
VERIFY_EOF
chmod +x "$PROJECT/.claude/verify.sh"

set_mode(){ printf '%s' "$1" > "$PROJECT/.claude/verify-mode"; }
set_mode red

# Trust it exactly the way `vstack trust` records it: sha256 + two-space-joined absolute path,
# resolved by cd+pwd the same way verify-gate.sh resolves $v (line 30), so the two spellings match.
V=$(cd "$PROJECT/.claude" && pwd)/verify.sh
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$V" | cut -d' ' -f1)
else H=$(sha256sum "$V" | cut -d' ' -f1); fi
printf '%s  %s\n' "$H" "$V" > "$HOME/.config/agents/verify-trust"

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

# Fires the real hook with a real Stop payload. Reports "block" (decision:block present) or
# "silent" (anything else -- exit 0, no decision field). Never inspects the hook's internals.
fire(){ # <session_id>
  local sid="$1" out
  out=$(printf '{"session_id":"%s"}' "$sid" | "$HOOK" 2>&1)
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    printf 'block'
  else
    printf 'silent'
  fi
}

echo "=== phase 1: session A, gate stays red for 10 consecutive Stop attempts ==="
SID_A="repro-A-$$"
for i in 1 2 3 4 5 6 7 8 9 10; do
  r=$(fire "$SID_A")
  echo "  attempt $i (red): $r"
  if [ "$r" = block ]; then
    ok "attempt $i blocks while the gate is red"
  else
    bad "attempt $i went silent while verify.sh is STILL FAILING -- red gate stopped blocking (fail-open latch)"
  fi
done

echo
echo "=== phase 2: session B is an independent counter (per-session, not global) ==="
SID_B="repro-B-$$"
r=$(fire "$SID_B")
echo "  attempt 1 (session B, red): $r"
[ "$r" = block ] && ok "session B starts its own count fresh" \
  || bad "session B's first-ever attempt went silent -- latch leaked across sessions"

echo
echo "=== phase 3: session C -- a green pass clears the failure state and re-arms blocking ==="
SID_C="repro-C-$$"
set_mode red
r1=$(fire "$SID_C"); echo "  attempt 1 (red):   $r1"
r2=$(fire "$SID_C"); echo "  attempt 2 (red):   $r2"
set_mode green
r3=$(fire "$SID_C"); echo "  attempt 3 (green): $r3"
[ "$r3" = silent ] && ok "a real pass does not block" || bad "a green verify.sh still blocked: $r3"
set_mode red
r4=$(fire "$SID_C"); echo "  attempt 4 (red again, after the clear): $r4"
[ "$r4" = block ] && ok "red blocks again after a green pass -- re-armed correctly" \
  || bad "red after a green pass stayed silent -- the clear did not re-arm the gate"

echo
echo "=== phase 4: session D -- does a green pass clear the state, or is silence just persistence? ==="
echo "    (the discriminator: fire red AGAIN after the green. If the gate actually evaluated the"
echo "    green pass and cleared, red must block again. If it is just latched open regardless of"
echo "    verify.sh's exit code, red stays silent too.)"
SID_D="repro-D-$$"
set_mode red
for i in 1 2 3 4 5; do
  r=$(fire "$SID_D")
  echo "  attempt $i (red): $r"
  [ "$r" = block ] && ok "attempt $i blocks while red" \
    || bad "attempt $i went silent while verify.sh is STILL FAILING"
done
set_mode green
rg=$(fire "$SID_D"); echo "  attempt 6 (green): $rg"
set_mode red
rr=$(fire "$SID_D"); echo "  attempt 7 (red again, right after the green): $rr"
if [ "$rr" = block ]; then
  ok "red blocks again after the green -- the gate re-evaluates verify.sh every time (fixed)"
else
  bad "red stayed silent even right after a green pass -- the session is latched open for good," \
      " not because verify.sh passed, but because 3 blocks happened once. A later green pass" \
      " has no effect either way: the gate never runs verify.sh again this session."
fi

echo
echo "=== phase 5: session E -- can the agent reach the off switch itself, no real failures? ==="
SID_E="repro-E-$$"
set_mode red
cnt_file_e="$TMPDIR/verify-gate-block-$SID_E"
[ -f "$cnt_file_e" ] && bad "counter file for a session that never ran already exists (test setup bug)"
# Nothing here is a secret or a privileged path: TMPDIR is the hook's own env var, the filename
# format (verify-gate-block-<session_id>) is read straight out of verify-gate.sh, and writing it
# is one shell redirect the agent's normal Bash tool already has permission to run.
echo 3 > "$cnt_file_e"
r=$(fire "$SID_E")
echo "  first-ever Stop attempt on session E, after self-writing the counter to 3: $r"
[ "$r" = block ] && ok "a self-planted counter file did not silence the gate -- no reachable bypass" \
  || bad "agent silenced the gate on its first-ever Stop call by writing one file itself, zero real failures behind it"

echo
echo "$PASS passed, $FAIL failed"
echo "real ~/.claude/vstack-delegation-log.jsonl: $before_deleg lines before this run"
echo "real ~/.claude/vstack-replay-log.jsonl:     $before_replay lines before this run"
after_deleg=$(wc -l < "$REAL_DELEG" 2>/dev/null | tr -d ' ')
after_replay=$(wc -l < "$REAL_REPLAY" 2>/dev/null | tr -d ' ')
echo "real ~/.claude/vstack-delegation-log.jsonl: $after_deleg lines after this run"
echo "real ~/.claude/vstack-replay-log.jsonl:     $after_replay lines after this run"
if [ "$before_deleg" != "$after_deleg" ] || [ "$before_replay" != "$after_replay" ]; then
  bad "real operator logs changed during this run -- sandboxing failed"
fi

[ "$FAIL" -eq 0 ]
