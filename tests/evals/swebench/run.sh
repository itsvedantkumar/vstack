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

N=3; HARD=0; ARMS_CSV="none,vstack,gstack"; PYVER="${PYVER:-3.11}"
while [ $# -gt 0 ]; do
  case "$1" in
    --n) N="$2"; shift 2 ;;
    --arms) ARMS_CSV="$2"; shift 2 ;;
    --hard) HARD=1; shift ;;
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
printf 'arm\tinstance\tresolved\tf2p_pass\tf2p_total\tstatus\tseconds\tp2p_broken\tp2p_total\n' > "$RUNLOG"
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
p2p_list() { jq -r ".[$1].PASS_TO_PASS | if type==\"string\" then fromjson else . end | .[0:5][]" "$DATA"; }
# The scoring pass samples wider than the pre-flight one. Pre-flight only needs enough signal to
# know the environment builds; scoring needs to know whether the patch broke anything.
p2p_score_list() { jq -r ".[$1].PASS_TO_PASS | if type==\"string\" then fromjson else . end | .[0:20][]" "$DATA"; }

# PASS_TO_PASS is the environment check, and leaving it out made every instance look usable.
#
# The gate was "do the target tests fail?" — which a completely broken environment also
# satisfies. One flask instance imported a werkzeug too new for it, so `from werkzeug.urls
# import url_quote` raised ImportError, every test failed, the instance was marked usable, and
# all three arms scored zero on a repository where flask could not be imported at all. Three
# identical zeroes look like a finding about the harnesses and were a finding about my setup.
#
# So a usable instance must ALSO have its PASS_TO_PASS tests passing: those are tests that
# already work, so if they fail the environment is broken rather than the code. A sample of
# five is enough to catch an import error without paying for the whole suite.
run_p2p_score() { # <dir> <index> -> "pass total", wider sample, used after the patch
  local d="$1" i="$2" pass=0 tot=0 t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tot=$((tot+1))
    ( cd "$d" && timeout 240 .venv/bin/python -m pytest -x -q "$t" >/dev/null 2>&1 ) && pass=$((pass+1))
  done < <(p2p_score_list "$i")
  printf '%s %s' "$pass" "$tot"
}

run_p2p() { # <dir> <index> -> "pass total"
  local d="$1" i="$2" pass=0 tot=0 t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tot=$((tot+1))
    ( cd "$d" && timeout 240 .venv/bin/python -m pytest -x -q "$t" >/dev/null 2>&1 ) && pass=$((pass+1))
  done < <(p2p_list "$i")
  printf '%s %s' "$pass" "$tot"
}

run_tests() { # <dir> <index> -> "pass total"
  local d="$1" i="$2" pass=0 tot=0 t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tot=$((tot+1))
    ( cd "$d" && timeout 240 .venv/bin/python -m pytest -x -q "$t" >/dev/null 2>&1 ) && pass=$((pass+1))
  done < <(f2p_list "$i")
  printf '%s %s' "$pass" "$tot"
}

# --- arm activation: global, one arm at a time, in the real home ----------------------------
#
# Isolation by time rather than by directory, and not by choice. Every attempt at directory
# isolation loses authentication: HOME=scratch, CLAUDE_CONFIG_DIR=scratch, and CLAUDE_CONFIG_DIR
# seeded with a copy of ~/.claude.json all return "Not logged in", because the CLI resolves its
# credentials against the real config dir. An unauthenticated arm scores zero and looks like a
# weak harness, which is benchmark bug 1 on this project's own list.
#
# gstack settles the question anyway. Its skills refer to ~/.claude/skills/gstack/bin/* about
# eighty-five times, its own `setup --local` prints "deprecated, use global install", and that
# flag rewrites those paths for Kiro only -- so a project-scope gstack is an arm whose every
# helper is `command not found`. Both harnesses are therefore installed the way their authors
# say to install them: globally, one at a time, with the machine restored in between.
#
# The machine is backed up once before anything moves and restored on any exit path.
MACHINE_BK="$ROOT/machine-backup"

# Only the directories an arm can occupy, not the whole config dir. Backing up ~/.claude wholesale
# copied 1.6 GB of plugin cache and session history, per run.
ARM_DIRS="skills agents commands hooks"

restore_machine() {
  [ -d "$MACHINE_BK" ] || return 0
  for _d in $ARM_DIRS; do
    rm -rf "$HOME/.claude/$_d"
    [ -d "$MACHINE_BK/$_d" ] && cp -R "$MACHINE_BK/$_d" "$HOME/.claude/$_d"
  done
  [ -f "$MACHINE_BK/settings.json" ] && cp "$MACHINE_BK/settings.json" "$HOME/.claude/settings.json"
  # Reinstall rather than trusting the copy: the wrappers under ~/.config/agents are outside the
  # backed-up set, and a restore that only put ~/.claude back left doctor reporting drift.
  ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || true
  printf 'machine restored\n' >&2
}

backup_machine() {
  mkdir -p "$MACHINE_BK"
  for _d in $ARM_DIRS; do
    [ -d "$HOME/.claude/$_d" ] && cp -R "$HOME/.claude/$_d" "$MACHINE_BK/$_d"
  done
  cp "$HOME/.claude/settings.json" "$MACHINE_BK/settings.json" 2>/dev/null
  trap restore_machine EXIT INT TERM
}

# Not ./uninstall.sh. That restores from the newest install backup, and because install.sh runs
# constantly here the newest backup contains vstack's own files -- measured: 28 skills before,
# 28 after. A deactivation that silently does nothing would have put vstack's skills on the
# gstack arm and produced a comparison of vstack against itself.
deactivate_all() {
  for _d in $ARM_DIRS; do rm -rf "$HOME/.claude/$_d"; mkdir -p "$HOME/.claude/$_d"; done
  if command -v jq >/dev/null 2>&1 && [ -f "$MACHINE_BK/settings.json" ]; then
    jq 'del(.hooks) | del(.skillOverrides) | del(.statusLine)' \
      "$MACHINE_BK/settings.json" > "$HOME/.claude/settings.json" 2>/dev/null || true
  fi
}

nskills() { find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

activate_arm() { # <arm>
  deactivate_all
  case "$1" in
    none) : ;;
    vstack) ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || return 1 ;;
    # Same install as vstack, with outputStyle forced back to Default. vstack ships Concise, so
    # the only variable between these two arms is the register the model writes in.
    vstack-default) ( cd "$SRC" && ./install.sh >/dev/null 2>&1 ) || return 1
                    jq '.outputStyle = "Default"' "$HOME/.claude/settings.json" > "$ROOT/s.json" \
                      && mv "$ROOT/s.json" "$HOME/.claude/settings.json" ;;
    gstack) ( cd "$GSTACK_DIR" && ./setup --quiet >/dev/null 2>&1 ) || return 1 ;;
  esac
  
  # Positive control. Every arm asserts that what it installed is actually there and that the
  # other arm is not, because a benchmark whose arms silently share a config dir compares one
  # harness against itself and prints a number anyway.
  local n; n=$(nskills)
  case "$1" in
    none)
      [ "$n" -eq 0 ] || { printf 'INVALID none: %s skill(s) still present after deactivation\n' "$n" >&2; return 1; } ;;
    vstack|vstack-default)
      local want; want=$(find "$SRC/claude/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
      [ "$n" -eq "$want" ] || { printf 'INVALID %s: %s skills installed, expected %s\n' "$1" "$n" "$want" >&2; return 1; }
      [ -d "$HOME/.claude/skills/gstack" ] && { printf 'INVALID %s: gstack is still installed\n' "$1" >&2; return 1; } ;;
    gstack)
      [ -d "$HOME/.claude/skills/gstack" ] || { printf 'INVALID gstack: its skills directory is absent after setup\n' >&2; return 1; }
      # The check whose absence let sixty gstack reviews be scored on a pathway with no helpers.
      local missing=0 q
      for q in bin/gstack-config bin/gstack-telemetry-log review/SKILL.md; do
        [ -e "$HOME/.claude/skills/gstack/$q" ] || missing=$((missing+1))
      done
      [ "$missing" -eq 0 ] || { printf 'INVALID gstack: %s declared helper path(s) missing\n' "$missing" >&2; return 1; } ;;
  esac
  printf 'arm %s active (%s user-scope skills)\n' "$1" "$n" >&2
  return 0
}

# --- selftest: exercise arm switching with no model calls --------------------------------------
#
# The expensive part of this benchmark is the model. The part most likely to be wrong is the arm
# switching, and it is free to test. Three defects were found this way before a single prompt was
# sent: a 1.6 GB per-run backup, a deactivation that left all 28 skills in place because
# ./uninstall.sh restores from the newest install backup, and a restore that put ~/.claude back
# but not the wrappers under ~/.config/agents, leaving doctor reporting drift.
if [ "${SELFTEST:-0}" = "1" ]; then
  fails=0
  before=$(nskills)
  printf 'before        %s skills\n' "$before"
  backup_machine
  printf 'backup        %s\n' "$(du -sh "$MACHINE_BK" 2>/dev/null | cut -f1)"
  for a in $(echo "$ARMS_CSV" | tr ',' ' '); do
    if activate_arm "$a"; then printf '  ok    %s\n' "$a"; else printf '  FAIL  %s\n' "$a"; fails=$((fails+1)); fi
  done
  restore_machine
  after=$(nskills)
  printf 'after restore %s skills\n' "$after"
  [ "$before" = "$after" ] || { printf '  FAIL  restore left %s skills, started with %s\n' "$after" "$before"; fails=$((fails+1)); }
  if "$SRC/bin/doctor" >/dev/null 2>&1; then printf '  ok    doctor green after restore\n'
  else printf '  FAIL  doctor is red after restore\n'; fails=$((fails+1)); fi
  [ "$fails" -eq 0 ] && { echo; echo "SELFTEST OK"; exit 0; } || { echo; echo "SELFTEST FAILED ($fails)"; exit 1; }
fi

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
    read -r pp pt <<< "$(run_p2p "$d" "$idx")"
    if [ "$t" -eq 0 ]; then
      printf 'UNUSABLE (no target tests)\n' >&2
    elif [ "$p" -ge "$t" ]; then
      printf 'UNUSABLE (target tests already pass)\n' >&2
    elif [ "$pt" -gt 0 ] && [ "$pp" -lt "$pt" ]; then
      # The decisive one: tests that are supposed to already pass do not, so the environment is
      # broken and any score from it would measure my setup rather than the agent.
      printf 'UNUSABLE (environment broken: %s/%s known-good tests fail)\n' "$((pt-pp))" "$pt" >&2
    else
      USABLE="$USABLE $idx"; checked=$((checked+1))
      printf 'usable (target %s/%s, known-good %s/%s)\n' "$p" "$t" "$pp" "$pt" >&2
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
# --- difficulty filter ------------------------------------------------------------------------
#
# --hard keeps only the instances unconfigured Claude Code cannot already solve.
#
# Without it the first run put four arms at 4/4 and told us nothing. Validity and difficulty are
# different filters: the pre-flight admits an instance whose environment builds and whose target
# tests genuinely fail, which says nothing about whether it is hard. A set every arm solves has no
# power to separate them, and reporting that as "no harness beat baseline" overstates it -- the
# honest statement is that the measurement could not tell.
#
# The baseline run is real work that also produces the baseline column, so nothing is wasted.
if [ "$HARD" = 1 ]; then
  backup_machine
  activate_arm none || { echo "cannot activate the baseline arm" >&2; exit 1; }
  KEEP=""
  for i in $USABLE; do
    id=$(jq -r ".[$i].instance_id" "$DATA")
    d="$ROOT/hard-$id"
    setup_repo "$i" "$d" || { rm -rf "$d"; continue; }
    ( cd "$d" && timeout 900 claude -p "Fix this bug in this repository. Change the source, not the tests.

$(jq -r ".[$i].problem_statement" "$DATA")" --setting-sources=project --permission-mode bypassPermissions \
        --output-format=stream-json --verbose < /dev/null >/dev/null 2>&1 )
    read -r p t <<< "$(run_tests "$d" "$i")"
    read -r pp pt <<< "$(run_p2p_score "$d" "$i")"
    if [ "$t" -gt 0 ] && [ "$p" -eq "$t" ] && [ "$((pt - pp))" -eq 0 ]; then
      printf '  baseline solved %-34s excluded as too easy\n' "$id" >&2
    else
      printf '  baseline failed %-34s kept\n' "$id" >&2
      KEEP="$KEEP $i"
    fi
    rm -rf "$d"
  done
  USABLE="$KEEP"
  NUSE=$(printf '%s' "$USABLE" | wc -w | tr -d ' ')
  printf 'hard set: %s instance(s) the baseline could not solve\n' "$NUSE" >&2
  [ "$NUSE" -gt 0 ] || { echo "no instances survived the difficulty filter; widen --n" >&2; exit 1; }
fi

backup_machine
for arm in $(echo "$ARMS_CSV" | tr ',' ' '); do
  if ! activate_arm "$arm"; then
    printf '%s\tINVALID\t0\t0\t0\tarm-not-installable\t0\n' "$arm" >> "$RUNLOG"
    printf 'skipping %s: not installable on this machine\n' "$arm" >&2
    continue
  fi
  printf '== arm %s active ==\n' "$arm" >&2
  for i in $USABLE; do
    id=$(jq -r ".[$i].instance_id" "$DATA")
    d="$ROOT/$arm-$id"
    if ! setup_repo "$i" "$d"; then
      printf '%s\t%s\t0\t0\t0\tsetup-failed\n' "$arm" "$id" >> "$RUNLOG"; rm -rf "$d"; continue
    fi
    prob=$(jq -r ".[$i].problem_statement" "$DATA")
    case "$arm" in none) pre="" ;; *) pre="/debug " ;; esac
    # --permission-mode bypassPermissions, or this measures the wrong thing entirely.
    #
    # Without it the first three runs scored 0/4 for every arm. The agent was calling Edit and
    # the calls were being denied: in headless mode with no project settings, the default
    # permission mode prompts, there is nobody to answer, and the write silently does not happen.
    # The repository was untouched at the end of every run, so the benchmark was measuring "can
    # this agent write a file" — the answer being no, identically, for all three arms — rather
    # than "can it fix the bug".
    #
    # Three identical zeroes have now been a bug in this harness three separate times. They are
    # worth treating as a defect report about the scaffolding until proven otherwise.
    t0=$(date +%s)
    ( cd "$d" && timeout 900 claude -p "${pre}Fix this bug in this repository. Change the source, not the tests.

$prob" --setting-sources=project --permission-mode bypassPermissions \
        --output-format=stream-json --verbose < /dev/null >/dev/null 2>&1 )
    secs=$(( $(date +%s) - t0 ))
    read -r p t <<< "$(run_tests "$d" "$i")"
    # Collateral damage. run_p2p existed and only ever ran in pre-flight, so a patch that fixed
    # the target test by breaking four others scored exactly the same as one that did not. That
    # is the difference a review phase is supposed to make, and nothing was measuring it.
    read -r pp pt <<< "$(run_p2p_score "$d" "$i")"
    broke=$((pt - pp))
    [ "$t" -gt 0 ] && [ "$p" -eq "$t" ] && [ "$broke" -eq 0 ] && res=1 || res=0
    printf '%s\t%s\t%s\t%s\t%s\tok\t%s\t%s\t%s\n' "$arm" "$id" "$res" "$p" "$t" "$secs" "$broke" "$pt" >> "$RUNLOG"
    printf '  %-14s %-34s resolved=%s (f2p %s/%s, broke %s of %s p2p) %ss\n' \
      "$arm" "$id" "$res" "$p" "$t" "$broke" "$pt" "$secs" >&2
    # Unresolved runs are kept. Deleting them left nothing to inspect when every arm scored zero,
    # which is exactly when you need to look at what the agent actually did.
    if [ "$res" = 1 ]; then rm -rf "$d"; else rm -rf "$d/.venv"; fi
  done
done

echo
echo "SWE-bench Lite — $NUSE usable instance(s) per arm"
echo
printf '%-15s %-12s %-8s %-10s %s\n' "arm" "resolved" "rate" "median s" "p2p broken"
printf '%-15s %-12s %-8s %-10s %s\n' "---------------" "------------" "------" "--------" "----------"
awk -F'\t' 'NR>1 && $6=="ok"{n[$1]++; r[$1]+=$3; s[$1]=s[$1]" "$7; b[$1]+=$8}
  END{for(a in n){k=split(s[a],v," ");
    for(x=1;x<k;x++)for(y=1;y<=k-x;y++)if(v[y]+0>v[y+1]+0){z=v[y];v[y]=v[y+1];v[y+1]=z}
    printf "%-15s %-12s %-8s %-10s %s\n", a, r[a]"/"n[a], sprintf("%.0f%%",100*r[a]/n[a]), v[int((k+1)/2)], b[a]+0}}' "$RUNLOG"
echo
echo "Resolved means every FAIL_TO_PASS test passes AND no sampled PASS_TO_PASS test regressed."
echo "A patch that fixes the target by breaking neighbours is not a fix. Instances whose"
echo "environment would not build, or whose tests already passed, were excluded before any arm"
echo "ran rather than counted as failures."
