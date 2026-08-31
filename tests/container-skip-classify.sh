#!/usr/bin/env bash
# tests/container-skip-classify.sh -- proves the "3-verify-gate" assertion block inside
# tests/container-matrix.sh's assertions.sh heredoc classifies a skipped .claude/verify.sh run
# correctly: a skip is "UNMEASURABLE WITHOUT CREDENTIALS" only when EVERY skip present is
# credential-related, never when even one is not.
#
# THE DEFECT FIXED 2026-08-31: the old code did
#   printf '%s' "$skip_reasons" | grep -qi 'plugin manifest\|authenticat\|claude CLI' && needs_auth=1
# on the JOINED reason string -- one credentials-matching skip stamped "UNMEASURABLE WITHOUT
# CREDENTIALS" across ALL skips present. Measured: at a non-tag ref the gate skipped twice -- the
# plugin manifest (genuinely credentials) and check 24 ("no tags in this checkout (shallow
# clone?), so there is nothing to compare against") -- and the second was published under a
# credentials banner that was untrue about it, so check 24 was dark while the output read as
# fully understood. The fix counts total skips vs credential-attributable skips and requires them
# EQUAL for the SKIP verdict; any unexplained skip produces FAIL naming it.
#
# TECHNIQUE: like tests/container-ref-resolve.sh and tests/falsify-parallel-reap.sh, this suite
# EXTRACTS the real classification block out of tests/container-matrix.sh (by locating its
# anchor line and scanning forward counting if/fi depth to the matching close) rather than
# reimplementing the logic, so it cannot pass against a classifier it never actually exercised.
# The extracted block's first line -- `out=$(/work/repo/.claude/verify.sh 2>&1)` -- is the only
# line touched: it is dropped and replaced with `out=$(cat "$FIXTURE")` so the block can be run,
# byte-identical otherwise, against synthetic .claude/verify.sh output instead of a real
# container. If that anchor line is not found verbatim, extraction fails and every proof below
# reports FAIL naming that fact -- which is what would make this suite RED against a rewritten
# block this technique cannot yet locate.
#
# SELF-CHECK: `CSC_SELFCHECK=1 ./tests/container-skip-classify.sh` (or `--selfcheck`) rebuilds the
# extracted block with ONE line mutated back to the pre-fix joined-grep condition (the exact shape
# described above) and re-runs PROOF 4 -- the two-skips-mixed regression case -- against it,
# expecting the WRONG "UNMEASURABLE WITHOUT CREDENTIALS" verdict to come back. That is the "watch
# it go red" evidence that PROOF 4 is not vacuous. It has no effect on PROOFS 1, 2, 3, 5, 6, none
# of which depend on the mutated line.
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$repo_root/tests/container-matrix.sh"
SELF="$repo_root/tests/container-skip-classify.sh"
SELFCHECK="${CSC_SELFCHECK:-0}"
[ "${1:-}" = "--selfcheck" ] && SELFCHECK=1

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(/usr/bin/grep -c '^# --- PROOF [0-9]' "$SELF")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }

[ "$SELFCHECK" = 1 ] && printf '*** CSC_SELFCHECK=1: PROOF 4 is expected to report the WRONG verdict below (classifier mutated back to the pre-fix joined-grep form) ***\n\n'

if [ ! -f "$target" ]; then
  bad "all proofs" "$target does not exist -- nothing to test"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/csc.XXXXXX") || { echo "cannot mktemp a workdir" >&2; exit 2; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM

ANCHOR_LITERAL='out=$(/work/repo/.claude/verify.sh 2>&1)'

# ---- extraction ---------------------------------------------------------------------------------
extract_gate_block(){
  # Prints the "3-verify-gate" block from $target: the anchor assignment line through its
  # matching `fi` (there are two, nested: the outer PASS/else split and the inner SKIP/FAIL
  # split), found by forward-scanning if/fi depth from the anchor -- extraction, not
  # reimplementation, so this cannot pass against a block that was rewritten or removed.
  anchor_line=$(/usr/bin/grep -nF "$ANCHOR_LITERAL" "$target" | head -1 | cut -d: -f1)
  [ -z "$anchor_line" ] && return 1
  awk -v start="$anchor_line" '
    NR < start { next }
    {
      trimmed = $0
      sub(/^[ \t]+/, "", trimmed)
      print
      if (trimmed ~ /^if[ \t]/) { depth++ }
      else if (trimmed ~ /^fi;?[ \t]*$/) {
        depth--
        if (depth == 0) exit
      }
    }
  ' "$target"
}

# build_classifier_script <outfile> <mutate:0|1>
# Writes a standalone script that: takes a fixture file path as $1, sets $out from it, runs the
# extracted block verbatim (or, if mutate=1, with the inner accounting condition swapped back for
# the pre-fix joined-grep test), and prints the res() call's status then detail.
build_classifier_script(){
  outfile="$1"; mutate="$2"
  block=$(extract_gate_block) || return 1
  [ -z "$block" ] && return 1
  first_line=$(printf '%s\n' "$block" | head -1)
  [ "$first_line" = "$ANCHOR_LITERAL" ] || return 1
  rest=$(printf '%s\n' "$block" | tail -n +2)

  if [ "$mutate" = 1 ]; then
    # The pre-fix condition: SKIP as soon as the JOINED skip_reasons string matches a credentials
    # keyword anywhere, ignoring whether every skip present is accounted for. Full-line
    # replacement (matched on the fixed-string accounting condition this block's fix introduced)
    # avoids partial-substitution escaping games.
    repl='  if [ "$tail_word" = "VERIFIED" ] && [ "${n_skip:-0}" -gt 0 ] && printf "%s" "$skip_reasons" | /usr/bin/grep -qi '"'"'plugin manifest\\|authenticat\\|claude CLI'"'"'; then'
    rest=$(printf '%s\n' "$rest" | awk -v repl="$repl" '
      /\$\{n_skip:-0\}" = "\$\{n_cred:-0\}/ { print repl; next }
      { print }
    ')
  fi

  {
    cat <<'HDR'
#!/usr/bin/env bash
set -u
FIXTURE="$1"
RES_STATUS=""; RES_NAME=""; RES_DETAIL=""
res(){ RES_STATUS="$1"; RES_NAME="$2"; RES_DETAIL="$3"; }
out=$(cat "$FIXTURE")
HDR
    printf '%s\n' "$rest"
    cat <<'TRL'
printf '%s\n' "$RES_STATUS"
printf '%s\n' "$RES_DETAIL"
TRL
  } > "$outfile"
  return 0
}

# run_classifier <script> <fixture> -> prints "STATUS\nDETAIL"
run_classifier(){
  bash "$1" "$2" 2>"$WORK/classify.err"
}

# mk_fixture <outfile> <tail_word> [skip_line ...] -- shapes synthetic output exactly like
# .claude/verify.sh's own: ok lines, skip lines (format "skip  <name> (<reason>)", matching
# .claude/verify.sh's own skip(){ printf 'skip  %s (%s)\n' ... }), a "checks: N declared, N ran,
# N skipped" line, then the terminal VERIFIED / VERIFICATION FAILED line.
mk_fixture(){
  outfile="$1"; tail_word="$2"; shift 2
  n_skip=$#
  n_ok=2
  declared=$((n_ok + n_skip))
  {
    echo "ok    dummy-check-a"
    echo "ok    dummy-check-b"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf 'checks: %d declared, %d ran, %d skipped\n' "$declared" "$n_ok" "$n_skip"
    printf '%s\n' "$tail_word"
  } > "$outfile"
}

CRED_A="skip  plugin manifests valid (claude CLI not installed)"
CRED_B="skip  plugin manifest versions (jq not installed)"
NONCRED="skip  declared version matches what installs (no tags in this checkout (shallow clone?), so there is nothing to compare against)"

normal_script="$WORK/classify-normal.sh"
mutated_script="$WORK/classify-mutated.sh"

if ! build_classifier_script "$normal_script" 0; then
  reason="no '3-verify-gate' block found in $target (anchor line '$ANCHOR_LITERAL' not present verbatim) -- the fix has not landed, or the block was rewritten, as of this run"
  bad "PROOF 1: zero skips + VERIFIED tail -> PASS verdict" "$reason"
  bad "PROOF 2: one credentials-related skip -> SKIP verdict" "$reason"
  bad "PROOF 3: two skips, both credentials-related -> SKIP verdict" "$reason"
  bad "PROOF 4: two skips, one credentials + one non-credentials -> FAIL naming the non-credentials skip" "$reason"
  bad "PROOF 5: one skip, NOT credentials-related -> FAIL" "$reason"
  bad "PROOF 6: trailing line not VERIFIED -> FAIL" "$reason"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi
build_classifier_script "$mutated_script" 1 >/dev/null 2>&1

classify(){ # <script> <fixture> -> sets CLS_STATUS, CLS_DETAIL
  out=$(run_classifier "$1" "$2")
  CLS_STATUS=$(printf '%s\n' "$out" | sed -n '1p')
  CLS_DETAIL=$(printf '%s\n' "$out" | sed -n '2,$p')
}

# --- PROOF 1: zero skips + VERIFIED tail -> PASS verdict ------------------------------------------
mk_fixture "$WORK/f1.out" "VERIFIED"
classify "$normal_script" "$WORK/f1.out"
if [ "$CLS_STATUS" = "PASS" ]; then
  ok "PROOF 1: zero skips + VERIFIED tail -> PASS verdict"
else
  bad "PROOF 1: zero skips + VERIFIED tail -> PASS verdict" \
      "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want PASS"
fi

# --- PROOF 2: one credentials-related skip -> SKIP verdict ----------------------------------------
mk_fixture "$WORK/f2.out" "VERIFIED" "$CRED_A"
classify "$normal_script" "$WORK/f2.out"
if [ "$CLS_STATUS" = "SKIP" ] && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF 'UNMEASURABLE WITHOUT CREDENTIALS'; then
  ok "PROOF 2: one credentials-related skip -> SKIP verdict"
else
  bad "PROOF 2: one credentials-related skip -> SKIP verdict" \
      "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want SKIP mentioning UNMEASURABLE WITHOUT CREDENTIALS"
fi

# --- PROOF 3: two skips, both credentials-related -> SKIP verdict ---------------------------------
mk_fixture "$WORK/f3.out" "VERIFIED" "$CRED_A" "$CRED_B"
classify "$normal_script" "$WORK/f3.out"
if [ "$CLS_STATUS" = "SKIP" ] && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF 'all 2 skip(s) accounted for'; then
  ok "PROOF 3: two skips, both credentials-related -> SKIP verdict"
else
  bad "PROOF 3: two skips, both credentials-related -> SKIP verdict" \
      "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want SKIP mentioning 'all 2 skip(s) accounted for'"
fi

# --- PROOF 4: two skips, one credentials + one non-credentials -> FAIL naming the non-credentials -
# skip. THIS IS THE REGRESSION CASE: the old joined-grep code stamped this "UNMEASURABLE WITHOUT
# CREDENTIALS" because ONE skip (the plugin manifest) matched, hiding that check 24's "no tags in
# this checkout" skip was never actually explained by credentials. Under CSC_SELFCHECK=1, runs
# against the mutated (pre-fix) classifier instead and expects that WRONG verdict back.
mk_fixture "$WORK/f4.out" "VERIFIED" "$CRED_A" "$NONCRED"
if [ "$SELFCHECK" = 1 ]; then
  classify "$mutated_script" "$WORK/f4.out"
  if [ "$CLS_STATUS" = "SKIP" ] && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF 'UNMEASURABLE WITHOUT CREDENTIALS'; then
    ok "PROOF 4 [selfcheck, mutated]: pre-fix joined-grep classifier wrongly reports SKIP on the mixed case"
  else
    bad "PROOF 4 [selfcheck, mutated]: pre-fix joined-grep classifier wrongly reports SKIP on the mixed case" \
        "mutation did not reproduce the old wrong verdict (got status=[$CLS_STATUS] detail=[$CLS_DETAIL]) -- the selfcheck itself is broken"
  fi
else
  classify "$normal_script" "$WORK/f4.out"
  if [ "$CLS_STATUS" = "FAIL" ] \
     && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF 'declared version matches what installs' \
     && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF '1 of 2 skip(s) are credential-related'; then
    ok "PROOF 4: two skips, one credentials + one non-credentials -> FAIL naming the non-credentials skip"
  else
    bad "PROOF 4: two skips, one credentials + one non-credentials -> FAIL naming the non-credentials skip" \
        "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want FAIL naming 'declared version matches what installs' and '1 of 2 skip(s) are credential-related'"
  fi
fi

# --- PROOF 5: one skip, NOT credentials-related -> FAIL --------------------------------------------
mk_fixture "$WORK/f5.out" "VERIFIED" "$NONCRED"
classify "$normal_script" "$WORK/f5.out"
if [ "$CLS_STATUS" = "FAIL" ] && printf '%s' "$CLS_DETAIL" | /usr/bin/grep -qF 'declared version matches what installs'; then
  ok "PROOF 5: one skip, NOT credentials-related -> FAIL"
else
  bad "PROOF 5: one skip, NOT credentials-related -> FAIL" \
      "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want FAIL naming 'declared version matches what installs'"
fi

# --- PROOF 6: trailing line not VERIFIED -> FAIL ----------------------------------------------------
mk_fixture "$WORK/f6.out" "VERIFICATION FAILED"
classify "$normal_script" "$WORK/f6.out"
if [ "$CLS_STATUS" = "FAIL" ]; then
  ok "PROOF 6: trailing line not VERIFIED -> FAIL"
else
  bad "PROOF 6: trailing line not VERIFIED -> FAIL" \
      "got status=[$CLS_STATUS] detail=[$CLS_DETAIL], want FAIL"
fi

echo
printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
if [ "$((RAN + SKIPPED))" -ne "$TOTAL" ]; then
  printf 'FAIL  check accounting\n      %d declared check(s) reported nothing\n' "$((TOTAL - RAN - SKIPPED))"
  FAIL=1
fi
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ] && echo VERIFIED || echo "VERIFICATION FAILED"
[ "$FAIL" -eq 0 ] && [ "$RAN" -gt 0 ]
exit $?
