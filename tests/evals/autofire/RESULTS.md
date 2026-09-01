# Autofire arm: do the four chain skills route from the situation alone?

**Status: complete. Read the significance caveat under the after table before quoting any number
from it.**

| | |
|---|---|
| Question | Do `writing-plans`, `test-driven-development`, `executing-plans` and `swarm` fire from a situation, with no user instruction naming them? |
| Instrument | `tests/auto-trigger.sh` SAMPLES mode. Every row logs the repo HEAD it ran at, `901bb3f`, which contains the mode itself (`d6ca391`) and the fixtures. |
| Model | `sonnet` (CLI alias), OAuth session, `ANTHROPIC_API_KEY` stripped by the harness |
| Tool fence | `Write,Edit,MultiEdit,NotebookEdit,Bash,Agent,Workflow,Explore,Task` |
| Seed / temperature | Neither. The CLI exposes no such knob, which is why n>1 exists. |
| Installed descriptions | `d4251fb4eda7` on all 60 baseline rows, `5cf618030b60` on all 40 after rows. One value per arm, no pooling. |
| Sampling | N=10 independent invocations per arm, no early stop. `ATTEMPTS` is unused. |

Raw k/N only. At n=10 a percentage or an interval would imply precision this sample does not
have, so the harness prints k/N.

Runlogs, one JSON object per sample:
`runlog-baseline-turns3-writing-plans-spec-to-steps.jsonl`,
`runlog-baseline-turns3-swarm-audit.jsonl`,
`runlog-baseline-turns3-executing-plans-checkpoints.jsonl`,
`runlog-baseline-turns3-tdd-known-bugfix.jsonl`,
`runlog-baseline-turns12-executing-plans-checkpoints.jsonl`,
`runlog-baseline-turns12-tdd-known-bugfix.jsonl`.

## Baseline at the suite default, max-turns=3

40 calls, $3.17.

| case | skill | fired | named-not-called | cut off |
|---|---|---|---|---|
| `writing-plans-spec-to-steps` | `writing-plans` | 9/10 | 0/10 | 10/10 |
| `swarm-audit` | `swarm` | 10/10 | 0/10 | 10/10 |
| `executing-plans-checkpoints` | `executing-plans` | 0/10 | 0/10 | 10/10 |
| `tdd-known-bugfix` | `test-driven-development` | 0/10 | 0/10 | 10/10 |

Every sample terminated `error_max_turns`, 40 of 40, including the two arms that fired. So being
cut off separates nothing here, and it cannot be offered as the reason the other two scored zero.
The runlog carries `fired` and `subtype` and no turn trace, so it cannot say where in a run the
decision was or was not reached. What it does say is that the two zeros were taken at a budget
that every single sample exhausted, which is enough reason to re-run them and not enough reason
to publish them.

## The same two arms at max-turns=12

20 calls, $5.61. `MAX_TURNS` became env-overridable at `17f918b` so this could run on a committed
instrument. The last person to probe turn budget here used a throwaway script and the numbers
were withdrawn for exactly that.

| case | skill | fired | named-not-called | cut off | misroutes |
|---|---|---|---|---|---|
| `tdd-known-bugfix` | `test-driven-development` | 3/10 | 0/10 | 0/10 | none |
| `executing-plans-checkpoints` | `executing-plans` | 1/10 | 0/10 | 0/10 | 2/10 to `test-driven-development` |

Cut-off drops to zero at this budget, so both arms now run to completion and choose. Turn budget
was carrying part of the TDD result: 0/10 to 3/10. It was carrying almost none of the
`executing-plans` result: 0/10 to 1/10.

`executing-plans` is the finding. Its prompt is "PLAN.md is the implementation plan we approved
last session. Execute it, and pause for my review after each phase." Its unedited description is
"Use when you have a written implementation plan to execute in a separate session with review
checkpoints." Those are close to the same sentence, and it still fires 1 time in 10. Whatever is
suppressing this skill, it is not that the description fails to describe the situation. Two of
the nine misses went to `test-driven-development` instead, on a prompt with no test in it, which
is the one piece of direct evidence in this run that these two descriptions compete.

## What the baseline overturns

The brief behind this work said `writing-plans`, `test-driven-development` and `executing-plans`
have fired zero times ever, and that `swarm` fires only when the user says "in parallel". The
first half is true of the transcript corpus (`tests/transcript-census.sh`, 2536 transcripts,
re-run 2026-09-01) and I am not disputing it.

Little of it carries over to this harness. `writing-plans` fires 9/10 on its unedited
description. `swarm` fires 10/10 on a prompt carrying none of the four trigger strings its own
description quotes, so "in parallel", "at once", "all of these" and "try N ways" are not what
carries it. For those two there is no description defect visible here and no headroom to fix one.
`test-driven-development` is weak rather than dead. Only `executing-plans` is close to dead, and
it is closest to dead where its description matches its prompt best.

### The caveat that limits all of this

`writing-plans-spec-to-steps` shares wording with the description it tests. The fixture says
"SPEC.md is agreed" against a description reading "once the shape is agreed", and "before anyone
touches app.js" against "before code". That is not a quotation, but it is the same two hinges,
and a fixture built from a description's own hinges will fire more often than a real request
does.

The gap between 9/10 here and zero in the real corpus is best explained by real prompts not
stating the situation this plainly. That is a claim about how people phrase requests, not about
how the description is worded, and this arm cannot separate the two.

Do not read this file as "the skills are fine". It says something narrower. Given a prompt that
states the situation outright, two of four route reliably, one routes weakly, one barely routes
at all, and the harness could not have told you any of that before, because its fixtures had no
referent and its only knob stopped at the first hit.

## Collision score

From `tests/description-collision.sh`. No model calls.

| | corpus score | hard-fail pairs |
|---|---|---|
| unedited (28 skills) | 23 | none |
| with the four rewrites | 13 | none |

The 10-point drop is exactly the two overlaps the ordinal framing created:
`test-driven-development` against `writing-plans` on "once shape", worth 6, and `brainstorming`
against `test-driven-development` on "shape known", worth 4. Three descriptions opening
`Nth, once the shape is X` compete on the same tokens in the clause a matcher weighs hardest,
and the `executing-plans` arm shows `test-driven-development` taking prompts that are not its
own.

This is design discipline, not a dispatch law. The claim that colliding triggers suppress both
skills was withdrawn in 1.47.0, and the pre-registered replacement found the hypothesis
unsupported (`tests/evals/collision/RESULTS.md`).

## After the rewrite

All four rewritten descriptions were installed together for this arm, by
`tests/stage-skill-descriptions.sh`, and restored afterwards. Digest `5cf618030b60` on all 40
rows. Each arm is budget-matched to its own baseline. 40 calls, $7.41.

Runlogs: `tests/evals/autofire/runlog-after-writing-plans-spec-to-steps.jsonl`,
`runlog-after-swarm-audit.jsonl`, `runlog-after-tdd-known-bugfix.jsonl`,
`runlog-after-executing-plans-checkpoints.jsonl`.

| skill | budget | before | after | Fisher p, two-sided | reading |
|---|---|---|---|---|---|
| `executing-plans` | 12 | 1/10 | 6/10 | 0.0573 | moved, not significant |
| `test-driven-development` | 12 | 3/10 | 3/10 | 1.0 | unchanged |
| `writing-plans` | 3 | 9/10 | 10/10 | 1.0 | no regression, no headroom |
| `swarm` | 3 | 10/10 | 10/10 | 1.0 | no regression, no headroom |

### The threshold passed and the statistic did not

Before the arm I registered: an arm counts as fixed when baseline is at most 1/10 and after is at
least 6/10. `executing-plans` came in at exactly 1/10 and 6/10, so the threshold is met.

It should not have been written that way. I derived "6/10" against an assumed 0/10 baseline,
where it gives p=0.0108 and clears the Bonferroni alpha of 0.0125 that four tests want. The
measured baseline was 1/10, and I never went back and re-derived the bound. Against 1/10, 6/10 is
p=0.0573. It clears neither 0.0125 nor 0.05.

So the check passed while the thing the check stood for did not. That is the failure
`docs/checks-that-inherit-their-answer.md` catalogues, and this is an instance of it in my own
pre-registration rather than in someone else's. The honest statement of this result is that
`executing-plans` moved from 1/10 to 6/10 and that n=10 cannot establish the move. Separating
those two rates at Bonferroni alpha needs roughly n=20 to 25 per arm, about $12 more at this
budget.

`test-driven-development` did not move at all. The rewrite bought it a description that asserts a
checkable property instead of an invisible chain position, and bought no dispatch. Both are in
the runlog.

The `executing-plans` misroute did not close. Two of ten samples still fire
`test-driven-development` on a prompt with no test in it, the same 2 as at baseline. The rewrite
narrows what makes those two compete without removing it.

## Cost

The harness records this per arm. Nobody estimated it. Baseline at turns=3 cost $3.17 across 40
calls, $0.079 each. The turns=12 re-run cost $5.61 across 20 calls, $0.281 each. The after arm
cost $7.41 across 40 calls. Total for the published arms: $16.19 across 100 calls.

## Instrument changes after the baseline, and why they do not invalidate it

Two defects were found by review after the baseline ran and fixed before the after-arm.

The runlog row was built by `printf` with a bare `%s` for `fired`, which comes from a
model-controlled tool-call argument. A value containing a double quote emits a line that fails
`jq .`. It is built by `jq -cn --arg` now. No baseline row was affected: every `fired` value in
all 60 rows is a plain skill name, and the file parses.

`stage-skill-descriptions.sh` had unchecked `cp` calls in both directions. That script took no
part in the baseline, which ran against the installed descriptions unmodified.

Neither change alters what a sample measures, so the baseline and after arms remain comparable.
