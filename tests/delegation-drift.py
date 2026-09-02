#!/usr/bin/env python3
"""delegation-drift.py -- extraction + pooling engine for tests/delegation-drift.sh.

Does the rate at which breadth-eligible work actually gets delegated fall off across a
session's own lifetime? "Breadth-eligible" is not this script's own idea of what warranted
delegation -- it is lifted verbatim from claude/hooks/skill-mandate.sh's breadth mandate:
dir_count>=3 and ext_count>=2 is the exact condition that mandate uses to decide whether to
block Stop for "multi-directory work ... zero subagents". Reusing it here means this script
cannot be accused of reverse-engineering a threshold from the answer it wanted -- the Stop hook
and tests/test-breadth-mandate.sh already both treat it as authoritative, before this file
existed.

CAUSAL LIMIT, stated here because BETH named it directly and it must not get lost between the
two files: this is correlational, not an experiment, and the specific reverse-causality risk is
that late-session work may be inherently less delegable -- a final review, a one-line wrap-up --
so the TASK SHAPE changes with session position, not only the model's willingness to delegate.
Pooling only over breadth-eligible windows (dir_count>=3, ext_count>=2 already true) holds
instantaneous task shape roughly constant at the moment each window is measured; it does not
control for fatigue or for cumulative compaction exposure across the session. A rate difference
here is evidence of association between session position and delegation, not evidence that
position CAUSES the difference. Read every number below as "associated with", never as "caused
by" -- same discipline tests/compaction-effect.py applies to its own numbers, for the same
reason.

TWO SOURCES, ONE SCHEMA:
  forward log   -- claude/hooks/skill-mandate.sh already logs one line per evaluated Stop to
                   $VSTACK_DELEGATION_LOG (default ~/.claude/vstack-delegation-log.jsonl):
                   {session_id, checkpoint_index, dir_count, ext_count, task_count, named, ts}.
                   This is real-time, so on the day this logger ships it is close to empty --
                   that is the expected state, not a bug (see tests/README.md's compaction-effect.sh
                   note: 8 qualifying sessions out of 3,134 for the identical reason, a feature
                   that started logging after almost all of the corpus already existed).
  replay        -- ~/.claude/projects/*/*.jsonl transcripts, replayed by recomputing the SAME
                   four fields (dir_count, ext_count, task_count, named) from raw tool_use blocks,
                   at each point a real Stop would have fired (immediately before the next
                   human-authored user turn, or at end of transcript). Restricted to transcripts
                   whose own file mtime postdates CUTOFF_COMMIT_ISO (a2d7f46, the commit that
                   fixed skill-mandate.sh's task_count to recognize the "Agent" tool name
                   alongside "Task"): a session that ran under the OLDER, blind hook was
                   receiving false "zero subagents" blocks even after real Agent dispatches,
                   which is a different treatment condition, not the one this measures. Replaying
                   it with today's fixed counting logic does not fix that -- the MODEL was still
                   responding to the broken gate's prompts in real time.

REPLAY IS A CONSERVATIVE UNDER-COUNT, DISCLOSED RATHER THAN CHASED: the live hook also folds
Bash-mediated writes (sed -i, redirects, cp/mv, tee, Python open()-in-heredoc) into dir_count and
ext_count, through roughly 130 lines of awk with its own heredoc-suppression state machine
(claude/hooks/skill-mandate.sh, "bash_write_extract"). Re-deriving that exactly in Python here
was judged not worth the duplicate-maintenance liability for a correlational drift analysis: this
replay counts only Write/Edit/NotebookEdit tool_use blocks. Every breadth-eligible window this
script finds by replay is therefore a real one (dir_count/ext_count are undercounts, never
overcounts, of what the live hook would have computed), but some windows the live hook WOULD have
flagged are invisible here. This narrows the replay sample; it does not fabricate one.

PRE-REGISTRATION (written before this file was run against real data; see
tests/delegation-drift.sh's own header for the order of operations and the invalidation rules):
  Primary metric: breadth-eligible-window delegation rate (hit = task_count>=1 at a checkpoint
  where dir_count>=3 and ext_count>=2 -- task_count>=1 is skill-mandate.sh's own definition of
  "already delegated", it is what suppresses the breadth block), pooled across all checkpoints in
  the first position-tertile of a session versus the last, position = (checkpoint ordinal - 1) /
  (session's final checkpoint ordinal - 1). ["Checkpoint ordinal", not raw tool-call index: the
  forward log's schema is frozen to checkpoint_index (one row per evaluated Stop) and carries no
  raw tool-call counter, and dir_count/ext_count/task_count are themselves only ever recomputed
  once per Stop in the live hook -- checkpoint ordinal is the finest granularity common to both
  sources and the granularity the mandate itself operates at. This is the one place this script
  had to choose an operationalization BETH's spec left implicit; flagged here rather than silently.]

  AMENDMENT (SUMMER, 2026-08-31, claude/hooks/skill-mandate.sh v1.57.0+): the clause just above --
  "task_count>=1 is skill-mandate.sh's own definition of 'already delegated', it is what
  suppresses the breadth block" -- was true when this was pre-registered and is FALSE as of the
  hook's current source. It is left in place rather than edited or deleted: it correctly described
  the hook up to v1.57.0 and this repository does not rewrite its own record. What actually
  suppresses the live breadth block today (skill-mandate.sh:710) is `fanout_batches != 0` -- 2+
  Task/Agent tool_use blocks landing in the SAME assistant message, the only shape Claude Code
  actually runs concurrently -- not `task_count>=1`, which also reads true for N delegations spread
  across N separate serial turns and is no longer sufficient to avoid the block. The PRIMARY metric
  below is UNCHANGED: it still reports task_count>=1, renamed in code from delegated() to
  any_dispatch() to say what it actually measures, so every number this file has ever published and
  every number it publishes after this amendment remain the same series and stay directly
  comparable. A new, separate, NOT-pre-registered metric was added alongside it (see
  delegated_fanout() / the "breadth-eligible-window suppression rate" section below) that reads
  fanout_batches directly and reports the real suppression condition -- computed only over rows
  that actually carry that field (forward-log rows written by a hook new enough to log it; see
  fanout_present()), with that population's own N printed next to it rather than folded into the
  primary's denominator. Historical forward-log rows written before this field existed are excluded
  from that metric's denominator, not scored as failures -- see fanout_present()'s docstring. It
  carries no SIGNAL/KEEPS-WORKING verdict of its own: no threshold for it was fixed before any data
  existed under it, and fixing one now, after the rate is already visible, is exactly the
  threshold-picked-after-seeing-the-number move this file refuses to let its own primary and
  secondary metrics make.
  SIGNAL (decay) iff last-third rate <= SIGNAL_DECAY_RATIO(0.7)x first-third rate, AND
    >= MIN_ELIGIBLE_PER_TERTILE(8) eligible windows in EACH tertile, AND
    >= MIN_CONTRIBUTING_SESSIONS(5) distinct sessions contributing >=1 eligible window to either
    tertile. Below any floor: NOT EVALUATED, not a rate.
  "Keeps working" iff last-third rate falls in [KEEPS_WORKING_LOW(0.85)x, KEEPS_WORKING_HIGH(1.15)x]
    of first-third rate, same floors.
  Gray zone: ratio in (0.7x, 0.85x) -- reported as-is, no verdict claimed.
  Opposite of predicted direction: ratio > 1.15x -- reported as-is, no verdict claimed (BETH's
    predicted direction was decay; a rise is not evidence of decay and this script does not
    invent a name implying it is a finding of the opposite kind).
  Secondary, reported alongside and never in place of the primary: call-sign attribution rate
    (named==true) among checkpoints with task_count>=1, same tertile split, no verdict gated on it.
  All thresholds overridable by environment variable of the same name, for reruns at a different
  floor; doing so invalidates comparison against a run at the defaults, same rule
  tests/README.md states for tests/compaction-effect.sh.

INVALIDATES THE RUN (checked where mechanically checkable, documented where it is not):
  - Identical per-session outcome vectors across >=2 sessions (every checkpoint reporting the
    exact same (dir_count, ext_count, task_count, named) tuple) is auto-detected below and
    reported as INVALID -- extraction broken, not genuine invariance -- overriding any verdict.
  - Mixed-version pool (a change to skill-mandate.sh's dir/ext counting logic straddling the
    pooled data without a control re-run) is NOT mechanically detectable from this schema alone
    (it carries no hook-version field) and is not auto-detected here. Same discipline
    tests/README.md's "A harness change invalidates its own prior findings until the control
    re-runs" already states in prose for compaction-effect.sh: after any change to
    skill-mandate.sh's breadth/agent-naming counting logic, treat prior pooled numbers as
    provisional until a control re-run confirms the harness itself did not move.
  - Any floor unmet is exactly the NOT EVALUATED path above, not a separate check.

Streaming: both the forward log and every replayed transcript are read one line at a time; only
small extracted fields survive past the line that produced them. Some transcripts on this machine
approach 1M tokens and must not be slurped -- same discipline tests/compaction-effect.py applies.
"""

import json
import math
import os
import re
import sys

SIGNAL_DECAY_RATIO = float(os.environ.get("SIGNAL_DECAY_RATIO", "0.7"))
KEEPS_WORKING_LOW = float(os.environ.get("KEEPS_WORKING_LOW", "0.85"))
KEEPS_WORKING_HIGH = float(os.environ.get("KEEPS_WORKING_HIGH", "1.15"))
MIN_ELIGIBLE_PER_TERTILE = int(os.environ.get("MIN_ELIGIBLE_PER_TERTILE", "8"))
MIN_CONTRIBUTING_SESSIONS = int(os.environ.get("MIN_CONTRIBUTING_SESSIONS", "5"))
CUTOFF_COMMIT_ISO = os.environ.get("CUTOFF_COMMIT_ISO", "2026-08-23T12:54:16+05:30")

# Same roster skill-mandate.sh's agent-naming mandate matches, kept in sync by hand -- a second
# duplicate-maintenance point, disclosed the same way the Bash-write-extraction gap is above.
ROSTER_RE = re.compile(
    r"\b(RICK|MEESEEKS|MORTY|SUMMER|ZEEP|GLOOTIE|JAGUAR|BETH|BIRDPERSON|EVIL-MORTY|NOOBNOOB"
    r"|PICKLE-RICK|SCARY-TERRY|POOPYBUTTHOLE|UNITY)\b",
    re.IGNORECASE,
)


def wilson_interval(k, n, z=1.96):
    """95% Wilson score interval. n==0 returns the maximally uninformative (0.0, 1.0)."""
    if n == 0:
        return (0.0, 1.0)
    phat = k / n
    denom = 1 + z * z / n
    center = (phat + z * z / (2 * n)) / denom
    half = (z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n))) / denom
    return (max(0.0, center - half), min(1.0, center + half))


def parent_dir(p):
    if "/" in p:
        return p.rsplit("/", 1)[0]
    return "."


def extension(p):
    base = p.rsplit("/", 1)[-1]
    if base.startswith(".") and base.count(".") == 1:
        return None
    if "." not in base:
        return None
    ext = base.rsplit(".", 1)[-1]
    return ext or None


# --- forward log (Part 1) -----------------------------------------------------------------------


def read_forward_log(path):
    """Returns (sessions, declared, ran, skipped). sessions: session_id -> {checkpoint_index: row}.
    Malformed lines and lines missing a required field are skipped, not fatal -- the log's own
    write path already swallows its failures (claude/hooks/skill-mandate.sh), so a reader that
    refuses a partial write would be re-adding the fragility the write path was built to avoid."""
    sessions = {}
    declared = 0
    ran = 0
    skipped = 0
    if not path or not os.path.isfile(path):
        return sessions, declared, ran, skipped
    required = (
        "session_id",
        "checkpoint_index",
        "dir_count",
        "ext_count",
        "task_count",
        "named",
    )
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            declared += 1
            try:
                row = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                skipped += 1
                continue
            if not isinstance(row, dict) or any(k not in row for k in required):
                skipped += 1
                continue
            sid = row["session_id"]
            sessions.setdefault(sid, {})[row["checkpoint_index"]] = row
            ran += 1
    return sessions, declared, ran, skipped


# --- replay (raw transcripts) -------------------------------------------------------------------


def is_real_user_turn(content):
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") == "tool_result":
                return False
        return True
    return False


def replay_session(path):
    """Streams one transcript and returns a list of checkpoint dicts (one per Stop-equivalent
    turn boundary, in order), or None if the transcript has no assistant activity at all."""
    dirs_seen = set()
    exts_seen = set()
    task_count = 0
    named_ever = False
    checkpoints = []
    turn_had_content = False

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                d = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                continue
            t = d.get("type")
            if t == "assistant":
                content = d.get("message", {}).get("content")
                if isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        if c.get("type") == "tool_use":
                            name = c.get("name")
                            if name in ("Write", "Edit", "NotebookEdit"):
                                fp = (c.get("input") or {}).get("file_path")
                                if isinstance(fp, str) and fp:
                                    dirs_seen.add(parent_dir(fp))
                                    ext = extension(fp)
                                    if ext:
                                        exts_seen.add(ext)
                                    turn_had_content = True
                            elif name in ("Task", "Agent"):
                                task_count += 1
                                turn_had_content = True
                        elif c.get("type") == "text":
                            txt = c.get("text")
                            if isinstance(txt, str) and ROSTER_RE.search(txt):
                                named_ever = True
            elif t == "user":
                content = d.get("message", {}).get("content")
                if is_real_user_turn(content) and turn_had_content:
                    checkpoints.append(
                        {
                            "dir_count": len(dirs_seen),
                            "ext_count": len(exts_seen),
                            "task_count": task_count,
                            "named": named_ever,
                        }
                    )
                    turn_had_content = False
            del d

    if turn_had_content:
        checkpoints.append(
            {
                "dir_count": len(dirs_seen),
                "ext_count": len(exts_seen),
                "task_count": task_count,
                "named": named_ever,
            }
        )
    return checkpoints or None


def collect_replay(candidates_path, cutoff_epoch):
    """Returns (sessions, declared, ran, skipped_old, skipped_empty, skipped_err).
    sessions: session_id (basename, extension stripped) -> {checkpoint_index: row}."""
    sessions = {}
    declared = 0
    ran = 0
    skipped_old = 0
    skipped_empty = 0
    skipped_err = 0
    if not candidates_path or not os.path.isfile(candidates_path):
        return sessions, declared, ran, skipped_old, skipped_empty, skipped_err
    with open(candidates_path) as fh:
        paths = [line.strip() for line in fh if line.strip()]
    for p in paths:
        declared += 1
        try:
            mtime = os.path.getmtime(p)
        except OSError:
            skipped_err += 1
            continue
        if mtime <= cutoff_epoch:
            skipped_old += 1
            continue
        try:
            cps = replay_session(p)
        except OSError:
            skipped_err += 1
            continue
        if not cps:
            skipped_empty += 1
            continue
        sid = os.path.basename(p)
        if sid.endswith(".jsonl"):
            sid = sid[: -len(".jsonl")]
        sessions[sid] = {i + 1: cp for i, cp in enumerate(cps)}
        ran += 1
    return sessions, declared, ran, skipped_old, skipped_empty, skipped_err


# --- pooling --------------------------------------------------------------------------------


def merge_sources(forward_sessions, replay_sessions):
    """Forward-log entries win on session_id collision -- they are the real-time capture: an
    entry actually written by the live hook, not reconstructed after the fact. Returns
    (merged, forward_used, replay_used)."""
    merged = dict(forward_sessions)
    forward_used = set(forward_sessions.keys())
    replay_used = set()
    for sid, rows in replay_sessions.items():
        if sid in merged:
            continue
        merged[sid] = rows
        replay_used.add(sid)
    return merged, forward_used, replay_used


def positioned_checkpoints(merged):
    """Yields (session_id, position in [0,1] or None, row) for every checkpoint across every
    session. position is None for a session with only one checkpoint -- it cannot be placed at
    both extremes of its own tertile split, so it contributes to accounting but not to pooling."""
    out = []
    for sid, rows in merged.items():
        indices = sorted(rows.keys())
        n = len(indices)
        for rank, idx in enumerate(indices):
            pos = (rank / (n - 1)) if n > 1 else None
            out.append((sid, pos, rows[idx]))
    return out


def measured(row):
    """True iff the hook actually computed breadth for this checkpoint.

    A latched row -- MEESEEKS's 2-strike-latch bypass, shipped v1.40.0, split out and made
    independently observable by MORTY's follow-up -- carries a real session_id and a real
    checkpoint_index (the Stop genuinely happened) but explicit JSON null for dir_count,
    ext_count, task_count, and named, because computing them there was measured as too
    expensive to pay unconditionally (1438ms mean / 1536ms p95 on a 17.5MB transcript) and
    MEESEEKS chose not to. A latched Stop is therefore KNOWN-UNMEASURED: it is neither
    zero-breadth (eligible() returning False on a null row would silently claim "measured and
    small") nor not-delegated (any_dispatch() would silently claim "measured and no dispatch").
    Both readings would misrepresent a missing measurement as a negative one, which is exactly
    the shape of the corpus-filter-that-looks-like-a-decision bug this repo keeps re-finding.
    Every caller that pools eligible()/any_dispatch() results MUST check measured() first and
    exclude -- not zero-fill -- an unmeasured row; see pool_tertiles() and
    detect_broken_extraction() for the two call sites that do."""
    return row.get("dir_count") is not None


def eligible(row):
    # Defensive null-guard only -- the real exclusion decision for a latched (unmeasured) row
    # is made by callers checking measured() BEFORE calling this, so its result is counted
    # separately rather than folded into "not eligible". This still returns a safe False rather
    # than raising if a future caller forgets that check, matching this file's own crash
    # discipline: an analyser must degrade, never traceback, on a schema it already knows about.
    dir_count = row.get("dir_count")
    ext_count = row.get("ext_count")
    if dir_count is None or ext_count is None:
        return False
    # Tracks skill-mandate.sh's breadth gate, lowered to dir>=2 in 1.66.0. "Eligible" here must
    # mean "the gate would have considered this turn", so the two move together; there is no live
    # drift result yet (the suite reports NOT EVALUATED until its floors are met) so nothing was
    # invalidated by the change.
    return dir_count >= 2 and ext_count >= 2


def any_dispatch(row):
    """PRIMARY metric's hit predicate: task_count>=1, i.e. at least one Task/Agent call landed
    anywhere in the checkpoint's window, in any number of turns, together or apart.

    Formerly named delegated() -- renamed, not redefined, so this says what it has always
    computed rather than what it was once believed to mean. See the PRE-REGISTRATION/AMENDMENT
    block in this file's module docstring: this WAS skill-mandate.sh's own suppression condition
    for the breadth block up to v1.57.0 and is NOT any longer. Kept exactly as it was (same
    null-guard, same threshold) so every number this file publishes stays one comparable series;
    see delegated_fanout() below for the metric keyed to the CURRENT suppression condition."""
    # Same defensive null-guard as eligible() -- see its comment.
    task_count = row.get("task_count")
    if task_count is None:
        return False
    return task_count >= 1


def fanout_present(row):
    """True iff this row actually carries a measured fanout_batches value -- i.e. it was written
    by a forward-log hook new enough to compute it (claude/hooks/skill-mandate.sh v1.57.0+) AND
    that Stop was not latched (see measured()). False covers two different populations that MUST
    NOT be conflated with a real 0: (a) the key is simply absent -- every forward-log row written
    before this field existed, and every replay-derived row, since replay never recomputes it
    (disclosed the same way this file's replay already under-counts dir_count/ext_count -- see the
    module docstring's REPLAY IS A CONSERVATIVE UNDER-COUNT section); (b) the key is present but
    JSON null -- a latched row (skill-mandate.sh writes fanout_batches:null there same as its other
    counts). Scoring either case as fanout_batches==0 would silently read "not measured" as "the
    hook's suppression condition was unmet", manufacturing a fake collapse in delegated_fanout()'s
    rate at exactly the schema boundary where the field started being written. Callers MUST check
    this before calling delegated_fanout() and exclude -- never zero-fill -- a row that fails it."""
    return row.get("fanout_batches") is not None


def delegated_fanout(row):
    """NOT pre-registered (added 2026-08-31, see the AMENDMENT block in the module docstring).
    Hit predicate keyed to the REAL, CURRENT suppression condition the live hook checks at
    skill-mandate.sh:710 (`[ "$fanout_batches" -eq 0 ]`, negated): 2+ Task/Agent calls landed in
    the SAME assistant message at least once in this checkpoint's window. Callers MUST check
    fanout_present(row) first -- this returns a bare False on an absent/null field, same defensive
    shape as eligible()/any_dispatch(), but that False must never be pooled as a real miss; see
    fanout_present()'s docstring for why."""
    fanout_batches = row.get("fanout_batches")
    if fanout_batches is None:
        return False
    return fanout_batches != 0


def pool_tertiles(all_checkpoints):
    """Returns dict with first/last tertile eligible-window counts, hits, and contributing
    sessions, for the primary metric, the secondary attribution metric, and the (not
    pre-registered) fanout-suppression metric -- the last one pooled only over eligible windows
    that also pass fanout_present(), with the windows that didn't counted separately so that
    exclusion is visible rather than silently shrinking the denominator."""
    first_n = last_n = first_hits = last_hits = 0
    first_named_n = last_named_n = first_named_hits = last_named_hits = 0
    first_fanout_n = last_fanout_n = first_fanout_hits = last_fanout_hits = 0
    fanout_absent_in_tertiles = 0
    contributing = set()
    contributing_named = set()
    contributing_fanout = set()
    latched_in_tertiles = 0
    for sid, pos, row in all_checkpoints:
        if pos is None:
            continue
        is_first = pos <= 1.0 / 3.0
        is_last = pos >= 2.0 / 3.0
        if not (is_first or is_last):
            continue
        if not measured(row):
            # KNOWN-UNMEASURED, not zero-breadth and not "no delegation" -- excluded from both
            # the primary and secondary pools, counted here rather than silently dropped. See
            # measured()'s docstring for why folding it into either pool would be wrong.
            latched_in_tertiles += 1
            continue
        if eligible(row):
            contributing.add(sid)
            if is_first:
                first_n += 1
                first_hits += 1 if any_dispatch(row) else 0
            else:
                last_n += 1
                last_hits += 1 if any_dispatch(row) else 0
            # Fanout-suppression pool: same eligible-window population as the primary, further
            # restricted to rows carrying a real fanout_batches measurement. A row that fails
            # fanout_present() is excluded from this pool's n and hits entirely -- not zero-filled
            # -- and counted in fanout_absent_in_tertiles so the exclusion has a visible count.
            if fanout_present(row):
                contributing_fanout.add(sid)
                if is_first:
                    first_fanout_n += 1
                    first_fanout_hits += 1 if delegated_fanout(row) else 0
                else:
                    last_fanout_n += 1
                    last_fanout_hits += 1 if delegated_fanout(row) else 0
            else:
                fanout_absent_in_tertiles += 1
        if any_dispatch(row):
            contributing_named.add(sid)
            if is_first:
                first_named_n += 1
                first_named_hits += 1 if row.get("named") else 0
            else:
                last_named_n += 1
                last_named_hits += 1 if row.get("named") else 0
    return {
        "first_n": first_n,
        "first_hits": first_hits,
        "last_n": last_n,
        "last_hits": last_hits,
        "contributing_sessions": len(contributing),
        "first_named_n": first_named_n,
        "first_named_hits": first_named_hits,
        "last_named_n": last_named_n,
        "last_named_hits": last_named_hits,
        "contributing_sessions_secondary": len(contributing_named),
        "latched_in_tertiles": latched_in_tertiles,
        "first_fanout_n": first_fanout_n,
        "first_fanout_hits": first_fanout_hits,
        "last_fanout_n": last_fanout_n,
        "last_fanout_hits": last_fanout_hits,
        "contributing_sessions_fanout": len(contributing_fanout),
        "fanout_absent_in_tertiles": fanout_absent_in_tertiles,
    }


def rate_report(label, hits, n):
    if n == 0:
        return f"{label}: n=0 (no qualifying checkpoints)"
    lo, hi = wilson_interval(hits, n)
    return f"{label}: {hits}/{n} = {hits / n:.3f}  (95% CI {lo:.3f}-{hi:.3f})"


def primary_verdict(p):
    if (
        p["first_n"] < MIN_ELIGIBLE_PER_TERTILE
        or p["last_n"] < MIN_ELIGIBLE_PER_TERTILE
    ):
        return (
            f"NOT EVALUATED -- eligible windows first={p['first_n']} last={p['last_n']}, "
            f"need >= {MIN_ELIGIBLE_PER_TERTILE} each"
        )
    if p["contributing_sessions"] < MIN_CONTRIBUTING_SESSIONS:
        return (
            f"NOT EVALUATED -- {p['contributing_sessions']} contributing session(s), "
            f"need >= {MIN_CONTRIBUTING_SESSIONS}"
        )
    first_rate = p["first_hits"] / p["first_n"]
    last_rate = p["last_hits"] / p["last_n"]
    if first_rate == 0:
        return f"NOT EVALUABLE -- first-tertile rate is 0 (last={last_rate:.3f}); ratio undefined"
    ratio = last_rate / first_rate
    if ratio <= SIGNAL_DECAY_RATIO:
        return (
            f"SIGNAL (decay) -- ratio={ratio:.2f}x, threshold <= {SIGNAL_DECAY_RATIO}x"
        )
    if KEEPS_WORKING_LOW <= ratio <= KEEPS_WORKING_HIGH:
        return f"KEEPS WORKING -- ratio={ratio:.2f}x, within [{KEEPS_WORKING_LOW}, {KEEPS_WORKING_HIGH}]x"
    if SIGNAL_DECAY_RATIO < ratio < KEEPS_WORKING_LOW:
        return f"gray zone -- ratio={ratio:.2f}x, reported as-is, no verdict claimed"
    return f"opposite of predicted direction -- ratio={ratio:.2f}x, reported as-is, no verdict claimed"


def detect_broken_extraction(merged):
    """>=2 sessions where EVERY MEASURED checkpoint across the whole pool shares one identical
    (dir_count, ext_count, task_count, named) tuple is not genuine invariance -- it is what a
    silently-broken extractor (e.g. every file_path read as empty) looks like. Sessions with
    zero checkpoints cannot participate either way.

    Latched (known-unmeasured, see measured()) rows are excluded from this check entirely, not
    just from the tuple set -- a pool that happens to be 100% latched right now is not evidence
    of a broken extractor, it is evidence of nothing measured yet, and conflating the two would
    print INVALID over what is really an (uncommon but legitimate) all-latched NOT EVALUATED."""
    tuples = set()
    sessions_with_data = 0
    for sid, rows in merged.items():
        measured_rows = [row for row in rows.values() if measured(row)]
        if not measured_rows:
            continue
        sessions_with_data += 1
        for row in measured_rows:
            tuples.add(
                (
                    row.get("dir_count"),
                    row.get("ext_count"),
                    row.get("task_count"),
                    row.get("named"),
                )
            )
    return sessions_with_data >= 2 and len(tuples) <= 1


def main():
    forward_log_path = sys.argv[1] if len(sys.argv) > 1 else None
    candidates_path = sys.argv[2] if len(sys.argv) > 2 else None

    import datetime

    try:
        cutoff_epoch = datetime.datetime.fromisoformat(CUTOFF_COMMIT_ISO).timestamp()
    except ValueError:
        print(
            f"FATAL: CUTOFF_COMMIT_ISO={CUTOFF_COMMIT_ISO!r} is not a valid ISO timestamp",
            file=sys.stderr,
        )
        return 1

    fwd_sessions, fwd_declared, fwd_ran, fwd_skipped = read_forward_log(
        forward_log_path
    )
    (
        rep_sessions,
        rep_declared,
        rep_ran,
        rep_skipped_old,
        rep_skipped_empty,
        rep_skipped_err,
    ) = collect_replay(candidates_path, cutoff_epoch)

    merged, forward_used, replay_used = merge_sources(fwd_sessions, rep_sessions)

    print("=== delegation-drift: bucketing ===")
    print(f"forward log: {forward_log_path or '(none given)'}")
    print(
        f"  lines declared / parsed OK / skipped (malformed or missing field): {fwd_declared} / {fwd_ran} / {fwd_skipped}"
    )
    print(f"  distinct sessions in forward log: {len(fwd_sessions)}")
    print(f"replay: candidates postdating a2d7f46 ({CUTOFF_COMMIT_ISO})")
    print(
        f"  transcripts declared / replayed OK / skipped (pre-cutoff, empty, error): "
        f"{rep_declared} / {rep_ran} / {rep_skipped_old} + {rep_skipped_empty} + {rep_skipped_err}"
    )
    print(f"  distinct sessions in replay: {len(rep_sessions)}")
    print(
        f"merged pool: {len(merged)} sessions "
        f"({len(forward_used)} from forward log, {len(replay_used)} from replay only, "
        f"forward-log wins on collision)"
    )

    total_ran = fwd_ran + rep_ran
    if len(merged) == 0:
        print()
        print(
            "INCONCLUSIVE: zero sessions from either source. No before/after rate can be"
        )
        print("computed. This is not a passing result and must not be read as one.")
        print(
            f"accounting: {fwd_declared + rep_declared} declared / {total_ran} ran / {fwd_skipped + rep_skipped_old + rep_skipped_empty + rep_skipped_err} skipped"
        )
        return 1

    if detect_broken_extraction(merged):
        print()
        print("INVALID: every checkpoint across >=2 sessions shares one identical")
        print(
            "(dir_count, ext_count, task_count, named) tuple. That is what a broken extractor"
        )
        print("looks like, not genuine invariance. No verdict is reported.")
        print(
            f"accounting: {fwd_declared + rep_declared} declared / {total_ran} ran / {fwd_skipped + rep_skipped_old + rep_skipped_empty + rep_skipped_err} skipped"
        )
        return 1

    all_checkpoints = positioned_checkpoints(merged)
    single_checkpoint_sessions = sum(1 for sid, rows in merged.items() if len(rows) < 2)
    total_checkpoints = len(all_checkpoints)
    latched_checkpoints = sum(
        1 for _sid, _pos, row in all_checkpoints if not measured(row)
    )
    pooled = pool_tertiles(all_checkpoints)

    print()
    print(
        f"sessions excluded from tertile pooling (only 1 checkpoint, no position to place): "
        f"{single_checkpoint_sessions}"
    )
    # Printed unconditionally, including when zero -- a latched (known-unmeasured) checkpoint
    # is neither zero-breadth nor "not delegated" (see measured()'s docstring) and pool_tertiles
    # already excludes it from every pooled rate below. This line is the only place that count
    # is visible; a silent drop here is exactly the corpus-filter-that-looks-like-a-decision
    # shape this repo has shipped before.
    print(
        f"checkpoints latched (known-unmeasured Stop, excluded from every pool below): "
        f"{latched_checkpoints} of {total_checkpoints} total checkpoints "
        f"({pooled['latched_in_tertiles']} of those were inside a first/last-tertile window)"
    )
    print()
    print(
        "=== primary: breadth-eligible-window delegation rate, first vs last tertile ==="
    )
    print("  " + rate_report("first-third", pooled["first_hits"], pooled["first_n"]))
    print("  " + rate_report("last-third ", pooled["last_hits"], pooled["last_n"]))
    print(f"  contributing sessions: {pooled['contributing_sessions']}")
    print("  verdict: " + primary_verdict(pooled))

    print()
    print(
        "=== secondary: call-sign attribution rate among task_count>=1 checkpoints (no verdict) ==="
    )
    sec_contrib = pooled["contributing_sessions_secondary"]
    sec_underpowered = (
        pooled["first_named_n"] < MIN_ELIGIBLE_PER_TERTILE
        or pooled["last_named_n"] < MIN_ELIGIBLE_PER_TERTILE
        or sec_contrib < MIN_CONTRIBUTING_SESSIONS
    )
    # Same floors as the primary metric, applied here purely as a per-line power indicator --
    # this metric is never verdict-gated by design (see header), but an unqualified rate reads
    # as a finding regardless of prose above it, so the caveat travels with the number itself.
    sec_note = (
        f"UNDERPOWERED: {sec_contrib} contributing session(s) (need >= {MIN_CONTRIBUTING_SESSIONS}), "
        f"windows first={pooled['first_named_n']} last={pooled['last_named_n']} (need >= {MIN_ELIGIBLE_PER_TERTILE} each) -- no verdict"
        if sec_underpowered
        else f"{sec_contrib} contributing session(s) -- no verdict"
    )
    print(
        "  "
        + rate_report(
            "first-third", pooled["first_named_hits"], pooled["first_named_n"]
        )
        + f"  [{sec_note}]"
    )
    print(
        "  "
        + rate_report("last-third ", pooled["last_named_hits"], pooled["last_named_n"])
        + f"  [{sec_note}]"
    )

    print()
    print(
        "=== NOT PRE-REGISTERED, added 2026-08-31 (see AMENDMENT in tests/delegation-drift.py's "
        "module docstring): breadth-eligible-window SUPPRESSION rate via the live hook's real "
        "fanout_batches!=0 condition (skill-mandate.sh:710), no verdict ==="
    )
    fan_contrib = pooled["contributing_sessions_fanout"]
    fan_underpowered = (
        pooled["first_fanout_n"] < MIN_ELIGIBLE_PER_TERTILE
        or pooled["last_fanout_n"] < MIN_ELIGIBLE_PER_TERTILE
        or fan_contrib < MIN_CONTRIBUTING_SESSIONS
    )
    # Same floors as the primary metric, same reason as the secondary's sec_note above: an
    # unqualified rate reads as a finding regardless of the caveat printed above it, so the power
    # indicator travels with the number. This metric's denominator is ALSO restricted to rows that
    # pass fanout_present() -- fanout_absent_in_tertiles (never folded into first/last_fanout_n)
    # is the count of eligible tertile windows that were excluded rather than zero-filled because
    # they predate the field or came from replay; see fanout_present()'s docstring for why a
    # missing field must never be scored as fanout_batches==0.
    fan_note = (
        f"UNDERPOWERED: {fan_contrib} contributing session(s) (need >= {MIN_CONTRIBUTING_SESSIONS}), "
        f"windows first={pooled['first_fanout_n']} last={pooled['last_fanout_n']} (need >= {MIN_ELIGIBLE_PER_TERTILE} each) -- no verdict"
        if fan_underpowered
        else f"{fan_contrib} contributing session(s) -- no verdict"
    )
    print(
        "  "
        + rate_report(
            "first-third", pooled["first_fanout_hits"], pooled["first_fanout_n"]
        )
        + f"  [{fan_note}]"
    )
    print(
        "  "
        + rate_report(
            "last-third ", pooled["last_fanout_hits"], pooled["last_fanout_n"]
        )
        + f"  [{fan_note}]"
    )
    print(
        f"  eligible tertile windows excluded (no fanout_batches on the row -- pre-field forward "
        f"log or replay, never scored as 0): {pooled['fanout_absent_in_tertiles']}"
    )

    print()
    print(
        f"accounting: {fwd_declared + rep_declared} declared / {total_ran} ran / "
        f"{fwd_skipped + rep_skipped_old + rep_skipped_empty + rep_skipped_err} skipped"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
