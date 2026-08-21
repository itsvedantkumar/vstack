# Review benchmark — results

Reproduce with:

```bash
GSTACK_DIR=/path/to/gstack tests/evals/run.sh --arms none,vstack,gstack --samples 5
```

## Run of 2026-08-21

4 fixtures × 5 samples × 3 arms = 60 model calls, Claude Opus 5, one file per review.

| arm | planted defects found | false positives | skills loaded | skill invocations |
|---|---|---|---|---|
| none (built-ins only) | 11 / 15 | 0 | 16 | 0 |
| vstack | 11 / 15 | 0 | 42 | 0 |
| gstack | 10 / 15 | 0 | 70 | 0 |

**No configuration outperformed the baseline.** The one-defect gap between arms is smaller than
the run-to-run variance we saw between pilots and means nothing at this sample size.

## Why, and why the result is not the harnesses' fault

The last column is the finding. **No skill was invoked in any of the 60 runs**, under any arm.
Verified two ways: the tool-use stream contains `Bash`, `Read` and `Write` calls and no `Skill`
call at all, and the same holds with the direct-work tools denied to force the model's hand.

The reason is that a single-file defect review does not route to a skill in any of these
configurations. vstack's review path is the `code-reviewer` **subagent**, reached through the
Task tool; gstack's is the `/review` **slash command**. Neither is a skill, and neither is
reached by asking a plain question about a file.

So this measured skills that were present and idle. It is a fair measurement of the question
"does having these skills installed change an ordinary review?" — the answer is no — and an
unfair measurement of "is one of these harnesses better at reviewing code", which it does not
address.

## What this does support

- The harness is real and reproducible: same prompt, same loading mechanism for every arm,
  ground truth with planted defects and decoys, scoring by line number rather than judgement.
- Every arm reports which skills it actually loaded, so an arm that silently failed to load its
  harness is marked INVALID instead of scored as a zero.
- On this task, installing 26 or 70 extra skills changed neither recall nor precision, and cost
  context on every session to do it.

## What it does not support

Any claim that one configuration reviews code better than another. Testing that fairly means
invoking each harness's actual review pathway — vstack's `code-reviewer` subagent against
gstack's `/review` command — which is a different and larger experiment.

## Two methodology failures worth publishing alongside the numbers

Both produced results that flattered this repository, and both were caught by checking rather
than by the numbers looking wrong.

1. **The first baseline was not authenticated.** It pointed `CLAUDE_CONFIG_DIR` at an empty
   directory, which removes credentials along with the configuration. Every baseline run
   returned "Not logged in", scored zero, and produced a 5/6-to-0/6 win for vstack over a CLI
   that had never logged in. The fix is `--setting-sources=project`, which drops user-scope
   config and keeps authentication.

2. **A shell bug scored an arm at zero.** Under `set -u`, bash 3.2 — which macOS ships — aborts
   on `"${arr[@]}"` when the array is empty. That killed every vstack run in one pilot and
   printed `0/6`, which reads like a catastrophic result rather than a broken loop.

A benchmark of your own project fails in your favour by default, and it fails quietly, because
a zero in the other column looks like a finding rather than a bug. The validity columns exist
because of these two.


---

# Review-pathway benchmark — each harness through its own `/review`

Reproduce:

```bash
GSTACK_DIR=/path/to/gstack tests/evals/run-pathways.sh --samples 1 --arms none,vstack,gstack
```

The first benchmark asked a plain question and found nothing, because neither harness reviews
through a skill. This one invokes each harness's actual front door — `/review` — against a git
diff, which is what both are written for. Fixtures become repos whose base commit is a
placeholder and whose working tree carries the defect.

## Run of 2026-08-21 — 8 fixtures, 1 sample per arm (superseded by n=5 below)

| arm | planted found | false positives | pathway entered |
|---|---|---|---|
| none (plain request) | 6 / 7 | 0 | n/a |
| vstack `/review` | **7 / 7** | 5 | 8/8 |
| gstack `/review` | 3 / 7 | 3 | 8/8 |

**This is one sample. It is a signal and not a result**, and the honest reading is a trade rather
than a win:

- vstack found every planted defect and was the noisiest, reporting five things that were not
  planted defects — including on the file with nothing wrong in it.
- gstack found fewer than half and still reported three.
- The plain request found six of seven with nothing spurious at all, which is the uncomfortable
  comparison: on this set, the unaided baseline had the best precision by a distance.

A reviewer that finds everything and cries wolf five times is not obviously better than one that
finds six of seven and never does. Which you prefer depends on whether a missed defect or an
ignored review costs you more. Nothing here settles that.

## Four ways this benchmark favoured its author before being fixed

Every one of these made vstack look better, none was caught by a number looking wrong, and each
is the reason the harness now carries the validity column it does.

1. **The baseline was not authenticated.** An empty `CLAUDE_CONFIG_DIR` removes credentials with
   the config, so every bare run returned "Not logged in" and scored zero — handing vstack 5/6
   against a CLI that had never logged in.
2. **A shell bug scored an arm zero.** Under `set -u`, bash 3.2 aborts on an empty array
   expansion, which killed every vstack run in one pilot and printed `0/6`.
3. **gstack was given only its `SKILL.md` files**, not the `specialists/` and checklist files its
   `/review` reads, so its pathway could not run and its arm scored zero.
4. **The validity check only recognised vstack's architecture.** It looked for a `Skill`/`Agent`
   delegation; vstack's `/review` delegates to a subagent and gstack's runs inline, so gstack
   failed a check that had quietly encoded one implementation style as the definition of
   working.

A benchmark of your own project fails in your favour by default, quietly, because a zero in the
other column reads as a finding rather than a bug. Anyone reproducing this should assume there
are more of these and look for them.

## What would make this publishable

n=1 across 8 fixtures is not enough to separate 7/7 from 6/7. The same harness at `--samples 5`
across all three arms is roughly 120 reviews and would give the recall and precision numbers
error bars. The fixtures are also small and Python-only; a defect class this set does not contain
is a defect class this says nothing about.


## RETRACTED — Run of 2026-08-21 — 8 fixtures, 5 samples per arm (120 reviews)

> **These numbers are unfair to both harnesses and are retracted.** The scoring counted a
> reviewer's nits, style notes and "no tests here" observations as false positives, while the
> baseline had been explicitly instructed not to make such observations at all. So the precision
> column compared a constrained prompt against unconstrained thorough reviews and scored the
> difference as error. The table is kept because deleting a wrong result you already published is
> worse than leaving it standing with the reason attached. A corrected run replaces it below.
>
> Caught by a reader refusing to believe the result, not by any check in this repository. The
> question "why would anyone use these harnesses then" was the right one to ask.

| arm | recall | false positives | precision |
|---|---|---|---|
| none (plain request) | **33/34 — 97.1%** | **0** | **100%** |
| vstack `/review` | 29/35 — 82.9% | 15 | 65.9% |
| gstack `/review` | 24/35 — 68.6% | 19 | 55.8% |

Both harness pathways engaged on all 40 of their runs, so both arms are valid.

**vstack beats gstack on both axes** — 14 points of recall and 10 points of precision. That
comparison is real, reproducible, and the numbers are above.

**Both lose badly to not using a harness at all.** A plain review request found 33 of 34 planted
defects and reported nothing spurious in 40 runs. Running either `/review` pathway found fewer
real defects and invented between 15 and 19 that were not there.

That is the result. Any use of the vstack-versus-gstack number that omits the first row is
dishonest, and trivially caught, because the harness that produced it is in this repository and
takes one command to re-run.

### The likely mechanism, stated as a hypothesis rather than a finding

Both `/review` pathways instruct a thorough, structured, multi-section review. On an
eight-line Python file with one planted defect, that structure appears to manufacture findings:
a review told to produce sections about security, performance and error handling will produce
them whether or not the file warrants any. The plain request has no such pressure and answers
the question asked.

If that is right, these harnesses would do better on the large diffs they were designed for than
on these fixtures, and this benchmark is unkind to them in a way worth saying out loud. Testing
that means running real repository-scale tasks, not eight-line files.

### Denominator note

The `none` arm shows 34 planted rather than 35: one of its 40 runs failed to return, so its
fixture's planted defect was not counted for that sample. It is reported as measured rather than
adjusted.

## A note on commit 3bbe618

Its message says "Stop tracking compiled Python". It also carries the SWE-bench PASS_TO_PASS
gate, which is a much more important change and deserved its own message: a `git add -A` in a
chained preflight command swept it in. Recorded here rather than rewritten, because the commit
is already pushed and an accurate note costs less than a force-push.

The change itself: the first SWE-bench run returned 0/4 for all three arms, which is the
signature of a broken harness rather than three identical failures. The pre-flight gate asked
"do the target tests fail?", and a completely broken environment satisfies that too — one flask
instance pulled a werkzeug too new for it, `from werkzeug.urls import url_quote` raised
ImportError, every test failed, the instance was marked usable, and all three arms scored zero
on a checkout where flask could not be imported.

PASS_TO_PASS exists for this. Those tests already pass before anyone touches the code, so if
they fail the environment is broken and any number from it measures the setup rather than the
agent. A usable instance now needs its target tests failing AND a sample of its known-good tests
passing.

That is the second time in this benchmark that three identical zeroes looked like a result about
the harnesses and was a result about my own scaffolding.

## SWE-bench Lite — three harness bugs before any number was real

The first three SWE-bench runs returned **0/4 for every arm**. None of those was a result.

1. **No pre-flight validity check.** The gate asked "do the target tests fail?", which a
   completely broken environment also satisfies. A flask instance pulled a werkzeug too new for
   it, `from werkzeug.urls import url_quote` raised ImportError, every test in the repository
   failed, the instance was marked usable, and all three arms scored zero on a checkout where
   flask could not be imported.

2. **PASS_TO_PASS was ignored.** Those tests already pass before anyone touches the code, so if
   they fail the environment is broken rather than the code. Using them is what turned "does it
   fail" into "does it fail for the right reason".

3. **Every edit was being denied.** In headless mode with no project settings the default
   permission mode prompts, there is nobody to answer, and the write silently does not happen.
   The agent called `Edit`, nothing changed on disk, and the benchmark measured "can this agent
   write a file" — no, identically, for all three arms — rather than "can it fix the bug".
   Re-running the same instance with `--permission-mode bypassPermissions` changed the source
   immediately.

Three identical zeroes have now been a bug in this harness three separate times, and each time
the arms agreed perfectly, which is what made it look like a finding. In a benchmark with
independent arms, **identical results are evidence of a common cause, and the harness is the
only thing all the arms share.**

Unresolved runs are now kept rather than deleted, because the moment you most need to look at
what the agent did is the moment everything scored zero.
