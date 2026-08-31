#!/usr/bin/env bash
# falsify-parallel.sh — run tests/gate-falsifiability.sh across isolated clones, in parallel.
#
# The sweep is O(rows x checks): every row breaks one file, runs the WHOLE gate to see which
# check goes red, and restores. At 101 rows and a ~84s gate that is over two hours serially, and
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

# FALSIFY_TIMEOUT_S bounds this run's TOTAL wall clock, not just the wait loop: the comparison
# below reads $SECONDS, which counts from script start, so row derivation and workdir setup sit
# inside the bound. Stated because the printed verdict names this number. Without it, a sweep
# whose shards will never report (killed session, crashed shard, wedged clone) is indistinguishable
# from one still working -- the rc-collection loop had no bound and would sit forever. 0 disables
# the bound entirely; any other value is seconds.
FALSIFY_TIMEOUT_S=${FALSIFY_TIMEOUT_S:-3600}

# kill_tree PID -- kill PID and every descendant, leaves first.
#
# Not `pkill -f`: it matches unrelated processes on a shared box. Not `pgrep -P` (absent on
# busybox/Alpine) and not `kill -- -$$` (assumes every child stayed in the parent's process group,
# which job control does not guarantee once `wait` starts reaping). Walk the pid/ppid table by
# hand instead -- it needs nothing but `ps`, which is on every target this has to run on.
_ps_snapshot() {
  # -A/-e select every process on the box, not just ones on this controlling terminal -- a
  # backgrounded shard detaches from the tty the instant it's `&`'d. Some minimal `ps` builds
  # reject both flags; the bare form is the busybox fallback, which lists unfiltered by default.
  _snap=$(ps -A -o pid= -o ppid= 2>/dev/null)
  [ -z "$_snap" ] && _snap=$(ps -e -o pid= -o ppid= 2>/dev/null)
  [ -z "$_snap" ] && _snap=$(ps -o pid= -o ppid= 2>/dev/null)
  printf '%s\n' "$_snap"
}

kill_tree() {
  _kt_root="$1"
  [ -z "$_kt_root" ] && return 0
  _kt_snap=$(_ps_snapshot)
  [ -z "$_kt_snap" ] && return 0

  # Breadth-first collect every descendant. Each pid has exactly one ppid, so this can't double-add
  # a victim; a second call (idempotent by construction) is the recovery if the table moved
  # mid-walk and it missed one.
  _kt_frontier="$_kt_root"
  _kt_victims=""
  while [ -n "$_kt_frontier" ]; do
    _kt_next=""
    for _kt_p in $_kt_frontier; do
      _kt_children=$(printf '%s\n' "$_kt_snap" | awk -v p="$_kt_p" '$2==p{print $1}')
      for _kt_c in $_kt_children; do
        _kt_victims="$_kt_victims $_kt_c"
        _kt_next="$_kt_next $_kt_c"
      done
    done
    _kt_frontier="$_kt_next"
  done

  # Reverse so leaves die first -- killing a parent while its child is still alive risks the child
  # surviving unsignalled past this walk, since the walk only knows the tree as it looked at
  # snapshot time.
  _kt_reversed=""
  for _kt_v in $_kt_victims; do
    _kt_reversed="$_kt_v $_kt_reversed"
  done

  _kt_hit=0
  for _kt_v in $_kt_reversed; do kill -TERM "$_kt_v" 2>/dev/null && _kt_hit=1; done
  kill -TERM "$_kt_root" 2>/dev/null && _kt_hit=1
  # Nothing was alive to signal. That is the NORMAL path: this runs from the EXIT trap after
  # `wait` has already reaped every shard, so there is no one left to escalate against. Returning
  # here is what stops a successful sweep paying one second of sleep per shard -- seven seconds
  # added to every green run -- to SIGKILL processes that do not exist.
  [ "$_kt_hit" = 0 ] && return 0
  # A shard wedged inside its own cleanup can outlive TERM; escalate once after a short grace
  # period rather than leaving it for whoever finds it next (measured: one orphan alive 3h22m
  # against a comparable ~20-minute run).
  sleep 1
  for _kt_v in $_kt_reversed; do kill -KILL "$_kt_v" 2>/dev/null; done
  kill -KILL "$_kt_root" 2>/dev/null
  return 0
}

kill_all_shards() {
  for _p in $SHARD_PIDS; do
    kill_tree "$_p"
  done
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/falsify-parallel.XXXXXX") || exit 2
# Kill the shard tree BEFORE removing the workdir it's running inside -- the old trap deleted
# $WORK out from under live shards, which then kept burning CPU with their tree gone and nobody
# left to collect them. SHARD_PIDS is empty until the launch loop below sets it, so this is a
# no-op for any exit before shards exist.
SHARD_PIDS=""
_CLEANED=0
_cleanup() {
  [ "$_CLEANED" = 1 ] && return 0
  _CLEANED=1
  kill_all_shards
  rm -rf "$WORK"
}
# INT and TERM get their own handlers that EXIT. A single `trap ... EXIT INT TERM` runs the
# handler on a signal and then RESUMES the interrupted statement -- so Ctrl-C reaped the shards,
# deleted $WORK, and left this script polling for .rc files inside a directory it had just
# removed, until the timeout fired up to an hour later. The operator saw the sweep ignore their
# Ctrl-C. Nothing in a trap body stops the process unless it says so.
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM

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
  SHARD_PIDS="$SHARD_PIDS $!"
done

# A twenty-minute run that prints nothing is indistinguishable from a hung one, and the first
# thing anyone does with a silent long job is kill it. Report each shard as its rc lands, and
# also emit a heartbeat at least every 60s even when nothing has landed -- silence has to be
# distinguishable from work, not just from the last shard's perspective but from this loop's.
_seen=0
_last_heartbeat=$SECONDS
while [ "$_seen" -lt "$JOBS" ]; do
  if [ "$FALSIFY_TIMEOUT_S" -gt 0 ] && [ "$SECONDS" -ge "$FALSIFY_TIMEOUT_S" ]; then
    # Kill before printing: a NOT RUN verdict next to still-running shards is the same lie as the
    # old trap deleting $WORK out from under them -- the printed state and the real state must
    # agree at the moment this line hits stdout.
    kill_all_shards
    printf 'falsify-parallel: NOT RUN (timed out after %d s; %d/%d shard(s) reported)\n' \
      "$FALSIFY_TIMEOUT_S" "$_seen" "$JOBS"
    exit 2
  fi
  sleep 5
  for s in $(seq 0 $((JOBS-1))); do
    if [ -f "$WORK/shard-$s.rc" ] && [ ! -f "$WORK/shard-$s.seen" ]; then
      : > "$WORK/shard-$s.seen"
      _seen=$((_seen+1))
      printf '  shard %d done (rc=%s, %d/%d)\n' \
        "$s" "$(cat "$WORK/shard-$s.rc")" "$_seen" "$JOBS"
    fi
  done
  if [ "$_seen" -lt "$JOBS" ] && [ $((SECONDS - _last_heartbeat)) -ge 55 ]; then
    printf '  ... %ds elapsed, %d/%d shard(s) reported\n' "$SECONDS" "$_seen" "$JOBS"
    _last_heartbeat=$SECONDS
  fi
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
  # Three ways this one line was wrong, all found by running it over 3 rows before trusting it
  # with 96. `\|` alternation is a GNU extension and BSD sed matches it literally. The column
  # widths are NOT uniform -- gate-falsifiability.sh pads `ok` to four spaces and `FAIL`/`skip`
  # to two -- so a pattern with a literal two spaces matched only the failures and skips, and
  # this reconciliation could never once have gone green. And `grep -c` PRINTS 0 while EXITING 1
  # on no match, so a `|| echo 0` fallback emits two lines and the arithmetic fails on the second.
  # Match whitespace as whitespace: a reconciler keyed to a printf's column padding is one
  # cosmetic edit away from silently reporting that nothing ran.
  n=$(sed -E -n 's/^(ok|FAIL|skip)[[:space:]]+check[[:space:]]+([^[:space:]]+).*/\2/p' "$d.log" 2>/dev/null | tee -a "$WORK/reported" | wc -l | tr -d ' ')
  k=$(/usr/bin/grep -c '^skip  check ' "$d.log" 2>/dev/null); k=${k:-0}
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
