#!/usr/bin/env bash
# compat-canary.sh — repro for P0 item 1: nothing in claude/hooks/*.sh notices when Claude Code
# sends a hook payload or reports a CLI version this bundle has never seen. Every hook that reads
# the payload uses `// empty` / `// "SessionStart"` jq fallbacks with no `else` — see
# inject-session-context.sh:36 and skill-mandate.sh:38 (`[ -n "$tr_" ] && [ -f "$tr_" ] || exit 0`).
# A renamed field or a new hook_event_name is indistinguishable, from the outside, from nothing
# happening: exit 0, no output. That is docs/checks-that-inherit-their-answer.md's pattern
# ("silence read as success") in a new place: absence of a recognised shape reads as "nothing to
# do" instead of "I could not tell".
#
# This is a FAILING regression test on purpose: claude/hooks/compat-canary.sh does not exist yet,
# so every invocation below fails to even run. It is written to exit 0 once that script exists and
# draws the KNOWN/UNKNOWN line correctly in both directions:
#   - a recognised version + a recognised payload shape -> KNOWN (exit 0), silent.
#   - an invented version, OR a payload missing/renaming a field the current event needs -> UNKNOWN
#     (exit 2), and the reason names which field or which version it could not read.
#
# Fully sandboxed: HOME/TMPDIR/CLAUDE_CONFIG_DIR live under one mktemp -d. Version is supplied via
# VSTACK_CLAUDE_VERSION_OVERRIDE so this test needs no real `claude` binary and cannot be confused
# by whichever CLI happens to be on the machine running it.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CANARY="$REPO/claude/hooks/compat-canary.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/compat-canary-repro.XXXXXX")
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM HUP

export HOME="$SANDBOX/home"
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$HOME" "$TMPDIR"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"

REAL_DELEG="$HOME/.claude/vstack-delegation-log.jsonl"  # sandbox path, never the real one

PASS=0
FAIL=0
ok(){ printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

if [ ! -x "$CANARY" ]; then
  bad "claude/hooks/compat-canary.sh does not exist yet (or is not executable) -- this is the red state"
  echo
  echo "$PASS passed, $FAIL failed"
  exit 1
fi

fire(){ # <payload-json> <version-override>
  VSTACK_CLAUDE_VERSION_OVERRIDE="$2" "$CANARY" <<<"$1"
}

echo "=== direction 1: a recognised version + a recognised payload -> KNOWN, silent, exit 0 ==="
out=$(fire '{"hook_event_name":"SessionStart","session_id":"abc123"}' "2.1.243"); rc=$?
echo "  rc=$rc out=$out"
[ "$rc" -eq 0 ] && ok "known SessionStart payload on the reference version (2.1.243) exits 0" \
  || bad "known-good input did not exit 0 (got $rc) -- canary is not a control, it just always fires"
case "$out" in *UNKNOWN*) bad "known-good input printed UNKNOWN: $out" ;; *) ok "known-good input stayed silent (no UNKNOWN text)" ;; esac

out=$(fire '{"hook_event_name":"Stop","session_id":"abc123","transcript_path":"/tmp/does-not-need-to-exist"}' "2.1.243"); rc=$?
[ "$rc" -eq 0 ] && ok "known Stop payload exits 0" || bad "known Stop payload did not exit 0 (got $rc): $out"

echo
echo "=== direction 2a: an invented version -> UNKNOWN, names the version, exit 2 ==="
out=$(fire '{"hook_event_name":"SessionStart","session_id":"abc123"}' "99.99.99"); rc=$?
echo "  rc=$rc out=$out"
[ "$rc" -eq 2 ] && ok "invented version 99.99.99 exits 2 (UNKNOWN)" \
  || bad "invented version did not report UNKNOWN (rc=$rc) -- an unrecognised version is passing as green"
case "$out" in *"99.99.99"*) ok "reason names the unrecognised version" ;; *) bad "UNKNOWN reason did not name the version: $out" ;; esac

echo
echo "=== direction 2b: a payload missing the field its event needs -> UNKNOWN, names the field ==="
out=$(fire '{"hook_event_name":"Stop","session_id":"abc123"}' "2.1.243"); rc=$?
echo "  rc=$rc out=$out (Stop payload with no transcript_path)"
[ "$rc" -eq 2 ] && ok "Stop payload missing transcript_path exits 2 (UNKNOWN)" \
  || bad "Stop payload missing a required field did not report UNKNOWN (rc=$rc) -- a renamed/dropped field passes as green"
case "$out" in *transcript_path*) ok "reason names transcript_path" ;; *) bad "UNKNOWN reason did not name the missing field: $out" ;; esac

echo
echo "=== direction 2c: a hook_event_name this bundle has never seen -> UNKNOWN, names it ==="
out=$(fire '{"hook_event_name":"FutureEventKind","session_id":"abc123"}' "2.1.243"); rc=$?
echo "  rc=$rc out=$out"
[ "$rc" -eq 2 ] && ok "unrecognised hook_event_name exits 2 (UNKNOWN)" \
  || bad "unrecognised hook_event_name did not report UNKNOWN (rc=$rc)"
case "$out" in *FutureEventKind*) ok "reason names the unrecognised event" ;; *) bad "UNKNOWN reason did not name the event: $out" ;; esac

echo
echo "=== direction 2d: unparseable payload -> UNKNOWN, does not crash ==="
out=$(fire 'not json at all' "2.1.243"); rc=$?
echo "  rc=$rc out=$out"
[ "$rc" -eq 2 ] && ok "unparseable payload exits 2 (UNKNOWN), not a crash and not a silent pass" \
  || bad "unparseable payload did not report UNKNOWN (rc=$rc)"

echo
echo "$PASS passed, $FAIL failed"
[ -f "$REAL_DELEG" ] && bad "sandbox wrote to a path shaped like the real delegation log (should be empty/absent here)"
[ "$FAIL" -eq 0 ]

echo
echo "=== direction 3: wired into inject-session-context.sh, the canary must not grow the hook's"
echo "    own stdout byte count in EITHER direction -- check 18 (.claude/verify.sh) measures the"
echo "    SessionStart hook's total stdout via wc -c on the same probe below, and the real baseline"
echo "    sits 4 bytes under its 4096-byte cap. A visible-but-in-band signal (systemMessage sharing"
echo "    the same JSON line as additionalContext) would push the gate red on exactly the occasion"
echo "    the canary is doing its job: a real version bump. ==="
HOOK="$REPO/claude/hooks/inject-session-context.sh"
if [ -x "$HOOK" ]; then
  known_out=$(printf '{"hook_event_name":"SessionStart","session_id":"s1"}' | bash "$HOOK" 2>/tmp/compat-canary-repro-known.err)
  unknown_out=$(printf '{"hook_event_name":"SessionStart","session_id":"s1"}' | VSTACK_CLAUDE_VERSION_OVERRIDE=8.8.8 bash "$HOOK" 2>/tmp/compat-canary-repro-unknown.err)
  if [ "$known_out" = "$unknown_out" ]; then
    ok "SessionStart hook stdout is byte-identical whether the canary is KNOWN or UNKNOWN"
  else
    bad "SessionStart hook stdout DIFFERS between KNOWN and UNKNOWN -- the canary is growing the byte-capped output"
  fi
  case "$(cat /tmp/compat-canary-repro-unknown.err 2>/dev/null)" in
    *UNKNOWN*8.8.8*) ok "the UNKNOWN case is still visible somewhere (hook stderr) and names the version" ;;
    *) bad "UNKNOWN case produced no visible signal on stderr" ;;
  esac
  rm -f /tmp/compat-canary-repro-known.err /tmp/compat-canary-repro-unknown.err
else
  bad "claude/hooks/inject-session-context.sh missing or not executable"
fi

echo
echo "$PASS passed, $FAIL failed (cumulative)"
[ -f "$REAL_DELEG" ] && bad "sandbox wrote to a path shaped like the real delegation log (should be empty/absent here)"
[ "$FAIL" -eq 0 ]
