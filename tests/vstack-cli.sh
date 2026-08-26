#!/usr/bin/env bash
# vstack-cli.sh — regression tests for bin/vstack's own commands, offline and zero-model.
#
# Every case runs bin/vstack with HOME reassigned to a throwaway sandbox under mktemp -d, and
# most also copy bin/vstack itself out of this repo's git tree so `resolve_vstack_repo`'s git-
# root fallback cannot silently find the real checkout underneath a faked HOME. Nothing here
# touches the real $HOME or this repo's working tree.
#
# Usage: tests/vstack-cli.sh [case-name ...]     (default: all)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC=$(pwd)
VSTACK_BIN="$SRC/bin/vstack"

ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vstack-cli-test.XXXXXX")" && pwd)
trap 'rm -rf "$ROOT"' EXIT

PASS=0; FAIL=0; SKIP=0
ok(){   printf 'ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIP=$((SKIP+1)); }

# A standalone copy of bin/vstack, outside any git tree, so `resolve_vstack_repo`'s last-resort
# fallback (walk up from $0 to a git root carrying claude/settings.json) cannot find THIS repo
# underneath a sandboxed HOME. Cases that want the real repo pass VSTACK_DIR="$SRC" explicitly.
standalone_vstack() {
  d="$ROOT/standalone-bin-$1"
  mkdir -p "$d"
  cp "$VSTACK_BIN" "$d/vstack"
  chmod +x "$d/vstack"
  printf '%s\n' "$d/vstack"
}

MINPATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"

# --- self-test: accounting balances and the verdict is truthful, in three shapes -----------

# Case 1: a fake full-lane install where every check can run. Positive control that ran+skipped
# always equals declared and the printed verdict matches the exit code, in the shape a real
# broken-but-not-empty install actually produces (drift found -> FAIL, not a crash, not a false
# green).
case_accounting_all_ran() {
  h="$ROOT/home-all-ran"
  mkdir -p "$h/.config/agents/bin" "$h/.claude/hooks"
  cp "$SRC/bin/doctor" "$h/.config/agents/bin/doctor"; chmod +x "$h/.config/agents/bin/doctor"
  printf '{}\n' > "$h/.claude/settings.json"
  printf '#!/usr/bin/env bash\necho hi\n' > "$h/.claude/hooks/format.sh"
  chmod +x "$h/.claude/hooks/format.sh"
  out=$(env -i HOME="$h" PATH="$MINPATH" VSTACK_DIR="$SRC" "$VSTACK_BIN" self-test 2>&1)
  rc=$?
  footer=$(printf '%s\n' "$out" | grep -m1 '^self-test: ')
  case "$footer" in
    "self-test: 5 declared, 5 ran, 0 skipped") ;;
    *) bad "self-test accounting (all checks run)" "unexpected footer: '$footer' full output:
$out"; return ;;
  esac
  # This sandbox's fake install genuinely differs from the real repo (only format.sh exists),
  # so doctor --drift must find real drift and the run must genuinely fail -- a pass here would
  # mean the check that is supposed to catch drift did not.
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^SELF-TEST FAILED$'; then
    ok "self-test accounting (all checks run, genuine drift -> FAIL)"
  else
    bad "self-test accounting (all checks run)" "rc=$rc, expected 1 with SELF-TEST FAILED. output:
$out"
  fi
}

# Case 2: doctor resolves (via $REPO, real repo passed through VSTACK_DIR) but nothing else is
# installed in this sandbox -- 2 ran (doctor, drift), 3 skip (hooks/bin dirs empty, no
# settings.json). Proves partial-skip accounting balances, and that skips name their missing
# dependency rather than passing silently.
case_accounting_partial_skip() {
  h="$ROOT/home-partial-skip"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$MINPATH" VSTACK_DIR="$SRC" "$VSTACK_BIN" self-test 2>&1)
  rc=$?
  footer=$(printf '%s\n' "$out" | grep -m1 '^self-test: ')
  if [ "$footer" != "self-test: 5 declared, 2 ran, 3 skipped" ]; then
    bad "self-test accounting (partial skip)" "unexpected footer: '$footer'"; return
  fi
  for reason in "hooks missing or empty" "bin missing or empty" "does not exist"; do
    printf '%s\n' "$out" | grep -qF "$reason" || {
      bad "self-test accounting (partial skip)" "missing named reason: '$reason' in:
$out"; return; }
  done
  [ "$rc" -eq 1 ] && ok "self-test accounting (partial skip, each skip named)" \
                  || bad "self-test accounting (partial skip)" "rc=$rc, expected 1"
}

# Case 3: the founding bar. No repo resolvable at all (standalone binary, empty sandbox HOME,
# no VSTACK_DIR) -> every check skips, 0 ran. A self-test that ran nothing must not report
# success: this is the one shape where PASS would be indistinguishable from "did not run."
case_ran_nothing_is_not_success() {
  v=$(standalone_vstack ran-nothing)
  h="$ROOT/home-ran-nothing"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$MINPATH" "$v" self-test 2>&1)
  rc=$?
  footer=$(printf '%s\n' "$out" | grep -m1 '^self-test: ')
  if [ "$footer" != "self-test: 5 declared, 0 ran, 5 skipped" ]; then
    bad "self-test: ran-nothing is not success" "unexpected footer: '$footer'"; return
  fi
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'ran nothing -- a self-test that ran nothing must not report success'; then
    ok "self-test: ran-nothing is not success (0 ran -> FAIL, not a silent pass)"
  else
    bad "self-test: ran-nothing is not success" "rc=$rc, expected 1 with the ran-nothing message. output:
$out"
  fi
}

# --- self-test: declared count is derived, not hand-maintained -----------------------------
# TOTAL is `grep -c '^  # --- self-test [0-9]' "$SELF"` against bin/vstack's own source. This
# proves the marker convention actually exists and actually matches the number self-test prints
# at runtime, so a check added later cannot silently drop out of the count the way check 18 in
# docs/checks-that-inherit-their-answer.md dropped out of a hand-maintained one.
case_declared_count_matches_source() {
  n=$(grep -c '^  # --- self-test [0-9]' "$VSTACK_BIN")
  h="$ROOT/home-declared-count"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$MINPATH" VSTACK_DIR="$SRC" "$VSTACK_BIN" self-test 2>&1)
  footer=$(printf '%s\n' "$out" | grep -m1 '^self-test: ')
  printed=$(printf '%s' "$footer" | sed -n 's/^self-test: \([0-9]*\) declared.*/\1/p')
  if [ -n "$n" ] && [ "$n" -gt 0 ] && [ "$printed" = "$n" ]; then
    ok "self-test declared count is derived from source ($n markers)"
  else
    bad "self-test declared count is derived from source" "grep found $n marker(s), footer printed '$printed'"
  fi
}

# --- self-test: unknown-command dispatch is unaffected by the REPO exemption ---------------
# self-test/explain are the two commands allowed to run without a resolvable repo (see bin/
# vstack's REPO gate). This proves that exemption is scoped to them and did not quietly widen
# to swallow the "no repo found" error for every other command, or to accept a typo'd command
# name as though it were self-test.
case_repo_gate_still_refuses_others() {
  v=$(standalone_vstack repo-gate)
  h="$ROOT/home-repo-gate"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$MINPATH" "$v" doctor 2>&1)
  rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'no vstack repo found'; then
    ok "REPO gate still refuses commands other than self-test/explain"
  else
    bad "REPO gate still refuses commands other than self-test/explain" "rc=$rc, output:
$out"
  fi
}

# --- local run log: real value or the literal string "UNKNOWN", never a fabricated one -----

# self-test writes one JSONL record per run, tagged as what it is (not an attestation, not a
# receipt), with a real SHA/dirty flag when a repo is resolvable.
case_runlog_written_on_self_test() {
  if ! command -v jq >/dev/null 2>&1; then skip "run log written by self-test" "jq not installed"; return; fi
  h="$ROOT/home-runlog-written"
  mkdir -p "$h"
  env -i HOME="$h" PATH="$MINPATH" VSTACK_DIR="$SRC" "$VSTACK_BIN" self-test >/dev/null 2>&1
  f="$h/.config/agents/vstack-runlog.jsonl"
  [ -f "$f" ] || { bad "run log written by self-test" "no file at $f"; return; }
  row=$(tail -1 "$f")
  kind=$(printf '%s' "$row" | jq -r '.kind')
  note=$(printf '%s' "$row" | jq -r '.schemaNote')
  cmd=$(printf '%s' "$row" | jq -r '.command')
  decl=$(printf '%s' "$row" | jq -r '.declared')
  sha=$(printf '%s' "$row" | jq -r '.sha')
  if [ "$kind" = "local-run-log-entry" ] && [ "$cmd" = "self-test" ] && [ "$decl" = 5 ] \
     && printf '%s' "$note" | grep -qi 'not an attestation' \
     && printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    ok "run log written by self-test (tagged, real SHA, matching accounting)"
  else
    bad "run log written by self-test" "row: $row"
  fi
}

# No resolvable repo -> sha and repoDirty must serialise as the literal string "UNKNOWN", never
# as an empty string, a fabricated SHA of an unrelated repo, or `false` standing in for "don't
# know." This is the check 24 / dirty-tree failure mode from docs/checks-that-inherit-their-
# answer.md, aimed at this file's own record instead of at someone else's.
case_runlog_unknown_when_no_repo() {
  if ! command -v jq >/dev/null 2>&1; then skip "run log UNKNOWN with no repo" "jq not installed"; return; fi
  v=$(standalone_vstack runlog-unknown)
  h="$ROOT/home-runlog-unknown"
  mkdir -p "$h"
  env -i HOME="$h" PATH="$MINPATH" "$v" self-test >/dev/null 2>&1
  row=$(tail -1 "$h/.config/agents/vstack-runlog.jsonl" 2>/dev/null)
  sha=$(printf '%s' "$row" | jq -r '.sha' 2>/dev/null)
  dirty=$(printf '%s' "$row" | jq -r '.repoDirty' 2>/dev/null)
  if [ "$sha" = "UNKNOWN" ] && [ "$dirty" = "UNKNOWN" ]; then
    ok "run log UNKNOWN when no repo is resolvable (sha, repoDirty)"
  else
    bad "run log UNKNOWN when no repo is resolvable" "sha='$sha' repoDirty='$dirty' row: $row"
  fi
}

# jq missing must fail VISIBLY -- a note on stderr naming the missing dependency -- and must not
# fabricate a directory or a partial record. Silence here would be exactly the shape check 29 in
# docs/checks-that-inherit-their-answer.md warns about: a tool that is absent producing the same
# nothing as a tool that ran clean.
case_runlog_visible_skip_without_jq() {
  d="$ROOT/nobins-runlog"
  mkdir -p "$d"
  for f in /usr/bin/* /bin/*; do
    b=$(basename "$f")
    [ "$b" = jq ] && continue
    ln -s "$f" "$d/$b" 2>/dev/null
  done
  h="$ROOT/home-runlog-nojq"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$d" VSTACK_DIR="$SRC" "$VSTACK_BIN" self-test 2>&1)
  if printf '%s\n' "$out" | grep -qF 'run log: not written -- jq not installed' \
     && [ ! -e "$h/.config/agents/vstack-runlog.jsonl" ]; then
    ok "run log skip is visible and creates nothing without jq"
  else
    bad "run log skip is visible and creates nothing without jq" "output:
$out"
  fi
}

# `vstack verify` wraps the real .claude/verify.sh, parsing its printed footer rather than
# recomputing the count. This is the join: the wrapper's declared/ran/skipped must equal what
# verify.sh itself printed on the very same run, read independently here rather than trusted.
# Slow (runs the real gate) and left in the default set anyway, because a parser that was never
# run against its real source is exactly the kind of check this repo has shipped broken before.
case_verify_runlog_matches_own_footer() {
  if ! command -v jq >/dev/null 2>&1; then skip "vstack verify run-log matches its own footer" "jq not installed"; return; fi
  [ -x "$SRC/.claude/verify.sh" ] || { skip "vstack verify run-log matches its own footer" "no .claude/verify.sh here"; return; }
  h="$ROOT/home-verify-runlog"
  mkdir -p "$h"
  out=$(env -i HOME="$h" PATH="$MINPATH" VSTACK_DIR="$SRC" "$VSTACK_BIN" verify 2>&1)
  footer=$(printf '%s\n' "$out" | grep -m1 '^checks: [0-9]* declared, [0-9]* ran, [0-9]* skipped$')
  want_decl=$(printf '%s' "$footer" | sed -n 's/^checks: \([0-9]*\) declared.*/\1/p')
  want_ran=$(printf '%s' "$footer" | sed -n 's/.* \([0-9]*\) ran,.*/\1/p')
  want_skip=$(printf '%s' "$footer" | sed -n 's/.* \([0-9]*\) skipped$/\1/p')
  row=$(tail -1 "$h/.config/agents/vstack-runlog.jsonl" 2>/dev/null)
  got_decl=$(printf '%s' "$row" | jq -r '.declared' 2>/dev/null)
  got_ran=$(printf '%s' "$row" | jq -r '.ran' 2>/dev/null)
  got_skip=$(printf '%s' "$row" | jq -r '.skipped' 2>/dev/null)
  got_cmd=$(printf '%s' "$row" | jq -r '.command' 2>/dev/null)
  if [ -n "$want_decl" ] && [ "$got_cmd" = "verify" ] \
     && [ "$got_decl" = "$want_decl" ] && [ "$got_ran" = "$want_ran" ] && [ "$got_skip" = "$want_skip" ]; then
    ok "vstack verify run-log matches its own printed footer ($want_decl/$want_ran/$want_skip)"
  else
    bad "vstack verify run-log matches its own printed footer" \
        "footer='$footer' row='$row'"
  fi
}

cases="accounting_all_ran accounting_partial_skip ran_nothing_is_not_success declared_count_matches_source repo_gate_still_refuses_others runlog_written_on_self_test runlog_unknown_when_no_repo runlog_visible_skip_without_jq verify_runlog_matches_own_footer"
if [ $# -gt 0 ]; then cases="$*"; fi
for c in $cases; do
  "case_$c"
done

echo
printf 'vstack-cli.sh: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
