# Pre-registration: why `principle-build-the-lever` does not dispatch

Written before any run. Zero model calls have been spent on this document; every number below is
either a threshold chosen in advance or a fact read off a file in this repo.

`principle-build-the-lever` is the last skill in `tests/auto-trigger.sh` failing with no theory
standing. Measured 0/10 at `--max-turns 3` and 2/10 at `--max-turns 10` (`tests/auto-trigger.sh`,
the 2026-08-23 probe block, lines 119-144). Six mechanical hypotheses have been tested and died:
turn budget, transcript truncation, `skillOverrides`, fixture mismatch, routing-block structure,
description wording. The last of those is the expensive one — the description rewrite that moved
`principle-type-system-discipline` from 1/10 to 9/10 was applied here with the identical method and
did not move it (`CHANGELOG.md`, 1.38.0).

This registers hypotheses 7 through 11, their arms, and the thresholds that decide each, before any
dispatch-rate call is made. Stage 0 (the instrument check) has since run; its result is recorded
below, in the section it was registered in, with no threshold altered after the fact.

## What was checked at zero cost, and came back clean

Recorded so nobody re-spends allowance on them:

- **No override.** `principle-build-the-lever` has no entry in `skillOverrides` in either
  `claude/settings.json` or the live `~/.claude/settings.json`. Confirms hypothesis 3's death by
  direct read rather than by inference.
- **No listing truncation from the per-description cap.** `skillListingMaxDescChars` is 200. The
  longest of the 28 descriptions is `blast-radius` at 198; `principle-build-the-lever` is 171.
  Nothing is cut by that cap.
- **The installed skill is the repo's skill.** `~/.claude/skills/principle-build-the-lever/SKILL.md`
  is byte-identical to `claude/skills/`. No `disable-model-invocation` anywhere in
  `~/.claude/skills/`.
- **The stale plugin cache is inert.** A copy exists at
  `~/.claude/plugins/cache/vstack/vstack/1.0.0/skills/principle-build-the-lever/SKILL.md`, but
  `~/.claude/plugins/installed_plugins.json` lists only `claude-mem` and `typescript-lsp`, so no
  second copy of this skill reaches the listing. Its description is byte-identical regardless.

## Three reasons to hold the 0-2/10 figure loosely (none of them overturns it)

1. **The numbers are unreplicable.** They come from a probe script deliberately not committed —
   `tests/auto-trigger.sh` says so at line 116 ("not reproduced here as code") and line 133 ("this
   was passed directly in a throwaway probe script"). No per-run output survives. The rate is
   probably right; it cannot be audited, and every arm below therefore re-derives its own baseline
   inside the same run rather than comparing against a historical number.
2. **The miss mode has never been recorded since the `principle-` prefix fix.** The probe counted
   hits, not what fired. The only "nothing fires at all, `(none)` in every attempt" claim is
   `CHANGELOG.md` 1.34.0 — written before 1.35.0 fixed eight routing entries that named skills which
   could not resolve. It describes a configuration that no longer exists. **Whether a sibling skill
   is winning this prompt today is unknown and has never been looked at**, and looking costs nothing
   extra: it is a logging requirement, not an arm.
3. **The fixture prompt is 119 characters, one below a behavioural cliff.**
   `claude/hooks/inject-session-context.sh` injects the GRILL nudge on the first prompt of a session
   at `[ "$_n" -ge 120 ]`. At 119 this case gets no nudge; at 120 it would. `CHANGELOG.md` 1.34.0
   records this exact case as the one that "passed before and failed after" the grill change. Any
   prior comparison spanning that change is confounded, and any arm that reworded the prompt past
   120 characters would silently change the injected context. **Every arm below is held under 120.**

## The hypotheses

Ranked by expected information, strongest first. Each carries the result that kills it.

### H11 — the harness denies the affordance the skill is about (strongest)

`run_case` passes `--disallowedTools "Write,Edit,MultiEdit,NotebookEdit,Bash,Agent"`. Every other
skill under test is advice about something in the prompt. This one instructs the model to produce an
artifact — "Applying this principle produces a file" — and the harness has removed every tool that
can produce one. The `Skill` call is upstream of the denial and is not mechanically blocked, so this
is a claim about the model's feasibility reasoning, not about plumbing. If true, the suite
systematically under-measures every skill whose output is an artifact, and every rate this repo has
published from `auto-trigger.sh` is depressed by an unknown amount for an unknown subset of cases.

Ranked first on the coordinator's correction, and the correction is right: a hypothesis that voids
the instrument goes before any hypothesis about the subject, because every other arm's number is
conditional on this one being false. A5 therefore runs in the first tranche alongside A0/A1/A2/A3,
not in an optional tail.

**Killed by:** arm A5 — the identical prompt with `Write` permitted — firing at k <= 2/10.

### H7 — the trigger is response-side, not prompt-side

Every skill that dispatches reliably here has a trigger that is a property of an object the user
names: a struct that can hold an invalid combination, a `try/except`, a cron job, a validation
boundary, a stack of PRs. `principle-build-the-lever`'s trigger is a property of the method the
responder has not chosen yet — "you are about to do this by hand instead of building the tool."
Nothing in the input is the trigger; the trigger is a counterfactual about the model's own
forthcoming plan. A dispatcher scoring descriptions against a prompt has nothing to score.

This repo has already diagnosed and acted on one skill of exactly this class. `CHANGELOG.md` 1.37.0:
`principle-prove-it-works` "scored 0/10 on its own fixture prompt because its trigger -- 'apply
before declaring any task or fix done' -- is a condition on the assistant's forthcoming speech act,
not on anything in the user's prompt a skill matcher can score against." That check was moved into
the Stop hook. Two skills, same structural property, 0/10 and 0-2/10.

H7 is the strongest hypothesis about the skill itself, as opposed to about the instrument. It is
the only one that explains the asymmetry that cost the most
to discover: why the description rewrite fixed `type-system-discipline` and not this one. A
description rewrite cannot supply evidence the input does not contain.

**Killed by:** arm A3 firing at k <= 2/10. If making the method choice the explicit object of the
request does not move dispatch, the locus is not the constraint.

### H8 — the fixture prompt contains no request

`"Every file in modules/ needs the same license header pasted at the top. I'll go through and add it
to each one by hand."` The user has announced they are doing the work themselves. Nothing is asked
of the model. Across all 28 auto-trigger cases in `tests/auto-trigger.sh` at pre-registration time,
exactly two prompts are declaratives
with no imperative and no question directed at the model — this one, and
`prove-it-works-declare-done` (`"I fixed the crash in fetch_stats by adding a retry, and the code
compiles cleanly -- this task is done."`). Those are also exactly the two cases measured at 0/10.
2 for 2 on 28 is suggestive at n=2 and nothing more, which is why it is an arm and not a conclusion.

H8 and H7 are confounded in the historical data: `prove-it-works` is both declarative-mood and
response-side-locus, so the two-case correlation cannot distinguish them. Arms A2 and A3 separate
them, and neither can be dropped without leaving the other unfalsifiable.

**Killed by:** arm A2 firing at k <= 2/10.

### H9 — the description's own gate excludes the fixture

The description reads "Apply to non-trivial edits, migrations, analyses, or checks — **not just bulk
work**", and the body sets the bar as "Skip it only when the task is genuinely trivial." The fixture
is `setup_bulk`: eight one-line `.js` files, each receiving an identical header paste. That is bulk,
and it is trivial. The routing line says something different — "Repeated manual edits or checks ->
principle-build-the-lever" — so the repo carries two contradictory trigger definitions, and the
fixture matches only the one in the hook.

Under H9 the 0/10 is the model correctly applying the description it was given, and the defect is
that the test asserts a behaviour the skill disclaims. Note the independently-built fixture set at
`~/vstack-dispatch/fixtures.jsonl` chose a very different scale for this same skill: `pos-15`,
`"I need to rename this prop across about 60 components."`

**Killed by:** arm A4 — the identical prompt against a 60-file fixture — firing at k <= 2/10.

### H10 — a sibling absorbs the prompt (costs nothing to answer)

The PRINCIPLES routing line assigns "Sweeps, migrations, stacked commits" to
`principle-sequence-verifiable-units` in the sentence immediately before it assigns "Repeated manual
edits or checks" to `principle-build-the-lever`, while build-the-lever's own description claims
"migrations" too. `principle-encode-lessons-in-structure` claims "or script". The fixture is a
sweep. `sequence-verifiable-units` passes on attempt 1 in both historical runs.

This needs no arm. It is answered by logging the **full fired-skill set** on every run of A1 instead
of a hit/miss boolean — the thing the throwaway probe did not do. If a sibling appears in A1's
misses, H10 is the finding and H7/H8/H9 are moot.

**Killed by:** A1's 10 transcripts containing zero `Skill` tool_use blocks naming any other skill.

## What is measured

One **sample** is one non-retrying `claude -p` invocation of a fixed prompt against a fixed fixture,
per `tests/auto-trigger.sh`'s own definition at lines 96-102: not one pass through the `ATTEMPTS`
loop, which stops at the first hit and measures "succeeded within 3 tries" rather than a rate.

Per sample, record: every `Skill` tool_use name in the stream (not a boolean), **every `ToolSearch`
call and its result** (Stage 0 found this build defers tools behind it and the suite does not deny
it), the top-level `result.subtype`, `num_turns`, the prompt's character count, and any
`fence_violations` output.
Per arm, report raw **k/n**. No percentages and no point estimates at n=10 — the interval does not
support them.

## The arms

All arms: `--model sonnet`, `--max-turns 10`, `--disallowedTools` as `run_case` sets it except where
noted, per-case timeout 120s, fresh `mktemp -d` workdir per sample, grill state held constant (every
prompt under 120 characters, count logged per sample).

`--max-turns 10` and not the case's `case_max_turns()` value of 3: turn starvation is already ruled
out for this case, and running at 10 keeps it from re-entering as a confound. A1 at 10 is directly
comparable to the historical 2/10, which was also taken at 10.

| arm | prompt | fixture | tools | tests |
|---|---|---|---|---|
| **A0** control | `root-cause-guard` verbatim, `--max-turns 3` | `setup_flaky` | default | the harness |
| **A1** baseline | shipped `build-the-lever-headers` verbatim (119 ch) | `setup_bulk` (8 files) | default | re-derives the rate; carries H10 |
| **A2** imperative | `Add the same license header to the top of every file in modules/.` (65 ch) | `setup_bulk` | default | H8 |
| **A3** method-question | `What's the best way to get the same license header onto every file in modules/?` (79 ch) | `setup_bulk` | default | H7 |
| **A4** scale | A1's prompt, byte-identical | `setup_bulk` at 60 files | default | H9 |
| **A5** affordance | A1's prompt, byte-identical | `setup_bulk` | `Write` permitted | H11 |

A4 and A5 change exactly one variable each and hold the prompt bytes fixed, so they inherit A1's
grill state by construction. A2 and A3 change the prompt and are both well under 120.

A2 deliberately keeps the response-side locus intact — it is still the model's own choice whether to
paste eight headers by hand or script it — so it moves mood and agency only. A3 makes the method
choice the object of the request without naming any of the skill's nouns (no "script", "codemod",
"tool", "automate"), so a hit there is not the lexical-overlap effect that hypothesis 6 already
tested and buried.

## Prediction, in advance

H7. A3 fires materially above A1; A2 does not. If that is what comes back, the conclusion is that
this skill's trigger is not matchable at dispatch time from a prompt of the shipped fixture's shape,
and the fix is the shape `prove-it-works` got — a hook at the moment the condition is actually
about — not further description surgery.

**A null result counts.** If A2, A3, A4 and A5 all land within 2 of A1 while A0 comes back clean,
that is published as "five hypotheses tested, five dead, and the instrument is not the cause," not
reworked into whichever arm happened to be highest.

## Thresholds, fixed now

Two-sided 95% Wilson at n=10: `0/10 = [0.00, 0.28]`, `2/10 = [0.06, 0.51]`, `7/10 = [0.40, 0.89]`,
`8/10 = [0.49, 0.94]`, `9/10 = [0.60, 0.98]`.

For each of A2, A3, A4, A5:

- **CONFIRM** at **k >= 8/10**. The interval's lower bound (0.49) clears the upper bound of a 0/10
  baseline (0.28) and sits at the edge of a 2/10 baseline's (0.51). This is the coarse question n=10
  actually supports: "never" versus "fires at least about half the time."
- **FALSIFY** at **k <= 2/10**. Indistinguishable from the shipped baseline. The hypothesis is dead
  and is written up as dead.
- **INDETERMINATE** at **k = 3..7**. Reported as indeterminate and as nothing else. At n=10 a 5/10
  is `[0.24, 0.76]` and cannot be called a partial effect without inventing precision. An
  indeterminate arm earns exactly one escalation: that arm alone re-run at n=33 (+23 calls), where
  `30/33 = [0.76, 0.97]` and `20/33 = [0.44, 0.75]` do separate. Escalation of more than one arm
  needs a fresh allowance decision.

For A0 the threshold is **k >= 7/10**, its historical rate less its historical miss. Below that, see
invalidation.

n=10 supports: never-versus-half, and each arm against A1. n=10 does **not** support: ranking two
arms that both confirm, or any claim that A3 at 8/10 beats A2 at 6/10.

## What would invalidate the run

- **A0 below 7/10.** The harness is the finding; every other number in the run is void. This is
  `tests/README.md`'s standing control rule, not a new one.
- More than 2 samples in any arm terminating `error_max_turns`. That arm is turn-starved, void, and
  re-runs at a higher budget before it is read.
- Any `fence_violations` output on any sample outside A5 (where `Write` into the temp workdir is the
  manipulation and is expected). A breach means the environment was not the one registered.
- Identical per-sample outcome vectors across two arms — the harness collapsed them.
- Any arm prompt logging at >= 120 characters. The grill nudge would then differ across arms and the
  comparison is confounded.
- The vstack SessionStart hook absent from the stream's injected context, or the routing block not
  reaching the model. The whole design assumes the routing line is present and read.
- `Skill` appearing in any arm's `--disallowedTools`. Stage 0 proved that empties the listing, so
  such an arm measures nothing.
- More than 2 samples in any arm spending a turn on `ToolSearch`. The arm is then partly a
  measurement of tool discovery and is re-run with `ToolSearch` denied.

## Stage 0 — RUN 2026-08-23. Result: CLEAN. Stage 1 is not cancelled.

Registered question: does `principle-build-the-lever`'s description survive the skill listing at
`MODEL=sonnet`, the model `tests/auto-trigger.sh` actually pins, given that
`docs/how-skills-fire.md` measured a 2,335-token listing against a 16,000-token budget on a
**1M-context** model and `skillListingBudgetFraction` is a fraction of the *actual* window?

**Answer: yes, verbatim and untruncated, 3/3.** Both the subject and an internal control came back
byte-identical to their `SKILL.md` frontmatter — `principle-fix-root-causes` at 164/164 characters,
`principle-build-the-lever` at 171/171 — on three independent samples, `subtype=success`,
`num_turns=1`, zero tool calls in every one. The sonnet-window truncation worry is dead. The six
hypotheses that came before this document were not tested against text the model never saw.

It took three probes, and the two dead ones are the useful part.

**Probe defect 1, and a mechanism fact worth more than the probe.** The registered prompt was first
run with `Skill` in `--disallowedTools` — the reasoning being that a model able to call the Skill
tool would load `SKILL.md` and quote the file rather than the listing. All 3 samples then reported
the description **absent**, one of them offering the hook's routing line as the only text it had for
that skill. That result is an artifact, and reporting it as a finding would have been the exact
failure this file exists to prevent. **The skill listing rides on the `Skill` tool: deny `Skill` and
the listing is not in context at all.** Re-run with `Skill` available and `Read`/`Grep`/`Glob`/`Bash`
denied instead — so the answer still cannot come from the filesystem — the descriptions are present
and exact. Consequence for this repo: `--disallowedTools` in `auto-trigger.sh` must never gain
`Skill`, and any future experiment that denies it is measuring an empty listing.

**Probe defect 2, and a live unrecorded turn sink in the instrument.** The first probe ran at
`--max-turns 2` and returned `error_max_turns` with no text on all 3 samples. The transcripts show
why: the model spent both turns calling **`ToolSearch`**, which returned `No matching deferred tools
found` and a `tool_reference` to a `DesignSync` tool. **This build has a deferred-tool registry, and
`ToolSearch` is absent from `auto-trigger.sh`'s `--disallowedTools` list.** Two turns lost to tool
discovery is the entire budget of a case running at the suite default of 3. Nothing in the repo
records this path, and it belongs to H11's class — an instrument that consumes the budget it is
measuring. It is not evidence that any case has actually lost turns this way; it is evidence that
nobody has looked. Stage 1 logs `ToolSearch` per sample and can answer it at zero marginal cost.

**Cost, stated honestly: 9 calls against an authorised 3.** Three on the mis-parameterised probe,
three on the `Skill`-denied probe, three on the run that answered the question. The overspend was
mine and is not backdated into the design; the registered prompt and n=3 were correct, the tool
denials around them were not.

## Sample size and cost

Every number here is a `claude -p` sonnet invocation, serial, ~15-30s each.

**Stage 0 — instrument. SPENT: 9 calls, registered as 3. Result above: CLEAN.** `"Reply with the exact description text you have for the skill
named principle-build-the-lever, verbatim, then stop."` at n=3, `--model sonnet`. This is the one
check the repo has never run: `docs/how-skills-fire.md` measures the listing at 2,335 tokens against
"a 16,000 token budget on a 1M context" — but `tests/auto-trigger.sh` pins `MODEL="sonnet"`, and
`skillListingBudgetFraction` is a fraction of the *actual* window. The doc's reassuring "15 percent
of its budget" is measured against a model the suite does not run. If the description comes back
absent or truncated, **that is the answer, Stage 1 is cancelled**, and the finding is that six
hypotheses were tested against a description the model never saw in full.

**Stage 1 — 60 calls.** Six arms at n=10. Minimum viable subset if allowance is tight: **A0, A1, A2,
A3 = 40 calls**, which answers the two top-ranked hypotheses and settles H10 for free from A1's logs,
and defers H9 and H11.

**Stage 2 — conditional, 23 calls.** One indeterminate arm re-run at n=33. Not authorised in advance.

**Stage 1 as authorised: the full 63-call design less Stage 0, i.e. 60 calls, six arms at n=10, A5 in
the first tranche rather than the tail.** Not reduced to 43: H11 is now ranked first and A5 is the
arm that tests it. A0 is not trimmed — a run without its control cannot be reported.

**Gate: Stage 1 waits for v1.40.0 to land and install.** `claude/hooks/skill-mandate.sh` is under
edit by MEESEEKS as this is written, so the repo tree and the installed tree differ. Stage 1 is a
dispatch-rate measurement and hook drift has silently voided three measurements in this repo
already. Stage 0 was run through the drift because it is drift-insensitive: the skill listing comes
from the CLI, not from our hooks, and the two probes that failed did so for reasons internal to the
probe.
