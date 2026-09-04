# Plan: retire the delegation breadth mandate

Planner: ZEEP D-4 (Fable 5.1), 2026-09-03, from the measured runs in
`tests/evals/showcase/RESULTS.md` and the verified literature in `../literature/`.
Status: accepted by RICK; execution tracked in the CHANGELOG entry that ships it.

## Current mechanism

1. `claude/hooks/skill-mandate.sh:725` counts distinct parent directories of written paths
   (`dir_count`) and `:735` distinct extensions (`ext_count`); reads never enter the set.
2. `:747` trips when `dir_count >= 2` and `ext_count >= 2` and no fan-out batch happened (lowered
   from three directories in 1.66.0).
3. On trip, `:770` appends "multi-directory work -- dispatch N agents in ONE message via Skill
   swarm" and the Stop returns a block.
4. `:197` a 1800 s window; two strikes silence it (`:210`, `:219`); counters at `:1043-1047`.
5. Pinned by `tests/test-breadth-mandate.sh` (block PROOFs 2, 5, 11, 16, 27; silent 1, 3, 4, 6,
   10, 15, 28), `tests/mandate-cases.sh` cases i, p, 9b, falsifiability row 27b, and check 40's
   requirement that the log row carries numeric counts.

## Evidence

The mandate fired on 2 of 5 headless runs of a three-file fix; those runs cost 3.6 to 4.4 times
the 3 silent runs and up to six times the wall time, for no correctness gain. Literature: delegate
reads, serialize writes (multi-agent-overhead, verified); no router beats always-strongest on
accuracy (model-routing, verified).

## Rule

Delete the mandate; keep the counts as log fields. A Stop hook sees the write-set after the
fact, so a coupling pre-flight can only ever say "do not fan out", and blocking a finished turn
to demand a redo is the defect being retired. A read-only-splittable detector has an unmeasured
false-block rate. The swarm skill already states the rule (reads fan out, one writer). The
naming, swarm-first and serial-tail mandates stay: each fires only after a dispatch happened.

Ranked alternative, deferred: log `read_breadth` (reads across two or more directories, zero
writes, zero dispatch) as a row field without blocking, decide from about fifty sessions.

## Commits

1. Hook and its pins. Remove `:747-772`, `hit_breadth`, `eval_breadth`, `cnt_breadth`
   (`:210`, `:219`, `:250`, `:285`, `:1043-1047`, `:1094-1095`); keep `:725` and `:735`.
   Flip the block PROOFs to silent, cases i, p, 9b to SILENT, delete falsifiability row 27b.
   Accept: `tests/test-breadth-mandate.sh`, verify check 27, `tests/gate-falsifiability.sh`.
2. Prose. `inject-session-context.sh:183` FANOUT line becomes "reads that split -> Skill swarm;
   writes stay serial on the lead"; drop `delegate-breadth` from the loop at `:171`;
   `tests/test-session-context-mandate.sh:80,157` seed `delegate-naming`. `claude/CLAUDE.md`
   FAN OUT paragraph: replace "widest batch, fewer than three is a decision" with the
   reads-fan-out, writes-serial rule; keep ISOLATE THE WRITERS. Accept: check 18, the CLAUDE.md
   size cap, `test-session-context-mandate.sh`.
3. Docs and version. CHANGELOG entry citing RESULTS.md; `tests/README.md:136-153`;
   `tests/delegation-drift.py:399` relabels the mirrored threshold as historical;
   `traps/multi_module/meta.json` "formerly triggered"; `measured-so-far.md`; mark
   `recommendations-draft.md` item 1 applied. Bump both manifests.
4. Tag locally, run falsifiability, push the same tag with `--no-follow-tags`, read
   `gh run list --workflow=release.yml`.

## Measurement

```bash
SHOWCASE_JOBS=2 tests/evals/showcase/run.sh vstack,gstack 10 traps multi_module
```

Pass: vstack `spawned == 0` on 10 of 10, 20 of 20 green, mean vstack cost within 1.25x of gstack.
If vstack still spawns after commit 1, the driver is prose (commit 2), not the hook. If parity
still fails, revert commits 1 and 2.

Result (2026-09-03, `tests/evals/showcase/runs/20260903-022953.55428.jsonl`, tree `773f3d4`):
vstack spawned on 0 of 10, 20 of 20 green. Acceptance met on the first paired run; commits 1 and 2
stand. The table is in `tests/evals/showcase/RESULTS.md` under "After retiring the breadth
mandate".

## Risks

- `dispatch-counter.sh` and the statusline read the dispatch counter, not the breadth counters.
- `inject-session-context.sh:172` tolerates missing counter files; its test would test nothing
  unless reseeded (commit 2).
- `delegation-drift.py` keeps computing "breadth-eligible delegation rate" over a retired rule:
  relabel, do not delete. The historical 44 percent and "21 blocks / 628 turns" stay as history.
- This reverses the 1.66.0 reach-widening on measured cost. The serial-tail mandate stays.
