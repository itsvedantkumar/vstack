# What the literature changed about vstack, and what it deliberately did not

Written 2026-08-22, immediately after
[`harness-value-literature-2026-08.md`](harness-value-literature-2026-08.md). True when written,
not maintained.

This is the translation layer. The survey says what the field measured. This says what we did
about it, and, more usefully, what we refused to do about it and why. The refusals are the part
worth reading, because the strongest temptation after a research pass is to over-read it.

## The one-line version

vstack was already built around the part of the evidence that holds. The gate, the destructive-op
guard, the refusal to claim output quality: all of that is the behavioural case, which is the case
the literature supports. What needed fixing was smaller than expected and mostly about honesty in
the README and dead references in two skills.

## Changed

### Dangling `superpowers:*` references in two skills

`executing-plans` and `writing-plans` each carried a header caveat saying sibling skills are not
vendored, then issued `**REQUIRED SUB-SKILL:** Use superpowers:<name>` in the body for skills that
are not installed. Verified absent: nothing in `~/.claude/skills` matches and no superpowers plugin
is present.

Eight such references, now zero outside the header caveat. Where the target exists here the prefix
was dropped (`superpowers:writing-plans` becomes `writing-plans`). Where it does not, the directive
became plain prose describing the work.

**Why this mattered more than it looks.** The wasted turn is the small cost. The real one is that
an agent reading `REQUIRED` and finding nothing there learns that `REQUIRED` is soft, which
devalues every mandatory instruction in the rest of the set. `REQUIRED` should only ever point at
something that exists. Evidence link: this is failure mode (a), exhortation with nothing behind it,
and TDAD's control arm is the measured case where prose alone was net-negative.

### README now states the context cost accurately

It said "about 3.6 KB" per session. Measured: **4,415 B floor** (CLAUDE.md 1,472 + SessionStart
baseline 2,943) **plus 305 B every prompt after that**. So 10.5 KB at 20 turns, 19.7 KB at 50. The
per-turn growth was not stated at all, which is the part that compounds.

Evidence link: cost is the best-measured harness effect in the literature and the one thing harness
authors reliably publish about themselves, always version-to-version and never against a bare
agent. A README that understates its own always-on cost is doing the same thing in miniature.

Reproduce:

```
echo '{"hook_event_name":"UserPromptSubmit"}' | claude/hooks/inject-session-context.sh | wc -c
```

A note on how that number was nearly wrong. The first measurement returned 2,943 B for the
per-prompt digest, a 9x overstatement, because the test JSON omitted `hook_event_name` and the hook
defaults to `SessionStart`. That exact defaulting bug is documented at line 13 of the hook as
something already found and fixed in production. It is a good reminder that measuring your own
instrumentation wrong is as easy as measuring anything else wrong.

### README claims section now cites the field rather than only confessing

It already refused the output-quality claim, which was right and stays. It now adds what the survey
found: nobody else has that measurement either, the nearest full-bundle-against-bare test returned
+2.2 points at a 45.6% baseline for 40% more tokens, and the config layer's measured wins are
behavioural. This converts an absence of evidence into a citation.

## Deliberately not changed

An adversarial review recommended cutting eleven skills, including all eight `principle-*`. I
declined most of it. The reasoning matters more than the verdict.

**"Software engineering is the weakest domain for skills" does not mean cut them.** It is +11.6
points, the second-lowest of eight domains. A gain. Reading a smaller gain as a loss is precisely
the inversion this project keeps having to correct in its own benchmarks.

**"More skills measured worse" does not transfer to a 28-skill library.** SkillsBench varied how
many skills were *mounted per task* (1, 2-3, 4+). vstack varies how many are *listed for
description matching*. Different variable. Treating them as the same would be exactly the
architectural-evidence-applied-to-the-config-layer error the survey spends its first section
warning about. The honest statement is that the realistic case, roughly 28 overlapping descriptions
competing, **is unmeasured by anyone**, including us.

**`principle-prove-it-works` was flagged as pure exhortation. It is not.** It ends by telling the
agent that prose reminders get skipped under pressure and to put the check in an executable
`.claude/verify.sh`, which the `verify-gate.sh` Stop hook runs and blocks on. That is the
retrieval-beats-exhortation lesson already encoded, before we knew there was evidence for it. Left
alone.

**`impeccable` and `brainstorming` reference unvendored scripts, but say so loudly.** Both carry
explicit "the file does not exist, the command will fail, never run one, do the work directly"
warnings. That is handled honestly, unlike the `REQUIRED SUB-SKILL` case. Left alone.

The general rule this produced: **a finding licenses a change only when the thing it measured is
the thing we have.** Most of the review's cut list failed that test.

## Should be measured, and is not yet

Two experiments. Neither has been run by anyone, publicly, and vstack is unusually well positioned
for both because it already has the mechanism.

### 1. False completion with the Stop-hook gate on versus off

**Nobody has measured this.** Section 8 of the survey establishes that no benchmark anywhere scores
"the agent asserted the task is complete while the test suite is red" on a coding repo. The nearest
work measures judges rather than scaffolds, or runs on a benchmark that forces patch submission so
a 100% submit rate is a harness artifact.

vstack has a pre-registered fixture, a recorded predicted direction, and a gate that can block. The
blocker is a known bug: `tests/evals/false-done/run.sh` truncates `RUNLOG` per invocation, which has
**already destroyed data**. `.audit/run/falsedone-1787408854.tsv` retains 9 vstack rows; the 12-run
`none` baseline was overwritten and has no surviving raw rows.

Fix is append mode, and per the survey's own preference for mechanism over instruction, a shared
`open_runlog()` helper rather than three patched call sites, so there is one place to put an
append-mode assertion that can fail.

Arms: `none`, `vstack` with the gate armed, `vstack` with `VSTACK_NO_GATE=1`. That third arm is the
one that isolates the gate from everything else vstack does, and it is the number nobody has.

### 2. Whether the right skill fires from a 28-skill library

SkillsBench measured 68.2% invocation for Claude Code with **one** relevant skill mounted and **no
distractors**. The realistic case is unmeasured. We have 28 descriptions, 3,959 bytes of them, and
one confirmed near-collision pair (`create-verification-skill` and `maintain-verification-skill`).

The `skill-mandate.sh` Stop hook already knows which skills fired. Logging fired-versus-expected
per turn against a fixture set of prompts with known correct skills would produce a
precision/recall number for description matching at realistic library size. That is a publishable
first and it costs one hook change plus a fixture file.

## Ranked, if only some of this gets done

1. Fix the `RUNLOG` truncation. It is actively destroying data every run.
2. Run the three-arm false-completion experiment. Highest value per unit of effort, and nobody else
   has the number.
3. Instrument skill firing. Second-highest, same reason.
4. Everything else here is already done.

## Handoffs at time of writing

`tests/evals/*` and `.claude/verify.sh` were being worked by other sessions when this was written,
so items 1 and 2 were handed to the session holding them rather than edited here. `docs/research/`,
`README.md` and `claude/skills/` were uncontended and are what this document's "Changed" section
covers.
