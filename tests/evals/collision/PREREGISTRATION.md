# Pre-registration: skill-collision arm, matched pairs

Written before the first sample was drawn, and committed before the harness was invoked. The
instrument this arm replaces was an uncommitted local edit, so the finding it produced cannot be
rebuilt from git — see "What this arm replaces" below. Committing the thresholds first is the only
part of that failure this document can prevent.

## The question

Two claims are published in `CHANGELOG.md` and neither has a surviving artifact:

- `CHANGELOG.md:23` — "Colliding triggers were measured over 80 samples to suppress both skills,
  not one." No 80-sample runlog exists on this machine or in git history. The only collision arm
  the repository records is **55 samples on `col-11` alone** (`tests/README.md:188`), produced by a
  local uncommitted edit to `tests/dispatch-fleet.sh` (its own fence comment, line 180, says so).
- `CHANGELOG.md:572` — "a uniform 0/5 across five fixtures", cited as the motivation for building
  the per-dispatch replay log in 1.43.0. No runlog, no transcripts, no fixture list.

Both read as measured. Neither can be re-read. That is the same defect this repository catalogues
in `docs/checks-that-inherit-their-answer.md`, applied to its own evidence base rather than to a
check.

So the question is not "why did those five fixtures score zero". That question is unanswerable:
the data is gone, and the harness cannot even produce the shape claimed — at
`tests/dispatch-fleet.sh:678-688` only `kind=="skill"` and `kind=="none"` fixtures get a numeric
`k`, so `col-11` (`CHAIN:brainstorming`) and `col-14` (`AMBIGUOUS:...`) return `{k: null}` and can
never print `0/5`.

The question this arm asks instead:

> When a skill fails to fire on a collision-framed prompt, is that because the collision
> suppressed it, or because that skill does not fire on any prompt under this harness?

One arm cannot answer that. Matched pairs can.

## Design

Each of two skills is run on **both** its clean positive fixture and its collision fixture, from
the same frozen fixture file, in one invocation, under one runlog header. A fifth arm reruns the
strongest form of the collision claim: a prompt that is a literal trigger string in two skill
descriptions at once.

| Arm | Fixture | Prompt | `expect` | n |
|---|---|---|---|---|
| P-swarm | `pos-19` | Audit these six packages for unused deps, all at once. | `swarm` | 5 |
| C-swarm | `col-13` | Try three different approaches to this and compare. | `swarm` | 5 |
| P-encode | `pos-11` | That's the second time I've told you to use pnpm not npm. | `principle-encode-lessons-in-structure` | 5 |
| C-encode | `col-15` | I keep having to remind you to run the tests. | `principle-encode-lessons-in-structure` | 5 |
| C-literal | `col-01` | Tear this apart. | `AMBIGUOUS:grill-me\|interrogate` | 5 |

**25 model calls. No more without an explicit further authorisation.**

n=5 is a pilot. At n=5 a two-sided 95% Wilson interval on 5/5 is [0.566, 1.000] and on 0/5 is
[0.000, 0.434]: the intervals do not overlap, so 5/5-versus-0/5 is a real separation and anything
between them is not. The thresholds below are set accordingly and are not negotiable after the run.

## Instrument

**Zero edits to `tests/dispatch-fleet.sh`.** Every parameter is passed by environment override.
That override path exists because a source edit is what destroyed the last arm; using it is the
point. A harness change would also invalidate the harness's prior findings
(`tests/README.md`: "A harness change invalidates its own prior findings").

```sh
N=5 MODEL=sonnet MAX_TURNS=20 KEEP_WORKDIRS=1 \
FIXTURES="$HOME/vstack-dispatch/fixtures.jsonl" \
RUNLOG=tests/evals/collision/runlog-2026-08-27.jsonl \
./tests/dispatch-fleet.sh pos-19 col-13 pos-11 col-15 col-01
```

- `MAX_TURNS=20`, not the suite default of 3: Stage 0 of the build-the-lever pre-registration
  measured `ToolSearch` deferred-tool discovery consuming 2 turns, which is two thirds of a
  3-turn budget before the model has decided anything.
- `DISALLOWED_TOOLS` is left at the committed default. It is recorded in the runlog header either
  way, and `check_runlog_params()` refuses to append samples drawn under different parameters.
- `KEEP_WORKDIRS=1`. The transcripts are the thing the lost arm did not have.
- The runlog is written to a **tracked path inside the repository** and committed with the
  results. `/private/tmp` is where the last one went and is why there is nothing to read.

**Fixture file pinned by content, not by path.** `~/vstack-dispatch/` is not a git repository and
carries no checksum, so the path alone does not identify what was run:

```
sha256  d940b4d37512bdf9085d2ee2184c4e936ac6095b02e455a9b8408c1815be4537
lines   54
classes pos 25, neg 8, col 15, var 6
```

If that digest does not match at run time, the arm is void and the mismatch is published.

## Hypotheses and thresholds, fixed in advance

**H-C1 — a shared literal trigger suppresses both skills.**
The published claim, in its strongest form. `col-01`'s prompt ("Tear this apart.") is a literal
string in both `grill-me`'s and `interrogate`'s descriptions.
- CONFIRM: `fired` is empty in ≥4/5 samples.
- FALSIFY: `fired` is empty in ≤1/5 samples.
- INDETERMINATE: 2/5 or 3/5. Reported as indeterminate, not rounded toward the prior.

**H-C2 — the collision framing fails, the skill is reachable.**
- CONFIRM, per skill: fires ≥4/5 on its `pos-*` fixture and ≤1/5 on its `col-*` fixture.
- Evaluated separately for `swarm` and `principle-encode-lessons-in-structure`. A split verdict
  is a result, not a problem.

**H-C3 — the skill does not fire under this harness at all.**
- CONFIRM, per skill: ≤1/5 on **both** its fixtures. The collision prompt then explains nothing,
  and any prior zero attributed to collision was attributed wrongly.

H-C2 and H-C3 are mutually exclusive by construction. If neither holds for a skill (e.g. 3/5 and
3/5), that skill's verdict is INDETERMINATE and is published as such.

**Discriminator for H11 — the tool fence.**
`tests/dispatch-fleet.sh:277-283` carries a standing publication gate: the fence may be suppressing
every skill whose expected output is an artifact. This arm was chosen to bear on it at no extra
cost. `swarm`'s affordance is the `Agent` tool, which the harness's own hard guard **requires** to
be denied (`dispatch-fleet.sh:195-224` refuses to run if `Agent` or `Workflow` is absent from the
fence). `principle-encode-lessons-in-structure`'s output is prose and needs no denied tool.
- If `swarm` is ≤1/5 on both arms while `principle-encode-lessons-in-structure` fires ≥4/5 on
  `pos-11`, H11 explains `swarm` and only `swarm`, and the fence — not collision — is the
  mechanism behind at least one prior zero.
- This does **not** discharge the publication gate. Arm A5 of
  `tests/evals/build-the-lever/PREREGISTRATION.md` is still the gate's named condition.

## Void conditions

- The fixture digest above does not match at run time.
- ≥3 of the 5 arms return `subtype` other than `success` (`no_output`, `error_max_turns`) in a
  majority of their samples. The instrument is then dead and no hypothesis is scored.
- The runlog does not contain exactly 25 rows, or `--score-only` over the committed runlog does not
  reproduce the same k/n with zero model calls.
- Any `fence_violations` entry. The workdir is supposed to be untouched.

A void run is published as void. It is not re-run with different parameters and reported as one
result.

## Named invalidators

Stated in advance, in the form `~/vstack-dispatch/README.md` uses:

- **Editing a fixture after seeing a score.** The fixture file is frozen by digest above.
- **Adding an arm after seeing results.** Five arms, 25 calls. A sixth arm is a new
  pre-registration with its own digest, not an appendix to this one.
- **Scoring the `AMBIGUOUS` fixture as a pass/fail.** `col-01`'s split *is* the datum. A 50/50
  split and a 100/0 split are different findings and neither is an error
  (`dispatch-fleet.sh:831`).
- **Choosing the threshold after the run.** ≥4/5 and ≤1/5 are fixed here.
- **Publishing a fleet-wide figure.** This arm publishes **per-fixture** numbers only. No `pos-*`
  recall or `neg-*` precision figure may be derived from it; the publication gate at
  `dispatch-fleet.sh:277-283` is untouched by this run.
- **Reading the exit code instead of the trailer.** The verdict is read off the printed k/n and
  the retained transcripts, not off `$?`.

## Declared limits

- n=5 per arm. This is a pilot sized to separate 5/5 from 0/5 and nothing finer.
- Two skills. Whatever it finds about `swarm` and `principle-encode-lessons-in-structure` does not
  generalise to the other 26 without running them.
- The visible skill set is whatever is installed under `~/.claude` at run time, since the harness
  deliberately does not isolate `CLAUDE_CONFIG_DIR` (`dispatch-fleet.sh:83-90`). The installed
  version is recorded in the results.
- The fixture labels are an author's judgement of what *should* fire, never validated against a
  live matcher (`~/vstack-dispatch/README.md`). A miss may be a wrong label.
- `MODEL=sonnet` matches the parameters the lost arm is recorded as having used, so that this arm
  is comparable to it in the one respect that record survives. It says nothing about any other
  model.

## What this arm replaces

Nothing. Both prior claims stay in `CHANGELOG.md` with an annotation naming them unsourced, the
way `tests/evals/RESULTS.md` keeps its retracted run with the reason attached. A number deleted
is a number that cannot be argued with later.
