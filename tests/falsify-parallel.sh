#!/usr/bin/env bash
# falsify-parallel.sh — run tests/gate-falsifiability.sh across isolated clones, in parallel.
#
# The sweep is O(rows x checks): every row breaks one file, runs the WHOLE gate to see which
# check goes red, and restores. At 94 rows and a ~84s gate that is over two hours serially, and
# it is the single slowest thing anyone waits for in this repository. CI has shared it 7 ways
# since v1.55.0 and finishes in about 18 minutes; this is the same split, locally.
#
# ISOLATION IS NOT AN OPTIMISATION HERE. Every row mutates a tracked file in place and restores
# it afterwards. Two sweeps sharing one tree would each see the other's mutation as a concurrent
# edit, and the suite's own restore-integrity guard would refuse to restore -- correctly, since
# it cannot tell whose bytes it is about to overwrite. So each shard gets its own clone.
#
# Usage:
#   ./tests/falsify-parallel.sh            # 7 shards, matching CI
#   VSTACK_FALSIFY_JOBS=4 ./tests/falsify-parallel.sh
#
# Exit codes: 0 every row passed and every declared row was accounted for; 1 a row failed or the
# reconciliation found a row no shard ran; 2 the run could not be set up (dirty tree, no rows).
set -u

SRC=$(cd "$(dirname "$0")/.." && pwd)
cd "$SRC" || exit 2
JOBS=${VSTACK_FALSIFY_JOBS:-7}

# A clone carries HEAD, not your working tree. Running the sweep against a dirty tree would
# produce a verdict about a commit rather than about the files you are looking at, and print it
# without ever saying so -- which is the exact shape of defect this suite exists to catch. Refuse.
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  printf 'REFUSING: the working tree is dirty, and a clone would test HEAD instead.\n'
  printf 'A verdict about a different tree than the one you are looking at is not evidence.\n'
  printf 'Commit or stash first:\n%s\n' "$DIRTY"
  exit 2
fi
SHA=$(git rev-parse HEAD)

# The one derivation. Same sed CI's falsify-plan uses and the same line check 16 of the gate
# polices, so a row added to CHECKS= lands in some shard here on its very next run.
# VSTACK_FALSIFY_ROWS scopes the run to a subset, the same spelling gate-falsifiability.sh takes,
# passed straight through to each shard. Without it, every row runs.
if [ -n "${VSTACK_FALSIFY_ROWS:-}" ]; then
  ROWS="$VSTACK_FALSIFY_ROWS"
else
  ROWS=$(sed -n 's/^CHECKS="\(.*\)"/\1/p' tests/gate-falsifiability.sh)
fi
NROWS=0
for _r in $ROWS; do NROWS=$((NROWS+1)); done
if [ "$NROWS" -eq 0 ]; then
  printf 'REFUSING: no CHECKS="..." row list found in tests/gate-falsifiability.sh -- nothing to run.\n'
  exit 2
fi
[ "$JOBS" -gt "$NROWS" ] && JOBS=$NROWS

WORK=$(mktemp -d "${TMPDIR:-/tmp}/falsify-parallel.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

printf 'falsify-parallel: %d rows over %d shard(s), %s\n\n' "$NROWS" "$JOBS" "${SHA%${SHA#???????}}"

# Round-robin (index i -> shard i % JOBS): a total function over the list, so every index lands
# in exactly one shard with no remainder bucket to forget about.
i=0
for _r in $ROWS; do
  s=$((i % JOBS))
  printf '%s ' "$_r" >> "$WORK/ids.$s"
  i=$((i+1))
done

for s in $(seq 0 $((JOBS-1))); do
  if [ ! -s "$WORK/ids.$s" ]; then
    printf 'REFUSING: shard %d would run zero rows (%d shards for %d rows).\n' "$s" "$JOBS" "$NROWS"
    exit 2
  fi
done

for s in $(seq 0 $((JOBS-1))); do
  ids=$(cat "$WORK/ids.$s")
  d="$WORK/shard-$s"
  (
    git clone -q "$SRC" "$d" 2>/dev/null && git -C "$d" checkout -q --detach "$SHA" 2>/dev/null || {
      printf 'clone failed\n' > "$d.log"; echo 2 > "$d.rc"; exit 0; }
    # A private TMPDIR per shard, not just a private tree. The shipped hooks keep per-session
    # state under ${TMPDIR:-/tmp} -- skill-mandate.sh's block counter, dispatch-counter.sh's
    # dispatch count, their lock directories -- so shards with separate checkouts still collide
    # there, and so does any unrelated process on the machine that drives a hook. Measured: five
    # of seven shards refused at baseline with "FAIL skill mandate decides correctly" while two
    # test suites elsewhere on this box were invoking the same hooks. .claude/verify.sh:829 wrote
    # this lesson down for one check ("with a shared TMPDIR and a fixed session id"); it applies
    # to the whole sweep.
    mkdir -p "$d.tmp"
    ( cd "$d" && TMPDIR="$d.tmp" VSTACK_FALSIFY_ROWS="$ids" ./tests/gate-falsifiability.sh ) > "$d.log" 2>&1
    echo $? > "$d.rc"
  ) &
done

# A twenty-minute run that prints nothing is indistinguishable from a hung one, and the first
# thing anyone does with a silent long job is kill it. Report each shard as its rc lands.
_seen=0
while [ "$_seen" -lt "$JOBS" ]; do
  sleep 5
  for s in $(seq 0 $((JOBS-1))); do
    if [ -f "$WORK/shard-$s.rc" ] && [ ! -f "$WORK/shard-$s.seen" ]; then
      : > "$WORK/shard-$s.seen"
      _seen=$((_seen+1))
      printf '  shard %d done (rc=%s, %d/%d)\n' \
        "$s" "$(cat "$WORK/shard-$s.rc")" "$_seen" "$JOBS"
    fi
  done
done
wait

# Reconciliation. A shard that dies early exits nonzero and is caught by the rc check, but a
# shard that runs a SUBSET of its ids and still exits 0 would not be -- and N shards each green
# over a partial list is precisely the failure this repository exists to catch. So the ids the
# shards themselves REPORTED are collected and diffed against the derived list. This re-derives
# nothing: it reads the output, not the plan.
: > "$WORK/reported"
FAILED=0; RAN=0; SKIPPED=0
for s in $(seq 0 $((JOBS-1))); do
  d="$WORK/shard-$s"; rc=$(cat "$d.rc" 2>/dev/null || echo 99)
  n=$(sed -n 's/^\(ok\|FAIL\|skip\)  check \([^ ]*\) .*/\2/p' "$d.log" 2>/dev/null | tee -a "$WORK/reported" | wc -l | tr -d ' ')
  k=$(/usr/bin/grep -c '^skip  check ' "$d.log" 2>/dev/null || echo 0)
  RAN=$((RAN+n)); SKIPPED=$((SKIPPED+k))
  if [ "$rc" -ne 0 ]; then
    FAILED=$((FAILED+1))
    printf 'SHARD %d  rc=%s  %d row(s) reported\n' "$s" "$rc" "$n"
    sed -n '/^FAIL/,+3p' "$d.log" | sed 's/^/    /'
  else
    printf 'shard %d  ok    %d row(s) reported, %s skipped\n' "$s" "$n" "$k"
  fi
done

MISSING=""
for _r in $ROWS; do
  /usr/bin/grep -qxF "$_r" "$WORK/reported" || MISSING="$MISSING $_r"
done

printf '\n%d rows declared, %d reported by shards, %d skipped, %d shard(s) failed\n' \
  "$NROWS" "$RAN" "$SKIPPED" "$FAILED"

if [ -n "$MISSING" ]; then
  printf 'FAIL  reconciliation: %s ran in no shard -- the sweep did not cover what it declared\n' \
    "${MISSING# }"
  exit 1
fi
if [ "$FAILED" -ne 0 ]; then
  printf 'NOT FALSIFIABLE (%d shard(s) failed; logs above)\n' "$FAILED"
  exit 1
fi
printf 'FALSIFIABLE (%d rows, %d shards, every declared row accounted for)\n' "$NROWS" "$JOBS"
