#!/usr/bin/env bash
# swebench/run.sh — SWE-bench Lite against each harness, on real repositories.
#
# The fixture benchmark measures review on eight-line files. This measures what the harnesses
# actually claim: given a real bug report from a real project, does the agent produce a patch
# that makes the project's own failing tests pass.
#
# Scoring is not a judgement call. Each instance ships FAIL_TO_PASS — tests that must go from
# failing to passing. An instance is resolved when all of them pass after the agent's patch.
# That is SWE-bench's own criterion.
#
# WHAT THE AGENT IS GIVEN: the problem statement and the repository. NOT the tests it must make
# pass, NOT the golden patch, NOT the `hints_text` field. All three are in the dataset and each
# would turn this into a memorisation test.
#
# ENVIRONMENTS. SWE-bench officially ships a Docker image per instance because these repos need
# period-appropriate interpreters and pinned dependencies. Without Docker this uses uv to fetch
# the interpreter and installs the project's own declared test requirements — a bare `pip install
# pytest` gives the wrong pytest and every test errors during collection, which scores as
# unresolved for reasons that have nothing to do with the agent.
#
# THE PRE-FLIGHT GATE is the important part. Before an agent runs, the failing test must actually
# fail. An instance whose environment did not build, or whose test passes already, is marked
# UNUSABLE and excluded from every arm's denominator — not counted as a loss. Counting broken
# setups as failures would let environment noise decide the comparison.
#
# Usage: GSTACK_DIR=... tests/evals/swebench/run.sh [--n 5] [--arms none,vstack,gstack]

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || exit 1
SRC=$(pwd)
DATA="$SRC/tests/evals/swebench/light.json"

N=3; ARMS_CSV="none,vstack,gstack"; PYVER="${PYVER:-3.11}"
while [ $# -gt 0 ]; do
  case "$1" in
    --n) N="$2"; shift 2 ;;
    --arms) ARMS_CSV="$2"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
# The dataset is fetched, never vendored: it is 3.9MB of upstream patches carrying absolute
# paths from other people's machines, which this repo's own home-path scanner objects to — and
# it is rightly not ours to redistribute.
if [ ! -f "$DATA" ]; then
  echo "fetching SWE-bench Lite (once)..." >&2
  python3 "$SRC/tests/evals/swebench/fetch.py" "$DATA" || { echo "could not fetch the dataset" >&2; exit 1; }
fi

command -v jq >/dev/null || { echo "needs jq"; exit 2; }
command -v uv >/dev/null || { echo "needs uv (it fetches the per-instance interpreter)"; exit 2; }
command -v claude >/dev/null || { echo "SKIP: claude CLI not installed"; exit 0; }
GSTACK_DIR="${GSTACK_DIR:-}"
case "$ARMS_CSV" in *gstack*) [ -d "$GSTACK_DIR" ] || { echo "note: dropping gstack (set GSTACK_DIR)" >&2; ARMS_CSV=$(echo "$ARMS_CSV"|sed 's/gstack//;s/,,/,/g;s/^,//;s/,$//'); } ;; esac

ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/swebench.XXXXXX")" && pwd)
RUNLOG="${RUNLOG:-$ROOT/runs.tsv}"
printf 'arm\tinstance\tresolved\tf2p_pass\tf2p_total\tstatus\n' > "$RUNLOG"
echo "log: $RUNLOG" >&2

setup_repo() { # <index> <dir> -> 0 usable, 1 unusable
  local i="$1" d="$2" repo base rq
  repo=$(jq -r ".[$i].repo" "$DATA"); base=$(jq -r ".[$i].base_commit" "$DATA")
  git clone -q "https://github.com/$repo" "$d" 2>/dev/null || return 1
  git -C "$d" checkout -q "$base" 2>/dev/null || return 1
  jq -r ".[$i].test_patch" "$DATA" | git -C "$d" apply - 2>/dev/null || return 1
  ( cd "$d" && uv venv --python "$PYVER" .venv >/dev/null 2>&1 ) || return 1
  # The project's own pinned test dependencies, not a bare pytest.
  for rq in requirements/tests.txt requirements/dev.txt test-requirements.txt requirements-dev.txt; do
    [ -f "$d/$rq" ] && ( cd "$d" && uv pip install -q -r "$rq" >/dev/null 2>&1 ) && break
  done
  ( cd "$d" && uv pip install -q -e . >/dev/null 2>&1 ) || return 1
  ( cd "$d" && uv pip install -q pytest >/dev/null 2>&1 )
  return 0
}

f2p_list() { jq -r ".[$1].FAIL_TO_PASS | if type==\"string\" then fromjson else . end | .[]" "$DATA"; }

run_tests() { # <dir> <index> -> "pass total"
  local d="$1" i="$2" pass=0 tot=0 t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tot=$((tot+1))
    ( cd "$d" && timeout 240 .venv/bin/python -m pytest -x -q "$t" >/dev/null 2>&1 ) && pass=$((pass+1))
  done < <(f2p_list "$i")
  printf '%s %s' "$pass" "$tot"
}

install_arm() { # <arm> <dir>
  local a="$1" d="$2" sk="$2/.claude/skills" cm="$2/.claude/commands" ag="$2/.claude/agents"
  mkdir -p "$sk" "$cm" "$ag"
  case "$a" in
    none) : ;;
    vstack)
      for x in "$SRC"/claude/skills/*/; do [ -d "$x" ] && cp -R "${x%/}" "$sk/"; done
      cp "$SRC"/claude/commands/*.md "$cm/" 2>/dev/null
      cp "$SRC"/claude/agents/*.md   "$ag/" 2>/dev/null ;;
    gstack)
      find "$GSTACK_DIR" -maxdepth 2 -name SKILL.md 2>/dev/null | while IFS= read -r m; do
        d0=$(dirname "$m"); cp -R "$d0" "$sk/$(basename "$d0")" 2>/dev/null
      done ;;
  esac
}

# --- pre-flight: which instances are usable at all -------------------------------------------
USABLE=""
idx=0; checked=0
while [ "$checked" -lt "$N" ] && [ "$idx" -lt "$(jq 'length' "$DATA")" ]; do
  id=$(jq -r ".[$idx].instance_id" "$DATA")
  d="$ROOT/preflight-$id"
  printf '\r  pre-flight %-34s ' "$id" >&2
  if setup_repo "$idx" "$d"; then
    read -r p t <<< "$(run_tests "$d" "$idx")"
    # Usable means the target tests genuinely fail before anyone touches the code.
    if [ "$t" -gt 0 ] && [ "$p" -lt "$t" ]; then
      USABLE="$USABLE $idx"; checked=$((checked+1))
      printf 'usable (%s/%s passing)\n' "$p" "$t" >&2
    else
      printf 'UNUSABLE (%s/%s already passing)\n' "$p" "$t" >&2
    fi
  else
    printf 'UNUSABLE (environment did not build)\n' >&2
  fi
  rm -rf "$d"
  idx=$((idx+1))
done
NUSE=$(echo $USABLE | wc -w | tr -d ' ')
echo "  usable instances: $NUSE" >&2
[ "$NUSE" -gt 0 ] || { echo "no usable instances; nothing to measure" >&2; exit 1; }

# --- the runs ----------------------------------------------------------------------------------
for arm in $(echo "$ARMS_CSV" | tr ',' ' '); do
  for i in $USABLE; do
    id=$(jq -r ".[$i].instance_id" "$DATA")
    d="$ROOT/$arm-$id"
    if ! setup_repo "$i" "$d"; then
      printf '%s\t%s\t0\t0\t0\tsetup-failed\n' "$arm" "$id" >> "$RUNLOG"; rm -rf "$d"; continue
    fi
    install_arm "$arm" "$d"
    prob=$(jq -r ".[$i].problem_statement" "$DATA")
    if [ "$arm" = none ]; then pre=""; else pre="/debug "; fi
    ( cd "$d" && timeout 900 claude -p "${pre}Fix this bug in this repository. Change the source, not the tests.

$prob" --setting-sources=project --output-format=stream-json --verbose < /dev/null >/dev/null 2>&1 )
    read -r p t <<< "$(run_tests "$d" "$i")"
    [ "$t" -gt 0 ] && [ "$p" -eq "$t" ] && res=1 || res=0
    printf '%s\t%s\t%s\t%s\t%s\tok\n' "$arm" "$id" "$res" "$p" "$t" >> "$RUNLOG"
    printf '  %-8s %-34s resolved=%s (%s/%s)\n' "$arm" "$id" "$res" "$p" "$t" >&2
    rm -rf "$d"
  done
done

echo
echo "SWE-bench Lite — $NUSE usable instance(s) per arm"
echo
printf '%-8s %-12s %s\n' "arm" "resolved" "rate"
printf '%-8s %-12s %s\n' "--------" "------------" "------"
awk -F'\t' 'NR>1 && $6=="ok"{n[$1]++; r[$1]+=$3} END{for(a in n) printf "%-8s %-12s %.0f%%\n", a, r[a]"/"n[a], 100*r[a]/n[a]}' "$RUNLOG"
echo
echo "Resolved means every FAIL_TO_PASS test passes after the agent's patch. Instances whose"
echo "environment would not build, or whose tests already passed, were excluded before any arm"
echo "ran rather than counted as failures."
