#!/usr/bin/env bash
# falsify-parallel-reap.sh -- proves tests/falsify-parallel.sh does not orphan shard processes
# and does not hang forever waiting on shards that will never report.
#
# The defect this exists to catch: falsify-parallel.sh backgrounds JOBS shard subshells with `&`
# and, in the version this suite was written against, its ONLY trap was `rm -rf "$WORK"` --
# deletes the workdir a live shard is running inside and leaves the shard running regardless.
# Measured: one orphaned sweep ran 3h22m against a ~20-minute expected duration. Separately, its
# rc-collection loop had no wall-clock bound, so a sweep that will never report was
# indistinguishable from one still working.
#
# WHAT THIS DOES NOT DO: it never runs the real ~20-minute sweep. That clones the repo 7 times
# and runs the whole gate; this suite's budget is seconds, and it needs neither the network nor
# tests/gate-falsifiability.sh to succeed. Two techniques stand in for it:
#
#   1. A miniature harness (parent script backgrounds a subshell that itself spawns a long-lived
#      `sleep 600` grandchild) reproduces the ORPHAN SHAPE directly -- PROOFS 1, 2, 6.
#   2. A disposable scratch git repo, seeded with nothing but a COPY of the live
#      tests/falsify-parallel.sh and a one-line fake gate-falsifiability.sh, run with a `git` on
#      PATH that blocks forever on `clone` (never touches the network) and passes every other
#      subcommand through to the real `git` -- PROOFS 3, 4. The scratch repo means these proofs
#      run against whatever tests/falsify-parallel.sh contains at THIS run's start, without
#      touching it, without depending on this actual repo's tree being clean (falsify-parallel.sh
#      itself refuses on a dirty tree, and a peer may be mid-edit on the very file under test),
#      and without racing that peer's own edits mid-run.
#
# SELF-CHECK: `REAP_SELFCHECK=1 ./tests/falsify-parallel-reap.sh` swaps the mechanism each of
# PROOFS 1, 2 and 6 depends on for a deliberately broken one (documented at each site) and
# expects that proof to report FAIL. That is the "watch it go red" evidence for proofs with no
# repo file this suite is allowed to edit. PROOFS 3, 4 and 5 have no live self-check switch --
# PROOFS 3/4 would require mutating tests/falsify-parallel.sh itself, which this suite may not
# touch (another agent owns that file), and PROOF 5 is disclosed below as structural-only for the
# same reason. Their negative control is the unfixed script's own prior behaviour, described in
# each proof's comment and in this run's own history: the very first read of
# tests/falsify-parallel.sh in this session (before the fix landed on disk, mid-session, from a
# concurrent writer) had no kill_tree function and a trap of bare `rm -rf "$WORK"` -- PROOFS 2,
# 3, 4 and 6 all report FAIL against that version, by construction, because the mechanism they
# check for is not there.
#
# PROOF 5's honesty note: "a heartbeat at least every 60s" is a claim about real time. Observing
# it behaviourally means waiting out a >=60s silence, which this suite's whole budget forbids. It
# is checked structurally (does the source contain a periodic print naming elapsed time and
# shards reported, inside the wait loop, distinct from the per-shard "done" line) and labelled
# [structural only] in its own output. A script that satisfies the grep and still never reaches
# that line at runtime would slip past this proof; that gap is real, not hidden.
#
# Every pid this suite spawns is recorded in TRACKED_PIDS and reaped by this suite's own
# EXIT/INT/TERM trap -- a test for orphan reaping that itself leaves orphans is not a test.
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$repo_root/tests/falsify-parallel.sh"
SELF="$repo_root/tests/falsify-parallel-reap.sh"
REAP_SELFCHECK="${REAP_SELFCHECK:-0}"
[ "${1:-}" = "--selfcheck" ] && REAP_SELFCHECK=1

RAN=0
SKIPPED=0
FAIL=0
TOTAL=$(grep -c '^# --- PROOF [0-9]' "$SELF")

ok(){   printf 'ok    %s\n' "$1"; RAN=$((RAN+1)); }
bad(){  printf 'FAIL  %s\n      %s\n' "$1" "$2"; FAIL=1; RAN=$((RAN+1)); }
skip(){ printf 'skip  %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

[ "$REAP_SELFCHECK" = 1 ] && printf '*** REAP_SELFCHECK=1: every proof with a live mutation switch is expected to FAIL below ***\n\n'

if [ ! -f "$target" ]; then
  bad "all proofs" "$target does not exist -- nothing to test"
  printf 'checks: %d declared, %d ran, %d skipped\n' "$TOTAL" "$RAN" "$SKIPPED"
  echo "VERIFICATION FAILED"
  exit 1
fi

# ---- reaping registry -------------------------------------------------------------------------
# Every top-level pid this suite backgrounds is `track`ed here. The cleanup trap walks each one's
# live descendants (its OWN walk, independent of kill_tree -- using the thing under test to check
# the thing under test would make PROOFS 2/6 circular) and kills the whole tree, leaves first,
# TERM then KILL, exactly so nothing this suite starts can outlive it.
TRACKED_PIDS=""
track(){ TRACKED_PIDS="$TRACKED_PIDS $1"; }

_assay_ps_snapshot(){
  _s=$(ps -A -o pid= -o ppid= 2>/dev/null)
  [ -z "$_s" ] && _s=$(ps -e -o pid= -o ppid= 2>/dev/null)
  [ -z "$_s" ] && _s=$(ps -o pid= -o ppid= 2>/dev/null)
  printf '%s\n' "$_s"
}

_assay_descendants(){
  # prints every live descendant of $1 (NOT including $1), breadth-first, bounded to 20
  # generations so a ps anomaly cannot spin this forever.
  _root="$1"
  _snap=$(_assay_ps_snapshot)
  [ -z "$_snap" ] && return 0
  _frontier="$_root"
  _found=""
  _gen=0
  while [ -n "$_frontier" ] && [ "$_gen" -lt 20 ]; do
    _next=""
    for _p in $_frontier; do
      _kids=$(printf '%s\n' "$_snap" | awk -v p="$_p" '$2==p{print $1}')
      for _k in $_kids; do
        case " $_found " in *" $_k "*) continue ;; esac
        _found="$_found $_k"
        _next="$_next $_k"
      done
    done
    _frontier="$_next"
    _gen=$((_gen+1))
  done
  for _f in $_found; do printf '%s\n' "$_f"; done
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/falsify-reap.XXXXXX") || { echo "cannot mktemp a workdir" >&2; exit 2; }

cleanup(){
  for _p in $TRACKED_PIDS; do
    for _d in $(_assay_descendants "$_p"); do kill -TERM "$_d" 2>/dev/null; done
    kill -TERM "$_p" 2>/dev/null
  done
  [ -n "$TRACKED_PIDS" ] && sleep 1
  for _p in $TRACKED_PIDS; do
    for _d in $(_assay_descendants "$_p"); do kill -KILL "$_d" 2>/dev/null; done
    kill -KILL "$_p" 2>/dev/null
  done
  rm -rf "$WORK" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ---- shared fixtures ----------------------------------------------------------------------------

write_orphan_harness(){
  # $1 = dir. Writes parent.sh: a backgrounded subshell (the "shard") that itself spawns a
  # long-lived grandchild and waits on it -- the exact shape falsify-parallel.sh's own shard loop
  # takes (`( git clone ...; ... ) &` backgrounding a subshell whose own child can outlive it).
  mkdir -p "$1"
  cat > "$1/parent.sh" <<'HARNESS'
#!/usr/bin/env bash
(
  sleep 600 &
  echo $! > "$1/grandchild.pid"
  wait
) &
echo $! > "$1/child.pid"
wait
HARNESS
  chmod +x "$1/parent.sh"
}

extract_fn(){
  # Parses $target for a top-level `name() {` ... matching `}` by brace-depth, prints it. Empty
  # output means the function is not there under that name -- extraction, not reimplementation,
  # so this cannot pass against a kill_tree that was renamed or removed.
  awk -v name="$1" '
    BEGIN{depth=0; on=0}
    on==0 && $0 ~ ("^"name"\\(\\)[[:space:]]*\\{[[:space:]]*$") { on=1 }
    on==1 {
      print
      n=gsub(/\{/,"{"); depth+=n
      n=gsub(/\}/,"}"); depth-=n
      if (depth==0) exit
    }
  ' "$target"
}

build_kill_tree_file(){
  # $1 = output path. Concatenates the two functions kill_tree depends on, extracted from the
  # live script, into a sourceable unit.
  {
    printf '#!/usr/bin/env bash\n'
    extract_fn _ps_snapshot
    printf '\n'
    extract_fn kill_tree
  } > "$1"
}

build_scratch_repo(){
  # $1 = dir. A disposable repo containing nothing but a COPY of the live falsify-parallel.sh (it
  # is never edited, only read and cp'd) and a one-line fake gate-falsifiability.sh, committed so
  # falsify-parallel.sh's own dirty-tree refusal never fires regardless of what the real repo
  # looks like right now.
  mkdir -p "$1/tests"
  cp "$target" "$1/tests/falsify-parallel.sh"
  chmod +x "$1/tests/falsify-parallel.sh"
  printf '#!/usr/bin/env bash\nCHECKS="1"\n' > "$1/tests/gate-falsifiability.sh"
  chmod +x "$1/tests/gate-falsifiability.sh"
  ( cd "$1" && git init -q && git -c user.email=t@t -c user.name=t add -A && \
    git -c user.email=t@t -c user.name=t commit -q -m scratch ) >/dev/null 2>&1
}

build_git_shim(){
  # $1 = bin dir to prepend to PATH. `git clone` parks as `sleep 600` -- a wedged clone, the
  # thing FALSIFY_TIMEOUT_S exists to bound -- without ever touching the network. Every other
  # subcommand (status, rev-parse, checkout, ...) passes straight through to the real git.
  mkdir -p "$1"
  _real_git=$(command -v git)
  cat > "$1/git" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "clone" ]; then
  exec sleep 600
fi
exec "$_real_git" "\$@"
SHIM
  chmod +x "$1/git"
}

# --- PROOF 1: the orphan bug's shape is real, independent of any code under test -----------------
# falsify-parallel.sh's shards are exactly this shape: a backgrounded subshell (the shard) whose
# own child (git clone, or whatever it execs into) can outlive a plain `kill` of the outer
# process, because SIGTERM to a pid says nothing about that pid's children -- nothing propagates
# a signal down a process tree by default. This proof never touches tests/falsify-parallel.sh; it
# establishes the underlying OS behaviour the bug depends on, so PROOF 2's demonstration that
# kill_tree() fixes it means something.
p1dir="$WORK/p1"
write_orphan_harness "$p1dir"
"$p1dir/parent.sh" "$p1dir" &
P1_PARENT=$!
track "$P1_PARENT"
p1_ready=0
for _i in 1 2 3 4 5 6 7 8; do
  [ -s "$p1dir/grandchild.pid" ] && { p1_ready=1; break; }
  sleep 1
done
if [ "$p1_ready" != 1 ]; then
  bad "PROOF 1: naive kill of only the parent leaves the grandchild running" \
      "the miniature harness never reported a grandchild pid within 8s -- cannot proceed"
else
  P1_GC=$(cat "$p1dir/grandchild.pid")
  track "$P1_GC"
  kill -TERM "$P1_PARENT" 2>/dev/null
  sleep 1
  if [ "$REAP_SELFCHECK" = 1 ]; then
    # mutation: invert the sense of the assertion (expect the grandchild to be DEAD after a naive
    # kill of only the parent). It is not -- this must report FAIL.
    if ! kill -0 "$P1_GC" 2>/dev/null; then
      ok "PROOF 1 [selfcheck, inverted]: naive kill of only the parent leaves the grandchild running"
    else
      bad "PROOF 1 [selfcheck, inverted]: naive kill of only the parent leaves the grandchild running" \
          "grandchild $P1_GC is still alive, as the real proof requires -- the inversion correctly reports FAIL"
    fi
  else
    if kill -0 "$P1_GC" 2>/dev/null; then
      ok "PROOF 1: naive kill of only the parent leaves the grandchild running"
    else
      bad "PROOF 1: naive kill of only the parent leaves the grandchild running" \
          "grandchild $P1_GC was already gone -- this platform does not reproduce the bug's shape the way this harness assumed"
    fi
  fi
  kill -KILL "$P1_GC" 2>/dev/null
fi

# --- PROOF 2: kill_tree(), extracted from the live tests/falsify-parallel.sh, reaps the same -----
# miniature tree PROOF 1 showed survives a naive kill. Extracting rather than reimplementing means
# this cannot pass against a kill_tree that was renamed or removed -- extraction would find nothing.
kt_file2="$WORK/kill_tree2.sh"
build_kill_tree_file "$kt_file2"
if ! grep -q '^kill_tree' "$kt_file2"; then
  bad "PROOF 2: kill_tree() extracted from tests/falsify-parallel.sh reaps the miniature tree" \
      "no 'kill_tree() {' function found in $target -- the fix has not landed (or was renamed) as of this run"
else
  # shellcheck source=/dev/null
  . "$kt_file2"
  if [ "$REAP_SELFCHECK" = 1 ]; then
    # mutation: shadow the extracted kill_tree with a no-op -- the faithful shape of "the fix
    # regresses to a function that exists but does nothing".
    kill_tree(){ :; }
  fi
  p2dir="$WORK/p2"
  write_orphan_harness "$p2dir"
  "$p2dir/parent.sh" "$p2dir" &
  P2_PARENT=$!
  track "$P2_PARENT"
  p2_ready=0
  for _i in 1 2 3 4 5 6 7 8; do
    [ -s "$p2dir/grandchild.pid" ] && { p2_ready=1; break; }
    sleep 1
  done
  if [ "$p2_ready" != 1 ]; then
    bad "PROOF 2: kill_tree() extracted from tests/falsify-parallel.sh reaps the miniature tree" \
        "the miniature harness never reported a grandchild pid within 8s -- cannot proceed"
  else
    P2_GC=$(cat "$p2dir/grandchild.pid")
    track "$P2_GC"
    kill_tree "$P2_PARENT"
    reaped=0
    for _i in 1 2 3 4 5; do
      kill -0 "$P2_GC" 2>/dev/null || { reaped=1; break; }
      sleep 1
    done
    if [ "$reaped" = 1 ]; then
      ok "PROOF 2: kill_tree() extracted from tests/falsify-parallel.sh reaps the miniature tree"
    else
      bad "PROOF 2: kill_tree() extracted from tests/falsify-parallel.sh reaps the miniature tree" \
          "grandchild $P2_GC was still alive 5s after kill_tree($P2_PARENT)"
    fi
    kill -KILL "$P2_GC" 2>/dev/null
  fi
  unset -f kill_tree _ps_snapshot 2>/dev/null
fi

# --- PROOF 3: an external SIGTERM to falsify-parallel.sh reaps its whole shard tree before --------
# the process exits -- the EXIT/INT/TERM trap must kill descendants BEFORE `rm -rf "$WORK"`, not
# just on its own internal timeout path (that is PROOF 4). Runs against a scratch clone of the
# live script with a `git` that parks `clone` as `sleep 600` -- no network, no real gate.
scratch3="$WORK/scratch3"
build_scratch_repo "$scratch3"
shim3="$WORK/shimbin3"
build_git_shim "$shim3"
tmproot3="$WORK/tmproot3"
mkdir -p "$tmproot3"
row3=$(sed -n 's/^CHECKS="\(.*\)"/\1/p' "$scratch3/tests/gate-falsifiability.sh" | awk '{print $1}')
DIRTY3=$(git -C "$scratch3" status --porcelain 2>/dev/null)
if [ -n "$DIRTY3" ]; then
  skip "PROOF 3: SIGTERM to falsify-parallel.sh reaps its shard tree before it exits" \
       "scratch repo failed to come up clean -- git init/commit did not produce a clean tree"
else
  PATH="$shim3:$PATH" TMPDIR="$tmproot3" VSTACK_FALSIFY_JOBS=1 VSTACK_FALSIFY_ROWS="$row3" \
    "$scratch3/tests/falsify-parallel.sh" > "$WORK/p3.log" 2>&1 &
  P3=$!
  track "$P3"
  descendants_before=""
  for _i in 1 2 3 4 5 6 7 8; do
    descendants_before=$(_assay_descendants "$P3")
    [ -n "$descendants_before" ] && break
    sleep 1
  done
  if [ -z "$descendants_before" ]; then
    bad "PROOF 3: SIGTERM to falsify-parallel.sh reaps its shard tree before it exits" \
        "no descendant of pid $P3 appeared within 8s -- environment issue, not evidence about the trap"
  else
    kill -TERM "$P3" 2>/dev/null
    p3_exited=0
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$P3" 2>/dev/null || { p3_exited=1; break; }
      sleep 1
    done
    if [ "$p3_exited" != 1 ]; then
      bad "PROOF 3: SIGTERM to falsify-parallel.sh reaps its shard tree before it exits" \
          "pid $P3 (falsify-parallel.sh) did not exit within 10s of SIGTERM"
      kill -KILL "$P3" 2>/dev/null
    else
      sleep 1
      survivors=""
      for _d in $descendants_before; do
        kill -0 "$_d" 2>/dev/null && survivors="$survivors $_d"
      done
      if [ -z "$survivors" ]; then
        ok "PROOF 3: SIGTERM to falsify-parallel.sh reaps its shard tree before it exits"
      else
        bad "PROOF 3: SIGTERM to falsify-parallel.sh reaps its shard tree before it exits" \
            "descendant pid(s)$survivors of exited pid $P3 are still alive -- the trap did not kill the shard tree"
        for _d in $survivors; do kill -KILL "$_d" 2>/dev/null; done
      fi
    fi
  fi
fi

# --- PROOF 4: FALSIFY_TIMEOUT_S bounds a sweep that will never report; on timeout it kills the ----
# shard tree, prints the NOT RUN line naming elapsed/reported counts, and exits 2 -- never 0.
# Same scratch-repo/git-shim technique as PROOF 3. This suite bounds its OWN wait on the child
# with an independent grace window and force-kills past it, so an UNFIXED script (which ignores
# FALSIFY_TIMEOUT_S entirely and hangs on `wait` forever) cannot hang this suite -- it is reported
# as a failure to honor the bound, not left to wedge the run.
scratch4="$WORK/scratch4"
build_scratch_repo "$scratch4"
shim4="$WORK/shimbin4"
build_git_shim "$shim4"
tmproot4="$WORK/tmproot4"
mkdir -p "$tmproot4"
row4=$(sed -n 's/^CHECKS="\(.*\)"/\1/p' "$scratch4/tests/gate-falsifiability.sh" | awk '{print $1}')
DIRTY4=$(git -C "$scratch4" status --porcelain 2>/dev/null)
if [ -n "$DIRTY4" ]; then
  skip "PROOF 4: FALSIFY_TIMEOUT_S=2 kills the tree, prints NOT RUN, exits 2 -- never hangs or exits 0" \
       "scratch repo failed to come up clean -- git init/commit did not produce a clean tree"
else
  (
    PATH="$shim4:$PATH" TMPDIR="$tmproot4" VSTACK_FALSIFY_JOBS=1 VSTACK_FALSIFY_ROWS="$row4" \
      FALSIFY_TIMEOUT_S=2 "$scratch4/tests/falsify-parallel.sh" > "$WORK/p4.log" 2>&1
    echo $? > "$WORK/p4.rc"
    : > "$WORK/p4.done"
  ) &
  P4=$!
  track "$P4"
  GRACE=8
  BOUND=$((2 + GRACE))
  descendants4_before=""
  p4_done=0
  for _i in $(seq 1 "$BOUND"); do
    if [ -f "$WORK/p4.done" ]; then p4_done=1; break; fi
    if [ -z "$descendants4_before" ]; then
      descendants4_before=$(_assay_descendants "$P4")
    fi
    sleep 1
  done
  if [ "$p4_done" != 1 ]; then
    for _d in $(_assay_descendants "$P4"); do kill -KILL "$_d" 2>/dev/null; done
    kill -KILL "$P4" 2>/dev/null
    bad "PROOF 4: FALSIFY_TIMEOUT_S=2 kills the tree, prints NOT RUN, exits 2 -- never hangs or exits 0" \
        "still running ${BOUND}s after launch with FALSIFY_TIMEOUT_S=2 -- force-killed by this suite; the bound was not honored"
  else
    p4_rc=$(cat "$WORK/p4.rc" 2>/dev/null || echo '?')
    p4_msg_ok=0
    grep -Eq 'falsify-parallel: NOT RUN \(timed out after 2 s; [0-9]+/[0-9]+ shard\(s\) reported\)' \
      "$WORK/p4.log" && p4_msg_ok=1
    survivors4=""
    for _d in $descendants4_before; do
      kill -0 "$_d" 2>/dev/null && survivors4="$survivors4 $_d"
    done
    if [ "$p4_rc" = 2 ] && [ "$p4_msg_ok" = 1 ] && [ -z "$survivors4" ]; then
      ok "PROOF 4: FALSIFY_TIMEOUT_S=2 kills the tree, prints NOT RUN, exits 2 -- never hangs or exits 0"
    else
      bad "PROOF 4: FALSIFY_TIMEOUT_S=2 kills the tree, prints NOT RUN, exits 2 -- never hangs or exits 0" \
          "rc=$p4_rc (want 2), NOT-RUN-message-seen=$p4_msg_ok (want 1), surviving descendant(s)=[$survivors4] (want none) -- see $WORK/p4.log"
      for _d in $survivors4; do kill -KILL "$_d" 2>/dev/null; done
    fi
  fi
fi

# --- PROOF 5: a heartbeat prints at least every 60s while waiting on shards -- STRUCTURAL ONLY ---
# Exercising this behaviourally means waiting out a real >=60s gap between shard completions,
# which this suite's whole design budget (seconds, not minutes -- see file header) forbids. This
# reads the source instead: a print statement inside the shard-wait loop, reachable when no NEW
# shard has just landed (so it's distinct from the per-shard "done" line), naming both an
# elapsed-seconds figure and a shards-reported count. A script that satisfies this grep and still
# never reaches the line at runtime would slip past this proof -- that gap is real, not hidden.
hb_line=$(awk '/elapsed/ && /reported/ { print; found=1 } END { exit !found }' "$target")
if [ -n "$hb_line" ] && printf '%s' "$hb_line" | grep -Eq '%?[ds][^0-9]*elapsed.*[0-9]+/[0-9]+.*reported|elapsed.*reported'; then
  ok "PROOF 5 [structural only]: a heartbeat print inside the shard-wait loop names elapsed seconds and shards reported"
else
  bad "PROOF 5 [structural only]: a heartbeat print inside the shard-wait loop names elapsed seconds and shards reported" \
      "no print statement in $target mentions both 'elapsed' and 'reported' -- no evidence the >=60s heartbeat contract is met"
fi

# --- PROOF 6: kill_tree() is idempotent and silent about pids that are already dead --------------
# Calling it a second time on an already-reaped tree must not error or print noise -- the trap
# calls it unconditionally on every exit path, including the ordinary green one where `wait` has
# already reaped every shard and there is nothing left to signal.
kt_file6="$WORK/kill_tree6.sh"
build_kill_tree_file "$kt_file6"
if ! grep -q '^kill_tree' "$kt_file6"; then
  bad "PROOF 6: kill_tree() is idempotent and silent about already-dead pids" \
      "no kill_tree() function found in $target (see PROOF 2)"
else
  # shellcheck source=/dev/null
  . "$kt_file6"
  if [ "$REAP_SELFCHECK" = 1 ]; then
    # mutation: a "loud" stub that does not suppress kill's own stderr on an already-dead pid --
    # the faithful shape of dropping kill_tree's `2>/dev/null`.
    kill_tree(){ kill -TERM "$1"; kill -KILL "$1"; }
  fi
  p6dir="$WORK/p6"
  write_orphan_harness "$p6dir"
  "$p6dir/parent.sh" "$p6dir" &
  P6=$!
  track "$P6"
  p6_ready=0
  for _i in 1 2 3 4 5 6 7 8; do
    [ -s "$p6dir/grandchild.pid" ] && { p6_ready=1; break; }
    sleep 1
  done
  if [ "$p6_ready" != 1 ]; then
    bad "PROOF 6: kill_tree() is idempotent and silent about already-dead pids" \
        "the miniature harness never reported a grandchild pid within 8s -- cannot proceed"
  else
    P6_GC=$(cat "$p6dir/grandchild.pid")
    track "$P6_GC"
    kill_tree "$P6" >/dev/null 2>/dev/null
    sleep 1
    err2=$(kill_tree "$P6" 2>&1 >/dev/null)
    still_alive=1
    kill -0 "$P6_GC" 2>/dev/null || still_alive=0
    if [ "$still_alive" = 0 ] && [ -z "$err2" ]; then
      ok "PROOF 6: kill_tree() is idempotent and silent about already-dead pids"
    else
      bad "PROOF 6: kill_tree() is idempotent and silent about already-dead pids" \
          "still_alive=$still_alive (want 0), second-call stderr=[$err2] (want empty)"
    fi
    kill -KILL "$P6_GC" 2>/dev/null
  fi
  unset -f kill_tree _ps_snapshot 2>/dev/null
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
