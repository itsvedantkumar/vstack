#!/usr/bin/env bash
# Repro: bin/doctor's claude-mem check reports green over a plugin that cannot execute.
#
# Two independent holes, both provable offline:
#   A. Version selection. doctor takes `ls -d .../*/hooks/hooks.json | tail -1`, the
#      LEXICALLY LAST version directory. Claude Code resolves the last version that is
#      NOT marked `.orphaned_at`. When the newest version is orphaned -- which is exactly
#      what happens after a failed self-update -- doctor grades a directory that will
#      never run, and stays silent about the one that will.
#   B. Executability. doctor asserts a flag inside hooks.json and nothing else. A version
#      whose package.json is unparseable throws ERR_INVALID_PACKAGE_CONFIG on every single
#      hook invocation while doctor keeps printing the async tick.
#
# Sandboxed: HOME is a mktemp -d, never the operator's. Exits 1 while the holes are open.
set -u

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0; FAIL=0
t_ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
t_bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# --- build a plugin cache that mirrors the real failure ------------------------
# 13.15.2 is healthy and is what Claude Code resolves.
# 13.16.0 is newer, orphaned, and corrupt -- it is what `tail -1` picks.
CDIR="$SANDBOX/dot-claude"
BASE="$CDIR/plugins/cache/thedotmack/claude-mem"
for v in 13.15.2 13.16.0; do
  mkdir -p "$BASE/$v/hooks" "$BASE/$v/scripts"
done

# healthy, resolved version -- and note its flag is DELIBERATELY WRONG (sync, not async).
# doctor must report this, because this is the version that actually runs.
cat > "$BASE/13.15.2/hooks/hooks.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"x","async":false}]}]}}
JSON
printf '{"name":"claude-mem-plugin","version":"13.15.2"}\n' > "$BASE/13.15.2/package.json"

# orphaned + corrupt version -- flag is right, package.json is not parseable.
cat > "$BASE/13.16.0/hooks/hooks.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"x","async":true}]}]}}
JSON
cat > "$BASE/13.16.0/package.json" <<'JSON'
{
  "name": "claude-mem-plugin",
<<<<<<< Updated upstream
  "version": "13.16.0",
=======
  "version": "13.13.1",
>>>>>>> Stashed changes
}
JSON
: > "$BASE/13.16.0/.orphaned_at"

mkdir -p "$SANDBOX/home/.claude-mem"
HOME_S="$SANDBOX/home"

run_doctor() {
  HOME="$HOME_S" CLAUDE_CONFIG_DIR="$CDIR" VSTACK_REPO="$SRC" \
    "$SRC/bin/doctor" 2>&1 | grep -i 'claude-mem'
}

OUT="$(run_doctor)"
printf '%s\n' "$OUT" | sed 's/^/    | /'

# --- A. does doctor grade the version that will actually run? ------------------
# The resolved version (13.15.2) has async=false. A doctor that reads the resolved
# version must go red here. A doctor that reads `tail -1` sees 13.16.0's async=true
# and prints the tick.
if printf '%s' "$OUT" | grep -qi 'async.*✔\|async ✔'; then
  t_bad "A: green async tick, but the RESOLVED version 13.15.2 has async=false"
else
  t_ok  "A: doctor graded the resolved version, not the lexically-last one"
fi

# --- B. does doctor notice the plugin cannot execute? --------------------------
# Corrupt the resolved version too. Every hook invocation now throws
# ERR_INVALID_PACKAGE_CONFIG. doctor must not stay quiet about that.
cp "$BASE/13.16.0/package.json" "$BASE/13.15.2/package.json"
OUT2="$(run_doctor)"
if printf '%s' "$OUT2" | grep -qiE 'unparse|corrupt|invalid|cannot (load|run|execute)'; then
  t_ok  "B: doctor reports the unparseable package.json"
else
  t_bad "B: package.json is unparseable on the resolved version and doctor says nothing"
fi

# --- C. is 'store' a measurement or just a directory? --------------------------
# $HOME/.claude-mem exists but is empty: no database, nothing stored.
if printf '%s' "$OUT" | grep -qi 'ok.*claude-mem store'; then
  t_bad "C: 'claude-mem store' ok on an empty directory with no database in it"
else
  t_ok  "C: store check requires more than a directory existing"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
