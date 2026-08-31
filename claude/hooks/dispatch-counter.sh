#!/usr/bin/env bash
# PostToolUse (matcher: Agent|Task): increments a per-session dispatch counter that
# claude/statusline.sh reads to render "RICK ·N▸". This is the WRITE side of that contract.
# Before this hook existed there was a reader with no writer -- claude/statusline.sh was built
# and verified against a hand-created fixture file, so its own test suite passed while the
# runtime path that was supposed to produce that file did not exist. Same defect shape this
# repo's own gates exist to catch elsewhere (a check that passes without measuring); the fix
# here is the same as everywhere else in this file's neighbours: build the missing half and
# prove both halves together, not each in isolation.
#
# Contract, fixed by the reader and matched here exactly -- see claude/statusline.sh's own
# "Lead and delegation" comment for the read side:
#   path   : ${TMPDIR:-/tmp}/vstack-dispatch-count-<session_id>
#   value  : bare integer, single line, no trailing newline (printf, not echo)
#   create : on first dispatch, not at SessionStart. A fresh session must have NO counter file at
#            all, not a "0" one -- that absence is what lets the reader render nothing instead of
#            "·0▸" for a session that hasn't delegated yet. Nothing in this repo creates this
#            file except this hook, and this hook only ever runs on an actual Agent/Task
#            dispatch, so the distinction holds by construction: no dispatch, no invocation, no
#            file.
#
# Cost: O(1) by design, never touches the transcript -- read one small file, add 1, write it
# back. This is the same shape as skill-mandate.sh's $cnt_file, which is also why the lock below
# is that file's lock ported verbatim rather than re-derived (see next paragraph). Measured
# against a real dispatch on this machine, n=30: mean/p50/p95 reported in the commit/handback
# that shipped this rather than duplicated here, where a number would drift stale next to the
# code that produces it.
#
# Concurrency: parallel subagents finish at once, which makes an unlocked read-modify-write here
# the identical race skill-mandate.sh already solved for $cnt_file -- ten racing invocations all
# read the same starting count, each computes its own +1, and the last write wins, undercounting
# every dispatch that raced another. `mkdir` is atomic on every POSIX filesystem (exactly one
# racing caller sees it succeed), needs no GNU flock and no coreutils on stock macOS, and is the
# same fix already proven in skill-mandate.sh and verify-gate.sh -- ported here, not reinvented.
# A lock older than 30s is assumed abandoned by a killed sibling rather than honored forever, so
# a crash can't wedge the counter shut for the rest of the session.
#
# Escape hatch, same shape as every other gate/log in this repo: VSTACK_NO_DISPATCH_COUNT=1
# disables this entirely. A counter nobody can turn off gets deleted by the first person it
# inconveniences.
#
# --- replay logging -----------------------------------------------------------------------------
# oh-my-claudecode (github.com/Yeachan-Heo/oh-my-claudecode) ships per-session agent-replay-*.jsonl
# logs; vstack had nothing recording WHICH agent ran, what it was asked, or what came back --
# claude/vstack-delegation-log.jsonl (skill-mandate.sh) only ever recorded per-Stop aggregate
# counts (dir_count/ext_count/task_count), never a per-dispatch row. That gap cost a real
# measurement: a session that got 0/5 on a fixture run with two fixtures sharing no trigger string
# with anything could not be diagnosed after the fact, because no record of the individual
# dispatches survived past the transcript.
#
# Five decisions, in the order this file's own header poses them:
#
# 1. WHERE. A single well-known file, ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-replay-log.jsonl
#    -- not one file per session. A per-session file (vstack-replay-<sid>.jsonl) needs the session
#    id to find, which is exactly the thing a debugger reading this tomorrow does not have; a
#    single aggregate file with session_id as a COLUMN is `cat`-able with no glob, no directory
#    listing, no guessing which of forty session files is the relevant one. This mirrors the
#    delegation-drift log's own layout exactly (one file, session_id is a field, not a filename).
#
# 2. WHAT EACH ROW CARRIES. ts, session_id, dispatch_index (the $cnt this hook already computed
#    above -- free, no second counter), tool_name (Agent vs Task), subagent_type -- plus
#    prompt_bytes, result_bytes, and description_bytes instead of the prompt/result/description
#    text themselves. description was carried verbatim in an earlier version of this file on the
#    theory that it is a short, human-authored 3-6 word imperative label (Task/Agent's own tool
#    schema: {description, prompt, subagent_type}) and therefore not the same exposure risk as
#    prompt/result. That theory does not hold: description is ordinary free text on the tool
#    call, not a constrained enum, and nothing on the schema or the runtime stops a caller from
#    writing a credential, a file path with a token in it, or any other secret-shaped string into
#    it -- reproduced directly (a dispatch whose description quoted an API-key-shaped string
#    landed that string verbatim in this log). A byte count cannot leak; a redaction pass over an
#    open-ended set of credential shapes (cloud provider keys, PATs, JWTs, private key headers,
#    ad hoc passwords) can only ever be a filter with known gaps, and it is not worth the false
#    confidence of shipping a partial one over description's few label-sized bytes when this
#    field's entire job -- "which agent ran and to do what" -- survives a byte count only
#    partially anyway. Sizing it exactly like prompt/result removes the class of bug instead of
#    chasing its instances: a replay log full of verbatim prompts (or descriptions) is a
#    secret-leak surface (subagent prompts routinely quote file contents, credentials found in
#    code, etc.) and a disk problem the delegation log's own 2MB-cap comment already argues
#    against elsewhere in this repo.
#
#    One field beyond the brief's minimum earns its bytes for free: duration_ms. Confirmed by
#    reading this CLI build's own hook-input constructor (`strings` on the installed 2.1.241
#    binary, function building the PostToolUse payload) rather than assumed --
#    `{...,hook_event_name:"PostToolUse",tool_name:e,tool_input:r,tool_response:n,
#    tool_use_id:t,duration_ms:l}` -- the runtime already measures how long the dispatch took and
#    was simply not being asked for it. This is the single field that answers "how did it go"
#    without touching content at all: a session that dispatched 25 times and got nothing useful is
#    now distinguishable, from this log alone, between "25 fast dispatches that each did nothing"
#    and "25 dispatches that each ran for minutes" -- which pointed a debugger at completely
#    different root causes had it existed for today's postmortem. tool_use_id is also carried,
#    same reasoning as $sid: not content, a correlation key back to the exact tool_use block in the
#    transcript for the rare case someone needs to go past this log's own redaction.
#
# 3. WHETHER THE RESULT IS THERE AT ALL. Checked, not assumed: same `strings` pass on the installed
#    binary turned up the literal source comment `"tool_response": { "success": true }  //
#    PostToolUse only` next to the hook-input construction above -- tool_response IS populated on
#    PostToolUse (PostToolUseFailure carries `error` instead, per the same binary's
#    PostToolUseFailure hook-input builder, and this hook's matcher never sees that event, so a
#    dispatch that fails outright is invisible to this specific log -- a real, disclosed gap, not
#    fixed here since matcher wiring is out of this file's scope). What tool_response contains
#    beyond that for a Task/Agent call specifically -- whether it is a bare {content:[...]} block
#    or carries its own usage/cost metadata -- was not confirmed against a live payload from
#    within this hook's own sandbox (no Task tool available to this process to dispatch one for
#    real). Rather than guess at an internal shape that could drift across builds, result_bytes
#    below measures the serialized byte size of tool_response AS A WHOLE, whatever its shape --
#    correct regardless of which internal fields a given build does or does not include, and it is
#    a size, so guessing wrong about the internal shape costs nothing.
#
# 4. ROTATION AND CAP. Reuses the exact mechanism skill-mandate.sh's `_delegation_log_row()`
#    already built for vstack-delegation-log.jsonl -- ported verbatim below as
#    `_replay_log_row()`, not re-derived, for the same reason skill-mandate.sh gives for porting
#    its own lock from verify-gate.sh: two copies of the same fix are two chances for them to
#    drift. Same cap: append, then one `stat` byte-size check; only once >2MB does it pay to
#    rewrite, keeping the last 5000 lines. This schema is wider than the delegation log's five
#    scalar fields (thirteen fields now, after decision 6 added cwd/isolation/run_in_background/
#    derived_prev_dispatch_gap_s -- two of the original nine, description and prompt, are still
#    free-text up to a few hundred bytes each as byte counts, not verbatim), so 5000 rows costs
#    more here. Measured directly against this hook's own real output (not estimated): a minimal
#    row (short cwd, isolation/run_in_background unset by the caller) went from 223B to 313B; a
#    realistic row (worktree-length cwd, isolation set) went from 251B to 394B -- both roughly
#    +90 to +143B (+40-57%) over the pre-decision-6 schema. At those per-row sizes, 5000 rows lands
#    around 1.5-1.9MB post-rotation, not the 1-1.5MB this line stated before decision 6 measured
#    it -- that older number was prose describing a schema this file no longer writes, left
#    uncorrected in the same diff that changed the schema, which is the exact defect shape this
#    repo's own gates exist to catch elsewhere; corrected here once measured, not before. Still
#    sawtooth-bounded at 2MB same as the delegation log -- the trigger check and the trim both run
#    unconditionally on the current row width, so the file cannot grow past 2MB regardless of
#    schema -- but the SLACK between a just-rotated file and the next retrigger shrank from
#    roughly 0.5-1MB to roughly 0.1-0.5MB, meaning rotation now fires on a shorter dispatch-count
#    interval than before, not less-bounded, just more frequent. That slack is not free headroom
#    for the next field: the sampled size check only runs every 20th dispatch (see below), and 19
#    unchecked dispatches at this schema's ~313-394B/row already add ~6-7.5KB between checks: if a
#    future addition ever left post-rotation size within that ~7.5KB of 2MB, rotation would fire on
#    essentially every sampled check instead of being the rare event this comment still describes
#    today -- worth re-measuring before adding another wide field, not worth pre-emptively
#    tightening the sampling for a case that has not happened yet. A busy session dispatching 50
#    subagents in an hour adds on the order of 15-20KB to this file at the current schema (was
#    10-15KB before decision 6); the 2MB cap is still reached by volume across many sessions over
#    weeks, not by one session.
#
# 5. ESCAPE HATCH. VSTACK_NO_REPLAY_LOG=1 disables the replay row alone -- the statusline counter
#    above keeps working, matching the existing split between VSTACK_NO_MANDATE (disables
#    everything) and VSTACK_NO_DELEGATION_LOG (disables just that one log) in skill-mandate.sh.
#    VSTACK_NO_DISPATCH_COUNT=1 (this file's own pre-existing hatch, checked below before either
#    logger's variables exist) disables replay logging too, for free, since there is no
#    dispatch_index left to log without the counter it is read from. VSTACK_REPLAY_LOG overrides
#    the destination path, same convention as VSTACK_DELEGATION_LOG, for any fixture harness
#    driving this hook directly -- unset, it MUST NOT land in the real
#    ~/.claude/vstack-delegation-log.jsonl (a different file, a live 90+-row measurement corpus)
#    or in ~/.claude/vstack-replay-log.jsonl during a test run; every test in this repo that drives
#    this hook sets VSTACK_REPLAY_LOG explicitly and exports it, per this repo's own dogfooded
#    lesson that `VAR=x printf ... | bash hook` scopes the var to printf alone and leaks fixture
#    rows into the real file.
#
# 6. PARALLELISM/ISOLATION FIELDS -- what this log could NOT answer before this addition: "fan
#    work out in parallel" and "isolate each agent's workspace" are policy claims this repo makes
#    elsewhere, and nothing in the schema above could confirm or refute either one after the fact.
#    Checked against this CLI build's own source (2.1.251, same `strings`-on-the-installed-binary
#    method decision 2 above already uses, not assumed):
#      - cwd IS a field on every hook payload (confirmed in the shared base hook-input zod schema,
#        object `Ee`: `session_id, transcript_path, cwd, prompt_id?, permission_mode?, agent_id?,
#        agent_type?, effort?`, which every hook event -- including PostToolUse -- intersects).
#        It is the CALLING context's own working directory at the moment the Task/Agent tool call
#        resolved, not the new subagent's isolated worktree path (that worktree is scoped to the
#        subagent's own run and this hook never runs inside it) -- so a value here answers "was
#        the DISPATCHER itself already inside an isolated worktree", not "was the callee isolated".
#      - tool_input.isolation and tool_input.run_in_background ARE real parameters on the
#        Task/Agent tool schema (confirmed via the same binary: the tool's own usage-note strings
#        document `isolation: "worktree"` / `isolation: "remote"` and `run_in_background: true`
#        literally, e.g. "With `isolation: "worktree"`, the worktree is automatically cleaned up
#        if the agent makes no changes" and "Subagents run in the background by default"). Both
#        are OPTIONAL call arguments: present in tool_input only when the calling model's turn
#        included them explicitly, absent (not "false"/"none") when it did not, regardless of
#        whatever runtime default then applies. run_in_background is a real boolean that can
#        legitimately be `false`, so it is read with the same `has()` guard decision 2's `named`
#        precedent established for this exact reason -- `// null` would silently relabel a real
#        `false` as unset.
#      - NOTHING on the PostToolUse payload identifies which assistant MESSAGE a dispatch's tool
#        call belonged to -- confirmed absent from the PostToolUse zod schema itself (only
#        hook_event_name/tool_name/tool_input/tool_response/tool_use_id/duration_ms beyond the
#        shared base fields above). The one thing in this build that DOES carry batch membership
#        is a *different*, separate hook event, PostToolBatch (`tool_calls: [...]`, one row per
#        resolved batch, documented in the same schema block as "PostToolUse fires per-tool and
#        may run concurrently for parallel tool calls; PostToolBatch fires exactly once with the
#        full batch") -- but this hook's own matcher is PostToolUse only, and rewiring which event
#        fires it is hooks.json's call, not this file's (same boundary decision 2 already draws
#        for PostToolUseFailure). prompt_id (base schema, optional) was considered and rejected as
#        a stand-in: its own doc string says it correlates "a user prompt with all subsequent
#        events until the NEXT prompt" -- coarser than one assistant message by construction, so
#        two dispatches sharing a prompt_id can just as easily be two turns of a serial loop
#        inside one long agentic response as two calls in one parallel batch. Logging it anyway
#        would invite exactly the "derived signal mistaken for observed" failure this decision
#        exists to avoid, for a field that would look authoritative and is not; left out.
#      - message_id (the assistant message's own id -- `.message.id` on a transcript's
#        `type:"assistant"` entries, e.g. "msg_011..."; the field that WOULD group tool_use
#        blocks into the batch they actually streamed in as one message) is real and present, but
#        only in the TRANSCRIPT, confirmed directly against a live transcript file, not the hook
#        payload -- and independently re-confirmed absent from the hook payload by reading the
#        exact PostToolUse object-literal construction in the installed binary a second time
#        (`{...Ea(session,cwd,mode,ctx),hook_event_name:"PostToolUse",tool_name,tool_input,
#        tool_response,tool_use_id,duration_ms}` -- no message field, no id derived from one,
#        anywhere in that literal or in Ea()'s own return). Reading transcript_path to recover it
#        was considered and rejected: this hook's own header opens on "never touches the
#        transcript" as its O(1) cost design, and a transcript can run to tens of thousands of
#        lines -- paying that cost on every single dispatch to recover one field is a materially
#        different hook than the one being extended here, not a schema tweak. This log cannot
#        answer "was this dispatch part of a parallel batch" today, and derived_prev_dispatch_gap_s
#        below is a real but limited proxy, not a fix for that gap.
#    derived_prev_dispatch_gap_s fills the resulting gap the only honest way available: the whole
#    integer seconds between this dispatch's own jq-computed `now` and the previous dispatch's,
#    for the SAME session_id, tracked in a sidecar file next to $cnt_file ($cnt_file.last_ts,
#    read-then-overwrite, no separate lock -- a torn read here costs one dispatch a null/stale
#    gap, never a wrong dispatch_index, so it rides on the $cnt_file lock's coverage rather than
#    earning its own). Name says "derived" on purpose. What it CAN suggest: a very small gap
#    between two consecutive dispatches in one session is consistent with both having been issued
#    in the same parallel tool-call batch (their PostToolUse hooks tend to land close together).
#    What it CANNOT do: prove concurrency (a tight serial loop with no model "thinking" gap
#    produces the same small number), identify which batch either dispatch was in, or even
#    guarantee a LARGE gap rules batching out (PostToolUse fires on RESOLUTION, so two truly
#    parallel dispatches where one subagent runs for minutes longer than its sibling will show a
#    large gap despite having launched together). It is a temporal correlate, read the same
#    causal-limit way tests/delegation-drift.sh's own header insists on for its correlational
#    metric -- never treated as a batch identifier because it structurally cannot be one.
set -uo pipefail

[ "${VSTACK_NO_DISPATCH_COUNT:-0}" = "1" ] && exit 0

JQ=""
if [ -x /usr/bin/jq ]; then JQ=/usr/bin/jq
elif command -v jq >/dev/null 2>&1; then JQ=$(command -v jq); fi
# Without jq there is no reliable way to read tool_name or session_id. Say nothing rather than
# guess: an undercounted statusline is a worse failure than a silent one, same reasoning
# skill-mandate.sh applies to its own jq-missing case.
[ -n "$JQ" ] || exit 0

input=$(cat 2>/dev/null || true)

# tool_name, session_id, AND the replay row (see the "replay logging" comment above) all come out
# of ONE jq invocation, not three. This used to be two separate calls (tool_name, then session_id)
# before replay logging existed; adding a third call purely for the row -- the first version of
# this change -- measured at 72.8ms mean/74.9ms p95 (n=30) against a 24.1ms/27.3ms baseline, well
# past the budget this hook is held to, almost entirely macOS fork+exec overhead per `jq`/`wc`
# process spawned in a straight-line script. Folding tool_name/session_id/row into one jq program
# removes that regression rather than accepting it: this script now spends the SAME single jq call
# the pre-replay-logging version spent on tool_name+session_id combined, and gets the row for free
# out of the same process. Re-measured after this fix (n=30, same machine, back to back against a
# stashed pre-change baseline): baseline mean=24.8ms/p95=25.9ms, this version mean=24.5ms/
# p95=26.8ms -- statistically flat.
#
# That comparison used to end on "~25ms p95", stated as an absolute budget. It does not hold as
# one, and nothing re-derived it. tests/hook-latency.sh, which re-runs the comparison on every
# invocation instead of freezing it in prose, measured this hook at 26-123ms p95 across n=30 runs
# taken quiet to heavily loaded on 2026-08-31 -- the same range a machine running concurrent
# Claude Code sessions or CI shards produces for EVERY hook in this directory, not something
# specific to this one. A budget in milliseconds is a claim about the machine, not about the code.
#
# So the claim is now made in fork-cost units: this hook's cost divided by a single `jq` fork+exec
# timed in the same run. Budgeted at <=5.2x mean / <=6.2x p95, measured at 3.8-4.2x / 4.3-6.2x
# across every calibration run, quiet and loaded alike, where the raw milliseconds moved 1.6x for
# no code change at all. See tests/hook-latency.sh's header for why. The mkdir
# guard and sampled `stat` below (see the replay-logging block further down) are the other half
# of closing that gap; neither alone got there. dispatch_index is the one field jq cannot know yet
# here -- it comes from the atomic counter below, which cannot run before the lock -- so jq emits
# the row with a literal placeholder token in that slot and bash substitutes the real integer in
# with a parameter expansion once $cnt is known (no process spawned for the substitution).
#
# @tsv (not raw newline-joined output) because the row itself is a JSON object containing
# commas, colons and quotes that would otherwise collide with a naive `read` split; jq's @tsv
# escapes only tab/newline/CR/backslash, none of which JSON's own tojson output produces, so the
# round trip through `read` below is exact.
jq_out=$(printf '%s' "$input" | "$JQ" -r --arg ph '@@VSTACK_DISPATCH_IDX@@' --arg gph '@@VSTACK_PREV_GAP@@' '
  (now) as $nowval
  | (.tool_name // "") as $tn
  | (.session_id // "") as $sid
  | (
      if ($tn == "Agent" or $tn == "Task") then
        ((.tool_input // {}) as $ti
         | {
             ts: ($nowval | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")),
             session_id: (if $sid == "" then null else $sid end),
             dispatch_index: $ph,
             tool_name: $tn,
             subagent_type: ($ti.subagent_type // null),
             description_bytes: (if ($ti | has("description")) then ($ti.description // "" | length) else null end),
             prompt_bytes: (if ($ti | has("prompt")) then ($ti.prompt // "" | length) else null end),
             result_bytes: (if has("tool_response") then (.tool_response | tostring | length) else null end),
             duration_ms: (.duration_ms // null),
             tool_use_id: (.tool_use_id // null),
             cwd: (.cwd // null),
             isolation: ($ti.isolation // null),
             run_in_background: (if ($ti | has("run_in_background")) then $ti.run_in_background else null end),
             derived_prev_dispatch_gap_s: $gph
           }
         | tojson)
      else "" end
    ) as $row
  | [$tn, $sid, $row, ($nowval | floor | tostring)] | @tsv
' 2>/dev/null)
IFS=$'\t' read -r tool_name sid encoded_row now_epoch <<< "$jq_out"
case "$now_epoch" in ''|*[!0-9]*) now_epoch=0 ;; esac

# Defense in depth: the settings.json matcher is what actually restricts which PostToolUse
# events reach this script, but a hook that trusts its own wiring to be the only thing standing
# between it and a miscount is one config edit away from silently counting Writes as dispatches.
case "$tool_name" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

[ -n "$sid" ] || sid="pid$PPID"

cnt_file="${TMPDIR:-/tmp}/vstack-dispatch-count-$sid"
lock_dir="$cnt_file.lock"

# Lock pattern ported verbatim from claude/hooks/skill-mandate.sh's $cnt_file lock (itself
# ported from verify-gate.sh) -- see that file's own comment for the full reasoning. Not
# re-derived here on purpose: two copies of the same fix are two chances for them to drift.
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

cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
cnt=$((cnt + 1))
printf '%s' "$cnt" > "$cnt_file" 2>/dev/null

# --- replay logging (see the "replay logging" comment near the top of this file for the five
# decisions this implements) -----------------------------------------------------------------
# $encoded_row was already built above, in the same jq call that read tool_name/session_id --
# see that call's own comment for why (a second/third jq call here, measured, cost 3x this
# script's whole prior runtime). The only thing left to do with it is drop in the real
# dispatch_index (unknowable until the lock above gave up $cnt) and append it.
if [ "${VSTACK_NO_REPLAY_LOG:-0}" != "1" ] && [ -n "$encoded_row" ]; then
(
  row="${encoded_row/\"@@VSTACK_DISPATCH_IDX@@\"/$cnt}"
  # derived_prev_dispatch_gap_s (see header decision 6 for exactly what this can and cannot show):
  # read this session's own last-dispatch epoch second from a sidecar next to $cnt_file, diff
  # against $now_epoch (already computed above, in the same jq call that built the row -- no new
  # fork), then overwrite the sidecar for the next dispatch to read. `read` against a redirection
  # is a bash builtin, not a fork; only the eventual append/rotation below pays process cost.
  ts_file="$cnt_file.last_ts"
  prev_epoch=""
  [ -r "$ts_file" ] && IFS= read -r prev_epoch < "$ts_file" 2>/dev/null
  case "$prev_epoch" in ''|*[!0-9]*) prev_epoch="" ;; esac
  if [ -n "$prev_epoch" ]; then
    gap_val=$((now_epoch - prev_epoch))
  else
    gap_val="null"
  fi
  printf '%s' "$now_epoch" > "$ts_file" 2>/dev/null
  row="${row/\"@@VSTACK_PREV_GAP@@\"/$gap_val}"
  log_file="${VSTACK_REPLAY_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vstack-replay-log.jsonl}"
  log_dir_="${log_file%/*}"
  [ "$log_dir_" = "$log_file" ] && log_dir_="."
  # Guard the mkdir with a builtin `[ -d ]` test first: `mkdir -p` is itself a forked process,
  # and on every real install the destination directory (~/.claude, same one the delegation log
  # already lives in) already exists, so this skips that fork on the overwhelming majority of
  # invocations rather than paying it every single dispatch.
  [ -d "$log_dir_" ] || mkdir -p "$log_dir_" 2>/dev/null
  printf '%s\n' "$row" >> "$log_file" 2>/dev/null
  # Rotation, ported verbatim from skill-mandate.sh's `_delegation_log_row()` -- same 2MB cap,
  # same tail-keep-5000 rewrite, same reasoning, deliberately not re-derived (two copies of the
  # same fix are two chances for them to drift). One difference from that function, made for the
  # same cost reason as the mkdir guard above: the `stat` size check only runs on 1 dispatch in
  # 20 ($cnt % 20 == 0), not every single one. `stat` is a forked process too, and unlike the
  # delegation log (written once per Stop, a low-frequency event) this file is written once per
  # DISPATCH, which is a materially higher-frequency event in a fan-out-heavy session. Sampling
  # the size check trades a bounded amount of cap slop -- the file can grow up to ~19 rows
  # (roughly 4-5KB at this schema's width) past 2MB before the next sampled check catches it --
  # for skipping that fork on 19 dispatches out of 20. The append itself is never skipped; only
  # the size check that decides whether to trim is sampled, so no row is ever silently dropped.
  if [ $((cnt % 20)) -eq 0 ]; then
    sz=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    if [ "$sz" -gt 2097152 ]; then
      tail -n 5000 "$log_file" > "$log_file.rot" 2>/dev/null && mv "$log_file.rot" "$log_file" 2>/dev/null
    fi
  fi
) 2>/dev/null
fi

# Hook contract: JSON-on-stdout-or-nothing, same as every other hook in this directory. This one
# has nothing to tell the model -- it is pure plumbing for the statusline -- so it says nothing.
exit 0
