#!/usr/bin/env bash
# tests/dispatch-static.sh
#
# THE LIMIT, STATED PLAINLY: this suite makes ZERO calls to the model. It proves that the
# FIXTURES tests/auto-trigger.sh depends on are internally consistent -- every skill name a
# run_case expects to see fire still exists on disk, every setup_* function a run_case invokes
# is actually defined, the files those setup functions write still parse in their own language,
# and the case count the file's own docs claim matches the case count the file actually has.
#
# It proves NOTHING about whether a skill actually fires on a prompt. Only tests/auto-trigger.sh
# proves that, because only tests/auto-trigger.sh runs the model. This suite would stay green
# the day auto-trigger stopped firing, because a dead skill dispatch and an intact fixture list
# are two different facts. Do not read a green run here as "skill dispatch works" -- read it as
# "the regression suite is not quietly rotting: the thing it says it tests still exists".
#
# It does not run on CI, on purpose: the user declined an ANTHROPIC_API_KEY secret in CI, so
# auto-trigger.sh (and team-gating.sh) can never run there and skill-dispatch regression stays
# unmeasured on that machine. This script recovers what CAN be checked for free -- fixture
# integrity, not dispatch behavior -- and is wired into CI for exactly that, and only that.
#
# Never source or exec tests/auto-trigger.sh from here. Sourcing it runs its preflight and, on
# any host with an authenticated `claude` CLI, falls straight through into real, billed model
# calls -- the exact thing this file exists to avoid. Every extraction below is done by reading
# auto-trigger.sh as text (grep/sed/awk over its literal 4-line `run_case \ / "..." \ / "..." \
# / "..." \ / "..."` call shape) and, for setup_* functions, by lifting just the function bodies
# out and sourcing those in isolation -- never the whole file.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET="$REPO_ROOT/tests/auto-trigger.sh"
SKILLS_DIR="$REPO_ROOT/claude/skills"
README="$REPO_ROOT/tests/README.md"

DECLARED=4
RAN=0
SKIPPED=0
FAIL=0

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

if [[ ! -f "$TARGET" ]]; then
  skip "fixtures parseable"          "tests/auto-trigger.sh not found"
  skip "skill names resolve"         "tests/auto-trigger.sh not found"
  skip "setup_* functions resolve"   "tests/auto-trigger.sh not found"
  skip "declared case count matches" "tests/auto-trigger.sh not found"
  printf 'assertions: %d declared, %d ran, %d skipped\n' "$DECLARED" "$RAN" "$SKIPPED"
  echo "NOTHING RAN -- refusing to report success"
  exit 2
fi

# ---------------------------------------------------------------------------
# Shared extraction: read every `run_case \ / "name" \ / "prompt" \ / "regex" \ / "setup_fn"`
# block by physical line offset. This is deliberately not a general bash-argument parser --
# it trusts the file's one actual layout (verified by hand against every call in the file when
# this suite was written) and calls out any block that does not match that shape as a parse
# failure rather than silently mis-reading it. A parser that guesses wrong and stays quiet is
# worse than one that refuses.
# ---------------------------------------------------------------------------
RC_NAME=(); RC_REGEX=(); RC_SETUP=()
PARSE_ERRORS=0
NEG_CASE_COUNT=0

qline_re='^[[:space:]]*".*"[[:space:]]*\\?[[:space:]]*$'
strip_q() { sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*\\?[[:space:]]*$//' <<<"$1"; }

FILE_LINES=()
while IFS= read -r fl_line || [[ -n "$fl_line" ]]; do FILE_LINES+=("$fl_line"); done < "$TARGET"
n=${#FILE_LINES[@]}
i=0
while (( i < n )); do
  line="${FILE_LINES[i]}"
  if [[ "$line" =~ ^run_case[[:space:]]*\\?[[:space:]]*$ ]]; then
    a1="${FILE_LINES[i+1]:-}"; a2="${FILE_LINES[i+2]:-}"; a3="${FILE_LINES[i+3]:-}"; a4="${FILE_LINES[i+4]:-}"
    if [[ "$a1" =~ $qline_re && "$a2" =~ $qline_re && "$a3" =~ $qline_re && "$a4" =~ $qline_re ]]; then
      RC_NAME+=("$(strip_q "$a1")")
      RC_REGEX+=("$(strip_q "$a3")")
      RC_SETUP+=("$(strip_q "$a4")")
    else
      PARSE_ERRORS=$((PARSE_ERRORS+1))
      echo "FAIL <parser> run_case block starting at auto-trigger.sh:$((i+1)) does not match the expected 4-line quoted-argument shape; static parser cannot verify this case"
    fi
    i=$((i+5))
  elif [[ "$line" =~ ^run_negative_case[[:space:]]*\\?[[:space:]]*$ ]]; then
    NEG_CASE_COUNT=$((NEG_CASE_COUNT+1))
    i=$((i+4))
  else
    i=$((i+1))
  fi
done

# ---------------------------------------------------------------------------
# (a) Every skill name a run_case expects resolves to a real installed skill directory.
# expected_regex may be an alternation ("a|b|c"); every alternative is checked individually --
# a stale alternative sitting next to two live ones is still a dead assertion worth catching.
# ---------------------------------------------------------------------------
echo "--- (a) skill names named in run_case resolve under claude/skills/ ---"
a_checked=0; a_fail=0
if [[ ! -d "$SKILLS_DIR" ]]; then
  skip "skill names resolve" "claude/skills/ not found at $SKILLS_DIR"
else
  for idx in "${!RC_NAME[@]}"; do
    IFS='|' read -r -a toks <<< "${RC_REGEX[$idx]}"
    for tok in "${toks[@]}"; do
      tok="$(echo "$tok" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -z "$tok" ]] && continue
      a_checked=$((a_checked+1))
      if [[ -f "$SKILLS_DIR/$tok/SKILL.md" ]]; then
        echo "PASS  ${RC_NAME[$idx]} -> $tok"
      else
        echo "FAIL  ${RC_NAME[$idx]} -> skill '$tok' has no $SKILLS_DIR/$tok/SKILL.md"
        a_fail=$((a_fail+1))
      fi
    done
  done
  (( PARSE_ERRORS > 0 )) && a_fail=$((a_fail + PARSE_ERRORS))
  if (( a_fail == 0 )); then
    ok "skill names resolve ($a_checked/$a_checked ok, 0 fail, $PARSE_ERRORS parse errors)"
  else
    bad "skill names resolve" "$a_fail of $a_checked checked names did not resolve ($PARSE_ERRORS parse errors)"
  fi
fi
echo

# ---------------------------------------------------------------------------
# (b) Every setup_* function referenced as a run_case argument is actually defined.
# ---------------------------------------------------------------------------
echo "--- (b) setup_* functions referenced by run_case are defined ---"
# No associative arrays / mapfile below: this repo's default macOS bash is 3.2, which has
# neither, and nothing else in the tree uses them -- match that convention rather than break it.
in_list() { local needle="$1"; shift; local x; for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

DEFINED_SETUP=()
while IFS= read -r ds_line; do DEFINED_SETUP+=("$ds_line"); done < <(grep -oE '^setup_[A-Za-z0-9_]+\(\)' "$TARGET" | sed -E 's/\(\)$//' | sort -u)

b_checked=0; b_fail=0
REFERENCED_LIST=()
for idx in "${!RC_SETUP[@]}"; do
  fn="${RC_SETUP[$idx]}"
  [[ -z "$fn" ]] && continue
  REFERENCED_LIST+=("$fn")
  b_checked=$((b_checked+1))
  if in_list "$fn" "${DEFINED_SETUP[@]}"; then
    echo "PASS  ${RC_NAME[$idx]} -> $fn is defined"
  else
    echo "FAIL  ${RC_NAME[$idx]} -> $fn referenced but not defined in tests/auto-trigger.sh"
    b_fail=$((b_fail+1))
  fi
done
for f in "${DEFINED_SETUP[@]}"; do
  in_list "$f" "${REFERENCED_LIST[@]}" || echo "INFO  $f is defined but never referenced by a run_case (dead fixture, not a failure)"
done
if (( b_fail == 0 )); then
  ok "setup_* functions resolve ($b_checked/$b_checked ok, 0 fail; ${#DEFINED_SETUP[@]} defined total)"
else
  bad "setup_* functions resolve" "$b_fail of $b_checked referenced setup_* functions are not defined"
fi
echo

# ---------------------------------------------------------------------------
# (c) Every fixture file a setup_* function writes is syntactically parseable, using a
# deterministic validator for each of the eight extensions today's fixtures actually use that
# are executable/structured rather than prose: .sh (bash -n), .py (python3 -m py_compile), .js/
# .mjs/.cjs (node --check), .json (jq empty), .ts (tsc --noEmit), .go (gofmt -l), .html
# (xmllint --html --noout), .css (csslint). Prose/data fixtures (.md, .txt, .log, .bak) have
# nothing to parse and are skipped on purpose.
#
# A missing validator for one of the eight is now a FAIL naming the missing binary, never a
# silent SKIP. It used to be a SKIP, and that is precisely the fake green this script existed
# to prevent: run with a PATH that hides `node` (`PATH=/usr/bin:/bin tests/dispatch-static.sh`)
# and the old code left 28 of 35 fixtures across ts/go/html/css/js entirely unexamined -- every
# .ts, .go, .html and .css fixture had no case at all, and every .js fixture skipped silently
# the moment node was not on PATH -- while still printing "ok fixtures parseable" and
# "FIXTURES INTACT". A skip is not evidence the file is fine, and the summary line must not
# claim it is. CI installs the missing tool (tsc, gofmt, xmllint, csslint are the four this
# host previously lacked wiring for); a local run without one now fails and says which.
# ---------------------------------------------------------------------------
echo "--- (c) fixture files setup_* functions write are syntactically valid ---"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-static.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Heredoc-aware on purpose: a naive "grab until the next line that is just '}'" over-reads a
# function's own fixture content. setup_typescript's sample.ts ends with a bare `}` (the closing
# brace of the TS function it writes) *inside* its `<<'EOF'` heredoc, and setup_stale_verify's
# search.js does the same -- both tripped a first version of this extractor that stopped mid
# heredoc, corrupted the concatenated function file, and made setup_webapp, setup_draft and
# setup_gostruct disappear as a side effect (their bodies got absorbed into the truncated
# heredoc above them). This tracks heredoc state and only treats a top-level `}` as the end of
# the function while no heredoc is open. Known limit: `<<-` (tab-stripped) terminators may be
# indented in the wild; none of today's fixtures use one, so that case is not handled.
AWK_PROG="$WORK/extract_setup.awk"
cat > "$AWK_PROG" <<'AWKEOF'
BEGIN { grab = 0; inhd = 0; delim = "" }
{
  if (!grab) {
    if ($0 ~ /^setup_[A-Za-z0-9_]+\(\) \{$/) { grab = 1; print; next }
    next
  }
  if (inhd) {
    print
    if ($0 == delim) { inhd = 0; delim = "" }
    next
  }
  print
  if (match($0, /<<-?['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
    seg = substr($0, RSTART, RLENGTH)
    gsub(/<<-?/, "", seg)
    gsub(/['"]/, "", seg)
    delim = seg
    inhd = 1
    next
  }
  if ($0 ~ /^}$/) { grab = 0 }
}
AWKEOF
awk -f "$AWK_PROG" "$TARGET" > "$WORK/setup_functions.sh"

c_ok=0; c_fail=0; c_skip=0
if [[ ! -s "$WORK/setup_functions.sh" ]]; then
  skip "fixtures parseable" "could not extract any setup_* function body from tests/auto-trigger.sh"
else
  # shellcheck disable=SC1091  # dynamically extracted from auto-trigger.sh, not a static target
  source "$WORK/setup_functions.sh"

  for fn in "${DEFINED_SETUP[@]}"; do
    fixdir="$(mktemp -d "$WORK/fx.XXXXXX")"
    if ! "$fn" "$fixdir" 2>"$WORK/setup.err"; then
      echo "FAIL  $fn wrote its fixtures: $(cat "$WORK/setup.err")"
      c_fail=$((c_fail+1))
      continue
    fi
    while IFS= read -r f; do
      case "$f" in
        *.sh)
          if bash -n "$f" 2>"$WORK/p.err"; then
            echo "PASS  $fn -> ${f#"$fixdir"/} (bash -n)"; c_ok=$((c_ok+1))
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/} (bash -n): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
          fi ;;
        *.py)
          if command -v python3 >/dev/null 2>&1; then
            if python3 -m py_compile "$f" 2>"$WORK/p.err"; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (python3 -m py_compile)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (python3 -m py_compile): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: python3"; c_fail=$((c_fail+1))
          fi ;;
        *.js|*.mjs|*.cjs)
          if command -v node >/dev/null 2>&1; then
            if node --check "$f" 2>"$WORK/p.err"; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (node --check)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (node --check): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: node"; c_fail=$((c_fail+1))
          fi ;;
        *.json)
          if command -v jq >/dev/null 2>&1; then
            if jq empty "$f" >"$WORK/p.err" 2>&1; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (jq empty)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (jq empty): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: jq"; c_fail=$((c_fail+1))
          fi ;;
        *.ts)
          # tsc reads a single file standalone (no tsconfig.json in a synthetic fixdir);
          # --skipLibCheck keeps it from pulling in lib.d.ts noise unrelated to the fixture,
          # and --noEmit means this never writes a .js file next to the fixture it is checking.
          if command -v tsc >/dev/null 2>&1; then
            if tsc --noEmit --skipLibCheck "$f" 2>"$WORK/p.err"; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (tsc --noEmit)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (tsc --noEmit): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: tsc (npm install -g typescript)"; c_fail=$((c_fail+1))
          fi ;;
        *.go)
          # gofmt -l is a real parse: a syntax error prints to stderr and exits non-zero. A
          # file that parses fine but needs reformatting also exits 0 (just lists itself on
          # stdout), which is deliberate -- this checks the fixture parses, not that it is
          # already gofmt-clean.
          if command -v gofmt >/dev/null 2>&1; then
            if gofmt -l "$f" >/dev/null 2>"$WORK/p.err"; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (gofmt -l)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (gofmt -l): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: gofmt (install the Go toolchain)"; c_fail=$((c_fail+1))
          fi ;;
        *.html)
          # libxml2's HTML parser is deliberately permissive -- it recovers from broken markup
          # rather than refusing it, so --html --noout always exits 0. It still reports genuine
          # parse errors ("HTML parser error :") to stderr while doing so; that text, not the
          # exit code, is the signal.
          if command -v xmllint >/dev/null 2>&1; then
            xmllint --html --noout "$f" >/dev/null 2>"$WORK/p.err"
            if ! grep -qi 'parser error' "$WORK/p.err" 2>/dev/null; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (xmllint --html)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (xmllint --html): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: xmllint (libxml2-utils on Debian/Alpine)"; c_fail=$((c_fail+1))
          fi ;;
        *.css)
          # csslint's exit code already isolates real parse errors from style opinion: it
          # exits non-zero only when the file has an `error`-level problem (a genuine syntax
          # break), and exits 0 when everything reported is a `warning` (property ordering,
          # box-model opinions, etc.) -- verified against both a hand-broken fixture and every
          # real .css fixture in this file before wiring this in.
          if command -v csslint >/dev/null 2>&1; then
            if csslint --quiet "$f" >"$WORK/p.err" 2>&1; then
              echo "PASS  $fn -> ${f#"$fixdir"/} (csslint)"; c_ok=$((c_ok+1))
            else
              echo "FAIL  $fn -> ${f#"$fixdir"/} (csslint): $(cat "$WORK/p.err")"; c_fail=$((c_fail+1))
            fi
          else
            echo "FAIL  $fn -> ${f#"$fixdir"/}: missing validator: csslint (npm install -g csslint)"; c_fail=$((c_fail+1))
          fi ;;
        *.md|*.txt|*.log|*.bak)
          echo "SKIP  $fn -> ${f#"$fixdir"/} (prose/data fixture, nothing to parse)"; c_skip=$((c_skip+1)) ;;
        *)
          echo "FAIL  $fn -> ${f#"$fixdir"/}: no validator wired up for this extension (add one to tests/dispatch-static.sh rather than let it skip silently)"; c_fail=$((c_fail+1)) ;;
      esac
    done < <(find "$fixdir" -type f | sort)
  done
  rm -f "$WORK/p.err" "$WORK/setup.err"

  if (( c_fail == 0 )); then
    ok "fixtures parseable ($c_ok parsed clean, $c_skip skipped as prose/data, 0 fail -- every executable fixture was actually run through a validator)"
  else
    bad "fixtures parseable" "$c_fail fixture file(s) failed to parse or had no validator available ($c_ok clean, $c_skip skipped as prose/data)"
  fi
fi
echo

# ---------------------------------------------------------------------------
# (d) The declared case count matches what tests/README.md's prose claims.
# ---------------------------------------------------------------------------
echo "--- (d) declared case count matches README's prose ---"
actual_cases=$(( ${#RC_NAME[@]} + NEG_CASE_COUNT ))
echo "auto-trigger.sh actually has ${#RC_NAME[@]} run_case + $NEG_CASE_COUNT run_negative_case = $actual_cases cases"

if [[ ! -f "$README" ]]; then
  skip "declared case count matches" "tests/README.md not found"
else
  stated=()
  while IFS= read -r st_line; do stated+=("$st_line"); done < <(grep -oE '[0-9]+ cases' "$README" | grep -oE '[0-9]+' | sort -u)
  if (( ${#stated[@]} == 0 )); then
    skip "declared case count matches" "tests/README.md states no 'N cases' count to check against"
  elif (( ${#stated[@]} > 1 )); then
    bad "declared case count matches" "tests/README.md itself states conflicting counts: ${stated[*]}"
  elif [[ "${stated[0]}" == "$actual_cases" ]]; then
    ok "declared case count matches (README says ${stated[0]}, file has $actual_cases)"
  else
    bad "declared case count matches" "README says ${stated[0]} cases, tests/auto-trigger.sh actually has $actual_cases"
  fi
fi
echo

printf 'assertions: %d declared, %d ran, %d skipped\n' "$DECLARED" "$RAN" "$SKIPPED"
if (( RAN == 0 )); then
  echo "NOTHING RAN -- refusing to report success"
  exit 2
fi
if (( RAN + SKIPPED != DECLARED )); then
  bad "assertion accounting" "$((DECLARED - RAN - SKIPPED)) declared assertion(s) reported nothing"
fi
if (( FAIL == 0 )); then
  echo "FIXTURES INTACT (this proves fixture integrity only -- see header. It does not prove skills fire.)"
  exit 0
else
  echo "FIXTURE CHECK FAILED"
  exit 1
fi
