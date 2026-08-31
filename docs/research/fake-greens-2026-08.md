# Checks that measure nothing

A check that returns a true statement about the wrong question is worse than no check. It costs
the same to run, it prints the same word, and it removes the pressure that would otherwise produce
a real one. This repository was built to test its own configuration and has spent six months
finding that its checks kept doing exactly that. This document reports what those runs measured.

The claim is narrow and it is not about model quality. Nothing here shows that an agent
configuration makes a frontier model write better code; the measurements this repository has run
on that question came back flat, and they are reported below with the rest. The claim is about
verification: **in a system that checks itself, the dominant failure is not a wrong answer but a
right answer to a question nobody asked.** Thirteen instances are catalogued. Two of them are in
this document's own evidence base.

Every number below names the file and the date it came from. Numbers without a surviving artifact
are marked unsourced and are not used to support anything.

## What the defect looks like

The shape is always the same. A check asserts something true. The truth of that thing does not
depend on the property the check exists to protect. The check passes forever, including on the day
the property breaks.

Three instances, each confirmed by running it:

- A statusline read a dispatch counter that no code ever wrote. The reader worked. The number it
  displayed was the absence of a writer, rendered as zero (`CHANGELOG.md`, 1.41.0).
- A mandate hook required agents to be named on dispatch, matching on the tool name `Task`. Against
  a real 15 MB transcript the session contained 70 `Agent` dispatches and zero `Task` matches. The
  mandate had been structurally unable to fire since it shipped (1.37.0).
- `doctor --drift` printed `no drift ✔ (74 item(s) compared)`. A new file family had shipped that
  its globs never matched. The count was 74 before the file existed and 74 after (1.45.1).

The third is the instructive one. The verdict was correct: there was no drift among the items it
compared. The question it was asked was whether the tree had drifted. Reading the verdict answers
the first question. Reading the count answers the second, and only the count moved, by staying
still.

`docs/checks-that-inherit-their-answer.md` catalogued thirteen of these when this document was
written. Six were found on 2026-08-22 and six more across 2026-08-26 and 2026-08-27. Six plus six
is twelve, and the catalogue's heading said thirteen. The document did not reconcile its own
arithmetic, which is recorded here rather than rounded away; on 2026-09-01 the catalogue moved its
uncounted coverage-gap note under a separate heading, so the instances are now derivable and stand
at seventeen. The numbers below are the ones this run measured and are not restated to match. The
document predicted roughly one a
month. Its own dates falsify that prediction by about an order of magnitude, which is the honest
reading of a catalogue that keeps growing under a fixed search.

Two of the entries are a distinct sub-shape and matter more than the rest: a check whose assertion
is load-bearing and true, attached to a decision it does not govern. No mutation test catches
these. Mutation testing proves a check notices when its subject changes. It cannot prove
the subject is the thing you care about.

## How the evidence is produced

Four mechanisms, in the order they were added, each after a failure that the previous three did not
catch.

**Mutation testing on the gate.** `tests/gate-falsifiability.sh` declares 73 rows (70 mutations
plus 3 fixed). Each row breaks exactly what one check watches, then requires `.claude/verify.sh` to
go red **naming that specific check**, not merely to go red. It then restores the file byte for
byte and refuses to restore over a third party's concurrent write. Two details are load-bearing and
were both added after the row they protect failed silently:

- If a mutation leaves a file's hash unchanged, the row fails as "mutation changed nothing," not as
  a pass. Rows 11, 26 and 28 each rotted this way. Their patterns stopped matching after a
  refactor, and they reported success while mutating nothing.
- Mutations are anchored on the decision the check asserts, never on a line that happens to be
  unique. Row 27 mutates `[ -n "$unmet" ] || exit 0` in `claude/hooks/skill-mandate.sh` because
  that expression *is* the block/no-block decision. Its predecessor was anchored on a nearby
  bookkeeping line, and one refactor moved that line and disarmed the row.

**Oracle controls that bite in both directions.** `tests/dispatch-fleet.sh` was proved against two
stubs at zero model cost before it measured anything: an always-firing stub scores 75/75 recall and
0/24 precision, and a never-firing stub scores the reciprocal. A harness that only reports recall
gives the always-firing stub a perfect score.

**Pre-registration.** Thresholds are fixed in a committed file before the first sample. Three exist:
`tests/evals/build-the-lever/PREREGISTRATION.md`, `tests/evals/agent-pilot/PREREGISTRATION.md`,
`tests/evals/false-done/PREREGISTRATION.md`. Each names its confirm bound, its falsify bound, its
void conditions, and the moves that would invalidate it. Each states in advance that a null result
is published as a null result.

**Publication gates.** `tests/dispatch-fleet.sh` refuses to let any fleet-wide recall or precision
figure be published until one specific arm reports, because that arm tests whether the harness's own
tool fence suppresses every skill whose output is a file. The gate is a comment in the harness, next
to the code it restricts.

## Result: guards that decide correctly and enforce nothing

`claude/hooks/guard-destructive.sh` classifies 37 destructive commands across three tiers and is
correct on all 37, including under a stripped environment. `tests/repro/guard-quote-aware-split.sh`
passes 18 of 18.

Under `bypassPermissions`, a live probe ran `git reset --hard` with the guard returning `ask`. The
command executed, returned 0, and produced no prompt and no block. Force-push to `main` was
enforced; the reset was not. On the same day, four agents lost uncommitted files to a bare `git
stash` and a fifth to a hard reset.

The check was measuring the decider. Enforcement is a separate system, and nothing was measuring
the join between them. Two fixes shipped, and they differ in kind. `.claude/verify.sh` now labels that check
`(decider only, not runtime enforcement)` in its own pass line, so the check keeps its scope and
stops implying a larger one. Separately, the guard escalates `ask` to `deny` under
`bypassPermissions` for the commands the probe caught leaking, so that specific hole is closed.
The label fix is the one that generalises. The escalation only covers commands somebody thought
to name. `docs/guard-enforcement-gap.md` records the probe and, separately,
what could not be verified and why.

The general lesson is stronger than the instance. A reader tested against a hand-made fixture passes
forever while its writer does not exist. Test the join, and grep for the writer.

## Result: skill descriptions behave like a keyword index

Skills are markdown files with a description. The runtime decides which to surface from those
descriptions. Every number in this section comes from `tests/auto-trigger.sh` at n=10 unless stated,
and that harness's replication limits are set out under "Threats to validity". They are severe.

- Rewriting `principle-type-system-discipline`'s description around the nouns a user actually types
  moved it from 1/10 to 9/10, matching its control.
- The identical method applied to `principle-build-the-lever` did not move it: 2/10 before, 2/10
  after. The rewrite was reverted rather than shipped, because a change that does not move its
  metric is not an improvement.
- `principle-prove-it-works` scored 0/10 on its own fixture and was replaced by a `Stop`-hook check.
  A skill that never fires is a file, not a mechanism.
- Removing the routing table from `CLAUDE.md` moved a 9-case subset from 9/9 to 7/9;
  `technical-writing` and `typescript-best-practices` never fired without it
  (`docs/how-skills-fire.md`).
- Across the 60 runs of the review benchmark in `tests/evals/RESULTS.md`, the `Skill` tool was
  invoked **zero** times in every arm, including the arm with 70 skills loaded.

The standing explanation for the hard cases is registered as H7 in
`tests/evals/build-the-lever/PREREGISTRATION.md`: the trigger for some skills is a counterfactual
about the model's own forthcoming plan, not a property of the user's prompt, so a dispatcher scoring
descriptions against a prompt has nothing to score. H7 has not been tested. Neither have H8 through
H11. Only Stage 0 has reported, and it is an instrument check: the description reaches the model
byte-identical, 171 of 171 characters, 3 of 3 samples.

Two byproducts of Stage 0 are worth more than the stage itself. Denying the `Skill` tool removes the
skill listing from context entirely, so a harness that fences `Skill` measures nothing about skills.
And on this build, deferred-tool discovery through `ToolSearch` consumed two turns, which is the
entire budget of a case at the suite default of three.

## Result: no measurable quality gain

`tests/evals/RESULTS.md` records five runs and retracts one, keeping the retracted table with its
reason attached.

| Run | Design | Result |
|---|---|---|
| Review benchmark, 2026-08-21 | 4 fixtures × 5 samples × 3 arms, 60 calls | unconfigured 11/15, vstack 11/15, other bundle 10/15; zero false positives in every arm |
| Review pathway, 2026-08-22 | 8 fixtures × 2 samples × 3 arms, 48 reviews, n=16 per arm | all three arms 11/14 (79%); precision 92%, 85%, 73%; false positives 1, 2, 4 |
| SWE-bench Lite | 4 instances × 3 arms | 0/4 for every arm on the first three runs, none of which was a result, because of three separate harness defects |

The 2026-08-22 row is the first run on which all three arms worked, and it is a three-way tie on
recall with the configured bundle worst on precision. Per-fixture hit vectors were printed to show
the tie is a tie and not a collapsed harness.

This is the finding the repository exists to report and the one it likes least.
`docs/what-this-actually-does.md` opens by stating it: there is no evidence this configuration
improves output quality on a frontier model. The defensible case for a configuration layer is
safety and reversibility, not output quality, and that case is made by the guard and gate results
above rather than by any benchmark here.

## Result: instruments that returned NOT EVALUATED

Two instruments were built, run, and reported no result, which is the outcome a harness that always
produces a number cannot express.

`tests/compaction-effect.sh` found that of 3,134 transcripts on this machine, only 8 contain a
compaction event. It reported NOT EVALUATED until enough boundaries existed, then reported a real
null: `is_error` at 1/45 before versus 0/45 after across 3 automatic boundaries, and 5/90 versus
7/90 across 6 manual ones. Both ratios sit under the 1.5× threshold fixed in advance.

`tests/delegation-drift.sh` had 2 and 3 eligible windows against a floor of 8 and still reports NOT
EVALUATED. It has never produced a number, which is the correct behaviour and the reason it is
mentioned here.

Both instruments were also found to be counting per-subagent transcript leaves as sessions: 965 of
3,292 files under the transcript directory are leaves, and 15 of 51 replayed sessions were leaves of
two parents. After the fix, neither instrument's printed numbers moved. A contamination that does
not move the result is still worth fixing, because the next question asked of the same corpus may
not be so forgiving.

## Result: two of this repository's own numbers had no artifact

The defect generalises past checks, to citations.

`CHANGELOG.md` stated that colliding triggers "were measured over 80 samples to suppress both
skills, not one." No 80-sample runlog exists in this repository's history or on the machine that
produced it. The only collision arm on record is 55 samples on a single fixture
(`tests/README.md`), and its instrument was an uncommitted local edit to `tests/dispatch-fleet.sh`
. That file's own fence comment already recorded the fact. Its runlog lived under `/private/tmp`
and is gone.

`CHANGELOG.md` also stated that a session "got a uniform 0/5 across five fixtures," cited as the
reason for building a per-dispatch replay log. That figure is not merely unsourced: the harness
cannot produce it. In `tests/dispatch-fleet.sh`, only fixtures of kind `skill` and kind `none`
receive a numeric score; a `CHAIN:` or `AMBIGUOUS:` fixture returns a null score and a distribution
instead. Two of the five fixtures in that arm are exactly those kinds, so the fraction attributed to
them could never have been printed.

Both lines keep their place with a retraction note attached. The direction each arm reported stands
as what that arm reported; the sample count is withdrawn from both. Deleting them would remove the
evidence that this happened.

Two mechanisms exist now because of this. `tests/dispatch-fleet.sh` writes a schema=2 runlog header
recording the model, turn cap, tool fence and fixture path of every arm, and refuses to append
samples drawn under different parameters rather than mix two arms into one score. And its tool
fence is environment-overridable, because a literal with no override is what forced the source edit
that destroyed the instrument.

## Result: the collision claim did not survive a committed instrument

The withdrawn "80 samples" claim was re-measured on 2026-08-27 under thresholds committed before the
first sample (`tests/evals/collision/PREREGISTRATION.md`) and a harness that was not edited. Five
fixtures, 5 samples each, 25 calls. Full report in `tests/evals/collision/RESULTS.md`.

Matched pairs, so that a suppressed skill can be told apart from a silent one: `swarm` and
`principle-encode-lessons-in-structure` each on their clean positive fixture and on their collision
fixture, plus `col-01` ("Tear this apart."), which is a literal trigger string in both `grill-me`'s
and `interrogate`'s descriptions.

| Fixture | Expected | Fired |
|---|---|---|
| `pos-19` | `swarm` | 0/5 |
| `col-13` | `swarm` | 0/5 |
| `pos-11` | `principle-encode-lessons-in-structure` | 0/5 |
| `col-15` | `principle-encode-lessons-in-structure` | 0/5 |
| `col-01` | `grill-me` or `interrogate` | 4 none, 1 `interrogate` |

One `Skill` call in 25 samples, every sample `subtype=success`, no fence violations.

The transcripts were kept, which the 2026-08-24 arm could not do, and they show two mechanisms.
The harness runs every sample in an empty `mktemp -d`, so a prompt that refers to a repository, a
diff, or a prior turn has no referent: all 5 `pos-19` samples globbed, found no packages, and asked
which repository held them. And the fence denies `Write`, so a skill whose action is to write a
file gets as far as the attempt: all 5 `pos-11` samples called `Write` and were refused.

The model knew the routing the whole time. It named `swarm` in prose without calling it in 7 of the
10 `swarm` samples, and named `interrogate` or `grill-me` in 4 of the 5 `col-01` samples. On
`pos-11` it named no skill and performed the skill's action directly instead.

So one mechanism explains both arms of the anomaly, and it is the instrument. `fired=[]` is recorded
identically for "the dispatcher did not route" and "the model asked which repository you meant."
Every dispatch rate this harness has produced inherits that confound.

Two further consequences. `col-01` fired more often than either uncolliding control, which is weak
evidence against suppression rather than for it. And H11, the hypothesis that the tool fence
suppresses skills whose output is an artifact, is confirmed wider than it was registered: this arm
picked `principle-encode-lessons-in-structure` as the fence-immune control because its output is
prose, and 5 of 5 samples disproved that premise by calling `Write`.

One more result, and it is the least comfortable in this document. H-C1 was written as a bare bound
on one arm: empty in 4 of 5 samples confirms suppression. `col-01` returned empty in 4 of 5, so the
threshold was met. It means nothing, because both controls returned empty in 5 of 5 and empty was
the modal outcome of every fixture in the run. The threshold lacked a control clause and would
therefore return CONFIRM on any run in which nothing fired at all. It was written on the morning of
the run, in a pre-registration whose stated purpose is to prevent exactly this, by the author of the
catalogue this paper is built on. Thirteen instances in a repository, and the fourteenth is in the
instrument written to measure the thirteenth.

## Threats to validity

Stated plainly, because the paper is about checks that overstate their scope.

- **Every per-skill dispatch rate above is unreplicable.** `tests/auto-trigger.sh` did not commit
  its probe script and no per-run output survives. Five commits landed in that harness in one
  session, touching tool availability and turn budgets, so cross-commit comparison of those rates
  is not supported by the single n=10 control run afterwards. The 1/10 → 9/10 result is the
  strongest single effect in this document and it rests on the weakest instrument.
- **n is small everywhere.** The benchmark arms are n=15 and n=16. A three-way tie at n=16
  excludes a large effect and nothing finer.
- **One machine, one operator, one model family.** Nothing here is a claim about other setups.
- **The harness fences its own subject.** `tests/dispatch-fleet.sh` denies the tools that several
  skills exist to use. Whether that suppresses those skills is registered as H11 and is untested,
  which is why the publication gate on fleet-wide figures is still closed.
- **The fixture labels are an author's judgement** of what should fire, never validated against a
  live matcher. A miss may be a wrong label.
- **This document is not falsifiable in the way its subjects are.** No mutation test can turn it
  red. Treat it as a report on artifacts you can re-run, and re-run them.

## What would change the conclusions

- A benchmark at n large enough to resolve a 5-point difference, on more than one task family,
  showing the configured arm ahead. Nothing here is designed to detect that; the runs above are
  sized to detect a large effect and found none.
- Arm A5 of `tests/evals/build-the-lever/PREREGISTRATION.md` returning k ≥ 8/10, which would mean
  the tool fence has been depressing every artifact-producing skill and every dispatch figure taken
  through that harness is wrong in the pessimistic direction by an unknown margin.
- A month in which `docs/checks-that-inherit-their-answer.md` does not grow under the same search.
  The catalogue's rate is currently its own strongest finding.
