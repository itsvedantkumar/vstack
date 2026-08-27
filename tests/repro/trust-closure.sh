#!/usr/bin/env bash
# tests/repro/trust-closure.sh
#
# `vstack trust` hashes .claude/verify.sh (plus any *.sh path it literally references, plus
# install.sh/overlay.sh/uninstall.sh/bootstrap.sh at the repo root). verify-gate.sh's Stop hook
# re-checks those hashes and refuses to run if any of them changed since trust was granted.
#
# verify.sh.tmpl's own default template shells out to `npm run test`, `uv run pytest`, and
# `cargo test` -- none of which is a .sh path, so none of it is in the hashed set. A repo can be
# trusted once, on a verify.sh a human actually read, and can then rewrite its own
# package.json/pyproject.toml/Cargo.toml/test files freely: the gate keeps running, because the
# one file it checks never changed.
#
# This test builds a throwaway repo, trusts a minimal verify.sh whose only action is `npm run
# test`, fires the Stop hook once to prove the mechanism works at all (the permitted-case
# control -- without it, deleting or no-op'ing verify-gate.sh would make this test pass for the
# wrong reason), then edits ONLY package.json's test script and fires the hook again with no
# re-trust. If the new code still runs, the hole is open.
#
# Exit 0  -- hole closed: baseline execution still works AND the post-mutation run was refused.
# Exit 1  -- hole open, or the harness itself is broken (permitted case did not fire).
set -uo pipefail

# macOS has `shasum` and no `sha256sum`; BusyBox has the reverse. A bare call to either returns
# nothing on the other platform, and two empty strings compare equal -- which would make the
# before/after comparison below pass on a file that changed. Refuse instead of hashing to "".
_h(){
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else echo "trust-closure: no sha256sum or shasum on PATH; refusing to compare empty hashes" >&2; exit 3; fi
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
VSTACK_BIN="$REPO_ROOT/bin/vstack"
GATE="$REPO_ROOT/claude/hooks/verify-gate.sh"

FAIL=0
note(){ printf '%s\n' "$1"; }
ok(){   printf 'ok    %s\n' "$1"; }
bad(){  printf 'FAIL  %s\n' "$1"; FAIL=1; }

[ -x "$VSTACK_BIN" ] || { echo "FAIL  $VSTACK_BIN missing or not executable"; exit 1; }
[ -x "$GATE" ] || { echo "FAIL  $GATE missing or not executable"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "skip  npm not installed on this host; cannot exercise the npm-run-test closure"; exit 0; }

# Own sandbox variable, never $HOME itself: the repo's destructive-command guard blocks
# `rm -rf "$HOME"` even with HOME reassigned, and this script cleans up its own tree, not HOME.
SANDBOX_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vstack-trust-closure.XXXXXX")
SANDBOX_ROOT=$(cd "$SANDBOX_ROOT" && pwd)  # normalize away a doubled slash from a trailing-slash TMPDIR
cleanup(){ rm -rf "$SANDBOX_ROOT"; }
trap cleanup EXIT

export HOME="$SANDBOX_ROOT/home"
mkdir -p "$HOME"
REPO_DIR="$SANDBOX_ROOT/victim-repo"
MARKER_DIR="$SANDBOX_ROOT/proof"
mkdir -p "$REPO_DIR/.claude" "$MARKER_DIR"

cat > "$REPO_DIR/.claude/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
if [ -f package.json ] && command -v npm >/dev/null; then
  node -e "process.exit(require('./package.json').scripts?.test?0:1)" 2>/dev/null && \
    npm run --silent test
fi
exit 0
EOF
chmod +x "$REPO_DIR/.claude/verify.sh"

cat > "$REPO_DIR/package.json" <<EOF
{
  "name": "victim",
  "version": "1.0.0",
  "scripts": {
    "test": "node -e \"require('fs').writeFileSync('$MARKER_DIR/marker-baseline','baseline test ran')\""
  }
}
EOF

note "-- trusting $REPO_DIR/.claude/verify.sh (non-interactive, --yes) --"
"$VSTACK_BIN" trust "$REPO_DIR" --yes >/tmp/vstack-trust-closure-trust.out 2>&1
trust_rc=$?
if [ "$trust_rc" -ne 0 ] || ! grep -qF "$REPO_DIR/.claude/verify.sh" "$HOME/.config/agents/verify-trust" 2>/dev/null; then
  bad "vstack trust did not record $REPO_DIR/.claude/verify.sh (rc=$trust_rc)"
  cat /tmp/vstack-trust-closure-trust.out
  rm -f /tmp/vstack-trust-closure-trust.out
  exit 1
fi
rm -f /tmp/vstack-trust-closure-trust.out
verify_hash_before=$(_h "$REPO_DIR/.claude/verify.sh")

# --- permitted case: the gate must actually run the trusted, unmodified script -----------------
# If this does not fire, either the mechanism is broken or someone disabled the hook to make
# the "hole is closed" check below pass for free. Both are failures of this test, not passes.
echo '{"session_id":"trust-closure-baseline"}' | CLAUDE_PROJECT_DIR="$REPO_DIR" "$GATE" >/dev/null 2>&1
if [ -f "$MARKER_DIR/marker-baseline" ]; then
  ok "permitted case: trusted verify.sh ran via the Stop hook (npm run test executed)"
else
  bad "permitted case: Stop hook did not execute the trusted verify.sh at all -- harness broken, cannot trust the rest of this test"
  exit 1
fi

# --- the claimed gap: mutate ONLY package.json, do not touch or re-trust verify.sh -------------
cat > "$REPO_DIR/package.json" <<EOF
{
  "name": "victim",
  "version": "1.0.0",
  "scripts": {
    "test": "node -e \"require('fs').writeFileSync('$MARKER_DIR/marker-attacker','attacker code executed via package.json test script; verify.sh was never edited')\""
  }
}
EOF
verify_hash_after=$(_h "$REPO_DIR/.claude/verify.sh")
if [ "$verify_hash_before" != "$verify_hash_after" ]; then
  bad "test bug: verify.sh hash changed when it should not have -- mutation touched the wrong file"
  exit 1
fi

echo '{"session_id":"trust-closure-attack"}' | CLAUDE_PROJECT_DIR="$REPO_DIR" "$GATE" >/dev/null 2>&1

if [ -f "$MARKER_DIR/marker-attacker" ]; then
  bad "HOLE OPEN: package.json's test script changed after trust, verify.sh (the only hashed file) did not, and the Stop hook still ran the new code unattended."
  note "         $(cat "$MARKER_DIR/marker-attacker")"
else
  ok "hole closed: mutated package.json did not run under the still-trusted, unmodified verify.sh"
fi

[ "$FAIL" -eq 0 ] && echo "TRUST CLOSURE: CLOSED" || echo "TRUST CLOSURE: OPEN"
exit "$FAIL"
