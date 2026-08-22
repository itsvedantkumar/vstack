# Handoff: does a Claude Code harness beat unconfigured Claude Code, and where?

A research brief. Everything below is measured on this machine unless marked otherwise. Read
`tests/evals/RESULTS.md` before running anything; it records twelve defects found in this
project's own benchmark harness, seven of which flattered vstack.

> **The literature side of this question is now answered separately.** See
> [`harness-value-literature-2026-08.md`](harness-value-literature-2026-08.md), a survey of ~70
> published sources with per-claim confidence and sourcing. This file stays as the record of what
> was measured *here*; that one records what other people measured. The hypotheses below are kept
> with the verdict the literature returned on each. What the survey changed about vstack, and what
> it deliberately did not, is in
> [`what-we-changed-2026-08-22.md`](what-we-changed-2026-08-22.md).

## The question

vstack and gstack both assume a harness improves on unconfigured Claude Code. Three benchmarks
here have failed to show it. Either the benefit is real and unmeasured, or it is smaller than
assumed, or it is concentrated in task shapes nobody has benchmarked. Decide which.

Do not start from the assumption that harnesses help. The single strongest pattern in this
project's history is that the checks are wrong more often than the things they check.

## What is already measured

**SWE-bench Lite, 4 arms, 4 instances.** All four arms resolved all four under fail-to-pass-only
scoring (`.audit/run/bench-1787372531.tsv`).

Adding a `PASS_TO_PASS` regression check changed the result rather than qualifying it
(`.audit/run/hard-1787395849.tsv`). Every arm drops to 0 of 2 resolved. On `flask-5063` all three
fixed the target tests and broke **the same 2 of 20** neighbours; on `pytest-7168` all three
scored 0 of 11 outright. So the ceiling is a property of the scorer, not of the task: once
collateral damage counts there is ample headroom, no harness used it, and the identical failure
across arms points at something the config layer never touched. This is the only local measurement
with an honest baseline, and it is a three-way tie at zero.

A difficulty filter then kept 2 of 12 instances, on the basis that unconfigured Claude Code already
solves 10 of 12 outright. That 10-of-12 figure has no surviving raw rows on disk; treat it as
reported, not reproduced.

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

## Hypotheses, and the verdict the literature returned

Full evidence and sourcing in [`harness-value-literature-2026-08.md`](harness-value-literature-2026-08.md).
Each verdict below is a one-line summary of a section there, not a new measurement.

**H1. The benefit is real but appears only past a complexity threshold. UNTESTED, and harder than
it looks.** Nobody has estimated a scaffold-by-difficulty interaction on coding tasks. The nearest
result is a pre-registered GAIA study where the scaffold effect *reverses sign* between difficulty
levels for the same model. Two local complications: at extreme multi-file complexity the effect is
a floor, not amplified benefit (FeatureBench, 11.0% vs 10.5% swapping harness under a fixed Opus
4.5), and in a 45,769-task difficulty model only about 18% of tasks sit in the band where any
intervention could move the outcome. An experiment that does not deliberately sample that band
spends most of its budget on tasks decided before the harness loaded.

**H2. The benefit is in variance, not the mean. HALF CONFIRMED, and the half that confirms is not
statistical.** No published study anywhere reports a variance statistic for a coding agent with a
config layer on versus off. Not one. But behavioural tails are measured and the effects are among
the largest in the literature: prompt strictness moves test-exploitation from >85% to 1%, an
anti-cheat block moves CTF cheating 33.0% to 8.5% at no cost to legitimate solves, and stripping
consent declarations moves Claude Code's destructive out-of-scope rate from 0.0% to 17.1%.
Config-layer text reliably suppresses *intentional* shortcut-taking and unreliably suppresses
*unintentional* scope creep.

**H3. The benefit is in the things that are not model output at all. CONFIRMED as the strongest
remaining case.** This is where H2's real evidence lives, and it is the category the literature
supports.

**H4. Harnesses helped more on weaker models and the advantage has eroded. SUPPORTED IN SIGN, NOT
MONOTONIC.** Harness spread at fixed model is 27.4pp on a weak model against 12.5pp on a strong
one; prompt compilation recovers +11.0pp on the weakest model and -1.2pp (n.s.) on the strongest.
But SkillsBench's normalized gain is roughly flat across a 5x span of bare capability, and the
*weakest* model of all has the smallest gain, so the curve is closer to an inverted U than to a
clean decline. Note also: nobody has measured skill lift on any model newer than Opus 4.8, so this
extrapolates past the last measured point, and Opus 5 is where our own null was run.

**H5. The benefit is real and negative in places. CONFIRMED in direction, with a twist that makes
our result worse.** More demanding review prompts measurably raise rejection of correct code across
5 models and 3 benchmarks, and 87.2% of those spurious rejections are asserted logic defects with
no falsifiable counterexample rather than style nitpicks. But in the published pattern the thorough
prompt *buys* something: false acceptance falls as false rejection rises. Ours raised false
positives at identical recall, meaning we paid over-correction's cost without its benefit. That is
not what the literature predicts and the miss arm is worth re-checking. Adjacent and unflattering:
in SkillsBench, more skills scored worse than fewer, "comprehensive" documentation scored +0.7pp,
and agent-authored skills scored *below* no skills at all.

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
