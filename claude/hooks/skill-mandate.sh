#!/usr/bin/env bash
# Stop: refuse to finish when the session did work that a skill is mandated for and never ran it.
#
# vstack already tells the model how to route: the SessionStart digest spells out "any prose you
# write -> unslop", and the skill descriptions carry their own triggers. Both are instructions,
# and an instruction is a probability. Measured over 12 prompts the routing lands, but "lands most
# of the time" is not the same claim as "always", and the second one is the one worth having.
#
# This closes the gap for the few rules where the situation is decidable from the transcript
# rather than from judgement. It reads what the session actually did -- which files were written,
# which skills were invoked -- and blocks Stop when a mandate went unmet. Nothing here guesses at
# intent: if the rule cannot be decided by looking at tool calls, it does not belong in this file.
#
# Escape hatch: VSTACK_NO_MANDATE=1 disables it entirely. A gate you cannot turn off gets deleted
# by the first person it inconveniences, which is worse than one that is on by default.
#
# This also logs one line per Stop to a delegation-drift log (see the "delegation-drift logger"
# comment below for the schema, rotation, and what it deliberately does not record) --
# VSTACK_NO_DELEGATION_LOG=1 disables that alone, same shape and same reasoning as the mandate's
# own escape hatch. VSTACK_DELEGATION_LOG overrides where it writes.
set -uo pipefail

[ "${VSTACK_NO_MANDATE:-0}" = "1" ] && exit 0

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi
# Without jq there is no way to read the transcript path or emit a block reason safely. Say
# nothing rather than guess: a mandate that misfires is worse than one that abstains.
[ -n "$JQ" ] || exit 0

input=$(cat 2>/dev/null || true)

# Claude Code sets this when Stop already fired once for this turn. Blocking again from inside a
# block is how a hook turns into an infinite loop.
[ "$(printf '%s' "$input" | "$JQ" -r '.stop_hook_active // false')" = "true" ] && exit 0

tr_=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty')
[ -n "$tr_" ] && [ -f "$tr_" ] || exit 0

sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty'); [ -n "$sid" ] || sid="pid$PPID"
cnt_file="${TMPDIR:-/tmp}/vstack-mandate-$sid"
lock_dir="$cnt_file.lock"
# Stop hooks from the same session can fire concurrently (parallel sub-agents finishing at once),
# and read-cat-then-write-echo on cnt_file is a classic unlocked read-modify-write: ten racing
# invocations all read the same starting count, each computes its own +1, and the last write
# wins -- the counter undercounts and the 2-strike cap never engages, so every invocation blocks
# instead of latching open after 2. Ported verbatim from verify-gate.sh's lock: `mkdir` is atomic
# on every POSIX filesystem (exactly one caller sees it succeed), which needs no GNU flock and no
# coreutils on stock macOS. A lock older than 30s is assumed abandoned by a killed sibling rather
# than honored forever, so a crash can't wedge the gate shut.
# `stat -f` is "file status" on BSD/macOS and "FILESYSTEM status" on GNU coreutils and BusyBox,
# where it ignores %m, prints five lines about the mount, and exits 0 -- so the familiar
# `stat -f %m || stat -c %Y` never falls through on Linux and hands the caller a paragraph where
# it asked for an integer. Measured 2026-08-28 in alpine and postgres:16 containers. GNU first,
# because `stat -c` on macOS is a usage error (rc=1, empty output), which is the honest failure
# the `||` was written for. The digit guard is the part that matters: it rejects anything that is
# not a bare integer, whatever exited 0. verify.sh check 55 executes this function against a stub
# of each documented platform, and finds it by name -- keep the name.
mtime_of() { # <path> -> epoch seconds, or 0 when it cannot be read
  _m=$(stat -c %Y "$1" 2>/dev/null) || _m=""
  case "$_m" in ""|*[!0-9]*) _m=$(stat -f %m "$1" 2>/dev/null) ;; esac
  case "$_m" in ""|*[!0-9]*) _m=0 ;; esac
  printf '%s\n' "$_m"
}
lock_acquired=0
i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    # `find -mmin` was tried first and dropped because some `find` implementations (e.g. bfs)
    # reject fractional minute arguments outright.
    lm=$(mtime_of "$lock_dir")
    now=$(date +%s)
    if [ "$lm" -gt 0 ] && [ $((now - lm)) -ge 30 ]; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    i=0
  fi
  sleep 0.02 2>/dev/null || sleep 1
done
lock_acquired=1
trap '[ "$lock_acquired" = 1 ] && rmdir "$lock_dir" 2>/dev/null' EXIT

# One shared writer for both the latched (below) and the full (bottom of file) delegation-drift
# log rows, so the append+rotate mechanics exist in exactly one place instead of two copies free
# to drift apart. Takes the fully-built JSON object as $1 and does nothing else -- callers decide
# what goes in the object, this only decides where it lands and when it rotates.
_delegation_log_row() {
  log_file="${VSTACK_DELEGATION_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-delegation-log.jsonl}"
  # Parameter expansion instead of `$(dirname ...)`: one fewer forked process on the path every
  # single Stop takes. `${log_file%/*}` strips the last /-segment; if log_file itself had no "/"
  # at all, the expansion leaves it unchanged, so the explicit fallback to "." matches what
  # dirname would have printed for a bare filename.
  log_dir_="${log_file%/*}"
  [ "$log_dir_" = "$log_file" ] && log_dir_="."
  mkdir -p "$log_dir_" 2>/dev/null
  printf '%s\n' "$1" >> "$log_file" 2>/dev/null
  # Rotation: capped at ~2MB. The check on every write is one `stat` call for the file's byte
  # size -- O(1), not a line count. Only once that cap is crossed does this pay to rewrite the
  # file, keeping the last 5000 lines (roughly 250-500KB at this schema's width) and dropping the
  # rest -- a sawtooth bounded at ~2MB, not an unbounded file.
  sz=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
  case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
  if [ "$sz" -gt 2097152 ]; then
    tail -n 5000 "$log_file" > "$log_file.rot" 2>/dev/null && mv "$log_file.rot" "$log_file" 2>/dev/null
  fi
}

# Monotonic per-session Stop counter for the delegation-drift logger (tests/delegation-drift.sh).
# Lives under the same lock as $cnt_file for the same reason: concurrent Stop invocations racing
# an unlocked read-modify-write would produce duplicate or skipped indices.
#
# Advances on EVERY Stop that reaches this point, latched or not. It used to advance only once
# the 2-strike latch below had been checked, on the theory that it then "counts Stops where the
# mandate was actually evaluated" -- which sounded right and was wrong in the population that
# matters: it meant this counter, and the log row it feeds, went silent forever the instant a
# session tripped the mandate twice, which is exactly the long, multi-directory session the log
# exists to measure. Confirmed against this machine's real installs: per-session cnt files existed
# in $TMPDIR for real session UUIDs, but not one had a matching ckpt file -- every real session
# that reached cnt>=2 stopped producing rows, and only short-lived fixtures (which never latch)
# were logging at all. Moved above the latch so a latched session still gets an index and a row
# (below); only the transcript-driven mandate evaluation itself stays gated on the latch, because
# that parse is the actual cost the latch exists to skip once the session can no longer be blocked
# by it anyway.
ckpt_file="${TMPDIR:-/tmp}/vstack-mandate-ckpt-$sid"
ckpt=$(cat "$ckpt_file" 2>/dev/null || echo 0)
ckpt=$((ckpt + 1))
printf '%s' "$ckpt" > "$ckpt_file" 2>/dev/null

# Per-mandate latch (coordinator-directed, replacing the two SHARED family counters above).
# f4f5468 already proved a shared counter bleeds across unrelated mandates -- measured, not
# theorized: skill-mandate's original single $cnt hit 2 within a session's first two evaluated
# Stops and silenced the UNRELATED delegation breadth mandate for the remaining 7 Stops of a real
# 64-minute, 90-dispatch, 36-directory session, latched:true with every count null the whole way.
# That commit split skill-vs-delegation into two counters. It did not split further: within the
# skill family, unslop/typescript-best-practices/prove-it-works still shared ONE counter, so two
# unrelated unslop misses disarmed typescript-best-practices and prove-it-works for the rest of
# the session even though neither had ever been tried, let alone failed -- the identical bleed,
# one level down. Same shape inside the delegation family once swarm became a third sibling of
# breadth/agent-naming on $dcnt: two naming strikes would have silenced the swarm mandate this
# release exists to add. Every mandate below now gets its own counter file and its own 2-strike
# cap, so tripping one never silences another.
#
# The cap itself is UNCHANGED at 2, and the reason is unchanged too: a mandate the model
# genuinely cannot satisfy (the Skill tool itself broken, or a skill file missing/corrupt) must
# not trap the session in an unbounded block-retry loop -- proven by simulation in 4693558 (the
# verify-gate latch this file's design was copied from): 5 Stops against an always-failing check
# produced exactly 3 blocks then silence once the counter was made to persist instead of reset.
# VSTACK_NO_MANDATE=1 is printed in every block reason as the escape hatch, but it needs an
# operator to act on it -- env vars set inside one Bash tool_use do not persist to the next
# Bash call in Claude Code's execution model, so the model cannot reliably self-administer it
# mid-session. The 2-strike cap is what actually bounds the wedge when nobody is there to read
# the escape-hatch line. Splitting the counter narrows WHICH mandate goes quiet after 2 misses;
# it does not touch whether it does, or when.
#
# Filenames: still "$cnt_file" (== "vstack-mandate-$sid") as the base, one distinct suffix per
# mandate on top of it, same convention the original $cnt_file.delegate split already used -- so
# anything that already sweeps "$cnt_file*" (tests/test-breadth-mandate.sh's sweep_latch_, and
# check 27's own cleanup glob "vstack-mandate-*vfy-[a-q]*", which is anchored loosely enough on
# both ends to already cover any suffix appended after the session id) keeps sweeping every one
# of these without needing to know the new names:
#   skill family (session-persistent, no window):
#     $cnt_file.unslop  $cnt_file.typescript  $cnt_file.proveitworks  $cnt_file.register
#   delegation family (windowed, cnt+timestamp pair per mandate):
#     $cnt_file.delegate-breadth(-ts)  $cnt_file.delegate-naming(-ts)  $cnt_file.delegate-swarm(-ts)
# $cnt_file.delegate-scan (the re-scan cooldown) and $cnt_file.lock stay singular and family-wide
# -- neither one is a strike counter, both exist purely to bound how often the expensive
# transcript scan itself runs, which is a family-wide cost regardless of which member mandate
# would have paid for it.
# Bash `read` builtin, not `cat`: reading a counter file this way costs zero process forks --
# `read -r v < "$file"` opens and consumes the file entirely inside the current shell, where
# `v=$(cat "$file")` pays for both a subshell (to capture the command substitution) AND a
# separate `cat` exec. That difference is the whole reason this is written this way instead of
# the more obvious cat-based one-liner: nine of these run every Stop now (six mandates, three of
# them windowed with a paired timestamp file), where the shared-counter design before this only
# ever paid for three. Measured, not assumed: the first cat-based draft of this block landed
# skill-mandate.sh's own fork-cost mean at 24.15u against tests/hook-latency.sh's 24.6u budget --
# technically under, but close enough that a noisier run could tip it red for a reason that has
# nothing to do with what the hook actually decided. `read`'s own error message on a missing
# input file would otherwise leak to stderr; `2>/dev/null` must sit BEFORE the `<` redirection on
# the same simple command, because redirections attach left to right and the failure happens
# while opening `<` itself, before a later `2>/dev/null` would take effect.
_read_cnt() { # <file> -> sets $_rc to a sanitized non-negative integer, 0 if missing/garbage
  _rc=""
  read -r _rc 2>/dev/null < "$1" || _rc=0
  case "$_rc" in ''|*[!0-9]*) _rc=0 ;; esac
}
_read_wcnt() { # <cntfile> <tsfile> <now> <window_secs> -> sets $_rc, windowed reset applied
  _read_cnt "$1"; _wc=$_rc
  _read_cnt "$2"; _wt=$_rc
  if [ "$_wt" -gt 0 ] && [ "$3" -gt 0 ] && [ $(( $3 - _wt )) -ge "$4" ]; then _wc=0; fi
  _rc=$_wc
}

now_d=$(date +%s 2>/dev/null || echo 0)
DELEGATE_RESET_SECS="${VSTACK_DELEGATE_RESET_SECS:-1800}"

# Skill family, same windowed re-arm the delegation family below already uses. A plain
# _read_cnt latched each of these to 0 evaluations for the rest of the session after two
# misses -- measured over ten real sessions, that retired every skill mandate early and is
# the mechanical cause of "the gate stops triggering". The window lets a latched mandate
# re-arm after SKILL_RESET_SECS instead of dying for hours; delegation has run this way since
# 1.63.0 without over-firing (21 blocks / 628 turns), so the cadence is already calibrated.
SKILL_RESET_SECS="${VSTACK_SKILL_RESET_SECS:-1800}"
_read_wcnt "$cnt_file.unslop"       "$cnt_file.unslop-ts"       "$now_d" "$SKILL_RESET_SECS"; cnt_unslop=$_rc
_read_wcnt "$cnt_file.typescript"   "$cnt_file.typescript-ts"   "$now_d" "$SKILL_RESET_SECS"; cnt_typescript=$_rc
_read_wcnt "$cnt_file.proveitworks" "$cnt_file.proveitworks-ts" "$now_d" "$SKILL_RESET_SECS"; cnt_proveitworks=$_rc
_read_wcnt "$cnt_file.register"     "$cnt_file.register-ts"     "$now_d" "$SKILL_RESET_SECS"; cnt_register=$_rc
_read_wcnt "$cnt_file.delegate-breadth" "$cnt_file.delegate-breadth-ts" "$now_d" "$DELEGATE_RESET_SECS"; cnt_breadth=$_rc
_read_wcnt "$cnt_file.delegate-naming" "$cnt_file.delegate-naming-ts" "$now_d" "$DELEGATE_RESET_SECS"; cnt_naming=$_rc
_read_wcnt "$cnt_file.delegate-swarm" "$cnt_file.delegate-swarm-ts" "$now_d" "$DELEGATE_RESET_SECS"; cnt_swarm=$_rc
_read_wcnt "$cnt_file.delegate-serial" "$cnt_file.delegate-serial-ts" "$now_d" "$DELEGATE_RESET_SECS"; cnt_serial=$_rc

eval_unslop=1;       [ "$cnt_unslop" -ge 2 ]       && eval_unslop=0
eval_typescript=1;   [ "$cnt_typescript" -ge 2 ]   && eval_typescript=0
eval_proveitworks=1; [ "$cnt_proveitworks" -ge 2 ] && eval_proveitworks=0
eval_register=1;     [ "$cnt_register" -ge 2 ]     && eval_register=0
eval_breadth=1;      [ "$cnt_breadth" -ge 2 ]      && eval_breadth=0
eval_naming=1;       [ "$cnt_naming" -ge 2 ]       && eval_naming=0
eval_swarm=1;        [ "$cnt_swarm" -ge 2 ]        && eval_swarm=0
eval_serial=1;       [ "$cnt_serial" -ge 2 ]       && eval_serial=0

# Second, SHORTER gate: how often to bother re-scanning at all once every skill-family mandate is
# already latched, independent of whether delegation has struck. Family-exhausted alone is not a
# sufficient skip condition on its own -- a session that is skill-latched but NEVER
# breadth-eligible (a long single-directory prose session that tripped unslop twice and then
# just keeps writing more prose in the same directory) would have every delegation counter stuck
# at 0 (nothing to strike on) and would otherwise fail the "family exhausted" test forever,
# paying the full transcript scan on literally every remaining Stop of the session -- the exact
# regression this file's own sampling-rejection comment (further down) was written to avoid.
# $dscan_file records the last time a full scan ran for delegation's sake AT ALL (met or unmet,
# struck or not, regardless of which of the three delegation mandates); once skill mandates are
# latched, a scan within the last $VSTACK_DELEGATE_SCAN_COOLDOWN_SECS (default 60s) is skipped.
dscan_file="$cnt_file.delegate-scan"
_read_cnt "$dscan_file"; dscan=$_rc
DELEGATE_SCAN_COOLDOWN_SECS="${VSTACK_DELEGATE_SCAN_COOLDOWN_SECS:-60}"
dscan_recent=0
if [ "$dscan" -gt 0 ] && [ "$now_d" -gt 0 ] && [ $((now_d - dscan)) -lt "$DELEGATE_SCAN_COOLDOWN_SECS" ]; then
  dscan_recent=1
fi

# Family-level flags, derived from the per-mandate flags above by OR (ANY member of the
# family still has headroom): used ONLY for the top-level scan-skip decision below and for the
# turn_json/prove-it-works cost gate further down, never for deciding whether an individual
# mandate contributes to $unmet -- each mandate's own eval_* flag alone decides that now.
skill_eval=1
[ "$eval_unslop" = 0 ] && [ "$eval_typescript" = 0 ] && [ "$eval_proveitworks" = 0 ] && [ "$eval_register" = 0 ] && skill_eval=0
deleg_eval=1
[ "$eval_breadth" = 0 ] && [ "$eval_naming" = 0 ] && [ "$eval_swarm" = 0 ] && [ "$eval_serial" = 0 ] && deleg_eval=0

# Combined latch: skip the transcript-driven evaluation entirely only when NEITHER family can
# still act on it. skill_eval=1 alone is enough to keep paying for the scan every Stop, unchanged
# from before. Once skill_eval=0 (every skill-family mandate individually latched), the scan
# still runs if delegation has a mandate with strikes left in the current $DELEGATE_RESET_SECS
# window AND was not just looked at within $DELEGATE_SCAN_COOLDOWN_SECS -- both conditions
# bounded, so this can never accumulate into "every Stop forever". The delegation-drift log
# still gets a row for this Stop when both are exhausted -- it just cannot carry
# dir_count/ext_count/task_count/fanout_batches/named, same reasoning as before.
#
# fanout_batches null here, same as its five siblings: a missing FIELD (older schema, before this
# key existed) means "predates the field"; a null VALUE here means "this checkpoint was latched,
# never evaluated"; a 0 (only ever written below, on an evaluated checkpoint) means "evaluated,
# and no 2+-in-one-message batch was found". A reader that treats null and 0 as the same fact
# would report a fake decline in fan-out at exactly the sessions that were never measured.
if [ "$skill_eval" = 0 ] && { [ "$deleg_eval" = 0 ] || [ "$dscan_recent" = 1 ]; }; then
  if [ "${VSTACK_NO_DELEGATION_LOG:-0}" != "1" ]; then
    (
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
      row=$("$JQ" -cn --arg sid "$sid" --argjson ckpt "${ckpt:-0}" --arg ts "$ts" \
        '{session_id:$sid, checkpoint_index:$ckpt, dir_count:null, ext_count:null, task_count:null, task_fail_count:null, fanout_batches:null, named:null, latched:true, ts:$ts}')
      _delegation_log_row "$row"
    ) 2>/dev/null
  fi
  exit 0
fi

# Per-mandate hit flags: which mandates actually added to $unmet this Stop. skill_hit/deleg_hit
# (family-level ORs of these) still feed the delegation-drift logger's own latched:true/false
# bookkeeping further down, unchanged in that one role.
hit_unslop=0
hit_typescript=0
hit_proveitworks=0
hit_register=0
hit_breadth=0
hit_naming=0
hit_swarm=0
hit_serial=0

# We are doing a full scan this Stop for at least one reason (skill_eval=1 or deleg_eval=1 --
# the latch above already exited otherwise). Record it now, unconditionally, so the cooldown
# gate above sees an up to date "last looked" time on the very next Stop regardless of what this
# one finds.
date +%s > "$dscan_file" 2>/dev/null

# Sampling was considered here and rejected: on every k-th latched checkpoint, pay for the full
# transcript-driven evaluation above (real dir_count/ext_count/task_count/named) instead of the
# null-count row, so the exact population that never contributes to the drift analyser (latched,
# long, multi-directory sessions) would start contributing real breadth data 1 Stop in k.
#
# Rejected on measurement, not on principle. The 116ms figure that made this look affordable was
# measured on a single-line synthetic transcript, which is not what a latched session's transcript
# looks like -- a latched session is definitionally a long one. Timing the SAME full-evaluation
# path this hook already runs (the mandates below, unlatched) against two real transcripts already
# on this machine:
#   17.5MB / 1593 assistant turns: mean 1438ms, p50 1435ms, p95 1536ms, max 1536ms  (n=10)
#   39.1MB / larger session      : mean 2009ms, p50 2002ms, p95 2114ms, max 2114ms  (n=10)
# roughly 12-17x the synthetic estimate, because the mandates below don't read the transcript
# once -- $paths, $skills, $bash_cmds, task_count, and turn_json are each their own jq/awk pass
# over the whole file. At k=10 the amortized mean (~144-200ms) would still look tolerable next to
# the ~16ms this fix already accepted for the null-count row, but a Stop hook runs synchronously
# in the one moment a long session is trying to end, and the number that matters there is the
# tail, not the mean: 1 latched Stop in 10 would synchronously stall that exact moment by 1.4-2.1s,
# on exactly the sessions this file exists not to trap. That is a user-visible regression traded
# for data on an instrument (tests/delegation-drift.sh) whose own live run the same day measured
# needing >=8 eligible windows per tertile against 2-3 available -- more rows at this per-row cost
# would not have closed that gap by the next release either.
#
# Revisit only with new evidence, not new arithmetic: a measured (not estimated) full-evaluation
# cost against this file's own real transcript population that lands under, say, 200ms at p99 for
# k=10 would change this. Guessing from the single-line-synthetic number again is what produced
# the wrong estimate the first time.

# Every file this session wrote or edited, and every skill it invoked. Both come from the
# transcript, so this measures what happened rather than what was asked for.
paths=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="NotebookEdit"))
            | .input.file_path // empty' "$tr_" 2>/dev/null | sort -u
)
skills=$(
  "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' "$tr_" 2>/dev/null \
  | sed 's/.*://' | sort -u
)

# Write/Edit/NotebookEdit tool_use blocks are not the only way a session changes a file. In
# bypass-permissions mode the model is explicitly told to prefer Bash -- sed, heredocs, short
# scripts -- over the dedicated Edit/Write tools, and every one of those edits was invisible to
# every mandate above: a v1.35.0 release cut six files across five directories and three
# extensions entirely through `sed -i` and `python3 - <<PY` heredocs, and the breadth mandate
# never fired. This scans every Bash tool_use block's .input.command for a bounded set of write
# patterns and folds anything it recognizes into $paths below it, so the breadth mandate (and,
# as a side effect, the prose/TypeScript ones, which key off the same $paths) see Bash-mediated
# edits the same way they see Edit/Write ones.
#
# Recognized, in order: `sed -i` / `sed -i.bak` (the last whitespace-separated argument is taken
# as the target file); `>` / `>>` / `&>` output redirection and `tee [-a]` (this also covers
# `cat > path <<EOF`-style heredoc writers, since it is the redirect that is matched, not the
# heredoc body); `cp` / `mv` (the last non-flag argument is taken as the destination); and Python
# `open(PATH, 'w'...)` / `'a'...` / `'x'...` calls with a literal string path, anywhere in the
# command text -- which is what a `python3 - <<'PY' ... PY` heredoc writer looks like once jq has
# flattened it to one string.
#
# Residual blind spots, left uncaught on purpose rather than chased with more regex:
#   - a quoted path containing a space truncates at the first space (`> "a b.txt"` yields `a`)
#   - a `sed -i` / `cp` / `mv` / `tee` invocation naming more than one target file only yields
#     the last one (`sed -i '' -e s/a/b/ x.sh y.sh` sees only y.sh)
#   - commands invoked by full path (`/bin/cp`, `/usr/bin/sed -i`), via `sudo`, `xargs`, `eval`,
#     `find -exec`, or with a `VAR=val cmd` prefix are not recognized as the command at all
#   - a Python write via a variable, an f-string, `pathlib.Path(...).write_text(...)`, or any
#     open() call whose path is not a literal string is invisible
#   - `touch`, `mkdir`, `install`, `rsync`, `dd`, and redirection to a process substitution or an
#     fd number are not treated as writes
#   - a literal `>` inside a quoted string earlier on the same line (`echo "a > b" > out`) can be
#     misread as its own redirect target -- this is the price of not tokenizing the shell, and it
#     is a false *addition* to $paths, not a false mandate-met: it can only make the breadth
#     mandate name a Bash line it otherwise would not have, never suppress one that is real
#   - the same trap in the mirror: `[[ "$x" > "$y" ]]` and `[ "$a" > "$b" ]` are lexicographic
#     string comparisons, not redirects, and the redirect scan cannot tell the difference -- it
#     reads `$y`/`$b` off as a write target. This used to be dismissed here as inert noise on the
#     theory that a bare `$var` has neither `/` nor `.` to supply a second directory or extension
#     on its own. That theory was wrong, measured against a real 15MB transcript: combined with
#     heredoc-body leakage (below), unexpanded-`$` candidates were not inert, they were the
#     dominant term behind a reported 53 directories / 83 extensions for a session that had
#     written one real file. `emit()` now drops any candidate containing `$` outright rather
#     than trusting it to stay harmless -- cheap, and it removes this whole family in one place
#     regardless of which rule produced the candidate.
#   - a line inside an open heredoc body is skipped entirely (tracked by the in_hd/hd_delim state
#     machine in emit()'s caller), so `cat > new-check.sh <<'EOF'` counts only new-check.sh, not
#     every `>`/`cp`/`mv`/`open()`-shaped line the generated script's own body happens to contain.
#     Before this, a test-fixture generator that wrote fixture code containing its own example
#     `printf ... > path` was read as this session performing that write too -- the other half of
#     the 53/83 measurement above. Residual within this fix: two heredocs opened on the same
#     physical line, or a delimiter line that also carries trailing content after it, are not
#     modeled -- both are rare enough in practice that chasing them was not worth it here.
#   - a same-line `>` used as a comparison/arithmetic/format-string character *outside* a heredoc
#     body -- `awk '{if (a>b) ...}'`, a `printf` format token like `%.3f` that happens to follow a
#     stray `>` earlier on the line -- is still misread as a redirect target exactly as before.
#     Suppressing heredoc bodies removed most of this family's real-world volume (it is what most
#     of these lines were embedded in), and the survivors are short, extension-poor, non-slash
#     tokens (`9.9`, `1{print`, `>>>>>`) that read the same way the existing extension-less-token
#     analysis above already argues is bounded -- left as a known, disclosed miss rather than
#     chased with a real shell tokenizer, which this file has never tried to be.
# None of this is a shell parser. It is a best-effort net over write shapes that are actually
# common in this repo's own history, traded deliberately against reads: `grep`, `cat`, `ls`,
# `git add`, `find` without `-delete`, and command substitution never match any rule below, so
# ordinary read-heavy Bash work stays silent -- a guard that cries wolf on reads gets disabled.
bash_write_paths=""
AWK_BIN=""
if [ -x /usr/bin/awk ]; then AWK_BIN=/usr/bin/awk
elif command -v awk >/dev/null 2>&1; then AWK_BIN=$(command -v awk); fi
if [ -n "$AWK_BIN" ]; then
  bash_cmds=$(
    "$JQ" -r 'select(.type=="assistant") | .message.content[]?
              | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' "$tr_" 2>/dev/null
  )
  if [ -n "$bash_cmds" ]; then
    # emit() is the one gate every extracted candidate passes through before it can become a
    # path: empty, and -- new -- anything still carrying an unexpanded shell variable. A path
    # like $g_empty/app/src/C.tsx never resolved to a real file; it is a fixture literal (this
    # repo writes exactly that shape in its own test-generator scripts) or a template a later
    # command substitutes into, and either way this hook has no value to substitute it with, so
    # counting it as a directory/extension is pure noise, not a conservative guess.
    #
    # Heredoc-body suppression is the second half. `cat > new-check.sh <<'CHK' ... CHK` writes
    # exactly one real file -- new-check.sh, captured by the `>` rule on the opening line, same
    # as always -- but every line *inside* that heredoc's body is script source being written
    # to disk, not a command running in this turn. Before this fix the same `>>?` / `cp`/`mv`
    # regexes ran over body lines too, so a generated test fixture that itself contained
    # `printf ... > "$g_empty/app/src/C.tsx"` or `mv .github/workflows/verify.yml /tmp/...`
    # inside its own body text was read as a second, third, fourth real write by *this*
    # session -- confirmed against a real 15MB transcript, where it was the dominant term
    # behind a reported 53 directories / 83 extensions that should have been ~1. The state
    # machine below tracks whether the current physical line is inside an open heredoc body
    # (in_hd) and skips all extraction there, resuming only once a line equal to the opening
    # delimiter (optionally indented, for `<<-`) is seen. It does not attempt to track nested
    # heredocs inside a body -- while in_hd, every line is skipped outright, including one that
    # looks like it opens another heredoc, which is correct: it is body text either way, and the
    # only delimiter that matters is the outer one already being waited for.
    #
    # A here-string (`cmd <<<"$x"`) does not falsely open heredoc-suppression: after consuming
    # `<<` plus an optional `-` plus optional spaces, the next character is still the third `<`,
    # which matches neither the stripped-quote branch nor a bareword delimiter, so the match
    # fails and in_hd is never set. A bitshift (`$((1 << 3))`) fails the same way -- the char
    # after `<<` is a digit, not `[A-Za-z_]`. Checked by hand against both shapes before shipping.
    #
    # Suppression only engages when the SAME physical line also matched one of the write rules
    # above (line_had_write) -- this is not incidental, it is the line separating an inert
    # heredoc from an executed one. `cat > file <<EOF` and `tee file <<EOF` both write the body
    # to a file verbatim; the body never runs, so any `>`/`cp`/`open()`-shaped text inside it
    # describes what the generated file contains, not what this Bash call did. `python3 - <<PY`
    # and `bash <<EOF`, by contrast, pipe the body to an interpreter that executes it immediately
    # in this same tool call -- neither line matches any write rule on its own (no redirect, no
    # cp/mv, nothing), so line_had_write is 0 and the body is scanned normally, meaning
    # `open("config/c.json", "w")` inside that body is still counted, correctly, as a real write.
    # Gating on line_had_write rather than on the presence of `<<` alone is what tells these two
    # shapes apart without knowing what command is on the line -- the first version of this fix
    # suppressed both alike and silently broke the one fixture (test-breadth-mandate.sh PROOF 5)
    # that depends on a `python3 - <<PY` heredoc's write being seen.
    bash_write_extract='
    function emit(f) {
      if (f == "" || f ~ /\$/) return
      print f
    }
    BEGIN { in_hd = 0; hd_delim = "" }
    {
      line = $0
      line_had_write = 0
      if (in_hd) {
        d = line
        gsub(/^[ \t]+/, "", d)
        if (d == hd_delim) { in_hd = 0; hd_delim = "" }
        next
      }
      if (match(line, /(^|[;&|]| )sed[ \t]+-i[^ \t]*[ \t]+/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        if (n >= 1) {
          f = toks[n]
          gsub(/^["'"'"']|["'"'"';]+$/, "", f)
          if (f !~ /^-/) emit(f)
        }
      }
      work = line
      while (match(work, />>?[ \t]*[^ \t;&|)]+/)) {
        line_had_write = 1
        tgt = substr(work, RSTART, RLENGTH)
        work = substr(work, RSTART + RLENGTH)
        sub(/^>>?[ \t]*/, "", tgt)
        gsub(/^["'"'"']|["'"'"']$/, "", tgt)
        if (tgt !~ /^&/ && tgt !~ /^\/dev\//) emit(tgt)
      }
      if (match(line, /(^|[;&|]| )tee[ \t]+(-a[ \t]+)?/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        for (i = 1; i <= n; i++) {
          t = toks[i]
          if (t ~ /^-/) continue
          gsub(/^["'"'"']|["'"'"']$/, "", t)
          emit(t)
          break
        }
      }
      if (match(line, /(^|[;&|]| )(cp|mv)[ \t]+/)) {
        line_had_write = 1
        rest = substr(line, RSTART + RLENGTH)
        n = split(rest, toks, /[ \t]+/)
        if (n >= 2) {
          f = toks[n]
          gsub(/^["'"'"']|["'"'"']$/, "", f)
          if (f !~ /^-/) emit(f)
        }
      }
      s = line
      while (match(s, /open\([ \t]*["'"'"'][^"'"'"']+["'"'"'][ \t]*,[ \t]*["'"'"'][waxWAX][^"'"'"']*["'"'"']/)) {
        line_had_write = 1
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        if (match(m, /["'"'"'][^"'"'"']+["'"'"']/)) {
          emit(substr(m, RSTART + 1, RLENGTH - 2))
        }
      }
      if (line_had_write && match(line, /<<-?[ \t]*/)) {
        rest2 = substr(line, RSTART + RLENGTH)
        gsub(/^["'"'"']/, "", rest2)
        if (match(rest2, /^[A-Za-z_][A-Za-z0-9_]*/)) {
          hd_delim = substr(rest2, RSTART, RLENGTH)
          in_hd = 1
        }
      }
    }
    '
    bash_write_paths=$(printf '%s\n' "$bash_cmds" | "$AWK_BIN" "$bash_write_extract" 2>/dev/null | sort -u)
  fi
fi
# Fold into the same $paths every mandate below reads, so a Bash-mediated write counts exactly
# like a Write/Edit/NotebookEdit one everywhere downstream -- breadth, prose, and TypeScript alike.
[ -n "$bash_write_paths" ] && paths=$(printf '%s\n%s' "$paths" "$bash_write_paths" | sed '/^$/d' | sort -u)

fired(){ printf '%s\n' "$skills" | grep -qxF "$1"; }

unmet=""
# --- the mandates -----------------------------------------------------------------------------
# Each one needs a situation decidable from a tool call, and a skill that is the answer to it
# every single time. That second half is the strict part: a rule that is right nine times out of
# ten belongs in the digest as guidance, not here as a gate.

# Prose. Any Markdown that is not a machine-written log or a vendored file.
prose=$(printf '%s\n' "$paths" | grep -iE '\.(md|mdx)$' \
        | grep -viE '(CHANGELOG\.md|node_modules|\.audit/|/(dist|build|vendor)/)' | head -5)
if [ "$eval_unslop" = 1 ] && [ -n "$prose" ] && ! fired unslop; then
  unmet="$unmet
  unslop -- you wrote prose and it never ran: $(printf '%s' "$prose" | tr '\n' ' ')"
  hit_unslop=1
fi

# TypeScript. Reading one is judgement; writing one is not.
ts=$(printf '%s\n' "$paths" | grep -E '\.(ts|tsx)$' | grep -v node_modules | head -5)
if [ "$eval_typescript" = 1 ] && [ -n "$ts" ] && ! fired typescript-best-practices; then
  unmet="$unmet
  typescript-best-practices -- you wrote TypeScript and it never ran: $(printf '%s' "$ts" | tr '\n' ' ')"
  hit_typescript=1
fi

# Multi-directory, multi-type work without delegation. Detects work that spans parts by
# measuring breadth: distinct parent directories AND distinct file extensions. Both must be
# present to trigger, avoiding false blocks on mechanical repetition.
#
# Why not count files? Because 5 test fixtures (fixtures/case1.json through case5.json) is
# 1 directory and 1 extension — mechanical repetition, not multi-part work. But a real change
# (hook.sh, test/hook.test.sh, doc/HOOK.md, manifest.json) spans 4 directories and 3 types —
# that is work with parts, and is what subagents exist for.
#
# Edge cases that stay silent by design:
# - 6 .md files across 6 directories: 6 dirs, 1 extension → no block (single type is focused).
# - 10 .js files in src/: 1 directory, 1 extension → no block (single directory is cohesive).
# - 3 dotfiles (.editorconfig, .gitignore, .npmrc) across 3 dirs: 3 dirs, 0 extensions → no block.
#
# Dotfile handling: a file starting with . and containing no further . has no extension
# (it is pure name, not name + type). .eslintrc.json yields json; .eslintrc yields nothing.
#
# Dispatch-tool name: the subagent-launch tool is called "Task" in the classic Claude Code CLI
# and "Agent" in the Claude Agent SDK build this hook was actually dogfooded against -- a real
# 15MB transcript logged 70 "Agent" tool_use blocks and zero "Task" ones, which meant this
# counter read 0 and both the delegation mandate and the agent-naming mandate below misfired on
# every session running that build: the former claimed "zero subagents" over 70 of them, the
# latter (gated on task_count>=1) was structurally unable to ever fire. Counting both names is
# not future-proofed against a third rename; a build using neither counts 0 and this hook falls
# back to its existing bias (say nothing rather than guess) rather than accusing a session that
# genuinely delegated under a name this file does not yet know.
#
# "TaskCreate" is deliberately NOT included here. It exists in this same build and looked like a
# third dispatch-tool alias at a glance, but its recorded .input is {subject, description,
# activeForm} -- a todo/checklist item, the same shape as TodoWrite -- not {prompt,
# subagent_type} like Task/Agent. Counting it would credit a session for delegating work it only
# planned. Confirmed against 3 real transcripts on this machine before excluding it, not assumed.
task_count=$( "$JQ" -s '[.[] | select(.type=="assistant") | .message.content[]?
            | select(.type=="tool_use" and (.name=="Task" or .name=="Agent"))] | length' "$tr_" 2>/dev/null )
case "$task_count" in ''|*[!0-9]*) task_count=0 ;; esac

# fanout_batches: the piece task_count cannot answer -- did any TWO OR MORE of those dispatches
# actually run concurrently, or were they N separate serial delegations the model happened to
# make one after another? task_count alone cannot tell "one subagent, dispatched three times"
# from "three subagents in one batch", and the breadth mandate below used to gate on task_count
# alone -- satisfied by a single Task call, exactly the failure mode this splits out.
#
# What actually runs concurrently in Claude Code is every tool_use block inside ONE assistant
# message: the harness executes them together and returns their results in the next user turn,
# not one Task at a time. So the unit that matters is "how many Task/Agent blocks shares one
# message", not "how many exist in the transcript". Two ways that unit shows up on disk, both
# handled here:
#   - a fixture (and some transcript writers) puts a whole message's content array on ONE JSONL
#     line -- N tool_use blocks in that one line's .message.content are unambiguously one batch.
#   - a real streaming Claude Code CLI transcript splits one message's content blocks across
#     MULTIPLE, immediately consecutive JSONL lines that all share the same .message.id --
#     confirmed against this machine's own 5b14be87 session (see the "dogfooded" comment above):
#     msg_011CeHz4AqmXQiL4T85zgdpg's content (thinking, text, 3x tool_use) landed as 5 back-to-
#     back lines, not one.
# Grouping is done by CONSECUTIVE-run, not by a global "group by message.id": the same session
# has 8 message.id values that reappear thousands of lines apart after a compaction/resume,
# each reappearance surrounded by entirely different assistant lines in between -- a global
# group-by would silently merge two unrelated real turns' dispatches into one inflated batch.
# uniq-style consecutive grouping (a run ends the moment the id changes, even if that same id
# value shows up again later) keeps those two turns separate, which matched this file's own
# adjacency check line for line. A null/missing .message.id (every fixture in this suite, and
# any transcript writer that never sets one) is never merged with a neighbor even if adjacent --
# there is no identity to merge on, so each such line is its own singleton batch. That is what
# makes "two Task calls in two separate lines, neither carrying an id" read as two batches of
# one, not one batch of two: the exact serial-loop shape this fix exists to catch.
# One pass, two numbers: "<fanout_batches> <serial_tail>". serial_tail is the count of
# Task/Agent dispatches AFTER the last 2+-in-one-message batch (all of them when no batch ever
# ran). fanout_batches answers "did a real batch ever happen"; serial_tail answers the question
# it structurally cannot: "what has happened SINCE". A whole-transcript batch count amnesties
# every later serial dispatch -- measured, not hypothesized: session 3ce9f899 batched 3 times
# early and then made 25 one-at-a-time dispatches with the breadth mandate silenced for good,
# and 8959d943 did the same behind 2 batches of 2. The serial-tail mandate below reads only the
# suffix, so history cannot pay for the present.
fanout_calc=$( "$JQ" -sr '
  ( [ .[] | select(.type=="assistant")
      | { id: (.message.id // null),
          n: ( [ .message.content[]? | select(.type=="tool_use" and (.name=="Task" or .name=="Agent")) ] | length ) } ]
  ) as $entries
  | ( reduce $entries[] as $e
        ( {runs: [], cid: null, cn: 0, first: true};
          if .first then
            {runs: [], cid: $e.id, cn: $e.n, first: false}
          elif ($e.id != null and $e.id == .cid) then
            . + {cn: (.cn + $e.n)}
          else
            {runs: (.runs + [{id: .cid, n: .cn}]), cid: $e.id, cn: $e.n, first: false}
          end
        )
    ) as $folded
  | ( $folded.runs + [{id: $folded.cid, n: $folded.cn}] ) as $all_runs
  | ( $all_runs | map(.n) ) as $ns
  | ( [ range(0; $ns|length) | select($ns[.] >= 2) ] | last ) as $lastb
  | ( [ $ns[] | select(. >= 2) ] | length ) as $batches
  | ( (if $lastb == null then $ns else $ns[($lastb+1):] end) | add // 0 ) as $tail
  | "\($batches) \($tail)"
' "$tr_" 2>/dev/null | tail -n 1 )
fanout_batches=${fanout_calc%% *}
serial_tail=${fanout_calc##* }
case "$fanout_batches" in ''|*[!0-9]*) fanout_batches=0 ;; esac
case "$serial_tail" in ''|*[!0-9]*) serial_tail=0 ;; esac

# task_fail_count: of those same Task/Agent dispatches, how many resolved with is_error==true on
# their tool_result. This is the field the delegation-drift ledger was missing entirely -- it
# could say a session dispatched N subagents, never whether any of them actually failed. A
# tool_use's result lands in a LATER "user"-type transcript entry, correlated by
# tool_use.id == tool_result.tool_use_id -- the same correlation tests/compaction-effect.py
# already relies on for its own is_error rate (confirmed there against real transcripts, not
# assumed here). A dispatch whose result never shows up at all (killed mid-run, or this Stop
# fired before the result landed) is not counted as failed -- absence of evidence is not
# evidence of failure, and this must never overclaim a rate it cannot see.
task_fail_count=$( "$JQ" -s '
    ( [.[] | select(.type=="assistant") | .message.content[]?
        | select(.type=="tool_use" and (.name=="Task" or .name=="Agent")) | .id] ) as $ids
    | [ .[] | select(.type=="user") | .message.content[]?
        | select(.type=="tool_result" and .is_error==true) | .tool_use_id
        | select(. as $t | $ids | any(. == $t)) ] | length
  ' "$tr_" 2>/dev/null )
case "$task_fail_count" in ''|*[!0-9]*) task_fail_count=0 ;; esac

# Agent naming: if Task/Agent count >= 1, one of the roster must appear in assistant text.
# Extract all assistant message text.
#
# $named feeds the delegation-drift logger below (tests/delegation-drift.sh's secondary,
# call-sign-attribution metric) as well as this mandate. false is the correct value both when
# task_count is 0 (attribution has nothing to attribute) and when it is >=1 but no roster name
# was found -- the logger's own consumer filters to task_count>=1 windows before reading it, so
# the two false cases are never conflated downstream.
named=false
if [ "$task_count" -ge 1 ]; then
  assistant_text=$( "$JQ" -r 'select(.type=="assistant") | .message.content[]?
            | select(.type=="text") | .text' "$tr_" 2>/dev/null | tr '\n' ' ' )
  # Roster: RICK MEESEEKS MORTY SUMMER ZEEP GLOOTIE JAGUAR BETH BIRDPERSON EVIL-MORTY NOOBNOOB PICKLE-RICK SCARY-TERRY POOPYBUTTHOLE UNITY
  if printf '%s' "$assistant_text" | grep -qiE '\b(RICK|MEESEEKS|MORTY|SUMMER|ZEEP|GLOOTIE|JAGUAR|BETH|BIRDPERSON|EVIL-MORTY|NOOBNOOB|PICKLE-RICK|SCARY-TERRY|POOPYBUTTHOLE|UNITY)\b'; then
    named=true  # at least one call sign found, mandate met
  elif [ "$eval_naming" = 1 ]; then
    unmet="$unmet
  agent naming -- $task_count subagent call(s) dispatched but no attribution found (name one: RICK MEESEEKS MORTY SUMMER ZEEP GLOOTIE JAGUAR BETH BIRDPERSON EVIL-MORTY NOOBNOOB PICKLE-RICK SCARY-TERRY POOPYBUTTHOLE UNITY)"
    hit_naming=1
  fi
fi

# Swarm: the operator rule is "every dispatch goes through the swarm skill first" -- every
# Task/Agent call this session must be preceded, somewhere in the transcript, by a Skill tool_use
# naming "swarm". Lives in its own delegation-family counter (eval_swarm/$cnt_file.delegate-swarm),
# same family as agent naming just above (both conditions are keyed off task_count>=1, not off
# file writes) but its own latch, not naming's or breadth's -- two unrelated naming strikes must
# not silence this mandate, the exact bleed this round of changes exists to close. Reuses
# $task_count and $skills/fired(), both already computed above for task_count and the
# unslop/typescript-best-practices mandates respectively -- no new jq slurp, same discipline the
# fanout_batches merge above already established.
#
# $skills is a session-wide set (order is not tracked, same as fired() everywhere else in this
# file), so this cannot tell "swarm called before this specific dispatch" from "swarm called once
# early, then five more dispatches went out unrouted" -- the same session-wide-vs-per-situation
# gap that applies to unslop/typescript-best-practices too, not a new one introduced here.
if [ "$task_count" -ge 1 ] && [ "$eval_swarm" = 1 ] && ! fired swarm; then
  unmet="$unmet
  swarm -- $task_count subagent call(s) dispatched without calling the swarm skill (call Skill swarm BEFORE dispatching Task/Agent calls, not after -- it routes the dispatch, it does not review one already sent)"
  hit_swarm=1
fi

parent_dirs=$( printf '%s\n' "$paths" | sed -E '
  s#/[^/]*$##
  t end
  s#^.*$#.#
  :end
' | sort -u )
dir_count=$( [ -z "$parent_dirs" ] && echo 0 || printf '%s\n' "$parent_dirs" | grep -c . )
extensions=$( printf '%s\n' "$paths" | sed -E '
  s#^.*/##
  /^\.[^.]*$/d
  s/^.*\.([^.]*)$/\1/
  t success
  d
  :success
  /^$/d
' | sort -u )
ext_count=$( [ -z "$extensions" ] && echo 0 || printf '%s\n' "$extensions" | grep -c . )
# Satisfied by $fanout_batches, not by $task_count: task_count only asks "did any Task/Agent
# calls happen anywhere in the transcript", which a single delegation, or N delegations spread
# across N separate serial turns, both answer yes to -- neither is the parallel batch the
# mandate exists to require. $fanout_batches (computed above, next to task_count) counts how
# many times 2+ Task/Agent calls landed in the SAME assistant message, which is the only shape
# Claude Code actually executes concurrently. Eligibility (dir_count/ext_count) is unchanged --
# only what counts as having answered it changed.
# Threshold lowered from dir>=3 to dir>=2 in 1.66.0. Measured: a two-directory, two-extension
# edit is a cross-cutting change that fans out cleanly, and it was never gated before, first
# offence or repeat. The AND with ext>=2 stays -- a three-file edit inside one file type is
# often legitimately serial, and gating it would be the nag that gets a guard switched off.
if [ "$eval_breadth" = 1 ] && [ "$dir_count" -ge 2 ] && [ "$ext_count" -ge 2 ] && [ "$fanout_batches" -eq 0 ]; then
  # Names the actual parts (bounded to 3, same head-N precedent the prose/typescript mandates
  # above already use for file paths) instead of only a count -- "touched 5 directories" tells
  # the model a number it already knew; "touched claude/hooks, tests, docs, ..." tells it which
  # subagent to dispatch at which part.
  dirs_named=$(printf '%s\n' "$parent_dirs" | head -3 | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  # Distinguishes the two ways fanout_batches can be 0, because the fix is different: nothing
  # dispatched at all vs. real delegation that never happened together. Without this split, a
  # session that dispatched 5 subagents one after another reads the same "zero subagents" message
  # a session that dispatched none did, which is not what happened and does not tell the model
  # what to change (it already knows it delegated).
  if [ "$task_count" -eq 0 ]; then
    fanout_state="zero subagents"
  else
    fanout_state="$task_count subagent call(s), but never 2+ in the same message -- $task_count separate serial delegation(s), which Claude Code runs one after another, not concurrently"
  fi
  # Leads with the imperative and the number, not the diagnosis: "touched N directories" tells
  # the model a fact it already knows, "dispatch 3 agents in ONE message" is the action the
  # next turn can take. Agent count = dir_count capped at 5 (above that, aggregation cost
  # eats the parallelism win; same reasoning as the swarm skill's own N guidance).
  breadth_agents=$dir_count
  [ "$breadth_agents" -gt 5 ] && breadth_agents=5
  unmet="$unmet
  multi-directory work -- dispatch $breadth_agents agents in ONE message via Skill swarm, one per area ($dirs_named$([ "$dir_count" -gt 3 ] && echo ', ...')), each on a disjoint file set. This Stop touched $dir_count directories with $ext_count file types, $fanout_state. One Task/Agent call followed by another later does not satisfy this."
  hit_breadth=1
fi

# Serial dispatch tail: the shape the breadth gate above structurally cannot see. Its
# fanout_batches==0 condition is evaluated over the whole transcript, so ONE early batch
# satisfies it for every remaining Stop of the session while the model degrades into a serial
# loop -- the amnesty measured in 3ce9f899 and 8959d943 (see the fanout_calc comment). This
# mandate reads $serial_tail instead: dispatches after the last real batch, or all of them
# when none ever ran. Threshold 3, replayed against real sessions before choosing it: tails
# of 12 (e0cd5a40), 25 (3ce9f899) and 9 (8959d943) all fire; 416fb382's post-block tail of 2
# does not, because two singleton dispatches are the shape two unrelated one-shot asks
# legitimately produce, and a tail of 3 is necessarily 3 separate messages (3 in one message
# would be a batch and would reset the tail). Its own windowed 2-strike latch above bounds
# the cost when this call is wrong. Not gated on dir/ext breadth: the defect it polices is in
# the dispatch pattern itself, not in what files were touched.
if [ "$eval_serial" = 1 ] && [ "$serial_tail" -ge 3 ]; then
  serial_n=$serial_tail
  [ "$serial_n" -gt 5 ] && serial_n=5
  unmet="$unmet
  serial dispatch tail -- $serial_tail Task/Agent dispatch(es) sent one message at a time since the last parallel batch (or session start, if none ever ran). Send the remaining independent work as $serial_n Agent calls in ONE message (call Skill swarm first -- it routes the batch)."
  hit_serial=1
fi

# --- delegation-drift logger (tests/delegation-drift.sh) ---------------------------------------
# Every field below -- dir_count, ext_count, task_count, named -- is already sitting in a
# variable by this point in the script; the breadth and agent-naming mandates above computed all
# of it to decide whether to block. This appends one line recording it, which costs one jq
# invocation and one file write, not a second pass over the transcript.
#
# task_fail_count is the one field above that ISN'T free: it is a second, small jq pass over the
# same already-slurped transcript (see task_fail_count= above, next to task_count), because the
# breadth/naming mandates never needed to know whether a dispatch failed, only whether one
# happened. Without it this ledger recorded that N subagents were dispatched and nothing about
# what came back -- a session logging task_count:5 reads identically whether all five returned
# verified fixes or all five errored in the first second, and no claim about the routing layer
# can be supported by a number that cannot tell those apart.
#
# Log unconditionally, block conditionally: this runs whether or not $unmet ends up non-empty,
# so the log measures the behaviour (did breadth cross the threshold, did a dispatch happen) on
# every evaluated Stop, not just the ones a mandate happened to block. A log that only captured
# blocks would show a denominator only when the gate already fired, which is the gate's own
# effect, not the rate the gate is trying to move.
#
# Not logged: any Stop that exits before reaching even the latch above (VSTACK_NO_MANDATE=1, no
# jq, no readable transcript, or stop_hook_active). A latched Stop (cnt>=2) IS logged -- see the
# latch block near the top of this file -- but with null counts and latched:true instead of the
# fields below, because computing dir_count/ext_count/task_count there would mean paying for the
# transcript parse this comment's "not a second pass" claim is about, on a Stop that can no longer
# be blocked by anything that parse would find.
#
# Never lets logging break the hook's JSON-stdout-or-nothing contract: the entire block is one
# subshell with stderr discarded, nothing in it writes to this script's own stdout, and no
# command's exit status here is checked or allowed to change the exit path below.
#
# No file contents, no paths: session id, seven integer/boolean fields, and a timestamp --
# matching the same discipline the mandates above already apply to $paths before it ever reaches
# a message. task_fail_count carries a count, same as task_count, never which agent or what it
# was asked -- that stays out of this log for the same reason prompts stay out of the replay log
# (dispatch-counter.sh's own header makes the same call for the same reason).
#
# fanout_batches: already computed above at $fanout_batches, next to task_count -- passed straight
# into the same jq invocation below, no second process. This is the field the breadth mandate
# itself now decides on ($fanout_batches, not $task_count -- see the "Satisfied by $fanout_batches"
# comment above); logging it is what lets the drift analyser's primary metric ever be reconciled
# against what the live hook actually gates on again. See the latched-row comment above (the
# other place this same field is written) for what missing vs. null vs. 0 each mean here -- a
# row this evaluated branch writes always carries a real integer, never null.
#
# Opt-out: VSTACK_NO_DELEGATION_LOG=1, same shape as VSTACK_NO_MANDATE.
# Destination override: VSTACK_DELEGATION_LOG, for tests/delegation-drift.sh's own fixtures and
# for tests/test-breadth-mandate.sh's synthetic sessions -- unset, it defaults to
# $CLAUDE_CONFIG_DIR/vstack-delegation-log.jsonl (or $HOME/.claude if CLAUDE_CONFIG_DIR is unset),
# the same config-dir convention install.sh and tests/install-matrix.sh already use elsewhere in
# this repo. Any fixture harness that drives this hook directly with synthetic transcripts MUST
# set this, or its synthetic checkpoints land in the real log next to genuine sessions.
#
# Append + rotation both live in _delegation_log_row(), defined once near the top of this file
# and shared with the latched row above it -- see that definition for the rotation policy.
if [ "${VSTACK_NO_DELEGATION_LOG:-0}" != "1" ]; then
  (
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    row=$("$JQ" -cn --arg sid "$sid" --argjson ckpt "${ckpt:-0}" --argjson dc "$dir_count" \
      --argjson ec "$ext_count" --argjson tc "$task_count" --argjson tfc "$task_fail_count" \
      --argjson fb "$fanout_batches" --argjson named "$named" --arg ts "$ts" \
      '{session_id:$sid, checkpoint_index:$ckpt, dir_count:$dc, ext_count:$ec, task_count:$tc, task_fail_count:$tfc, fanout_batches:$fb, named:$named, latched:false, ts:$ts}')
    _delegation_log_row "$row"
  ) 2>/dev/null
fi

# Prove it works: a completion claim closing this turn with zero evidence produced in it.
#
# Every mandate above asks "did a skill run against a file this session touched", which the
# matcher above can answer because both halves -- the file, the skill invocation -- are things
# that already happened. This one is different in kind. principle-prove-it-works's trigger is
# "before declaring any task or fix done": a condition on the assistant's own next speech act,
# not on anything in the user's prompt. Skill dispatch scores the user's text against skill
# descriptions, so no description can reach a condition that names the assistant's own
# forthcoming output -- measured at 0/10 on its fixture prompt, the worst score of any principle
# skill, and not for lack of vocabulary overlap (its description contains both of the prompt's
# literal tokens). The thing that needs catching is not in the text being matched.
#
# This hook already runs on Stop, which is exactly the moment the condition is about: the turn
# is over, and whatever the assistant said last is what it is about to leave standing. So instead
# of asking a skill matcher to catch a property of unwritten text, this reads the transcript for
# it directly, the same way the mandates above read it for file writes.
#
# "This turn" is bounded by the transcript itself, not guessed: a real human turn starts at a
# "type":"user" entry whose content is a plain string, or an array with a "text" block and no
# "tool_result" block (a tool result is also logged as type "user" -- that is Claude Code's
# transcript format, not a human reply, and must not reset the boundary). Everything after the
# LAST such entry is this turn. A transcript with no such entry at all (every fixture in this
# repo's own test suites, which build a transcript as one bare assistant block with no user
# line) falls back to treating the whole file as the turn, which is what the two-line file this
# hook actually sees in a real session with a fresh session_id effectively already reduces to.
#
# Within that turn: did the closing remark claim completion, and did the turn edit a file while
# producing zero evidence? Both conditions gate the trigger, not either alone.
#
#   claim   -- the LAST assistant "text" block in the turn (i.e. the words actually left standing
#              when the turn ends, not something said and then acted past) matches a bounded list
#              of completion phrasings below.
#   edit    -- at least one Write/Edit/NotebookEdit tool_use happened in the turn. Without this,
#              a completion claim is conversational, not a claim about code, and the false-block
#              cost of guessing otherwise is worse than the miss (see the false-positive note by
#              the pattern list below).
#   silent  -- ANY Bash, Read, or Task/Agent tool_use anywhere in the turn, in any order relative to
#              the edit. This is deliberately generous in both directions: a Bash call is treated
#              as evidence whether or not it happens to be a test invocation, and a Read is
#              treated as evidence even if it came before the edit (i.e. was investigation of the
#              bug, not verification of the fix) rather than after it. Both loosen the trigger
#              past what "prove it works" strictly asks for. That is the intended trade: this
#              fires on every Stop of every install, so the cost of a rule this hook cannot
#              satisfy is not "the model tries again", it is "the mandate gets disabled" -- and
#              a disabled mandate catches nothing, including the 9 times it would have been
#              right. Ordering the Bash/Read calls against the edit to tighten this further was
#              considered and dropped: the added jq is not free, and the case it would catch (an
#              investigative Read with no verification after) is already the rarer shape.
#
# Known false-positive shape, disclosed rather than chased: a turn that Writes a genuinely
# unverifiable artifact -- a poem, a note, a scratch file with no "works" to check -- and closes
# with a plain "Done." trips this exactly like an unverified code fix would, because file-write
# plus closing "done" plus no Bash/Read/Task/Agent in the same turn is indistinguishable from here.
# Scoping the edit check to code-like extensions was considered and rejected: it would have
# meant maintaining an extension allowlist this hook has no way to keep current, trading one
# false-positive shape for a false-negative one (a `.sh` fix that never runs is exactly the case
# this exists to catch). Left as a known, bounded miss in the direction this file always prefers.
# A two-pass version of this was tried first: stream the file once in jq's default per-line
# mode to find which line the turn starts on (matching how every other mandate above reads the
# transcript), then hand only the tail after that line to a second, small jq call, on the theory
# that avoiding a whole-file `-s` slurp would be the cheaper path. Measured on a 37MB real
# session transcript it was slower, not faster -- +520ms over the streaming mandates alone in
# this hook, roughly triple this one-pass version's cost. The reason: shelling out to `tail -n
# +N` to extract that tail is not free on this platform. BSD `tail`'s from-line mode measured at
# ~400ms on this repo's own darwin box to extract an 11-line, 33KB tail from that same 1782-line
# file -- line-oriented access apparently is not the fast path GNU tail's implementation makes
# it look like elsewhere. jq's own `-s` slurp-then-slice of the same whole file measured ~170ms,
# faster than just the `tail` step of the "optimization" meant to beat it. Reverted to the
# simpler single-pass slurp below in favor of the version that is both less code and faster.
#
# Gated on the two mandates that read the current turn -- prove-it-works and register -- not
# the family-level skill_eval: this jq slurp is their shared cost alone (unslop/
# typescript-best-practices need none of turn_json), so it must not run just because unslop or
# typescript-best-practices still has headroom -- only because a turn-reading mandate does.
# Each consumer below re-gates on its OWN eval_* flag: a latched prove-it-works must not get a
# free evaluation because register kept the slurp alive, and vice versa.
if [ "$eval_proveitworks" = 1 ] || [ "$eval_register" = 1 ]; then
turn_json=$(
  "$JQ" -sc '
    . as $all
    | ( $all
        | to_entries
        | map(select(.value.type == "user"
                     and (
                       (.value.message.content | type) == "string"
                       or ((.value.message.content // []) | map(.type) | index("tool_result")) == null
                     )))
        | last | .key
      ) as $ts
    | ($all[(($ts // -1) + 1):] | map(select(.type == "assistant"))) as $turn
    | {
        turn_texts: ( [ $turn[] | .message.content[]? | select(.type == "text") | .text ] | join("\n") ),
        final_text: ( [ $turn[] | .message.content[]? | select(.type == "text") | .text ] | last // "" ),
        bash_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Bash") ] | length ),
        read_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Read") ] | length ),
        task_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and .name == "Task") ] | length ),
        edit_n: ( [ $turn[] | .message.content[]? | select(.type == "tool_use" and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit")) ] | length )
      }
  ' "$tr_" 2>/dev/null
)
[ -n "$turn_json" ] || turn_json='{}'

# The register mandate: ~/.claude/CLAUDE.md's REGISTER rule, enforced instead of remembered.
# Scans every assistant text block of the CURRENT TURN (same turn boundary prove-it-works uses
# -- whole-transcript scanning would re-block old sins on every later Stop forever) for the
# exact banned-opener list, line-anchored. Deliberately narrow: no narration heuristics
# ("^Reading...") in v1 -- their false-positive rate on imperative prose is unmeasured; widen
# only from measured misses. Known accepted false positives, bounded by the 2-strike session
# latch: quoted peer text and list items that start a line with a banned word.
if [ "$eval_register" = 1 ]; then
  reg_texts=$(printf '%s' "$turn_json" | "$JQ" -r '.turn_texts // ""' 2>/dev/null)
  reg_pattern="^(Ah|I see|Got it|Right|Okay|Sure|Great|Perfect|Good catch|You('|’)re right|Let me|Now I('|’)ll|Now I('|’)m)[,! .]"
  reg_match=""
  if [ -n "$reg_texts" ]; then
    reg_match=$(printf '%s\n' "$reg_texts" | grep -oE "$reg_pattern" 2>/dev/null | head -1 | sed 's/[,! .]*$//')
  fi
  if [ -n "$reg_match" ]; then
    unmet="$unmet
  register -- banned opener \"$reg_match\" in this turn's text. Delete it; state the fact or make the tool call instead."
    hit_register=1
  fi
fi

if [ "$eval_proveitworks" = 1 ]; then
piw_final_text=$(printf '%s' "$turn_json" | "$JQ" -r '.final_text // ""' 2>/dev/null)
piw_bash_n=$(printf '%s' "$turn_json" | "$JQ" -r '.bash_n // 0' 2>/dev/null)
piw_read_n=$(printf '%s' "$turn_json" | "$JQ" -r '.read_n // 0' 2>/dev/null)
piw_task_n=$(printf '%s' "$turn_json" | "$JQ" -r '.task_n // 0' 2>/dev/null)
piw_edit_n=$(printf '%s' "$turn_json" | "$JQ" -r '.edit_n // 0' 2>/dev/null)
: "${piw_bash_n:=0}"; : "${piw_read_n:=0}"; : "${piw_task_n:=0}"; : "${piw_edit_n:=0}"

# Bounded, not exhaustive -- the examples the mandate names ("done", "fixed", "works now", "all
# tests pass", "that should do it") plus their closest paraphrases. The unescaped `.` inside
# "that.s done" is a one-char wildcard standing in for whatever apostrophe got typed (straight
# ', curly ', or none at all -- "thats done"), so the pattern needs no quote-escaping at all.
piw_pattern='\bit works( now)?\b|\bthat works( now)?\b|\bworks now\b|\ball tests? (pass(ing|es)?|passed)\b|\bthat should do it\b|\bshould (work|be fixed) now\b|\bthe (fix|bug) is (fixed|done|complete|resolved)\b|\bthis (is|should be) (fixed|done|complete|resolved)\b|\b(task|issue|problem) is (fixed|done|complete|resolved)\b|\ball (set|good|done)\b|\bfixed\b|\bthat.s done\b|^done[.!]*$'

piw_claims=0
if [ -n "$piw_final_text" ] && printf '%s' "$piw_final_text" | grep -qiE "$piw_pattern"; then piw_claims=1; fi

if [ "$piw_edit_n" -ge 1 ] && [ "$piw_claims" -eq 1 ] \
   && [ "$piw_bash_n" -eq 0 ] && [ "$piw_read_n" -eq 0 ] && [ "$piw_task_n" -eq 0 ]; then
  unmet="$unmet
  prove-it-works -- this turn edited a file and closed claiming it is done, with no Bash/Read/Task/Agent call in the turn to back it up"
  hit_proveitworks=1
fi
fi # eval_proveitworks: the prove-it-works evaluation itself
fi # eval_proveitworks || eval_register: turn_json and its two consumers

# Per-mandate bookkeeping, replacing the two shared-counter blocks above: each of the six
# mandates persists or clears its OWN counter file independently now, so hitting one never
# advances or resets another's strike count -- the entire point of this change (coordinator-
# directed, closing the bleed f4f5468 already proved real one level up). A mandate that was
# evaluated this Stop (its own eval_* flag was 1) and did NOT contribute to $unmet had every
# chance to and passed -- its own counter resets to 0, the same "fully met -> clear" rule the
# shared counters used, now scoped to one mandate instead of a whole family.
# Skill-family writes now carry a -ts sidecar so the windowed read above can re-arm them,
# exactly as the delegation family does below. On hit, stamp the time; on a clean evaluated
# turn, clear both the counter and its stamp.
if [ "$hit_unslop" = 1 ]; then
  echo $((cnt_unslop + 1)) > "$cnt_file.unslop"
  date +%s > "$cnt_file.unslop-ts" 2>/dev/null
elif [ "$eval_unslop" = 1 ]; then
  rm -f "$cnt_file.unslop" "$cnt_file.unslop-ts"
fi
if [ "$hit_typescript" = 1 ]; then
  echo $((cnt_typescript + 1)) > "$cnt_file.typescript"
  date +%s > "$cnt_file.typescript-ts" 2>/dev/null
elif [ "$eval_typescript" = 1 ]; then
  rm -f "$cnt_file.typescript" "$cnt_file.typescript-ts"
fi
if [ "$hit_proveitworks" = 1 ]; then
  echo $((cnt_proveitworks + 1)) > "$cnt_file.proveitworks"
  date +%s > "$cnt_file.proveitworks-ts" 2>/dev/null
elif [ "$eval_proveitworks" = 1 ]; then
  rm -f "$cnt_file.proveitworks" "$cnt_file.proveitworks-ts"
fi
if [ "$hit_register" = 1 ]; then
  echo $((cnt_register + 1)) > "$cnt_file.register"
  date +%s > "$cnt_file.register-ts" 2>/dev/null
elif [ "$eval_register" = 1 ]; then
  rm -f "$cnt_file.register" "$cnt_file.register-ts"
fi
if [ "$hit_breadth" = 1 ]; then
  echo $((cnt_breadth + 1)) > "$cnt_file.delegate-breadth"
  date +%s > "$cnt_file.delegate-breadth-ts" 2>/dev/null
elif [ "$eval_breadth" = 1 ]; then
  rm -f "$cnt_file.delegate-breadth" "$cnt_file.delegate-breadth-ts"
fi
if [ "$hit_naming" = 1 ]; then
  echo $((cnt_naming + 1)) > "$cnt_file.delegate-naming"
  date +%s > "$cnt_file.delegate-naming-ts" 2>/dev/null
elif [ "$eval_naming" = 1 ]; then
  rm -f "$cnt_file.delegate-naming" "$cnt_file.delegate-naming-ts"
fi
if [ "$hit_swarm" = 1 ]; then
  echo $((cnt_swarm + 1)) > "$cnt_file.delegate-swarm"
  date +%s > "$cnt_file.delegate-swarm-ts" 2>/dev/null
elif [ "$eval_swarm" = 1 ]; then
  rm -f "$cnt_file.delegate-swarm" "$cnt_file.delegate-swarm-ts"
fi
if [ "$hit_serial" = 1 ]; then
  echo $((cnt_serial + 1)) > "$cnt_file.delegate-serial"
  date +%s > "$cnt_file.delegate-serial-ts" 2>/dev/null
elif [ "$eval_serial" = 1 ]; then
  rm -f "$cnt_file.delegate-serial" "$cnt_file.delegate-serial-ts"
fi

[ -n "$unmet" ] || exit 0

reason="A vstack mandate went unmet. These fire every time, not when they seem relevant:
$unmet
"
# One strike line per mandate that actually hit THIS Stop, not one combined line per family --
# each mandate now has its own 2-strike cap and its own reset trigger, so the reader needs to
# know which specific one is about to go quiet, not "the skill family" or "the delegation
# family" (which, before this change, was frequently a lie: the family could still have two
# other mandates with a full 2 strikes left).
_strike_line() { # <label> <new-count> <scope-sentence>
  printf '
%s strike %s/2 %s' "$1" "$2" "$3"
}
if [ "$hit_unslop" = 1 ]; then
  reason="$reason$(_strike_line unslop "$((cnt_unslop + 1))"     "this session -- after 2, unslop alone stops being enforced for the rest of the session (self-police from here).")"
fi
if [ "$hit_typescript" = 1 ]; then
  reason="$reason$(_strike_line typescript-best-practices "$((cnt_typescript + 1))"     "this session -- after 2, typescript-best-practices alone stops being enforced for the rest of the session (self-police from here).")"
fi
if [ "$hit_proveitworks" = 1 ]; then
  reason="$reason$(_strike_line prove-it-works "$((cnt_proveitworks + 1))"     "this session -- after 2, prove-it-works alone stops being enforced for the rest of the session (self-police from here).")"
fi
if [ "$hit_register" = 1 ]; then
  reason="$reason$(_strike_line register "$((cnt_register + 1))"     "this session -- after 2, register alone stops being enforced for the rest of the session (self-police from here).")"
fi
if [ "$hit_breadth" = 1 ]; then
  reason="$reason$(_strike_line "multi-directory work" "$((cnt_breadth + 1))"     "in this ${DELEGATE_RESET_SECS}s window -- after 2, this mandate alone stops being enforced until the window elapses with no further unmet Stop for it.")"
fi
if [ "$hit_naming" = 1 ]; then
  reason="$reason$(_strike_line "agent naming" "$((cnt_naming + 1))"     "in this ${DELEGATE_RESET_SECS}s window -- after 2, this mandate alone stops being enforced until the window elapses with no further unmet Stop for it.")"
fi
if [ "$hit_swarm" = 1 ]; then
  reason="$reason$(_strike_line swarm "$((cnt_swarm + 1))"     "in this ${DELEGATE_RESET_SECS}s window -- after 2, this mandate alone stops being enforced until the window elapses with no further unmet Stop for it.")"
fi
if [ "$hit_serial" = 1 ]; then
  reason="$reason$(_strike_line "serial dispatch tail" "$((cnt_serial + 1))"     "in this ${DELEGATE_RESET_SECS}s window -- after 2, this mandate alone stops being enforced until the window elapses with no further unmet Stop for it.")"
fi
reason="$reason
Run each named skill with the Skill tool against the files listed, apply what it says, then finish.
For prove-it-works: run the command that proves the change, read its actual output, then restate
the claim with that evidence -- or state the real status if the output disagrees with it.
For register: there is no skill to run -- delete the named phrase from the reply text.
Set VSTACK_NO_MANDATE=1 to disable this gate."
"$JQ" -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
