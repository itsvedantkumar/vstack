#!/usr/bin/env bash
# ui-gate.sh — an executable floor for interface work.
#
# A floor, not taste. Every rule here has a fixed threshold, a pinned tool where it needs one, and
# a mutation in mutations.sh that proves it can fail. Nothing in here judges whether a design is
# good; it judges whether a set of known conditions hold. Green means those conditions held. It is
# not evidence that the interface is worth using, and it must never be quoted as if it were.
#
# The contract, from docs/provenance/research-v1.7.0.md:
#   - print declared, ran, passed, failed and skipped
#   - fail unless ran + skipped == declared
#   - every skip carries a rule ID and a reason
#
# That accounting is the point. A rule that throws mid-body, or is wrapped in a conditional with
# no else, reports nothing at all -- and a gate that cannot tell "passed" from "never ran" is the
# defect this whole repository exists to catch.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# Read by the rule files sourced below, not in this file.
# shellcheck disable=SC2034  # consumed by ui-gate/rules/*.sh after sourcing
TARGET="${1:-$PWD}"
DECLARED=0; RAN=0; PASSED=0; FAILED=0; SKIPPED=0
FAILURES=""

declare_rule() { DECLARED=$((DECLARED + 1)); }
pass() { RAN=$((RAN+1)); PASSED=$((PASSED+1)); printf 'ok    %-12s %s\n' "$1" "$2"; }
fail() { RAN=$((RAN+1)); FAILED=$((FAILED+1)); printf 'FAIL  %-12s %s\n' "$1" "$2"
         FAILURES="$FAILURES\n  $1: $2"; }
skip() { SKIPPED=$((SKIPPED+1)); printf 'skip  %-12s %s\n' "$1" "$2"; }

# Every blocking rule, declared up front so the accounting has something to check against.
for r in TOK-RAW-COLOR TOK-ARBITRARY TOK-TYPE-SCALE \
         A11Y-AXE A11Y-KEYBOARD COV-STATES COV-VIEWPORT VIS-SNAPSHOT PERF-LAB; do
  declare_rule "$r"
done

for f in ui-gate/rules/*.sh; do
  [ -f "$f" ] || continue
  # shellcheck source=/dev/null
  . "$f"
done

echo
printf 'rules: %d declared, %d ran, %d passed, %d failed, %d skipped\n' \
  "$DECLARED" "$RAN" "$PASSED" "$FAILED" "$SKIPPED"

if [ "$((RAN + SKIPPED))" -ne "$DECLARED" ]; then
  printf 'FAIL  accounting   %d declared rule(s) reported nothing\n' "$((DECLARED - RAN - SKIPPED))"
  echo "UI GATE FAILED"
  exit 1
fi
if [ "$FAILED" -ne 0 ]; then
  printf 'failures:%b\n' "$FAILURES"
  echo "UI GATE FAILED"
  exit 1
fi
echo "UI GATE OK (a floor: known conditions held, which is not a claim about quality)"
