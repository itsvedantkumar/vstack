# Results: skill-collision arm, matched pairs

Run 2026-08-27. Thresholds fixed in advance in `PREREGISTRATION.md`, committed at `224eef7`
before the first sample. Instrument: `tests/dispatch-fleet.sh` at that commit, unedited, driven by
environment overrides only.

```
# dispatch-fleet runlog schema=2 model=sonnet max_turns=20
# tools=Write,Edit,MultiEdit,NotebookEdit,Bash,Agent,Workflow,Explore,Task
# fixtures=~/vstack-dispatch/fixtures.jsonl  sha256 d940b4d3...be4537
```

The committed runlog carries one edit and no other: the header's `fixtures=` path was rewritten
from this machine's absolute home path to `~/`, because `.claude/verify.sh`'s home-path scanner
refuses a committed absolute `/Users/...`. The file's sha256 before that edit was
`a79ae7ff97d332efb5f90bf4b84d4e861413b9c632dcd6626b3132e23537ab1b`, recorded here so the redaction is auditable. The path was never the
instrument's identifier anyway; the fixture digest in `PREREGISTRATION.md` is. The harness should
write a `$HOME`-relative path and the fixture digest into the header itself, which would remove
the need for any post-hoc edit. That change is deliberately not made in the same commit as this
arm's first result.

25 samples, 25 rows plus the header. Every sample returned `subtype=success`. Zero fence
violations. `--score-only` over the committed runlog reproduces every figure below with no model
calls.

## What was measured

| Arm | Fixture | Expected | Fired | Skill calls |
|---|---|---|---|---|
| P-swarm | `pos-19` | `swarm` | 0/5 | 0 |
| C-swarm | `col-13` | `swarm` | 0/5 | 0 |
| P-encode | `pos-11` | `principle-encode-lessons-in-structure` | 0/5 | 0 |
| C-encode | `col-15` | `principle-encode-lessons-in-structure` | 0/5 | 0 |
| C-literal | `col-01` | `grill-me` or `interrogate` | 4 none, 1 `interrogate` | 1 |

One `Skill` call in 25 samples.

## Verdicts against the pre-registered thresholds

**H-C1, a shared literal trigger suppresses both skills: threshold met, hypothesis not supported.**
`col-01` returned an empty `fired` in 4 of 5 samples, which is the registered CONFIRM bound of
≥4/5. The conclusion does not follow, because both positive-control fixtures returned empty in 5 of
5. Empty is the modal outcome of every fixture in this run, collision or not, and `col-01` fired
*more* often than either control. The suppression reading requires a baseline where uncolliding
skills fire, and this run has no such baseline.

**The threshold was mis-specified, and it is the same defect this repository catalogues.** H-C1 was
written as a bare bound on one arm with no control clause. It returns CONFIRM on a run where
nothing fired at all, which is a true statement about the wrong question. It was written on the
morning of the run by the author of `docs/checks-that-inherit-their-answer.md`. A correct H-C1
reads: empty in ≥4/5 on `col-01` **and** fired in ≥4/5 on at least one control. That amendment is
recorded here, after the fact, and is not applied retroactively to score this run.

**H-C2, the collision framing fails while the skill stays reachable: FALSIFIED for both skills.**
Neither skill reached the ≥4/5 bound on its own clean positive fixture.

**H-C3, the skill does not fire under this harness at all: CONFIRMED for both skills.** `swarm` is
0/5 on `pos-19` and 0/5 on `col-13`. `principle-encode-lessons-in-structure` is 0/5 on `pos-11` and
0/5 on `col-15`. Collision framing explains none of it.

**No void condition was met.** All 25 samples succeeded, the runlog holds exactly 25 rows, the
fixture digest matched, and no workdir was written outside the three files the harness creates.

## Why nothing fired, from the transcripts

`KEEP_WORKDIRS=1` retained all 25 transcripts, which is what the lost 2026-08-24 arm could not do.
Two mechanisms account for every sample, and neither is trigger collision.

**The workdir is empty, so the prompt has no referent.** The harness runs each sample in a fresh
`mktemp -d` holding only the three files it creates. `pos-19` asks the model to audit six packages
that do not exist. All 5 samples ran `Glob`, found nothing, and asked which repository held them.
`col-13` says "Try three different approaches to this and compare", and "this" has no antecedent in
a one-shot prompt; 3 of 5 samples answered in a single turn with no tool calls at all. `col-01`
says "Tear this apart" with nothing present to tear apart.

> No project files here. `/private/tmp/dispatch-fleet.lkBy6L` only has log files, no packages.
> Which repo/path has the six packages you want audited?
> **Next:** point me at the repo path so I can dispatch the swarm.
> — `pos-19`

**The affordance is denied, so the model pursues the action and is stopped.** `pos-11` says "That's
the second time I've told you to use pnpm not npm". All 5 samples went straight to writing a memory
file, and all 5 called `Write`, which the fence denies. They then reported that they could not
persist it.

> I can't write the memory file this session since Write is disabled. The pnpm-not-npm rule stands
> as in-session context only until Write is available again.
> — `pos-11`

`col-15` reached the same wall earlier: 4 of 5 samples searched for a write tool through
`ToolSearch`, found none, and said so without attempting the call. The fifth declined on the merits
and is the most interesting sample in the run:

> Duplicating it in memory won't fix that. I'll enforce it directly on every task going forward, no
> separate reminder needed.
> — `col-15`

**The routing knowledge was present the whole time.** The model named the skill it would have used,
in prose, without calling it: `swarm` in 7 of the 10 `swarm` samples, and `interrogate` or
`grill-me` in 4 of the 5 `col-01` samples. On `pos-11` it named no skill and instead performed the
skill's action directly, which is the same result by a different route.

> `interrogate` needs a diff or artifact to review. There's nothing here to tear apart.
> — `col-01`, a sample that did not call `Skill`

## What this closes and what it opens

The open question was why one arm of fixtures scored uniform zeros while an earlier arm did not,
given that no single mechanism seemed to explain both. A single mechanism does explain both: the
harness supplies no situation, and denies the tools that several skills exist to use. A fixture
whose prompt is self-contained and needs no repository and no denied tool can still fire. A fixture
that needs either cannot, whatever its trigger words are.

This is a defect in the instrument, not a finding about skills. `tests/dispatch-fleet.sh` scores a
miss and a clarifying question identically: both are `fired=[]`. The distinction is visible only in
the transcript, and the harness deleted transcripts by default until `KEEP_WORKDIRS` was added.
Every `pos-*` figure taken through this harness inherits the confound.

**H11 is confirmed wider than it was registered.** The publication gate in
`tests/dispatch-fleet.sh` asks whether denying `Write` suppresses skills "whose expected output is
an artifact". This arm chose `principle-encode-lessons-in-structure` as the control *because* its
output is prose. That premise was wrong: its output is a memory file, and 5 of 5 samples proved it
by calling `Write` and being denied. The category "artifact-producing skill" is larger than the
gate's author assumed, and the gate should stay closed.

**The `col-01` result is weak evidence against suppression, not for it.** One clean `interrogate`
call, and three more samples naming `interrogate` in prose, in the fixture whose prompt is a literal
trigger string in two competing descriptions. If a shared trigger suppressed both skills, that is
not what a shared trigger looks like. At n=5 this settles nothing on its own, and it is reported as
the raw split the pre-registration requires rather than as a rate.

## What to run next

Not more samples through this harness. The instrument needs a fixture-appropriate workdir and an
arm that permits the denied tools before any dispatch rate it produces means anything. Two changes,
in this order:

1. Give each fixture a workdir that contains what its prompt refers to, or mark the fixture as one
   that needs none. Roughly half the collision fixtures refer to a repository, a diff, or a prior
   turn that the harness does not provide.
2. Run one arm with `Write` and `Bash` permitted. That is arm A5 of
   `tests/evals/build-the-lever/PREREGISTRATION.md` and it is still the named condition on the
   publication gate. This run raises its priority: the fence demonstrably stopped 5 of 5 samples on
   a fixture nobody expected it to touch.
