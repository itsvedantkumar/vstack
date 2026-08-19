#!/usr/bin/env bash
# verify.sh — the proof that this repo works. Replace the placeholder below with real checks.
#
# Two things run this. The verify-gate.sh Stop hook runs it before an agent may claim the work
# is done, and a non-zero exit blocks that claim and hands the output back as the reason.
# Conductor's verify button runs it too.
#
# The Stop hook only runs scripts you have explicitly trusted, so this file does nothing until
# you run `vstack trust` in this repo. Trust is keyed by content hash: edit this file and it
# needs trusting again.
#
# Write checks that would actually fail. A gate that cannot go red is worse than no gate,
# because it reads as proof.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAIL=0
ok(){   printf 'ok    %s\n' "$1"; }
bad(){  printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; FAIL=1; }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; }

# --- 1. whatever this repo already knows how to check -----------------------------------------
# A starting point, not a finish line: it runs the project's own scripts if they exist. Real
# checks assert the behaviour that matters — that the endpoint answers, that the CLI prints the
# right thing, that the migration is reversible.
ran=0
if [ -f package.json ] && command -v npm >/dev/null; then
  for s in typecheck lint test; do
    node -e "process.exit(require('./package.json').scripts?.['$s']?0:1)" 2>/dev/null || continue
    ran=1
    out=$(npm run --silent "$s" 2>&1) && ok "npm run $s" || bad "npm run $s" "$(printf '%s' "$out" | tail -20)"
  done
fi
if [ -f pyproject.toml ] && command -v uv >/dev/null; then
  ran=1
  out=$(uv run pytest -q 2>&1) && ok "pytest" || bad "pytest" "$(printf '%s' "$out" | tail -20)"
fi
if [ -f Cargo.toml ] && command -v cargo >/dev/null; then
  ran=1
  out=$(cargo test --quiet 2>&1) && ok "cargo test" || bad "cargo test" "$(printf '%s' "$out" | tail -20)"
fi

if [ "$ran" = 0 ]; then
  skip "project checks" "nothing detected — replace this file with checks for what this repo does"
fi

echo
[ "$FAIL" -eq 0 ] && echo "VERIFIED" || echo "VERIFICATION FAILED"
exit "$FAIL"
