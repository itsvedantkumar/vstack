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
# A gate that ran nothing has not agreed with you. The accounting above is satisfied at RAN=0 --
# nine declared, nine skipped, nothing left unreported -- and FAILED is 0 because nothing ran to
# fail, so both guards passed and the OK below fired over a directory with no interface in it at
# all. `./ui-gate/ui-gate.sh docs` printed "9 declared, 0 ran, 0 passed, 0 failed, 9 skipped"
# followed by "UI GATE OK" and exited 0. That is the defect named at the top of this file,
# reproduced in the summary written to catch it.
#
# The floor is RAN, not PASSED: browser rules skipping because playwright is absent is honest,
# but every rule skipping means the target has no UI, and running a UI gate over a target with
# no UI is a category error rather than a pass.
#
# exit 2 follows this file's own precedent -- the cd above spends 2 on "could not run" and 1 is
# already spoken for by "rules failed". A caller doing `ui-gate.sh . && ship` blocks either way;
# a caller that wants to tell the two apart now can.
if [ "$RAN" -eq 0 ]; then
  printf 'no rule executed: %d declared, %d skipped, nothing measured\n' "$DECLARED" "$SKIPPED"
  echo "UI GATE NOT RUN"
  exit 2
fi
echo "UI GATE OK ($PASSED of $DECLARED rules ran and held; a floor, not a claim about quality)"
