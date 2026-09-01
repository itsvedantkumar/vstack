#!/usr/bin/env python3
"""transcript-census.py -- extraction engine for tests/transcript-census.sh.

WHY THIS FILE EXISTS. CHANGELOG 1.57.0 publishes six figures about this machine's transcript
corpus -- 2536 transcripts, 20508 assistant tool-using messages, 516 Skill invocations, 2.52 per
100, 1008 dispatches, 0.0 fan-out per record against 53.0% per run -- and until now nothing in
the repository could recompute any of them. They existed as prose. A number with no instrument is
a number nobody can disagree with, which is the same defect this repository is named for wearing
different clothes: the reader cannot tell a measurement from a recollection.

This is a census, not an experiment. It reports what is in the corpus on the machine it runs on.
It makes no claim that the corpus is representative of anything, and it cannot be run on CI at
all -- there are no transcripts there. That is why the arithmetic is separately provable against
fixtures with hand-computed answers (tests/transcript-census.sh --self-test, gated by check 63):
an instrument whose only proof is the corpus it measured is unfalsifiable by construction.

THE TWO FAN-OUT DENOMINATORS, STATED BEFORE THEY ARE COMPUTED. Claude Code streams each tool_use
block as its own JSONL record. So "how many assistant records hold two or more dispatches" is
structurally zero on every corpus that will ever exist, and a measurement built on it returns
0.0 fan-out forever while looking like it measured something. The unit that survives is a
maximal run of CONSECUTIVE assistant records sharing a non-null `.message.id`, which is what
claude/hooks/skill-mandate.sh's `fanout_batches` already counts and what
tests/test-breadth-mandate.sh already proves. CONSECUTIVE matters: ids reappear thousands of
lines later after compaction, so grouping globally by id merges two unrelated turns into one
inflated batch.

Both are reported, side by side, always. The per-record figure is kept precisely because it is
the wrong one -- printing 0.0 next to the per-run figure is the only way a reader can see that
the difference is the measurement and not the behaviour.

Two per-run denominators are reported for the same reason, because "53.0% fan-out" does not say
which was meant and this file will not silently pick one:
  batched_runs / runs_with_any_dispatch    -- what share of dispatching turns were batches
  dispatches_in_batches / dispatches        -- what share of dispatches went out in a batch

EXCLUSIONS, each with its reason:
  */subagents/*.jsonl  a subagent leaf transcript is not a session. Its dispatches were already
                       counted in the parent's transcript at the Task/Agent call that spawned it,
                       so folding the leaf in double-counts one delegation. Same decision, same
                       reason, as tests/delegation-drift.py's find(1) call site.
  unparseable lines    counted and reported, never silently dropped.
"""

import json
import os
import sys

DISPATCH_NAMES = ("Task", "Agent")


def iter_records(path):
    """Yields parsed JSON objects from one transcript; returns the count of unparseable lines."""
    bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                yield json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                bad += 1
    if bad:
        BAD_LINES[0] += bad


BAD_LINES = [0]


def census_file(path, acc):
    """Folds one transcript into acc. Returns True if the file held any assistant activity."""
    saw_assistant = False
    # A run is a maximal span of CONSECUTIVE assistant records sharing a non-null message.id.
    run_id = None
    run_dispatches = 0

    def close_run():
        if run_dispatches >= 1:
            acc["runs_with_dispatch"] += 1
            if run_dispatches >= 2:
                acc["batched_runs"] += 1
                acc["dispatches_in_batches"] += run_dispatches

    for d in iter_records(path):
        if not isinstance(d, dict) or d.get("type") != "assistant":
            # Any non-assistant record breaks the run. A user turn between two same-id assistant
            # records means they are not one batch, whatever the id says.
            if run_id is not None:
                close_run()
                run_id, run_dispatches = None, 0
            continue
        saw_assistant = True
        msg = d.get("message") or {}
        content = msg.get("content")
        mid = msg.get("id")
        n_tools = 0
        n_dispatch = 0
        if isinstance(content, list):
            for c in content:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                n_tools += 1
                name = c.get("name")
                if name == "Skill":
                    acc["skill_calls"] += 1
                    sk = (c.get("input") or {}).get("skill")
                    if isinstance(sk, str) and sk:
                        acc["per_skill"][sk] = acc["per_skill"].get(sk, 0) + 1
                elif name in DISPATCH_NAMES:
                    n_dispatch += 1
        if n_tools:
            acc["tool_using_messages"] += 1
        if n_dispatch:
            acc["dispatches"] += n_dispatch
            acc["records_with_dispatch"] += 1
            if n_dispatch >= 2:
                acc["records_with_2plus"] += 1

        if mid is not None and mid == run_id:
            run_dispatches += n_dispatch
        else:
            if run_id is not None:
                close_run()
            run_id = mid
            run_dispatches = n_dispatch
            if mid is None:
                # No id: this record cannot be grouped with anything. Close it immediately as a
                # run of one so it is not silently merged into the next record's run.
                close_run()
                run_id, run_dispatches = None, 0
    if run_id is not None:
        close_run()
    return saw_assistant


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        if os.path.basename(dirpath) == "subagents":
            dirnames[:] = []
            continue
        for fn in sorted(filenames):
            if fn.endswith(".jsonl"):
                yield os.path.join(dirpath, fn)


def pct(k, n):
    return 0.0 if n == 0 else 100.0 * k / n


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude/projects")
    if not os.path.isdir(root):
        print("INCONCLUSIVE: %s is not a directory, so there is no corpus to count." % root)
        return 3

    acc = {
        "tool_using_messages": 0,
        "skill_calls": 0,
        "per_skill": {},
        "dispatches": 0,
        "records_with_dispatch": 0,
        "records_with_2plus": 0,
        "runs_with_dispatch": 0,
        "batched_runs": 0,
        "dispatches_in_batches": 0,
    }
    files = 0
    empty = 0
    for path in walk(root):
        try:
            if census_file(path, acc):
                files += 1
            else:
                empty += 1
        except OSError as e:
            print("SKIP %s: %s" % (path, e), file=sys.stderr)

    if files == 0:
        print("INCONCLUSIVE: 0 transcripts with assistant activity under %s." % root)
        print("A census over an empty corpus is not a rate. Nothing is reported.")
        return 3

    out = {
        "corpus_root": root,
        "transcripts": files,
        "transcripts_without_assistant_activity": empty,
        "unparseable_lines": BAD_LINES[0],
        "tool_using_messages": acc["tool_using_messages"],
        "skill_invocations": acc["skill_calls"],
        "skill_per_100_tool_using_messages": round(pct(acc["skill_calls"], acc["tool_using_messages"]), 2),
        "dispatches": acc["dispatches"],
        "records_with_dispatch": acc["records_with_dispatch"],
        "records_with_2plus_dispatches": acc["records_with_2plus"],
        "fanout_per_record_pct": round(pct(acc["records_with_2plus"], acc["records_with_dispatch"]), 1),
        "runs_with_dispatch": acc["runs_with_dispatch"],
        "batched_runs": acc["batched_runs"],
        "fanout_per_run_pct": round(pct(acc["batched_runs"], acc["runs_with_dispatch"]), 1),
        "dispatches_in_batches": acc["dispatches_in_batches"],
        "fanout_by_dispatch_pct": round(pct(acc["dispatches_in_batches"], acc["dispatches"]), 1),
        "per_skill": acc["per_skill"],
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
