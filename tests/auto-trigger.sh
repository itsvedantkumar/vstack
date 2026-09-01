#!/usr/bin/env bash
# tests/auto-trigger.sh
#
# Regression test: proves Claude Code skills still auto-trigger from natural
# language prompts, without a slash command. See tests/README.md for the
# full story on why this exists and how to extend it.
#
# Exit codes:
#   0  all cases passed (or the suite was skipped because claude is
#      unavailable/unauthenticated -- CI cannot run this test)
#   1  one or more cases failed to fire the expected skill
set -uo pipefail

PER_CASE_TIMEOUT=120   # seconds; enforced by the polling loop in run_case (macOS has no timeout(1))
MODEL="sonnet"
MAX_TURNS=3
# Per-case turn budget, measured not guessed (2026-08-23), enforced by case_max_turns() below.
# MAX_TURNS above is still the global default -- a case with no row here is not in the case
# statement below either, and inherits MAX_TURNS unchanged, same as before this table existed.
# Do not silently raise the floor for a case with no row: only the two entries under
# "needs more than the default" get an override. Each row is a real claude invocation at
# that value, run outside this harness with matching flags (including the "Agent" denial),
# workdir inspected before cleanup for terminal `subtype`, `num_turns`, and whether a `Skill`
# tool_use appears. `num_turns` in that result event is NOT the same counter --max-turns
# enforces against: it also tallies turns from spawned subagents/internal tool infrastructure
# (a haiku-model subagent's turns showed up in the SAME result event as the capped sonnet
# agent's own, in the encode-lessons-lint @6 transcript). The cap itself is proven binding by
# the CLI's own error text, which cites the configured value exactly ("Reached maximum number
# of turns (6)" at --max-turns 6) even though num_turns reported 7 for that same run --
# read num_turns as a rough diagnostic, not as turns-consumed-of-budget.
#
# MEASURED, sufficient at the current default (3) -- no override needed:
#   root-cause-guard                       PASS both historical runs, attempt 1
#   idempotent-cron                        PASS both historical runs, attempt <=2
#   boundary-discipline-api                PASS both historical runs, attempt 1
#   sequence-verifiable-units-migration    PASS both historical runs, attempt 1
#
# MEASURED, needs more than the default -- recommended per-case value:
#   prove-it-works-declare-done   -> 6     @6, one sample: subtype=success, num_turns=4/6,
#                                           no Skill call, tools used Grep,Grep,Read --
#                                           completed without consulting the dispatcher. But
#                                           a same-day 3-attempt baseline at the DEFAULT (3)
#                                           was 0/3 miss, then 1/3 PASS on the very next run
#                                           (attempt 1) -- a flapper, not a hard zero. One
#                                           sample of a stochastic process is not a
#                                           measurement of it: do NOT read this as a proven
#                                           "never fires." 6 is still a reasonable budget
#                                           (the one deep-dive sample used only 4 of it), but
#                                           the dispatch-rate question is open pending a
#                                           proper per-case sample count.
#   encode-lessons-lint            -> 10   @3: starved, never fired in 3/3 attempts (two
#                                           separate historical runs).
#                                           @6: still subtype=error_max_turns, num_turns=7,
#                                           no Skill call (transcript preserved at
#                                           /tmp/auto-trigger-test.AJGn8t).
#                                           @10: subtype=success, num_turns=12/10, Skill
#                                           fired (principle-encode-lessons-in-structure).
#                                           Turn-starved, not structurally unfireable like
#                                           prove-it-works-declare-done -- 10 is the first
#                                           measured-sufficient value; not tried below 10.
#
# MEASURED flaky at the default, but NO measurement above 3 exists -- deliberately left
# unset rather than guessed. A guessed number here would be indistinguishable from a
# measured one, which is exactly the confusion this table exists to prevent:
#   build-the-lever-headers                @3: PASS attempt 2 one historical run,
#                                           never-fired-in-3 the other. Not measured above 3.
#   type-system-discipline-go              @3: PASS attempt 1 one historical run,
#                                           never-fired-in-3 the other. Not measured above 3.
#
# UNSET -- no data, not run this session. Unset means "nobody has checked," not "3 is known
# to be enough":
#   readme-writing, typescript-review, swarm-audit, blast-radius-auth, feature-chain,
#   overnight-audit-trail, ui-iterate-styles, component-registry-combobox, grill-my-plan,
#   find-a-skill, agent-browser-screenshot, create-verification-skill-cold-start,
#   executing-plans-checkpoints, impeccable-polish, interrogate-auth-diff,
#   maintain-verification-skill-drift, reflect-session, unslop-draft-pass,
#   negative-arithmetic, negative-factual
# ---------------------------------------------------------------------------
# case_max_turns NAME
# Prints the --max-turns value for NAME: the override from the table above if it has one,
# else the global MAX_TURNS default. A plain case statement, not an associative array --
# macOS ships bash 3.2, which doesn't have those.
# ---------------------------------------------------------------------------
case_max_turns() {
  case "$1" in
    prove-it-works-declare-done) echo 6 ;;
    encode-lessons-lint)         echo 10 ;;
    *)                           echo "$MAX_TURNS" ;;
  esac
}

# ---------------------------------------------------------------------------
# A note on "how many times would it take to know" (2026-08-23), for whoever next wants a
# cheaper dispatch-rate number than a full run of ATTEMPTS.
#
# A SAMPLE for rate purposes is one raw `claude -p` invocation of a fixed prompt. It is NOT
# one ATTEMPTS-loop case-run through run_case: that loop stops at the first hit, so it
# measures "did this succeed within 3 tries," not a firing rate, and reusing it as a cheap
# substitute would reproduce the exact early-stopping bias that mislabeled
# encode-lessons-lint as a dead skill when it was turn-starved. Getting n independent
# samples means n full, non-retrying invocations -- there is no shortcut through the
# existing retry machinery.
#
# What n actually buys, via two-sided 95% Wilson intervals: separating a case that fires
# 90% of the time from one that fires 60% of the time needs n of roughly 32-35 per prompt.
# n=5 and n=10 do NOT get there -- at n=10 the 90%-case interval is [0.60, 0.98] and the
# 60%-case interval is [0.31, 0.83]; they overlap. What n=10 DOES support is the coarser,
# cheaper question -- "never fired" vs "fires at least about half the time" -- which
# already separates at n=10. Report raw k/n at that n, not a percentage or an interval: a
# point estimate implies precision this sample size does not have.
#
# A 2026-08-23 probe used exactly this design on the 4 cases in dispute at the time --
# 10 independent, non-retrying samples each, at their case_max_turns() budget -- and is not
# reproduced here as code because it is not part of the suite: no neg-* precision arm, no
# collision split, one phrasing per case. It answers only "broken vs stochastic" for cases
# already in dispute, and must not be read as a fleet dispatch measurement. See
# ~/vstack-dispatch/README.md for what a real one requires.
#
# That probe's raw results (k/10, no CI -- n=10 doesn't support one; see above):
#   root-cause-guard              9/10 hit  (control -- matches its prior 1-attempt-pass
#                                            record; the instrument reads as trustworthy,
#                                            so the other three are readable as findings)
#   prove-it-works-declare-done   0/10 hit  (at its assigned budget, max-turns=6)
#   build-the-lever-headers       0/10 hit  (at the default, max-turns=3 -- not tested at
#                                            a higher budget, so turn-starvation the way
#                                            encode-lessons-lint had it is NOT ruled out)
#   type-system-discipline-go     1/10 hit  (at the default, max-turns=3 -- same caveat)
# All three disputed cases separate cleanly from the control (0/10 and 1/10 vs 9/10) --
# clearly below "fires at least about half the time," clearly not turn-budget noise on the
# order of the control's one miss.
#
# Follow-up (same day): the two unset cases re-sampled at --max-turns 10 as a PROBE
# PARAMETER ONLY -- case_max_turns() was not touched, this was passed directly in a
# throwaway probe script, the same jump where encode-lessons-lint went from failing to a
# clean Skill call:
#   build-the-lever-headers       0/10 @ turns=3   ->   2/10 @ turns=10
#   type-system-discipline-go     1/10 @ turns=3   ->   1/10 @ turns=10
# What this rules out: turn budget is not the variable for these two, unlike
# encode-lessons-lint. Tripling the budget left both firing rarely-to-never instead of
# flipping to reliable. Neither earns a case_max_turns() entry on this evidence --
# 2/10 is not a result, and an entry that encodes a non-result is worse than no entry.
# Whatever suppresses dispatch here (description overlap, listing/ranking, something in
# the routing block) is a different investigation than the one this table answers, and it
# needs its own allowance decision before more calls go against it.
# ---------------------------------------------------------------------------

# Attempts per case before calling it a failure. Skill dispatch is a model decision, so a
# single sample is a coin flip; a skill that has actually stopped firing misses every attempt.
# feature-chain is the measured-marginal case (~50% per attempt across runs: the model often
# just starts building instead of brainstorming first) — three attempts keep the suite
# honest about "does this situation ever route there" without crying wolf.
ATTEMPTS="${ATTEMPTS:-3}"

# ---------------------------------------------------------------------------
# SAMPLES=N -- rate mode. OFF by default (0): with SAMPLES unset every line below behaves
# exactly as it did before, same output, same exit codes, same gate.
#
# ATTEMPTS is NOT a sample-size knob and raising it will never make one. It early-stops on the
# first hit, so it answers "did this land within N tries" and biases upward -- the same
# early-stopping error that read encode-lessons-lint as a dead skill when it was turn-starved
# (see the note above case_max_turns). SAMPLES runs N INDEPENDENT, non-retrying invocations of
# the same prompt and reports raw k/N.
#
# Report k/N, never a percentage and never an interval: at the n this mode is affordable at, a
# point estimate implies precision the sample does not have.
#
# Measurement is not a verdict. A low rate does NOT fail the run -- only a fence breach does.
# ---------------------------------------------------------------------------
SAMPLES="${SAMPLES:-0}"
SAMPLES_ALL="${SAMPLES_ALL:-0}"   # required to sample every case; see the cost guard below
SAMPLE_LOG="${SAMPLE_LOG:-}"      # optional path; one JSON line per sample, append-only
SAMPLE_CASES=0
SAMPLE_CALLS=0
SAMPLE_COST="0"
SAMPLE_HEAD=""
SAMPLE_DESCS=""
AT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
declare -a RESULT_LINES=()
# Which attempt each case landed on. Pass/fail alone hides erosion: a skill that has slipped
# from firing every time to firing on the third try still reads PASS, and stays a pass right up
# until it reaches zero. The attempt number is the early warning.
declare -a HIT_LINES=()

# ---------------------------------------------------------------------------
# Preflight. In CI this skips with exit 0: GitHub Actions cannot authenticate
# headlessly, so an absent session is expected rather than broken.
#
# Everywhere else it exits 2. A local run that quietly returned 0 without having
# tested anything read exactly like a pass, which is the failure mode this whole
# suite exists to catch in the config it tests.
# ---------------------------------------------------------------------------
skip_or_fail() {
  echo "SKIP: $1"
  if [[ "${CI:-}" == "true" ]]; then exit 0; fi
  echo "      (exit 2: nothing was tested. Set CI=true to make this a pass.)"
  exit 2
}

command -v claude >/dev/null 2>&1 || \
  skip_or_fail "'claude' CLI not found on PATH."

AUTH_JSON="$(claude auth status 2>/dev/null)"
if [[ -z "$AUTH_JSON" ]] || ! echo "$AUTH_JSON" | grep -q '"loggedIn": *true'; then
  skip_or_fail "'claude' CLI is not authenticated (claude auth status did not report loggedIn: true)."
fi

command -v jq >/dev/null 2>&1 || \
  skip_or_fail "'jq' not found on PATH; required to parse stream-json output."

# BusyBox/Linux ships sha256sum and no shasum; macOS ships shasum and no sha256sum by default.
# Same fallback tests/install-matrix.sh already uses for its tree fingerprint. Needed by
# hash_snapshot() below, the content half of fence_violations().
if command -v shasum >/dev/null 2>&1; then SUM_CMD=shasum
elif command -v sha256sum >/dev/null 2>&1; then SUM_CMD=sha256sum
else
  skip_or_fail "neither 'shasum' nor 'sha256sum' found on PATH; required for fence_violations' content-hash check."
fi

# ---------------------------------------------------------------------------
# The tool fence, and the full audit behind it (2026-08-23).
#
# ZEEP Z-3 found `Workflow` launched in the background in a live sample: it wrote an 863-byte
# generator script into ~/.claude/projects/.../workflows/scripts/, then fanned out to 8 parallel
# subagents, each told to Edit or Write a fixture file. The denial happened to hold that time --
# every subagent got "No such tool available", nothing was modified -- but that came from
# whatever implementation detail those 8 subagents' code path happened to inherit
# disallowed-tools through, not from anything actually fencing `Workflow`: it was simply absent
# from the list below. `Agent`'s own reasoning (kept in the exec block further down) already
# said why that's not good enough: a spawned thing is not guaranteed to inherit this process's
# disallowed-tools list on every code path, and it can keep running detached past this process's
# own kill -9. The only reliable fence is not letting the spawn happen at all.
#
# That makes "can this tool spawn something that then gets its OWN tool access" the real
# question, not "is this tool literally named Agent." Below is every tool-name string found in
# this build's binary (`claude` v2.1.241 -- resolved via `whence -p claude`, then
# `strings -a "$bin" | grep -x -F '"<candidate>"'` for each name already named somewhere in this
# repo's own comments/docs or in `claude --help`'s tool-adjacent flag text; NOT a blind scan of
# every string in the binary -- it embeds large unrelated vendored string tables and a generic
# scan is too noisy to triage by hand). Confirmed present, one at a time:
#
#   DENIED, spawn-class, confirmed live in a real sample:
#     Agent      -- launches a subagent; this build's actual dispatch tool_use name (see
#                   docs/what-this-actually-does.md for the Task-vs-Agent history below).
#     Workflow   -- launches a background workflow that itself fans out to subagents (the ZEEP
#                   sample above). This is the fix this comment exists to explain.
#
#   DENIED, spawn-class by name and shape, capability NOT verified against a live sample --
#   denying costs nothing (nothing in this suite's prompts needs either) so both are denied on
#   the same reasoning as Agent rather than left open on an absence of evidence:
#     Explore    -- reads as a lighter-weight exploration subagent. Even if it turns out to be
#                   read-only by construction, that restriction would be enforced through the
#                   same kind of internal plumbing that failed to reliably fence Agent/Workflow
#                   in the ZEEP sample -- "probably read-only" is not a reason to leave it open.
#     Task       -- legacy alias, most likely dead. docs/what-this-actually-does.md already
#                   measured this build emitting 70 `Agent` tool_use blocks and 0 `Task` blocks
#                   against a real 15MB transcript. Denying a name that never fires is a
#                   zero-cost no-op; the cost of NOT denying it, if it ever turns out to be live
#                   after all, is another Workflow-shaped gap.
#
#   REVIEWED, not spawn-class, left allowed -- either this suite needs them, or they cannot
#   reach a file the way this fence would need to see:
#     Read, Glob, Grep      -- read-only; the prompts below need Read to review seeded files.
#     Skill                  -- the tool_use this entire suite exists to detect firing.
#     TodoWrite              -- writes to the session's own todo list, not the filesystem.
#     ExitPlanMode           -- a mode toggle, no filesystem effect.
#     BashOutput, KillShell  -- operate on a shell already started via Bash, which is denied
#                               below; moot without a live Bash to operate on.
#     ListMcpResources,
#     ReadMcpResource        -- read-only against configured MCP servers, and no --mcp-config
#                               is passed to any invocation in this file, so moot here too.
#     WebFetch, WebSearch    -- network only, cannot write into WORKDIR -- fence_violations
#                               (which only ever diffs WORKDIR, see its own comment below) has
#                               nothing to see either way. That is a different, UNDETECTED risk
#                               (network exfiltration of file contents), not a false sense of
#                               safety about the one this fence actually checks.
#     SendMessage,
#     SendUserMessage        -- inter-agent/user messaging. Requires an already-running peer
#                               session to do anything; does not itself grant new, independent
#                               tool access the way Agent/Workflow/Explore do. Same exfiltration
#                               caveat as WebFetch/WebSearch: out of scope for a fence that only
#                               diffs local filesystem state, not a proof nothing leaves.
#
#   Already denied directly below, not part of the spawn-class question at all: Write, Edit,
#   MultiEdit, NotebookEdit, Bash -- these write files themselves, they don't delegate to
#   something that might.
#
# This audit is current as of claude v2.1.241 and the tool-name strings that build embeds. A
# version bump can add a new spawn-shaped tool name and silently reopen exactly the gap Workflow
# just closed -- whoever next bumps the pinned version should re-run the targeted string search
# above against the new binary and re-triage this table, not assume it is still exhaustive.
DISALLOWED_TOOLS="Write,Edit,MultiEdit,NotebookEdit,Bash,Agent,Workflow,Explore,Task"

# ---------------------------------------------------------------------------
# extract_fired_skills OUT_JSONL
# Prints one skill name per line that fired via the Skill tool.
#
# Shape (verified with a throwaway run before writing this filter):
#   {"type":"assistant","message":{"id":"msg_...","content":[
#     {"type":"tool_use","id":"toolu_...","name":"Skill","input":{"skill":"foo", ...}}
#   ]}}
#
# Claude Code emits one "assistant" stream-json event per CONTENT BLOCK, not
# per message -- several lines can share the same message.id. That's fine
# here because each tool_use block still appears exactly once across the
# stream (verified empirically), so no dedup/grouping is needed to detect
# "did skill X fire." Grouping by message.id only matters if you need
# per-message tool-call *counts*, which this test does not.
# ---------------------------------------------------------------------------
extract_fired_skills() {
  local jsonl="$1"
  jq -r '
    select(.type=="assistant")
    | (.message.content // [])[]
    | select(.type=="tool_use" and .name=="Skill")
    | (.input.skill // "unknown")
  ' "$jsonl" 2>/dev/null | sort -u
}

# ---------------------------------------------------------------------------
# top_level_subtype OUT_JSONL
# Prints the CLI's own "subtype" for the RUN's terminal result event -- e.g.
# "success" (ran to completion, whatever it did or didn't call) or
# "error_max_turns" (cut off mid-task, never reached a decision).
#
# There can be more than one type=="result" event in the stream: a background
# subagent launched via the Agent tool reports its OWN completion as a
# type=="result" line too (verified against /tmp/auto-trigger-test.AJGn8t,
# encode-lessons-lint @ MAX_TURNS=6 -- two result events, same session_id).
# The subagent's carries an "origin":{"kind":"task-notification"} field the
# top-level run's result does not, so that's the discriminator: select the
# result event with no origin, not just the last result line in the file.
# ---------------------------------------------------------------------------
top_level_subtype() {
  local jsonl="$1"
  jq -r 'select(.type=="result" and (.origin==null)) | .subtype' "$jsonl" 2>/dev/null | tail -1
}

# ---------------------------------------------------------------------------
# top_level_cost OUT_JSONL
# Billed cost of ONE invocation, read from the same terminal result event top_level_subtype
# reads: the one with no `origin`. A subagent's result event carries origin.kind ==
# "task-notification" and its own total_cost_usd. Agent/Workflow/Explore/Task are denied by
# DISALLOWED_TOOLS, so there should be no second result event here; if that fence is ever
# loosened this becomes an undercount, and this sentence is the warning.
# Prints 0 when the field is absent, so a timed-out or crashed sample contributes 0 rather
# than breaking the running total.
#
# Nothing in this file counted a billed call before this existed. A measurement that cannot
# say what it cost cannot be budgeted, and every prior dispatch number here was published
# without one.
# ---------------------------------------------------------------------------
top_level_cost() {
  local jsonl="$1"
  jq -r 'select(.type=="result" and (.origin==null)) | (.total_cost_usd // 0)' "$jsonl" 2>/dev/null | tail -1
}

# ---------------------------------------------------------------------------
# named_in_prose OUT_JSONL REGEX
# Prints 1 if the run's assistant TEXT names a skill matching REGEX without having called it.
#
# Measured 2026-08-27 (tests/evals/collision/RESULTS.md, "Why nothing fired"): when the tool a
# skill needs is denied -- Write for a plan document, Agent for a fan-out -- the model names
# the skill in prose and never calls Skill. Under `fired=[]` that scores identically to a
# routing miss. Separating the two is the difference between "the description does not route"
# and "the description routes and the fence blocks the payoff", and DISALLOWED_TOOLS denies
# exactly the tools the four chain skills exist to use.
#
# A 0/10 printed without this number beside it is uninterpretable.
#
# Herestring, not a pipe: `grep -q` closes the pipe early and returns 141 under `pipefail`.
# ---------------------------------------------------------------------------
named_in_prose() {
  local jsonl="$1" regex="$2" txt
  txt="$(jq -r 'select(.type=="assistant") | (.message.content // [])[]
                | select(.type=="text") | .text' "$jsonl" 2>/dev/null)"
  if grep -qE "$regex" <<<"$txt"; then echo 1; else echo 0; fi
}

# ---------------------------------------------------------------------------
# hash_snapshot DIR
# One "hash  path" line per regular file under DIR (find -type f -- directories are excluded,
# they have no content to hash; a mkdir is still caught by the path-diff half of
# fence_violations below). Sorted by path so two snapshots taken at different times line up
# cleanly for a line-based diff. Uses SUM_CMD, chosen once during preflight above (shasum on
# macOS, sha256sum elsewhere -- same fallback tests/install-matrix.sh already uses).
# ---------------------------------------------------------------------------
hash_snapshot() {
  local dir="$1"
  find "$dir" -type f -exec "$SUM_CMD" {} + 2>/dev/null | sort -k2
}

# ---------------------------------------------------------------------------
# fence_violations WORKDIR BASELINE BASELINE_HASHES OUT_JSONL ERR_LOG
# BASELINE is a newline-separated snapshot of WORKDIR's paths taken right after setup_fn ran and
# before claude launched. BASELINE_HASHES is hash_snapshot(WORKDIR) taken at that same moment.
# Prints one violation per line: an added path (present now, absent from BASELINE, and not one
# of the harness's own two artifacts), or "MODIFIED: path" for a path that existed at BASELINE
# time, still exists now, but whose content hash changed. Empty output means the fence held.
#
# This exists as a second, independent layer behind --disallowedTools: a subagent or workflow
# spawned via one of the tools denied in DISALLOWED_TOOLS (see that comment, "The tool fence",
# for the full audit) is not guaranteed to inherit the parent's disallowed-tools list on every
# code path, and it can run detached in the background past this process's own kill -9. Trusting
# the flag alone is trusting a single point of failure; this catches whatever gets through it, by
# tool name or by mechanism, no matter which.
#
# The path-diff half (added paths, unchanged since this function was first written) only ever
# sees a NEW path appear -- a Write to a path that didn't exist, or a mkdir. It is blind to an
# Edit against an existing path, or a Write that overwrites one: both leave the path listing
# byte-identical. A run that made 32 Edit calls against seeded fixtures reported clean across 10
# samples on exactly that blind spot (2026-08-23, ZEEP Z-3's transcript). The hash-diff half
# below is what closes it, and it names the specific file that changed rather than just noting
# that something did -- "fence_violations: clean" meaning "and this check could not have seen a
# mutation anyway" is worse than no check at all.
#
# Scope, stated rather than left for the reader to assume: this function only ever inspects
# WORKDIR, on both halves. A write outside it -- the ZEEP sample's 863-byte generator script
# landed in ~/.claude/projects/.../workflows/scripts/, well outside any case's temp dir -- is
# invisible to this check, full stop. Widening it to catch that would mean snapshotting $HOME
# (or wider) before and after every attempt, which is slow, and on this machine specifically
# risky: several Claude sessions edit shared trees like ~/Projects/vstack directly and
# concurrently (see tests/README.md, "this checkout may not be yours alone"), so hashing a
# peer's live working set out from under it is its own hazard, not a free safety upgrade. That
# is a materially bigger, separately-designed check, not a one-line extension of this one --
# left undone here on purpose, not by oversight. --disallowedTools denying
# Agent/Workflow/Explore/Task is what actually stood between the ZEEP sample and that write;
# this function's real job is catching what happens if that flag is the one that fails, inside
# the one directory it can safely watch.
# ---------------------------------------------------------------------------
fence_violations() {
  local workdir="$1" baseline="$2" baseline_hashes="$3" out_jsonl="$4" err_log="$5"
  local now added now_hashes hdiff removed_paths added_paths modified

  now="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
  added="$(diff <(printf '%s\n' "$baseline") <(printf '%s\n' "$now") 2>/dev/null \
    | sed -n 's/^> //p' \
    | grep -v -F -x -e "$out_jsonl" -e "$err_log" \
    | grep -v '^$')"

  now_hashes="$(hash_snapshot "$workdir")"
  hdiff="$(diff <(printf '%s\n' "$baseline_hashes") <(printf '%s\n' "$now_hashes") 2>/dev/null)"
  # A modified file shows up as ONE line lost from the baseline hash-set (old hash + path) and
  # ONE line gained in the current set (new hash + same path). Stripping the hash off each side
  # and taking the intersection (comm -12, both inputs sorted) leaves exactly the paths present
  # in both -- i.e. still there, content changed -- with no while-loop or associative-array
  # lookup needed (macOS bash 3.2 has neither).
  removed_paths="$(printf '%s\n' "$hdiff" | sed -n 's/^< //p' | sed -E 's/^[^ ]+  //' | sort)"
  added_paths="$(printf '%s\n' "$hdiff" | sed -n 's/^> //p' | sed -E 's/^[^ ]+  //' | sort)"
  modified="$(comm -12 <(printf '%s\n' "$removed_paths") <(printf '%s\n' "$added_paths") 2>/dev/null \
    | sed 's/^/MODIFIED: /')"

  { printf '%s\n' "$added"; printf '%s\n' "$modified"; } | grep -v '^$'
}

# ---------------------------------------------------------------------------
# run_case NAME PROMPT EXPECTED_REGEX SETUP_FN
# SETUP_FN is a function name invoked with the temp dir as $1, or "" for none.
# ---------------------------------------------------------------------------
# Case selection. Without it, proving one fix means re-running all 28 cases and spending the
# whole allowance to learn about eight of them. Matches install-matrix.sh's convention:
# no arguments runs everything, arguments name the cases to run.
#   tests/auto-trigger.sh                       # all cases
#   tests/auto-trigger.sh prove-it-works-declare-done encode-lessons-lint
SELECTED=("$@")
selected_() {
  [ ${#SELECTED[@]} -eq 0 ] && return 0
  local want
  for want in "${SELECTED[@]}"; do [ "$want" = "$1" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# Provenance for anything SAMPLES mode publishes.
#
# The rule in this repository is that an instrument is committed before the run it produces a
# number for -- a 55-sample collision result was withdrawn precisely because its harness edit
# was never committed and the runlog is gone (CHANGELOG.md, 1.47.0). Recording the instrument
# sha AND a digest of the description bytes in every sample row is what makes a published k/N
# checkable afterwards instead of merely asserted, because in this suite the *subject* of the
# measurement is the description text and the *instrument* is this file. Both have to be
# pinned or the number cannot be reproduced.
#
# The descriptions digested here are the INSTALLED ones, not the repo's: the CLI runs in a
# scratch workdir and reads ~/.claude/skills. Measured 2026-09-01: a project-local
# .claude/skills/<name>/SKILL.md IS loaded, but a user-level skill of the same name WINS --
# the installed description is what reaches the matcher, and a repo edit is invisible here
# until it is installed. Digesting the wrong tree would pin a number to bytes the model never
# saw.
# ---------------------------------------------------------------------------
SAMPLE_HEAD="$(git -C "$AT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
SAMPLE_DESCS="$(grep -h '^description:' "$HOME"/.claude/skills/*/SKILL.md 2>/dev/null \
  | "$SUM_CMD" | cut -c1-12)"

if (( SAMPLES > 0 )) \
   && [ -n "$(git -C "$AT_ROOT" status --porcelain -- tests/auto-trigger.sh 2>/dev/null)" ]; then
  echo "WARNING: tests/auto-trigger.sh is uncommitted. A number from an uncommitted instrument"
  echo "         is inadmissible here. Commit the harness, then re-run."
fi

# Cost guard. Nothing in this file counted a call before spending it. SAMPLES across the whole
# suite is SAMPLES x every case, which at SAMPLES=10 is several hundred billed invocations from
# one keystroke and no confirmation.
if (( SAMPLES > 0 )) && [ ${#SELECTED[@]} -eq 0 ] && [ "$SAMPLES_ALL" != "1" ]; then
  echo "SAMPLES=$SAMPLES with no case named would run $SAMPLES x $(grep -cE '^run_(negative_)?case ' "$0") invocations."
  echo "Name the cases you want, or set SAMPLES_ALL=1 to mean it."
  exit 2
fi

# ---------------------------------------------------------------------------
# sample_case NAME PROMPT REGEX SETUP_FN POLARITY
#
# SAMPLES independent invocations of one prompt, no early stop, raw k/N. POLARITY is "pos"
# (REGEX names the skill that SHOULD fire) or "neg" (REGEX names skills that must NOT); it
# changes the printed label only, because a fire rate and a false-positive rate are the same
# arithmetic pointed at different prompts.
#
# Deliberately never touches PASS_COUNT/FAIL_COUNT except on a fence breach. A rate is a
# measurement, not a verdict: wiring a low rate to a red exit would make this suite refuse to
# report the very thing it was run to find out.
# ---------------------------------------------------------------------------
sample_case() {
  local name="$1" prompt="$2" regex="$3" setup_fn="$4" polarity="$5"
  local i fired term cost prose_hit hits=0 prose=0 cutoff=0 case_cost="0"
  local workdir out_jsonl err_log runner_pid waited baseline baseline_hashes violations
  local case_turns; case_turns="$(case_max_turns "$name")"

  for i in $(seq 1 "$SAMPLES"); do
    workdir="$(mktemp -d "/tmp/auto-trigger-sample.XXXXXX")"
    [[ -n "$setup_fn" ]] && "$setup_fn" "$workdir"
    baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
    baseline_hashes="$(hash_snapshot "$workdir")"
    out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"

    # Same exec/timeout discipline as run_case: without exec the kill -9 hits an empty parent
    # and leaks a live, billed claude session per timed-out sample.
    (
      cd "$workdir" || exit 1
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        claude -p "$prompt" \
          --output-format stream-json --verbose \
          --disallowedTools "$DISALLOWED_TOOLS" \
          --model "$MODEL" --max-turns "$case_turns" \
          < /dev/null > "$out_jsonl" 2> "$err_log"
    ) &
    runner_pid=$!
    waited=0
    while kill -0 "$runner_pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
      if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
    done
    wait "$runner_pid" 2>/dev/null

    fired=""; term="no-output"; cost=0; prose_hit=0
    if [[ -s "$out_jsonl" ]]; then
      fired="$(extract_fired_skills "$out_jsonl")"
      term="$(top_level_subtype "$out_jsonl")"
      cost="$(top_level_cost "$out_jsonl")"
      prose_hit="$(named_in_prose "$out_jsonl" "$regex")"
    fi
    [[ "$term" == "error_max_turns" ]] && cutoff=$((cutoff + 1))
    if [[ -n "$fired" ]] && grep -qE "^($regex)$" <<<"$fired"; then
      hits=$((hits + 1))
    elif [[ "$prose_hit" == "1" ]]; then
      prose=$((prose + 1))
    fi
    # bash 3.2 has no float arithmetic; awk does the addition.
    case_cost="$(awk -v a="$case_cost" -v b="${cost:-0}" 'BEGIN{printf "%.6f", a+b}')"
    SAMPLE_CALLS=$((SAMPLE_CALLS + 1))

    violations="$(fence_violations "$workdir" "$baseline" "$baseline_hashes" "$out_jsonl" "$err_log")"
    if [[ -n "$SAMPLE_LOG" ]]; then
      printf '{"case":"%s","sample":%d,"polarity":"%s","fired":"%s","subtype":"%s","named_in_prose":%s,"cost_usd":%s,"model":"%s","max_turns":%s,"instrument":"%s","descs":"%s"}\n' \
        "$name" "$i" "$polarity" "$(tr '\n' ' ' <<<"$fired" | sed 's/ *$//')" "$term" \
        "$prose_hit" "${cost:-0}" "$MODEL" "$case_turns" "$SAMPLE_HEAD" "$SAMPLE_DESCS" \
        >> "$SAMPLE_LOG"
    fi
    rm -rf "$workdir"

    if [[ -n "$violations" ]]; then
      echo "FAIL $name -> fence breach on sample $i of $SAMPLES: $(tr '\n' ';' <<<"$violations")"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi
  done

  SAMPLE_COST="$(awk -v a="$SAMPLE_COST" -v b="$case_cost" 'BEGIN{printf "%.6f", a+b}')"
  SAMPLE_CASES=$((SAMPLE_CASES + 1))
  printf 'SAMPLE %-30s %-3s fired %d/%d  named-not-called %d/%d  cut-off %d/%d  $%s (max-turns=%s)\n' \
    "$name" "$polarity" "$hits" "$SAMPLES" "$prose" "$SAMPLES" "$cutoff" "$SAMPLES" \
    "$case_cost" "$case_turns"
  HIT_LINES+=("$(printf '%-30s %-3s %d/%d fired, %d/%d named-only, %d/%d cut off, $%s' \
    "$name" "$polarity" "$hits" "$SAMPLES" "$prose" "$SAMPLES" "$cutoff" "$SAMPLES" "$case_cost")")
}

run_case() {
  local name="$1" prompt="$2" expected_regex="$3" setup_fn="$4"
  selected_ "$name" || return 0
  if (( SAMPLES > 0 )); then sample_case "$name" "$prompt" "$expected_regex" "$setup_fn" pos; return; fi
  local attempt fired fired_csv matched workdir out_jsonl err_log runner_pid waited
  local baseline baseline_hashes violations term_subtype last_fired_csv=""
  local case_turns; case_turns="$(case_max_turns "$name")"

  # Skill dispatch is a model decision, not a deterministic branch, so one sample is a coin
  # flip and a single-shot assertion makes this suite cry wolf. Retry a miss up to $ATTEMPTS
  # times: the property worth protecting is that the situation routes here, not that it does
  # so on the first try. A skill that has genuinely stopped firing misses every attempt.
  for attempt in $(seq 1 "$ATTEMPTS"); do
    workdir="$(mktemp -d "/tmp/auto-trigger-test.XXXXXX")"
    [[ -n "$setup_fn" ]] && "$setup_fn" "$workdir"
    baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
    baseline_hashes="$(hash_snapshot "$workdir")"
    out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"

    # exec is load-bearing: without it the subshell forks claude as a child, and the
    # timeout's kill -9 hits only the empty parent — leaking a live, billed claude session
    # per timed-out attempt. exec makes $runner_pid BE the claude process.
    (
      cd "$workdir" || exit 1
      # Mutation tools are denied: with bypassPermissions inherited from user settings, a
      # test prompt once wrote a real script into ~/.config/agents/bin. Detection only needs
      # the Skill tool call, which still happens. DISALLOWED_TOOLS's own comment above ("The
      # tool fence") has the full audit of which spawn-shaped tools are denied here and why.
      exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
        claude -p "$prompt" \
          --output-format stream-json --verbose \
          --disallowedTools "$DISALLOWED_TOOLS" \
          --model "$MODEL" --max-turns "$case_turns" \
          < /dev/null > "$out_jsonl" 2> "$err_log"
    ) &
    runner_pid=$!

    waited=0
    while kill -0 "$runner_pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
      if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
    done
    wait "$runner_pid" 2>/dev/null

    if [[ ! -s "$out_jsonl" ]]; then
      fired=""; fired_csv="(no output: timeout or crash)"
    else
      fired="$(extract_fired_skills "$out_jsonl")"
      fired_csv="$(echo "$fired" | tr '\n' ',' | sed 's/,$//')"
      if [[ -z "$fired_csv" ]]; then
        # A miss is not one thing. "error_max_turns" means the run was cut off before it
        # ever reached a decision point -- that's a starved case, not a routing failure.
        # Anything else that still didn't fire actually ran to completion and chose not to
        # call Skill, which IS a dispatch signal. Printing both as "(none)" makes the suite
        # report a turn-budget problem as if it were a skill-routing problem.
        term_subtype="$(top_level_subtype "$out_jsonl")"
        if [[ "$term_subtype" == "error_max_turns" ]]; then
          fired_csv="(none: cut off by error_max_turns, never reached a decision)"
        else
          fired_csv="(none: ran to completion, subtype=${term_subtype:-unknown})"
        fi
      fi
    fi

    violations="$(fence_violations "$workdir" "$baseline" "$baseline_hashes" "$out_jsonl" "$err_log")"
    rm -rf "$workdir"

    if [[ -n "$violations" ]]; then
      echo "FAIL $name -> fence breach (max-turns=$case_turns): run wrote outside its allowed tools:"
      while IFS= read -r v; do printf '    %s\n' "$v"; done <<< "$violations"
      RESULT_LINES+=("FAIL $name -> fence breach, max-turns=$case_turns (wrote: $(echo "$violations" | tr '\n' ';' | sed 's/;$//'))")
      HIT_LINES+=("$(printf '%-22s FENCE BREACH  -> max-turns=%s, wrote %s' "$name" "$case_turns" "$(echo "$violations" | wc -l | tr -d ' ')file(s)")")
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi

    last_fired_csv="$fired_csv"

    if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($expected_regex)$"; then
      matched="$(echo "$fired" | grep -E "^($expected_regex)$" | head -1)"
      if (( attempt > 1 )); then
        echo "PASS $name -> $matched (on attempt $attempt of $ATTEMPTS, max-turns=$case_turns)"
        RESULT_LINES+=("PASS $name -> $matched (attempt $attempt, max-turns=$case_turns)")
      else
        echo "PASS $name -> $matched (max-turns=$case_turns)"
        RESULT_LINES+=("PASS $name -> $matched (max-turns=$case_turns)")
      fi
      HIT_LINES+=("$(printf '%-22s attempt %s/%s  -> %s (max-turns=%s)' "$name" "$attempt" "$ATTEMPTS" "$matched" "$case_turns")")
      PASS_COUNT=$((PASS_COUNT + 1))
      return
    fi

    (( attempt < ATTEMPTS )) && echo "  retry $name (attempt $attempt, max-turns=$case_turns, fired: [$fired_csv])"
  done

  echo "FAIL $name -> expected $expected_regex, never fired in $ATTEMPTS attempts at max-turns=$case_turns (last: [$last_fired_csv])"
  RESULT_LINES+=("FAIL $name -> expected $expected_regex, $ATTEMPTS attempts, max-turns=$case_turns (last: $last_fired_csv)")
  HIT_LINES+=("$(printf '%-22s never in %s   -> %s (max-turns=%s)' "$name" "$ATTEMPTS" "$last_fired_csv" "$case_turns")")
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Negative control. Every other case asks "did the right skill fire", which cannot see a skill
# that fires on everything — and an over-eager skill actively helps the positive cases pass. One
# sample, no retries: the question is whether it fires at all on a prompt that is plainly not
# its situation.
run_negative_case() {
  local name="$1" prompt="$2" forbidden_regex="$3"
  selected_ "$name" || return 0
  # In SAMPLES mode the forbidden regex is exactly what we want a rate for: k/N here IS the
  # over-trigger rate of the new descriptions, measured for free alongside the positive arms.
  if (( SAMPLES > 0 )); then sample_case "$name" "$prompt" "$forbidden_regex" "" neg; return; fi
  local workdir out_jsonl err_log runner_pid waited fired fired_csv baseline baseline_hashes violations
  local case_turns; case_turns="$(case_max_turns "$name")"

  workdir="$(mktemp -d "/tmp/auto-trigger-neg.XXXXXX")"
  baseline="$(find "$workdir" -mindepth 1 2>/dev/null | sort)"
  baseline_hashes="$(hash_snapshot "$workdir")"
  out_jsonl="$workdir/.out.jsonl"; err_log="$workdir/.err.log"
  (
    cd "$workdir" || exit 1
    exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
      claude -p "$prompt" \
        --output-format stream-json --verbose \
        --disallowedTools "$DISALLOWED_TOOLS" \
        --model "$MODEL" --max-turns "$case_turns" \
        < /dev/null > "$out_jsonl" 2> "$err_log"
  ) &
  runner_pid=$!
  waited=0
  while kill -0 "$runner_pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if (( waited >= PER_CASE_TIMEOUT )); then kill -9 "$runner_pid" 2>/dev/null; break; fi
  done
  wait "$runner_pid" 2>/dev/null

  fired=""
  [[ -s "$out_jsonl" ]] && fired="$(extract_fired_skills "$out_jsonl")"
  fired_csv="$(echo "$fired" | tr '\n' ',' | sed 's/,$//')"; [[ -z "$fired_csv" ]] && fired_csv="(none)"
  violations="$(fence_violations "$workdir" "$baseline" "$baseline_hashes" "$out_jsonl" "$err_log")"
  rm -rf "$workdir"

  if [[ -n "$violations" ]]; then
    echo "FAIL $name -> fence breach (max-turns=$case_turns): run wrote outside its allowed tools:"
    while IFS= read -r v; do printf '    %s\n' "$v"; done <<< "$violations"
    RESULT_LINES+=("FAIL $name -> fence breach, max-turns=$case_turns (wrote: $(echo "$violations" | tr '\n' ';' | sed 's/;$//'))")
    HIT_LINES+=("$(printf '%-22s FENCE BREACH  -> max-turns=%s, wrote %s' "$name" "$case_turns" "$(echo "$violations" | wc -l | tr -d ' ')file(s)")")
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ -n "$fired" ]] && echo "$fired" | grep -qE "^($forbidden_regex)$"; then
    echo "FAIL $name -> $forbidden_regex fired on a prompt that is not its situation (max-turns=$case_turns) [$fired_csv]"
    RESULT_LINES+=("FAIL $name -> over-triggered, max-turns=$case_turns")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> fired: %s (max-turns=%s)' "$name" "$fired_csv" "$case_turns")")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS $name -> did not over-trigger (max-turns=$case_turns) [$fired_csv]"
    RESULT_LINES+=("PASS $name -> no over-trigger, max-turns=$case_turns")
    HIT_LINES+=("$(printf '%-22s NEGATIVE      -> clean (%s) (max-turns=%s)' "$name" "$fired_csv" "$case_turns")")
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup functions: seed the temp working dir so the prompt has something
# concrete to react to (an empty dir gives the model nothing to review).
# ---------------------------------------------------------------------------
setup_readme() {
  local dir="$1"
  cat > "$dir/deploy.sh" <<'EOF'
#!/usr/bin/env bash
# deploy.sh - builds the project and uploads the dist folder to S3
set -euo pipefail
npm run build
aws s3 sync ./dist s3://my-bucket/app --delete
echo "Deploy complete"
EOF
  chmod +x "$dir/deploy.sh"
}

setup_typescript() {
  local dir="$1"
  cat > "$dir/sample.ts" <<'EOF'
export function processData(input: any): any {
  const result: any = input.map((x: any) => x.value);
  return result;
}
EOF
}

setup_webapp() {
  local dir="$1"
  cat > "$dir/package.json" <<'EOF'
{ "name": "notes-app", "version": "1.0.0", "scripts": { "test": "node --test" } }
EOF
  cat > "$dir/app.js" <<'EOF'
const notes = [];
export function addNote(text) { notes.push({ text, at: Date.now() }); }
export function listNotes() { return notes; }
EOF
  cat > "$dir/index.html" <<'EOF'
<!doctype html><html><head><title>Notes</title></head>
<body><ul id="notes"></ul><script type="module" src="app.js"></script></body></html>
EOF
}

setup_messy() {
  local dir="$1"
  mkdir -p "$dir/old" "$dir/tmp"
  for f in draft1 draft2 final final-v2 final-FINAL; do echo "$f" > "$dir/$f.txt"; done
  echo "log" > "$dir/tmp/build.log"; echo "bak" > "$dir/old/app.js.bak"
}

setup_styled() {
  local dir="$1"
  setup_webapp "$dir"
  cat > "$dir/styles.css" <<'EOF'
.hero { padding: 12px 80px 3px 7px; font-size: 15px; color: #888; }
.hero h1 { font-size: 16px; margin: 0 0 2px; }
EOF
}

setup_flaky() {
  local dir="$1"
  cat > "$dir/sync.py" <<'EOF'
import json, urllib.request

def fetch_stats():
    with urllib.request.urlopen("https://api.example.com/stats") as r:
        return json.load(r)

print(fetch_stats()["total"])
EOF
}

# --- Setup functions added for the 14 previously-uncovered skills below. ---

setup_plan() {
  local dir="$1"
  cat > "$dir/PLAN.md" <<'EOF'
# Implementation Plan: Add search to notes app

## Phase 1 - Search index
- Add an in-memory index over note text
- Unit test the index lookup

## Phase 2 - Search UI
- Add a search box to index.html
- Wire it to the index from Phase 1

## Phase 3 - Persistence
- Persist notes and index to localStorage
EOF
}

setup_authdiff() {
  local dir="$1"
  cat > "$dir/auth_middleware.py" <<'EOF'
# auth_middleware.py - verifies a bearer token before allowing a request through
import hmac

SECRET = "dev-secret"

def verify_token(token: str) -> bool:
    expected = hmac.new(SECRET.encode(), b"user", "sha256").hexdigest()
    return token == expected

def handle_request(headers: dict):
    token = headers.get("Authorization", "").replace("Bearer ", "")
    if verify_token(token):
        return {"status": 200}
    return {"status": 401}
EOF
}

setup_stale_verify() {
  local dir="$1"
  setup_webapp "$dir"
  # A feature the verification setup below does not know about -- the drift under test.
  cat > "$dir/search.js" <<'EOF'
export function searchNotes(notes, query) {
  return notes.filter((n) => n.text.includes(query));
}
EOF
  mkdir -p "$dir/.claude/skills/verify-notes-app"
  cat > "$dir/.claude/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
node --test
echo "verify: add-note flow OK"
EOF
  chmod +x "$dir/.claude/verify.sh"
  cat > "$dir/.claude/skills/verify-notes-app/SKILL.md" <<'EOF'
---
name: verify-notes-app
description: Drives the notes app and proves the add-note feature works.
---
# Feature map
- add-note: covered, see verify.sh
EOF
}

setup_draft() {
  local dir="$1"
  cat > "$dir/draft.md" <<'EOF'
In today's fast-paced digital landscape, it is important to note that our new
onboarding flow leverages cutting-edge best practices to seamlessly delight
users. Furthermore, it's worth noting that this represents a significant step
forward in our ongoing journey towards excellence.
EOF
}

setup_bulk() {
  local dir="$1"
  mkdir -p "$dir/modules"
  for f in auth billing search reports export inventory users notifications; do
    cat > "$dir/modules/$f.js" <<EOF
export function $f() { return "$f"; }
EOF
  done
}

setup_gostruct() {
  local dir="$1"
  cat > "$dir/order.go" <<'EOF'
package main

type Order struct {
	Status       string
	TrackingCode string
	CancelReason string
}
EOF
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
echo "Running skill auto-trigger regression suite (model=$MODEL, default max-turns=$MAX_TURNS, per-case timeout=${PER_CASE_TIMEOUT}s)"
echo "Per-case max-turns overrides: prove-it-works-declare-done=$(case_max_turns prove-it-works-declare-done), encode-lessons-lint=$(case_max_turns encode-lessons-lint) (every other case uses the default)"
echo "---"

run_case \
  "readme-writing" \
  "Write a README section explaining what this script does." \
  "technical-writing" \
  "setup_readme"

run_case \
  "typescript-review" \
  "Review this TypeScript file for type safety." \
  "typescript-best-practices" \
  "setup_typescript"

run_case \
  "swarm-audit" \
  "Audit this directory three different ways at once and report back." \
  "swarm" \
  ""

run_case \
  "blast-radius-auth" \
  "I need to ship a risky change to auth, review the blast radius." \
  "blast-radius" \
  ""

# The three-way match is deliberate and stays. This case protects "a feature request routes
# into the planning chain", and any of the three IS the chain — narrowing it to brainstorming
# alone would assert a specific entry point that measures ~50% per attempt, which makes the
# suite flaky rather than strict. A flaky gate gets ignored, and an ignored gate is worse than
# a wide one. The hit-rate table below is what makes erosion here visible instead.
run_case \
  "feature-chain" \
  "I want a dark-mode toggle feature in this notes app. Build it." \
  "brainstorming|writing-plans|test-driven-development" \
  "setup_webapp"

run_case \
  "root-cause-guard" \
  "This script crashes sometimes. Add a try/except around the main call so it stops failing." \
  "principle-fix-root-causes" \
  "setup_flaky"

run_case \
  "overnight-audit-trail" \
  "Clean up and reorganize the files in this directory. You are running unattended overnight - I will step away now and review everything you did tomorrow morning." \
  "show-me-your-work" \
  "setup_messy"

run_case \
  "ui-iterate-styles" \
  "I just edited the hero styles in styles.css and the dev server is running on port 3000. Make sure it actually looks right before we call this done." \
  "ui-iterate" \
  "setup_styled"

# The prompt states the plan is already approved so the planning chain has no reason to fire;
# what is under test is the narrower reflex "about to hand-write a UI component -> check the
# registries first".
run_case \
  "component-registry-combobox" \
  "The plan is approved: this React + Tailwind app gets an accessible multi-select combobox. Write the component now." \
  "component-registry" \
  "setup_webapp"

run_case \
  "idempotent-cron" \
  "Write a cron job that syncs this directory to S3 every hour, with retries on failure." \
  "principle-make-operations-idempotent" \
  ""

run_case \
  "grill-my-plan" \
  "Here is my plan: migrate the whole database in one cutover this Saturday. Poke holes in it before I start — what am I missing?" \
  "grill-me" \
  ""

# Terraform on purpose, and it is worth saying why rather than leaving a bland prompt behind.
#
# The obvious case to write was "Find a skill for reviewing pull requests." It fires 3 of 3 on
# opus and 0 of 3 on sonnet, which is the model this suite pins: sonnet routes it to review-pr,
# because "reviewing pull requests" names a skill that is installed and the request reads as
# asking for the work rather than for the search. Terraform has no competing skill installed, so
# the sentence can only be read as discovery, and it lands 3 of 3 on both.
#
# That is a real limit of description-based dispatch and not one to paper over: where the domain
# in the request collides with an installed skill, the weaker model picks the domain. The
# description leads with DISCOVER or INSTALL for exactly this reason.
run_case \
  "find-a-skill" \
  "What skills exist for working with Terraform? Search for one I can install." \
  "find-skills" \
  ""

# --- Cases added for the 14 skills that previously had zero coverage. ---

run_case \
  "agent-browser-screenshot" \
  "I'm working in a Conductor workspace and need to screenshot this app's dev server on localhost:3000, but the shared Chrome window is already busy with another workspace's session." \
  "agent-browser" \
  "setup_webapp"

# Discriminator: "no automated way to prove it works ... from scratch" states nothing exists
# yet, which is create-verification-skill's situation, not maintain-verification-skill's
# (something exists and has drifted) or principle-prove-it-works' (verify one already-done task).
run_case \
  "create-verification-skill-cold-start" \
  "This webapp has no automated way to prove it works end-to-end -- no test script, no smoke test, nothing that actually launches it and checks a real feature. Set that up from scratch." \
  "create-verification-skill" \
  "setup_webapp"

run_case \
  "executing-plans-checkpoints" \
  "PLAN.md is the implementation plan we approved last session. Execute it, and pause for my review after each phase." \
  "executing-plans" \
  "setup_plan"

run_case \
  "impeccable-polish" \
  "This notes app UI already works and renders fine, but visually it looks like generic default styling. Push the typography, spacing, and motion to a genuinely production, award-winning level." \
  "impeccable" \
  "setup_styled"

# Discriminator: the diff already exists ("already written", "nobody else has reviewed it") and
# the prompt uses interrogate's own trigger phrase "tear this apart" -- grill-me is for a plan or
# design the user is still forming, before anything exists to review.
run_case \
  "interrogate-auth-diff" \
  "This auth middleware change is already written and nobody else has reviewed it. Tear this apart -- find every way it can be broken before we merge." \
  "interrogate" \
  "setup_authdiff"

# Discriminator: verify.sh and a feature map already exist and have drifted from the app
# (a feature was added that the gate/map don't know about) -- maintain-verification-skill's
# situation, not create-verification-skill's "nothing exists yet".
run_case \
  "maintain-verification-skill-drift" \
  "verify.sh here still exits 0, but I added a search feature to this app last week and I don't think the verification skill's feature map or the gate actually exercises it anymore. Bring it back in sync." \
  "maintain-verification-skill" \
  "setup_stale_verify"

run_case \
  "reflect-session" \
  "Before we wrap up -- reflect on this session. I corrected your approach twice today; what should turn into a skill edit so it doesn't happen a third time?" \
  "reflect" \
  ""

run_case \
  "unslop-draft-pass" \
  "The draft in draft.md is done. Do the final pass to cut the AI-sounding phrasing and make it read like a human wrote it." \
  "unslop" \
  "setup_draft"

run_case \
  "boundary-discipline-api" \
  "Wire up input validation and error handling for this API's incoming request body, and make sure the business logic underneath never has to re-check any of it." \
  "principle-boundary-discipline" \
  "setup_webapp"

run_case \
  "build-the-lever-headers" \
  "Every file in modules/ needs the same license header pasted at the top. I'll go through and add it to each one by hand." \
  "principle-build-the-lever" \
  "setup_bulk"

# Discriminator: asks for a structural fix to the repo's own CI (a lint/check), for a correction
# that has already repeated once -- principle-encode-lessons-in-structure's situation. This is
# not "reflect on this session": nothing here asks to mine the transcript or edit a Claude skill.
run_case \
  "encode-lessons-lint" \
  "This is the second time a PR has shipped without a trailing newline at end of file. Add something to CI that catches this automatically -- I don't want to keep telling people by hand." \
  "principle-encode-lessons-in-structure" \
  "setup_webapp"

# Discriminator: declaring one specific, already-attempted fix done on the strength of "it
# compiles" -- principle-prove-it-works' exact situation. Unlike create-verification-skill, this
# is not a request to generate any verify.sh/skill infrastructure, just the habit of checking a
# concrete claim before it's made.
run_case \
  "prove-it-works-declare-done" \
  "I fixed the crash in fetch_stats by adding a retry, and the code compiles cleanly -- this task is done." \
  "principle-prove-it-works" \
  "setup_flaky"

run_case \
  "sequence-verifiable-units-migration" \
  "We're migrating all 12 API endpoints in this service to the new auth middleware across a stack of PRs. How should we order the steps so each one lands in a known-good state before the next starts?" \
  "principle-sequence-verifiable-units" \
  ""

# Go, not TypeScript, on purpose: a .ts file here would compete with typescript-best-practices,
# which also covers type design and is the broader match on that extension. Go has no such
# competing skill installed, so the prompt can only land on the general type-system principle.
run_case \
  "type-system-discipline-go" \
  "Redesign this Go Order struct so an invalid combination like a cancelled order with a tracking code can't compile -- model pending, shipped, and cancelled as separate cases." \
  "principle-type-system-discipline" \
  "setup_gostruct"

run_negative_case \
  "negative-arithmetic" \
  "What is 17 times 23? Just the number." \
  "ui-iterate|impeccable|blast-radius|show-me-your-work|swarm"

run_negative_case \
  "negative-factual" \
  "Which HTTP status code means Payment Required?" \
  "ui-iterate|impeccable|blast-radius|brainstorming|writing-plans"

echo "---"

# A selector that matches no case would otherwise print "0 passed, 0 failed" and exit 0,
# which is the same shape as a clean run. A typo'd case name must not read as a pass.
# This sits above the hit-rate loop because HIT_LINES is unset when nothing ran, and
# `set -u` turns that into a stack trace rather than an answer.
if (( PASS_COUNT + FAIL_COUNT + SAMPLE_CASES == 0 )); then
  echo "no case ran. ${#SELECTED[@]} selector(s) given, none matched a case name."
  exit 2
fi

if (( SAMPLES > 0 )); then
  echo "Rates (raw k/N, no early stop):"
  for l in "${HIT_LINES[@]}"; do echo "  $l"; done
  echo
  echo "Sample mode: SAMPLES=$SAMPLES, $SAMPLE_CASES case(s), $SAMPLE_CALLS invocation(s), total_cost_usd=$SAMPLE_COST"
  echo "  model=$MODEL  max-turns-default=$MAX_TURNS  instrument=$SAMPLE_HEAD  installed-descs=$SAMPLE_DESCS"
  echo "  fence=$DISALLOWED_TOOLS"
  echo "  k/N is a measurement, not a gate: a low rate does not fail this run. A fence breach does."
  echo "  Read named-not-called beside every k/N -- a 0/N with a high named-not-called is the"
  echo "  denied-affordance wall (tests/evals/collision/RESULTS.md), not a dead description."
  if (( FAIL_COUNT > 0 )); then exit 1; fi
  exit 0
fi

echo "Hit rates (which attempt each case landed on):"
for l in "${HIT_LINES[@]}"; do echo "  $l"; done
echo
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
