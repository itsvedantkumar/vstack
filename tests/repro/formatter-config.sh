#!/usr/bin/env bash
# tests/repro/formatter-config.sh
#
# format.sh is a PostToolUse hook on Edit|Write|MultiEdit: it fires on ordinary editing, not
# only at Stop, and it never goes through verify-gate.sh's trust check. Its own comments already
# flagged the residual hole: a static (JSON/YAML/TOML) prettier config's "plugins" entry names a
# local .js file, and prettier require()s it -- executing arbitrary code -- the instant an agent
# edits any covered file in a repo carrying that config, whether or not the operator has ever
# run `vstack trust` there.
#
# This builds two throwaway repos with an identical malicious .prettierrc.json (a "plugins"
# entry pointing at a script that writes a marker file the instant it is require()d, before
# prettier ever calls into it as a plugin): one trusted via the real `vstack trust`, one never
# trusted. It fires format.sh against each, plus a positive control (baseline formatting with no
# plugins, in neither repo) to prove the harness exercises the hook at all rather than passing
# by accident. It then re-runs the untrusted attack against the pre-fix committed blob of
# format.sh (via `git show HEAD`) in a scratch copy, to prove this test is not a no-op: the
# reverted hook must let the attack through, or nothing here is measuring anything.
#
# Exit 0 -- hole closed: untrusted repo's plugin never ran, trusted repo's plugin still does,
#           baseline formatting still works, and the reverted copy demonstrably lets it through.
# Exit 1 -- hole open, or the harness itself is broken.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
HOOK="$REPO_ROOT/claude/hooks/format.sh"
VSTACK_BIN="$REPO_ROOT/bin/vstack"

FAIL=0
note(){ printf '%s\n' "$1"; }
ok(){   printf 'ok    %s\n' "$1"; }
bad(){  printf 'FAIL  %s\n' "$1"; FAIL=1; }

[ -x "$HOOK" ] || { echo "FAIL  $HOOK missing or not executable"; exit 1; }
[ -x "$VSTACK_BIN" ] || { echo "FAIL  $VSTACK_BIN missing or not executable"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "skip  npm not installed on this host; cannot install a real prettier to exercise the plugin loader"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "skip  git not installed; cannot fetch the pre-fix blob for the no-op proof"; exit 0; }

# Own sandbox variable, never $HOME itself -- guard-destructive.sh blocks rm -rf "$HOME"-shaped
# commands even with HOME reassigned, and everything below cleans up its own tree, not HOME.
FMT_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/vstack-formatter-config.XXXXXX")
FMT_SANDBOX=$(cd "$FMT_SANDBOX" && pwd)  # normalize away a doubled slash from a trailing-slash TMPDIR
cleanup(){ rm -rf "$FMT_SANDBOX"; }
trap cleanup EXIT

# Real trust store: read-only, before/after line counts recorded, never written to.
REAL_TS="$HOME/.config/agents/verify-trust"
real_ts_before=$( [ -f "$REAL_TS" ] && wc -l < "$REAL_TS" | tr -d ' ' || echo 0 )

MARKER_DIR="$FMT_SANDBOX/proof"
VENDOR="$FMT_SANDBOX/vendor"
mkdir -p "$MARKER_DIR" "$VENDOR"

note "-- installing prettier@3.9.6 once, shared read-only across both repos --"
if ! npm install prettier@3.9.6 --no-save --prefix "$VENDOR" >"$FMT_SANDBOX/npm-install.log" 2>&1; then
  echo "skip  npm install prettier failed (offline?); see $FMT_SANDBOX/npm-install.log before cleanup races it"
  cat "$FMT_SANDBOX/npm-install.log"
  exit 0
fi
[ -x "$VENDOR/node_modules/.bin/prettier" ] || { echo "skip  prettier install did not produce an executable; cannot exercise the plugin loader"; exit 0; }

make_repo() { # $1: repo dir, $2: marker file name written by the plugin on load
  d="$1"; marker="$2"
  mkdir -p "$d/.claude"
  ln -s "$VENDOR/node_modules" "$d/node_modules"
  cat > "$d/evil-plugin.js" <<EOF
const fs = require('fs');
fs.writeFileSync('$MARKER_DIR/$marker', 'executed at ' + new Date().toISOString());
module.exports = { languages: [], parsers: {}, printers: {} };
EOF
  cat > "$d/.prettierrc.json" <<'EOF'
{ "plugins": ["./evil-plugin.js"], "semi": false }
EOF
  printf 'const x = 1;\n' > "$d/target.js"
  cat > "$d/.claude/verify.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$d/.claude/verify.sh"
}

run_hook() { # $1: hook script, $2: repo dir, $3: HOME to use
  f="$2/target.js"
  echo '{"tool_input":{"file_path":"'"$f"'"}}' | env HOME="$3" CLAUDE_PROJECT_DIR="$2" "$1" >/dev/null 2>&1
}

# --- repo A: trusted via the real `vstack trust` -------------------------------------------
REPO_TRUSTED="$FMT_SANDBOX/trusted-repo"
FAKE_HOME_TRUSTED="$FMT_SANDBOX/home-trusted"
mkdir -p "$FAKE_HOME_TRUSTED"
make_repo "$REPO_TRUSTED" "marker-trusted"
HOME="$FAKE_HOME_TRUSTED" "$VSTACK_BIN" trust "$REPO_TRUSTED" --yes >"$FMT_SANDBOX/trust.out" 2>&1
trust_rc=$?
if [ "$trust_rc" -ne 0 ] || ! grep -qF "$REPO_TRUSTED/.claude/verify.sh" "$FAKE_HOME_TRUSTED/.config/agents/verify-trust" 2>/dev/null; then
  bad "vstack trust did not record $REPO_TRUSTED/.claude/verify.sh (rc=$trust_rc)"
  cat "$FMT_SANDBOX/trust.out"
  exit 1
fi

# --- repo B: never trusted -------------------------------------------------------------------
REPO_UNTRUSTED="$FMT_SANDBOX/untrusted-repo"
FAKE_HOME_UNTRUSTED="$FMT_SANDBOX/home-untrusted"
mkdir -p "$FAKE_HOME_UNTRUSTED/.config/agents"
: > "$FAKE_HOME_UNTRUSTED/.config/agents/verify-trust"  # exists, empty: never trusted, not merely absent
make_repo "$REPO_UNTRUSTED" "marker-untrusted-attack"

# --- positive control: trusted repo's plugin must still load ---------------------------------
run_hook "$HOOK" "$REPO_TRUSTED" "$FAKE_HOME_TRUSTED"
if [ -f "$MARKER_DIR/marker-trusted" ] && ! grep -q '^const x = 1;$' "$REPO_TRUSTED/target.js"; then
  ok "positive control: trusted repo's prettier plugin still loads and prettier still formats (semi:false honored)"
else
  bad "positive control failed: trusted repo did not format via the plugin-bearing config -- fix is not merely narrowing, it broke the ordinary trusted case"
  exit 1
fi

# --- the claimed gap: untrusted repo, identical malicious config -----------------------------
run_hook "$HOOK" "$REPO_UNTRUSTED" "$FAKE_HOME_UNTRUSTED"
if [ -f "$MARKER_DIR/marker-untrusted-attack" ]; then
  bad "HOLE OPEN: untrusted repo's .prettierrc.json plugins entry executed via format.sh with no trust check at all"
else
  ok "hole closed: untrusted repo's plugin-bearing config did not execute"
fi

# --- no-op proof: same attack against the pre-fix committed blob of format.sh ----------------
PREFIX_HOOK="$FMT_SANDBOX/format-prefix.sh"
if ! git -C "$REPO_ROOT" show HEAD:claude/hooks/format.sh > "$PREFIX_HOOK" 2>/dev/null; then
  bad "could not read HEAD:claude/hooks/format.sh to build the no-op proof"
  exit 1
fi
chmod +x "$PREFIX_HOOK"
REPO_REVERT="$FMT_SANDBOX/revert-repo"
make_repo "$REPO_REVERT" "marker-revert-proof"
run_hook "$PREFIX_HOOK" "$REPO_REVERT" "$FAKE_HOME_UNTRUSTED"
if [ -f "$MARKER_DIR/marker-revert-proof" ]; then
  ok "no-op proof: the pre-fix committed format.sh does let this exact attack through -- this test is not vacuous"
else
  bad "no-op proof failed: reverting to HEAD's format.sh did NOT reproduce the attack -- either HEAD already closed this, or this test cannot detect the hole it claims to"
fi

real_ts_after=$( [ -f "$REAL_TS" ] && wc -l < "$REAL_TS" | tr -d ' ' || echo 0 )
note "real trust store line count: before=$real_ts_before after=$real_ts_after"
if [ "$real_ts_before" != "$real_ts_after" ]; then
  bad "the real trust store changed size -- this test must never write to $REAL_TS"
fi

[ "$FAIL" -eq 0 ] && echo "FORMATTER PLUGIN LOADING: CLOSED" || echo "FORMATTER PLUGIN LOADING: OPEN"
exit "$FAIL"
