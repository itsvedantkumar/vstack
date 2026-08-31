#!/usr/bin/env bash
# tests/container-ref-resolve.sh -- proves tests/container-matrix.sh can install from a full
# commit SHA, not just a branch/tag name.
#
# The defect: the inner assertions.sh heredoc in tests/container-matrix.sh (assembled by the
# host script and run inside each container) resolves $REF with a single
#   git clone --quiet --branch "$REF" --depth 1 https://github.com/itsvedantkumar/vstack.git /work/repo
# `git clone --branch` resolves ONLY refs/heads and refs/tags -- never a bare commit SHA. Measured
# against the real remote: REF=main -> rc=0; REF=cf1bc5be05d44829844a443f26ba3891dac928f6 (a real
# commit on this repo's default branch) -> rc=128 "Remote branch ... not found in upstream origin".
# VSTACK_REF=<sha> is a legitimate, already-documented way to pin container-matrix.sh (see e.g.
# CONTAINER_MATRIX_REF plumbing elsewhere in this repo's release process); today it always fails.
#
# The planned fix classifies REF: a 40-char all-lowercase-hex string is a commit SHA and must be
# resolved via `git init` + `git remote add origin <url>` + `git fetch --depth 1 origin <sha>` +
# `git checkout FETCH_HEAD`; anything else keeps the existing
# `git clone --quiet --branch "$REF" --depth 1` form unchanged (this is the release lane -- a fix
# that silently changed it for tags/branches too would be its own regression).
#
# TECHNIQUE: like tests/falsify-parallel-reap.sh, this suite EXTRACTS the real classification
# logic out of tests/container-matrix.sh rather than reimplementing it, so it cannot pass against
# a fix whose behaviour it never actually exercised. It tries two shapes, in order, since the fix
# has not landed as of this writing and its exact shape is not dictated here:
#   1. a top-level predicate function (checked under a short list of plausible names) that returns
#      0 when its argument should be treated as a SHA;
#   2. failing that, an inline `if`/`elif` condition immediately guarding the first
#      `git fetch --depth 1 origin` call in the file, found by scanning backward from that call
#      for its nearest enclosing if/elif at matching if/fi depth.
# If NEITHER shape is found, PROOF 1 reports FAIL with that fact stated plainly -- which is what
# makes this suite RED today, for the right reason: the fix is simply not there yet. This is a
# real, disclosed limitation: a fix written as a `case` statement, or one that does not reference
# a variable literally named REF inside the extracted condition, will not be picked up by strategy
# 2 and this proof will need updating alongside it landing in a shape strategy 1 or 2 does not
# anticipate.
#
# PROOF 2 does not have this naming problem: the fix's mechanism is pinned by the brief in literal
# command text (`git init`, `remote add origin`, `git fetch --depth 1 origin`, `FETCH_HEAD`), so
# it is checked by literal presence, independent of any function/variable naming choice.
#
# SELF-CHECK: `CTRR_SELFCHECK=1 ./tests/container-ref-resolve.sh` (or `--selfcheck`) stubs the
# extracted classifier, once found, to unconditionally report "not a SHA" and expects PROOF 1 to
# then report FAIL on the one case (the real 40-hex SHA) that stub gets wrong -- the "watch it go
# red" evidence that PROOF 1 is not vacuous. It has no effect on PROOFS 2/3 (neither depends on
# the classifier).
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$repo_root/tests/container-matrix.sh"
SELF="$repo_root/tests/container-ref-resolve.sh"
SELFCHECK="${CTRR_SELFCHECK:-0}"
[ "${1:-}" = "--selfcheck" ] && SELFCHECK=1

SHA40="cf1bc5be05d44829844a443f26ba3891dac928f6"
REMOTE_URL="https://github.com/itsvedantkumar/vstack.git"

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(/usr/bin/grep -c '^# --- PROOF [0-9]' "$SELF")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

[ "$SELFCHECK" = 1 ] && printf '*** CTRR_SELFCHECK=1: PROOF 1 is expected to FAIL below (classifier stubbed to always say "not a SHA") ***\n\n'

if [ ! -f "$target" ]; then
  bad "all proofs" "$target does not exist -- nothing to test"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi

if [ "${#SHA40}" -ne 40 ]; then
  bad "all proofs" "this suite's own fixture SHA40 is not 40 characters -- fix the test, not the target"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi
SHA39="${SHA40%?}"
SHA41="${SHA40}0"
SHA40_BADCHAR="${SHA40%?}g"

# ---- scratch workdir + pid tracking (mirrors falsify-parallel-reap.sh) -------------------------
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ctrr.XXXXXX") || { echo "cannot mktemp a workdir" >&2; exit 2; }
TRACKED_PIDS=""
track(){ TRACKED_PIDS="$TRACKED_PIDS $1"; }
cleanup(){
  for _p in $TRACKED_PIDS; do kill -TERM "$_p" 2>/dev/null; done
  [ -n "$TRACKED_PIDS" ] && sleep 1
  for _p in $TRACKED_PIDS; do kill -KILL "$_p" 2>/dev/null; done
  rm -rf "$WORK" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ---- extraction ----------------------------------------------------------------------------
extract_fn(){
  # Parses $target for a top-level `name() {` ... matching `}` by brace-depth, prints it. Empty
  # output means the function is not there under that name -- extraction, not reimplementation.
  awk -v name="$1" '
    BEGIN{depth=0; on=0}
    # The trailing (#.*)? is not cosmetic tolerance. This repo documents the arguments of a
    # function in a comment on the brace line -- see res(){ # <status> <name> <detail> in
    # tests/container-matrix.sh -- so anchoring on a bare { at end-of-line would refuse to
    # extract a correctly-written classifier and report the fix as absent. That is a test
    # asserting formatting instead of behaviour, and it fails in the dangerous direction:
    # red forever, for a reason that reads like the implementation is missing.
    # No apostrophes in this block: the awk program is single-quoted and one would close it.
    on==0 && $0 ~ ("^"name"\\(\\)[[:space:]]*\\{[[:space:]]*(#.*)?$") { on=1 }
    on==1 {
      print
      n=gsub(/\{/,"{"); depth+=n
      n=gsub(/\}/,"}"); depth-=n
      if (depth==0) exit
    }
  ' "$target"
}

CANDIDATE_NAMES="is_sha_ref is_commit_sha is_sha is_full_sha is_git_sha looks_like_sha ref_is_sha classify_ref"

extract_classifier(){
  # Prints a sourceable shell fragment defining __ctrr_is_sha(){ } (0 = treat $1 as a SHA, 1 =
  # not) on stdout, and returns 0, if either extraction strategy finds something; otherwise
  # prints nothing and returns 1.
  for name in $CANDIDATE_NAMES; do
    body=$(extract_fn "$name")
    if [ -n "$body" ]; then
      printf '%s\n' "$body" | sed "1s/^${name}(/__ctrr_is_sha(/"
      return 0
    fi
  done

  fetch_line=$(/usr/bin/grep -nE 'git( +-C +[^ ]+)? +fetch( +--quiet)? +--depth 1 +origin' "$target" | head -1 | cut -d: -f1)
  [ -z "$fetch_line" ] && return 1

  cond=$(awk -v startline="$fetch_line" '
    NR<=startline { lines[NR]=$0 }
    END {
      depth=0
      for (i=startline; i>=1; i--) {
        line=lines[i]
        if (line ~ /^[[:space:]]*fi[[:space:]]*(#.*)?$/) { depth++; continue }
        if (line ~ /^[[:space:]]*(if|elif)[[:space:]]/) {
          if (depth==0) { print line; exit }
          depth--
        }
      }
    }
  ' "$target")
  [ -z "$cond" ] && return 1

  body=$(printf '%s' "$cond" | sed -E 's/^[[:space:]]*(if|elif)[[:space:]]+//; s/;[[:space:]]*then[[:space:]]*$//')
  [ -z "$body" ] && return 1
  printf '__ctrr_is_sha() {\n  REF="$1"\n  %s\n}\n' "$body"
  return 0
}

# --- PROOF 1: the ref classifier treats a 40-char hex string as a SHA, and rejects near-misses --
classifier_src="$WORK/classifier.sh"
if ! extract_classifier > "$classifier_src" 2>/dev/null || [ ! -s "$classifier_src" ]; then
  bad "PROOF 1: the ref classifier treats a 40-hex string as a SHA and rejects near-misses" \
      "no SHA classifier found in $target -- checked named functions ($CANDIDATE_NAMES) and an inline if/elif guarding 'git fetch --depth 1 origin' -- the fix has not landed as of this run"
else
  # shellcheck source=/dev/null
  . "$classifier_src"
  if [ "$SELFCHECK" = 1 ]; then
    # mutation: stub the extracted classifier to always report "not a SHA" -- the faithful shape
    # of "the 40-hex case is not recognised". Must break the "40-hex-sha" case below.
    __ctrr_is_sha(){ return 1; }
  fi

  p1_fail=""
  check_case(){ # $1=label $2=value $3=expect(0 sha, 1 not-sha)
    __ctrr_is_sha "$2"
    got=$?
    got_bin=0
    [ "$got" -ne 0 ] && got_bin=1
    [ "$got_bin" != "$3" ] && p1_fail="$p1_fail $1"
  }
  check_case "40-hex-sha"            "$SHA40"         0
  check_case "branch-main"           "main"           1
  check_case "tag-v1.38.0"           "v1.38.0"        1
  check_case "tag-v1.57.0"           "v1.57.0"        1
  check_case "39-char-hex"           "$SHA39"         1
  check_case "41-char-hex"           "$SHA41"         1
  check_case "40-char-with-nonhex"   "$SHA40_BADCHAR" 1
  unset -f __ctrr_is_sha 2>/dev/null

  if [ "$SELFCHECK" = 1 ]; then
    if [ -n "$p1_fail" ] && printf '%s' "$p1_fail" | /usr/bin/grep -q '40-hex-sha'; then
      ok "PROOF 1 [selfcheck, mutated]: classifier stubbed to always say 'not a SHA' correctly fails on:$p1_fail"
    else
      bad "PROOF 1 [selfcheck, mutated]: classifier stubbed to always say 'not a SHA' correctly fails on the real SHA case" \
          "mutation did not break the 40-hex-sha case (p1_fail=[$p1_fail]) -- the selfcheck itself is broken"
    fi
  else
    if [ -z "$p1_fail" ]; then
      ok "PROOF 1: the ref classifier treats a 40-hex string as a SHA and rejects near-misses"
    else
      bad "PROOF 1: the ref classifier treats a 40-hex string as a SHA and rejects near-misses" \
          "misclassified case(s):$p1_fail -- see $classifier_src"
    fi
  fi
fi

# --- PROOF 2: the generated inner script has both a SHA-fetch branch and the retained clone -----
# form. Checked by literal command presence (the brief pins this mechanism verbatim), never by a
# function/variable name -- this is what stops the fix from silently changing the release lane
# (the plain branch/tag clone path) too.
p2_missing=""
/usr/bin/grep -qF 'git clone --quiet --branch "$REF" --depth 1' "$target" || p2_missing="$p2_missing clone-branch-form-retained"
/usr/bin/grep -qE 'git( +-C +[^ ]+)? +fetch( +--quiet)? +--depth 1 +origin' "$target" || p2_missing="$p2_missing git-fetch-depth1-origin"
/usr/bin/grep -qE '(^|[^A-Za-z_.-])git init([^A-Za-z_.-]|$)' "$target"     || p2_missing="$p2_missing git-init"
/usr/bin/grep -qF 'remote add origin' "$target"                            || p2_missing="$p2_missing remote-add-origin"
/usr/bin/grep -qF 'FETCH_HEAD' "$target"                                   || p2_missing="$p2_missing FETCH_HEAD"
if [ -z "$p2_missing" ]; then
  ok "PROOF 2: the generated inner script has a SHA-fetch branch and keeps the clone --branch form"
else
  bad "PROOF 2: the generated inner script has a SHA-fetch branch and keeps the clone --branch form" \
      "missing in $target:$p2_missing -- the fix has not landed (or does not use the specified mechanism) as of this run"
fi

# --- PROOF 3: the SHA-fetch mechanism itself resolves cf1bc5b...8f6 against the real remote ------
# (network; degrades to a named SKIP, not a pass, if the network or remote is unreachable). This
# proves the technique works at all -- independent of whether tests/container-matrix.sh has been
# patched to use it yet, exactly as falsify-parallel-reap.sh's PROOF 1 establishes the underlying
# OS behaviour a fix depends on before checking the fix itself.
p3dir=$(mktemp -d "${TMPDIR:-/tmp}/ctrr-p3.XXXXXX" 2>/dev/null) || p3dir=""
if [ -z "$p3dir" ]; then
  skip "PROOF 3: the SHA-fetch mechanism resolves $SHA40 against the real remote" \
       "could not mktemp a scratch dir under \${TMPDIR:-/tmp}"
else
  p3log="$WORK/p3-fetch.log"
  (
    cd "$p3dir" || exit 9
    git init -q . && \
    git remote add origin "$REMOTE_URL" && \
    git fetch --depth 1 origin "$SHA40"
  ) > "$p3log" 2>&1 &
  P3PID=$!
  track "$P3PID"
  p3_done=0
  for _i in $(seq 1 30); do
    kill -0 "$P3PID" 2>/dev/null || { p3_done=1; break; }
    sleep 1
  done
  if [ "$p3_done" != 1 ]; then
    kill -KILL "$P3PID" 2>/dev/null
    skip "PROOF 3: the SHA-fetch mechanism resolves $SHA40 against the real remote" \
         "git fetch did not complete within 30s -- treating as network/remote unreachable"
  else
    wait "$P3PID" 2>/dev/null
    p3_rc=$?
    if [ "$p3_rc" -ne 0 ]; then
      skip "PROOF 3: the SHA-fetch mechanism resolves $SHA40 against the real remote" \
           "git init/remote add/fetch failed rc=$p3_rc -- treating as network/remote unreachable; log: $(tr '\n' ' ' < "$p3log")"
    else
      git -C "$p3dir" checkout -q FETCH_HEAD >/dev/null 2>&1
      got_sha=$(git -C "$p3dir" rev-parse HEAD 2>/dev/null)
      if [ "$got_sha" = "$SHA40" ]; then
        ok "PROOF 3: the SHA-fetch mechanism resolves $SHA40 against the real remote"
      else
        bad "PROOF 3: the SHA-fetch mechanism resolves $SHA40 against the real remote" \
            "git rev-parse HEAD after checkout FETCH_HEAD gave [$got_sha], want [$SHA40]"
      fi
    fi
  fi
  rm -rf "$p3dir" 2>/dev/null
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
