# Handoff: does a Claude Code harness beat unconfigured Claude Code, and where?

A research brief. Everything below is measured on this machine unless marked otherwise. Read
`tests/evals/RESULTS.md` before running anything; it records twelve defects found in this
project's own benchmark harness, seven of which flattered vstack.

## The question

vstack and gstack both assume a harness improves on unconfigured Claude Code. Three benchmarks
here have failed to show it. Either the benefit is real and unmeasured, or it is smaller than
assumed, or it is concentrated in task shapes nobody has benchmarked. Decide which.

Do not start from the assumption that harnesses help. The single strongest pattern in this
project's history is that the checks are wrong more often than the things they check.

## What is already measured

**SWE-bench Lite, 4 arms, 4 instances.** All four arms resolved all four. Adding a
`PASS_TO_PASS` regression check later showed those "resolutions" included patches that broke
neighbouring tests, so the 100% was an artifact. A difficulty filter then kept 2 of 12 instances:
unconfigured Claude Code already solves 10 of 12 outright.

**Review pathway, 3 arms, 8 fixtures, 2 samples, 48 reviews.** Every arm passed a dispatch canary
first.

| arm | recall | precision | false positives |
|---|---|---|---|
| none | 11/14 (79%) | 92% | 1 |
| gstack | 11/14 (79%) | 85% | 2 |
| vstack | 11/14 (79%) | 73% | 4 |

Per-fixture hit vectors differ between arms, so the tie is arithmetic coincidence rather than a
collapsed harness. No harness improved recall; vstack lowered precision.

**False completion.** How often an agent asserts a task is done while the suite is red. Twelve
runs unconfigured: 0 false completions, 12 of 12 solved. Nine runs on vstack before the run was
interrupted: 0 false completions, 9 of 9 solved. The fixture has twelve specified behaviours
across two files, eight failing at the start, and no virtualenv, so running the tests costs
effort. The baseline set up the environment and solved it anyway, every time.

**The pattern.** On small, well-specified, single-file tasks with a frontier model, the baseline
is at or near ceiling. A ceiling leaves no headroom to measure, and three benchmarks in a row have
reported that as "no difference" when the honest statement is "this could not tell."

## Hypotheses, and what would settle each

**H1. The benefit is real but appears only past a complexity threshold.**
The tasks measured are single-file, single-defect, with correctness pre-specified. Test on
multi-file changes, tasks spanning more than one session, and repositories large enough that
context management matters. Settled by: a task size where baseline resolve rate falls below about
70%, then comparing arms there. If no arm separates even where baseline fails, H1 is dead.

**H2. The benefit is in variance, not the mean.**
A harness may not raise the average outcome but may cut the tail: the catastrophic edit, the
confidently wrong claim, the destroyed working tree. Means hide this entirely. Settled by:
reporting p95 and worst case rather than medians, over enough runs to see a tail, and counting
catastrophic outcomes separately from failed ones.

**H3. The benefit is in the things that are not model output at all.**
Guards, uninstall, drift detection, an unverified change being blocked. These are capability facts
that need no benchmark, and vstack has them where gstack does not. Settled already, by inspection.
The open question is whether they matter to outcomes anyone measures, or only to trust.

**H4. Harnesses helped more on weaker models and the advantage has eroded.**
Plausible and cheap to test: run the same benchmarks on a smaller model. If harness arms separate
from baseline on the smaller model and not on the larger one, the honest claim becomes "a harness
substitutes for model capability", which is a real finding and a diminishing one.

**H5. The benefit is real and negative in places.**
vstack lowered review precision, 4 false positives against 1. Thoroughness instructions may
produce over-reporting. Settled by: checking whether the extra findings are wrong or merely
out of scope, which is the exact confusion that forced this project to retract an earlier run.

## Traps, all of which have already happened here

- **Benchmark shopping.** Choosing the measurement after seeing which arm wins. Six of the twelve
  documented defects arose this way. Pre-register metric and direction; see
  `tests/evals/false-done/PREREGISTRATION.md` for the format.
- **Ceiling effects read as null results.** Arms agreeing perfectly is a harness problem until
  proven otherwise. Check the per-item vectors before concluding anything from an aggregate tie.
- **Validity gates that measure a model's choice.** Three versions of one gate here were wrong,
  twice failing an arm for having a different architecture, once for measuring whether a model
  chose to delegate. Prove the pathway *can* run with a canary; do not infer it from a transcript.
- **Scoring that hides collateral damage.** Fixing the target test while breaking neighbours
  scored identically to a clean fix until `PASS_TO_PASS` was added to the scoring pass.
- **Baselines that are not authenticated.** Every form of directory isolation on this machine
  loses login. Arms are isolated by time instead. An unauthenticated arm scores zero and reads as
  a weak harness.

## Known flaws in the current harness

- `tests/evals/false-done/run.sh` truncates `RUNLOG` on each invocation, so running one arm per
  call overwrites the previous arm's rows. Append instead.
- The false-completion run was interrupted at 9 of 12 for vstack; gstack was never run.
- Sample sizes throughout are too small for a confidence interval. Nothing here should be quoted
  without its n.

## What a good answer looks like

A task shape where unconfigured Claude Code measurably fails, and a comparison on it. Or a
demonstration that no such shape exists within a reasonable budget, which would be the more
interesting result and should be published as such.

If the answer turns out to be that harnesses do not improve output quality on current frontier
models, that belongs in vstack's own README. The project's claim would then narrow to what is
already verifiable: guards, reversibility, and a gate whose every check has been watched failing.
