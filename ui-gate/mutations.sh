#!/usr/bin/env bash
# mutations.sh — proof that each ui-gate rule can fail.
#
# A rule nobody has watched fail is indistinguishable from a rule that always passes, and this
# repository has shipped five of those. The contract in research-v1.7.0.md requires every blocking
# rule to map to at least one mutation, applied one at a time, producing the named failure. This
# script fails if any blocking rule has no mutation, which is what stops a rule being added
# without one.
#
# Skipped rules are exempt and listed, because a rule that cannot run cannot be shown to fail.
# That exemption is the dangerous one: it is how a family gets declared, skipped, and quietly
# never implemented. The count is printed so it stays visible.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
GATE=ui-gate/ui-gate.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PASSED=0; FAILED=0; EXEMPT=0

clean_fixture() {
  rm -rf "$W/app"; mkdir -p "$W/app/src"
  cat > "$W/app/src/Card.tsx" <<'F'
export const Card = () => (
  <div className="mt-4 p-4 text-fg-muted">
    <button type="button">Save</button>
  </div>
);
F
  printf '.a{font-size: 16px;}\n' > "$W/app/src/a.css"
}

# rule id -> the single edit that must make that rule, by name, go red
mutate() { case "$1" in
  TOK-RAW-COLOR)  sed -i.t 's/text-fg-muted/text-fg-muted" style={{ color: "#3b82f6" }}/' "$W/app/src/Card.tsx" && rm -f "$W/app/src/Card.tsx.t" ;;
  TOK-ARBITRARY)  sed -i.t 's/mt-4/mt-[13px]/' "$W/app/src/Card.tsx" && rm -f "$W/app/src/Card.tsx.t" ;;
  TOK-TYPE-SCALE) printf '.b{font-size: 13px;}\n' >> "$W/app/src/a.css" ;;
  *) return 1 ;;
esac }

clean_fixture
base=$("$GATE" "$W/app" 2>&1)
if ! printf '%s' "$base" | grep -q 'UI GATE OK'; then
  printf 'FAIL  the clean fixture does not pass; nothing below would be evidence\n%s\n' "$base"
  exit 1
fi
printf 'ok    clean fixture passes at baseline\n'

# The other direction, and the one that was missing. A gate is only evidence if it can withhold
# its verdict, and this one could not: against a directory with no interface files in it, all
# nine rules skipped, the accounting was satisfied at RAN=0, and it printed UI GATE OK and
# exited 0. Every mutation below would have been just as green on an empty directory.
empty=$(mktemp -d "$W/empty.XXXXXX")
nr=$("$GATE" "$empty" 2>&1)
if grep -q 'UI GATE OK' <<<"$nr"; then
  printf 'FAIL  the gate reports OK over a target with no UI files; nothing below is evidence\n%s\n' "$nr"
  exit 1
fi
printf 'ok    gate withholds its verdict when no rule ran\n\n'

# Every declared rule, read out of the gate itself so the two cannot drift apart.
RULES=$(sed -n '/^for r in /,/^done$/p' "$GATE" | tr ' \\;\n' '\n' | grep -E '^[A-Z0-9]+-[A-Z-]+$')
# Assert the list is complete. The first version split on space, backslash and newline but not the
# semicolon that ends the for-list, so PERF-LAB arrived as "PERF-LAB;", failed the pattern, and was
# dropped -- an audit that silently skipped one of the rules it exists to audit. Reconcile against
# the gate's own declared count rather than trusting the parse.
_declared=$("$GATE" "$W/app" 2>&1 | sed -n 's/^rules: \([0-9]*\) declared.*/\1/p')
_parsed=$(printf '%s\n' "$RULES" | grep -c .)
if [ "${_declared:-0}" != "$_parsed" ]; then
  printf 'FAIL  parsed %s rule(s) but the gate declares %s; the audit is incomplete\n' "$_parsed" "${_declared:-0}"
  exit 1
fi
for r in $RULES; do
  clean_fixture
  if ! mutate "$r"; then
    if printf '%s' "$base" | grep -q "^skip  $r"; then
      printf 'exempt %-14s skipped by the gate, so it cannot be shown to fail\n' "$r"
      EXEMPT=$((EXEMPT+1))
    else
      printf 'FAIL  %-14s is blocking and has no mutation\n' "$r"; FAILED=$((FAILED+1))
    fi
    continue
  fi
  out=$("$GATE" "$W/app" 2>&1)
  if printf '%s' "$out" | grep -q "^FAIL  $r"; then
    printf 'ok    %-14s falsifiable\n' "$r"; PASSED=$((PASSED+1))
  else
    printf 'FAIL  %-14s did NOT fail when broken\n' "$r"; FAILED=$((FAILED+1))
  fi
done

echo
printf '%d falsifiable, %d failed, %d exempt because the gate skips them\n' "$PASSED" "$FAILED" "$EXEMPT"
[ "$EXEMPT" -gt 0 ] && printf 'note: %d rule(s) are declared but not implemented. A skip is not a pass.\n' "$EXEMPT"
[ "$FAILED" -eq 0 ] && echo "UI GATE FALSIFIABLE" || echo "UI GATE NOT FALSIFIABLE"
[ "$FAILED" -eq 0 ]
